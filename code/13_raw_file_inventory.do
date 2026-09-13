*! 13_raw_file_inventory.do — read the header of every original .dta recorded
*  in meta_sources and compare it with what the database recorded when the
*  files were first imported. Nothing is loaded into memory except the
*  inventory itself, so this is safe with the multi-hundred-MB raw files.
version 17
set more off
if "${PROJ}" == "" {
    display as error "run 00_master.do first"
    exit 601
}

capture confirm file "${DERIVED}/meta_sources.dta"
if _rc {
    display as error "missing ${DERIVED}/meta_sources.dta"
    global QA_FAILED = ${QA_FAILED} + 1
    exit 601
}

use "${DERIVED}/meta_sources.dta", clear
keep if strpos(lower(file_name), ".dta") > 0
keep file_name abs_path dataset survey_year size_bytes readable_status

* recorded row and variable counts, parsed out of readable_status
gen str20 rec_rows = ""
replace rec_rows = ustrregexs(1) if ustrregexm(readable_status, "n_rows=([0-9]+)")
gen str20 rec_vars = ""
replace rec_vars = ustrregexs(1) if ustrregexm(readable_status, "n_vars=([0-9]+)")
destring rec_rows, gen(rec_n) force
destring rec_vars, gen(rec_k) force

gen double n_stata = .
gen double k_stata = .
gen str24 check = ""

quietly count
local total = r(N)
display as txt "checking `total' raw .dta files recorded in meta_sources"

forvalues i = 1/`total' {
    local path = abs_path[`i']
    capture describe using "`path'", short
    if _rc == 0 {
        replace n_stata = r(N) in `i'
        replace k_stata = r(k) in `i'
        if !missing(rec_n[`i']) & rec_n[`i'] != r(N) {
            replace check = "N_MISMATCH" in `i'
        }
        else if !missing(rec_k[`i']) & rec_k[`i'] != r(k) {
            replace check = "K_MISMATCH" in `i'
        }
        else replace check = "readable" in `i'
    }
    else {
        replace check = "UNREADABLE" in `i'
    }
}

display as txt _n "result by source"
tabulate check

display as txt _n "result by survey"
tabulate dataset check, row

keep file_name abs_path dataset survey_year rec_n rec_k n_stata k_stata check
order file_name dataset check rec_n n_stata rec_k k_stata
export delimited using "${LOGS}/raw_file_inventory.csv", replace
display as txt "wrote ${LOGS}/raw_file_inventory.csv"

quietly count if check != "readable"
if r(N) > 0 {
    display as error r(N) " raw .dta file(s) did not match the recorded shape"
    global QA_FAILED = ${QA_FAILED} + 1
    list file_name check rec_n n_stata if check != "readable", noobs
}
