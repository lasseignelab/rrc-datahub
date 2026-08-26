#!/bin/bash

cap_verify_append "Number of differences:"
cap_verify_append "$(singularity exec --cleanenv \
	--containall \
	--pwd "${CAP_PROJECT_PATH}" \
	-B "${CAP_PROJECT_PATH}" \
	"${CAP_CONTAINER_PATH}"/rrc-datahub_0.2.0.sif \
	python3 src/compare_csvs.py -q <(git show HEAD:results/multiqc/multiqc_summary.csv) results/multiqc/multiqc_summary.csv --rtol 1e-5 --atol 1e-9)"
cap_verify_append "If differences > 0, re-run verification without the '-q' argument to investigate."
