*! 99_qa_checks.do — assertions on the numbers the manuscript depends on.
version 17
set more off
if "${PROJ}" == "" {
    display as error "run 00_master.do first"
    exit 601
}

* ------------------------------------------------------------ CFPS panel
use "${DERIVED}/der_cfps_panel.dta", clear
quietly count
if r(N) != 166924 {
    display as error "der_cfps_panel: " r(N) " rows, expected 166924"
    global QA_FAILED = ${QA_FAILED} + 1
}
else display as txt "ok  der_cfps_panel has 166,924 person-waves"

capture isid pid wave
if _rc {
    display as error "der_cfps_panel: pid+wave is not unique"
    global QA_FAILED = ${QA_FAILED} + 1
}

* The integrated panel covers 2014-2022; the analysis samples use 2014-2020.
quietly levelsof wave, local(waves) clean
if "`waves'" != "2014 2016 2018 2020 2022" {
    display as error "der_cfps_panel: unexpected waves: `waves'"
    global QA_FAILED = ${QA_FAILED} + 1
}
else display as txt "ok  waves are `waves'"

quietly count if !missing(housing_problem_national) & ///
    (housing_problem_national < 0 | housing_problem_national > 10)
if r(N) > 0 {
    display as error "housing_problem_national outside 0-10 in " r(N) " rows"
    global QA_FAILED = ${QA_FAILED} + 1
}
else display as txt "ok  housing_problem_national stays inside 0-10"

* ------------------------------------------------- analysis sample registry
use "${DERIVED}/smp_summary.dta", clear
quietly count
display as txt _n "registered samples (smp_summary)"
list sample_id n_included n_distinct_units, noobs

use "${DERIVED}/smp_membership.dta", clear
keep if sample_id == "cfps_fe_tenure" & included == 1
quietly count
if r(N) != 102103 {
    display as error "cfps_fe_tenure: " r(N) " included units, expected 102103"
    global QA_FAILED = ${QA_FAILED} + 1
}
else display as txt "ok  cfps_fe_tenure carries 102,103 included person-waves"

* --------------------------------------------------------------- US surveys
use "${DERIVED}/der_feh_respondent.dta", clear
quietly count
if r(N) != 15713 {
    display as error "der_feh_respondent: " r(N) " rows, expected 15713"
    global QA_FAILED = ${QA_FAILED} + 1
}
else display as txt "ok  der_feh_respondent has 15,713 respondents"

* ------------------------------------------------------- original raw files
capture confirm file "${LOGS}/raw_file_inventory.csv"
if _rc == 0 {
    import delimited using "${LOGS}/raw_file_inventory.csv", clear varnames(1) case(preserve)
    quietly count if check != "readable"
    local bad = r(N)
    quietly count
    display as txt "raw .dta inventory: " r(N) " files, `bad' not readable/matching"
    if `bad' > 0 {
        global QA_FAILED = ${QA_FAILED} + 1
    }
}
else {
    display as error "raw file inventory missing; 13_raw_file_inventory.do did not run"
    global QA_FAILED = ${QA_FAILED} + 1
}

display as txt _n "accumulated failure count: ${QA_FAILED}"
