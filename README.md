README
================
2026-07-10

**PKD RRC DataHub**

## Purpose

**\[Replace this section with the purpose of your research project.\]**
This is an R Markdown document created for the Lasseigne Lab R Project
Template. The project and README template are designed to create
standardized R projects for research ongoing in the [Lasseigne Lab at
the University of Alabama at Birmingham](https://www.lasseigne.org/)

## Installation/Dependencies OR Scripts

**\[if project will be a package\]** - this section should be titled
“Installation” Include a code chunk on how to install your package

**\[if project will not be a package\]** - this section should be titled
“Dependencies” or “Scripts” Include a code chunk (if relevant) on what
your project depends on. Include a “script tree” on how to reproduce
your results with descriptions for all scripts

## Pipeline Execution Guide

Run each step in order. Each step includes a verification command — run
it and check the diff before moving to the next step.

### 1. Data download

Downloads raw data from GEO.

``` bash
cap run -e default -s batch src/01_geo_download.sh
```

**Verify:**

``` bash
cap verify verifications/01_geo_download.sh -s batch
```

Once verification finishes, run:

``` bash
git diff verifications/01_geo_download.out
```

### 2. Reference genome download

Downloads the reference genome used for alignment.

``` bash
cap run -e default -s batch src/02_ref_genome_download.sh
```

**Verify:**

``` bash
cap verify verifications/02_ref_genome_download.sh
```

Once verification finishes, run:

``` bash
git diff verifications/02_ref_genome_download.out
```

### 3. Data alignment

Creates the conda environment and generates nf-core/rnaseq samplesheets.

``` bash
cap run -e default -s batch src/00_create_conda_env.sh
cap run -e default -s batch src/03_generate_nfcore_rnaseq_samplesheets.sh
```

Once both finish, run the alignment pipeline:

``` bash
cap run -e default -s batch src/04_run_nfcore_rnaseq.sh
```

**Verify:**

``` bash
cap verify -s batch verifications/04_run_nfcore_rnaseq.sh
```

Once verification finishes, run:

``` bash
git diff verifications/04_run_nfcore_rnaseq.out
```

### 4. Transform metadata

``` bash
cap run -e default -s batch src/05_transform_metadata.sh
```

**Verify:**

``` bash
cap verify verifications/05_transform_metadata.sh -s batch
```

Once verification finishes, run:

``` bash
git diff verifications/05_transform_metadata.out
```

### 5. QC metadata compilation

Compiles MultiQC metrics across datasets.

``` bash
cap run -e default -s batch src/06_compile_multiqc_metrics.sh
```

**Verify:**

``` bash
cap verify verifications/06_compile_multiqc_metrics.sh
```

Once verification finishes, run:

``` bash
git diff verifications/06_compile_multiqc_metrics.out
```

## Authors

List co-authors if known here.

## Lasseigne Lab

[What is Happening in the Lasseigne Lab?](https://www.lasseigne.org/)

## Funding

List project funding sources.

## Acknowledgements

List project acknowledgements.

## License

This repository is licensed under the MIT License, see LICENSE
documentation within this repository for more details.
