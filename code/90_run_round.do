*! 90_run_round.do — run everything and keep this round of output in its own folder.
*
*  Usage:
*      global ROUND "20260912_supplement"
*      do "${STATA_DIR}/90_run_round.do"
*  or, in one line, with the round name as an argument:
*      do "${STATA_DIR}/90_run_round.do" 20260912_supplement
*
*  With ROUND unset a dated folder name is used. The round folder holds
*      derived/   the .dta files and export_manifest.csv
*      logs/      the master log, the raw-file inventory and round_info.txt
*  and nothing else in the project is written to.
version 17
clear all
set more off

* The path block below mirrors 00_master.do: with ROUND set before this file is
* run, STATA_DIR has to be known, so allow the caller to set PROJ as well.
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

if "`1'" != "" global ROUND "`1'"
if "${ROUND}" == "" {
    local stamp = subinstr("`c(current_date)'", " ", "_", .)
    local clock = subinstr("`c(current_time)'", ":", "", .)
    global ROUND "run_`stamp'_`clock'"
}
global ROUND_DIR "${STATA_DIR}/runs/${ROUND}"
global DERIVED   "${ROUND_DIR}/derived"
global LOGS      "${ROUND_DIR}/logs"
global RAWCN     "<raw_survey_download_root>"
if "${DB}" == "" {
    global DB "${PROJ}/data/route_a_existing_data/v2.1_candidate/housing_existing_data.v2.1.20260911T145919_0ef553b2.db"
}
if "${PYTHON}" == "" {
    display as error "PYTHON is not set."
    display as error "  global PYTHON \"C:/path/to/python.exe\" (or \"python\" on PATH)"
    exit 601
}
* Stata's mkdir does not create intermediate folders, so build the path one
* level at a time, then prove the log folder is writable before going on.
foreach dir in "${STATA_DIR}/runs" "${ROUND_DIR}" "${DERIVED}" "${LOGS}" {
    capture mkdir "`dir'"
}
capture file close dirprobe
capture file open dirprobe using "${LOGS}/_write_test.txt", write text replace
local write_rc = _rc
capture file close dirprobe
capture erase "${LOGS}/_write_test.txt"
if `write_rc' {
    display as error "cannot write into ${LOGS}; the folder could not be created"
    exit 603
}

display as txt "round        : ${ROUND}"
display as txt "round folder : ${ROUND_DIR}"

do "${STATA_DIR}/00_master.do"

* ------------------------------------------------------------ round summary
capture file close roundinfo
file open roundinfo using "${LOGS}/round_info.txt", write text replace
file write roundinfo "round        : ${ROUND}" _n
file write roundinfo "created      : `c(current_date)' `c(current_time)'" _n
file write roundinfo "project      : ${PROJ}" _n
file write roundinfo "database     : ${DB}" _n
file write roundinfo "derived      : ${DERIVED}" _n
file write roundinfo "logs         : ${LOGS}" _n
file write roundinfo "stata        : `c(stata_version)' (MP=`c(MP)'), version `c(version)' rules" _n
file write roundinfo "failures     : ${QA_FAILED}" _n
file close roundinfo
display as txt "round info   : ${LOGS}/round_info.txt"
