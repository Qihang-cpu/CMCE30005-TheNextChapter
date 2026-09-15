# Run from the repository root: Rscript tests/test_peer_inputs.R
library(digest)
library(jsonlite)

# Load the gate definition without evaluating the ranking script's analysis.
expressions <- parse("scripts/08_peer_ranking.R")
definition <- Filter(function(x) is.call(x) && identical(x[[1]], as.name("<-")) &&
                       identical(x[[2]], as.name("verify_analysis_inputs")), expressions)
stopifnot(length(definition) == 1L)
test_environment <- new.env(parent = globalenv())
eval(definition[[1]], test_environment)
verify_inputs <- test_environment$verify_analysis_inputs

with_fixture <- function(check) {
  root <- tempfile("peer-inputs-")
  dir.create(root)
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  for (directory in c("config", "data/raw", "data/processed", "reports/tables")) {
    dir.create(file.path(root, directory), recursive = TRUE)
  }
  raw_paths <- paste0("data/raw/", c("listings", "calendar", "reviews"), "_airbnb.csv")
  for (path in raw_paths) writeLines(c("id", "1"), file.path(root, path))
  config_path <- "config/review_analysis.json"
  write_json(list(review_window_days = 365, established_history_days = 365),
             file.path(root, config_path), auto_unbox = TRUE)
  cleaned_path <- "data/processed/listings_clean.rds"
  saveRDS(data.frame(id = "1"), file.path(root, cleaned_path))
  hash <- function(path) digest(file.path(root, path), file = TRUE, algo = "sha256")
  hashes <- setNames(lapply(raw_paths, hash), raw_paths)
  manifest <- list(
    inputs = lapply(raw_paths, function(path) list(path = path, rows = 1L, sha256 = hash(path))),
    outputs = list(list(path = cleaned_path, sha256 = hash(cleaned_path))))
  write_json(manifest, file.path(root, "data/processed/cleaning_manifest.json"), auto_unbox = TRUE)
  summary <- list(config_sha256 = hash(config_path), provenance = list(
    raw_validation = TRUE, raw_file_sha256 = hashes,
    raw_review_validation = list(passed = TRUE, validation_population = "all source listings",
                                 validation_listings = 1L, all_source_listings = 1L)))
  write_json(summary, file.path(root, "reports/tables/rq_scope_summary.json"), auto_unbox = TRUE)
  check(root)
}

expect_failure <- function(root, text) {
  message <- tryCatch({verify_inputs(root); NA_character_}, error = conditionMessage)
  stopifnot(!is.na(message), grepl(text, message, fixed = TRUE),
            grepl("in that order", message, fixed = TRUE))
}

with_fixture(function(root) {
  stopifnot(isTRUE(verify_inputs(root)$provenance$raw_validation))
})
with_fixture(function(root) {
  writeLines("changed configuration", file.path(root, "config/review_analysis.json"))
  expect_failure(root, "different review-analysis configuration")
})
with_fixture(function(root) {
  saveRDS(data.frame(id = "2"), file.path(root, "data/processed/listings_clean.rds"))
  expect_failure(root, "cleaned listings do not match")
})
with_fixture(function(root) {
  writeLines(c("id", "2"), file.path(root, "data/raw/calendar_airbnb.csv"))
  expect_failure(root, "current raw file disagree")
})
with_fixture(function(root) {
  path <- file.path(root, "reports/tables/rq_scope_summary.json")
  summary <- fromJSON(path, simplifyVector = FALSE)
  summary$provenance$raw_file_sha256[["data/raw/reviews_airbnb.csv"]] <- paste(rep("0", 64), collapse = "")
  write_json(summary, path, auto_unbox = TRUE)
  expect_failure(root, "current raw file disagree")
})
with_fixture(function(root) {
  path <- file.path(root, "reports/tables/rq_scope_summary.json")
  summary <- fromJSON(path, simplifyVector = FALSE)
  summary$provenance$raw_review_validation$validation_population <- "specified subset"
  write_json(summary, path, auto_unbox = TRUE)
  expect_failure(root, "not passed for every source listing")
})
with_fixture(function(root) {
  path <- file.path(root, "reports/tables/rq_scope_summary.json")
  summary <- fromJSON(path, simplifyVector = FALSE)
  summary$provenance$raw_review_validation$passed <- FALSE
  write_json(summary, path, auto_unbox = TRUE)
  expect_failure(root, "not passed for every source listing")
})
cat("Peer input gate: seven synthetic checks passed. No analysis outputs were written.\n")
