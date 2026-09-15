# ============================================================
# CMCE30005 Business Analytics Challenge
# Script: 01_data_cleaning.R
# Purpose: Clean the Inside Airbnb Melbourne snapshot and build the
#          analysis-ready tables used by scripts 02 and 03
# Author: TheNextChapter (Group 2)
# Date: 6 August 2026
# ============================================================
#
# Input : data/raw/listings_airbnb.csv
#         data/raw/calendar_airbnb.csv
#         data/raw/reviews_airbnb.csv
# Output: data/processed/*.rds
#
# Note: data.table is used instead of readr here because calendar_airbnb.csv
# holds 9.4 million rows (361 MB); fread keeps the run under two minutes.
# ============================================================

library(data.table)
library(stringr)
library(jsonlite)
library(digest)

clean_data <- function() {
  output_dir <- "data/processed"

  # ---- Listings ----------------------------------------------------------------

  # Missing values arrive as the literal string "NA", so they must be declared
  # explicitly or every numeric column is read as text.
  raw_paths <- file.path("data/raw", c("listings_airbnb.csv", "calendar_airbnb.csv", "reviews_airbnb.csv"))
  if (!all(file.exists(raw_paths))) {
    stop("Restore the three school-supplied CSV files in data/raw before running cleaning. Existing processed files have not been changed.")
  }
  config <- fromJSON("config/review_analysis.json")
  review_window_days <- as.integer(config$review_window_days)
  stopifnot(length(review_window_days) == 1L, !is.na(review_window_days),
            review_window_days == 365L)
  input_hashes <- vapply(raw_paths, digest, character(1), file = TRUE, algo = "sha256")
  staging_dir <- tempfile(".cleaning-", tmpdir = "data")
  dir.create(staging_dir)
  keep_staging <- FALSE
  on.exit(if (!keep_staging) unlink(staging_dir, recursive = TRUE), add = TRUE)

  listings <- fread(raw_paths[1], na.strings = c("NA", "", "N/A"),
                    colClasses = c(id = "character", host_id = "character"))
  stopifnot(!anyNA(listings$id), !anyDuplicated(listings$id))

  cat("Raw listings:", nrow(listings), "\n")

  # price is stored as text, e.g. "$1,234.00"
  listings[, price_num := as.numeric(str_remove_all(price, "[$,]"))]

  # two listings at the same nightly price are not comparable if one sleeps
  # two and the other eight
  listings[, price_per_person  := round(price_num / accommodates, 2)]
  listings[, price_per_bedroom := round(price_num / pmax(bedrooms, 1), 2)]

  # the bathrooms column is empty; the real information sits in bathrooms_text,
  # e.g. "1.5 shared baths", "Half-bath"
  listings[, bathrooms_num := as.numeric(str_extract(bathrooms_text, "[0-9.]+"))]
  listings[str_detect(tolower(bathrooms_text), "half"), bathrooms_num := 0.5]
  listings[, shared_bath := str_detect(tolower(bathrooms_text), "shared") %in% TRUE]

  # Parse the list itself: an amenity name may contain a comma.
  parse_amenity_array <- function(value) {
    if (!startsWith(trimws(value), "[")) stop("Amenities must be a JSON array.")
    items <- parse_json(value, simplifyVector = FALSE)
    stopifnot(is.list(items), all(vapply(items, function(item) {
      is.character(item) && length(item) == 1L && !is.na(item)
    }, logical(1))))
    as.character(unlist(items, use.names = FALSE))
  }
  amenity_items <- lapply(listings$amenities, function(x) {
    if (is.na(x)) return(NA_character_)
    tryCatch(parse_amenity_array(x), error = function(e) {
      # fread retains doubled quotes inside standard CSV quoted fields.
      tryCatch(parse_amenity_array(gsub('""', '"', x, fixed = TRUE)),
               error = function(e) NA_character_)
    })
  })
  listings[, n_amenities := vapply(amenity_items, function(x) {
    if (anyNA(x)) NA_integer_ else length(x)
  }, integer(1))]
  amenity_flag <- function(pattern, exclude = NULL) vapply(amenity_items, function(x) {
    if (anyNA(x)) return(NA)
    found <- grepl(pattern, x, ignore.case = TRUE)
    if (!is.null(exclude)) found <- found & !grepl(exclude, x, ignore.case = TRUE)
    any(found)
  }, logical(1))
  listings[, has_wifi := amenity_flag("wi-?fi")]
  listings[, has_pool := amenity_flag("\\bpool\\b", "pool table")]
  listings[, has_aircon := amenity_flag("air conditioning")]
  listings[, has_free_parking := amenity_flag("free parking")]

  num_cols <- c("bedrooms", "beds", "minimum_nights", "maximum_nights",
                "review_scores_rating", "review_scores_accuracy",
                "review_scores_cleanliness", "review_scores_checkin",
                "review_scores_communication", "review_scores_location",
                "review_scores_value", "reviews_per_month",
                "estimated_revenue_l365d")
  listings[, (num_cols) := lapply(.SD, function(x) suppressWarnings(as.numeric(x))),
           .SDcols = num_cols]

  # Host tenure. host_since is empty in this snapshot, but the years/months pair
  # survives and reconstructs the same information.
  listings[, host_tenure_years := hosts_time_as_host_years + hosts_time_as_host_months / 12]

  # Thirteen columns are entirely empty in this snapshot and are dropped rather
  # than carried through as all-NA: calendar_updated, host_acceptance_rate,
  # host_neighbourhood, host_response_rate, host_response_time, host_since,
  # host_thumbnail_url, host_total_listings_count, instant_bookable, license,
  # neighborhood_overview, neighbourhood, neighbourhood_group_cleansed.

  # minimum_nights of 28 or more is effectively a long-stay listing and sits in a
  # different market to nightly short-stay accommodation
  listings[, min_nights_grp := cut(minimum_nights, c(0, 1, 6, 27, Inf),
                                   labels = c("1", "2-6", "7-27", "28+"))]

  # Working price range for comparisons. Values outside it are not automatically
  # errors; analyses must report the effect of this sample restriction.
  listings[, priced := !is.na(price_num) & price_num >= 30 & price_num <= 1500]

  # flags, not deletions: an outlier is a statement about the distribution,
  # not about the truth of the value
  listings[, never_reviewed   := number_of_reviews == 0]
  listings[, always_available := availability_365 == 365]

  cat("Listings with usable price:", listings[priced == TRUE, .N],
      sprintf("(dropped %d missing, %d outside $30-$1500)\n",
              listings[is.na(price_num), .N],
              listings[!is.na(price_num) & (price_num < 30 | price_num > 1500), .N]))

  keep_cols <- c("id", "host_id", "last_scraped", "host_is_superhost", "host_tenure_years",
                 "host_identity_verified", "host_listings_count",
                 "calculated_host_listings_count",
                 "neighbourhood_cleansed", "latitude", "longitude",
                 "property_type", "room_type", "accommodates", "bedrooms", "beds",
                 "bathrooms_num", "shared_bath", "n_amenities",
                 "has_wifi", "has_pool", "has_aircon", "has_free_parking",
                 "price_per_person", "price_per_bedroom",
                 "never_reviewed", "always_available",
                 "price_num", "priced", "minimum_nights", "min_nights_grp",
                 "availability_365", "availability_90", "availability_eoy",
                 "number_of_reviews", "number_of_reviews_ltm", "reviews_365d",
                 "number_of_reviews_ly", "reviews_per_month",
                 "review_scores_rating", "review_scores_location",
                 "review_scores_value", "estimated_occupancy_l365d",
                 "estimated_revenue_l365d", "first_review", "last_review")

  # ---- Calendar: monthly availability -----------------------------------------

  calendar <- fread(raw_paths[2],
                    select = c("listing_id", "date", "available"),
                    colClasses = c(listing_id = "character"))
  calendar[, date := as.IDate(date)]
  stopifnot(!anyNA(calendar$listing_id), !anyNA(calendar$date),
            !anyDuplicated(calendar[, .(listing_id, date)]),
            all(calendar$listing_id %in% listings$id),
            all(calendar$available %in% c("t", "f")))
  calendar_nrows <- nrow(calendar)
  calendar[, month := format(date, "%Y-%m")]

  calendar_monthly <- calendar[, .(nights = .N, open = sum(available == "t")), by = month]
  calendar_monthly[, pct_open := open / nights]
  setorder(calendar_monthly, month)
  saveRDS(calendar_monthly, file.path(staging_dir, "calendar_monthly.rds"))

  # Ninety dates, starting with each listing's first observed calendar date.
  calendar[, window_start := min(date), by = listing_id]
  avail_90 <- calendar[date < window_start + 90,
                       .(open_90 = mean(available == "t"),
                         window_start = min(date), window_end = max(date),
                         observed_nights = .N), by = listing_id]
  stopifnot(all(avail_90$observed_nights <= 90))
  saveRDS(avail_90, file.path(staging_dir, "availability_90.rds"))

  rm(calendar); gc()

  # ---- Reviews: monthly counts as a demand proxy -------------------------------

  reviews <- fread(raw_paths[3], select = c("listing_id", "date"),
                   colClasses = c(listing_id = "character"))
  reviews[, date := as.IDate(date)]
  stopifnot(!anyNA(reviews$listing_id), !anyNA(reviews$date),
            all(reviews$listing_id %in% listings$id))

  scrape_dates <- as.IDate(listings$last_scraped)
  stopifnot(!anyNA(scrape_dates))
  reviews[, days_before_scrape := as.integer(
    scrape_dates[match(listing_id, listings$id)] - date)]
  stopifnot(all(reviews$days_before_scrape >= 0L))

  recent_counts <- reviews[days_before_scrape < review_window_days,
                           .(reviews_365d = .N), by = listing_id]
  inclusive_counts <- reviews[days_before_scrape <= review_window_days,
                              .(source_window_count = .N), by = listing_id]
  listings[, reviews_365d := recent_counts$reviews_365d[match(id, recent_counts$listing_id)]]
  listings[is.na(reviews_365d), reviews_365d := 0L]
  reconstructed_source <- inclusive_counts$source_window_count[
    match(listings$id, inclusive_counts$listing_id)]
  reconstructed_source[is.na(reconstructed_source)] <- 0L
  supplied_ltm <- suppressWarnings(as.numeric(listings$number_of_reviews_ltm))
  stopifnot(!anyNA(supplied_ltm), all(supplied_ltm >= 0),
            all(supplied_ltm == floor(supplied_ltm)))
  source_window_mismatches <- sum(reconstructed_source != supplied_ltm)
  if (source_window_mismatches > 0L) {
    stop("The supplied recent-review counts do not match the inclusive source window for ",
         source_window_mismatches, " listings. Existing processed files have not been changed.")
  }

  reviews_monthly <- reviews[, .N, by = .(month = format(date, "%Y-%m"))]
  setorder(reviews_monthly, month)
  saveRDS(reviews_monthly, file.path(staging_dir, "reviews_monthly.rds"))

  reviews_per_listing <- reviews[, .(n_reviews = .N, last_review = max(date)),
                                 by = listing_id]
  reconstructed_total <- reviews_per_listing$n_reviews[
    match(listings$id, reviews_per_listing$listing_id)]
  reconstructed_total[is.na(reconstructed_total)] <- 0L
  stopifnot(all(reconstructed_total == listings$number_of_reviews))
  saveRDS(reviews_per_listing, file.path(staging_dir, "reviews_per_listing.rds"))

  # Preserve the supplied field and derive the exact 365-date outcome separately.
  keep_cols <- intersect(keep_cols, names(listings))
  saveRDS(listings[, ..keep_cols], file.path(staging_dir, "listings_clean.rds"))

  # A run must use one unchanged set of inputs before any output is replaced.
  final_hashes <- vapply(raw_paths, digest, character(1), file = TRUE, algo = "sha256")
  if (!identical(input_hashes, final_hashes)) {
    stop("A source CSV changed during cleaning. Existing processed files have not been changed.")
  }
  staged_paths <- list.files(staging_dir, pattern = "\\.rds$", full.names = TRUE)
  input_rows <- c(nrow(listings), calendar_nrows, nrow(reviews))
  manifest <- list(
    created_at_utc = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    review_reconstruction = list(
      passed = TRUE,
      listings_checked = nrow(listings),
      review_rows = nrow(reviews),
      outcome_column = "reviews_365d",
      outcome_window = "(last_scraped minus 365 days, last_scraped]",
      preserved_source_column = "number_of_reviews_ltm",
      observed_source_window = "[last_scraped minus 365 days, last_scraped]",
      source_window_mismatches = source_window_mismatches,
      total_review_count_mismatches = sum(reconstructed_total != listings$number_of_reviews),
      listings_changed_by_boundary = sum(listings$reviews_365d != supplied_ltm),
      reviews_on_excluded_boundary = sum(reviews$days_before_scrape == review_window_days)
    ),
    inputs = lapply(seq_along(raw_paths), function(i) list(
      path = raw_paths[i], rows = input_rows[i], sha256 = unname(input_hashes[i])
    )),
    outputs = lapply(staged_paths, function(path) list(
      path = file.path(output_dir, basename(path)),
      sha256 = digest(path, file = TRUE, algo = "sha256")
    ))
  )
  manifest_path <- file.path(staging_dir, "cleaning_manifest.json")
  write_json(manifest, manifest_path, pretty = TRUE, auto_unbox = TRUE)
  staged_paths <- c(staged_paths, manifest_path)

  # Back up only this script's outputs; other processed results remain untouched.
  dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)
  destinations <- file.path(output_dir, basename(staged_paths))
  if (any(dir.exists(destinations))) stop("A processed output path is a directory.")
  backup_dir <- file.path(staging_dir, "previous")
  dir.create(backup_dir)
  backups <- file.path(backup_dir, basename(staged_paths))
  existed <- file.exists(destinations)
  if (any(existed) && !all(file.copy(destinations[existed], backups[existed]))) {
    stop("Could not back up processed outputs. Existing files have not been changed.")
  }
  published <- rep(FALSE, length(staged_paths))
  tryCatch({
    for (i in seq_along(staged_paths)) {
      if (!file.rename(staged_paths[i], destinations[i])) {
        stop("Could not publish ", basename(destinations[i]))
      }
      published[i] <- TRUE
    }
  }, error = function(e) {
    restore <- which(published & existed)
    restored <- !length(restore) || all(file.copy(backups[restore], destinations[restore],
                                                 overwrite = TRUE))
    remove <- destinations[published & !existed]
    removed <- !length(remove) || unlink(remove) == 0L
    if (!restored || !removed) {
      keep_staging <<- TRUE
      stop(conditionMessage(e), "; recovery copies retained in ", staging_dir)
    }
    stop(conditionMessage(e), "; previous processed outputs restored.")
  })
  cat("Cleaned tables and input manifest written to data/processed/\n")
}

clean_data()
