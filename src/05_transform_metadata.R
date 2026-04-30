### Sample metadata transformation
# Author: Kieran Casper, with AI assistance from Claude (Anthropic)
# Date: April 23, 2026
## Goal: Transform raw BioProject sample metadata TSVs into harmonized,
##       analysis-ready TSVs with normalized column names, controlled
##       vocabulary fields, and derived biological annotations.
## Reproducibility:
# * GitHub: lasseignelab/rrc-datahub
#
## Harmonization rules applied:
# * Column names lowercased and standardized
# * Genotype consolidated from genotype / genotype.variation /
#   control.or.cystic into genotype; causal gene extracted into
#   underlying_variant via explicit lookup table
# * Strain consolidated from strain / strain.background /
#   background.strain into strain_raw; spelling normalized in
#   strain
# * Tissue normalized to controlled vocabulary; age embedded in tissue
#   string for PRJNA637874 is split out
# * Age converted from free-text postnatal day strings to integer days.
#   All ages stored as ranges: age_range_lower and age_range_upper.
#   Single ages have lower == upper. Ranges (e.g. 7-10) split into bounds.
#   Original string preserved in age_raw.
# * Sex consolidated from sex.y / sex; sex.x (always blank) dropped
# * sample_type derived from source_name via lookup table
# * treatment_group derived from treatment via lookup table
# * NA used for not applicable; NP for not provided
# * UNMAPPED flag written for any value absent from lookup tables so
#   new projects with novel strings are caught immediately
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
# Lookup tables
# All controlled-vocabulary mappings are defined here so they are visible,
# auditable, and easy to extend when new projects are added.
# ---------------------------------------------------------------------------

