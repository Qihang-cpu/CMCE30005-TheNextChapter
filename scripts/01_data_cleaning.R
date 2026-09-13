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

dir.create("data/processed", showWarnings = FALSE, recursive = TRUE)

# ---- Listings ----------------------------------------------------------------

# Missing values arrive as the literal string "NA", so they must be declared
# explicitly or every numeric column is read as text.
raw_paths <- file.path("data/raw", c("listings_airbnb.csv", "calendar_airbnb.csv", "reviews_airbnb.csv"))
if (!all(file.exists(raw_paths))) {
  stop("Restore the three school-supplied CSV files in data/raw before running cleaning. Existing processed files have not been changed.")
}
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
amenity_items <- lapply(listings$amenities, function(x) {
  if (is.na(x)) return(NA_character_)
  tryCatch(as.character(fromJSON(x)), error = function(e) NA_character_)
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
               "number_of_reviews", "number_of_reviews_ltm",
               "number_of_reviews_ly", "reviews_per_month",
               "review_scores_rating", "review_scores_location",
               "review_scores_value", "estimated_occupancy_l365d",
               "estimated_revenue_l365d", "first_review", "last_review")
keep_cols <- intersect(keep_cols, names(listings))
saveRDS(listings[, ..keep_cols], "data/processed/listings_clean.rds")

# ---- Calendar: monthly availability -----------------------------------------

calendar <- fread("data/raw/calendar_airbnb.csv",
                  select = c("listing_id", "date", "available"),
                  colClasses = c(listing_id = "character"))
stopifnot(!anyDuplicated(calendar[, .(listing_id, date)]),
          all(calendar$listing_id %in% listings$id))
calendar[, month := format(date, "%Y-%m")]

calendar_monthly <- calendar[, .(nights = .N, open = sum(available == "t")), by = month]
calendar_monthly[, pct_open := open / nights]
setorder(calendar_monthly, month)
saveRDS(calendar_monthly, "data/processed/calendar_monthly.rds")

# Ninety dates, starting with each listing's first observed calendar date.
calendar[, window_start := min(date), by = listing_id]
avail_90 <- calendar[date < window_start + 90,
                     .(open_90 = mean(available == "t"),
                       window_start = min(date), window_end = max(date),
                       observed_nights = .N), by = listing_id]
stopifnot(all(avail_90$observed_nights <= 90))
saveRDS(avail_90, "data/processed/availability_90.rds")

rm(calendar); gc()

# ---- Reviews: monthly counts as a demand proxy -------------------------------

reviews <- fread("data/raw/reviews_airbnb.csv", select = c("listing_id", "date"),
                 colClasses = c(listing_id = "character"))
stopifnot(all(reviews$listing_id %in% listings$id))

reviews_monthly <- reviews[, .N, by = .(month = format(date, "%Y-%m"))]
setorder(reviews_monthly, month)
saveRDS(reviews_monthly, "data/processed/reviews_monthly.rds")

reviews_per_listing <- reviews[, .(n_reviews = .N, last_review = max(date)),
                               by = listing_id]
saveRDS(reviews_per_listing, "data/processed/reviews_per_listing.rds")

cat("Cleaned tables written to data/processed/\n")
