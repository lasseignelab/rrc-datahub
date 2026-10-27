### Sample metadata transformation
# Author: Kieran Casper, with AI assistance from Claude (Anthropic)
# Date: April 23, 2026
# Revised: October 27, 2026 (human datasets, disease_state, exit codes)
## Goal: Transform raw BioProject sample metadata TSVs into harmonized,
##       analysis-ready TSVs with normalized column names, controlled
##       vocabulary fields, and derived biological annotations.
## Reproducibility:
# * GitHub: lasseignelab/rrc-datahub
#
## Harmonization rules applied (one rule set for every species):
# * Column names lowercased; values trimmed. NCBI placeholders ("missing",
#   "not collected", "not provided", "not available") become Not provided;
#   "not applicable" becomes NA.
# * Genotype: first non-empty of genotype / genotype.variation /
#   control.or.cystic, copied as written by the submitter. underlying_variant
#   is the harmonized causal gene (canonical spelling, e.g. Pkd1, Bicc1),
#   found by (1) the exact-string table (case-insensitive), (2) a
#   wild-type rule, (3) standalone gene symbols from causal_genes. A genotype
#   that matches nothing gets NA (no listed gene) and is listed in the
#   report as INFO.
# * disease_state (column 36): cystic / non-cystic. Read from phenotype,
#   diagnosis or control.or.cystic first (unrecognised value = UNMAPPED),
#   otherwise from state words in tissue, source_name or cell.type.
#   microcystic, cyst and ADPKD all normalise to cystic.
# * Strain: strain_raw is the first non-empty of strain / strain.background /
#   background.strain / cell.line / cell.line.background, so a human cell
#   line is recorded where a mouse strain would be. strain is the same
#   value with spelling normalised; generic material words (Organoid, Tissue)
#   are not strains, so strain is Not provided for them (strain_raw keeps
#   the raw value and sample_type uses it).
# * sample_type: in_vivo_tissue, cell_line, organoid, ipsc_derived or
#   primary_cells, derived from source_name, cell line, cell.type, strain and
#   tissue by ordered rules (see .derive_sample_type). No match = UNMAPPED.
# * Tissue: any value containing "kidney" becomes kidney; any other value is
#   kept as written (and listed in the report as INFO). Age embedded in a
#   tissue string (e.g. "postnatal day 7-10 kidney") is split out.
# * Age: first non-empty of age / time. Postnatal day N, N-M, "N days/weeks/
#   months (old)" are converted to integer days (7-day week, 30-day month)
#   and stored as age_range_lower / age_range_upper (single ages have
#   lower == upper). Culture time (e.g. "10 days" of differentiation) is
#   treated as age. Passage notation (P4) is recognised but not a duration:
#   age_raw keeps it and the ranges are Not provided. Any other age string is
#   UNMAPPED in the report (ranges Not provided).
# * Culture descriptions in the treatment column (culture or differentiation
#   wording plus a duration, no dose, no known compound or vehicle) are not
#   treatments: treatment becomes NA and the duration becomes the age.
# * treatment_group: vehicle_control (vehicle words, zero doses),
#   experimental (listed compounds, non-zero doses), untreated. No
#   treatment column = NA. Anything else = UNMAPPED.
# * Sex consolidated from sex.y / sex; sex.x (always blank) dropped.
# * Not provided = depositor gave no value; NA = not applicable;
#   UNMAPPED = a value was present but no rule matched it.
#
## Output: <bioproject>_transformed.tsv (36 columns; columns 1-35 are
##   unchanged in position and meaning, disease_state is appended).
##   <bioproject>_transform_report.txt is written next to it whenever any
##   value is UNMAPPED or INFO-worthy, with the column, raw value, the
##   rows and the run accessions affected. Any stale report is removed.
#
## Exit codes:
# * 0: finished, nothing UNMAPPED
# * 1: hard error (bad arguments, missing columns, a true NA reached the
#      writer, unreadable input). No output is written.
# * 2: output written, but at least one value is UNMAPPED. Read the report
#      and add rows to the lookup tables below.
#
## Changes from the previous version (all intended):
# * NP is now "Not provided"; the dplyr dependency was removed.
# * Lookups are case- and whitespace-insensitive.
# * UNMAPPED no longer stops the script; it is reported and exit code 2.
# * sample_type is now checked for UNMAPPED (it was not before).
# * strain / strain_raw also read cell.line and cell.line.background.
# * Tissue strings containing "kidney" collapse to kidney.
# * Age parser rewritten (the old one could misalign rows when only some
#   rows matched) and extended to days / weeks / months and passage.
#   Age strings that the old parser silently left as NP are now reported.
# * Unit symbols such as the micro sign are not recognised in doses
#   (uM and nM are); extend dose_unit_rx if needed.
#
# Arguments:
# * args[1]: BioProject accession (e.g. "PRJNA285844")
# * args[2]: Path to the input metadata TSV
# * args[3]: Path to the output directory

# ---------------------------------------------------------------------------
# Parse command-line arguments
# ---------------------------------------------------------------------------
args <- commandArgs(trailingOnly = TRUE)

if (length(args) != 3L) {
  stop(
    "Usage: Rscript 05_transform_metadata.R <bioproject_id> ",
    "<input_tsv> <output_dir>"
  )
}

bioproject_id <- args[1]
input_path    <- args[2]
output_dir    <- args[3]

message("Starting metadata transformation for ", bioproject_id)

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
NOT_PROVIDED   <- "Not provided"
NOT_APPLICABLE <- "NA"
UNMAPPED       <- "UNMAPPED"
EXIT_FLAGGED   <- 2L

# ---------------------------------------------------------------------------
# Lookup tables
# All controlled-vocabulary mappings are defined here so they are visible,
# auditable, and easy to extend when new projects are added.
# ---------------------------------------------------------------------------

# Raw values that mean "nothing was provided" / "not applicable"
placeholder_not_provided   <- c(
  "missing", "not collected", "not provided", "not available"
)
placeholder_not_applicable <- c("not applicable")

# Causal genes recognised as standalone symbols inside a genotype string,
# in the canonical spelling written to underlying_variant. Add a symbol here
# when a new gene is studied. Matching is case-insensitive.
causal_genes <- c("Pkd1", "Pkd2", "Pkhd1", "Bicc1")

