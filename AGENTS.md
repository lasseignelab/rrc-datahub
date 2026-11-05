# AGENTS.md

## Changelog

Record any change you make in `AGENTS_CHANGELOG.md`, newest first. Note what
changed, why, and any follow-up work left undone, so the next agent does not
have to rediscover it. Add the entry in the same commit as the change.

## What this repo is

Research data pipeline for the Lasseigne Lab (UAB). Downloads GEO RNA-seq data, aligns with nf-core/rnaseq on Cheaha HPC, and compiles QC metadata. Languages: Bash, R, Python. Managed by `cap` (project scaffolding and pipeline runner).

## Pipeline execution

Steps are numbered shell scripts in `src/`. Run them in order via `cap run`. Each step has a matching verification script in `verifications/`.

```bash
# General pattern:
cap run -e default -s batch src/NN_step_name.sh
cap verify -s batch verifications/NN_step_name.sh   # when -s batch needed
git diff verifications/NN_step_name.out              # review before proceeding
```

See `README.md` for the exact step-by-step sequence. Steps 3a/3b (conda env + samplesheets) must run before 3c (nf-core pipeline).

## Key files

| Path                     | Purpose                                                         |
|--------------------------|-----------------------------------------------------------------|
| `src/`                   | Pipeline scripts (numbered 00-06), helper R in `src/functions/` |
| `config/pipeline.sh`     | Project name and random seed for `cap`                          |
| `config/cheaha.config`   | Nextflow SLURM config for Cheaha HPC                            |
| `config/nextflow.config` | nf-core/rnaseq params (gencode=true)                            |
| `.caprc`                 | Sets `NFCORE_RNASEQ_VERSION` (currently 3.25.0)                 |
| `doc/geo_datasets.csv`   | Input dataset list consumed by step 01                          |
| `verifications/`         | Verification scripts + `.out` baselines for `cap verify`        |
| `data/`                  | Gitignored raw data (downloaded by step 01)                     |
| `results/`               | Pipeline outputs; `results/transformed-metadata/` is tracked    |
| `AGENTS_CHANGELOG.md`    | Running log of agent changes; append to it, newest first        |

## Running tests

R tests use testthat inside a Singularity container. Requires `bin/container/rrc-datahub_0.1.1.sif` to exist locally.

```bash
cap run -edefault tests/run
```

CI runs the same command via `Rscript -e 'testthat::test_dir("tests/testthat", stop_on_failure = TRUE)'` inside the container image `acrumley/rrc-datahub:0.1.1`.

## Linting

MegaLinter runs on every push in CI, covering Python, R, Bash, Perl, and Markdown. Locally, the relevant linters are configured via `.pylintrc`, `.lintr`, and `pyrightconfig.json` (basic mode, no import checking).

## Things to know

- Pipeline scripts are SLURM batch jobs (`#SBATCH` headers). They are not meant to be run interactively on a laptop.
- `cap` provides env variables like `CAP_DATA_PATH`, `CAP_PROJECT_PATH`, `CAP_CONTAINER_PATH`, `CAP_ENV_PATH` that scripts depend on.
- Data downloads use `cap_data_download` and `cap_array_value` helpers, not raw curl/wget.
- Singularity containers are stored in `bin/container/` (gitignored `.sif` files). Build with `cap_container`.
- The `data/` directory is gitignored except for `data/README`.
- `src/03_fastq_dir_to_samplesheet.py` is gitignored (generated file).
