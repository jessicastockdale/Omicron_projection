## This is an adaptation of BC_projection.R, which explores 3 ways to define the uncertainty ribbons in model incidence plot

# Lines 1-191 are exactly the same as BC_projection, except we make sure to output the hessian from optim. 



########## Source required files
source("analysis-new/functions.R")
source("analysis-new/likelihood_func.R")
#run BC_data.R line by line (if possible) :sometimes case data are incomplete, with 0's  and NA's 
source("analysis-new/BC_data.R") 


########## Data set up
forecasts_days <- 30 
intro_date <-  ymd("2021-11-20")
stop_date <- ymd("2022-01-30")  
#import data 
dat = readRDS("data/BC-dat.rds")
#include Omicron wave only
dat <- dat %>% filter(date >= intro_date &  date <= stop_date)
dat_omic <- dat
dat_omic <- filter(dat_omic, date >= intro_date) %>% dplyr::select(c("day", "value", "date"))
dat_omic$day <- 1:nrow(dat_omic)



########## Test_prop set up
#-------EB: test_prop now has dates and this ensures it starts at the right date 

#tp_approx <- tp_approx_fit(mytest_BC=mytest_BC, dat= dat_omic, forecasts_days=forecasts_days,
#                          howlow = 0.2, 

tp_approx <- tp_approx_fit(mytest=mytest_BC, dat= dat_omic, 
                           forecasts_days=forecasts_days, howlow = 0.1, 
                           slope = 0.2,  midpoint=45, intro_date= intro_date, stop_date=stop_date)
plot_fit <- tp_approx[1]
plot_fit 

# test_prop for fit and projection 
test_prop_proj <- data.frame(tp_approx[2])

#subset for fitting alone (length of data)
test_prop <- test_prop_proj$tp[1:length(dat_omic$day)] #or set forecasts_days to 0 in tp_approx_fit() above 


# ---- cc's function to modify test_prop ----
# start lowering it even more when it hits the startlower value
# lower it by a linear function , ending at endfraction of its final value
# ie if endfraction is 0.5, the final value after adjustment is 1/2 the value before
# adjustment 
modifytp = function(startlower=0.6, endfraction=0.55, test_prop) {
  tt = min(which(test_prop < startlower))
  myline = seq(1, endfraction, length.out = length(test_prop)-tt)
  myfrac = c(rep(1, tt), myline)
  return(test_prop*myfrac)
}

mytp = modifytp(startlower = 0.5, endfraction = 0.35, test_prop)
ggplot(data = data.frame(date = intro_date+1:length(test_prop), 
                         test_prop=test_prop, 
                         mytp = mytp), 
       aes(x=date, y=test_prop))+geom_line() + 
  geom_line(aes(x=date, y=mytp), color="blue") + ylim(c(0,1))

test_prop = mytp 
# NOTE leaving as is for now 


# --- cc's function to append values to test_prop to stop getting length errors ----
# see changes to how test_prop is used in the likelihood functions
# basically if test_prop does not start at the same date as the simulation, you are hooped 
extendtp <- function(n=100, test_prop=test_prop){
  return(c(test_prop, rep(test_prop[length(test_prop)], n-length(test_prop))))
}


########## Parameters set up 
#set values to generate initial conditions with make_init()
N=5.07e6
N_pop=N
vaxlevel_in = 0.88 # portion of the pop vaccinated at start time 
port_wane_in = 0.04 # portion boosted at start tie 
past_infection_in = 0.18  #increased this from 0.1 to 0.18 # total in R at start time
incres_in = 470 # resident strain (delta) incidence at start 
incmut_in = 6# new (omicron) inc at stat 
simu_size = 1e5 # number of times to resample the negative binom (for ribbons)
forecasts_days =30 # how long to forecast for 
times = 1:nrow(dat_omic)

