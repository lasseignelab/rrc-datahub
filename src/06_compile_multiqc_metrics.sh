#!/bin/bash
#SBATCH --ntasks=1            
#SBATCH --time=01:00:00                    
#SBATCH --mem=12G
#SBATCH --partition=express

echo "Getting Docker image ..."
cap_container -c singularity "tsoelter/sn-ml-drug-repurposing:2.1.0"

echo "Setting up for analysis ..."
OUTPUT_DIR="${CAP_RESULTS_PATH}/multiqc"
mkdir -p "${OUTPUT_DIR}"
OUTPUT_FILE="${OUTPUT_DIR}/multiqc_summary.csv"
REAL_RNASEQ_PATH=$(readlink -f "${CAP_DATA_PATH}/nfcore_rnaseq")

echo "Compiling multiQC metrics ..."
singularity exec --cleanenv \
                 --containall \
                 -B "${CAP_PROJECT_PATH}" \
                 -B "${REAL_RNASEQ_PATH}" \
                 "${CAP_CONTAINER_PATH}"/sn-ml-drug-repurposing_2.1.0.sif \
                 python3 -u "${CAP_PROJECT_PATH}"/src/06_compile_multiqc_metrics.py \
                     --data-path "${REAL_RNASEQ_PATH}" \
                     --datasets-file "${CAP_PROJECT_PATH}"/doc/geo_datasets.csv \
                     --output "${OUTPUT_FILE}"

echo "Results written to: ${OUTPUT_FILE}"