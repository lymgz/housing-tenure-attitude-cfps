*! 21_fig_measurement.do — Figure 1: how much does the housing-problem rating
*  move within a person between adjacent waves?
*
*  Reads ${R}/estimates/within_person_change.dta, written by 15_export_estimates.py
*  out of the frozen S_M1 estimation sample. Stata is a plotting engine here: no
*  model is estimated and no number is recomputed from raw survey files.
version 17
set more off

use "${R}/estimates/within_person_change.dta", clear
quietly count
display as txt "adjacent two-year pairs: " r(N)
tempfile base
save `base'

* ------------------------------------------------- panel A: the change itself
use `base', clear
gen byte one = 1
collapse (sum) n = one, by(d_h)
tempfile obsA
save `obsA'
clear
set obs 21
gen int d_h = _n - 11
merge 1:1 d_h using `obsA', nogen
replace n = 0 if missing(n)
quietly sum n
gen double share = 100 * n / r(sum)
twoway (bar share d_h, barwidth(0.75) color("23 66 122") lcolor("23 66 122")), ///
       xlabel(-10(2)10, format(%3.0f) nogrid) ylabel(, nogrid) ///
       xtitle("Change in the housing-problem rating, points") ///
       ytitle("Share of adjacent pairs, %") ///
       legend(off) graphregion(color(white)) plotregion(color(white)) ///
       name(gA, replace)

* ------------------------- panel B: share moving by at least k points, k = 0..10
use `base', clear
gen byte one = 1
collapse (sum) n = one, by(abs_d_h)
tempfile obsB
save `obsB'
clear
set obs 11
gen int abs_d_h = _n - 1
merge 1:1 abs_d_h using `obsB', nogen
replace n = 0 if missing(n)
gsort -abs_d_h
quietly sum n
local tot = r(sum)
gen double cum = sum(n)
replace cum = 100 * cum / `tot'
sort abs_d_h
twoway (connected cum abs_d_h, lcolor("23 66 122") lwidth(medthick) ///
        msymbol(O) msize(small) mcolor("23 66 122")), ///
       xlabel(0(1)10, format(%3.0f) nogrid) ylabel(0(10)100, nogrid) ///
       xtitle("Absolute change, points") ///
       ytitle("Share of pairs moving at least this much, %") ///
       legend(off) graphregion(color(white)) plotregion(color(white)) ///
       name(gB, replace)

* ------------------------------------------------- numbers the caption quotes
use `base', clear
quietly sum d_h
display as txt "mean dH " %6.3f r(mean) "   sd of dH " %6.3f r(sd)
foreach k in 0 2 3 5 {
    quietly count if abs_d_h >= `k'
    display as txt "share |dH| >= `k' : " %5.1f 100 * r(N) / _N " per cent"
}

graph combine gA gB, rows(1) ysize(2.6) xsize(6.6) ///
      graphregion(color(white)) name(fig1, replace)
graph export "${FIG}/F01_within_person_variation.pdf", replace
graph export "${FIG}/F01_within_person_variation.png", replace width(2400)
display as txt "wrote F01_within_person_variation"