# Map every observed genotype_raw string to a causal-gene controlled value.
# wild-type : sample has no PKD-related mutation
# NA        : genotype concept not applicable (control.or.cystic projects)
# UNMAPPED  : written at runtime for any string absent from this table
underlying_variant_map <- c(
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

# Map source_name values to controlled sample_type vocabulary.
# Anything containing "kidney" (case-insensitive) is handled programmatically
# below; only outliers require explicit entries here.
sample_type_map <- c(
  "primary cell tubuloids"                      = "organoid",
  "murine inner medullary collecting duct cells" = "cell_line",
  "Cultured mIMCD-3 Cells (ATCC CRL-2123)"     = "cell_line"
)

# Map raw treatment strings to grouped controlled vocabulary.
# vehicle_control covers PBS and DMSO; experimental covers active treatments.
treatment_group_map <- c(
  "RGLS4326"     = "experimental",
  "DOX"          = "experimental",
  "PBS"          = "vehicle_control",
  "DMSO"         = "vehicle_control",
  "No treatment" = "untreated"
)

# ---------------------------------------------------------------------------
# Helper functions
# ---------------------------------------------------------------------------

#' Apply a named lookup vector, returning UNMAPPED for unknown inputs.
#'
#' @param x         Character vector of values to look up.
#' @param map       Named character vector mapping input to output.
#' @param na_value  Value to return for NA inputs instead of looking them up.
#' @return Character vector of mapped values.
.apply_lookup <- function(x, map, na_value = NA_character_) {
  result <- map[x]
  result[is.na(x)] <- na_value
  # Values absent from the map but non-NA get UNMAPPED flag
  result[is.na(result) & !is.na(x)] <- "UNMAPPED"
  unname(result)
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

#' Convert a month count to days using a 30-day month approximation.
#'
#' Standard biomedical approximation; precision beyond this is not warranted
#' given the variability in how age is reported across studies.
#'
#' @param months Integer or numeric. Number of months.
#' @return Integer. Number of days.
.months_to_days <- function(months) {
  as.integer(round(months * 30))
}

#' Parse a postnatal age string to integer days.
#'
#' Handles all observed spelling variants of "postnatal day N" and any
#' "N months old" string by extracting N and converting via .months_to_days().
#' Returns NA_integer_ for strings that cannot be parsed.
#'
#' @param x Character vector of raw age strings.
#' @return Integer vector of postnatal age in days.
.parse_age_days <- function(x) {
  result <- rep(NA_integer_, length(x))

  # Match "post[-]?natal day N" (case-insensitive, hyphen optional, spaces
  # between words optional) and extract the numeric part
  pnd_pattern <- "(?i)post[- ]?natal\\s*day\\s*(\\d+)"
  pnd_match   <- regmatches(x, regexpr(pnd_pattern, x, perl = TRUE))
  pnd_nums    <- suppressWarnings(
    as.integer(gsub("(?i).*?(\\d+)$", "\\1", pnd_match, perl = TRUE))
  )
  result[nchar(pnd_match) > 0] <- pnd_nums[nchar(pnd_match) > 0]

  # Match "N months old" (case-insensitive) and convert to days
  # using a 30-day month approximation
  mo_pattern <- "(?i)^(\\d+)\\s+months?\\s+old$"
  mo_match   <- regmatches(x, regexpr(mo_pattern, x, perl = TRUE))
  mo_nums    <- suppressWarnings(
    as.integer(gsub("(?i)^(\\d+).*", "\\1", mo_match, perl = TRUE))
  )
  has_mo <- nchar(mo_match) > 0
  result[has_mo] <- .months_to_days(mo_nums[has_mo])

  result
}

#' Derive sample_type from source_name.
#'
#' Uses dplyr::case_when for vectorized classification. Checks the explicit
#' lookup table first, then classifies anything containing "kidney"
#' (case-insensitive) as in_vivo_tissue. The map is passed explicitly to
#' avoid hidden dependency on the global environment.
#'
#' @param source_name    Character vector of source_name values.
#' @param type_map       Named character vector mapping source_name to
#'   sample_type controlled vocabulary.
#' @return Character vector of sample_type controlled vocabulary values.
.derive_sample_type <- function(source_name, type_map) {
  dplyr::case_when(
    is.na(source_name)                         ~ "NP",
    source_name %in% names(type_map)           ~ type_map[source_name],
    grepl("kidney", source_name,
          ignore.case = TRUE)                  ~ "in_vivo_tissue",
    .default                                   = "UNMAPPED"
  )
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

# ---------------------------------------------------------------------------
# Main transformation function
# ---------------------------------------------------------------------------

#' Transform a single raw metadata TSV into harmonized output.
#'
#' @param bioproject_id Character. BioProject accession.
#' @param input_path    Character. Path to the raw metadata TSV.
#' @param output_dir    Character. Directory to write the output TSV.
#' @return Invisibly returns the transformed data.frame.
transform_metadata <- function(bioproject_id, input_path, output_dir) {

  # -- Read input ------------------------------------------------------------
  message("Reading: ", input_path)
  raw <- read.delim(
    input_path,
    sep       = "\t",
    header    = TRUE,
    colClasses = "character",
    na.strings = c("", "NA")
  )
  message("  Rows: ", nrow(raw), " | Columns: ", ncol(raw))

  # -- Filter: PRJNA342113 contains mixed miRNA-seq and RNA-seq runs ---------
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

  # -- Normalize source column names to lowercase for robust matching ---------
  # The fetch script (01_geo_download.R) outputs all lowercase column names.
  # Normalizing here ensures matching works regardless of casing variation
  # across future fetch script versions.
  colnames(raw) <- tolower(colnames(raw))

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

  # Replace any remaining NA in pass-through columns with NP
  # (not provided by the depositor)
  for (col in colnames(out)) {
    out[[col]][is.na(out[[col]])] <- "NP"
  }

  # -- sample_type -----------------------------------------------------------
  out[["sample_type"]] <- .derive_sample_type(
    .coalesce_columns(raw, c("source_name")),
    sample_type_map
  )

  # -- genotype ----------------------------------------------------------
  # Priority: genotype > genotype.variation > control.or.cystic
  # control.or.cystic encodes disease status not allele identity so it maps
  # to NA in genotype_gene (see lookup table) but is still preserved here.
  raw_genotype <- .coalesce_columns(
    raw,
    c("genotype", "genotype.variation", "control.or.cystic")
  )
  out[["genotype"]] <- ifelse(is.na(raw_genotype), "NP", raw_genotype)

  # Track mapping failures — script will error at end if any UNMAPPED remain
  mapping_failures <- character(0)

  # -- underlying_variant --------------------------------------------------
  # NA is correct for wild-type (no mutated PKD gene, not applicable)
  # NA is also correct for PRJNA805541/805542 (control.or.cystic maps to NA)
  out[["underlying_variant"]] <- .apply_lookup(
    raw_genotype,
    underlying_variant_map,
    na_value = "NP"
  )
  n_unmapped_geno <- sum(
    out[["underlying_variant"]] == "UNMAPPED", na.rm = TRUE
  )
  if (n_unmapped_geno > 0L) {
    mapping_failures <- c(
      mapping_failures,
      paste0(
        bioproject_id, ": ", n_unmapped_geno,
        " underlying_variant value(s) could not be mapped. ",
        "Add them to underlying_variant_map in 05_transform_metadata.R."
      )
    )
  }

  # -- strain_raw and strain_normalized --------------------------------------
  raw_strain <- .coalesce_columns(
    raw,
    c("strain", "strain.background", "background.strain")
  )
  out[["strain_raw"]] <- ifelse(is.na(raw_strain), "NP", raw_strain)

  # Apply canonical spelling normalization; unknown strains copy as-is
  strain_norm <- raw_strain
  for (variant in names(strain_norm_map)) {
    strain_norm[!is.na(strain_norm) & strain_norm == variant] <-
      strain_norm_map[[variant]]
  }
  out[["strain"]] <- ifelse(is.na(strain_norm), "NP", strain_norm)

  # -- tissue ----------------------------------------------------------------
  raw_tissue <- .coalesce_columns(raw, c("tissue"))
  # Normalize capitalization variants before PRJNA637874 fix
  raw_tissue[!is.na(raw_tissue) & raw_tissue == "Kidney"] <- "kidney"

  # -- age_raw, age_range_lower, and age_range_upper -------------------------
  # All ages are stored as ranges with lower and upper bounds.
  # Single ages (e.g. postnatal day 21) have lower == upper == 21.
  # Age ranges (e.g. postnatal day 7-10) have lower = 7, upper = 10.
  # This allows PostgreSQL to store as a native range type downstream.
  raw_age         <- .coalesce_columns(raw, c("age"))
  age_lower       <- rep(NA_integer_, nrow(raw))
  age_upper       <- rep(NA_integer_, nrow(raw))

  # Parse single postnatal day values — exclude range strings (e.g. "7-10")
  # by requiring no dash after the number
  single_days <- .parse_age_days(raw_age)
  # Mark as single only if raw_age is not a range pattern
  is_range_str  <- !is.na(raw_age) &
    grepl(range_pattern, raw_age, perl = TRUE)
  has_single    <- !is.na(single_days) & !is_range_str
  age_lower[has_single] <- single_days[has_single]
  age_upper[has_single] <- single_days[has_single]

  # Parse postnatal day ranges (e.g. "postnatal day 7-10")
  range_pattern <- "(?i)post[- ]?natal\\s*day\\s*(\\d+)-(\\d+)"
  has_range     <- !is.na(raw_age) &
    grepl(range_pattern, raw_age, perl = TRUE)
  if (any(has_range)) {
    lo <- as.integer(gsub(range_pattern, "\\1",
                          raw_age[has_range], perl = TRUE))
    hi <- as.integer(gsub(range_pattern, "\\2",
                          raw_age[has_range], perl = TRUE))
    age_lower[has_range] <- lo
    age_upper[has_range] <- hi
  }

  # Extract age from tissue strings where age was embedded by the submitter
  fixed <- .extract_age_from_tissue(
    raw_tissue, age_lower, age_upper, raw_age
  )
  raw_tissue  <- fixed$tissue
  age_lower   <- fixed$age_lower
  age_upper   <- fixed$age_upper
  raw_age_out <- fixed$age_raw

  out[["tissue"]]          <- ifelse(is.na(raw_tissue), "NP", raw_tissue)
  out[["age_raw"]]         <- ifelse(is.na(raw_age_out), "NP", raw_age_out)
  out[["age_range_lower"]] <- ifelse(
    is.na(age_lower), "NP", as.character(age_lower)
  )
  out[["age_range_upper"]] <- ifelse(
    is.na(age_upper), "NP", as.character(age_upper)
  )

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
  out[["sex"]] <- ifelse(is.na(raw_sex), "NP", tolower(trimws(raw_sex)))

  # -- treatment -------------------------------------------------------------
  raw_treatment <- .coalesce_columns(raw, c("treatment"))
  # NA here means no treatment was part of the study design (not applicable)
  out[["treatment"]] <- ifelse(is.na(raw_treatment), "NA", raw_treatment)

  # -- treatment_group -------------------------------------------------------
  out[["treatment_group"]] <- .apply_lookup(
    raw_treatment,
    treatment_group_map,
    na_value = "NA"
  )
  n_unmapped_trt <- sum(
    out[["treatment_group"]] == "UNMAPPED", na.rm = TRUE
  )
  if (n_unmapped_trt > 0L) {
    mapping_failures <- c(
      mapping_failures,
      paste0(
        bioproject_id, ": ", n_unmapped_trt,
        " treatment_group value(s) could not be mapped. ",
        "Add them to treatment_group_map in 05_transform_metadata.R."
      )
    )
  }

  # Error if any mapping failures occurred so they are not silently missed
  if (length(mapping_failures) > 0L) {
    stop(
      "Mapping failures detected — fix lookup tables before proceeding:\n",
      paste(mapping_failures, collapse = "\n")
    )
  }

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
    "sex", "treatment", "treatment_group"
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
    na        = "NP"
  )

  message("Written: ", output_path)
  message("  Rows: ", nrow(out), " | Columns: ", ncol(out))

  invisible(out)
}

# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------
transform_metadata(bioproject_id, input_path, output_dir)

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
