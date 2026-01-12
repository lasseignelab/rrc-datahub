#!/bin/bash

#SBATCH --nodes=1
#SBATCH --ntasks=1  
#SBATCH --cpus-per-task=1
#SBATCH --mem-per-cpu=4G
#SBATCH --time=12:00:00
#SBATCH --partition=short
#SBATCH --array=0-13

echo "Creating output directory ..."
DATASET=$(cap_array_value "$CAP_PROJECT_PATH/doc/geo_datasets.csv")
OUTDIR="${CAP_DATA_PATH}/raw-data/${DATASET}"
mkdir -p "${OUTDIR}"
echo -e "\tFastq files for ${DATASET} will be saved to ${OUTDIR}"

echo "Fetching metadata for ${DATASET} ..."
base_url="https://www.ebi.ac.uk/ena/portal/api/filereport"
params="?accession=${DATASET}&result=read_run"
fields="&fields=run_accession,fastq_ftp,fastq_md5"
format="&format=tsv&download=true"
curl -s "${base_url}${params}${fields}${format}" -o "${OUTDIR}/${DATASET}_metadata.tsv"

echo "Extracting URLs and MD5 checksums..."
awk -F '\t' '{
  if (NR > 1) print $2 "\t" $3
}' "${OUTDIR}/${DATASET}_metadata.tsv" > "${OUTDIR}/${DATASET}_urls_and_md5s.tsv"

echo "Downloading and verifying files ..."
while IFS=$'\t' read -r urls md5s; do
    IFS=';' read -ra url_array <<< "$urls"
    IFS=';' read -ra md5_array <<< "$md5s"

    for i in "${!url_array[@]}"; do
        url="https://${url_array[i]}"
        md5="${md5_array[i]}"
        filename=$(basename "$url")

        echo "Downloading $filename from ENA ..."
        cap_data_download --md5sum="${md5}" --subdirectory "raw-data/${DATASET}" "${url}"
    done

done < "${OUTDIR}/${DATASET}_urls_and_md5s.tsv"
