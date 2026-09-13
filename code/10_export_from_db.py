"""Export the integrated housing-beliefs database to Stata-readable .dta files.

Path resolution
------------
The project root is resolved in this order:
  1. environment variable FELT_PROJ, if set;
  2. the parent of the parent of this file (assumes this script lives at
     <project_root>/code/By_stata/10_export_from_db.py);
  3. otherwise, raise FileNotFoundError. Set FELT_PROJ to your project root.
"""

from __future__ import annotations

import argparse
import hashlib
import re
import sqlite3
import sys
from pathlib import Path

import numpy as np
import pandas as pd

PROJ = Path(os.environ["FELT_PROJ"]) if os.environ.get("FELT_PROJ") else Path(__file__).resolve().parents[2]
DEFAULT_DB = PROJ / "data/route_a_existing_data/v2.1.candidate/housing_existing_data.v2.1.db"
TIER_PREFIX = {
    "core": ("der_", "smp_"),
    "raw": ("src_",),
    "external": ("ext_",),
    "geo": ("geo_",),
    "ref": ("ref_",),
    "meta": ("meta_", "audit_"),
}

# Stata 14+ .dta format: Unicode strings, variable names up to 32 characters.
STATA_FORMAT = 118
STATA_NAME_MAX = 32
RESERVED = {
    "_all", "_b", "_coef", "_cons", "_merge", "_n", "_N", "_pi", "_pred", "_rc",
    "_se", "_skip", "byte", "double", "float", "if", "in", "int", "long",
    "strL", "using", "with",
}


def sha256_file(path: Path, chunk: int = 8 << 20) -> str:
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for block in iter(lambda: handle.read(chunk), b""):
            digest.update(block)
    return digest.hexdigest()


def safe_names(columns) -> tuple[list[str], dict[str, str]]:
    """Return Stata-legal column names plus a map of the ones that changed."""
    used: set[str] = set()
    new_names: list[str] = []
    renamed: dict[str, str] = {}
    for original in columns:
        name = re.sub(r"[^0-9A-Za-z_]", "_", str(original))
        if not name or name[0].isdigit() or name in RESERVED or name[0] == "_":
            name = "v" + name
        if len(name) > STATA_NAME_MAX:
            tail = hashlib.sha1(str(original).encode("utf-8")).hexdigest()[:6]
            name = name[: STATA_NAME_MAX - 7] + "_" + tail
        base, counter = name, 1
        while name in used:
            counter += 1
            suffix = f"_{counter}"
            name = base[: STATA_NAME_MAX - len(suffix)] + suffix
        used.add(name)
        if name != str(original):
            renamed[str(original)] = name
        new_names.append(name)
    return new_names, renamed


def coerce_columns(frame: pd.DataFrame, declared: dict[str, str] | None = None) -> pd.DataFrame:
    """Make column dtypes acceptable to ``to_stata`` without losing information."""
    out = frame.copy()
    declared = declared or {}
    for column in out.columns:
        series = out[column]
        if isinstance(series.dtype, pd.CategoricalDtype):
            series = series.astype(object)
        if pd.api.types.is_datetime64_any_dtype(series):
            continue  # to_stata writes these as %tc
        if pd.api.types.is_bool_dtype(series):
            out[column] = series.astype("float64")
            continue
        if pd.api.types.is_numeric_dtype(series):
            # pandas nullable dtypes (Int64, Float64) break to_stata; plain floats do not.
            out[column] = pd.to_numeric(series, errors="coerce").astype("float64")
            continue
        if series.dtype != object:
            series = series.astype(object)
        if bool(series.isna().all()):
            # An empty column has no values that reveal its type, so fall back to
            # the type SQLite declares for it.
            if "TEXT" in str(declared.get(column, "")).upper():
                out[column] = pd.Series("", index=out.index, dtype=object)
            else:
                out[column] = pd.Series(np.nan, index=out.index, dtype="float64")
            continue
        present = series[~series.isna()]
        decoded = [
            value.decode("utf-8", "replace") if isinstance(value, (bytes, bytearray)) else value
            for value in present
        ]
        if all(isinstance(value, str) for value in decoded):
            continue  # object array of str/None, which to_stata accepts as is
        numeric = pd.to_numeric(pd.Series(decoded, index=present.index), errors="coerce")
        if bool(numeric.notna().all()):
            out[column] = pd.to_numeric(series, errors="coerce").astype("float64")
        else:
            out[column] = series.map(
                lambda value: None if value is None else str(value)
            ).astype(object)
    return out


