#!/usr/bin/env python3
"""
Tolerance-based comparison of two CSV files that should be "essentially the same".

Reports:
  - Column-set differences
  - Rows present in one file but not the other (via a key column)
  - For shared rows: per-column max absolute and relative differences, and
    the count of elements that exceed rtol/atol tolerances
  - A final verdict (exit 0 = reproducible within tolerance, exit 1 otherwise)

In --quiet mode, suppresses all reporting and prints a single integer:
the total count of differences (structural + non-numeric + numeric cells
exceeding tolerance). Useful for automated checks:

    if ! python compare_csvs.py -q a.csv b.csv > /dev/null; then
        echo "files differ"
    fi

    count=$(python compare_csvs.py -q a.csv b.csv)

Example (verbose):
    python compare_csvs.py file1.csv file2.csv --key dataset --rtol 1e-6 --atol 1e-9
"""
import argparse
import sys
import numpy as np
import pandas as pd


def _align_columns(cols1, cols2, key_col, out):
    """Report column-set differences and return shared columns."""
    only1 = [c for c in cols1 if c not in cols2]
    only2 = [c for c in cols2 if c not in cols1]
    if only1 or only2:
        out("COLUMN DIFFERENCES")
        if only1:
            out(f"  Only in file 1: {only1}")
        if only2:
            out(f"  Only in file 2: {only2}")
        out()
    shared_cols = [c for c in cols1 if c in cols2]

    if key_col not in shared_cols:
        print(f"ERROR: key column {key_col!r} not present in both files",
              file=sys.stderr)
        sys.exit(2)

    return shared_cols, only1, only2


def _align_rows(df1, df2, key_col, shared_cols, out):
    """Report row differences and return aligned DataFrames for shared keys."""
    k1, k2 = set(df1[key_col]), set(df2[key_col])
    only_rows_1 = sorted(k1 - k2)
    only_rows_2 = sorted(k2 - k1)
    if only_rows_1 or only_rows_2:
        out("ROW DIFFERENCES")
        if only_rows_1:
            out(f"  Only in file 1: {only_rows_1}")
        if only_rows_2:
            out(f"  Only in file 2: {only_rows_2}")
        out()

    shared_keys = sorted(k1 & k2)
    value_cols = [c for c in shared_cols if c != key_col]
    df1_aligned = df1.set_index(key_col).loc[shared_keys, value_cols]
    df2_aligned = df2.set_index(key_col).loc[shared_keys, value_cols]

    return df1_aligned, df2_aligned, shared_keys, only_rows_1, only_rows_2


def _check_non_numeric(df1_aligned, df2_aligned, other_cols, out):
    """Compare non-numeric columns using strict equality."""
    mismatches = 0
    for col in other_cols:
        s1, s2 = df1_aligned[col], df2_aligned[col]
        mask = (s1 != s2) & ~(s1.isna() & s2.isna())
        if mask.any():
            count = int(mask.sum())
            mismatches += count
            out(f"  [non-numeric mismatch] {col}: {count} rows")
    return mismatches


def _check_numeric(df1_aligned, df2_aligned, numeric_cols, rtol, atol):
    """Compute max absolute/relative differences and tolerances for numeric columns."""
    stats = {}
    for col in numeric_cols:
        x_vals = df1_aligned[col].to_numpy(dtype=float)
        y_vals = df2_aligned[col].to_numpy(dtype=float)
        both_nan = np.isnan(x_vals) & np.isnan(y_vals)
        finite = ~both_nan & np.isfinite(x_vals) & np.isfinite(y_vals)
        if finite.sum() == 0:
            continue
        diff = np.abs(x_vals[finite] - y_vals[finite])
        denom = np.maximum(np.abs(x_vals[finite]), np.abs(y_vals[finite]))
        rel = np.zeros_like(diff)
        np.divide(diff, denom, out=rel, where=denom > 0)
        exceed = int((~np.isclose(x_vals[finite], y_vals[finite],
                                  rtol=rtol, atol=atol)).sum())
        stats[col] = {
            "max_abs": float(diff.max()),
            "max_rel": float(rel.max()),
            "exceed": exceed,
            "n": int(finite.sum()),
        }
    return stats


