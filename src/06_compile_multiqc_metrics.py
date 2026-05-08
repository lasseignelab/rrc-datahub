#!/usr/bin/env python3
"""
compile_multiqc_metrics.py

Compiles and averages MultiQC general stats across multiple nf-core/rnaseq
output directories. Produces a single CSV where each row is one dataset.

Expected stats file location within each dataset directory:
    <dataset_dir>/multiqc/star_salmon/multiqc_report_data/multiqc_general_stats.txt

Usage:
    python compile_multiqc_metrics.py \
        --data-path /path/to/nfcore_rnaseq \
        --datasets-file /path/to/geo_datasets.csv \
        --output /path/to/results/multiqc_summary.csv
"""

import argparse
import os
import re
import sys
import pandas as pd


# Exact relative path to multiqc_general_stats.txt within an nf-core/rnaseq
# dataset output directory (star_salmon workflow layout).
MULTIQC_STATS_RELATIVE = os.path.join(
    "multiqc", "star_salmon", "multiqc_report_data", "multiqc_general_stats.txt"
)

# Columns that should be summed across samples rather than averaged.
# These are raw read counts that scale with sequencing depth.
SUM_COLUMNS = {
    "fastqc_raw-total_sequences",
    "fastqc_trimmed-total_sequences",
    "qualimap_rnaseq-reads_aligned",
    "salmon-num_mapped",
    "samtools_stats-non_primary_alignments",
    "samtools_stats-reads_mapped",
    "samtools_stats-raw_total_sequences",
    "samtools_flagstat-flagstat_total",
    "samtools_flagstat-mapped_passed",
    "star-total_reads",
    "star-mapped",
    "star-uniquely_mapped",
    "star-multimapped",
}


def find_general_stats(dataset_dir: str) -> str | None:
    """
    Return the path to multiqc_general_stats.txt.
    First tries the known nf-core/rnaseq star_salmon path, then falls back to
    a directory walk so the script stays robust to minor layout variations.
    """
    primary = os.path.join(dataset_dir, MULTIQC_STATS_RELATIVE)
    if os.path.isfile(primary):
        return primary

    # Fallback: walk the tree (skips hidden dirs and nextflow work/ dir)
    for root, dirs, files in os.walk(dataset_dir):
        dirs[:] = [d for d in dirs if not d.startswith(".") and d != "work"]
        if "multiqc_general_stats.txt" in files:
            return os.path.join(root, "multiqc_general_stats.txt")

    return None


def load_general_stats(path: str) -> pd.DataFrame:
    """
    Load multiqc_general_stats.txt and collapse per-sample rows.

    MultiQC sometimes splits one sample across multiple rows with suffixes:
        SAMPLE_ID
        SAMPLE_ID_1
        SAMPLE_ID_2
    where each row may hold values the others lack (NaN).

    This function:
      1. Strips _1 / _2 suffixes to get the base sample ID.
      2. Groups rows by base sample ID and coalesces: for each column, takes
         the first non-NaN value across the group.
      3. Returns one row per unique sample.
    """
    df = pd.read_csv(path, sep="\t", index_col=0)

    # Strip trailing _1 or _2 suffix from sample names
    df.index = [re.sub(r"_[12]$", "", idx) for idx in df.index]
    df.index.name = "Sample"

    # Coalesce: for each base sample ID, take the first non-NaN value per column
    def coalesce(group):
        return group.apply(
            lambda col: col.dropna().iloc[0] if col.notna().any() else float("nan")
        )

    df = df.groupby(df.index, sort=False).apply(coalesce)

    return df


def aggregate_metrics(df: pd.DataFrame, shortened: bool) -> pd.Series:
    """
    Aggregate numeric columns across samples:
      - Sum columns in SUM_COLUMNS (raw read counts)
      - Average all other numeric columns (percentages, rates, etc.)

    Column names are matched after shortening if shortened=True.
    Returns a single Series with aggregated values.
    """
    numeric = df.select_dtypes(include="number")

    # Shorten column names for matching against SUM_COLUMNS if needed
    if shortened:
        col_map = {col: _shorten(col) for col in numeric.columns}
    else:
        col_map = {col: col for col in numeric.columns}

    result = {}
    for orig_col, short_col in col_map.items():
        if short_col in SUM_COLUMNS:
            result[short_col + "_sum"] = numeric[orig_col].sum()
        else:
            result[short_col + "_avg"] = numeric[orig_col].mean()

    return pd.Series(result)


