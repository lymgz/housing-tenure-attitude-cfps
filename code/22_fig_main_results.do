*! 22_fig_main_results.do — Figure 2: main coefficients and the precision of the
*  housing-cost result.
*
*  Panel A   the tenure coefficients of model M1 (unchanged).
*  Panel B1  the same frozen log-rent coefficient scaled to four rent contrasts, with
*            the prespecified equivalence bounds of Table 2. Nothing is re-estimated:
*            every number is read from rent_scaled_contrasts.dta, which is the frozen
*            coefficient multiplied by log(1+c), c = 10, 25, 50 and 100 per cent.
*  Panel B2  the within-person distribution of log monthly rent changes on the same rent
*            sample, so a reader can see where +10 per cent and a doubling sit relative
*            to the changes these respondents actually experienced.
version 17
set more off

* ---------------------------------------------------- panel A: tenure coefficients
use "${R}/estimates/cfps_coefficients.dta", clear
keep if model_id == "M1" & term_status == "estimated"

gen int y = .
gen str32 lab = ""
replace y = 1 if term == "D_owner_full"
replace y = 8 if term == "D_owner_full"
replace y = 7 if term == "D_owner_partial"
replace y = 6 if term == "D_work_unit_public"
replace y = 5 if term == "D_subsidized_lowrent"
replace y = 4 if term == "D_subsidized_public_rental"
replace y = 3 if term == "D_relatives_friends"
replace y = 2 if term == "D_other"
replace y = 1 if term == "P"
replace lab = "Full ownership"     if term == "D_owner_full"
replace lab = "Partial ownership"  if term == "D_owner_partial"
replace lab = "Work-unit/public"   if term == "D_work_unit_public"
replace lab = "Low-rent subsidized" if term == "D_subsidized_lowrent"
replace lab = "Public rental"      if term == "D_subsidized_public_rental"
replace lab = "Relatives/friends"  if term == "D_relatives_friends"
replace lab = "Other tenure"       if term == "D_other"
replace lab = "Additional property" if term == "P"
keep if !missing(y)
label define tenurelab 8 "Full ownership" 7 "Partial ownership" 6 "Work-unit/public" ///
    5 "Low-rent subsidized" 4 "Public rental" 3 "Relatives/friends" 2 "Other tenure" ///
    1 "Additional property", replace
label values y tenurelab
twoway (pcspike y ci_lo y ci_hi, lcolor("23 66 122") lwidth(medthick)) ///
       (scatter y estimate, msymbol(O) mcolor("23 66 122") msize(medium)), ///
       xline(0, lpattern(dash) lcolor(gs8)) ///
       xlabel(-0.6(0.2)0.2, format(%4.2f) nogrid) ylabel(1(1)8, valuelabel angle(0) noticks nogrid) ///
       xtitle("Coefficient on housing-problem severity, points") ytitle("") ///
       legend(off) graphregion(color(white)) plotregion(color(white)) ///
       name(gA, replace)

* ------------------------- panel B1: the same coefficient at four rent contrasts
use "${R}/estimates/rent_scaled_contrasts.dta", clear
quietly sum sd_within
local sdw = r(mean)
quietly sum bound_05_sd
local b05 = r(mean)
quietly sum bound_10_sd
local b10 = r(mean)
quietly sum scale_ln1p if prespecified == 1
local ln10 = r(mean)
quietly sum scale_ln1p if contrast == "doubling"
local ln2 = r(mean)
quietly sum n_obs
local nrent = r(mean)
quietly sum n_persons
local nrentp = r(mean)
quietly sum n_psu
local nrentc = r(mean)

gen int y = .
replace y = 4 if contrast == "+10%"
replace y = 3 if contrast == "+25%"
replace y = 2 if contrast == "+50%"
replace y = 1 if contrast == "doubling"
label define contrastlab 4 "+10% (prespecified)" 3 "+25% (scaled)" ///
    2 "+50% (scaled)" 1 "Doubling (scaled)", replace
label values y contrastlab

