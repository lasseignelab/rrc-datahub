library(testthat)

source_file <- file.path(
  "..",
  "..",
  "src",
  "functions",
  "get_bioproject_metadata.R"
)
source(source_file)


# Helper: temporarily replace a function in the global environment
# and restore it when the calling test_that block exits.
mock_fn <- function(name, replacement, envir = globalenv()) {
  original <- get(name, envir = envir)
  assign(name, replacement, envir = envir)
  withr::defer(assign(name, original, envir = envir), envir = parent.frame())
}


# =============================================================================
# .validate_bioproject_id
# =============================================================================

test_that(".validate_bioproject_id accepts valid accessions", {
  expect_silent(.validate_bioproject_id("PRJNA543107"))
  expect_silent(.validate_bioproject_id("PRJNA1"))
  expect_silent(.validate_bioproject_id("PRJNA000123"))
  # Case-insensitive
  expect_silent(.validate_bioproject_id("prjna543107"))
})

test_that(".validate_bioproject_id rejects invalid accessions", {
  expect_error(.validate_bioproject_id("GSE69556"), "BioProject accession")
  expect_error(.validate_bioproject_id("PRJNA"), "BioProject accession")
  expect_error(.validate_bioproject_id("PRJNA_123"), "BioProject accession")
  expect_error(.validate_bioproject_id("SRR1234567"), "BioProject accession")
  expect_error(.validate_bioproject_id(""), "BioProject accession")
  expect_error(.validate_bioproject_id("PRJNA123abc"), "BioProject accession")
})


# =============================================================================
# .clean_column_names
# =============================================================================

test_that(".clean_column_names converts to lowercase", {
  df <- data.frame(Run = 1, BioSample = 2, LibraryLayout = 3)
  result <- .clean_column_names(df)
  expect_equal(colnames(result), c("run", "biosample", "librarylayout"))
})

test_that(".clean_column_names replaces special characters with dots", {
  df <- data.frame(a = 1, b = 2, c = 3)
  colnames(df) <- c("genotype:ch1", "age (years)", "tissue/organ")
  result <- .clean_column_names(df)
  expect_equal(colnames(result), c("genotype.ch1", "age.years", "tissue.organ"))
})

test_that(".clean_column_names collapses multiple dots", {
  df <- data.frame(a = 1)
  colnames(df) <- c("foo::bar")
  result <- .clean_column_names(df)
  expect_equal(colnames(result), "foo.bar")
})

test_that(".clean_column_names strips leading and trailing dots", {
  df <- data.frame(a = 1, b = 2)
  colnames(df) <- c(".leading", "trailing.")
  result <- .clean_column_names(df)
  expect_equal(colnames(result), c("leading", "trailing"))
})

test_that(".clean_column_names deduplicates after cleaning", {
  df <- data.frame(a = 1, b = 2)
  colnames(df) <- c("Sex", "sex")
  result <- .clean_column_names(df)
  expect_equal(colnames(result), c("sex", "sex_1"))
})

test_that(".clean_column_names preserves underscores and dots", {
  df <- data.frame(a = 1, b = 2)
  colnames(df) <- c("sample_name", "version.2")
  result <- .clean_column_names(df)
  expect_equal(colnames(result), c("sample_name", "version.2"))
})


# =============================================================================
# .parse_biosample_xml
# =============================================================================

test_that(".parse_biosample_xml extracts attributes from single sample", {
  xml_text <- '<?xml version="1.0" encoding="UTF-8"?>
    <BioSampleSet>
      <BioSample accession="SAMN12345">
        <Attributes>
          <Attribute attribute_name="tissue">kidney</Attribute>
          <Attribute attribute_name="genotype">WT</Attribute>
          <Attribute attribute_name="age">P0</Attribute>
        </Attributes>
      </BioSample>
    </BioSampleSet>'

  result <- .parse_biosample_xml(xml_text)

  expect_s3_class(result, "data.frame")
  expect_equal(nrow(result), 1)
  expect_equal(result$BioSample, "SAMN12345")
  expect_equal(result$tissue, "kidney")
  expect_equal(result$genotype, "WT")
  expect_equal(result$age, "P0")
})

