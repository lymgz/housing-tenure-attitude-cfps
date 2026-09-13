*! 12_import_external.do — read the external US tables (ACS, Zillow, Apartment
*  List, BPS, WRLURI) plus the ZIP geography and the ACS reference shells.
version 17
set more off
if "${PROJ}" == "" {
    display as error "run 00_master.do first"
    exit 601
}

local ext_names "ext_us_acs5 ext_us_acs5_files ext_us_apartmentlist_month"
local ext_names "`ext_names' ext_us_bps_county_year ext_us_wrluri2020"
local ext_names "`ext_names' ext_us_zillow_versions ext_us_zillow_zip_meta"
local ext_names "`ext_names' ext_us_zillow_zip_month geo_uszips geo_zip_county"
local ext_names "`ext_names' ref_acs_jam_values ref_acs_open_interval_rules ref_acs_table_shells"
local ext_rows "6659055 36 359775 96992 2844 4 67434 5887296 33120 54262 122 9 180"

local ntab : word count `ext_names'
if `ntab' != `: word count `ext_rows'' {
    display as error "internal error: name list and row list differ in length"
    global QA_FAILED = ${QA_FAILED} + 1
}

* Only the headers are read here, which is enough to confirm the big Zillow and
* ACS tables arrived intact without loading millions of rows.
display as txt _n "external tables"
forvalues i = 1/`ntab' {
    local tbl : word `i' of `ext_names'
    local want : word `i' of `ext_rows'
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

display as txt _n "opening ext_us_bps_county_year, county building permits"
use "${DERIVED}/ext_us_bps_county_year.dta", clear
quietly describe, short
display as txt "  observations = " r(N) "   variables = " r(k)
summarize

display as txt _n "opening geo_zip_county, ZIP to county crosswalk"
use "${DERIVED}/geo_zip_county.dta", clear
quietly describe, short
display as txt "  observations = " r(N) "   variables = " r(k)

display as txt _n "opening ext_us_wrluri2020, land-use regulation index"
use "${DERIVED}/ext_us_wrluri2020.dta", clear
quietly describe, short
display as txt "  observations = " r(N) "   variables = " r(k)
