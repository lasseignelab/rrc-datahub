#!/bin/bash

#SBATCH --ntasks=1            
#SBATCH --time=02:00:00                    
#SBATCH --mem=12G
#SBATCH --partition=express

# GRCm39 M38 release
cap_data_download \
  --unzip \
  --md5sum="92c47db49fa5565133693482b0feb9c8" \
  "https://ftp.ebi.ac.uk/pub/databases/gencode/Gencode_mouse/release_M38/gencode.vM38.primary_assembly.annotation.gtf.gz"

cap_data_download \
  --unzip \
  --md5sum="3cb1b11c69e053250725be59b43061b9" \
  "https://ftp.ebi.ac.uk/pub/databases/gencode/Gencode_mouse/release_M38/GRCm39.primary_assembly.genome.fa.gz"
