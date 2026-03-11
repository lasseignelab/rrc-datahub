#!/bin/bash

#SBATCH --nodes=1
#SBATCH --ntasks=1  
#SBATCH --cpus-per-task=1
#SBATCH --mem-per-cpu=2G
#SBATCH --time=2:00:00
#SBATCH --partition=express
#SBATCH --array=0-13

echo "Downloading helper script for creating samplesheet ..."
file="$CAP_PROJECT_PATH/src/03_fastq_dir_to_samplesheet.py"
url="https://raw.githubusercontent.com/nf-core/rnaseq/refs/heads/master/bin/fastq_dir_to_samplesheet.py"
wget -nc -O "$file" "$url"

dataset=$(cap_array_value "$CAP_PROJECT_PATH/doc/geo_datasets.csv")
echo "Creating samplesheet for ${dataset} ..."
fastq_dir="$CAP_DATA_PATH/raw-data/${dataset}"
cd "$fastq_dir" || exit

if ls -- *_1.fastq.gz 1> /dev/null 2>&1; then
    python3 "$file" "$fastq_dir" "$fastq_dir/samplesheet.csv" \
    -r1 "_1.fastq.gz" \
    -r2 "_2.fastq.gz"
else
    python3 "$file" "$fastq_dir" "$fastq_dir/samplesheet.csv" \
    -r1 ".fastq.gz" \
    -se
fi

sed -i 's|/[^,]*/data/raw-data/|../data/raw-data/|g' "$fastq_dir/samplesheet.csv"

echo -e "\tSamplesheet created successfully"