def _shorten(col: str) -> str:
    """Strip the verbose MultiQC module prefix from a column name."""
    parts = col.split("_mqc-generalstats-", 1)
    return parts[-1] if len(parts) > 1 else col


def shorten_column_names(series: pd.Series) -> pd.Series:
    series.index = [_shorten(c) for c in series.index]
    return series


def parse_datasets_file(path: str) -> list[str]:
    """
    Parse a CSV or plain-text file of dataset directory names.
    - Ignores comment lines (starting with #) and blank lines.
    - For CSV files, reads only the first column.
    """
    datasets = []
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            datasets.append(line.split(",")[0].strip())
    return datasets


def main():
    parser = argparse.ArgumentParser(
        description="Average MultiQC general stats across nf-core/rnaseq datasets."
    )
    parser.add_argument(
        "--data-path",
        required=True,
        metavar="DIR",
        help="Root directory containing all dataset subdirectories "
             "(i.e. $CAP_DATA_PATH/nfcore_rnaseq).",
    )
    parser.add_argument(
        "--datasets-file",
        required=True,
        metavar="FILE",
        help="CSV or text file of dataset directory names (one per line, first column used).",
    )
    parser.add_argument(
        "--output",
        default="multiqc_summary.csv",
        help="Output CSV file path (default: multiqc_summary.csv).",
    )
    parser.add_argument(
        "--sep",
        default=",",
        help="Delimiter for the output file. Use '\\t' for TSV (default: ',').",
    )
    parser.add_argument(
        "--no-shorten",
        action="store_true",
        help="Keep original verbose MultiQC column names.",
    )
    args = parser.parse_args()

    sep = args.sep.replace("\\t", "\t")
    shortened = not args.no_shorten

    dataset_names = parse_datasets_file(args.datasets_file)
    if not dataset_names:
        print("[ERROR] No dataset names found in datasets file.", file=sys.stderr)
        sys.exit(1)

    rows = []
    skipped = []

    for name in dataset_names:
        dataset_dir = os.path.join(args.data_path, name)

        if not os.path.isdir(dataset_dir):
            print(f"[WARNING] Directory not found, skipping: {dataset_dir}", file=sys.stderr)
            skipped.append(name)
            continue

        stats_file = find_general_stats(dataset_dir)

        if stats_file is None:
            print(f"[WARNING] multiqc_general_stats.txt not found in: {dataset_dir}", file=sys.stderr)
            skipped.append(name)
            continue

        print(f"[INFO] Processing '{name}' -> {stats_file}")

        df = load_general_stats(stats_file)
        n_samples = len(df)
        agg = aggregate_metrics(df, shortened=shortened)

        agg["dataset"] = name
        agg["n_samples"] = n_samples
        rows.append(agg)

    if not rows:
        print("[ERROR] No valid datasets found. Exiting.", file=sys.stderr)
        sys.exit(1)

    summary = pd.DataFrame(rows)

    # Move metadata columns to the front
    meta_cols = ["dataset", "n_samples"]
    metric_cols = [c for c in summary.columns if c not in meta_cols]
    summary = summary[meta_cols + metric_cols]

    os.makedirs(os.path.dirname(os.path.abspath(args.output)), exist_ok=True)
    summary.to_csv(args.output, sep=sep, index=False)

    print(f"\n[DONE] Summary written to: {args.output}")
    print(f"       Datasets processed : {len(rows)}")
    print(f"       Metrics per dataset: {len(metric_cols)}")

    if skipped:
        print(f"\n[WARNING] Skipped {len(skipped)} dataset(s):")
        for s in skipped:
            print(f"  - {s}")


if __name__ == "__main__":
    main()