twoway (pcspike y ci_lo y ci_hi if prespecified == 1, lcolor("23 66 122") lwidth(vthick)) ///
       (pcspike y ci_lo y ci_hi if prespecified == 0, lcolor("23 66 122") lwidth(medthick)) ///
       (scatter y estimate if prespecified == 1, msymbol(D) mcolor("23 66 122") msize(medium)) ///
       (scatter y estimate if prespecified == 0, msymbol(Oh) mcolor("23 66 122") msize(medium)), ///
       xline(-`b05' `b05', lpattern(shortdash) lcolor(gs7)) ///
       xline(-`b10' `b10', lpattern(dash) lcolor(gs11)) ///
       xline(0, lpattern(solid) lcolor(gs13)) ///
       xlabel(-0.2(0.1)0.2, format(%4.2f) nogrid) ///
       ylabel(1(1)4, valuelabel angle(0) noticks nogrid) ///
       text(3.80 `b05' "0.05 SD", place(n) size(vsmall) color(gs5)) ///
       text(3.80 `b10' "0.10 SD", place(n) size(vsmall) color(gs5)) ///
       xtitle("Change in housing-problem severity, points") ytitle("") ///
       legend(off) graphregion(color(white)) plotregion(color(white)) ///
       name(gB1, replace)

* ----------------- panel B2: within-person rent changes on the same rent sample
use "${R}/estimates/rent_change_stats.dta", clear
local med   = median[1]
local p10   = p10[1]
local p90   = p90[1]
local wlo   = window_lo[1]
local whi   = window_hi[1]
local wd    = bin_width[1]
local npair = n_pairs[1]
local maxc  = max_count_window[1]
local nout  = n_outside_window[1]
local ty    = 0.97 * `maxc'

use "${R}/estimates/rent_change_panel.dta", clear

twoway (bar count bin_mid, barwidth(`wd') fcolor(gs14) lcolor(gs9) lwidth(vthin)) ///
       (scatter rug d_ln_rent if inrange(d_ln_rent, `wlo', `whi'), ///
            msymbol(|) msize(vsmall) mcolor(gs9)), ///
       xline(`p10' `p90', lpattern(dash) lcolor(gs7)) ///
       xline(`med', lpattern(solid) lcolor(gs3) lwidth(medthick)) ///
       xline(`ln10', lpattern(shortdash) lcolor("23 66 122")) ///
       xline(`ln2', lpattern(longdash) lcolor("23 66 122")) ///
       text(`ty' `ln10' "+10%", place(n) size(vsmall) color("23 66 122")) ///
       text(`ty' `ln2' "doubling", place(n) size(vsmall) color("23 66 122")) ///
       xlabel(-1.5(0.5)1.5, format(%4.1f) nogrid) ///
       xtitle("Within-person change in log monthly rent, adjacent waves") ///
       ytitle("Person-wave pairs per 0.10 bin") ///
       legend(off) graphregion(color(white)) plotregion(color(white)) ///
       name(gB2, replace)

* ------------------------------------------------------------------- assembly
graph combine gB1 gB2, rows(2) graphregion(color(white)) name(gB, replace)
graph combine gA gB, rows(1) ysize(3.6) xsize(7.4) graphregion(color(white)) ///
      name(fig2, replace)
graph export "${FIG}/F02_main_results.pdf", replace
graph export "${FIG}/F02_main_results.png", replace width(2700)
display as txt "wrote F02_main_results"
display as txt "Panel B1: within-person SD = " %6.4f `sdw' "; bounds " %6.4f `b05' ///
    " and " %6.4f `b10' "; rent sample N = " %8.0f `nrent' " person-waves, " ///
    %8.0f `nrentp' " individuals, " %8.0f `nrentc' " PSUs"
display as txt "Panel B2: " %8.0f `npair' " adjacent-wave pairs; median " %6.3f `med' ///
    "; p10 " %6.3f `p10' "; p90 " %6.3f `p90' "; +10% at " %6.3f `ln10' ///
    "; doubling at " %6.3f `ln2' "; tallest bin " %8.0f `maxc' "; outside window " %8.0f `nout'