#declaring  parameters 
intv_date <-  ymd("2022-02-10")
eff_date <-   ymd("2021-12-31")  # intervention date 
parameters <-         c(sigma=1/3, # incubation period (days) 
                        gamma=1/5, #recovery rate 
                        nu =0.007, #vax rate: 0.7% per day 
                        mu=1/(82*365), # 1/life expectancy 
                        w1= 1/(0.5*365),# waning rate from R to S 
                        w2= 1/(0.5*365), # waning rate from Rv to V 
                        w3= 1/(0.5*365),# waning rate Rw to W 
                        ve=1, # I think this should be 1. it is not really efficacy  
                        beta_r=0.6, #transmission rate 
                        beta_m=1, #transmission rate 
                        epsilon_r = (1-0.8), # % this should be 1-ve 
                        epsilon_m = 1-0.3, # % 1-ve omicron 
                        b= 0.006, # booster rate
                        beff = 0.7, # booster efficacy
                        wf=0.05, # protection for newly recovered
                        N=5e6,
                        stngcy= 0.4, #(*%(reduction)) strength of intervention (reduction in beta's)
                        eff_t = as.numeric(eff_date - intro_date),
                        relx_level = 0,
                        rlx_t = as.numeric(intv_date - intro_date),
                        p = 0.5, #negative binomial mean
                        theta = 0.1 #negative binomial dispersion
                        
)
init <- make_init()   #generate initial states




########## Run the model and compare the model to the data
#          (i.e. without fitting anything)
times <- 1:(nrow(dat_omic) + forecasts_days)
outtest <- as.data.frame(deSolve::ode(y=init,time=times,func= sveirs,
                                      parms=parameters)) 
inctest = get_total_incidence(outtest, parameters = parameters) # has p but not test_prop! 
inctest$date = intro_date-1+1:nrow(inctest)
thisvec=extendtp(nrow(inctest), test_prop)
inctest$inc_reported = inctest$inc_tot*thisvec

# sanity check - should have delta in a decline of about 2% /day (-0.02) and around 
# a 0.2 to 0.25 difference between the two, so omicron at about 0.2 
get_growth_rate(outtest, startoffset = 2, duration = 10)

ggplot(data =inctest, aes(x=date, y = inc_reported))+geom_line() +
  geom_line(aes(x=date, y= inc_res), color = "blue") +
  geom_line(aes(x=date, y= inc_mut), color = "red") +
  geom_point(data = dat, aes(x=date, y=cases), alpha=0.5) +
  ylim(c(0,5000)) + xlim(c(ymd("2021-11-20"), ymd("2022-02-28")))



########## Fit the model
# fitting any subset of parameters. 
# REMEMBER: params must be named and need to ensure there's an upper and lower bound for each in optim
guess <- c( beta_m=1, stngcy=0.4,beta_r=0.6) 
# cc: i learned that the same likelihood can be achieved with higher efficacy 
# (lower eps_m) and higher beta_m, vs the other way around. good! 
# however, this will all depend on the (somewhat strong) assumption re: test_prop
# and the modification of test_prop 

#the parameters are constrained  accordingly (lower and upper)
fit_BC <- optim(fn=func_loglik,  par=guess, lower=c(0,0,0), 
                upper = c(Inf,1,Inf), method = "L-BFGS-B", parameters = parameters,
                test_prop=test_prop, dat_omic=dat_omic, hessian=T)
# check the values:
fit_BC
func_loglik(fit_BC$par, test_prop, dat_omic,parameters) 

#this catches estimated parameter values from MLE , and adds them to 'parameters' structure
parameters[names(guess)] <- fit_BC$par
plot.loglik.info(parameters, 1:nrow(dat_omic), test_prop,init) # cc's sanity check plot 
gg = simple_prev_plot(parameters, numdays = 190, mode = "both", init); gg  # cc's simple prevalence plot 



########## Check fit: make prediction and projection with estimated parameters
times <- 1:(nrow(dat_omic) + forecasts_days)
out_BC <- as.data.frame(deSolve::ode(y=init,time=times,func= sveirs,
                                     parms=parameters)) 
#with test_prop 
incidence_BC =  parameters[["p"]]*parameters[["sigma"]]*(out_BC$Er + out_BC$Erv + out_BC$Erw +
                                                           out_BC$Em + out_BC$Emv +
                                                           out_BC$Emw)*extendtp(nrow(out_BC), test_prop)

plot(1:nrow(dat_omic), incidence_BC[1:nrow(dat_omic)])
uncert_bound_BC = raply(simu_size,rnbinom(n=length(incidence_BC),
                                          mu=incidence_BC,
                                          size=1/parameters[["theta"]]))

project_dat_BC =  as.data.frame(aaply(uncert_bound_BC 
                                      ,2,quantile,na.rm=TRUE,probs=c(0.025,0.5,0.975))) %>% 
  mutate(date=seq.Date(ymd(intro_date),
                       ymd(intro_date)-1+length(times), 1))
#add dat to data for plotting 

