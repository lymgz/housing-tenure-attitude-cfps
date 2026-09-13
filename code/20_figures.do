*! 20_figures.do — build the manuscript figures from the frozen analysis output.
*
*  Stata is a plotting engine here: it reads the .dta files written by
*  15_export_estimates.py plus the panel data in the round folder. No model is
*  re-estimated, so the figures cannot drift away from the tables.
*
*  Usage:
*      do "${STATA_DIR}/20_figures.do"                       (default round)
*      do "${STATA_DIR}/20_figures.do" runs/figdev           (another round)
version 17
clear all
set more off

* --------------------------------------------------------------- paths
if "${PROJ}" == "" {
    local suffix "code/By_stata"
    local here = subinstr("`c(pwd)'", "\", "/", .)
    if strpos("`here'", "`suffix'") > 0 {
        global PROJ = subinstr("`here'", "/`suffix'", "", 1)
    }
}
if "${PROJ}" == "" {
    display as error "PROJ is not set and the working directory is not code/By_stata."
    display as error "  global PROJ ""D:/path/to/your/project/root"""
    exit 601
}
global STATA_DIR "${PROJ}/code/By_stata"

local round "runs/20260912_supplement"
if "`1'" != "" local round "`1'"
global R   "${STATA_DIR}/`round'"
global FIG "${R}/figures"

capture mkdir "${FIG}"
display as txt "round  : ${R}"
display as txt "figures: ${FIG}"

foreach need in "estimates" "derived" {
    capture confirm file "${R}/`need'/.keep"
    capture confirm file "${R}/`need'/smp_summary.dta"
    capture confirm file "${R}/`need'/estimates_manifest.csv"
}
capture confirm file "${R}/estimates/cfps_coefficients.dta"
if _rc {
    display as error "missing ${R}/estimates/*.dta"
    display as error "run first:  python 15_export_estimates.py --round `round'"
    exit 601
}

global FIG_FAILED = 0
foreach step in 21_fig_measurement 22_fig_main_results 23_fig_restriction_ladder ///
        24_fig_item_specificity 25_fig_us_gap 26_fig_baseline_comparison {
    display as txt _n "{hline 78}"
    display as txt "== `step'"
    display as txt "{hline 78}"
    capture noisily do "${STATA_DIR}/`step'.do"
    if _rc {
        display as error "FIGURE FAILED: `step' (rc = " _rc ")"
        global FIG_FAILED = ${FIG_FAILED} + 1
    }
}

display as txt _n "{hline 78}"
if ${FIG_FAILED} == 0 {
    display as result "RESULT: OK - every figure was written to ${FIG}"
}
else {
    display as error "RESULT: FAILED - ${FIG_FAILED} figure script(s) errored"
}
display as txt "{hline 78}"
