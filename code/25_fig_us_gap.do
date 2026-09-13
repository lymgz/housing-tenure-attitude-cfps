*! 25_fig_us_gap.do — Appendix figure: wanting lower prices is not the same as
*  supporting specific developments (US surveys, external reference).
version 17
set more off

use "${R}/estimates/us_gap_distribution.dta", clear
keep if block == "policy" & tenure == "Owner+Renter" & category == "oppose"
keep if inlist(group, "want_lower==1", "want_lower==0")
gen byte wants = group == "want_lower==1"
gen byte tod   = tool == "TOD"
gen double x0  = tod - 0.18
gen double x1  = tod + 0.18

keep wave wants tod x0 x1 share_pct ci_lo_pct ci_hi_pct
reshape wide share_pct ci_lo_pct ci_hi_pct, i(wave tod) j(wants)

quietly sum x0
local a = r(mean)
quietly sum x1
local b = r(mean)

twoway (bar share_pct0 x0 if wave == "s2", barwidth(0.35) color(gs10) lcolor(gs8)) ///
       (bar share_pct1 x1 if wave == "s2", barwidth(0.35) color("23 66 122") lcolor("23 66 122")) ///
       , ylabel(0(10)50, nogrid) xlabel(0 "Open land" 1 "Near transit", noticks nogrid) ///
       ytitle("Opposes the proposal, %") xtitle("") ///
       legend(order(1 "Does not prefer lower prices" 2 "Prefers lower prices") ///
              rows(1) position(6) region(lstyle(none))) ///
       title("August 2022", size(medium)) ///
       graphregion(color(white)) plotregion(color(white)) name(gu1, replace)

twoway (bar share_pct0 x0 if wave == "s3", barwidth(0.35) color(gs10) lcolor(gs8)) ///
       (bar share_pct1 x1 if wave == "s3", barwidth(0.35) color("23 66 122") lcolor("23 66 122")) ///
       , ylabel(0(10)50, nogrid) xlabel(0 "Open land" 1 "Near transit", noticks nogrid) ///
       ytitle("") xtitle("") legend(off) title("April-May 2023", size(medium)) ///
       graphregion(color(white)) plotregion(color(white)) name(gu2, replace)

twoway (bar share_pct0 x0 if wave == "jpipe", barwidth(0.35) color(gs10) lcolor(gs8)) ///
       (bar share_pct1 x1 if wave == "jpipe", barwidth(0.35) color("23 66 122") lcolor("23 66 122")) ///
       , ylabel(0(10)50, nogrid) xlabel(0 "Open land" 1 "Near transit", noticks nogrid) ///
       ytitle("") xtitle("") legend(off) title("March 2024", size(medium)) ///
       graphregion(color(white)) plotregion(color(white)) name(gu3, replace)

graph combine gu1 gu2 gu3, rows(1) ysize(2.2) xsize(6.8) ///
      graphregion(color(white)) name(figB1, replace)
graph export "${FIG}/FB1_us_gap.pdf", replace
graph export "${FIG}/FB1_us_gap.png", replace width(2400)
display as txt "wrote FB1_us_gap"