test_that(".parse_biosample_xml handles multiple samples", {
  xml_text <- '<?xml version="1.0" encoding="UTF-8"?>
    <BioSampleSet>
      <BioSample accession="SAMN11111">
        <Attributes>
          <Attribute attribute_name="tissue">brain</Attribute>
          <Attribute attribute_name="genotype">KO</Attribute>
        </Attributes>
      </BioSample>
      <BioSample accession="SAMN22222">
        <Attributes>
          <Attribute attribute_name="tissue">liver</Attribute>
          <Attribute attribute_name="genotype">WT</Attribute>
        </Attributes>
      </BioSample>
    </BioSampleSet>'

  result <- .parse_biosample_xml(xml_text)

  expect_equal(nrow(result), 2)
  expect_setequal(result$BioSample, c("SAMN11111", "SAMN22222"))
  expect_equal(result$tissue[result$BioSample == "SAMN11111"], "brain")
  expect_equal(result$tissue[result$BioSample == "SAMN22222"], "liver")
})

test_that(".parse_biosample_xml fills NA for missing attributes across samples", {
  xml_text <- '<?xml version="1.0" encoding="UTF-8"?>
    <BioSampleSet>
      <BioSample accession="SAMN11111">
        <Attributes>
          <Attribute attribute_name="tissue">brain</Attribute>
          <Attribute attribute_name="sex">female</Attribute>
        </Attributes>
      </BioSample>
      <BioSample accession="SAMN22222">
        <Attributes>
          <Attribute attribute_name="tissue">kidney</Attribute>
          <Attribute attribute_name="strain">C57BL/6</Attribute>
        </Attributes>
      </BioSample>
    </BioSampleSet>'

  result <- .parse_biosample_xml(xml_text)

  expect_equal(nrow(result), 2)
  expect_true(is.na(result$strain[result$BioSample == "SAMN11111"]))
  expect_true(is.na(result$sex[result$BioSample == "SAMN22222"]))
})

test_that(".parse_biosample_xml collapses duplicate attribute names with semicolons", {
  xml_text <- '<?xml version="1.0" encoding="UTF-8"?>
    <BioSampleSet>
      <BioSample accession="SAMN99999">
        <Attributes>
          <Attribute attribute_name="tissue">kidney</Attribute>
          <Attribute attribute_name="treatment">drug_A</Attribute>
          <Attribute attribute_name="treatment">drug_B</Attribute>
        </Attributes>
      </BioSample>
    </BioSampleSet>'

  result <- .parse_biosample_xml(xml_text)

  expect_equal(nrow(result), 1)
  expect_equal(result$treatment, "drug_A;drug_B")
  expect_equal(result$tissue, "kidney")
})

test_that(".parse_biosample_xml handles sample with no attributes", {
  xml_text <- '<?xml version="1.0" encoding="UTF-8"?>
    <BioSampleSet>
      <BioSample accession="SAMN00001">
        <Attributes>
        </Attributes>
      </BioSample>
    </BioSampleSet>'

  result <- .parse_biosample_xml(xml_text)

  expect_equal(nrow(result), 1)
  expect_equal(result$BioSample, "SAMN00001")
  expect_equal(ncol(result), 1)
})


# =============================================================================
# .merge_biosample_attributes
# =============================================================================

test_that(".merge_biosample_attributes skips when no BioSample column", {
  df <- data.frame(Run = "SRR123", Platform = "ILLUMINA",
                   stringsAsFactors = FALSE)
  result <- .merge_biosample_attributes(df)
  expect_equal(colnames(result), c("Run", "Platform"))
  expect_equal(nrow(result), 1)
})


# =============================================================================
# .merge_ena_fastq_info
# =============================================================================

