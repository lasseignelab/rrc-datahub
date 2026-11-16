#!/bin/bash

cap_verify_append "fastq MD5 sums:"
cap_verify_md5 data/raw-data/ --select "*.gz"
cap_verify_append "metadata TSV MD5 sums:"
cap_verify_md5 data/raw-data/*/ --select "*_metadata.tsv"
