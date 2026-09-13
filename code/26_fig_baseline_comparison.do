*! 26_fig_baseline_comparison.do — Figure 3: pooled versus within-person estimates
*  of the same coefficients, on unchanged samples.
*
*  Stata is a plotting engine. Every number is read from the frozen stage-2 results
*  exported by 15_export_estimates.py into cfps_coefficients.dta and
*  cfps_model_stats.dta. Nothing is estimated here, no sample changes, and no
*  coefficient, interval or sample size is typed by hand.
*
*  Panel A pairs the eight tenure and additional-property coefficients of M0_T
*  (pooled OLS with wave effects) and M1 (person and wave fixed effects).
*  Panel B pairs the four housing-position coefficients of M0_R and M2 that share
*  the same unit, with the log-rent coefficient rescaled to 10 per cent higher rent.
*  The controls (ln_income, familysize, urban) are deliberately not plotted: their
*  units are not comparable with the coefficients shown.
version 17
set more off

local k = ln(1.10)   // rent is reported per log point, not per 10 per cent

* ------------------------------------------------- samples: pooled and FE agree
use "${R}/estimates/cfps_model_stats.dta", clear
foreach pair in "M0_T M1" "M0_R M2" {
    local a : word 1 of `pair'
    local b : word 2 of `pair'
    foreach v in n_obs n_persons n_clusters {
        quietly sum `v' if model_id == "`a'"
        local va = r(mean)
        quietly sum `v' if model_id == "`b'"
        local vb = r(mean)
        if `va' != `vb' {
            display as error "`a' and `b' differ on `v': `va' vs `vb'"
            exit 459
        }
    }
}
quietly sum n_obs if model_id == "M0_T"
local nT : display %9.0fc r(mean)
local nT = trim("`nT'")
quietly sum n_obs if model_id == "M0_R"
local nR : display %9.0fc r(mean)
local nR = trim("`nR'")

* ================================================================ Panel A
use "${R}/estimates/cfps_coefficients.dta", clear
keep if inlist(model_id, "M0_T", "M1") & term_status == "estimated"
keep term estimate ci_lo ci_hi model_id
gen byte fe = model_id == "M1"
drop model_id
reshape wide estimate ci_lo ci_hi, i(term) j(fe)

* only the coefficients whose unit is a point of H; the controls are a different unit
keep if inlist(term, "D_owner_full", "D_owner_partial", "D_work_unit_public", "D_subsidized_lowrent", ///
    "D_subsidized_public_rental", "D_relatives_friends", "D_other", "P")
gen str40 lab = ""
replace lab = "Full ownership"                 if term == "D_owner_full"
replace lab = "Partial ownership"              if term == "D_owner_partial"
replace lab = "Work-unit or public housing"    if term == "D_work_unit_public"
replace lab = "Low-rent subsidized housing"    if term == "D_subsidized_lowrent"
replace lab = "Public rental housing"          if term == "D_subsidized_public_rental"
replace lab = "Housing from relatives/friends" if term == "D_relatives_friends"
replace lab = "Other arrangements"             if term == "D_other"
replace lab = "Additional property (vs none)"  if term == "P"
count if lab == ""
if r(N) > 0 {
    display as error "unlabelled coefficient in Panel A"
    exit 459
}

sort estimate0
gen int ytop = _N + 1 - _n
gen double diff = estimate0 - estimate1

egen double lo_all = rowmin(ci_lo0 ci_lo1)
egen double hi_all = rowmax(ci_hi0 ci_hi1)
quietly sum lo_all
local xlo = floor(r(min) * 10) / 10 - 0.15
quietly sum hi_all
local xhi = r(max) + 0.55
local tx  = r(max) + 0.12
quietly sum ytop
local ylo = r(min) - 0.7
local yhi = r(max) + 0.9
local hy  = r(max) + 0.5
local ylabs ""
local annopts ""
forvalues i = 1/`=_N' {
    local yy = ytop[`i']
    local ll = lab[`i']
    local dd : display %5.2f diff[`i']
    local ylabs `ylabs' `yy' "`ll'"
    local annopts `annopts' text(`yy' `tx' "`dd'", place(e) size(vsmall) color(gs3))
}

reshape long estimate ci_lo ci_hi, i(term lab ytop diff) j(fe)
gen double ypos = ytop + cond(fe == 1, 0.16, -0.16)
bysort term: egen double xa = min(estimate)
bysort term: egen double xb = max(estimate)

