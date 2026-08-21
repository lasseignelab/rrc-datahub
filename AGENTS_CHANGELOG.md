# AGENTS_CHANGELOG.md

Log of changes made by coding agents. Newest entries first.

Each entry should record what changed, why, and anything a future agent or
reviewer would otherwise have to rediscover, such as follow-up work left
undone or decisions that were deliberately deferred.

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
