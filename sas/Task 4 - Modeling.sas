
* Import clean ds;
options nosource;
proc import out=churn_pred
    datafile = "/workspaces/myfolder/forage_bcgx/data_for_predictions.csv"
    dbms=csv
    replace;
    getnames=yes;
run;

* Inspect dataset;
proc print data=churn_pred (obs=3);
run;

title2 'Create training and test data sets with the PARTITION procedure';
proc partition data=churn_pred seed=531
    partind samppct=75;
    output out=churn_part;
run;

data churn_train(drop=_partind_);
    set churn_part(where=(_partind_=1));
run;

data churn_test(drop=_partind_);
    set churn_part(where=(_partind_~=1));
run;

/* Set interval and nominal variables */
%let num = cons_12m cons_gas_12m cons_last_month forecast_cons_12m forecast_discount_energy forecast_meter_rent_12m
forecast_price_energy_off_peak forecast_price_energy_peak forecast_price_pow_off_peak pow_max imp_cons
margin_gross_pow_ele margin_net_pow_ele nb_prod_act net_margin 
months_activ months_modif_prod months_renewal months_to_end
var_year_price_off_peak_var	var_year_price_peak_var	var_year_price_mid_peak_var	var_year_price_off_peak_fix	var_year_price_peak_fix	var_year_price_mid_peak_fix	var_year_price_off_peak	var_year_price_peak	var_year_price_mid_peak	var_6m_price_off_peak_var	var_6m_price_peak_var	var_6m_price_mid_peak_var	var_6m_price_off_peak_fix	var_6m_price_peak_fix	var_6m_price_mid_peak_fix	var_6m_price_off_peak	var_6m_price_peak	var_6m_price_mid_peak 
offpeak_diff_dec_january_energy	offpeak_diff_dec_january_power	off_peak_peak_var_mean_diff	peak_mid_peak_var_mean_diff	off_peak_mid_peak_var_mean_diff	off_peak_peak_fix_mean_diff	peak_mid_peak_fix_mean_diff	off_peak_mid_peak_fix_mean_diff	off_peak_peak_var_max_monthly_di	peak_mid_peak_var_max_monthly_di	off_peak_mid_peak_var_max_monthl	off_peak_peak_fix_max_monthly_di	peak_mid_peak_fix_max_monthly_di	off_peak_mid_peak_fix_max_monthl
tenure;	

%let cat = has_gas channel_MISSING channel_ewpakwlliwisiwduibdlfmal channel_foosdfpfkusacimwkcsosbic channel_lmkebamcaaclubfxadlmuecc channel_usilxuppasemubllopkaafes
origin_up_kamkkxfxxuwbdslkwifmmc	origin_up_ldkssxwpmemidmecebumci	origin_up_lxidpiddsbxsbosboudaco;

/******************************************************************************

 RANDOM FOREST procedure

 ******************************************************************************/


title2 'Build classification model using Random Forest';
ods output modelInfo=forestModel;
ods output FitStatistics = foreststat;
ods output VariableImportance = varimp;
proc forest data=churn_train ntrees=100 seed=7543;
    input &num/ level=interval;
    input &cat / level=nominal;
    target churn / level=nominal;
    savestate rstore=forstore;
run;

data _null_;
    set forestModel;
    if prxmatch('m/misclassification/i', description) then
       call symputx('acc_train_forest', (1-value));
run;

title3 'Score the model with ASTORE for the test data';
proc astore;
    score data=churn_test rstore=forstore out=for_scoreout copyvars=(churn);
run;

/* Preview variable headers */ 
title4 'Variable headers in scoring dataset';
proc sql;
    select name
    into :cols separated by ' '
    from DICTIONARY.COLUMNS
    where memname = 'FOR_SCOREOUT' and libname = 'WORK';
quit;

/***********************************
 Compute accuracy score (Random Forest)
 The percentage of customers in test data whose predicted churn status matched their actual status.
 ***********************************/
data _null_;
    retain matchSum 0;
    set for_scoreout(keep=I_churn churn) end=last;
    match = (I_churn = churn);
    matchSum + match;
    if last then call symputx ('acc_test_forest', (matchSum/_n_));
run;

/******************************************************************************

 LOGISTIC procedure

 ******************************************************************************/



title2 'Build classification model using Logistic (Quasi-Newton Method)';
ods output FitStatistics=logfitstat;
proc logselect data=churn_train technique=lbfgs maxiter=1000 partfit;
    class churn &cat;
    model churn = &cat &num;
    savestate rstore=logstore;
run;