# Exact genotype strings (matched case-insensitively, whitespace collapsed).
# Needed where the gene cannot be read off the string: floxed alleles without
# Cre are wild-type, and a Cre driver (Pkhd1Cre, KSP/Cre) is not the causal
# gene.
# wild-type : sample has no PKD-related mutation
# NA        : genotype concept not applicable (control.or.cystic projects,
#             and control samples in engineered cell lines)
underlying_variant_exact <- c(
  # PRJNA285844
  "wild-type"                              = "wild-type",
  "Pkhd1Cre; Pkd2 F/F"                   = "Pkd2",
  "Pkhd1Cre; Pkd2 F/F; miR-21null"       = "Pkd2",
  # PRJNA342113
  "Pkd1f/f"                               = "wild-type",
  "Pkd1f/f:HoxB7-Cre"                    = "Pkd1",
  "Pkd2f/f"                               = "wild-type",
  "Pkd2f/f:HoxB7-Cre"                    = "Pkd2",
  # PRJNA353115
  "KspCre; Pkd1 F/RC"                    = "Pkd1",
  "KspCre; Pkd1 F/RC miR17~92 F/F"      = "Pkd1",
  # PRJNA428970
  "KSP/Cre-;Pkd1f/f"                     = "wild-type",
  "KSP/Cre+;Pkd1f/f"                     = "Pkd1",
  "Pkhd1/Cre-;Pkd2f/f"                   = "wild-type",
  "Pkhd1/Cre+;Pkd2f/f"                   = "Pkd2",
  # PRJNA543107
  "WT"                                    = "wild-type",
  "Pkd1-RC/RC"                            = "Pkd1",
  "Pkhd1-/-"                              = "Pkhd1",
  "Digenic"                               = "Pkd1;Pkhd1",
  # PRJNA556224
  "Pdk2KO"                                = "Pkd2",
  "wildtype"                              = "wild-type",
  # PRJNA573926
  "Pkhd1Cre; Pkd2 F/F; miR-214null"     = "Pkd2",
  # PRJNA629819
  "Wild type"                             = "wild-type",
  "Pkd2fl/fl;Pax8rtTA;TetO-cre"         = "Pkd2",
  "Ift88fl/fl;Pkd2fl/fl;Pax8rtTA;TetO-cre" = "Pkd2",
  # PRJNA637874
  "Pkd2fl/fl Pax8rtTA TetOCre mTmG"     = "Pkd2",
  # PRJNA745972
  "Pkd1-/-"                               = "Pkd1",
  "Pkd2-/-"                               = "Pkd2",
  # PRJNA857739
  "Pkd1RC/RC-Casp1KO"                    = "Pkd1",
  "Pkd1RC/RC"                             = "Pkd1",
  "cystic"                                = "NA",
  "control"                               = "NA"
)

# Map strain strings to canonical normalized values.
# Only genuine spelling variants are normalized; biologically distinct
# strains (Pcy/CD1, CD1) are left as-is.
strain_norm_map <- c(
  "C57BL/6J" = "C57BL/6",
  "C57BL6"   = "C57BL/6"
)

# A value in a strain/cell-line field that names the kind of material
# rather than a strain or cell line (submitters sometimes put it there).
material_word_rx <- "^(?:organoids?|tissues?|tubuloids?|spheroids?|primary cells?|cells?|cultures?)$"

# Exact source_name values for sample_type (case-insensitive). Everything
# else goes through the ordered rules in .derive_sample_type().
sample_type_map <- c(
  "primary cell tubuloids"                      = "organoid",
  "murine inner medullary collecting duct cells" = "cell_line",
  "Cultured mIMCD-3 Cells (ATCC CRL-2123)"     = "cell_line"
)

# Keyword rules used by .derive_sample_type(); all case-insensitive.
rx_organoid  <- "(?<![a-z0-9])(?:organoids?|tubuloids?|spheroids?)(?![a-z0-9])"
rx_tissue    <- "^tissues?$"
rx_ipsc      <- paste0(
  "(?<![a-z0-9])(?:hipsc|hips|ipsc|ips)s?(?![a-z0-9])",
  "|induced pluripotent|pluripotent|differentiated"
)
rx_cell_line <- "cell[- ]line|immortali[sz]ed"
rx_primary   <- "(?<![a-z0-9])primary(?![a-z0-9])"

# Treatment groups. Exact strings first (case-insensitive), then the rules
# in .assign_treatment_group(): vehicle / untreated words, zero dose,
# listed compounds, non-zero dose.
treatment_group_map <- c(
  "RGLS4326"     = "experimental",
  "DOX"          = "experimental",
  "PBS"          = "vehicle_control",
  "DMSO"         = "vehicle_control",
  "No treatment" = "untreated"
)
vehicle_words        <- c("vehicle", "pbs", "dmso", "saline")
untreated_rx         <- "^(?:no treatment|untreated)$"
experimental_compounds <- c(
  "RGLS4326", "DOX", "doxycycline", "sulforaphane", "SFN", "QNZ"
)

# Doses: a number followed by one of these units. Zero doses mean the
# carrier only (vehicle_control); non-zero doses mean experimental.
dose_unit_rx <- "(?:pm|nm|um|mm|mg|ug|ng)(?![a-z])"
zero_dose_rx <- paste0("(?<![0-9.])0+(?:\\.0+)?\\s*", dose_unit_rx)
any_dose_rx  <- paste0("(?<![0-9.])\\d+(?:\\.\\d+)?\\s*", dose_unit_rx)

# Durations (age and culture time)
duration_days <- c(day = 1L, week = 7L, month = 30L)
duration_rx   <- "(?<![0-9.])\\d+\\s*(?:day|week|month)s?(?![a-z])"
culture_words_rx <- paste0(
  "(?<![a-z0-9])(?:cultured|differentiated|derived|passaged|maintained)",
  "(?![a-z0-9])"
)

# disease_state vocabularies. Dedicated fields (phenotype, diagnosis,
# control.or.cystic) must match the whole value; "control" only counts as
# non-cystic in control.or.cystic. Free-text fields (tissue, source_name,
# cell.type) are scanned for the words, negations first.
state_cystic_rx     <- paste0(
  "^(?:cysts?|cystic|microcystic|macrocystic|adpkd|arpkd|pkd|",
  "polycystic(?: kidney disease)?)$"
)
state_non_cystic_rx <- "^(?:non[- ]?cystic|non[- ]?pkd|normal|healthy)$"
state_control_rx    <- "^control$"
free_non_cystic_rx  <- paste0(
  "(?<![a-z])(?:non[- ]?cystic|non[- ]?pkd|healthy|normal)(?![a-z])"
)
free_cystic_rx      <- paste0(
  "cyst|adpkd|arpkd|polycystic|(?<![a-z])pkd(?![a-z])"
)