def _print_verdict(diffs, stats, top_n, rtol, atol, out):
    """Print top differences summary and final verdict in verbose mode."""
    only1, only2, only_r1, only_r2, non_num_mismatches, num_exceed = diffs
    total_diffs = sum(len(x) for x in (only1, only2, only_r1, only_r2))
    total_diffs += non_num_mismatches + num_exceed

    n_bad = sum(1 for s in stats.values() if s["exceed"] > 0)

    if stats:
        top = sorted(stats.items(), key=lambda kv: -kv[1]["max_abs"])[:top_n]
        out(f"Top {len(top)} columns by max absolute difference:")
        out(f"  {'max_abs':>12}  {'max_rel':>12}  {'exceed':>6}  column")
        for c, s in top:
            out(f"  {s['max_abs']:12.3e}  {s['max_rel']:12.3e}  "
                f"{s['exceed']:>6}  {c}")
        out()

    if total_diffs == 0:
        out(f"VERDICT: files are equivalent within tolerance "
            f"(rtol={rtol}, atol={atol}).")
    else:
        out(f"VERDICT: files DIFFER  (total differences: {total_diffs})")
        if only1 or only2:
            out(f"  - {len(only1) + len(only2)} column(s) only in one file")
        if only_r1 or only_r2:
            out(f"  - {len(only_r1) + len(only_r2)} row(s) only in one file")
        if non_num_mismatches:
            out(f"  - {non_num_mismatches} non-numeric cell mismatch(es)")
        if num_exceed:
            out(f"  - {num_exceed} numeric cell(s) exceed tolerance "
                f"(across {n_bad} column(s))")


def compare(path1, path2, key_col="dataset", rtol=1e-5, atol=1e-8,
            top_n=10, quiet=False):
    """Compare two CSV files for equivalence within specified numerical tolerance."""
    def out(*args, **kwargs):
        if not quiet:
            print(*args, **kwargs)

    df1, df2 = pd.read_csv(path1), pd.read_csv(path2)
    out(f"File 1: {path1}  shape={df1.shape}")
    out(f"File 2: {path2}  shape={df2.shape}")
    out(f"Tolerances: rtol={rtol}, atol={atol}   Key: {key_col!r}")
    out("-" * 78)

    shared_cols, only1, only2 = _align_columns(
        list(df1.columns), list(df2.columns), key_col, out
    )
    a, b, shared_keys, only_r1, only_r2 = _align_rows(
        df1, df2, key_col, shared_cols, out
    )

    numeric_cols = a.select_dtypes(include=[np.number]).columns.tolist()
    other_cols = [c for c in shared_cols if c != key_col and c not in numeric_cols]

    out(f"Comparing {len(shared_keys)} shared rows across "
        f"{len(numeric_cols)} numeric + {len(other_cols)} non-numeric columns.\n")

    non_num_mismatches = _check_non_numeric(a, b, other_cols, out)
    stats = _check_numeric(a, b, numeric_cols, rtol, atol)

    n_any = sum(1 for s in stats.values() if s["max_abs"] > 0)
    n_bad = sum(1 for s in stats.values() if s["exceed"] > 0)
    num_exceed = sum(s["exceed"] for s in stats.values())

    out(f"Numeric columns with ANY non-zero difference:        {n_any} / {len(stats)}")
    out(f"Numeric columns with differences EXCEEDING tolerance: {n_bad} / {len(stats)}\n")

    diff_counts = (only1, only2, only_r1, only_r2, non_num_mismatches, num_exceed)
    total_diffs = sum(len(x) for x in (only1, only2, only_r1, only_r2))
    total_diffs += non_num_mismatches + num_exceed

    if quiet:
        print(total_diffs)
    else:
        _print_verdict(diff_counts, stats, top_n, rtol, atol, out)

    return 0 if total_diffs == 0 else 1


def main():
    """Parse CLI arguments and run CSV comparison."""
    p = argparse.ArgumentParser()
    p.add_argument("file1")
    p.add_argument("file2")
    p.add_argument("--key", default="dataset")
    p.add_argument("--rtol", type=float, default=1e-5)
    p.add_argument("--atol", type=float, default=1e-8)
    p.add_argument("--top-n", type=int, default=10)
    p.add_argument("-q", "--quiet", action="store_true",
                   help="suppress reporting; print only total difference count")
    args = p.parse_args()
    sys.exit(compare(args.file1, args.file2,
                     key_col=args.key, rtol=args.rtol, atol=args.atol,
                     top_n=args.top_n, quiet=args.quiet))


if __name__ == "__main__":
    main()
