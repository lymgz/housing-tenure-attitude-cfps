*! 00_master.do — Stata layer for the housing-beliefs project.
*  Reads the integrated database (through the files written by
*  10_export_from_db.py) and checks every table, then reads the original
*  Chinese survey files.
*
*  How to run
*    Batch:    "<stata_installation>\StataMP-64.exe" /e do 00_master.do
*    GUI:      open this file and press Execute (Ctrl+D)
*    Working directory must be this folder, code/By_stata, or the fallback
*    project root below is used.
*
*  Before the first run:
*    python 10_export_from_db.py
*  If that has not been done, this file runs it for you, provided ${PYTHON}
*  points at an interpreter that has pandas installed.
*
*  To point somewhere else, set the globals before running:
*    global PROJ "D:/somewhere/The Folk Economics of Housing"
*    global DB   "D:/somewhere/housing_existing_data.db"
version 17
clear all
set more off
set linesize 120
set varabbrev off

* --------------------------------------------------------------- project root
local suffix "code/By_stata"
if "${PROJ}" == "" {
    local here = subinstr("`c(pwd)'", "\", "/", .)
    if strpos("`here'", "`suffix'") > 0 {
        global PROJ = subinstr("`here'", "/`suffix'", "", 1)
    }
}
    if "${PROJ}" == "" {
        display as error "PROJ is not set."
        display as error "  global PROJ \"C:/path/to/your/project/root\""
        display as error "  set it before running this file."
        exit 601
    }
global STATA_DIR "${PROJ}/code/By_stata"
* DERIVED and LOGS can be set by the caller, so that one round of output can be
* kept in its own folder. See 90_run_round.do.
if "${DERIVED}" == "" global DERIVED "${STATA_DIR}/_derived"
if "${LOGS}" == ""    global LOGS    "${STATA_DIR}/_logs"
global RAWCN     "<raw_survey_download_root>"
if "${PYTHON}" == "" {
    display as error "PYTHON is not set."
    display as error "  global PYTHON \"C:/path/to/python.exe\" (or \"python\" on PATH)"
    exit 601
}
if "${DB}" == "" {
    global DB "${PROJ}/data/route_a_existing_data/v2.1_candidate/housing_existing_data.v2.1.20260911T145919_0ef553b2.db"
}

capture mkdir "${LOGS}"
capture mkdir "${DERIVED}"
capture log close master
log using "${LOGS}/00_master.log", name(master) replace text

display as txt "project root : ${PROJ}"
display as txt "derived      : ${DERIVED}"
display as txt "database     : ${DB}"
display as txt "Stata        : `c(stata_version)' (MP=`c(MP)'), version `c(version)' rules"

* ------------------------------------------------- prerequisite: step 10 first
capture confirm file "${DERIVED}/export_manifest.csv"
if _rc {
    display as txt _n "step 10 has not run yet: export_manifest.csv is missing"
    display as txt "building the Stata files now with ${PYTHON}; about two minutes"
    display as txt "(progress is printed to the console, not into this log)"
    capture shell "${PYTHON}" "${STATA_DIR}/10_export_from_db.py" --out "${DERIVED}"
    capture confirm file "${DERIVED}/export_manifest.csv"
    if _rc {
        display as error _n "could not build the Stata files."
        display as error "run this yourself:"
        display as error "    cd ""${STATA_DIR}"""
        display as error "    python 10_export_from_db.py"
        display as error "then run 00_master.do again."
        display as txt _n "RESULT: STOPPED - nothing was checked"
        capture log close master
        exit
    }
    display as txt "step 10 finished"
}

global QA_FAILED = 0
local steps "01_setup 11_import_core 12_import_external 13_raw_file_inventory 20_apply_labels 99_qa_checks"
foreach step of local steps {
    display as txt _n "{hline 78}"
    display as txt "== `step'"
    display as txt "{hline 78}"
    capture noisily do "${STATA_DIR}/`step'.do"
    if _rc {
        display as error "STEP FAILED: `step' (rc = " _rc ")"
        global QA_FAILED = ${QA_FAILED} + 1
    }
}

display as txt _n "{hline 78}"
if ${QA_FAILED} == 0 {
    display as result "RESULT: OK - every step ran"
}
else {
    display as error "RESULT: FAILED - ${QA_FAILED} step(s) reported a problem above"
}
display as txt "log: ${LOGS}/00_master.log"
display as txt "{hline 78}"
capture log close master