# ---------------------------------------------------------------------------
# Helper functions
# ---------------------------------------------------------------------------

#' Escape regex metacharacters so a literal string can be used in a pattern.
.rx_escape <- function(x) {
  gsub("([.|()\\^{}+$*?\\[\\]\\\\])", "\\\\\\1", x, perl = TRUE)
}

#' tolower() that never errors on strings invalid in the current locale.
.safe_tolower <- function(x) {
  tryCatch(tolower(x), error = function(e) x)
}

#' Trim values and convert NCBI placeholder words.
#' Blank and placeholder values become NA (written later as Not provided);
#' "not applicable" becomes the string NA.
.clean_values <- function(x) {
  x   <- tryCatch(trimws(x), error = function(e) x)
  low <- .safe_tolower(x)
  to_missing <- !is.na(low) & low %in% placeholder_not_provided
  to_na      <- !is.na(low) & low %in% placeholder_not_applicable
  x[to_missing] <- NA_character_
  x[to_na]      <- NOT_APPLICABLE
  x[!is.na(x) & x == ""] <- NA_character_
  x
}

#' Consolidate a concept spread across several column name variants.
#'
#' Tries each candidate column name in order and returns the first non-NA,
#' non-empty value found. Returns NA_character_ if none are present.
#'
#' @param df       data.frame to search.
#' @param columns  Character vector of candidate column names in priority order.
#' @return Character vector with the consolidated values.
.coalesce_columns <- function(df, columns) {
  result <- rep(NA_character_, nrow(df))
  for (col in columns) {
    if (col %in% colnames(df)) {
      candidate <- as.character(df[[col]])
      candidate[trimws(candidate) == ""] <- NA_character_
      fill <- is.na(result) & !is.na(candidate)
      result[fill] <- candidate[fill]
    }
  }
  result
}

#' Same as .coalesce_columns() but also returns which column each value
#' came from.
#'
#' @return data.frame with columns value and source.
.coalesce_with_source <- function(df, columns) {
  value  <- rep(NA_character_, nrow(df))
  source <- rep(NA_character_, nrow(df))
  for (col in columns) {
    if (col %in% colnames(df)) {
      candidate <- as.character(df[[col]])
      candidate[trimws(candidate) == ""] <- NA_character_
      fill <- is.na(value) & !is.na(candidate)
      value[fill]  <- candidate[fill]
      source[fill] <- col
    }
  }
  data.frame(value = value, source = source, stringsAsFactors = FALSE)
}

#' TRUE where x matches rx (case-insensitive, PCRE); FALSE for NA.
.grepl_i <- function(rx, x) {
  !is.na(x) & grepl(paste0("(?i)", rx), x, perl = TRUE)
}

#' TRUE where any of the supplied character vectors matches rx.
.any_match <- function(rx, ...) {
  fields <- list(...)
  hit <- rep(FALSE, length(fields[[1L]]))
  for (f in fields) {
    hit <- hit | .grepl_i(rx, f)
  }
  hit
}

#' Extract one capture group from the first match of rx.
#' Returns NA where rx does not match. rx may be anchored with ^ and $.
.capture <- function(x, rx, group = 1L) {
  hit    <- .grepl_i(rx, x)
  result <- rep(NA_character_, length(x))
  prefix <- if (startsWith(rx, "^")) "" else "^.*?"
  suffix <- if (endsWith(rx, "$")) "" else ".*$"
  result[hit] <- sub(
    paste0("(?i)", prefix, rx, suffix),
    paste0("\\", group),
    x[hit],
    perl = TRUE
  )
  result
}

#' Convert a count and a unit (day / week / month) to integer days.
#' Uses a 7-day week and a 30-day month approximation; precision beyond
#' this is not warranted given how age is reported across studies.
.duration_to_days <- function(n, unit) {
  as.integer(round(as.numeric(n) * unname(duration_days[tolower(unit)])))
}

#' Parse an age string to integer day bounds.
#'
#' Recognises (in order): postnatal day N-M, postnatal day N, "N-M units",
#' "N units (old)" with units day / week / month, and passage notation (P4).
#'
#' @param x Character vector of raw age strings.
#' @return List with integer vectors $lower and $upper, and character vector
#'   $status: "none" (no value), "parsed", "passage" (recognised, not a
#'   duration) or "unparsed" (value present but not recognised).
.parse_age <- function(x) {
  n      <- length(x)
  lower  <- rep(NA_integer_, n)
  upper  <- rep(NA_integer_, n)
  x      <- trimws(x)
  status <- ifelse(is.na(x), "none", "unparsed")

  # postnatal day range, e.g. "postnatal day 7-10"
  rx  <- "post[- ]?natal\\s*day\\s*(\\d+)-(\\d+)"
  hit <- status == "unparsed" & .grepl_i(rx, x)
  lower[hit]  <- as.integer(.capture(x[hit], rx, 1L))
  upper[hit]  <- as.integer(.capture(x[hit], rx, 2L))
  status[hit] <- "parsed"

  # postnatal day single, e.g. "postnatal day 21"
  rx  <- "post[- ]?natal\\s*day\\s*(\\d+)"
  hit <- status == "unparsed" & .grepl_i(rx, x)
  lower[hit]  <- as.integer(.capture(x[hit], rx, 1L))
  upper[hit]  <- lower[hit]
  status[hit] <- "parsed"

  # generic range, e.g. "7-10 days"
  rx  <- "^(\\d+)\\s*-\\s*(\\d+)\\s*(day|week|month)s?(?:\\s+old)?$"
  hit <- status == "unparsed" & .grepl_i(rx, x)
  unit <- .capture(x[hit], rx, 3L)
  lower[hit]  <- .duration_to_days(.capture(x[hit], rx, 1L), unit)
  upper[hit]  <- .duration_to_days(.capture(x[hit], rx, 2L), unit)
  status[hit] <- "parsed"

  # generic single, e.g. "10 days", "6 weeks", "3 months old"
  rx  <- "^(\\d+)\\s*(day|week|month)s?(?:\\s+old)?$"
  hit <- status == "unparsed" & .grepl_i(rx, x)
  unit <- .capture(x[hit], rx, 2L)
  lower[hit]  <- .duration_to_days(.capture(x[hit], rx, 1L), unit)
  upper[hit]  <- lower[hit]
  status[hit] <- "parsed"

  # passage notation, e.g. "P4": recognised but not a duration
  hit <- status == "unparsed" & .grepl_i("^p\\s*\\d+$", x)
  status[hit] <- "passage"

  list(lower = lower, upper = upper, status = status)
}

