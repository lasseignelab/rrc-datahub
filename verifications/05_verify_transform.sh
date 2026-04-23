#!/bin/bash
#
# Verify transformed metadata TSVs produced by 04_transform_metadata.sh.
# Checks MD5 checksums of all output files to confirm results are complete
# and reproducible across runs.
#
# Usage (from project root):
#   cap verify verifications/04_verify_transform.sh -s batch
#
cap_verify_md5 results/ --select "*_transformed.tsv"
