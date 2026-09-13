*! 20_apply_labels.do — attach the variable and value labels that were read out of
*  the original survey files and stored in meta_variables / meta_value_labels.
*
*  Called by 00_master.do, which demonstrates it on der_cfps_panel. To label
*  another table, load it first and set the matching source table name:
*
*      use "${DERIVED}/src_cfps_person_2014.dta", clear
*      global LABEL_TABLE "src_cfps_person_2014"
*      do "${STATA_DIR}/20_apply_labels.do"
version 17
set more off
if "${PROJ}" == "" {
    display as error "run 00_master.do first"
    exit 601
}

foreach need in meta_variables meta_value_labels {
    capture confirm file "${DERIVED}/`need'.dta"
    if _rc {
        display as error "missing ${DERIVED}/`need'.dta"
        global QA_FAILED = ${QA_FAILED} + 1
        exit 601
    }
}

* meta_variables is the variable dictionary of the ORIGINAL survey files, so its
* labels describe the src_* mirror tables, not the derived analysis tables.
if "${LABEL_TABLE}" == "" {
    global LABEL_TABLE "src_cfps_person_2014"
    use "${DERIVED}/src_cfps_person_2014.dta", clear
    display as txt "LABEL_TABLE was not set; demonstrating on src_cfps_person_2014"
}

capture frame drop feh_lab
capture frame drop feh_vallab
frame create feh_lab
frame feh_lab: use "${DERIVED}/meta_variables.dta", clear
frame feh_lab: keep if imported_table == "${LABEL_TABLE}"
frame feh_lab: keep var_name var_label value_label_set
frame feh_lab: quietly count
local nlab = r(N)

* ------------------------------------------------------------ variable labels
local applied = 0
local sets ""
forvalues i = 1/`nlab' {
    frame feh_lab: local v = var_name[`i']
    frame feh_lab: local l = var_label[`i']
    frame feh_lab: local s = value_label_set[`i']
    capture confirm variable `v'
    if _rc == 0 {
        capture label variable `v' "`l'"
        if _rc == 0 local applied = `applied' + 1
    }
    if "`s'" != "" & "`s'" != "." {
        if strpos("|`sets'|", "|`s'|") == 0 local sets "`sets' `s'"
    }
}
display as txt "variable labels applied: `applied' of `nlab' recorded for ${LABEL_TABLE}"

* -------------------------------------------------------------- value labels
local sets = strtrim("`sets'")
if "`sets'" == "" {
    display as txt "no value label sets recorded for this table"
    exit
}

foreach s of local sets {
    capture label drop `s'
}

frame create feh_vallab
frame feh_vallab: use "${DERIVED}/meta_value_labels.dta", clear
frame feh_vallab: generate byte keepme = 0
foreach s of local sets {
    frame feh_vallab: replace keepme = 1 if label_set == "`s'"
}
frame feh_vallab: keep if keepme
frame feh_vallab: keep label_set value label
capture frame feh_vallab: destring value, replace force
frame feh_vallab: quietly count
local nval_all = r(N)

* Label sets that map one label to every person or household are identifier-like:
* they carry no information and can hold thousands of entries. Sets larger than
* 100 entries are skipped and reported rather than defined.
frame feh_vallab: bysort label_set: generate long set_size = _N
frame feh_vallab: quietly count if set_size > 100
local skipped = r(N)
frame feh_vallab: drop if set_size > 100
frame feh_vallab: drop set_size
frame feh_vallab: quietly count
local nval = r(N)
display as txt "value label entries found: `nval_all'; skipped `skipped' in identifier-like sets"

local defined = 0
forvalues i = 1/`nval' {
    frame feh_vallab: local s = label_set[`i']
    frame feh_vallab: local val = value[`i']
    frame feh_vallab: local txt = label[`i']
    if "`val'" != "" & "`val'" != "." {
        capture label define `s' `val' "`txt'", add
        if _rc == 0 local defined = `defined' + 1
    }
}
display as txt "value labels defined: `defined' of `nval' entries"

local attached = 0
forvalues i = 1/`nlab' {
    frame feh_lab: local v = var_name[`i']
    frame feh_lab: local s = value_label_set[`i']
    if "`s'" != "" & "`s'" != "." {
        capture confirm variable `v'
        if _rc == 0 {
            capture label values `v' `s'
            if _rc == 0 local attached = `attached' + 1
        }
    }
}
display as txt "value labels attached to `attached' variables"

display as txt _n "the labelled dataset now in memory"
describe, short
