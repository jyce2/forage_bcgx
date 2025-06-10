* Import client ds;
options nosource;
proc import out=client
    datafile = "/workspaces/myfolder/client_data.csv"
    dbms=csv
    replace;
    getnames=yes;
run;

* Import price ds;
options nosource;
proc import out=price
    datafile = "/workspaces/myfolder/price_data.csv"
    dbms=csv
    replace;
    getnames=yes;
run;

* Import clean ds;
options nosource;
proc import out=clean
    datafile = "/workspaces/myfolder/clean_data_after_eda.csv"
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
select  *, c.id
    from client as c inner join 
         price as p
    on c.id = p.id
    order by id desc;
quit;

* Final merged dataset;
proc sort data=merged nodupkey out=final; 
    by id;
run;

* Final dataset;
ods exclude EngineHost;
title 'Final dataset';
proc contents data=final;
run;

proc sort data=final;
   by id;
run;

proc sort data=clean;
   by id;
run;

* Compare two datasets; 
proc compare base=final compare=clean;
   title 'Comparison of Variables in Different Data Sets';
run;


* Save Kendall's pairwise correlation estimates;
ods select VarInformation;
proc corr data=final kendall; 
   var _numeric_;
   ods output kendallcorr=corrs;
run;


* Transpose dataset and derive vars for each pairwise corr and p-value;
data long; set corrs end=eof;
      keep variable vname corr pval;
      array c (*) cons_12m	cons_gas_12m cons_last_month date_activ date_end date_modif_prod date_renewal	forecast_cons_12m	forecast_cons_year forecast_discount_energy	forecast_meter_rent_12m	forecast_price_energy_off_peak forecast_price_energy_peak forecast_price_pow_off_peak imp_cons margin_gross_pow_ele margin_net_pow_ele	nb_prod_act	net_margin	num_years_antig pow_max churn price_date price_off_peak_var price_peak_var	price_mid_peak_var price_off_peak_fix price_peak_fix price_mid_peak_fix;
      array p (*) p:;
      do i=1 to dim(c);
         vname=vname(c(i));
         corr=c(i); pval=p(i);
         output;
      end;
      if eof then do;
         variable=''; vname=''; corr=-1; pval=0; output;
         variable=''; vname=''; corr=1; pval=1; output;
      end;
run;

* Use estimates to create a correlation matrix (heatmap);
ods graphics / height=15in width=15in;
proc sgplot data=long noautolegend;
   heatmapparm x=variable y=vname colorresponse=corr / colormodel=(red white firebrick);
   text x=variable y=vname text=corr / position=top;
   *text x=variable y=vname text=pval / position=bottom;
   gradlegend / title="Correlation";
   xaxis display=(nolabel noticks);
   yaxis reverse display=(nolabel noticks);
   format pval pvalue6.;
   format corr 8.2;
   title "Estimated Correlation Matrix";
run;

%let num = price_mid_peak_fix price_peak_fix price_mid_peak_var price_peak_var forecast_price_energy_peak forecast_price_pow_off_peak price_off_peak_fix num_years_antig date_activ net_margin forecast_cons_12m nb_prod_act cons_gas_12m imp_cons cons_last_month forecast_cons_year date_renewal date_end;;

/* Test strongly correlated vars */
* Save Kendall's pairwise correlation estimates;
ods select KendallCorr;
proc corr data=final kendall; 
   var &num;
   ods output kendallcorr=corrs2;
run;


* Transpose dataset and derive vars for each pairwise corr and p-value;
data long2; set corrs2 end=eof;
      keep variable vname corr pval;
      array c (*) &num;
      array p (*) p:;
      do i=1 to dim(c);
         vname=vname(c(i));
         corr=c(i); pval=p(i);
         output;
      end;
      if eof then do;
         variable=''; vname=''; corr=-1; pval=0; output;
         variable=''; vname=''; corr=1; pval=1; output;
      end;
run;

* Use estimates to create a correlation matrix (heatmap);
ods graphics / height=15in width=15in;
proc sgplot data=long2 noautolegend;
   heatmapparm x=variable y=vname colorresponse=corr / colormodel=(red white firebrick);
   text x=variable y=vname text=corr / position=top;
   *text x=variable y=vname text=pval / position=bottom;
   gradlegend / title="Correlation";
   xaxis display=(nolabel noticks);
   yaxis reverse display=(nolabel noticks);
   format pval pvalue6.;
   format corr 8.2;
   title "Estimated Correlation Matrix";
run;



* Average off-peak prices by month;
* Note: All company IDs are unique per row and there are no repeated ids across month. 

proc sql number;
    select month(price_date) as month, price_date, mean(price_off_peak_var) as avg_off_peak_energy, mean(price_off_peak_fix) as avg_off_peak_power,
    dif(price_off_peak_var)
    from final
    group by price_date;
quit;

proc sort data=final nodupkey dupout=dup;
    by id;
run;

proc print data=dup;
    var id price_date;
run;