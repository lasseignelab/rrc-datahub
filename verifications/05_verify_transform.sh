#!/bin/bash
### Sample metadata transformation verification
# Author: Kieran Casper, with AI assistance from Claude (Anthropic)
# Date: April 23, 2026
## Goal: Verify transformed metadata TSVs produced by 05_transform_metadata.sh
##       by checking MD5 checksums of all output files to confirm results are
##       complete and reproducible across runs.
## Reproducibility:
# * GitHub: lasseignelab/rrc-datahub
# * Docker: acrumley/rrc-datahub:0.1.0
#
# Usage (from project root):
#   cap verify verifications/05_verify_transform.sh -s batch
#
cap_verify_md5 results/ --select "*_transformed.tsv"
