# AGENTS_CHANGELOG.md

Log of changes made by coding agents. Newest entries first.

Each entry should record what changed, why, and anything a future agent or
reviewer would otherwise have to rediscover, such as follow-up work left
undone or decisions that were deliberately deferred.

## 2026-08-26

### Fix MegaLinter linting errors across all linter categories

Ran `mega` locally and fixed all 46 reported errors:

- **bash-exec**: `chmod +x` on 17 shell scripts missing the executable bit
  (all `src/*.sh`, `verifications/*.sh`, `config/*.sh`, `.caprc`).
- **shfmt**: Reformatted all shell scripts with `shfmt -i 0 -bn -ci -sr`
  (tabs, no trailing whitespace, no space before `"` in redirections/herestrings).
- **black**: Reformatted `src/06_compile_multiqc_metrics.py` and
  `src/compare_csvs.py` to match black's formatting rules.
- **isort**: Fixed import ordering in both Python files (stdlib before
  third-party, blank line between groups).
- **markdownlint**: Added `.markdownlint.json` disabling MD003 (heading style),
  MD013 (line length), MD025 (single h1), and MD036 (emphasis-as-heading)
  since the project uses ATX headings, long table rows, and emphasis titles.
  Fixed blank-line issues around headings in `DEVELOPMENT.md` and `README.md`.

### Preserve literal "NA" strings from NCBI in metadata pipeline

Three changes ensure that the literal string `"NA"` (returned by NCBI for
missing attributes on some samples, e.g. cell cultures) is distinguished from
R's `NA` (true missing data):

1. `src/functions/get_bioproject_metadata.R` — `.fetch_biosample_attributes`
   now fills missing columns with `""` instead of `NA_character_`.
   `.parse_biosample_xml` now returns `""` for absent attributes instead of
   `NA_character_`.
2. `src/functions/get_bioproject_metadata.R` — `.write_metadata_tsv` now
   passes `na = ""` to `write.table` so R's `NA` is written as an empty
   field, not the literal string `"NA"`.
3. `src/05_transform_metadata.R` — After column-name lowercasing, replaces
   any literal `"NA"` string with `"Not applicable"` (does not affect R's `NA`
   since `==` returns `NA`, not `TRUE`, for the missing value).

Follow-up: the existing raw metadata TSVs in `data/raw-data/` were generated
before fix #2 and still contain literal `"NA"` strings for truly missing
fields. They should be regenerated with the updated fetch script.

## 2026-08-20

### Add overwrite option to step 05 transform script

Added a `OVERWRITE` environment variable check to `src/05_transform_metadata.sh`.
When `OVERWRITE=1` is set, the script will re-transform metadata even if the
output file already exists. Without it, the existing skip-if-exists behavior is
preserved.

## 2026-08-19

### Use a named constant for the not-provided sentinel (`418aa8a`)

`src/05_transform_metadata.R` previously wrote two distinct sentinel strings
into its output: `"NP"` for values the depositor did not provide, and `"NA"`
for values that were not applicable. Both are now a single `not_provided`
constant set to `"Not provided"`.

- Added `not_provided <- "Not provided"` in a new Constants section.
- Replaced all 12 `"NP"` output sites with the constant.
- Replaced the 4 `"NA"` output sites (the `cystic` and `control` entries in
  `underlying_variant_map`, and the `treatment` / `treatment_group`
  defaults). The `na.strings` argument on line 337 is input parsing, not an
  output sentinel, and was deliberately left as `"NA"`.
- Updated five comments that still documented the old two-sentinel scheme.

Naming note: the constant is `snake_case`, not `SCREAMING_SNAKE_CASE`.
lintr's `object_name_linter` is part of `linters_with_defaults()` and has no
separate convention for constants, so an uppercase name fails CI.

Also added `AGENTS.md`, `CLAUDE.md`, and this file.

Outstanding follow-ups:

- The md5 baselines in `verifications/05_transform_metadata.out` are stale.
  All 14 will mismatch on the next step 5 run because the output values
  changed. Regenerate them after a real run and review the diff.
- Merging `"NA"` into `"Not provided"` is lossy. "Not applicable" (wild-type
  has no causal gene) and "not provided" (depositor omitted the field) are
  now indistinguishable downstream. A comment in the script refers to a
  PostgreSQL consumer outside this repo; confirm it does not rely on the
  distinction.
- `"Not provided"` contains a space. This is TSV-safe given `sep = "\t"` and
  `quote = FALSE`, but any consumer splitting on whitespace will break.
- The transformation was never executed. `Rscript` is not on the Cheaha
  login host and `bin/container/rrc-datahub_0.1.1.sif` was not built, so the
  change is lint-clean and parses but is unverified at runtime.
