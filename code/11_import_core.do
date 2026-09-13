*! 11_import_core.do — read the analysis-ready tables written by 10_export_from_db.py
*  and check that each one arrived with the right shape.
version 17
set more off
if "${PROJ}" == "" {
    display as error "run 00_master.do first"
    exit 601
}

* Table names and the row counts the integrated database reports, in the same order.
* Two parallel lists are used on purpose: a quoted list continued with /// inside a
* local gets glued into one word, which is a trap.
local core_names "der_cfps_panel der_cfps_person_wave der_cfps_household_wave"
local core_names "`core_names' der_cgss_person_year der_chfs_household_2019"
local core_names "`core_names' der_chfs_household_2021 der_feh_respondent"
local core_names "`core_names' der_feh_community der_feh_market_exposure"
local core_names "`core_names' der_feh_rent_coverage smp_membership smp_summary"
local core_rows "166924 166924 64529 33732 34643 22027 15713 15713 94278 47139 934421 9"

local ntab : word count `core_names'
if `ntab' != `: word count `core_rows'' {
    display as error "internal error: name list and row list differ in length"
    global QA_FAILED = ${QA_FAILED} + 1
}

display as txt _n "core analysis tables"
forvalues i = 1/`ntab' {
    local tbl : word `i' of `core_names'
    local want : word `i' of `core_rows'
    capture confirm file "${DERIVED}/`tbl'.dta"
    if _rc {
        display as error "  missing ${DERIVED}/`tbl'.dta"
        global QA_FAILED = ${QA_FAILED} + 1
        continue
    }
    quietly describe using "${DERIVED}/`tbl'.dta", short
    local n = r(N)
    local k = r(k)
    if `n' != `want' {
        display as error "  `tbl' has `n' rows; the database has `want'"
        global QA_FAILED = ${QA_FAILED} + 1
    }
    else {
        display as txt "  ok  `tbl'   rows = `n'   columns = `k'"
    }
}

* ------------------------------------------------- opening one table properly
display as txt _n "opening der_cfps_panel in memory"
use "${DERIVED}/der_cfps_panel.dta", clear
quietly describe, short
display as txt "  observations = " r(N) "   variables = " r(k)

capture isid pid wave
if _rc {
    display as error "  pid + wave is not unique"
    global QA_FAILED = ${QA_FAILED} + 1
}
else display as txt "  ok  pid + wave identifies each row"

quietly count if missing(pid) | missing(wave)
if r(N) > 0 {
    display as error "  pid or wave missing in " r(N) " rows"
    global QA_FAILED = ${QA_FAILED} + 1
}

display as txt _n "person-wave observations by wave"
tabulate wave

* der_cfps_panel covers 2014, 2016, 2018, 2020 and 2022; the analysis samples
* described in the manuscript use 2014-2020 only.
display as txt _n "national housing-problem rating, 0 to 10, all waves in the panel"
summarize housing_problem_national, detail

display as txt _n "number of waves each person appears in"
quietly bysort pid: generate long n_waves_obs = _N
quietly tabulate n_waves_obs
drop n_waves_obs

display as txt _n "current tenure, pooled across all waves in the panel"
tabulate hh__tenure_group, missing
