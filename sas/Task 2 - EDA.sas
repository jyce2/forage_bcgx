* Import client ds;

proc import out=client
    datafile = "/workspaces/myfolder/forage_bcgx/client_data.csv"
    dbms=csv
    replace;
    getnames=yes; 
run;

* Import price ds;
options nosource;
proc import out=price
    datafile = "/workspaces/myfolder/forage_bcgx/price_data.csv"
    dbms=csv
    replace;
    getnames=yes;
run;

/* Merge datasets matched by Customer ID */

proc sort data=client;
    by id;
run;

proc sort data=price;
    by id;
run;

proc sql;
    create table merged as 
select  *
    from client as c inner join 
         price as p
    on c.id = p.id
    order by c.id desc;
quit;

* Final merged dataset;
proc sort data=merged nodupkey out=final; 
    by id;
run;

* Customer dataset;
ods noproctitle;
ods exclude EngineHost;
title 'Customer dataset';
proc contents data=client;
run;

* Price dataset;
ods noproctitle;
ods exclude EngineHost;
title 'Price dataset';
proc contents data=price;
run;

/* Ensure all variables present */
ods exclude EngineHost;
title 'Final dataset';
proc contents data=final;
run;

proc print data=final (obs=3);
run;

* Preview first 5 rows;

* Customer dataset;
title 'Customer dataset';
proc print data=client (obs=5);
run;

* Price dataset;
title 'Price dataset';
proc print data=price (obs=5);
run;


* EDA of customer dataset;
%let client_num = cons_12m	cons_gas_12m	cons_last_month	date_activ	date_end	date_modif_prod	date_renewal	forecast_cons_12m	forecast_cons_year	forecast_discount_energy	forecast_meter_rent_12m	forecast_price_energy_off_peak	forecast_price_energy_peak	forecast_price_pow_off_peak	pow_max	imp_cons	margin_gross_pow_ele	margin_net_pow_ele	nb_prod_act	net_margin	num_years_antig;
%let client_cat = has_gas origin_up channel_sales churn;

%macro c_eda(ds);
   /* Summary statistics for numeric variables */
   title "Numeric Statistics of &ds dataset";
   proc means data=&ds n mean std min q1 median q3 max nmiss maxdec=1;
   var &client_num;
   run;

   proc contents data=&ds out=varinfo(keep=name type) noprint;
   run;

   /* Frequency tables for character variables */
   title "Categorical Statistics of &ds dataset";
   proc freq data=&ds nlevels order=freq;
      table &client_cat / nocum norow nocol;
   run;

%mend c_eda;

* Customer dataset;
%c_eda(ds = client);


* EDA of price dataset;
%let price_num = price_date	price_off_peak_var	price_peak_var	price_mid_peak_var	price_off_peak_fix	price_peak_fix	price_mid_peak_fix;

%macro p_eda(ds);
   /* Summary statistics for numeric variables */
   title "Numeric Statistics of &ds dataset";
   proc means data=&ds n mean std min q1 median q3 max nmiss maxdec=1;
   var &price_num;
   run;

%mend p_eda;

%p_eda(price);


* Propotion of Customer churn %; 

proc freq data=final order=freq noprint;
    tables churn/ out=freqout nocum plots=freqplot(scale=percent orient=horizontal);
run;

title "Customer Churn Rate (%)";
ods graphics /height=500px width=800px;
proc sgplot data=freqout;
  hbarbasic churn / response=percent group=churn groupdisplay=stack
      seglabel seglabelfitpolicy=none seglabelattrs=(color=white size=12pt) ;
  keylegend; 
  xaxis grid;
run;
/* The customer churn rate is approximately 10%. */



* Customer churn % by Category;

%macro stacked(title, var);
proc freq data=final order=freq noprint;
    tables churn*&var / out=freqout outpct norow nofreq nocum nopercent plots=freqplot(twoway=stacked scale=grouppct); 
run;

