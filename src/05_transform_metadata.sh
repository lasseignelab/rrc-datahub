#!/bin/bash
#
# Transform raw BioProject sample metadata TSVs into harmonized, analysis-ready
# TSVs with normalized column names, controlled vocabulary fields, and derived
# biological annotations. One transformed TSV is produced per BioProject.
#
# Inputs:
#   - doc/geo_datasets.csv           : list of BioProject accession IDs
#   - data/raw-data/<ID>/<ID>_metadata.tsv : raw metadata from 01_geo_download.R
#
# Outputs:
#   - results/<ID>/<ID>_transformed.tsv : harmonized metadata TSV per project
#
# Usage (from project root):
#   cap run -e default -s batch src/04_transform_metadata.sh
#
# Author: kjcasper
#
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem-per-cpu=4G
#SBATCH --time=12:00:00
#SBATCH --partition=short
#SBATCH --array=0-13

# ---------------------------------------------------------------------------
# Resolve dataset ID and paths for this array task
# ---------------------------------------------------------------------------
DATASET=$(cap_array_value "${CAP_PROJECT_PATH}/doc/geo_datasets.csv")
INFILE="${CAP_DATA_PATH}/raw-data/${DATASET}/${DATASET}_metadata.tsv"
OUTDIR="${CAP_RESULTS_PATH}/${DATASET}"

echo "Processing dataset: ${DATASET}"
mkdir -p "${OUTDIR}"

# ---------------------------------------------------------------------------
# Skip if output already exists (matches project convention)
# ---------------------------------------------------------------------------
if [[ -f "${OUTDIR}/${DATASET}_transformed.tsv" ]]; then
    echo "File ${OUTDIR}/${DATASET}_transformed.tsv already exists — skipping."
    exit 0
fi

# ---------------------------------------------------------------------------
# Verify input exists before attempting transformation
# ---------------------------------------------------------------------------
if [[ ! -f "${INFILE}" ]]; then
    echo "ERROR: Input file not found: ${INFILE}" >&2
    exit 1
fi

echo "Transforming metadata for ${DATASET} at $(date) ..."

# ---------------------------------------------------------------------------
# Run the R transformation script inside the project container
# ---------------------------------------------------------------------------
cap_container "acrumley/rrc-datahub:0.1.0"
singularity exec --cleanenv \
                 --containall \
                 -B "${CAP_PROJECT_PATH}" \
                 --pwd "${CAP_PROJECT_PATH}" \
                 "${CAP_CONTAINER_PATH}"/rrc-datahub_0.1.0.sif \
                 Rscript --vanilla "${CAP_PROJECT_PATH}"/src/04_transform_metadata.R \
                 "${DATASET}" \
                 "${INFILE}" \
                 "${OUTDIR}"

echo "Done: ${DATASET} at $(date)"
