#!/usr/bin/env python3
"""
MultiQC dataset-level metadata curation
Author: Tabea M. Soelter
Date: March 26th, 2026

Compiles and averages/sums MultiQC general stats across multiple nf-core/rnaseq
output directories. Produces a single CSV where each row is one dataset. Script
expects the multiqc_general_stats.txt file for every dataset in
data/nfcore_rnaseq/<dataset_dir>/multiqc/star_salmon/multiqc_report_data/
"""
import argparse
import os
import re
import sys
from pathlib import Path
import pandas as pd

print("Setting up for analysis ...")
sum_columns = {
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


def main():
    """
    Parse arguments, compile MultiQC stats across datasets, and write output CSV.
    """
    parser = argparse.ArgumentParser(
        description="Compile MultiQC stats across nf-core/rnaseq datasets."
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
        help=(
            "CSV or text file of dataset directory names (one per line, first "
            "column used). Lines starting with '#' and blank lines are ignored."
            " If your file has a header row, prefix it with '#' to skip it."
        ),
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

    args = parser.parse_args()

    dataset_names = parse_datasets_file(args.datasets_file)

    rows = []

    for name in dataset_names:
        stats_file = os.path.join(
            args.data_path, name,
            "multiqc", "star_salmon", "multiqc_report_data",
            "multiqc_general_stats.txt"
        )
        if not os.path.isfile(stats_file):
            print(
                f"[ERROR] multiqc_general_stats.txt not found for dataset "
                f"'{name}': {stats_file}",
                file=sys.stderr,
            )
            sys.exit(1)

        print(f"[INFO] Processing '{name}' -> {stats_file}")

        df = load_general_stats(stats_file)
        n_samples = len(df)

        agg = aggregate_metrics(df)

        agg["dataset"] = name
        agg["n_samples"] = n_samples
        rows.append(agg)

    summary = pd.DataFrame(rows)

    meta_cols = ["dataset", "n_samples"]
    metric_cols = [c for c in summary.columns if c not in meta_cols]
    summary = summary[meta_cols + metric_cols]

    print("Saving final results ...")
    Path(args.output).parent.mkdir(parents=True, exist_ok=True)
    summary.to_csv(args.output, sep=args.sep.replace("\\t", "\t"), index=False)


def load_general_stats(path: str) -> pd.DataFrame:
    """
    Load multiqc_general_stats.txt and collapse per-sample rows, because MultiQC
    sometimes splits one sample across multiple rows with suffixes (i.e.,
    SAMPLE_ID Read 1, SAMPLE_ID Read 2). Return one row per unique sample.
    """
    df = pd.read_csv(path, sep="\t", index_col=0)

    df.index = pd.Index(
        [re.sub(r"(_\d+| Read \d+)$", "", idx) for idx in df.index], name="Sample"
    )

    df = df.groupby(df.index, sort=False).first()

    return df


def aggregate_metrics(df: pd.DataFrame) -> pd.Series:
    """
    Aggregate numeric columns across samples:
      - Sum columns whose name is in sum_columns.
      - Average all other numeric columns (percentages, rates, etc.)

    Returns a single Series with aggregated values, suffixed _sum or _avg.
    """
    numeric = df.select_dtypes(include="number")

    matched = set(numeric.columns) & sum_columns
    unmatched = sum_columns - matched
    if unmatched:
        print(
            f"[WARNING] sum_columns entries not found in data: "
            f"{sorted(unmatched)}",
            file=sys.stderr,
        )

    result = {}
    for col in numeric.columns:
        if col in sum_columns:
            result[col + "_sum"] = numeric[col].sum()
        else:
            result[col + "_avg"] = numeric[col].mean()

    return pd.Series(result)


def parse_datasets_file(path: str) -> list:
    """
    Parse a CSV or plain-text file of dataset directory names.
    - Ignores comment lines (starting with #) and blank lines.
    - For CSV files, reads only the first column.
    """
    datasets = []
    with open(path, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            datasets.append(line.split(",")[0].strip())
    return datasets


if __name__ == "__main__":
    main()