proc sort data=freqout;
    by descending pct_col;
run;

title "Customer Churn Rate (%) by &title";
ods graphics /height=500px width=800px;
proc sgplot data=freqout;
  vbarparm category=&var response=pct_col / group=churn
      seglabel seglabelfitpolicy=none seglabelattrs=(color=white weight=bold size=12pt) grouporder=ascending;
  keylegend;
run;
%mend stacked;

/* Customer churn % by Sales Channel */
%stacked(title= Sales_Channel, var=channel_sales);

/* Customer churn % by Gas Client */ 
%stacked(title= Gas_Client, var=has_gas);

/* Customer churn % by Electricity Campaign the Customer First Subscribed to */
%stacked(title=First_Subscribed, var =origin_up);



/* Histogram of Numeric var by churn */ 
 %macro hist_eda(ds);
   /*Output vartype*/
   proc contents data=&ds out=varinfo(keep=name type) noprint;
   run;

   data _null_;
      set varinfo;
      if type = 1 then call execute('
         proc sgplot data=&ds;
         histogram ' || strip(name) ||' / scale = percent group=churn;
         density ' || strip(name) || ' / type = kernel scale=percent group = churn;
         run;');
   run;


   %mend hist_eda;

   %hist_eda(final)

%macro sortboxplot(var=, label=);

* Boxplots of Numeric Variable by Customer churn;
title "Distribution of &var by Customer Churn";
proc sgplot data=final noautolegend;
  /* Add the JITTER option to separate points at the same location */
  /* Use filled outlined symbols */
  scatter x=churn y=&var / jitter filledoutlinedmarkers
      markerattrs=(symbol=circlefilled size=11) 
      markerfillattrs=(color=cxfdae6b)
      markeroutlineattrs=(color=orange)
      transparency=0.5;
  vbox &var / category=churn nofill 
      lineattrs=(color=black thickness=2)
      whiskerattrs=(color=black thickness=2)
      medianattrs=(color=black thickness=2)
      displaystats=(std median n);
  label &var ="&label";
run;

%mend sortboxplot;

%sortboxplot(var=cons_12m, label=Electricity consumption last 12 mths);
%sortboxplot(var=cons_gas_12m, label=Gas consumption last 12 mths);
%sortboxplot(var=cons_last_month, label=Electricity consumption last mth);
%sortboxplot(var=forecast_cons_12m, label=Forecasted electricity consumption next 12 mths);
%sortboxplot(var=forecast_cons_year, label=Forecasted electricity consumption next calendar year);
%sortboxplot(var=forecast_discount_energy, label=Forecasted value of current discount);
%sortboxplot(var=forecast_meter_rent_12m, label=Forecasted bill of meter rental for next 12 mths);
%sortboxplot(var=forecast_price_energy_off_peak, label=Forecasted energy price for 1st period (off peak));
%sortboxplot(var=pow_max, label=Subscribed power);
%sortboxplot(var=imp_cons, label=Current paid consumption);
%sortboxplot(var=margin_gross_pow_ele, label=Gross margin on power subscription);
%sortboxplot(var=margin_net_pow_ele, label=Net margin on power subscription);
%sortboxplot(var=nb_prod_act, label=Number of active products and services);
%sortboxplot(var=net_margin, label=Total net margin);
%sortboxplot(var=num_years_antig, label=Antiquity of client in years);

%sortboxplot(var=price_off_peak_var, label=Price of energy at 1st period (off peak));
%sortboxplot(var=price_peak_var, label=Price of energy at 2nd period (peak));
%sortboxplot(var=price_mid_peak_var, label=Price of energy at 3rd period (mid peak));
%sortboxplot(var=price_off_peak_fix, label= Price of power at 1st period (off peak));
%sortboxplot(var=price_peak_fix	, label=Price of power at 2nd period (peak));
%sortboxplot(var=price_mid_peak_fix, label=Price of power at 3rd period (mid peak));


