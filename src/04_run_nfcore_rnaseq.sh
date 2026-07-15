#!/bin/bash

#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --mem-per-cpu=12G
#SBATCH --cpus-per-task=12
#SBATCH --time=48:00:00
#SBATCH --partition=medium
#SBATCH --array=0-13%3

# The results of the nf-core/rnaseq pipeline are not fully reproducible.
# Processed outputs will be available on Zenodo to allow for downstream
# reproducibility of our results.
echo "Setting up for alignment with the nf-core/rnaseq pipeline ..."
dataset=$(cap_array_value "$CAP_PROJECT_PATH/doc/geo_datasets.csv")
out_dir="${CAP_DATA_PATH}/nfcore_rnaseq/$dataset"
mkdir -p "$out_dir"
samplesheet="${CAP_DATA_PATH}/raw-data/$dataset/samplesheet.csv"
gtf="${CAP_DATA_PATH}/GRCm39_M37/gencode.vM37.primary_assembly.annotation.gtf"
fasta="${CAP_DATA_PATH}/GRCm39_M37/GRCm39.primary_assembly.genome.fa"
profile="${NEXTFLOW_PROFILE:-singularity}"

echo "Aligning ${dataset} to the reference genome ..."
ml Anaconda3
conda activate rrc-datahub-nextflow-v26_04_0

working_directory="$CAP_PROJECT_PATH/work/04_run_nfcore_rnaseq/$dataset"
mkdir -p "$working_directory"

export NXF_CACHE_DIR="$working_directory"

nextflow run nf-core/rnaseq -r ${NFCORE_RNASEQ_VERSION} \
    -c "${CAP_PROJECT_PATH}/config/nextflow.config" \
    --input "${samplesheet}" \
    --outdir "${out_dir}" \
    --gtf "${gtf}" \
    --fasta "${fasta}" \
    --aligner star_salmon \
    --pseudo_aligner salmon \
    -w "${working_directory}" \
    -profile "${profile}"

exit_code=$?

if [[ $exit_code -eq 0 ]]; then
    rm -rf "$working_directory"
else
    echo "Pipeline failed — preserving working directory"
fi

exit $exit_code
