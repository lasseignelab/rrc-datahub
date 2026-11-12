#!/bin/bash

cap_verify_append "##### nf-core/rnaseq pipeline files #####"
cap_verify_append "$(tree data/nfcore_rnaseq/ \
  -I "pipeline_info|fastqc|fq_lint|multiqc_report_plots|multiqc_report_data|index|rsem|dupradar|featurecounts|qualimap|rseqc|samtools_stats|picard_metrics|log|stringtie|trimgalore" \
  -P "*.tsv|*.rds|*.RData|*.sf|*.json|*.bam|*.bai|*.gtf|*.fa|*.txt|*.html")"
