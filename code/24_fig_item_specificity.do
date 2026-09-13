*! 24_fig_item_specificity.do — Figure 4: is the rent association specific to housing?
*  Housing plus each of the six other national problems, same sample and covariates.
version 17
set more off

use "${R}/estimates/item_specificity.dta", clear
keep if inlist(outcome, "H", "env_problem", "wealthgap_problem", "jobs_problem", ///
               "education_problem", "health_problem", "socialsecurity_problem", "R")
gen byte housing = outcome == "H"
gen byte diff    = outcome == "R"

* order: housing first, then the six other items by estimate, then the difference
gen double ord = .
replace ord = 1 if outcome == "H"
replace ord = 2 if outcome == "socialsecurity_problem"
replace ord = 3 if outcome == "jobs_problem"
replace ord = 4 if outcome == "env_problem"
replace ord = 5 if outcome == "health_problem"
replace ord = 6 if outcome == "education_problem"
replace ord = 7 if outcome == "wealthgap_problem"
replace ord = 9 if outcome == "R"
gen int y = 8 - ord

gen str34 lab = ""
replace lab = "Housing problems"          if outcome == "H"
replace lab = "Social security"           if outcome == "socialsecurity_problem"
replace lab = "Employment"                if outcome == "jobs_problem"
replace lab = "Environment"               if outcome == "env_problem"
replace lab = "Health care"               if outcome == "health_problem"
replace lab = "Education"                 if outcome == "education_problem"
replace lab = "Income inequality"         if outcome == "wealthgap_problem"
replace lab = "Difference: housing minus other six" if outcome == "R"

label define itemlab -1 "Difference: housing minus other six" ///
    1 "Income inequality" 2 "Education" 3 "Health care" 4 "Environment" ///
    5 "Employment" 6 "Social security" 7 "Housing problems", replace
label values y itemlab
keep if !missing(y)

* Ticks on multiples of 0.01: the previous -0.035(0.01)0.035 grid produced two
* pairs of labels that rounded to the same string.
twoway (pcspike y ci_lo_10pct y ci_hi_10pct if !housing & !diff, lcolor(gs6) lwidth(medthin)) ///
       (pcspike y ci_lo_10pct y ci_hi_10pct if housing, lcolor("213 94 0") lwidth(medthick)) ///
       (pcspike y ci_lo_10pct y ci_hi_10pct if diff,    lcolor("23 66 122") lwidth(medthick)) ///
       (scatter y estimate_10pct if !housing & !diff, msymbol(O) mcolor(gs6) msize(medium)) ///
       (scatter y estimate_10pct if housing, msymbol(D) mcolor("213 94 0") msize(medium)) ///
       (scatter y estimate_10pct if diff,    msymbol(S) mcolor("23 66 122") msize(medium)), ///
       xline(0, lpattern(solid) lcolor(gs10)) ///
       xlabel(-0.04(0.01)0.04, format(%4.2f) nogrid) ///
       ylabel(-1 1/7, valuelabel angle(0) noticks nogrid) ///
       xtitle("Change in the rating for 10% higher rent, points") ytitle("") ///
       legend(off) graphregion(color(white)) plotregion(color(white)) ///
       name(fig4, replace)

* Figure 5 in the manuscript.
graph export "${FIG}/F05_item_specificity.pdf", replace
graph export "${FIG}/F05_item_specificity.png", replace width(2200)
display as txt "wrote F05_item_specificity"