twoway (pcspike ypos ci_lo ypos ci_hi if fe == 0, lcolor(gs8) lwidth(medthin)) ///
       (pcspike ypos ci_lo ypos ci_hi if fe == 1, lcolor("23 66 122") lwidth(medthick)) ///
       (pcspike ytop xa ytop xb if fe == 1, lpattern(shortdash) lcolor(gs5) lwidth(thin)) ///
       (scatter ypos estimate if fe == 0, msymbol(O) mcolor(gs10) msize(medium)) ///
       (scatter ypos estimate if fe == 1, msymbol(S) mcolor("23 66 122") msize(medium)), ///
       xline(0, lpattern(solid) lcolor(gs10)) ///
       xlabel(#5, format(%4.2f) nogrid) xscale(range(`xlo' `xhi')) ///
       ylabel(`ylabs', angle(0) noticks nogrid) yscale(range(`ylo' `yhi')) ///
       text(`hy' `tx' "Pooled - FE", place(e) size(vsmall) color(gs3)) ///
       `annopts' ///
       xtitle("Association with H, points") ytitle("") ///
       legend(order(4 "Pooled OLS with wave effects" 5 "Person and wave fixed effects") ///
              rows(2) position(6) region(lstyle(none)) size(small)) ///
       title("A. Same `nT' tenure observations", size(medium)) ///
       graphregion(color(white)) plotregion(color(white)) name(gA, replace)

* ================================================================ Panel B
use "${R}/estimates/cfps_coefficients.dta", clear
keep if inlist(model_id, "M0_R", "M2") & term_status == "estimated"
keep term estimate ci_lo ci_hi model_id
gen byte fe = model_id == "M2"
drop model_id
reshape wide estimate ci_lo ci_hi, i(term) j(fe)

* housing-position coefficients only, and all in points of H after the rent scaling
keep if inlist(term, "ln_rent", "D_subsidized_lowrent", "D_subsidized_public_rental", "P")
foreach v in estimate0 estimate1 ci_lo0 ci_lo1 ci_hi0 ci_hi1 {
    quietly replace `v' = `v' * `k' if term == "ln_rent"
}
gen str40 lab = ""
replace lab = "Monthly rent, 10% higher"      if term == "ln_rent"
replace lab = "Low-rent subsidized housing"   if term == "D_subsidized_lowrent"
replace lab = "Public rental housing"         if term == "D_subsidized_public_rental"
replace lab = "Additional property (vs none)" if term == "P"
count if lab == ""
if r(N) > 0 {
    display as error "unlabelled coefficient in Panel B"
    exit 459
}

* cross-check: the equivalence table publishes the same scaled fixed-effects quantity
preserve
use "${R}/estimates/mde_table.dta", clear
keep if preset == 1 & sd_type == "within"
quietly sum estimate_scaled
local ref = r(mean)
restore
quietly sum estimate1 if term == "ln_rent"
if abs(r(mean) - `ref') > 1e-9 {
    display as error "scaled rent estimate does not match mde_table: " %12.9f r(mean) " vs " %12.9f `ref'
    exit 459
}

sort estimate0
gen int ytop = _N + 1 - _n
gen double diff = estimate0 - estimate1

egen double lo_all = rowmin(ci_lo0 ci_lo1)
egen double hi_all = rowmax(ci_hi0 ci_hi1)
quietly sum lo_all
local xlo = floor(r(min) * 10) / 10 - 0.15
quietly sum hi_all
local xhi = r(max) + 0.55
local tx  = r(max) + 0.12
quietly sum ytop
local ylo = r(min) - 0.7
local yhi = r(max) + 0.9
local hy  = r(max) + 0.5
local ylabs ""
local annopts ""
forvalues i = 1/`=_N' {
    local yy = ytop[`i']
    local ll = lab[`i']
    local dd : display %5.2f diff[`i']
    local ylabs `ylabs' `yy' "`ll'"
    local annopts `annopts' text(`yy' `tx' "`dd'", place(e) size(vsmall) color(gs3))
}

reshape long estimate ci_lo ci_hi, i(term lab ytop diff) j(fe)
gen double ypos = ytop + cond(fe == 1, 0.16, -0.16)
bysort term: egen double xa = min(estimate)
bysort term: egen double xb = max(estimate)

twoway (pcspike ypos ci_lo ypos ci_hi if fe == 0, lcolor(gs8) lwidth(medthin)) ///
       (pcspike ypos ci_lo ypos ci_hi if fe == 1, lcolor("23 66 122") lwidth(medthick)) ///
       (pcspike ytop xa ytop xb if fe == 1, lpattern(shortdash) lcolor(gs5) lwidth(thin)) ///
       (scatter ypos estimate if fe == 0, msymbol(O) mcolor(gs10) msize(medium)) ///
       (scatter ypos estimate if fe == 1, msymbol(S) mcolor("23 66 122") msize(medium)), ///
       xline(0, lpattern(solid) lcolor(gs10)) ///
       xlabel(#5, format(%4.2f) nogrid) xscale(range(`xlo' `xhi')) ///
       ylabel(`ylabs', angle(0) noticks nogrid) yscale(range(`ylo' `yhi')) ///
       text(`hy' `tx' "Pooled - FE", place(e) size(vsmall) color(gs3)) ///
       `annopts' ///
       xtitle("Association with H, points") ytitle("") ///
       legend(off) ///
       title("B. Same `nR' rental observations", size(medium)) ///
       graphregion(color(white)) plotregion(color(white)) name(gB, replace)

graph combine gA gB, rows(1) ysize(3.2) xsize(7.2) ///
      graphregion(color(white)) name(fig3, replace)
graph export "${FIG}/F03_cfps_baseline_comparison.pdf", replace
graph export "${FIG}/F03_cfps_baseline_comparison.png", replace width(2600)
display as txt "wrote F03_cfps_baseline_comparison"