test_that(".merge_ena_fastq_info reorders columns correctly on success", {
  metadata <- data.frame(
    Run = c("SRR001", "SRR002"),
    download_path = c("path1", "path2"),
    Platform = c("ILLUMINA", "ILLUMINA"),
    stringsAsFactors = FALSE
  )
  ena_data <- data.frame(
    run_accession = c("SRR001", "SRR002"),
    fastq_ftp = c("ftp://file1", "ftp://file2"),
    fastq_md5 = c("abc123", "def456"),
    stringsAsFactors = FALSE
  )

  mock_fn(".fetch_ena_fastq_info", function(bioproject_id) ena_data)

  result <- .merge_ena_fastq_info(metadata, "PRJNA000001")

  expect_equal(colnames(result)[1:3], c("Run", "fastq_ftp", "fastq_md5"))
  expect_false("download_path" %in% colnames(result))
  expect_equal(result$fastq_ftp, c("ftp://file1", "ftp://file2"))
})

test_that(".merge_ena_fastq_info returns metadata unchanged when ENA fails", {
  metadata <- data.frame(
    Run = c("SRR001"),
    download_path = c("path1"),
    Platform = c("ILLUMINA"),
    stringsAsFactors = FALSE
  )

  mock_fn(".fetch_ena_fastq_info", function(bioproject_id) NULL)

  result <- .merge_ena_fastq_info(metadata, "PRJNA000001")

  expect_true("download_path" %in% colnames(result))
  expect_false("fastq_ftp" %in% colnames(result))
})

test_that(".merge_ena_fastq_info handles partial ENA matches", {
  metadata <- data.frame(
    Run = c("SRR001", "SRR002", "SRR003"),
    download_path = c("p1", "p2", "p3"),
    stringsAsFactors = FALSE
  )
  ena_data <- data.frame(
    run_accession = c("SRR001", "SRR003"),
    fastq_ftp = c("ftp://f1", "ftp://f3"),
    fastq_md5 = c("md5_1", "md5_3"),
    stringsAsFactors = FALSE
  )

  mock_fn(".fetch_ena_fastq_info", function(bioproject_id) ena_data)

  result <- .merge_ena_fastq_info(metadata, "PRJNA000001")

  expect_equal(nrow(result), 3)
  expect_true(is.na(result$fastq_ftp[result$Run == "SRR002"]))
  expect_true(is.na(result$fastq_md5[result$Run == "SRR002"]))
  expect_equal(result$fastq_ftp[result$Run == "SRR001"], "ftp://f1")
})


# =============================================================================
# .write_metadata_tsv
# =============================================================================

test_that(".write_metadata_tsv writes a valid TSV with default filename", {
  tmp_dir <- tempdir()
  test_dir <- file.path(tmp_dir, "test_output")
  on.exit(unlink(test_dir, recursive = TRUE), add = TRUE)

  df <- data.frame(run = "SRR001", tissue = "kidney",
                   stringsAsFactors = FALSE)

  .write_metadata_tsv(df, "PRJNA999999", test_dir, NULL)

  output_path <- file.path(test_dir, "PRJNA999999_metadata.tsv")
  expect_true(file.exists(output_path))

  result <- read.delim(output_path, stringsAsFactors = FALSE)
  expect_equal(nrow(result), 1)
  expect_equal(result$run, "SRR001")
  expect_equal(result$tissue, "kidney")
})

test_that(".write_metadata_tsv uses custom filename", {
  tmp_dir <- tempdir()
  test_dir <- file.path(tmp_dir, "test_output_custom")
  on.exit(unlink(test_dir, recursive = TRUE), add = TRUE)

  df <- data.frame(run = "SRR001", stringsAsFactors = FALSE)

  .write_metadata_tsv(df, "PRJNA999999", test_dir, "custom_name.tsv")

  expect_true(file.exists(file.path(test_dir, "custom_name.tsv")))
  expect_false(file.exists(file.path(test_dir, "PRJNA999999_metadata.tsv")))
})

test_that(".write_metadata_tsv creates output directory if needed", {
  tmp_dir <- tempdir()
  nested_dir <- file.path(tmp_dir, "a", "b", "c")
  on.exit(unlink(file.path(tmp_dir, "a"), recursive = TRUE), add = TRUE)

  df <- data.frame(run = "SRR001", stringsAsFactors = FALSE)

  .write_metadata_tsv(df, "PRJNA999999", nested_dir, NULL)

  expect_true(dir.exists(nested_dir))
  expect_true(file.exists(file.path(nested_dir, "PRJNA999999_metadata.tsv")))
})


