*! 01_setup.do — environment checks. Called by 00_master.do.
version 17
set more off
if "${PROJ}" == "" {
    display as error "PROJ is not set: run 00_master.do instead of this file"
    exit 601
}

display as txt "checking paths"
local problems 0

* The only hard requirement is the set of files written by step 10, because that
* is what the Stata scripts actually read.
capture confirm file "${DERIVED}/export_manifest.csv"
if _rc {
    display as error "  missing: ${DERIVED}/export_manifest.csv"
    local problems = `problems' + 1
}
else display as txt "  ok: ${DERIVED}/export_manifest.csv"

* Informational from here on. The database is read by step 10 only; the scripts
* in this folder never open it.
capture confirm file "${DB}"
if _rc display as txt "  note: no database at ${DB} (only step 10 needs it)"
else display as txt "  ok: ${DB}"

* The original survey files are not opened directly either: step 13 re-reads the
* paths recorded in meta_sources. Missing files therefore show up there as
* UNREADABLE rather than as a hard stop here.
* Note: confirm dir is not used, because on Windows it misreports any folder
* whose path contains non-ASCII characters. A file inside the folder is checked
* instead.
foreach probe in "${PROJ}/code/route_a_stage2/scripts/run_stage2.py" ///
        "${RAWCN}/cfps数据集/2010/cfps2010famecon_201906.dta" ///
        "${RAWCN}/CGSS原始数据/CGSS2015/CGSS2015.dta" ///
        "${RAWCN}/chfs原始数据/2019/chfs2019_hh_202112.dta" {
    capture confirm file "`probe'"
    if _rc display as txt "  note: not found: `probe'"
    else display as txt "  ok: `probe'"
}

if `problems' > 0 {
    display as error _n "`problems' problem(s); run this first: python 10_export_from_db.py"
    exit 601
}

quietly count
display as txt "Stata version `c(version)', data in memory: " r(N) " observations"