#' Extract age information embedded in tissue strings.
#'
#' Some submitters include age information inside the tissue field
#' (e.g. "postnatal day 7-10 kidney"). This function detects any tissue
#' value that contains both an age pattern and a tissue keyword, splits
#' them out, and updates tissue, age_lower, age_upper, and age_raw.
#' Both single ages and ranges are supported — single ages have
#' age_lower == age_upper.
#'
#' @param tissue_raw Character vector of raw tissue values.
#' @param age_lower  Integer vector of lower age bounds.
#' @param age_upper  Integer vector of upper age bounds.
#' @param age_raw    Character vector of raw age strings.
#' @return A list with elements $tissue, $age_lower, $age_upper, $age_raw.
.extract_age_from_tissue <- function(tissue_raw, age_lower,
                                     age_upper, age_raw) {
  # Detect tissue strings that contain an embedded age pattern
  # Pattern: postnatal day N or postnatal day N-M followed by a tissue word
  embedded_pattern <- "(?i)(post[- ]?natal\\s*day\\s*\\d+(?:-\\d+)?)\\s+(.+)"
  has_embedded <- !is.na(tissue_raw) &
    grepl(embedded_pattern, tissue_raw, perl = TRUE)

  if (any(has_embedded)) {
    matched <- tissue_raw[has_embedded]

    # Extract age string (first capture group)
    age_str <- gsub(embedded_pattern, "\\1", matched, perl = TRUE)
    # Extract tissue string (second capture group)
    tissue_str <- gsub(embedded_pattern, "\\2", matched, perl = TRUE)

    # Check if the age is a range (e.g. "7-10")
    range_pattern <- "(\\d+)-(\\d+)"
    is_range <- grepl(range_pattern, age_str, perl = TRUE)

    for (idx in seq_along(matched)) {
      age_raw[has_embedded][idx]    <- matched[idx]
      tissue_raw[has_embedded][idx] <- tissue_str[idx]

      if (is_range[idx]) {
        lo <- as.integer(gsub(
          paste0(".*", range_pattern, ".*"), "\\1",
          age_str[idx], perl = TRUE
        ))
        hi <- as.integer(gsub(
          paste0(".*", range_pattern, ".*"), "\\2",
          age_str[idx], perl = TRUE
        ))
        age_lower[has_embedded][idx] <- lo
        age_upper[has_embedded][idx] <- hi
      } else {
        single <- suppressWarnings(
          as.integer(gsub(".*?(\\d+).*", "\\1",
                          age_str[idx], perl = TRUE))
        )
        age_lower[has_embedded][idx] <- single
        age_upper[has_embedded][idx] <- single
      }
    }

    message(
      "  Extracted age from tissue string for ",
      sum(has_embedded), " row(s) (",
      sum(is_range), " range(s))"
    )
  }

  list(
    tissue    = tissue_raw,
    age_lower = age_lower,
    age_upper = age_upper,
    age_raw   = age_raw
  )
}

#' Assign underlying_variant (causal gene) from raw genotype strings.
#'
#' Order: exact table, wild-type rule, standalone gene symbols. A genotype
#' that matches nothing gets NA (no listed gene). A missing genotype gets
#' Not provided.
#'
#' @param genotype   Character vector of raw genotype strings.
#' @param exact_map  Named character vector of exact strings to values.
#' @param genes      Canonical gene symbols recognised as standalone tokens.
#' @return List with $value and $basis ("table", "gene", "none", "missing").
.assign_underlying_variant <- function(genotype, exact_map, genes) {
  n       <- length(genotype)
  x       <- gsub("\\s+", " ", trimws(genotype))
  value   <- rep(NA_character_, n)
  basis   <- rep(NA_character_, n)
  present <- !is.na(x)

  # 1. exact strings (case-insensitive)
  for (i in seq_along(exact_map)) {
    rx  <- paste0("^", .rx_escape(names(exact_map)[i]), "$")
    hit <- present & is.na(value) &
      grepl(rx, x, ignore.case = TRUE, perl = TRUE)
    value[hit] <- unname(exact_map[i])
    basis[hit] <- "table"
  }

  # 2. wild-type, optionally prefixed by a gene symbol (e.g. "PKD1 WT")
  wt_rx <- paste0(
    "^(?:(?:", paste(tolower(genes), collapse = "|"), ")[ _-]?)?",
    "(?:wt|wild[- ]?type)$"
  )
  hit <- present & is.na(value) &
    grepl(wt_rx, x, ignore.case = TRUE, perl = TRUE)
  value[hit] <- "wild-type"
  basis[hit] <- "table"

  # 3. standalone gene symbols; several genes are joined with ";"
  open <- present & is.na(value)
  if (any(open)) {
    gene_hits <- lapply(genes, function(g) {
      open & grepl(
        paste0("(?<![a-z0-9])", tolower(g), "(?![a-z0-9])"),
        x, ignore.case = TRUE, perl = TRUE
      )
    })
    for (r in which(open)) {
      found <- genes[vapply(gene_hits, function(h) h[r], logical(1))]
      if (length(found) > 0L) {
        value[r] <- paste(found, collapse = ";")
        basis[r] <- "gene"
      }
    }
  }

  # 4. nothing matched: no listed gene; no genotype at all: not provided
  none <- present & is.na(value)
  value[none]     <- NOT_APPLICABLE
  basis[none]     <- "none"
  value[!present] <- NOT_PROVIDED
  basis[!present] <- "missing"

  list(value = value, basis = basis)
}

#' Is a treatment string really a culture description?
#' Culture or differentiation wording plus a duration, with no dose and no
#' known compound or vehicle word.
.is_culture_description <- function(x, compounds, vehicles) {
  known_rx <- paste0(
    "(?<![a-z0-9])(?:",
    paste(tolower(c(compounds, vehicles)), collapse = "|"),
    ")(?![a-z0-9])"
  )
  .grepl_i(culture_words_rx, x) &
    .grepl_i(duration_rx, x) &
    !.grepl_i(any_dose_rx, x) &
    !.grepl_i(known_rx, x)
}

