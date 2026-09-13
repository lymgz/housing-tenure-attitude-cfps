#!/usr/bin/env python
"""Export the analysis result files as Stata .dta so 20_figures.do can plot them.

The Stata figure scripts must plot the same numbers the tables report. Re-running
the models in Stata would create a second source of truth, so instead this script
converts the frozen analysis outputs into .dta and Stata acts as the plotting
engine only.

Usage (from code/By_stata):
    python 15_export_estimates.py --round runs/20260912_supplement
    python 15_export_estimates.py --round runs/20260912_supplement --check

Writes <round>/estimates/*.dta plus estimates_manifest.csv.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import math
import sys
from pathlib import Path

import numpy as np
import pandas as pd

HERE = Path(__file__).resolve().parent
PROJ = Path(os.environ["FELT_PROJ"]) if os.environ.get("FELT_PROJ") else Path(__file__).resolve().parents[2]
S2 = (PROJ / "docs/Pilot study_3/analysis/outputs/existing_data_comparison/stage2"
             / "20260911T1930_stage2_rev1/public/results")
REV = PROJ / "docs/Pilot study_3/analysis/major_revision_20260912"

# target .dta name -> source csv
SOURCES = {
    "cfps_coefficients": S2 / "cfps_coefficients.csv",
    "cfps_model_stats": S2 / "cfps_model_stats.csv",
    "specificity_coefficients": S2 / "specificity_coefficients.csv",
    "specificity_tests": S2 / "specificity_results.csv",
    "item_specificity": REV / "A5_item_specificity/item_specificity_coefficients.csv",
    "construct_validity": REV / "outputs/c5_decomposition_coefficients.csv",
    "attrition_by_tenure": REV / "A1_attrition/attrition_by_tenure.csv",
    "ipw_model_comparison": REV / "A1_attrition/ipw_model_comparison.csv",
    "mde_table": REV / "A2_rent_equivalence/mde_table.csv",
    "tost_table": REV / "A2_rent_equivalence/tost_results.csv",
    "us_gap_distribution": REV / "A4_gap/gap_distribution.csv",
    "us_gap_tenure_difference": REV / "A4_gap/gap_tenure_difference.csv",
}

# The tenure estimation sample is not a table in the database: its membership
# lives in the frozen stage-2 sample file. The within-person-change figure needs
# it, because the change is defined on that sample.
S2_PRIVATE = (PROJ / "docs/Pilot study_3/analysis/outputs/existing_data_comparison/stage2"
                     / "20260911T1930_stage2_rev1/private/samples")
EXPECTED_ADJACENT_PAIRS = 61141
EXPECTED_RENT_PAIRS = 1348
EXPECTED_RENT_PERSON_WAVES = 2716
# Two-sided 0.975 and 80 per-cent power quantiles at the frozen df=152, taken from
# A2_rent_equivalence/mde_table.csv so the MDE arithmetic here matches that file.
T_0975_152 = 1.9756939278061865
T_080_152 = 0.8439923719239055


def _p_value(t: float, df: int) -> float:
    """Two-sided and one-sided t tail without scipy (Stata's ttail, to 1e-15)."""
    import math

    # regularised incomplete beta via continued fraction (Numerical Recipes betacf)
    def betacf(a: float, b: float, x: float) -> float:
        tiny = 1e-300
        qab, qap, qam = a + b, a + 1.0, a - 1.0
        c, d = 1.0, 1.0 - qab * x / qap
        if abs(d) < tiny:
            d = tiny
        d = 1.0 / d
        h = d
        for m in range(1, 300):
            m2 = 2 * m
            aa = m * (b - m) * x / ((qam + m2) * (a + m2))
            d = 1.0 + aa * d
            if abs(d) < tiny:
                d = tiny
            c = 1.0 + aa / c
            if abs(c) < tiny:
                c = tiny
            d = 1.0 / d
            h *= d * c
            aa = -(a + m) * (qab + m) * x / ((a + m2) * (qap + m2))
            d = 1.0 + aa * d
            if abs(d) < tiny:
                d = tiny
            c = 1.0 + aa / c
            if abs(c) < tiny:
                c = tiny
            d = 1.0 / d
            delta = d * c
            h *= delta
            if abs(delta - 1.0) < 3e-16:
                break
        return h

    def betai(a: float, b: float, x: float) -> float:
        if x <= 0.0:
            return 0.0
        if x >= 1.0:
            return 1.0
        lbeta = math.lgamma(a + b) - math.lgamma(a) - math.lgamma(b) + a * math.log(x) + b * math.log1p(-x)
        if x < (a + 1.0) / (a + b + 2.0):
            return math.exp(lbeta) * betacf(a, b, x) / a
        return 1.0 - math.exp(lbeta) * betacf(b, a, 1.0 - x) / b

    return betai(df / 2.0, 0.5, df / (df + t * t))


def _upper_tail(t: float, df: int) -> float:
    """P(T_df > t)."""
    return 0.5 * _p_value(t, df) if t >= 0 else 1.0 - 0.5 * _p_value(t, df)


def _lower_tail(t: float, df: int) -> float:
    """P(T_df < t), evaluated without subtracting from one so small tails stay exact."""
    return 1.0 - 0.5 * _p_value(t, df) if t >= 0 else 0.5 * _p_value(t, df)


def rent_scaled_contrasts() -> pd.DataFrame:
    """The prespecified +10 per cent contrast and three same-model scaled contrasts.

    Every row is the SAME frozen baseline log-rent coefficient multiplied by log(1+c).
    No model is re-estimated: the coefficient, its standard error and the degrees of
    freedom come from A2_rent_equivalence/rent_model_replication.csv, and the +10 per
    cent and doubling rows are checked against the frozen mde_table.csv rows.
    Equivalence flags reuse the frozen TOST arithmetic (two one-sided tests against
    0.05 and 0.10 within-person SD of H, rent sample).
    """
    replication = REV / "A2_rent_equivalence/rent_model_replication.csv"
    mde = REV / "A2_rent_equivalence/mde_table.csv"
    rep = pd.read_csv(replication)
    baseline = rep[(rep["model"].str.startswith("P1")) & (rep["term"] == "ln_rent")]
    if len(baseline) != 1:
        raise SystemExit(f"expected one frozen ln_rent row, found {len(baseline)}")
    b = float(baseline["estimate"].iloc[0])
    se = float(baseline["se"].iloc[0])
    df = int(baseline["df"].iloc[0])
    n_obs = int(baseline["n_obs"].iloc[0])
    n_persons = int(baseline["n_persons"].iloc[0])
    n_psu = int(baseline["n_psu"].iloc[0])

    mde_frame = pd.read_csv(mde)
    within = mde_frame[mde_frame["sd_type"] == "within"]
    sd_within = float(within["sd_value"].iloc[0])
    frozen = {(bool(r["preset"]), round(float(r["estimate_scaled"]), 12)): r for _, r in within.iterrows()}

    rows = []
    for pct, prespecified in ((0.10, True), (0.25, False), (0.50, False), (1.00, False)):
        k = math.log(1.0 + pct)
        est, se_scaled = b * k, se * k
        lo, hi = est - T_0975_152 * se_scaled, est + T_0975_152 * se_scaled
        mde_points = (T_0975_152 + T_080_152) * se_scaled
        row = {"contrast": ("+10%" if pct == 0.10 else "+25%" if pct == 0.25 else
                            "+50%" if pct == 0.50 else "doubling"),
               "pct": pct, "scale_ln1p": k, "prespecified": int(prespecified),
               "estimate": est, "se": se_scaled, "ci_lo": lo, "ci_hi": hi,
               "df": df, "t0975": T_0975_152, "mde_points": mde_points,
               "sd_within": sd_within, "bound_05_sd": 0.05 * sd_within, "bound_10_sd": 0.10 * sd_within,
               "baseline_beta": b, "baseline_se": se, "n_obs": n_obs, "n_persons": n_persons, "n_psu": n_psu}
        for tag, bound in (("05", 0.05 * sd_within), ("10", 0.10 * sd_within)):
            t_lower = (est + bound) / se_scaled          # H0: effect <= -bound
            t_upper = (est - bound) / se_scaled          # H0: effect >= +bound
            p_lower = _upper_tail(t_lower, df)           # reject when t_lower is large positive
            p_upper = _lower_tail(t_upper, df)           # reject when t_upper is large negative
            p_tost = max(p_lower, p_upper)
            row[f"t_lower_{tag}"] = t_lower
            row[f"t_upper_{tag}"] = t_upper
            row[f"p_lower_{tag}"] = p_lower
            row[f"p_upper_{tag}"] = p_upper
            row[f"p_tost_{tag}"] = p_tost
            row[f"equivalent_{tag}"] = int(mde_points < bound and p_tost < 0.05)
        # cross-check the two rows that exist in the frozen file
        match = frozen.get((prespecified, round(est, 12)))
        if match is not None:
            for column, mine in (("estimate_scaled", est), ("se_scaled", se_scaled),
                                 ("ci95_lo", lo), ("ci95_hi", hi), ("mde_points", mde_points)):
                if abs(float(match[column]) - mine) > 1e-12:
                    raise SystemExit(f"scaled contrast disagrees with the frozen {column}: "
                                     f"{float(match[column])!r} vs {mine!r}")
        rows.append(row)
    frame = pd.DataFrame(rows)

    # Guard: the frozen TOST file contains the +10 per cent and doubling rows. Recompute them
    # here from the baseline coefficient and the within-person SD, and refuse to write anything
    # if the arithmetic or the equivalence decision disagrees with that file.
    tost = pd.read_csv(REV / "A2_rent_equivalence/tost_results.csv")
    tost = tost[tost["sd_type"] == "within"]
    for _, ref in tost.iterrows():
        tag = "05" if abs(float(ref["bound_in_sd"]) - 0.05) < 1e-12 else "10"
        # match on the scaled estimate, not on the preset flag: three contrasts are not prespecified
        match = frame[(frame["estimate"] - float(ref["estimate_scaled"])).abs() < 1e-12]
        if len(match) != 1:
            raise SystemExit(f"cannot match the frozen TOST row {ref['scale']!r} to a scaled contrast")
        mine = match.iloc[0]
        for column, key in (("t_lower", f"t_lower_{tag}"), ("t_upper", f"t_upper_{tag}"),
                            ("p_lower", f"p_lower_{tag}"), ("p_upper", f"p_upper_{tag}"),
                            ("p_tost", f"p_tost_{tag}")):
            if key not in mine.index:
                continue
            if not math.isclose(float(ref[column]), float(mine[key]), rel_tol=1e-6, abs_tol=1e-300):
                raise SystemExit(f"TOST {column} disagrees with tost_results.csv for "
                                 f"{ref['scale']!r} at bound {tag}: "
                                 f"{float(ref[column])!r} vs {float(mine[key])!r}")
        if int(ref["equivalent_at_0.05"]) != int(mine[f"equivalent_{tag}"]):
            raise SystemExit(f"equivalence flag disagrees with tost_results.csv for "
                             f"{ref['scale']!r} at bound {tag}")
    return frame


def rent_change_distribution(helpers) -> pd.DataFrame:
    """Within-person change in log monthly rent between adjacent waves, rent sample.

    Membership is the frozen S_M2 sample (2,716 person-waves, 1,154 individuals); rents
    come from the read-only database. A pair is kept when the same person is in the rent
    sample in both waves two years apart, which reproduces the 1,348 person-wave pairs
    the robustness table reports for the rent-sample first difference.
    """
    import csv
    import gzip
    import sqlite3

    sample_file = S2_PRIVATE / "S_M2.csv.gz"
    members = set()
    with gzip.open(sample_file, "rt", encoding="utf-8-sig", newline="") as handle:
        for row in csv.DictReader(handle):
            members.add((str(row["pid"]), int(row["wave"])))
    if len(members) != EXPECTED_RENT_PERSON_WAVES:
        raise SystemExit(f"rent sample has {len(members):,} person-waves; "
                         f"the manuscript says {EXPECTED_RENT_PERSON_WAVES:,}")

    with sqlite3.connect(f"file:{helpers.DEFAULT_DB.as_posix()}?mode=ro", uri=True) as connection:
        rents = {}
        for pid, wave, value, miss in connection.execute(
                "select pid, wave, hh__rent_monthly, hh__rent_monthly_miss from der_cfps_panel"
                " where wave in (2014, 2016, 2018, 2020)"):
            key = (str(pid), int(wave))
            if key in members and miss == "valid" and value is not None and float(value) > 0:
                rents[key] = float(value)

    records = []
    for (pid, wave), value in rents.items():
        following = rents.get((pid, wave + 2))
        if following is None:
            continue
        records.append({"pid": pid, "base_wave": wave, "rent_base": value, "rent_next": following,
                        "d_ln_rent": math.log(following) - math.log(value),
                        "pct_change": following / value - 1.0})
    frame = pd.DataFrame.from_records(records).sort_values(["base_wave", "d_ln_rent"]).reset_index(drop=True)
    if len(frame) != EXPECTED_RENT_PAIRS:
        raise SystemExit(f"rent adjacent pairs = {len(frame):,}; the robustness table says "
                         f"{EXPECTED_RENT_PAIRS:,} - stop and reconcile before plotting")
    return frame


def _bin_counts(d: np.ndarray, window: float, width: float) -> tuple[np.ndarray, np.ndarray]:
    """Counts per bin of [lo, lo + width) over [-window, window), assigned without float drift."""
    n_bins = int(round(2 * window / width))
    index = np.floor((d + window) / width + 1e-9).astype(int)
    keep = (index >= 0) & (index < n_bins)
    edges = -window + width * np.arange(n_bins)
    return edges, np.bincount(index[keep], minlength=n_bins)


def rent_change_histogram(distribution: pd.DataFrame, window: float = 1.5,
                          width: float = 0.10) -> pd.DataFrame:
    """Bin counts for Panel B2.

    The binning is done here rather than inside Stata's histogram so the plotted bar
    heights, the tallest-bar value used to place the labels, and the count of pairs
    outside the window are all read from a file that can be checked against the data.
    """
    d = distribution["d_ln_rent"].to_numpy()
    edges, counts = _bin_counts(d, window, width)
    return pd.DataFrame({"bin_lo": edges, "bin_hi": edges + width, "bin_mid": edges + width / 2,
                         "count": counts.astype(int)})


def rent_change_panel(distribution: pd.DataFrame, histogram: pd.DataFrame) -> pd.DataFrame:
    """One dataset that carries both Panel B2 layers: the bars and the rug."""
    bars = histogram.copy()
    bars["d_ln_rent"] = np.nan
    bars["rug"] = np.nan
    rug = pd.DataFrame({"bin_lo": np.nan, "bin_hi": np.nan, "bin_mid": np.nan, "count": np.nan,
                        "d_ln_rent": distribution["d_ln_rent"].to_numpy(), "rug": 0.0})
    return pd.concat([bars, rug], ignore_index=True)


def rent_change_stats(distribution: pd.DataFrame, window: float = 1.5,
                      width: float = 0.10) -> pd.DataFrame:
    """Marker values for Panel B2, computed from the distribution rather than hard-coded."""
    d = distribution["d_ln_rent"].to_numpy()
    inside = (d >= -window) & (d <= window)
    _, counts = _bin_counts(d, window, width)
    n_bins = len(counts)
    return pd.DataFrame([{
        "n_pairs": int(len(d)),
        "window_lo": -window, "window_hi": window,
        "bin_width": width, "n_bins": int(n_bins), "max_count_window": int(counts.max()),
        "n_outside_window": int((~inside).sum()),
        "median": float(np.median(d)),
        "p10": float(np.percentile(d, 10)), "p90": float(np.percentile(d, 90)),
        "share_ge_10pct": float((d >= math.log(1.10)).mean()),
        "share_ge_2x": float((d >= math.log(2.0)).mean()),
        "share_zero": float((d == 0).mean()),
        "share_inside_window": float(inside.mean()),
        "share_below_window": float((d < -window).mean()),
        "share_above_window": float((d > window).mean()),
    }])


def within_person_change(helpers) -> pd.DataFrame:
    """Change in the housing-problem rating between adjacent waves, gap 2.

    Membership comes from S_M1.csv.gz, the estimation sample of the tenure model
    that the manuscript describes as 98,166 person-waves. Values of H come from
    the read-only database. A pair is kept when both waves are in the sample, so
    the count is the number the robustness table and the transition matrix use.
    """
    import csv
    import gzip
    import sqlite3

    sample_file = S2_PRIVATE / "S_M1.csv.gz"
    members = set()
    with gzip.open(sample_file, "rt", encoding="utf-8-sig", newline="") as handle:
        for row in csv.DictReader(handle):
            members.add((str(row["pid"]), int(row["wave"])))
    if not members:
        raise SystemExit(f"empty estimation-sample file: {sample_file}")

    with sqlite3.connect(f"file:{helpers.DEFAULT_DB.as_posix()}?mode=ro", uri=True) as connection:
        values = {(str(pid), int(wave)): int(value) for pid, wave, value in connection.execute(
            "select pid, wave, housing_problem_national from der_cfps_panel"
            " where wave in (2014, 2016, 2018, 2020) and housing_problem_national is not null")}

    records = []
    for (pid, wave), value in values.items():
        if (pid, wave) not in members or (pid, wave + 2) not in members:
            continue
        following = values.get((pid, wave + 2))
        if following is None:
            continue
        records.append({"base_wave": wave, "d_h": following - value,
                        "abs_d_h": abs(following - value)})

    frame = pd.DataFrame.from_records(records).sort_values(["base_wave", "d_h"]).reset_index(drop=True)
    if len(frame) != EXPECTED_ADJACENT_PAIRS:
        raise SystemExit(f"adjacent-pair count is {len(frame):,}; the manuscript says "
                         f"{EXPECTED_ADJACENT_PAIRS:,} - stop and reconcile before plotting")
    return frame


def load_helpers():
    """Reuse the name sanitising and dtype coercion written for the DB export."""
    spec = importlib.util.spec_from_file_location("db_export", HERE / "10_export_from_db.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for block in iter(lambda: handle.read(8 << 20), b""):
            digest.update(block)
    return digest.hexdigest()


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--round", required=True, help="round folder, e.g. runs/20260912_supplement")
    parser.add_argument("--check", action="store_true", help="report, write nothing")
    parser.add_argument("--only", default="", help="comma-separated targets, e.g. within_person_change")
    args = parser.parse_args(argv)
    only = {name.strip() for name in args.only.split(",") if name.strip()}

    round_dir = Path(args.round)
    if not round_dir.is_absolute():
        round_dir = HERE / round_dir
    if not round_dir.is_dir():
        print(f"ERROR: round folder not found: {round_dir}", file=sys.stderr)
        return 2
    out_dir = round_dir / "estimates"
    helpers = load_helpers()

    rows, missing = [], []
    targets = []
    for name, source in SOURCES.items():
        if only and name not in only:
            continue
        if not source.is_file():
            missing.append(f"{name}: {source}")
            continue
        frame = pd.read_csv(source, low_memory=False)
        targets.append((name, frame, str(source), sha256(source)))

    if not only or "within_person_change" in only:
        note = ("computed: S_M1 membership from the frozen stage-2 run joined to "
                "der_cfps_panel.housing_problem_national")
        targets.append(("within_person_change", within_person_change(helpers), note, ""))

    if not only or "rent_scaled_contrasts" in only:
        note = ("computed: frozen log-rent coefficient x ln(1+c) for c = 10/25/50/100 per cent; "
                "no re-estimation; +10 per cent and doubling cross-checked against mde_table.csv")
        targets.append(("rent_scaled_contrasts", rent_scaled_contrasts(), note, ""))

    if not only or "rent_change_distribution" in only or "rent_change_stats" in only:
        distribution = rent_change_distribution(helpers)
        note = ("computed: S_M2 membership from the frozen stage-2 run joined to "
                "der_cfps_panel.hh__rent_monthly; adjacent-wave pairs")
        if not only or "rent_change_distribution" in only:
            targets.append(("rent_change_distribution", distribution, note, ""))
        histogram = rent_change_histogram(distribution)
        targets.append(("rent_change_histogram", histogram,
                        note + "; 0.10 log-point bins over the plotted window", ""))
        targets.append(("rent_change_panel", rent_change_panel(distribution, histogram),
                        note + "; bars and rug in one dataset for Panel B2", ""))
        targets.append(("rent_change_stats", rent_change_stats(distribution),
                        note + "; marker values for Figure 2 Panel B2", ""))

    for name, frame, source, digest in targets:
        names, renamed = helpers.safe_names(frame.columns)
        frame.columns = names
        frame = helpers.coerce_columns(frame, {})
        rows.append({"target": name, "source": source, "n_rows": len(frame),
                     "n_cols": frame.shape[1], "n_renamed_cols": len(renamed),
                     "renamed_cols": ";".join(f"{k}->{v}" for k, v in renamed.items()),
                     "source_sha256": digest})
        if not args.check:
            out_dir.mkdir(parents=True, exist_ok=True)
            frame.to_stata(out_dir / f"{name}.dta", write_index=False, version=118)
        print(f"{'would write' if args.check else 'wrote'} {name}.dta  "
              f"({len(frame):,} rows x {frame.shape[1]} cols)")

    if missing:
        print("\nMISSING SOURCES")
        for item in missing:
            print("  ", item)

    if not args.check and rows:
        manifest = out_dir / "estimates_manifest.csv"
        fresh = pd.DataFrame(rows)
        if manifest.is_file():
            previous = pd.read_csv(manifest)
            previous = previous[~previous["target"].isin(fresh["target"])]
            columns = list(previous.columns) + [c for c in fresh.columns if c not in previous.columns]
            fresh = pd.concat([previous, fresh], ignore_index=True)[columns]
        fresh.sort_values("target").to_csv(manifest, index=False, encoding="utf-8")
        print(f"\nestimates written to {out_dir}")
    return 1 if missing else 0


if __name__ == "__main__":
    raise SystemExit(main())
