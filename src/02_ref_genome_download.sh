#!/bin/bash

#SBATCH --ntasks=1            
#SBATCH --time=02:00:00                    
#SBATCH --mem=12G
#SBATCH --partition=express

# GRCm39 M37 release
cap_data_download \
  --unzip \
  --md5sum="702e27a8727db66cd23e9f66f5aa1d38" \
  --subdirectory "GRCm39_M37" \
  "https://ftp.ebi.ac.uk/pub/databases/gencode/Gencode_mouse/release_M37/gencode.vM37.primary_assembly.annotation.gtf.gz"

cap_data_download \
  --unzip \
  --md5sum="551c3d4ad6da2503ae0b7ebfe02a2c3c" \
  --subdirectory "GRCm39_M37" \
  "https://ftp.ebi.ac.uk/pub/databases/gencode/Gencode_mouse/release_M37/GRCm39.primary_assembly.genome.fa.gz"

# GRCh38 v50 release
cap_data_download \
  --unzip \
  --md5sum="4e6bbda4b74c9033d0f1209581c8b97d" \
  --subdirectory "GRCh38_v50" \
  "https://ftp.ebi.ac.uk/pub/databases/gencode/Gencode_human/release_50/gencode.v50.primary_assembly.annotation.gtf.gz"
  
cap_data_download \
  --unzip \
  --md5sum="da1a11258be075cfa7af718162c894e7" \
  --subdirectory "GRCh38_v50" \
  "https://ftp.ebi.ac.uk/pub/databases/gencode/Gencode_human/release_50/GRCh38.primary_assembly.genome.fa.gz"