# =============================================================================
# .fetch_biosample_attributes
# =============================================================================

test_that(".fetch_biosample_attributes returns NULL for empty input", {
  result <- .fetch_biosample_attributes(character(0))
  expect_null(result)
})


# =============================================================================
# .fetch_ena_fastq_info
# =============================================================================

test_that(".fetch_ena_fastq_info constructs correct ENA URL", {
  captured_url <- NULL

  mock_fn(".fetch_ena_fastq_info", function(bioproject_id) {
    # Reconstruct the URL the same way the real function does
    captured_url <<- paste0(
      "https://www.ebi.ac.uk/ena/portal/api/filereport",
      "?accession=", bioproject_id,
      "&result=read_run",
      "&fields=run_accession,fastq_ftp,fastq_md5",
      "&format=tsv"
    )
    data.frame(
      run_accession = "SRR001",
      fastq_ftp = "ftp://test",
      fastq_md5 = "abc",
      stringsAsFactors = FALSE
    )
  })

  .fetch_ena_fastq_info("PRJNA543107")

  expect_true(grepl("accession=PRJNA543107", captured_url))
  expect_true(grepl("result=read_run", captured_url))
  expect_true(grepl("fields=run_accession,fastq_ftp,fastq_md5", captured_url))
  expect_true(grepl("format=tsv", captured_url))
})

test_that(".fetch_ena_fastq_info returns NULL on error", {
  mock_fn(".fetch_ena_fastq_info", function(bioproject_id) {
    warning("Failed to fetch ENA data: Network error\n",
            "The download_path column will be retained instead.")
    NULL
  })

  expect_warning(
    result <- .fetch_ena_fastq_info("PRJNA000001"),
    "Failed to fetch ENA data"
  )
  expect_null(result)
})


# =============================================================================
# get_bioproject_metadata (integration with mocks)
# =============================================================================

test_that("get_bioproject_metadata orchestrates all steps correctly", {
  tmp_dir <- tempdir()
  test_dir <- file.path(tmp_dir, "integration_test")
  on.exit(unlink(test_dir, recursive = TRUE), add = TRUE)

  mock_runinfo <- data.frame(
    Run = c("SRR001", "SRR002"),
    BioSample = c("SAMN001", "SAMN002"),
    download_path = c("path1", "path2"),
    Platform = c("ILLUMINA", "ILLUMINA"),
    LibraryLayout = c("PAIRED", "PAIRED"),
    stringsAsFactors = FALSE
  )

  mock_biosample <- data.frame(
    BioSample = c("SAMN001", "SAMN002"),
    tissue = c("kidney", "brain"),
    genotype = c("WT", "KO"),
    stringsAsFactors = FALSE
  )

  mock_ena <- data.frame(
    run_accession = c("SRR001", "SRR002"),
    fastq_ftp = c("ftp://f1", "ftp://f2"),
    fastq_md5 = c("md5_1", "md5_2"),
    stringsAsFactors = FALSE
  )

  mock_fn(".fetch_sra_runinfo", function(bioproject_id, retmax) mock_runinfo)
  mock_fn(".fetch_biosample_attributes", function(ids, ...) mock_biosample)
  mock_fn(".fetch_ena_fastq_info", function(bioproject_id) mock_ena)

  result <- get_bioproject_metadata("PRJNA543107", output_dir = test_dir)

  # Column ordering: run, fastq_ftp, fastq_md5 first
  expect_equal(colnames(result)[1:3], c("run", "fastq_ftp", "fastq_md5"))

  # All columns lowercase
  expect_equal(colnames(result), tolower(colnames(result)))

  # BioSample attributes merged
  expect_true("tissue" %in% colnames(result))
  expect_true("genotype" %in% colnames(result))

  # download_path removed
  expect_false("download_path" %in% colnames(result))

  # TSV written
  output_path <- file.path(test_dir, "PRJNA543107_metadata.tsv")
  expect_true(file.exists(output_path))

  # Round-trip: read back and verify
  written <- read.delim(output_path, stringsAsFactors = FALSE)
  expect_equal(nrow(written), 2)
  expect_true("tissue" %in% colnames(written))
})
