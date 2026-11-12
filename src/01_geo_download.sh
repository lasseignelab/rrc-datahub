#!/bin/bash
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem-per-cpu=4G
#SBATCH --time=50:00:00
#SBATCH --partition=medium
#SBATCH --array=0-23%3
echo "Creating output directory ..."
DATASET=$(cap_array_value "$CAP_PROJECT_PATH/doc/geo_datasets.csv")
OUTDIR="${CAP_DATA_PATH}/raw-data/${DATASET}"
mkdir -p "${OUTDIR}"
echo -e "\tFastq files for ${DATASET} will be saved to ${OUTDIR}"
if [[ -f "${OUTDIR}/${DATASET}_metadata.tsv" ]]; then
	echo "File ${OUTDIR}/${DATASET}_metadata.tsv already exists"
else
	sleep $((SLURM_ARRAY_TASK_ID * 120))
	echo "Fetching metadata for ${DATASET} at $(date) ..."
	cap_container "acrumley/rrc-datahub:0.1.0"
	singularity exec --cleanenv \
		--containall \
		-B "${CAP_PROJECT_PATH}" \
		--pwd "${CAP_PROJECT_PATH}" \
		"${CAP_CONTAINER_PATH}"/rrc-datahub_0.1.0.sif \
		Rscript --vanilla "${CAP_PROJECT_PATH}"/src/01_geo_download.R \
		"${DATASET}" \
		"${OUTDIR}"
fi
if [[ -f "${OUTDIR}/${DATASET}_urls_and_md5s.tsv" ]]; then
	echo "File ${OUTDIR}/${DATASET}_urls_and_md5s.tsv already exists"
else
	echo "Extracting URLs and MD5 checksums..."
	awk -F '\t' '{
      if (NR > 1) print $2 "\t" $3
    }' "${OUTDIR}/${DATASET}_metadata.tsv" >"${OUTDIR}/${DATASET}_urls_and_md5s.tsv"
fi

echo "Downloading and verifying files ..."
MAX_RETRIES=5
while IFS=$'\t' read -r urls md5s; do
	IFS=';' read -ra url_array <<<"$urls"
	IFS=';' read -ra md5_array <<<"$md5s"
	for i in "${!url_array[@]}"; do
		url="https://${url_array[i]}"
		md5="${md5_array[i]}"
		filename=$(basename "$url")
		filepath="${OUTDIR}/${filename}"

		attempt=1
		success=false
		while [[ $attempt -le $MAX_RETRIES ]]; do
			echo "Downloading $filename from ENA (attempt ${attempt}/${MAX_RETRIES}) ..."
			if (cap_data_download --md5sum="${md5}" --subdirectory "raw-data/${DATASET}" "${url}"); then
				if [[ -f "${filepath}" ]]; then
					actual_md5=$(md5sum "${filepath}" | awk '{print $1}')
					if [[ "${actual_md5}" == "${md5}" ]]; then
						echo "  -> ${filename} verified (md5 match)"
						success=true
						break
					else
						echo "  -> WARNING: md5 mismatch for ${filename} (expected ${md5}, got ${actual_md5}). Removing and retrying."
						rm -f "${filepath}"
					fi
				else
					echo "  -> WARNING: ${filename} not found after reported success. Retrying."
				fi
			else
				echo "  -> cap_data_download failed for ${filename} (exit code $?). Removing any partial file and retrying."
				rm -f "${filepath}"
			fi
			attempt=$((attempt + 1))
			sleep $((attempt * 30))
		done

		if [[ "${success}" != true ]]; then
			echo "ERROR: Failed to download and verify ${filename} after ${MAX_RETRIES} attempts." >&2
		fi
	done
done <"${OUTDIR}/${DATASET}_urls_and_md5s.tsv"