#' Assign treatment_group from raw treatment strings.
#'
#' Order: no value, exact table, vehicle / untreated words, zero dose,
#' listed compound, non-zero dose. Anything else is UNMAPPED.
.assign_treatment_group <- function(x, exact_map, vehicles, compounds) {
  n       <- length(x)
  t       <- gsub("\\s+", " ", trimws(x))
  out     <- rep(NA_character_, n)
  present <- !is.na(t)

  out[!present]              <- NOT_APPLICABLE
  out[present & t == "NA"]   <- NOT_APPLICABLE

  # exact strings (case-insensitive)
  idx <- match(tolower(t), tolower(names(exact_map)))
  hit <- is.na(out) & !is.na(idx)
  out[hit] <- unname(exact_map[idx[hit]])

  # vehicle / untreated words (whole string)
  vehicle_rx <- paste0(
    "^(?:", paste(vehicles, collapse = "|"), ")(?: control)?$"
  )
  hit <- is.na(out) & .grepl_i(vehicle_rx, t)
  out[hit] <- "vehicle_control"
  hit <- is.na(out) & .grepl_i(untreated_rx, t)
  out[hit] <- "untreated"

  # zero dose = carrier only
  hit <- is.na(out) & .grepl_i(zero_dose_rx, t)
  out[hit] <- "vehicle_control"

  # listed compound
  compound_rx <- paste0(
    "(?<![a-z0-9])(?:", paste(tolower(compounds), collapse = "|"),
    ")(?![a-z0-9])"
  )
  hit <- is.na(out) & .grepl_i(compound_rx, t)
  out[hit] <- "experimental"

  # non-zero dose
  hit <- is.na(out) & .grepl_i(any_dose_rx, t)
  out[hit] <- "experimental"

  out[is.na(out)] <- UNMAPPED
  out
}

#' Derive sample_type with ordered rules; the first match wins.
#'
#' 1. exact source_name table (case-insensitive)
#' 2. organoid / tubuloid / spheroid in any descriptive field
#' 3. a strain or cell-line field that just says "Tissue"
#' 4. iPSC wording (iPS, iPSC, pluripotent, differentiated)
#' 5. a cell line is named, or the text says cell line / immortalized
#' 6. "primary" wording (primary cells / cultures)
#' 7. "kidney" in source_name (in_vivo_tissue)
#' Otherwise UNMAPPED, or Not provided when no descriptive field has a value.
#'
#' @return Character vector of sample_type values.
.derive_sample_type <- function(source_name, cell_line, cell_type,
                                strain_raw, tissue, type_map) {
  n      <- length(source_name)
  result <- rep(NA_character_, n)

  idx  <- match(tolower(source_name), tolower(names(type_map)))
  fill <- is.na(result) & !is.na(idx)
  result[fill] <- unname(type_map[idx[fill]])

  mask <- .any_match(rx_organoid, source_name, cell_type, strain_raw, tissue)
  result[is.na(result) & mask] <- "organoid"

  mask <- .any_match(rx_tissue, strain_raw, cell_line, cell_type)
  result[is.na(result) & mask] <- "in_vivo_tissue"

  mask <- .any_match(rx_ipsc, source_name, cell_type, strain_raw)
  result[is.na(result) & mask] <- "ipsc_derived"

  mask <- !is.na(cell_line) |
    .any_match(rx_cell_line, source_name, cell_type)
  result[is.na(result) & mask] <- "cell_line"

  mask <- .any_match(rx_primary, source_name, cell_type, tissue)
  result[is.na(result) & mask] <- "primary_cells"

  mask <- .any_match("kidney", source_name)
  result[is.na(result) & mask] <- "in_vivo_tissue"

  nothing <- is.na(source_name) & is.na(cell_line) & is.na(cell_type) &
    is.na(strain_raw)
  result[is.na(result) & nothing]  <- NOT_PROVIDED
  result[is.na(result) & !nothing] <- UNMAPPED
  result
}

#' Derive disease_state (cystic / non-cystic).
#'
#' Dedicated fields (phenotype, diagnosis, control.or.cystic) are read
#' first and must match the vocabulary exactly, otherwise UNMAPPED. Rows with
#' no dedicated value are scanned for state words in tissue, source_name and
#' cell.type (negations first). No signal = Not provided.
#'
#' @return List with $state, $source (where the value came from) and
#'   $raw (the dedicated raw value, NA when none).
.derive_disease_state <- function(raw) {
  n   <- nrow(raw)
  ded <- .coalesce_with_source(
    raw, c("phenotype", "diagnosis", "control.or.cystic")
  )
  has_ded <- !is.na(ded$value)
  is_ctrl <- !is.na(ded$source) & ded$source == "control.or.cystic"

  state  <- rep(NA_character_, n)
  source <- rep(NA_character_, n)

  # dedicated fields: whole-value vocabulary
  non  <- has_ded & (.grepl_i(state_non_cystic_rx, ded$value) |
                       (is_ctrl & .grepl_i(state_control_rx, ded$value)))
  cyst <- has_ded & !non & .grepl_i(state_cystic_rx, ded$value)
  state[non]  <- "non-cystic"
  state[cyst] <- "cystic"
  bad <- has_ded & is.na(state)
  state[bad] <- UNMAPPED
  source[has_ded] <- ded$source[has_ded]

  # free text: tissue, source_name, cell.type (first field with a signal)
  for (col in c("tissue", "source_name", "cell.type")) {
    f    <- .coalesce_columns(raw, col)
    open <- !has_ded & is.na(state)
    non  <- open & .grepl_i(free_non_cystic_rx, f)
    state[non] <- "non-cystic"
    source[non] <- col
    open <- !has_ded & is.na(state)
    cyst <- open & .grepl_i(free_cystic_rx, f)
    state[cyst] <- "cystic"
    source[cyst] <- col
  }

  state[is.na(state)] <- NOT_PROVIDED
  list(state = state, source = source, raw = ded$value)
}

#' Collapse a vector of ids for the report, capped at max_n entries.
.collapse_ids <- function(x, max_n = 25L) {
  if (length(x) > max_n) {
    paste0(
      paste(x[seq_len(max_n)], collapse = ";"),
      ";...(+", length(x) - max_n, " more)"
    )
  } else {
    paste(x, collapse = ";")
  }
}

