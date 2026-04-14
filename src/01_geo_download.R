### Sample metadata download
# Author: Tonie Crumley
# Date: April 14, 2026

## Goal: Download metadata for all the samples included in the RRC DataHub.

## Reproducibility:
# * GitHub: lasseignelab/rrc-datahub
# * Docker: acrumley/rrc-datahub:0.1.0

args <- R.utils::commandArgs(trailingOnly = TRUE)

source(file.path("src", "functions", "get_bioproject_metadata.R"))

dataset <- args[1]
output_dir <- args[2]

get_bioproject_metadata(dataset, output_dir = output_dir)

print("Printing session information ...")
sessionInfo()

# R version 4.5.2 (2025-10-31)
# Platform: x86_64-pc-linux-gnu
# Running under: Ubuntu 24.04.4 LTS
#
# Matrix products: default
# BLAS:   /usr/lib/x86_64-linux-gnu/openblas-pthread/libblas.so.3
# LAPACK: /usr/lib/x86_64-linux-gnu/openblas-pthread/libopenblasp-r0.3.26.so;
# LAPACK version 3.12.0
#
# locale:
#  [1] LC_CTYPE=en_US.UTF-8       LC_NUMERIC=C
#  [3] LC_TIME=en_US.UTF-8        LC_COLLATE=en_US.UTF-8
#  [5] LC_MONETARY=en_US.UTF-8    LC_MESSAGES=en_US.UTF-8
#  [7] LC_PAPER=en_US.UTF-8       LC_NAME=C
#  [9] LC_ADDRESS=C               LC_TELEPHONE=C
# [11] LC_MEASUREMENT=en_US.UTF-8 LC_IDENTIFICATION=C
#
# time zone: Etc/UTC
# tzcode source: system (glibc)
#
# attached base packages:
# [1] stats     graphics  grDevices utils     datasets  methods   base
#
# loaded via a namespace (and not attached):
#  [1] httr_1.4.8        rentrez_1.2.4     compiler_4.5.2    R6_2.6.1
#  [5] cli_3.6.5         curl_7.0.0        xml2_1.5.2        R.methodsS3_1.8.2
#  [9] jsonlite_2.0.0    R.utils_2.13.0    rlang_1.1.7       XML_3.99-0.23
# [13] R.oo_1.27.1