def list_tables(connection: sqlite3.Connection) -> list[str]:
    rows = connection.execute(
        "select name from sqlite_master where type = 'table' order by name"
    )
    return [row[0] for row in rows]


def tier_of(table: str) -> str:
    for tier, prefixes in TIER_PREFIX.items():
        if table.startswith(prefixes):
            return tier
    return "other"


def export_table(connection, table: str, out_dir: Path, limit: int | None) -> dict:
    declared = {
        row[1]: row[2] or "" for row in connection.execute(f'PRAGMA table_info("{table}")')
    }
    sql = f'select * from "{table}"'
    if limit:
        sql += f" limit {int(limit)}"
    frame = pd.read_sql_query(sql, connection)
    names, renamed = safe_names(frame.columns)
    declared = {renamed.get(key, key): value for key, value in declared.items()}
    frame.columns = names
    frame = coerce_columns(frame, declared)
    path = out_dir / f"{table}.dta"
    frame.to_stata(path, write_index=False, version=STATA_FORMAT)
    return {
        "table": table,
        "tier": tier_of(table),
        "n_rows": int(len(frame)),
        "n_cols": int(frame.shape[1]),
        "n_renamed_cols": len(renamed),
        "renamed_cols": ";".join(f"{k}->{v}" for k, v in renamed.items()),
        "file": path.name,
        "size_bytes": path.stat().st_size,
        "sha256": sha256_file(path),
    }


def parse_args(argv=None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--db", default=str(DEFAULT_DB), help="integrated database (read-only)")
    parser.add_argument("--out", default=None, help="output folder (default: ./_derived)")
    parser.add_argument("--tier", nargs="*", choices=sorted(TIER_PREFIX), default=None,
                        help="export only these tiers (default: all)")
    parser.add_argument("--tables", nargs="*", default=None, help="export only these tables")
    parser.add_argument("--limit", type=int, default=None, help="row limit per table (smoke runs)")
    parser.add_argument("--no-db-hash", action="store_true", help="skip hashing the 1.4 GB database")
    return parser.parse_args(argv)


def main(argv=None) -> int:
    args = parse_args(argv)
    db_path = Path(args.db)
    if not db_path.is_file():
        print(f"ERROR: database not found: {db_path}", file=sys.stderr)
        return 2
    out_dir = Path(args.out) if args.out else Path(__file__).resolve().parent / "_derived"
    out_dir.mkdir(parents=True, exist_ok=True)

    uri = "file:" + db_path.as_posix() + "?mode=ro"
    connection = sqlite3.connect(uri, uri=True)
    try:
        tables = list_tables(connection)
        if args.tables:
            wanted = [t for t in tables if t in set(args.tables)]
            missing = sorted(set(args.tables) - set(tables))
            if missing:
                print(f"WARNING: not in database: {missing}", file=sys.stderr)
        else:
            keep = set(sum((TIER_PREFIX[t] for t in (args.tier or TIER_PREFIX)), ()))
            wanted = [t for t in tables if t.startswith(tuple(keep))]

        print(f"database : {db_path}")
        print(f"output   : {out_dir}")
        print(f"tables   : {len(wanted)} of {len(tables)}")
        db_hash = "" if args.no_db_hash else sha256_file(db_path)
        rows: list[dict] = []
        for index, table in enumerate(wanted, start=1):
            info = export_table(connection, table, out_dir, args.limit)
            info["source_db"] = str(db_path)
            info["source_db_sha256"] = db_hash
            info["row_limit"] = args.limit or ""
            rows.append(info)
            print(f"  [{index:>3}/{len(wanted)}] {table:44s} "
                  f"{info['n_rows']:>9,d} rows  {info['n_cols']:>3} cols")
    finally:
        connection.close()

    manifest = out_dir / "export_manifest.csv"
    pd.DataFrame(rows).to_csv(manifest, index=False, encoding="utf-8")
    print(f"\nwrote {len(rows)} .dta files and {manifest.name}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
