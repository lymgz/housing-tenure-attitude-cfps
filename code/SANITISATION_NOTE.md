# Stata layer (sanitised)

This is a publishable copy of the Stata pipeline under code/By_stata/.
What was redacted from the working copy before this package was built:

  - 20_figures.log, 90_run_round.log, __pycache__/, _derived/, _logs/, runs/:
    intermediate output and Python bytecode; the logs contain the
    author's home / Windows-username paths and were dropped.

  - README.md and the .do scripts had hardcoded fallbacks for the
    project root, the Stata and Miniconda install paths, and the
    raw-survey download root (a personal cloud-disk folder). Those are
    now placeholder paths. The package aborts on launch until you set
    the global PROJ (and PYTHON) at the top of your do-file.

  - 10_export_from_db.py used to have an absolute DEFAULT_DB. It now
    honours the FELT_PROJ environment variable and otherwise derives the
    project root from this file's location.

Run instructions are in README.md inside this folder.
