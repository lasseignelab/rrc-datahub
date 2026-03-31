args <- R.utils::commandArgs(trailingOnly = TRUE)

source(file.path("src", "functions", "get_bioproject_metadata.R"))

dataset <- args[1]
output_dir <- args[2]

get_bioproject_metadata(dataset, output_dir = output_dir)
