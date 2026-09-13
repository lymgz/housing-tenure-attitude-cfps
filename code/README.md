# Stata layer — code/By_stata

Reads the project data in Stata. The Python pipeline in code/route_a_stage2 stays the
reference implementation; this folder is a parallel Stata path for inspection,
teaching, and referee requests.

## 1. How to run

Two steps, in this order.

Step 1 — build the Stata files from the integrated database (once per data change).
00_master.do runs this for you if it has not been done, so you can skip straight to
step 2 and let it happen; the manual command is:

    conda activate lym313
    cd "C:\bgy\C-documents\碧桂园\综合管理\职称\博士相关\UPM\The Folk Economics of Housing\code\By_stata"
    python 10_export_from_db.py

Step 2 — run the Stata scripts:

    cd "...\code\By_stata"
    & "C:\Softwares\Stata18\StataMP-64.exe" /e do 00_master.do

In the Stata GUI, open 00_master.do and press Execute (Ctrl+D).
The log is _logs/00_master.log.

## 2. Files

| file | what it does |
|---|---|
| 00_master.do | sets the paths, opens the log, runs every step below, reports failures |
| 01_setup.do | checks the database, the exported files and the raw survey folders exist |
| 10_export_from_db.py | reads the integrated database read-only and writes one .dta per table into _derived/ |
| 11_import_core.do | reads the analysis-ready tables (CFPS panel, samples, CGSS, CHFS, FEH) and checks row counts |
| 12_import_external.do | reads the external tables (ACS, Zillow, Apartment List, BPS, WRLURI, ZIP geography) |
| 13_raw_file_inventory.do | reads the header of all 152 original .dta survey files and compares them with what the database recorded |
| 20_apply_labels.do | attaches the Chinese variable and value labels recovered from the original files |
| 99_qa_checks.do | assertions on the numbers the manuscript uses (row counts, unique keys, value ranges) |

Generated files: _derived/*.dta and _derived/export_manifest.csv (never committed,
because .gitignore excludes *.dta and *.csv), _logs/*.log, and
_logs/raw_file_inventory.csv.

## 3. Where the data comes from

    original survey files                    integrated database               Stata
    C:\Downloads\BaiduNetdiskDownload\
      cfps数据集\2010 ... 2022        \
      CGSS原始数据\                    >  housing_existing_data.v2.1.db  >  _derived\*.dta
      chfs原始数据\                   /   (read-only, 72 tables)             (one per table)

The database is opened with mode=ro. Nothing in this folder writes to it. Its build
stamp, provenance and known limitations are documented in
data/route_a_existing_data/v2.1_candidate/README.md.

## 4. Table tiers

| tier | tables | contents |
|---|---|---|
| core | der_, smp_ | analysis-ready CFPS / CGSS / CHFS / FEH tables and sample flags |
| raw | src_ | variables imported from the original survey files |
| external | ext_ | ACS, Zillow, Apartment List, BPS, WRLURI |
| geo | geo_ | ZIP and ZIP-to-county crosswalks |
| ref | ref_ | ACS jam-value and table-shell reference files |
| meta | meta_, audit_ | provenance, variable dictionary, audit trail |

Useful options:

    python 10_export_from_db.py --tier core meta       # only these tiers
    python 10_export_from_db.py --tables der_cfps_panel
    python 10_export_from_db.py --limit 5000           # smoke run
    python 10_export_from_db.py --out D:/somewhere     # different output folder

## 4b. Keeping one round of output in its own folder

To run everything and leave this round apart from the default `_derived` folder:

```stata
global ROUND "20260912_supplement"
do "${STATA_DIR}/90_run_round.do"
```

or in one line, with the name as an argument:

```stata
do "${STATA_DIR}/90_run_round.do" 20260912_supplement
```

That writes `code/By_stata/runs/<ROUND>/derived/` (the `.dta` files plus
`export_manifest.csv`) and `runs/<ROUND>/logs/` (the master log, the raw-file
inventory and `round_info.txt`, which records the database path and its hash and
the number of failures). Nothing else in the project is touched.

## 5. Things that will bite you

1. Stata cannot read SQLite. Step 1 is not optional.
2. Batch mode writes the log into the working directory, not next to the do-file.
   Run Stata from this folder, as in step 2, or the log lands somewhere else.
3. c(filename) is empty in batch mode and Stata does not resolve ".." inside paths.
   That is why 00_master.do decides the project root from the working directory in one
   place, with one documented fallback. To use a different checkout, run from this
   folder or set the globals first:

       global PROJ "D:/somewhere/The Folk Economics of Housing"
       global DB   "D:/somewhere/housing_existing_data.db"
       do "D:/somewhere/code/By_stata/00_master.do"

4. Variable names longer than 32 characters exist in three tables
   (der_feh_community, der_cgss_person_year, der_chfs_household_2019). The exporter
   shortens them and records every rename in _derived/export_manifest.csv under
   renamed_cols, so nothing is lost.
5. A column that is empty in the source keeps the type SQLite declares for it: TEXT
   becomes an empty string, anything else becomes numeric missing.
6. The master turns variable abbreviation off (set varabbrev off), so
   hh__tenure_group cannot be matched by an ambiguous abbreviation.
7. confirm dir misreports any folder whose path contains non-ASCII characters on
   Windows, so the scripts test a file inside a folder instead. This is why
   01_setup.do never says a Chinese-named folder is missing.
8. 00_master.do does not set a shell exit code. Read the last line of
   _logs/00_master.log: it reads RESULT: OK or RESULT: FAILED.

## 6. Scope

These scripts read and check data. They deliberately contain no estimation: the models,
the figures and every number in the manuscript are produced by code/route_a_stage2 and
its revisions. Adding a model here means the manuscript and the Stata output can
disagree, which is the failure mode this folder is meant to avoid.
