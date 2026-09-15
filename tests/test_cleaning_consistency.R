# Run from the repository root: Rscript tests/test_cleaning_consistency.R
library(data.table)
library(digest)
library(jsonlite)
script_path <- normalizePath("scripts/01_data_cleaning.R")
config_path <- normalizePath("config/review_analysis.json")
original_dir <- getwd()
fixture_dir <- tempfile("cleaning-check-")
dir.create(file.path(fixture_dir, "data/raw"), recursive = TRUE)
dir.create(file.path(fixture_dir, "data/processed"), recursive = TRUE)
dir.create(file.path(fixture_dir, "config"))
file.copy(config_path, file.path(fixture_dir, "config/review_analysis.json"))
setwd(fixture_dir)
listings <- data.table(id = c("1001", "1002"), host_id = c("10", "20"),
  price = c("$100.00", "$200.00"), accommodates = c(2, 4), bedrooms = c(1, 2),
  bathrooms_text = c("1 bath", "1.5 baths"), amenities = c(toJSON(c("Wifi", "Free parking", 'TV, 43" screen')), '[]'),
  hosts_time_as_host_years = c(1, 2), hosts_time_as_host_months = c(0, 6),
  number_of_reviews = c(3, 1), number_of_reviews_ltm = c(3, 1),
  availability_365 = c(180, 365), last_scraped = "2026-06-20")
num_cols <- c("beds", "minimum_nights", "maximum_nights", "review_scores_rating", "review_scores_accuracy",
  "review_scores_cleanliness", "review_scores_checkin", "review_scores_communication", "review_scores_location",
  "review_scores_value", "reviews_per_month", "estimated_revenue_l365d")
listings[, (num_cols) := 1]
calendar <- data.table(listing_id = rep(c("1001", "1002"), each = 2),
  date = rep(c("2026-06-20", "2026-06-21"), 2), available = c("t", "f", "f", "t"))
reviews <- data.table(listing_id = c("1001", "1001", "1001", "1002"),
  date = c("2025-06-20", "2025-06-21", "2026-06-20", "2026-06-02"))
restore_raw <- function() {
  fwrite(listings, "data/raw/listings_airbnb.csv")
  fwrite(calendar, "data/raw/calendar_airbnb.csv")
  fwrite(reviews, "data/raw/reviews_airbnb.csv")
}
hashes <- function() {
  paths <- sort(list.files("data/processed", full.names = TRUE))
  setNames(vapply(paths, digest, character(1), file = TRUE, algo = "sha256"), basename(paths))
}
run_cleaning <- function(overrides = list()) {
  env <- list2env(overrides, parent = globalenv())
  failure <- NULL
  invisible(capture.output(tryCatch(source(script_path, local = env), error = function(e) failure <<- conditionMessage(e))))
  failure
}
check_failure <- function(label, overrides = list()) {
  before <- hashes()
  failure <- run_cleaning(overrides)
  stopifnot(!is.null(failure), identical(before, hashes()),
    !length(list.files("data", pattern = "^\\.cleaning-", all.files = TRUE)))
  cat("PASS:", label, "preserves all prior outputs\n")
}
restore_raw()
writeLines("preserve", "data/processed/unrelated.txt")
stopifnot(is.null(run_cleaning()))
m <- fromJSON("data/processed/cleaning_manifest.json")
stopifnot(identical(m$inputs$rows, c(2L, 4L, 4L)), nrow(m$outputs) == 5L,
  all(m$inputs$sha256 == vapply(m$inputs$path, digest, character(1), file = TRUE, algo = "sha256")),
  all(m$outputs$sha256 == vapply(m$outputs$path, digest, character(1), file = TRUE, algo = "sha256")),
  all(readRDS("data/processed/availability_90.rds")$open_90 == .5),
  identical(readRDS("data/processed/listings_clean.rds")$price_num, c(100, 200)),
  identical(readRDS("data/processed/listings_clean.rds")$n_amenities, c(3L, 0L)),
  identical(readRDS("data/processed/listings_clean.rds")$has_wifi, c(TRUE, FALSE)),
  identical(readRDS("data/processed/listings_clean.rds")$reviews_365d, c(2L, 1L)),
  identical(readRDS("data/processed/listings_clean.rds")$number_of_reviews_ltm, c(3L, 1L)),
  m$review_reconstruction$passed,
  m$review_reconstruction$listings_changed_by_boundary == 1L,
  m$review_reconstruction$reviews_on_excluded_boundary == 1L,
  m$review_reconstruction$source_window_mismatches == 0L,
  readLines("data/processed/unrelated.txt") == "preserve")
cat("PASS: consistent outputs preserve source counts and exclude the 365-day start boundary\n")
long_listings <- copy(listings)
long_listings[1, amenities := toJSON(c("Wifi", rep(paste(rep("long amenity", 100), collapse = " "), 100)))]
fwrite(long_listings, "data/raw/listings_airbnb.csv")
old_warn <- getOption("warn")
options(warn = 2)
long_failure <- run_cleaning()
options(warn = old_warn)
stopifnot(is.null(long_failure), readRDS("data/processed/listings_clean.rds")$n_amenities[1] == 101L)
cat("PASS: long amenity JSON is parsed as text without file-path warnings\n")
malformed_listings <- copy(listings)
malformed_listings[1, amenities := '["Wifi", broken]']
malformed_listings[2, amenities := '{"Wifi": true}']
fwrite(malformed_listings, "data/raw/listings_airbnb.csv")
stopifnot(is.null(run_cleaning()), all(is.na(readRDS("data/processed/listings_clean.rds")$n_amenities)))
cat("PASS: malformed and non-array amenities remain missing\n")
restore_raw()
stopifnot(is.null(run_cleaning()))
unlink("data/raw/reviews_airbnb.csv")
check_failure("missing raw input")
restore_raw()
bad_calendar <- copy(calendar); bad_calendar[1, available := "invalid"]
fwrite(bad_calendar, "data/raw/calendar_airbnb.csv")
check_failure("invalid calendar value after listings staging")
restore_raw()
bad_reviews <- copy(reviews); bad_reviews[1, listing_id := "missing"]
fwrite(bad_reviews, "data/raw/reviews_airbnb.csv")
check_failure("review foreign-key failure after calendar staging")
restore_raw()
bad_reviews <- copy(reviews); bad_reviews[1, date := NA_character_]
fwrite(bad_reviews, "data/raw/reviews_airbnb.csv")
check_failure("missing review date")
restore_raw()
bad_reviews <- copy(reviews); bad_reviews[1, date := "2026-06-21"]
fwrite(bad_reviews, "data/raw/reviews_airbnb.csv")
check_failure("review after listing scrape date")
restore_raw()
bad_listings <- copy(listings); bad_listings[1, number_of_reviews_ltm := 4L]
fwrite(bad_listings, "data/raw/listings_airbnb.csv")
check_failure("source recent-review reconstruction mismatch")
restore_raw()
bad_listings <- copy(listings); bad_listings[1, number_of_reviews := 4L]
fwrite(bad_listings, "data/raw/listings_airbnb.csv")
check_failure("source total-review reconstruction mismatch")
restore_raw()
rename_failure <- function(from, to) {
  if (basename(to) == "reviews_monthly.rds") return(FALSE)
  base::file.rename(from, to)
}
check_failure("publication failure", list(file.rename = rename_failure))
unlink("data/processed/availability_90.rds")
check_failure("publication failure with a newly introduced output", list(file.rename = rename_failure))
setwd(original_dir)
unlink(fixture_dir, recursive = TRUE)
