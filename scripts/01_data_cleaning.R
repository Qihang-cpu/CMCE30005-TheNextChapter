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

dir.create("data/processed", showWarnings = FALSE, recursive = TRUE)

# ---- Listings ----------------------------------------------------------------

# Missing values arrive as the literal string "NA", so they must be declared
# explicitly or every numeric column is read as text.
listings <- fread("data/raw/listings_airbnb.csv", na.strings = c("NA", "", "N/A"))

cat("Raw listings:", nrow(listings), "\n")

# price is stored as text, e.g. "$1,234.00"
listings[, price_num := as.numeric(str_remove_all(price, "[$,]"))]

# the bathrooms column is empty; the real information sits in bathrooms_text,
# e.g. "1.5 shared baths", "Half-bath"
listings[, bathrooms_num := as.numeric(str_extract(bathrooms_text, "[0-9.]+"))]
listings[str_detect(tolower(bathrooms_text), "half"), bathrooms_num := 0.5]
listings[, shared_bath := str_detect(tolower(bathrooms_text), "shared") %in% TRUE]

# amenities is a JSON-style list; the item count is a simple richness measure
listings[, n_amenities := str_count(amenities, '",\\s*"') + 1L]
listings[amenities %in% c("[]", NA), n_amenities := 0L]

num_cols <- c("bedrooms", "beds", "minimum_nights", "maximum_nights",
              "review_scores_rating", "review_scores_accuracy",
              "review_scores_cleanliness", "review_scores_checkin",
              "review_scores_communication", "review_scores_location",
              "review_scores_value", "reviews_per_month",
              "estimated_revenue_l365d", "host_total_listings_count")
listings[, (num_cols) := lapply(.SD, function(x) suppressWarnings(as.numeric(x))),
         .SDcols = num_cols]

listings[, host_response_rate_num := as.numeric(str_remove(host_response_rate, "%")) / 100]
listings[, host_acceptance_rate_num := as.numeric(str_remove(host_acceptance_rate, "%")) / 100]

# minimum_nights of 28 or more is effectively a long-stay listing and sits in a
# different market to nightly short-stay accommodation
listings[, min_nights_grp := cut(minimum_nights, c(0, 1, 6, 27, Inf),
                                 labels = c("1", "2-6", "7-27", "28+"))]

# Analysis sample: a nightly price in a plausible short-stay range. Below $30 is
# usually a mis-entered or long-let rate; above $1,500 is a handful of luxury
# outliers that distort the price distribution.
listings[, priced := !is.na(price_num) & price_num >= 30 & price_num <= 1500]

cat("Listings with usable price:", listings[priced == TRUE, .N],
    sprintf("(dropped %d missing, %d outside $30-$1500)\n",
            listings[is.na(price_num), .N],
            listings[!is.na(price_num) & (price_num < 30 | price_num > 1500), .N]))

keep_cols <- c("id", "host_id", "host_since", "host_is_superhost",
               "host_response_rate_num", "host_acceptance_rate_num",
               "host_listings_count", "calculated_host_listings_count",
               "neighbourhood_cleansed", "latitude", "longitude",
               "property_type", "room_type", "accommodates", "bedrooms", "beds",
               "bathrooms_num", "shared_bath", "n_amenities",
               "price_num", "priced", "minimum_nights", "min_nights_grp",
               "availability_365", "availability_90",
               "number_of_reviews", "number_of_reviews_ltm", "reviews_per_month",
               "review_scores_rating", "review_scores_location",
               "review_scores_value", "estimated_occupancy_l365d",
               "estimated_revenue_l365d", "first_review", "last_review")
saveRDS(listings[, ..keep_cols], "data/processed/listings_clean.rds")

# ---- Calendar: monthly availability -----------------------------------------

calendar <- fread("data/raw/calendar_airbnb.csv",
                  select = c("listing_id", "date", "available"))
calendar[, month := format(date, "%Y-%m")]

calendar_monthly <- calendar[, .(nights = .N, open = sum(available == "t")), by = month]
calendar_monthly[, pct_open := open / nights]
setorder(calendar_monthly, month)
saveRDS(calendar_monthly, "data/processed/calendar_monthly.rds")

avail_90 <- calendar[date <= min(date) + 90,
                     .(open_90 = mean(available == "t")), by = listing_id]
saveRDS(avail_90, "data/processed/availability_90.rds")

rm(calendar); gc()

# ---- Reviews: monthly counts as a demand proxy -------------------------------

reviews <- fread("data/raw/reviews_airbnb.csv", select = c("listing_id", "date"))

reviews_monthly <- reviews[, .N, by = .(month = format(date, "%Y-%m"))]
setorder(reviews_monthly, month)
saveRDS(reviews_monthly, "data/processed/reviews_monthly.rds")

reviews_per_listing <- reviews[, .(n_reviews = .N, last_review = max(date)),
                               by = listing_id]
saveRDS(reviews_per_listing, "data/processed/reviews_per_listing.rds")

cat("Cleaned tables written to data/processed/\n")
