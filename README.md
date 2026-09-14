README
================
2026-09-14

**PKD RRC DataHub**

## Purpose

This repository contains the data processing pipeline for the **PKD RRC
DataHub**, a community resource for polycystic kidney disease (PKD)
research. The pipeline downloads public RNA-seq datasets from GEO,
aligns them against a reference genome using `nf-core/rnaseq`, and
compiles QC and sample metadata into a format ready for ingestion into
the DataHub platform. All steps run through the CAPTURE framework
(`cap run`/`cap verify`) on UAB’s Cheaha HPC cluster for
reproducibility.

This is an R Markdown document created for the Lasseigne Lab R Project
Template. The project and README template are designed to create
standardized R projects for research ongoing in the [Lasseigne Lab at
the University of Alabama at Birmingham](https://www.lasseigne.org/)

## Input Data

DataHub 0.1 is mouse-only Illumina bulk RNA-seq; future releases will
expand to additional species and sequencing types.

| Accession   | Species | Sequencing type | Original publication             |
|-------------|---------|-----------------|----------------------------------|
| PRJNA629819 | Mouse   | Bulk RNA-seq    | Zhang et al., 2021               |
| PRJNA285844 | Mouse   | Bulk RNA-seq    | Lakhia et al., 2016              |
| PRJNA556224 | Mouse   | Bulk RNA-seq    | Lee et al., 2019                 |
| PRJNA805542 | Mouse   | Bulk RNA-seq    | Lakhia et al., 2022              |
| PRJNA857739 | Mouse   | Bulk RNA-seq    | Swenson-Fields et al., 2022      |
| PRJNA745972 | Mouse   | Bulk RNA-seq    | Friedrich et al., 2021           |
| PRJNA543107 | Mouse   | Bulk RNA-seq    | Olson et al., 2019               |
| PRJNA353115 | Mouse   | Bulk RNA-seq    | Hajarnis et al., 2017            |
| PRJNA342113 | Mouse   | Bulk RNA-seq    | Woo et al., 2017                 |
| PRJNA805547 | Mouse   | Bulk RNA-seq    | Lakhia & Ramalingam et al., 2022 |
| PRJNA573926 | Mouse   | Bulk RNA-seq    | Lakhia et al., 2020              |
| PRJNA428970 | Mouse   | Bulk RNA-seq    | Aboudehen et al., 2018           |
| PRJNA637874 | Mouse   | Bulk RNA-seq    | Dixon et al., 2020               |
| PRJNA556227 | Mouse   | Bulk RNA-seq    | Lee et al., 2019                 |

## Scripts

This pipeline is run via the CAPTURE framework and depends on: - CAPTURE
(`cap` CLI) for reproducible batch execution and verification - Conda
(environment created in step 3) - `nf-core/rnaseq` for alignment

**Script tree:**

| Script | Description |
|----|----|
| `src/00_create_conda_env.sh` | Creates the conda environment used for downstream data alignment |
| `src/01_geo_download.sh` | Downloads raw RNA-seq data from GEO |
| `src/02_ref_genome_download.sh` | Downloads the reference genome used for alignment |
| `src/03_generate_nfcore_rnaseq_samplesheets.sh` | Generates nf-core/rnaseq samplesheets |
| `src/04_run_nfcore_rnaseq.sh` | Runs the nf-core/rnaseq alignment pipeline |
| `src/05_transform_metadata.sh` | Reshapes/transforms sample metadata |
| `src/06_compile_multiqc_metrics.sh` | Compiles MultiQC QC metrics across datasets |

## Tool & Reference Versions

- CAPTURE: v1.0.0
- nf-core/rnaseq: v3.25.0
- Reference genome: GRCm39, release M37
- All other tools are containerized (conda/Docker). Please see pipeline
  configs for exact pinned versions.

## Pipeline Execution Guide

Run each step in order. Each step includes a verification command run it
and check the diff before moving to the next step.

### 1. Data download

Downloads raw data from GEO.

``` bash
cap run -e default -s batch src/01_geo_download.sh
```

**Verify:**

``` bash
cap verify -s batch verifications/01_geo_download.sh
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
cap verify -s batch verifications/05_transform_metadata.sh
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

## Output

Processed gene expression matrices generated by this pipeline are
archived on Zenodo for reuse in independent analyses: \[DOI link to be
added\].

## Authors

Tabea M. Soelter, Anthony B. Crumley, Kieran Casper, Elizabeth Okunbor,
Brittany N. Lasseigne

## Lasseigne Lab

[What is Happening in the Lasseigne Lab?](https://www.lasseigne.org/)

## Funding

This work was supported by NIH grant 2U54DK126087-06.

## Related Work

This pipeline feeds the [PKD RRC DataHub web
application](https://github.com/lasseignelab/rrc-datahub-web), where the
processed data is visualized and made available to the research
community.

## Contact

For questions or issues, please open an issue on this repository’s
GitHub Issues page.

## Acknowledgements

We would like to thank all members of the Lasseigne lab and the UAB/CHOP
PKD group for their feedback on this project.

## License

This repository is licensed under the MIT License, see LICENSE
documentation within this repository for more details.