dat_reported <- dat_omic  %>% mutate(date=seq.Date(ymd(intro_date),
                                                   ymd(intro_date)-1+length(dat_omic$day), 1))

p2 <- ggplot() + geom_line(data=project_dat_BC,aes(x=date,y=`50%`), col="green",size=1.5,alpha=0.4) +
  geom_ribbon(data=project_dat_BC,aes(x=date,ymin=`2.5%`,ymax=`97.5%`),fill='darkgreen',alpha=0.1, size = 1.5)+
  geom_point(data=dat_reported,aes(x=date, y=value),color='grey48', alpha=0.8, size = 1.5)
p2





### NEW PART: GET ALTERNATE RIBBONS BY RESAMPLING MLES


library(MASS)
times <- 1:(nrow(dat_omic) + forecasts_days)
# Sample from asymptotic distribution of MLEs, 100 times
resampled <- mvrnorm(n = 100, mu = fit_BC$par, Sigma = (1/nrow(dat_omic))*solve(fit_BC$hessian)) # don't need -ve because we MINimised NEGloglike

resample_incidence <- function(x, parameters){
  # For each set of resampled MLEs, do a model simulation and output the daily incident reported cases
  parameters[names(guess)] <- x
  out_samp <- as.data.frame(deSolve::ode(y=init,time=times,func=sveirs,
                                       parms=parameters)) 
  incidence_samp =  parameters[["p"]]*parameters[["sigma"]]*(out_samp$Er + out_samp$Erv + out_samp$Erw +
                                                             out_samp$Em + out_samp$Emv +
                                                             out_samp$Emw)*extendtp(nrow(out_samp), test_prop)
}
incidence_resampled <- apply(resampled, 1, resample_incidence, parameters=parameters)

# Get the quantiles of the distribution of simulated cases under resampled MLEs (and add dates)
quantiles_resampled =  as.data.frame(aaply(incidence_resampled 
                                      ,1,quantile,na.rm=TRUE,probs=c(0.025,0.5,0.975))) %>% 
  mutate(date=seq.Date(ymd(intro_date),
                       ymd(intro_date)-1+length(times), 1))
 

dat_reported <- dat_omic  %>% mutate(date=seq.Date(ymd(intro_date),
                                                   ymd(intro_date)-1+length(dat_omic$day), 1))

# Plot the result: 
p1 <- ggplot() + geom_line(data=quantiles_resampled ,aes(x=date,y=`50%`), col="green",size=1.5,alpha=0.4) +
  geom_ribbon(data=quantiles_resampled ,aes(x=date,ymin=`2.5%`,ymax=`97.5%`),fill='darkgreen',alpha=0.1, size = 1.5)+
  geom_point(data=dat_reported,aes(x=date, y=value),color='grey48', alpha=0.8, size = 1.5)
p1
# Really small uncertainty because the variance of the MLE distribution is tiny (lh very peaked - great!)


## Third ribbon calculation approach: add nbinom resampling ON TOP OF mle resampling 
bound_mlesample<-lapply(incidence_resampled,  function(x){raply(simu_size/100,rnbinom(n=length(x),
                                                                 mu=x,
                                                                 size=1/parameters[["theta"]]))}, simplify=FALSE)
bound_mlesample <- do.call(rbind, bound_mlesample)
# For each of the 100 MLE resamples in 'incidence_resampled', we do the nbinom resampling simu_size/100 times

# Then we calculate the quantiles of the entire set of samples
project_mlesample =  as.data.frame(aaply(bound_mlesample 
                                      ,2,quantile,na.rm=TRUE,probs=c(0.025,0.5,0.975))) %>% 
  mutate(date=seq.Date(ymd(intro_date),
                       ymd(intro_date)-1+length(times), 1))

dat_reported <- dat_omic  %>% mutate(date=seq.Date(ymd(intro_date),
                                                   ymd(intro_date)-1+length(dat_omic$day), 1))
# And finally plot this third approach:
p3 <- ggplot() + geom_line(data=project_mlesample ,aes(x=date,y=`50%`), col="green",size=1.5,alpha=0.4) +
  geom_ribbon(data=project_mlesample ,aes(x=date,ymin=`2.5%`,ymax=`97.5%`),fill='darkgreen',alpha=0.1, size = 1.5)+
  geom_point(data=dat_reported,aes(x=date, y=value),color='grey48', alpha=0.8, size = 1.5)
p3
# Again, because the MLE variance is so small, this looks almost exactly the same as the first thing we tried. 

# ---- end check fit ---- 