data _null_;
    set logfitstat;
    if rowid = 'MISCLASS' then
        call symputx('acc_train_logselect', (1-value));
run;

title3 'Score the model with ASTORE for the test data';
proc astore;
    score data=churn_test rstore=logstore out=log_scoreout copyvars=(churn);
run;

/***********************************
 Compute accuracy score (Logistic)
 ***********************************/
data _null_;
    retain matchSum 0;
    set log_scoreout end=last;
    match = (I_churn = churn);
    matchSum + match;
    if last then call symputx ('acc_test_logselect', (matchSum/_n_));
run;


/******************************************************************************

 TREESPLIT procedure

 ******************************************************************************/

title2 'Build classification model using PROC TREESPLIT';
ods output treeperformance=treestat;
proc treesplit data=churn_train;
    class churn &cat;
    model churn = &cat &num;
    prune c45;
    savestate rstore=dtstore;
run;

data _null_;
    set treestat;
    call symputx('acc_train_treesplit', (1-MiscRate));
run;

title3 'Score the model with ASTORE for the test data';
proc astore;
    score data=churn_test rstore=dtstore out=dt_scoreout copyvars=(churn);
run;

/***********************************
 Compute accuracy score (decision tree)
 ***********************************/
data _null_;
    retain matchSum 0;
    set dt_scoreout(keep=I_churn churn) end=last;
    match = (I_churn = churn);
    matchSum + match;
    if last then call symputx ('acc_test_treesplit', (matchSum/_n_));
run;


/******************************************************************************

 GRADBOOST procedure

 ******************************************************************************/

title2 'Build classification model using PROC GRADBOOST';
ods output FitStatistics=gbfitstat;
proc gradboost data=churn_train;
    input &num / level=interval;
    input &cat / level=nominal;
    target churn / level=nominal;
    savestate rstore=gbstore;
run;

data _null_;
    set gbfitstat end=last;
    if last then
       call symputx('acc_train_gradboost', (1-MiscTrain));
run;

title3 'Score the model with ASTORE for the test data';
proc astore;
    score data=churn_test rstore=gbstore out=gb_scoreout copyvars=(churn);
run;

/***********************************
 Compute accuracy score (Gradient Boost)
 ***********************************/
data _null_;
    retain matchSum 0;
    set gb_scoreout(keep=I_churn churn) end=last;
    match = (I_churn = churn);
    matchSum + match;
    if last then call symputx ('acc_test_gradboost', (matchSum/_n_));
run;


/******************************************************************************

 SVMACHINE procedure

 ******************************************************************************/

title2 'Build classification model using PROC SVMACHINE';
ods output FitStatistics=svmstat;
proc svmachine data=churn_train;
    input &num / level=interval;
    input &cat / level=nominal;
    target churn / level=nominal;
    savestate rstore=svmstore;
run;

data _null_;
    set svmstat;
    if statistic = 'Accuracy' then
       call symputx('acc_train_svmachine', training);
run;

title3 'Score the model with ASTORE for the test data';
proc astore;
    score data=churn_test rstore=svmstore out=svm_scoreout copyvars=(churn);
run;

/***********************************
 Compute accuracy score (SV machine)
 ***********************************/
data _null_;
    retain matchSum 0;
    set svm_scoreout(keep=I_churn churn) end=last;
    match = (I_churn = churn);
    matchSum + match;
    if last then call symputx ('acc_test_svmachine', (matchSum/_n_));
run;




/* Plot accuracy scores of test vs. training sets 
across all models */

%macro ap;
    %let allprocs = forest logselect treesplit gradboost svmachine;
    data allMethods;
        length procname $16. type $8.;
        %do i = 1 %to %sysfunc(countw(&allprocs));
            %let currentProc = %scan(&allprocs,&i);
            procname = "&currentProc";
            type = "train";
            accuracy = &&&acc_train_&currentProc;
            output;
            procname = "&currentProc";
            type = "test";
            accuracy = &&&acc_test_&currentProc;
            output;
        %end;
    run;
    proc sgplot data=allMethods;
        vbar procname / response=accuracy group=type nostatlabel datalabel
                    groupdisplay=cluster dataskin=pressed;
        xaxis display=(nolabel);
        yaxis grid;
    run;
%mend ap;

title2 'Comparison of Accuracy across Machine Learning Models';
%ap;

title;


title 'Feature importance of Churn Prediction';
proc sgplot data=varimp;
    hbarparm category=variable response = importance;
run;


proc freq data=for_scoreout;
    table i_churn * churn / out=conf_matrix;
run;
