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
    python compare_csvs.py file1.csv file2.csv --key dataset --rtol 1e-6
"""
import argparse
from dataclasses import dataclass, field
import sys
from typing import Dict, List, Optional
import numpy as np
import pandas as pd


@dataclass
class CompareConfig:
    """Configuration options for CSV comparison."""

    key_col: str = "dataset"
    rtol: float = 1e-5
    atol: float = 1e-8
    top_n: int = 10
    quiet: bool = False


@dataclass
class AlignmentData:
    """Stores intermediate data and structural diffs after alignment."""

    df1_aligned: pd.DataFrame
    df2_aligned: pd.DataFrame
    numeric_cols: List[str]
    other_cols: List[str]
    diffs: Dict[str, List[str]] = field(default_factory=dict)
    non_num_mismatches: int = 0

    @property
    def shared_rows_count(self) -> int:
        """Return the number of shared rows between aligned dataframes."""
        return len(self.df1_aligned)

    @property
    def struct_diff_count(self) -> int:
        """Return total count of structural column and row differences."""
        return sum(len(v) for v in self.diffs.values())


def _align_data(df1, df2, config, out):
    """Align columns and rows, reporting structural differences."""
    diffs = {
        "c1": [c for c in df1.columns if c not in df2.columns],
        "c2": [c for c in df2.columns if c not in df1.columns],
    }
    if diffs["c1"] or diffs["c2"]:
        out("COLUMN DIFFERENCES")
        if diffs["c1"]:
            out(f"  Only in file 1: {diffs['c1']}")
        if diffs["c2"]:
            out(f"  Only in file 2: {diffs['c2']}")
        out()

    shared_cols = [c for c in df1.columns if c in df2.columns]
    if config.key_col not in shared_cols:
        print(f"ERROR: key column {config.key_col!r} missing in both files",
              file=sys.stderr)
        sys.exit(2)

    s1, s2 = set(df1[config.key_col]), set(df2[config.key_col])
    diffs["r1"], diffs["r2"] = sorted(s1 - s2), sorted(s2 - s1)
    if diffs["r1"] or diffs["r2"]:
        out("ROW DIFFERENCES")
        if diffs["r1"]:
            out(f"  Only in file 1: {diffs['r1']}")
        if diffs["r2"]:
            out(f"  Only in file 2: {diffs['r2']}")
        out()

    shared_keys = sorted(s1 & s2)
    val_cols = [c for c in shared_cols if c != config.key_col]
    a = df1.set_index(config.key_col).loc[shared_keys, val_cols]
    b = df2.set_index(config.key_col).loc[shared_keys, val_cols]

    num_cols = a.select_dtypes(include=[np.number]).columns.tolist()

    return AlignmentData(
        df1_aligned=a,
        df2_aligned=b,
        numeric_cols=num_cols,
        other_cols=[c for c in val_cols if c not in num_cols],
        diffs=diffs,
    )


def _check_non_numeric(align, out):
    """Compare non-numeric columns using strict equality."""
    mismatches = 0
    a, b = align.df1_aligned, align.df2_aligned
    for col in align.other_cols:
        s1, s2 = a[col], b[col]
        mask = (s1 != s2) & ~(s1.isna() & s2.isna())
        if mask.any():
            count = int(mask.sum())
            mismatches += count
            out(f"  [non-numeric mismatch] {col}: {count} rows")
    align.non_num_mismatches = mismatches


def _check_numeric(a, b, numeric_cols, config):
    """Compute max absolute/relative differences and check tolerances."""
    stats = {}
    for col in numeric_cols:
        x_vals = a[col].to_numpy(dtype=float)
        y_vals = b[col].to_numpy(dtype=float)
        both_nan = np.isnan(x_vals) & np.isnan(y_vals)
        finite = ~both_nan & np.isfinite(x_vals) & np.isfinite(y_vals)
        if finite.sum() == 0:
            continue
        diff = np.abs(x_vals[finite] - y_vals[finite])
        denom = np.maximum(np.abs(x_vals[finite]), np.abs(y_vals[finite]))
        rel = np.zeros_like(diff)
        np.divide(diff, denom, out=rel, where=denom > 0)
        exceed = int((~np.isclose(x_vals[finite], y_vals[finite],
                                  rtol=config.rtol, atol=config.atol)).sum())
        stats[col] = {
            "max_abs": float(diff.max()),
            "max_rel": float(rel.max()),
            "exceed": exceed,
            "n": int(finite.sum()),
        }
    return stats


def _print_verdict(align, num_exceed, stats, cfg, out):
    """Print top differences summary and final verdict in verbose mode."""
    total_diffs = align.struct_diff_count + align.non_num_mismatches + num_exceed
    n_bad = sum(1 for s in stats.values() if s["exceed"] > 0)

    if stats:
        top = sorted(stats.items(), key=lambda kv: -kv[1]["max_abs"])[:cfg.top_n]
        out(f"Top {len(top)} columns by max absolute difference:")
        out(f"  {'max_abs':>12}  {'max_rel':>12}  {'exceed':>6}  column")
        for c, s in top:
            out(f"  {s['max_abs']:12.3e}  {s['max_rel']:12.3e}  "
                f"{s['exceed']:>6}  {c}")
        out()

    if total_diffs == 0:
        out(f"VERDICT: files are equivalent within tolerance "
            f"(rtol={cfg.rtol}, atol={cfg.atol}).")
    else:
        out(f"VERDICT: files DIFFER  (total differences: {total_diffs})")
        if align.diffs["c1"] or align.diffs["c2"]:
            n_cols = len(align.diffs["c1"]) + len(align.diffs["c2"])
            out(f"  - {n_cols} column(s) only in one file")
        if align.diffs["r1"] or align.diffs["r2"]:
            n_rows = len(align.diffs["r1"]) + len(align.diffs["r2"])
            out(f"  - {n_rows} row(s) only in one file")
        if align.non_num_mismatches:
            out(f"  - {align.non_num_mismatches} non-numeric cell mismatch(es)")
        if num_exceed:
            out(f"  - {num_exceed} numeric cell(s) exceed tolerance "
                f"(across {n_bad} column(s))")


def compare(path1, path2, config: Optional[CompareConfig] = None, **kwargs):
    """Compare two CSV files for equivalence within specified tolerance."""
    cfg = config or CompareConfig(**kwargs)

    def out(*args_out, **kwargs_out):
        if not cfg.quiet:
            print(*args_out, **kwargs_out)

    df1, df2 = pd.read_csv(path1), pd.read_csv(path2)
    out(f"File 1: {path1}  shape={df1.shape}")
    out(f"File 2: {path2}  shape={df2.shape}")
    out(f"Tolerances: rtol={cfg.rtol}, atol={cfg.atol}   Key: {cfg.key_col!r}")
    out("-" * 78)

    align = _align_data(df1, df2, cfg, out)
    out(f"Comparing {align.shared_rows_count} shared rows across "
        f"{len(align.numeric_cols)} numeric + "
        f"{len(align.other_cols)} non-numeric columns.\n")

    _check_non_numeric(align, out)
    stats = _check_numeric(
        align.df1_aligned, align.df2_aligned, align.numeric_cols, cfg
    )

    n_any = sum(1 for s in stats.values() if s["max_abs"] > 0)
    n_bad = sum(1 for s in stats.values() if s["exceed"] > 0)
    num_exceed = sum(s["exceed"] for s in stats.values())

    out(f"Numeric columns with ANY non-zero difference:        "
        f"{n_any} / {len(stats)}")
    out(f"Numeric columns with differences EXCEEDING tolerance: "
        f"{n_bad} / {len(stats)}\n")

    total_diffs = (align.struct_diff_count + align.non_num_mismatches +
                   num_exceed)

    if cfg.quiet:
        print(total_diffs)
    else:
        _print_verdict(align, num_exceed, stats, cfg, out)

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

    cfg = CompareConfig(
        key_col=args.key,
        rtol=args.rtol,
        atol=args.atol,
        top_n=args.top_n,
        quiet=args.quiet,
    )
    sys.exit(compare(args.file1, args.file2, config=cfg))


if __name__ == "__main__":
    main()