#' Build report rows for the flagged rows of one column.
#'
#' @param status  "UNMAPPED" (sets exit code 2) or "INFO".
#' @param column  Output column the value ends up in.
#' @param source  Raw column(s) the value came from.
#' @param raw     Raw value per row (same length as output).
#' @param output  Output value per row.
#' @param idx     Integer row positions that are flagged.
#' @param runs    Run accession per row.
#' @return data.frame, or NULL when idx is empty.
.flag_rows <- function(bioproject_id, status, column, source,
                       raw, output, idx, runs) {
  if (length(idx) == 0L) {
    return(NULL)
  }
  key    <- ifelse(is.na(raw[idx]), "<missing>", raw[idx])
  groups <- split(idx, key)
  parts  <- lapply(names(groups), function(k) {
    ii <- groups[[k]]
    data.frame(
      bioproject    = bioproject_id,
      status        = status,
      column        = column,
      source_column = source,
      raw_value     = k,
      output_value  = output[ii[1L]],
      n_rows        = length(ii),
      rows          = .collapse_ids(ii),
      runs          = .collapse_ids(runs[ii]),
      stringsAsFactors = FALSE
    )
  })
  do.call(rbind, parts)
}

#' Print a small frequency table to the log.
.log_review <- function(title, labels) {
  tb <- sort(table(labels), decreasing = TRUE)
  df <- data.frame(
    value = names(tb), n = as.integer(tb), stringsAsFactors = FALSE
  )
  message("\n  --- Review: ", title, " ---")
  message(paste0("  ", capture.output(print(df, row.names = FALSE)),
                 collapse = "\n"))
}

# ---------------------------------------------------------------------------
# Main transformation function
# ---------------------------------------------------------------------------

