*! 23_fig_restriction_ladder.do — Figure 3: does the contrast fall towards zero under
*  the construct-validity restrictions? (visualises Table 4)
version 17
set more off

use "${R}/estimates/construct_validity.dta", clear
keep if term == "renter_aligned" | term == "fid_changed"
gen str20 tag = ""
replace tag = "baseline"        if strpos(model, "V1") > 0
replace tag = "hlh:no"          if strpos(model, "V6") > 0
replace tag = "urban:no"        if strpos(model, "V7") > 0
replace tag = "oneswitch"       if strpos(model, "V8") > 0
replace tag = "age30"           if strpos(model, "V10") > 0
replace tag = "controls"        if strpos(model, "V4") > 0
keep if tag != ""

* keep only the renter contrast from V4; the household-change coefficient is reported
* separately in the table and would need a different scale here
keep if term == "renter_aligned"

gen int y = .
gen str34 lab = ""
* baseline on top, restrictions below, so the ladder reads downwards
replace y = 6 if tag == "baseline"
replace y = 5 if tag == "hlh:no"
replace y = 4 if tag == "urban:no"
replace y = 3 if tag == "oneswitch"
replace y = 2 if tag == "age30"
replace y = 1 if tag == "controls"

label define ladder 6 "Aligned owners and renters" ///
    5 "Household id never changes" ///
    4 "Urban status never changes" ///
    3 "At most one tenure change" ///
    2 "Observed at age 30 or above" ///
    1 "+ household and urban change controls", replace
label values y ladder

* the number of tenure changers behind each row belongs in the caption, not on the
* plot: 2,099 / 1,412 / 1,494 / 1,796 / 1,315 / 713 from top to bottom

quietly sum estimate if y == 1
local base = r(mean)

twoway (pcspike y ci_lo y ci_hi, lcolor("23 66 122") lwidth(medthick)) ///
       (scatter y estimate, msymbol(O) mcolor("23 66 122") msize(medium)) ///
       (scatter y estimate if y == 1, msymbol(O) mcolor("213 94 0") msize(medium)), ///
       xline(`base', lpattern(dash) lcolor(gs8)) ///
       xline(0, lpattern(solid) lcolor(gs10)) ///
       xlabel(0(0.1)0.6, format(%3.1f) nogrid) ylabel(1(1)6, valuelabel angle(0) noticks nogrid) ///
       xtitle("Renter minus owner, points on the 0-10 scale") ytitle("") ///
       legend(off) graphregion(color(white)) plotregion(color(white)) ///
       name(fig3, replace)

* Figure 4 in the manuscript: Figure 3 is the pooled-versus-within comparison.
graph export "${FIG}/F04_restriction_ladder.pdf", replace
graph export "${FIG}/F04_restriction_ladder.png", replace width(2200)
display as txt "wrote F04_restriction_ladder"
