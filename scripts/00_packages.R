# Packages used by the R cleaning and descriptive analysis scripts.
required <- c("data.table", "stringr", "jsonlite", "ggplot2", "scales",
              "dplyr", "tidyr", "skimr", "patchwork", "broom", "sandwich")
missing <- required[!vapply(required, requireNamespace, logical(1), quietly = TRUE)]
if (length(missing)) {
  stop("Install the missing packages before running the analysis: ",
       paste(missing, collapse = ", "))
}
invisible(lapply(required, library, character.only = TRUE))
sessionInfo()