#' Transform a single raw metadata TSV into harmonized output.
#'
#' @param bioproject_id Character. BioProject accession.
#' @param input_path    Character. Path to the raw metadata TSV.
#' @param output_dir    Character. Directory to write the output TSV.
#' @return Invisibly returns a list: $data (the output data.frame),
#'   $report (data.frame of flagged values) and $n_unmapped (number of
#'   distinct UNMAPPED values).
transform_metadata <- function(bioproject_id, input_path, output_dir) {

  # -- Read input ------------------------------------------------------------
  # quote = "" so a stray double quote in a field cannot swallow rows.
  message("Reading: ", input_path)
  raw <- read.delim(
    input_path,
    sep        = "\t",
    header     = TRUE,
    colClasses = "character",
    na.strings = c("", "NA"),
    quote      = ""
  )
  message("  Rows: ", nrow(raw), " | Columns: ", ncol(raw))

  # -- Normalize source column names to lowercase for robust matching ---------
  # The fetch script (01_geo_download.R) outputs all lowercase column names.
  # Normalizing here ensures matching works regardless of casing variation
  # across future fetch script versions.
  colnames(raw) <- tolower(colnames(raw))

  # -- Trim values and convert NCBI placeholder words --------------------------
  raw[] <- lapply(raw, .clean_values)

  # -- Filter: keep RNA-Seq only ---------------------------------------------
  # Some BioProjects mix library strategies (e.g. miRNA-seq with RNA-seq).
  # Only mRNA-seq runs (LibraryStrategy == "RNA-Seq") are retained.
  if ("librarystrategy" %in% colnames(raw)) {
    n_before <- nrow(raw)
    raw <- raw[raw[["librarystrategy"]] == "RNA-Seq" |
                 is.na(raw[["librarystrategy"]]), ]
    n_dropped <- n_before - nrow(raw)
    if (n_dropped > 0L) {
      warning(
        bioproject_id, ": dropped ", n_dropped,
        " non-RNA-Seq row(s) (e.g. miRNA-Seq). Runs retained: ", nrow(raw)
      )
    }
  }

  # -- Pass-through columns (taken as-is, already lowercase) -----------------
  out <- data.frame(
    run            = .coalesce_columns(raw, c("run")),
    bioproject     = .coalesce_columns(raw, c("bioproject")),
    biosample      = .coalesce_columns(raw, c("biosample")),
    sample_name     = .coalesce_columns(raw, c("samplename")),
    experiment     = .coalesce_columns(raw, c("experiment")),
    sra_study       = .coalesce_columns(raw, c("srastudy")),
    submission     = .coalesce_columns(raw, c("submission")),
    release_date    = .coalesce_columns(raw, c("releasedate")),
    load_date       = .coalesce_columns(raw, c("loaddate")),
    bases          = .coalesce_columns(raw, c("bases")),
    spots          = .coalesce_columns(raw, c("spots")),
    avg_length      = .coalesce_columns(raw, c("avglength")),
    size_mb        = .coalesce_columns(raw, c("size_mb")),
    library_layout  = .coalesce_columns(raw, c("librarylayout")),
    platform       = .coalesce_columns(raw, c("platform")),
    model          = .coalesce_columns(raw, c("model")),
    fastq_ftp      = .coalesce_columns(raw, c("fastq_ftp")),
    fastq_md5      = .coalesce_columns(raw, c("fastq_md5")),
    run_hash        = .coalesce_columns(raw, c("runhash")),
    read_hash       = .coalesce_columns(raw, c("readhash")),
    tax_id          = .coalesce_columns(raw, c("taxid")),
    scientific_name = .coalesce_columns(raw, c("scientificname")),
    source_name    = .coalesce_columns(raw, c("source_name")),
    stringsAsFactors = FALSE
  )

  # Replace any remaining NA in pass-through columns with Not provided
  for (col in colnames(out)) {
    out[[col]][is.na(out[[col]])] <- NOT_PROVIDED
  }

  runs         <- out[["run"]]
  report_parts <- list()
  .add_report  <- function(part) {
    if (!is.null(part)) {
      report_parts[[length(report_parts) + 1L]] <<- part
    }
  }

  # -- Raw descriptive fields used by several derivations --------------------
  raw_source_name <- .coalesce_columns(raw, c("source_name"))
  raw_cell_type   <- .coalesce_columns(raw, c("cell.type"))
  raw_tissue_orig <- .coalesce_columns(raw, c("tissue"))

  # -- strain_raw and strain -------------------------------------------------
  # Mouse strain fields come first; a human cell line fills the same slot.
  raw_strain <- .coalesce_columns(
    raw,
    c("strain", "strain.background", "background.strain",
      "cell.line", "cell.line.background")
  )
  is_material <- !is.na(raw_strain) &
    grepl(material_word_rx, raw_strain, ignore.case = TRUE, perl = TRUE)
  out[["strain_raw"]] <- ifelse(is.na(raw_strain), NOT_PROVIDED, raw_strain)

  # Apply canonical spelling normalization; unknown strains copy as-is
  strain_norm <- raw_strain
  for (variant in names(strain_norm_map)) {
    strain_norm[!is.na(strain_norm) & strain_norm == variant] <-
      strain_norm_map[[variant]]
  }
  strain_norm[is_material] <- NA_character_
  out[["strain"]] <- ifelse(is.na(strain_norm), NOT_PROVIDED, strain_norm)

  # Cell line alone (material words such as "Organoid" are not cell lines)
  raw_cell_line <- .coalesce_columns(raw, c("cell.line", "cell.line.background"))
  raw_cell_line[!is.na(raw_cell_line) &
                  grepl(material_word_rx, raw_cell_line,
                        ignore.case = TRUE, perl = TRUE)] <- NA_character_

  # -- sample_type -----------------------------------------------------------
  st <- .derive_sample_type(
    source_name = raw_source_name,
    cell_line   = raw_cell_line,
    cell_type   = raw_cell_type,
    strain_raw  = raw_strain,
    tissue      = raw_tissue_orig,
    type_map    = sample_type_map
  )
  out[["sample_type"]] <- st

  .dash <- function(v) ifelse(is.na(v), "-", v)
  st_desc <- paste0(
    "source_name=", .dash(raw_source_name),
    "; cell_line=", .dash(raw_cell_line),
    "; cell.type=", .dash(raw_cell_type),
    "; strain=", .dash(raw_strain),
    "; tissue=", .dash(raw_tissue_orig)
  )
  .add_report(.flag_rows(
    bioproject_id, "UNMAPPED", "sample_type",
    "source_name, cell.line, cell.type, strain, tissue",
    st_desc, st, which(st == UNMAPPED), runs
  ))

  # -- genotype and underlying_variant ---------------------------------------
  # Priority: genotype > genotype.variation > control.or.cystic
  # control.or.cystic encodes disease status not allele identity so it maps
  # to NA in underlying_variant (see lookup table) but is still preserved here.
  raw_genotype <- .coalesce_columns(
    raw,
    c("genotype", "genotype.variation", "control.or.cystic")
  )
  out[["genotype"]] <- ifelse(is.na(raw_genotype), NOT_PROVIDED, raw_genotype)

  uv <- .assign_underlying_variant(
    raw_genotype, underlying_variant_exact, causal_genes
  )
  out[["underlying_variant"]] <- uv$value
  .add_report(.flag_rows(
    bioproject_id, "INFO", "underlying_variant",
    "genotype / genotype.variation / control.or.cystic",
    raw_genotype, uv$value, which(uv$basis == "none"), runs
  ))

  # -- disease_state ---------------------------------------------------------
  ds <- .derive_disease_state(raw)
  out[["disease_state"]] <- ds$state
  .add_report(.flag_rows(
    bioproject_id, "UNMAPPED", "disease_state",
    "phenotype / diagnosis / control.or.cystic",
    ds$raw, ds$state, which(ds$state == UNMAPPED), runs
  ))

  # -- treatment and culture descriptions ------------------------------------
  # A culture description is not a treatment: treatment becomes NA (not
  # applicable) and its duration is used as the age below.
  raw_treatment <- .coalesce_columns(raw, c("treatment"))
  is_culture <- .is_culture_description(
    raw_treatment, experimental_compounds, vehicle_words
  )
  culture_duration <- .capture(
    raw_treatment, paste0("(", duration_rx, ")"), 1L
  )
  treatment_original <- raw_treatment
  raw_treatment[is_culture] <- NA_character_
  if (any(is_culture)) {
    message(
      "  Treated ", sum(is_culture),
      " treatment value(s) as culture descriptions (treatment = NA)"
    )
    .add_report(.flag_rows(
      bioproject_id, "INFO", "treatment", "treatment",
      treatment_original, rep(NOT_APPLICABLE, length(runs)),
      which(is_culture), runs
    ))
  }

  # -- age_raw, age_range_lower, and age_range_upper -------------------------
  # All ages are stored as ranges with lower and upper bounds.
  # Single ages (e.g. postnatal day 21) have lower == upper == 21.
  # Age ranges (e.g. postnatal day 7-10) have lower = 7, upper = 10.
  # This allows PostgreSQL to store as a native range type downstream.
  raw_age <- .coalesce_columns(raw, c("age", "time"))
  fill_age <- is.na(raw_age) & is_culture & !is.na(culture_duration)
  raw_age[fill_age] <- culture_duration[fill_age]

  parsed    <- .parse_age(raw_age)
  age_lower <- parsed$lower
  age_upper <- parsed$upper

  # Extract age from tissue strings where age was embedded by the submitter
  fixed <- .extract_age_from_tissue(
    raw_tissue_orig, age_lower, age_upper, raw_age
  )
  raw_tissue  <- fixed$tissue
  age_lower   <- fixed$age_lower
  age_upper   <- fixed$age_upper
  raw_age_out <- fixed$age_raw

  unparsed_age <- which(parsed$status == "unparsed" & is.na(age_lower))
  .add_report(.flag_rows(
    bioproject_id, "UNMAPPED", "age_range_lower/age_range_upper",
    "age / time", raw_age,
    rep(NOT_PROVIDED, length(runs)), unparsed_age, runs
  ))

  out[["age_raw"]] <- ifelse(is.na(raw_age_out), NOT_PROVIDED, raw_age_out)
  out[["age_range_lower"]] <- ifelse(
    is.na(age_lower), NOT_PROVIDED, as.character(age_lower)
  )
  out[["age_range_upper"]] <- ifelse(
    is.na(age_upper), NOT_PROVIDED, as.character(age_upper)
  )

  # -- tissue ----------------------------------------------------------------
  # Anything containing "kidney" becomes kidney; other values stay as written.
  is_kidney <- !is.na(raw_tissue) &
    grepl("kidney", raw_tissue, ignore.case = TRUE)
  tissue_out <- raw_tissue
  tissue_out[is_kidney] <- "kidney"
  out[["tissue"]] <- ifelse(is.na(tissue_out), NOT_PROVIDED, tissue_out)
  .add_report(.flag_rows(
    bioproject_id, "INFO", "tissue", "tissue",
    raw_tissue, out[["tissue"]],
    which(!is.na(raw_tissue) & !is_kidney), runs
  ))

  # -- sex -------------------------------------------------------------------
  # sex.y from BioSample has the real values; sex.x from SRA runinfo is
  # expected to be blank. Warn if sex.x has unexpected values so future
  # datasets with populated sex.x are not silently dropped.
  if ("sex.x" %in% colnames(raw)) {
    sex_x_vals <- raw[["sex.x"]][!is.na(raw[["sex.x"]]) &
                                   trimws(raw[["sex.x"]]) != ""]
    if (length(sex_x_vals) > 0L) {
      warning(
        bioproject_id, ": sex.x has ", length(sex_x_vals),
        " non-blank value(s) — review whether sex.y still takes priority."
      )
    }
  }
  raw_sex <- .coalesce_columns(raw, c("sex.y", "sex"))
  out[["sex"]] <- ifelse(is.na(raw_sex), NOT_PROVIDED, tolower(trimws(raw_sex)))

  # -- treatment and treatment_group -----------------------------------------
  # NA here means no treatment was part of the study design (not applicable)
  out[["treatment"]] <- ifelse(is.na(raw_treatment), NOT_APPLICABLE, raw_treatment)
  tg <- .assign_treatment_group(
    raw_treatment, treatment_group_map, vehicle_words, experimental_compounds
  )
  out[["treatment_group"]] <- tg
  .add_report(.flag_rows(
    bioproject_id, "UNMAPPED", "treatment_group", "treatment",
    raw_treatment, tg, which(tg == UNMAPPED), runs
  ))

  # -- Review tables for the log ---------------------------------------------
  # These make silent mislabelling visible: read them when a new project
  # is added.
  .log_review("strain_raw -> strain",
              paste(out[["strain_raw"]], "->", out[["strain"]]))
  .log_review("genotype -> underlying_variant",
              paste(out[["genotype"]], "->", out[["underlying_variant"]]))
  .log_review("descriptive fields -> sample_type",
              paste(st_desc, "->", st))
  .log_review("disease_state", out[["disease_state"]])

  # -- Final column order (must match column reference exactly) --------------
  final_cols <- c(
    "run", "bioproject", "biosample", "sample_name", "experiment",
    "sra_study", "submission", "release_date", "load_date",
    "bases", "spots", "avg_length", "size_mb",
    "library_layout", "platform", "model",
    "fastq_ftp", "fastq_md5", "run_hash", "read_hash",
    "tax_id", "scientific_name", "source_name",
    "sample_type",
    "underlying_variant", "genotype",
    "strain", "strain_raw",
    "tissue", "age_raw", "age_range_lower", "age_range_upper",
    "sex", "treatment", "treatment_group",
    "disease_state"
  )

  # Verify all expected columns were produced before writing
  missing_cols <- setdiff(final_cols, colnames(out))
  if (length(missing_cols) > 0L) {
    stop(
      bioproject_id, ": output is missing expected columns: ",
      paste(missing_cols, collapse = ", ")
    )
  }

  out <- out[, final_cols, drop = FALSE]

  # A true NA would be written as text and mislabelled; every missing value
  # must already be Not provided or the string NA.
  na_cols <- colnames(out)[vapply(out, anyNA, logical(1))]
  if (length(na_cols) > 0L) {
    stop(
      bioproject_id, ": true NA values reached the writer in column(s): ",
      paste(na_cols, collapse = ", ")
    )
  }

  # -- Write output ----------------------------------------------------------
  if (!dir.exists(output_dir)) {
    dir.create(output_dir, recursive = TRUE)
  }

  output_path <- file.path(
    output_dir, paste0(bioproject_id, "_transformed.tsv")
  )

  write.table(
    out,
    file      = output_path,
    sep       = "\t",
    quote     = FALSE,
    row.names = FALSE,
    na        = NOT_PROVIDED
  )

  message("Written: ", output_path)
  message("  Rows: ", nrow(out), " | Columns: ", ncol(out))

  # -- Report ----------------------------------------------------------------
  report_path <- file.path(
    output_dir, paste0(bioproject_id, "_transform_report.txt")
  )
  report <- if (length(report_parts) > 0L) {
    do.call(rbind, report_parts)
  } else {
    NULL
  }

  n_unmapped <- 0L
  if (!is.null(report)) {
    write.table(
      report, file = report_path, sep = "\t", quote = FALSE,
      row.names = FALSE, na = NOT_PROVIDED
    )
    n_unmapped <- sum(report$status == "UNMAPPED")
    n_info     <- sum(report$status == "INFO")
    message("Report written: ", report_path)
    message("  UNMAPPED values: ", n_unmapped, " | INFO entries: ", n_info)
    flagged <- report[report$status == "UNMAPPED", , drop = FALSE]
    for (r in seq_len(nrow(flagged))) {
      message(
        "  [UNMAPPED] ", flagged$bioproject[r], " | column: ",
        flagged$column[r], " | raw: '", flagged$raw_value[r],
        "' | rows: ", flagged$n_rows[r],
        " (runs: ", flagged$runs[r], ")"
      )
    }
  } else if (file.exists(report_path)) {
    file.remove(report_path)
  }

  invisible(list(data = out, report = report, n_unmapped = n_unmapped))
}

# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------
result <- transform_metadata(bioproject_id, input_path, output_dir)

# ---------------------------------------------------------------------------
# Session info (required by project coding guidelines)
# Written to a file so reviewers can access it without log file access.
# ---------------------------------------------------------------------------
session_info_path <- file.path(output_dir, "..", "session_info.txt")
session_info_path <- normalizePath(session_info_path, mustWork = FALSE)
message("\n--- Session Info ---")
session_info <- sessionInfo()
print(session_info)
writeLines(capture.output(print(session_info)), session_info_path)
message("Session info written to: ", session_info_path)

# ---------------------------------------------------------------------------
# Exit status: 2 when output was written but some values are UNMAPPED
# ---------------------------------------------------------------------------
if (result$n_unmapped > 0L) {
  message(
    "\n", result$n_unmapped, " UNMAPPED value(s) in ", bioproject_id,
    ". Output was written. See the transform report and extend the lookup ",
    "tables. Exiting with status ", EXIT_FLAGGED, "."
  )
  quit(save = "no", status = EXIT_FLAGGED)
}
