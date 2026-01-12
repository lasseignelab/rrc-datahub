#!/bin/bash

#SBATCH --ntasks=1
#SBATCH --mem=12G
#SBATCH --partition=express
#SBATCH --time=01:00:00

module load Anaconda3

conda env create -f "${CAP_CONDA_PATH}/rrc-datahub-nfcore.yml"
