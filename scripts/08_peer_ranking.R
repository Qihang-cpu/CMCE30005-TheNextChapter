# CMCE30005: descriptive review activity in established residential listings.
# Run from the repository root after cleaning and the Python review analysis.
# Common eligibility and benchmark-partition rules are in config/review_analysis.json.
# First review measures recorded history, not launch date or continuous operation.

library(data.table)
library(ggplot2)
library(scales)
library(digest)
library(jsonlite)

dir.create("reports/tables", showWarnings = FALSE, recursive = TRUE)
dir.create("reports/figures", showWarnings = FALSE, recursive = TRUE)
cfg <- fromJSON("config/review_analysis.json")
MIN_LISTINGS <- as.integer(cfg$minimum_segment_listings)
BOOT_REPS <- 1000L
BOOT_SEED <- as.integer(cfg$seed)
HISTORY_DAYS <- cfg$established_history_days
REVIEW_WINDOW_DAYS <- cfg$review_window_days
stopifnot(length(HISTORY_DAYS) == 1L, is.finite(HISTORY_DAYS), HISTORY_DAYS >= 1,
          HISTORY_DAYS == as.integer(HISTORY_DAYS),
          length(REVIEW_WINDOW_DAYS) == 1L, is.finite(REVIEW_WINDOW_DAYS), REVIEW_WINDOW_DAYS >= 1,
          REVIEW_WINDOW_DAYS == as.integer(REVIEW_WINDOW_DAYS))
SEGMENT_COLS <- c("lga", "dwelling_class", "bedrooms")
PROPERTY_MAP <- unlist(cfg$property_map)
MAIN_SCOPE <- sprintf("Established standard entire homes, 1-3 bedrooms, price AUD%s-%s; non-benchmark hosts; final segment n>=%s",
                      cfg$minimum_price, cfg$maximum_price, MIN_LISTINGS)
ALL_HISTORIES_SCOPE <- sub("Established standard", "All-review-history standard", MAIN_SCOPE, fixed = TRUE)
NO_PRICE_SCOPE <- "Established standard entire homes, 1-3 bedrooms; no price restriction; non-benchmark hosts; final segment n>=50"

# Expand an exact non-negative integer from its text spelling. Only the small
# decimal exponent is converted to an R integer; identifier digits never pass
# through floating point. This cannot recover precision lost before this file.
canonical_id <- function(s) {
  if (is.na(s) || !nzchar(trimws(s))) stop("Missing host identifier")
  s <- trimws(s)
  pieces <- strsplit(tolower(s), "e", fixed = TRUE)[[1]]
  if (length(pieces) > 2L) stop("Invalid host identifier: ", s)
  exponent <- if (length(pieces) == 2L) as.integer(pieces[2]) else 0L
  if (is.na(exponent) || abs(exponent) > 100L) stop("Invalid identifier exponent")
  mantissa <- sub("^\\+", "", pieces[1])
  if (!grepl("^[0-9]+(\\.[0-9]*)?$", mantissa)) stop("Invalid host identifier: ", s)
  decimal <- strsplit(mantissa, ".", fixed = TRUE)[[1]]
  fraction <- if (length(decimal) == 2L) decimal[2] else ""
  digits <- paste0(decimal[1], fraction)
  end <- nchar(decimal[1]) + exponent
  if (end <= 0L) {
    if (grepl("[1-9]", digits)) stop("Non-integer host identifier")
    answer <- "0"
  } else if (end < nchar(digits)) {
    if (grepl("[1-9]", substring(digits, end + 1L))) stop("Non-integer host identifier")
    answer <- substr(digits, 1L, end)
  } else {
    answer <- paste0(digits, strrep("0", end - nchar(digits)))
  }
  answer <- sub("^0+", "", answer)
  if (!nzchar(answer)) "0" else answer
}

# Missing first reviews are retained for the all-history sensitivity. A missing
# or malformed scrape date cannot define either eligibility or a review window.
parse_listing_date <- function(x, field, allow_missing = FALSE) {
  if (inherits(x, "POSIXt")) x <- as.Date(x, tz = "UTC")
  raw <- trimws(as.character(x))
  missing <- is.na(raw) | raw == ""
  parsed <- suppressWarnings(as.Date(raw, format = "%Y-%m-%d"))
  invalid <- !missing & (!grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}$", raw) |
                          is.na(parsed) | as.character(parsed) != raw)
  if (any(invalid)) stop(field, " contains ", sum(invalid), " invalid date(s). Rebuild the cleaned data from validated raw files.")
  if (!allow_missing && any(missing)) stop(field, " contains ", sum(missing), " missing date(s). Rebuild the cleaned data from validated raw files.")
  parsed[missing] <- as.Date(NA)
  parsed
}

has_established_history <- function(first_review, last_scraped, history_days) {
  !is.na(first_review) & first_review <= last_scraped - history_days
}

verify_analysis_inputs <- function(root = ".") {
  fail <- function(reason) stop(reason,
    "\nRestore the raw files, then run scripts/01_data_cleaning.R, scripts/rq_scope_feasibility.py and scripts/08_peer_ranking.R in that order.",
    call. = FALSE)
  read_record <- function(relative_path) {
    path <- file.path(root, relative_path)
    if (!file.exists(path)) fail(paste("Required verification file is missing:", relative_path))
    tryCatch(fromJSON(path, simplifyVector = FALSE),
             error = function(e) fail(paste("Cannot read verification file:", relative_path)))
  }
  recorded_hash <- function(entries, relative_path) {
    if (!is.list(entries) || !length(entries)) fail("The cleaning manifest has no input/output records.")
    matches <- vapply(entries, function(entry) is.list(entry) && identical(entry$path, relative_path), logical(1))
    if (sum(matches) != 1L) fail(paste("The cleaning manifest needs one record for", relative_path))
    entries[[which(matches)]]$sha256
  }
  actual_hash <- function(relative_path) {
    path <- file.path(root, relative_path)
    if (!file.exists(path) || dir.exists(path)) fail(paste("Required input file is missing:", relative_path))
    digest(path, file = TRUE, algo = "sha256")
  }
  manifest <- read_record("data/processed/cleaning_manifest.json")
  summary <- read_record("reports/tables/rq_scope_summary.json")
  provenance <- summary$provenance
  validation <- provenance$raw_review_validation
  if (!isTRUE(provenance$raw_validation) || !isTRUE(validation$passed) ||
      !identical(validation$validation_population, "all source listings") ||
      !isTRUE(validation$validation_listings == validation$all_source_listings)) {
    fail("The Python review reconstruction has not passed for every source listing.")
  }
  if (!identical(summary$config_sha256, actual_hash("config/review_analysis.json"))) {
    fail("The Python results use a different review-analysis configuration.")
  }
  cleaned_path <- "data/processed/listings_clean.rds"
  if (!identical(recorded_hash(manifest$outputs, cleaned_path), actual_hash(cleaned_path))) {
    fail("The cleaned listings do not match the cleaning manifest.")
  }
  for (name in c("listings", "calendar", "reviews")) {
    path <- paste0("data/raw/", name, "_airbnb.csv")
    expected <- recorded_hash(manifest$inputs, path)
    if (!identical(expected, provenance$raw_file_sha256[[path]]) ||
        !identical(expected, actual_hash(path))) {
      fail(paste("Cleaning, Python validation and the current raw file disagree:", path))
    }
  }
  summary
}

verified_summary <- verify_analysis_inputs()
listings <- readRDS("data/processed/listings_clean.rds")
required <- c("id", "host_id", "room_type", "property_type", "bedrooms",
              "neighbourhood_cleansed", "price_num", "reviews_365d", "first_review", "last_scraped")
missing_columns <- setdiff(required, names(listings))
if (length(missing_columns)) stop("Cleaned listings are missing required columns: ",
                                paste(missing_columns, collapse = ", "),
                                ". Rebuild them from validated raw files before ranking.")
stopifnot(!anyDuplicated(listings$id))
listings[, last_scraped := parse_listing_date(last_scraped, "last_scraped")]
listings[, first_review := parse_listing_date(first_review, "first_review", allow_missing = TRUE)]
if (any(listings$first_review > listings$last_scraped, na.rm = TRUE)) {
  stop("At least one first_review date is after its listing's last_scraped date.")
}
listings[, established_history := has_established_history(first_review, last_scraped, HISTORY_DAYS)]
# Python has checked reviews_365d against the same raw review file:
# last_scraped - REVIEW_WINDOW_DAYS < review date <= last_scraped.
if (anyNA(listings$reviews_365d) || any(!is.finite(listings$reviews_365d)) ||
    any(listings$reviews_365d < 0) || any(listings$reviews_365d %% 1 != 0)) {
  stop("reviews_365d must contain non-negative integer counts for every listing.")
}
raw_hosts <- unique(listings$host_id)
host_map <- setNames(vapply(raw_hosts, canonical_id, character(1)), raw_hosts)
listings[, canonical_host_id := unname(host_map[host_id])]
hash_rule <- cfg$benchmark_partition
canonical_hosts <- unique(listings$canonical_host_id)
hash_values <- vapply(canonical_hosts, function(h)
  digest(paste0(hash_rule$hash_prefix, h), algo = hash_rule$hash_algorithm, serialize = FALSE), character(1))
benchmark_flags <- strtoi(substr(hash_values, 1, hash_rule$hex_characters), base = 16L) %% hash_rule$modulus ==
  hash_rule$benchmark_remainder
partition_map <- setNames(benchmark_flags, canonical_hosts)
listings[, benchmark_host := unname(partition_map[canonical_host_id])]
listings[, lga := fifelse(neighbourhood_cleansed == "Moreland", "Merri-bek", neighbourhood_cleansed)]
listings[, dwelling_class := unname(PROPERTY_MAP[property_type])]

entire13 <- copy(listings[room_type == cfg$room_type & bedrooms %in% cfg$bedrooms])
entire13[, standard_type := !is.na(dwelling_class)]
standard <- entire13[standard_type == TRUE]
priced <- standard[!is.na(price_num) & price_num >= cfg$minimum_price & price_num <= cfg$maximum_price]
established <- priced[established_history == TRUE]
stopifnot(!anyNA(established$reviews_365d), !anyNA(established$canonical_host_id),
          !anyNA(established$lga), all(established$reviews_365d >= 0))

eligible_cohort <- function(x) {
  cells <- x[, .(n_listings = .N), by = SEGMENT_COLS][n_listings >= MIN_LISTINGS]
  x[cells[, ..SEGMENT_COLS], on = SEGMENT_COLS, nomatch = 0]
}
analysis_before_size <- established[benchmark_host == FALSE]
main <- eligible_cohort(analysis_before_size)
main_cells <- unique(main[, ..SEGMENT_COLS])
benchmark_before_cells <- established[benchmark_host == TRUE]
benchmark <- benchmark_before_cells[main_cells, on = SEGMENT_COLS, nomatch = 0]
stopifnot(nrow(main) > 0, nrow(benchmark) > 0,
          !length(intersect(main$canonical_host_id, benchmark$canonical_host_id)))
benchmark_p75 <- unname(quantile(benchmark$reviews_365d, cfg$benchmark_quantile, type = 7))
REVIEW_TARGET <- as.integer(ceiling(benchmark_p75))
main[, meets_target := reviews_365d >= REVIEW_TARGET]
benchmark[, meets_target := reviews_365d >= REVIEW_TARGET]
agreement <- c(
  source_listings = isTRUE(nrow(listings) == verified_summary$provenance$raw_review_validation$all_source_listings),
  review_target = isTRUE(REVIEW_TARGET == verified_summary$common_review_threshold),
  analysis_listings = isTRUE(nrow(main) == verified_summary$eligible_listings),
  analysis_hosts = isTRUE(uniqueN(main$canonical_host_id) == verified_summary$eligible_hosts),
  analysis_segments = isTRUE(nrow(main_cells) == verified_summary$eligible_cells_ge_50),
  reference_listings = isTRUE(nrow(benchmark) == verified_summary$benchmark_development$n_listings),
  reference_hosts = isTRUE(uniqueN(benchmark$canonical_host_id) == verified_summary$benchmark_development$n_hosts))
if (!all(agreement)) {
  stop("R and Python disagree on: ", paste(names(agreement)[!agreement], collapse = ", "),
       ". Resolve the cleaning/scope differences and rerun 01, Python review analysis and 08 before publishing rankings.")
}

# Remove all benchmark hosts from every analysis sensitivity, not just the
# benchmark hosts whose listings supplied the primary reference distribution.
all_histories <- eligible_cohort(priced[benchmark_host == FALSE])
all_histories[, meets_target := reviews_365d >= REVIEW_TARGET]
no_price <- eligible_cohort(standard[benchmark_host == FALSE & established_history == TRUE])
no_price[, meets_target := reviews_365d >= REVIEW_TARGET]
stopifnot(!any(main$benchmark_host), !any(all_histories$benchmark_host), !any(no_price$benchmark_host))

scope_row <- function(x, stage) data.table(
  stage = stage, n_listings = nrow(x), n_hosts = uniqueN(x$canonical_host_id),
  n_segments = uniqueN(x[, ..SEGMENT_COLS]),
  n_zero_reviews = sum(x$reviews_365d == 0),
  n_meeting_target = sum(x$reviews_365d >= REVIEW_TARGET),
  observed_target_rate = mean(x$reviews_365d >= REVIEW_TARGET),
  reviews_median = median(x$reviews_365d),
  reviews_p75 = unname(quantile(x$reviews_365d, .75, type = 7)),
  review_target = REVIEW_TARGET)
scope <- rbindlist(list(
  scope_row(entire13, "Entire homes with 1-3 bedrooms, all host partitions"),
  scope_row(standard, "Four standard dwelling types, all host partitions"),
  scope_row(priced, "Standard types with eligible price, all host partitions"),
  scope_row(established, "Established history and price eligible, all host partitions"),
  scope_row(analysis_before_size, "Established analysis hosts, before segment size rule"),
  scope_row(main, "Main established analysis cohort after segment n>=50"),
  scope_row(benchmark_before_cells, "Established benchmark hosts before main-cell restriction"),
  scope_row(benchmark, "Benchmark reference within final main analysis cells"),
  scope_row(all_histories, "All-review-histories analysis sensitivity after segment n>=50"),
  scope_row(no_price, "Established no-price-filter analysis sensitivity after segment n>=50")))
fwrite(scope, "reports/tables/review_scope_summary.csv")
partition_summary <- rbindlist(lapply(list(
  list(x = listings, population = "All saved listings"),
  list(x = established, population = "Primary eligibility before cell-size rule"),
  list(x = rbind(main, benchmark, fill = TRUE), population = "Final main analysis cells")
), function(entry) entry$x[, .(
  population = entry$population, n_listings = .N, n_hosts = uniqueN(canonical_host_id),
  n_segments = uniqueN(.SD), review_target = REVIEW_TARGET,
  n_meeting_target = sum(reviews_365d >= REVIEW_TARGET),
  observed_target_rate = mean(reviews_365d >= REVIEW_TARGET)
), by = .(partition = fifelse(benchmark_host, "benchmark development", "analysis")), .SDcols = SEGMENT_COLS]))
partition_summary[, benchmark_raw_p75 := benchmark_p75]
partition_summary[, partition_rule := sprintf("SHA256(%s + canonical host ID), first %s hex %% %s == %s",
                                              hash_rule$hash_prefix, hash_rule$hex_characters,
                                              hash_rule$modulus, hash_rule$benchmark_remainder)]
fwrite(partition_summary, "reports/tables/benchmark_partition_summary.csv")

# The property-type inventory uses all supplied entire homes with 1-3 bedrooms;
# its denominators are not the smaller established analysis cohort.
type_counts <- entire13[, .(n_listings = .N), by = .(property_type, standard_type)]
type_counts[, scope := "All entire homes with 1-3 bedrooms, before history, price or host filters"]
type_counts[, lga := "All LGAs"]
type_counts[, n_scope_listings := nrow(entire13)]
type_counts[, share_of_scope := n_listings / n_scope_listings]
excluded_by_lga <- entire13[, .(n_listings = sum(!standard_type), n_scope_listings = .N,
                                 share_of_scope = mean(!standard_type)), by = lga]
excluded_by_lga[, scope := "Excluded whitelist types within LGA, entire homes with 1-3 bedrooms"]
excluded_by_lga[, property_type := "All excluded types"]
excluded_by_lga[, standard_type := FALSE]
three_types <- c("Entire cottage", "Entire guesthouse", "Farm stay")
three_by_lga <- entire13[, .(n_listings = sum(property_type %in% three_types), n_scope_listings = .N,
                              share_of_scope = mean(property_type %in% three_types)), by = lga]
three_by_lga[, scope := "Cottage, guesthouse and farm stay within LGA, entire homes with 1-3 bedrooms"]
three_by_lga[, property_type := "Entire cottage / Entire guesthouse / Farm stay"]
three_by_lga[, standard_type := FALSE]
excluded <- rbindlist(list(type_counts, excluded_by_lga, three_by_lga), use.names = TRUE)
setcolorder(excluded, c("scope", "lga", "property_type", "standard_type", "n_listings",
                       "n_scope_listings", "share_of_scope"))
fwrite(excluded, "reports/tables/excluded_dwelling_types.csv")

# Compare composition before and after the whitelist under identical history,
# price and host-partition rules. Broad classes are held fixed across stages:
# apartment-like = rental unit, condo, serviced apartment or loft; other entire
# homes = every remaining entire-home type. Recompute n>=50 in each stage.
broad <- entire13[benchmark_host == FALSE & established_history == TRUE &
                  !is.na(price_num) & price_num >= cfg$minimum_price & price_num <= cfg$maximum_price]
broad[, broad_class := fifelse(property_type %in% c("Entire rental unit", "Entire condo",
                                                   "Entire serviced apartment", "Entire loft"),
                               "Apartment-like", "Other entire-home types")]
type_sensitivity <- rbindlist(lapply(c(FALSE, TRUE), function(after) {
  x <- if (after) broad[standard_type == TRUE] else broad
  ans <- x[, .(n_listings = .N, n_hosts = uniqueN(canonical_host_id),
                n_meeting_target = sum(reviews_365d >= REVIEW_TARGET),
                n_zero_reviews = sum(reviews_365d == 0),
                observed_target_rate = mean(reviews_365d >= REVIEW_TARGET),
                reviews_p75 = unname(quantile(reviews_365d, .75))), by = .(lga, broad_class, bedrooms)]
  ans[, stage := if (after) "After four-type whitelist" else "Before four-type whitelist"]
  ans[, eligible_n50 := n_listings >= MIN_LISTINGS]
  ans[eligible_n50 == TRUE, rank_observed_rate := frank(-observed_target_rate, ties.method = "min")]
  ans
}))
type_sensitivity[, review_target := REVIEW_TARGET]
type_sensitivity[, broad_class_definition := fifelse(broad_class == "Apartment-like",
  "Entire rental unit, condo, serviced apartment or loft", "Every other entire-home property type")]
type_sensitivity[, shared_scope := "Established history, price AUD30-1500, non-benchmark hosts; n>=50 recomputed by stage"]
setorder(type_sensitivity, stage, -observed_target_rate, lga, broad_class, bedrooms)
fwrite(type_sensitivity, "reports/tables/type_whitelist_sensitivity.csv")

# A paired composition check also holds LGA x bedrooms fixed without imposing
# a broad dwelling-class mapping. Both sides need at least 50 listings. These
# groups differ from the primary segments and are not a replacement ranking.
composition_stats <- function(x) x[, .(
  n_listings = .N, n_hosts = uniqueN(canonical_host_id),
  n_meeting_target = sum(reviews_365d >= REVIEW_TARGET),
  n_zero_reviews = sum(reviews_365d == 0),
  observed_target_rate = mean(reviews_365d >= REVIEW_TARGET),
  reviews_median = as.numeric(median(reviews_365d)),
  reviews_p75 = unname(quantile(reviews_365d, .75))
), by = .(lga, bedrooms)]
composition <- merge(composition_stats(broad), composition_stats(broad[standard_type == TRUE]),
                     by = c("lga", "bedrooms"), suffixes = c("_before", "_after"))
composition <- composition[n_listings_before >= MIN_LISTINGS & n_listings_after >= MIN_LISTINGS]
composition[, excluded_n := n_listings_before - n_listings_after]
composition[, rate_change_after_minus_before := observed_target_rate_after - observed_target_rate_before]
composition[, review_target := REVIEW_TARGET]
composition[, shared_scope := "LGA x bedrooms; established history, price AUD30-1500, non-benchmark hosts; both stages n>=50"]
composition[, interpretation := "Paired composition check across all dwelling types; not the primary class-specific ranking"]
setorder(composition, lga, bedrooms)
fwrite(composition, "reports/tables/type_whitelist_lga_bedrooms_comparison.csv")

# Hosts are sampled with replacement, bringing all of their listings along.
# Each replicate's denominator is its resulting listing count. Intervals are
# pointwise 90% percentile intervals, not confidence in a segment's rank.
cluster_rate_ci <- function(y, host, reps = BOOT_REPS) {
  h <- as.integer(factor(host))
  nh <- max(h)
  host_n <- tabulate(h, nbins = nh)
  host_yes <- tabulate(h[y], nbins = nh)
  draws <- replicate(reps, {
    w <- tabulate(sample.int(nh, nh, replace = TRUE), nbins = nh)
    sum(w * host_yes) / sum(w * host_n)
  })
  unname(quantile(draws, c(.05, .95), type = 7))
}
summarise_groups <- function(x, by_cols, scope_text) {
  ans <- x[, {
    q <- quantile(reviews_365d, c(.25, .50, .75, .90), type = 7, names = FALSE)
    ci <- cluster_rate_ci(meets_target, canonical_host_id)
    .(n_listings = .N, n_hosts = uniqueN(canonical_host_id),
      n_meeting_target = sum(meets_target), n_zero_reviews = sum(reviews_365d == 0),
      reviews_p25 = q[1], reviews_median = q[2], reviews_p75 = q[3], reviews_p90 = q[4],
      observed_target_rate = mean(meets_target), ci90_lo = ci[1], ci90_hi = ci[2])
  }, by = by_cols]
  ans[, scope := scope_text]
  ans[, review_target := REVIEW_TARGET]
  ans[, interval_method := "Host-cluster percentile bootstrap, 1000 draws, pointwise 90%"]
  ans
}

set.seed(BOOT_SEED)
ladder <- summarise_groups(main, SEGMENT_COLS, MAIN_SCOPE)
ladder[, rank_observed_rate := frank(-observed_target_rate, ties.method = "min")]
ladder[, rank_within_bedrooms := frank(-observed_target_rate, ties.method = "min"), by = bedrooms]
setorder(ladder, bedrooms, -observed_target_rate, lga, dwelling_class)
fwrite(ladder, "reports/tables/segment_ladder.csv")
city <- summarise_groups(main, c("dwelling_class", "bedrooms"),
                         paste("Final main cells pooled by class and bedrooms;", MAIN_SCOPE))
setorder(city, dwelling_class, bedrooms)
fwrite(city, "reports/tables/segment_ladder_bedroom_class_citywide.csv")
all_history_ladder <- summarise_groups(all_histories, SEGMENT_COLS, ALL_HISTORIES_SCOPE)
all_history_ladder[, rank_observed_rate := frank(-observed_target_rate, ties.method = "min")]
setorder(all_history_ladder, bedrooms, -observed_target_rate, lga, dwelling_class)
fwrite(all_history_ladder, "reports/tables/segment_ladder_all_histories_sensitivity.csv")
no_price_ladder <- summarise_groups(no_price, SEGMENT_COLS, NO_PRICE_SCOPE)
no_price_ladder[, rank_observed_rate := frank(-observed_target_rate, ties.method = "min")]
setorder(no_price_ladder, bedrooms, -observed_target_rate, lga, dwelling_class)
fwrite(no_price_ladder, "reports/tables/segment_ladder_no_price_sensitivity.csv")
sensitivity <- merge(
  ladder[, c(SEGMENT_COLS, "n_listings", "observed_target_rate"), with = FALSE],
  all_history_ladder[, c(SEGMENT_COLS, "n_listings", "observed_target_rate"), with = FALSE],
  by = SEGMENT_COLS, all = TRUE, suffixes = c("_established_main", "_all_histories"))
sensitivity[, rate_difference := observed_target_rate_established_main - observed_target_rate_all_histories]
sensitivity[, established_history_days := HISTORY_DAYS]
sensitivity[, established_definition := "first_review <= each listing last_scraped - established_history_days"]
sensitivity[, review_window_days := REVIEW_WINDOW_DAYS]
sensitivity[, review_target := REVIEW_TARGET]
fwrite(sensitivity, "reports/tables/review_exposure_sensitivity.csv")

# All common cutoffs come from the benchmark-host reference distribution,
# restricted to the primary eligible cells. They remain fixed for all analysis
# segments and sensitivities. This revised separation follows earlier exploration.
benchmark_values <- data.table(
  benchmark = c("Benchmark-development P50", "Common upper-quartile target", "Benchmark-development P90"),
  raw_quantile = unname(quantile(benchmark$reviews_365d, c(.50, .75, .90), type = 7)))
benchmark_values[, review_target := ceiling(raw_quantile)]
map_benchmarks <- function(x, cols = character()) rbindlist(lapply(seq_len(nrow(benchmark_values)), function(i) {
  cut <- benchmark_values$review_target[i]
  x[, .(benchmark = benchmark_values$benchmark[i], raw_quantile = benchmark_values$raw_quantile[i],
        review_target = cut, n_listings = .N, n_below = sum(reviews_365d < cut),
        n_at_threshold = sum(reviews_365d == cut), n_at_least = sum(reviews_365d >= cut),
        share_below = mean(reviews_365d < cut), share_at_least = mean(reviews_365d >= cut),
        reference_scope = "Benchmark-development hosts, primary eligibility and final main cells"), by = cols]
}))
fwrite(map_benchmarks(main, SEGMENT_COLS), "reports/tables/benchmark_map_by_segment.csv")
fwrite(map_benchmarks(main), "reports/tables/benchmark_map_citywide.csv")
MET_LABEL <- sprintf("At least %d reviews", REVIEW_TARGET)
BELOW_LABEL <- sprintf("Fewer than %d reviews", REVIEW_TARGET)

# Pooled property-attribute contrasts describe composition, not causal effects.
safe_median <- function(x) if (all(is.na(x))) NA_real_ else as.numeric(median(x, na.rm = TRUE))
safe_share <- function(x) if (all(is.na(x))) NA_real_ else mean(x, na.rm = TRUE)
profile <- main[, .(
  n_listings = .N,
  median_accommodates = safe_median(accommodates),
  median_beds = safe_median(beds),
  median_bathrooms = safe_median(bathrooms_num),
  median_amenities = safe_median(n_amenities),
  apartment_share = mean(dwelling_class == "Apartment/unit"),
  one_bedroom_share = mean(bedrooms == 1),
  two_bedroom_share = mean(bedrooms == 2),
  three_bedroom_share = mean(bedrooms == 3),
  wifi_share = safe_share(has_wifi), pool_share = safe_share(has_pool),
  aircon_share = safe_share(has_aircon), free_parking_share = safe_share(has_free_parking),
  n_missing_beds = sum(is.na(beds)), n_missing_bathrooms = sum(is.na(bathrooms_num))
), by = .(group = fifelse(meets_target, MET_LABEL, BELOW_LABEL))]
profile[, scope := MAIN_SCOPE]
setorder(profile, group)
fwrite(profile, "reports/tables/tier_profile.csv")

theme_set(theme_minimal(base_size = 11))
pal <- c("Apartment/unit" = "#236A9F", "House/townhouse" = "#327553")
plot_dt <- copy(ladder)
plot_dt[, label := paste(lga, dwelling_class, sep = " | ")]
plot_dt[, label_key := paste(label, bedrooms, sep = "___")]
setorder(plot_dt, bedrooms, observed_target_rate, lga, dwelling_class)
plot_dt[, label_key := factor(label_key, levels = unique(label_key))]
plot_dt[, bedroom_group := factor(paste0(bedrooms, " bedroom"), levels = paste0(1:3, " bedroom"))]
pooled_rate <- mean(main$meets_target)
p16 <- ggplot(plot_dt, aes(y = label_key, colour = dwelling_class)) +
  geom_vline(xintercept = pooled_rate, linetype = "dashed", colour = "grey50", linewidth = .4) +
  geom_segment(aes(x = ci90_lo, xend = ci90_hi, yend = label_key), linewidth = .7) +
  geom_point(aes(x = observed_target_rate, size = n_listings)) +
  facet_wrap(~bedroom_group, ncol = 1, scales = "free_y", space = "free_y") +
  scale_y_discrete(labels = function(x) sub("___.*$", "", x)) +
  scale_x_continuous(labels = label_percent(accuracy = 1), limits = c(0, NA),
                     expand = expansion(mult = c(.01, .03))) +
  scale_colour_manual(values = pal, name = NULL) +
  scale_size_continuous(range = c(2, 5), breaks = c(50, 250, 1000), labels = comma,
                        name = "Eligible listings") +
  guides(colour = guide_legend(order = 1, override.aes = list(size = 3)),
         size = guide_legend(order = 2)) +
  labs(title = "Review activity across established residential segments",
       subtitle = sprintf("Common upper-quartile target: at least %d reviews | %s analysis listings in %d segments",
                          REVIEW_TARGET, comma(nrow(main)), nrow(ladder)),
       x = sprintf("Observed proportion with at least %d reviews", REVIEW_TARGET), y = NULL,
       caption = sprintf(paste0("Dots: observed proportions. Lines: pointwise 90%% host-cluster bootstrap intervals (1,000 draws).\n",
                                "Dashed line: pooled rate, %.2f%%. Each segment has at least 50 eligible listings; zero-review listings are retained.\n",
                                "First review at least %d days before each listing's scrape date. Benchmark hosts supply the cutoff and are excluded."),
                         100 * pooled_rate, HISTORY_DAYS)) +
  theme(legend.position = "bottom", panel.grid.major.y = element_blank(),
        panel.grid.minor = element_blank(), strip.text = element_text(face = "bold", hjust = 0),
        plot.title.position = "plot", plot.caption = element_text(hjust = 0, size = 9))
ggsave("reports/figures/16_segment_ladder.png", p16, width = 11.5, height = 11.5, dpi = 150)

profile_plot <- melt(profile[, .(group, `Guest capacity (median)` = median_accommodates,
                                  `Beds (median)` = median_beds,
                                  `Bathrooms (median)` = median_bathrooms,
                                  `Amenities (median)` = median_amenities,
                                  `Free parking (%)` = free_parking_share * 100)],
                      id.vars = "group", variable.name = "attribute", value.name = "value")
profile_plot[, group := factor(group, levels = c(MET_LABEL, BELOW_LABEL))]
profile_plot[, value_label := fifelse(attribute == "Free parking (%)", sprintf("%.1f%%", value),
                                      sprintf("%g", value))]
p17 <- ggplot(profile_plot, aes(x = group, y = value, fill = group)) +
  geom_col(width = .65) + geom_text(aes(label = value_label), vjust = -.4, size = 3.5) +
  facet_wrap(~attribute, nrow = 1, scales = "free_y") +
  scale_fill_manual(values = setNames(c("#236A9F", "#ADC4D5"), c(MET_LABEL, BELOW_LABEL)), name = NULL) +
  scale_x_discrete(labels = setNames(c(sprintf("%d or more", REVIEW_TARGET), sprintf("Below %d", REVIEW_TARGET)), c(MET_LABEL, BELOW_LABEL))) +
  scale_y_continuous(expand = expansion(mult = c(0, .18))) +
  labs(title = "Listing attributes by recent review activity",
       subtitle = sprintf("Common benchmark-derived target: at least %d reviews | %s meet it; %s fall below it",
                          REVIEW_TARGET, comma(sum(main$meets_target)), comma(sum(!main$meets_target))),
       x = sprintf("Guest reviews in the %d days ending on each listing's scrape date", REVIEW_WINDOW_DAYS), y = NULL,
       caption = "Pooled, unadjusted attributes in the established analysis cohort; benchmark hosts excluded. Available values are used for each attribute.\nDifferences describe composition and are not causal effects. The common cutoff comes from the separate benchmark reference.") +
  theme(legend.position = "none", panel.grid.major.x = element_blank(),
        panel.grid.minor = element_blank(), strip.text = element_text(face = "bold", size = 10),
        plot.title.position = "plot", plot.caption = element_text(hjust = 0, size = 9))
ggsave("reports/figures/17_top_quartile_profile.png", p17, width = 12.5, height = 4.5, dpi = 150)


stopifnot(all(ladder$n_listings >= MIN_LISTINGS), sum(ladder$n_listings) == nrow(main),
          sum(ladder$n_meeting_target) == sum(main$meets_target),
          sum(ladder$n_zero_reviews) == sum(main$reviews_365d == 0),
          all(ladder$ci90_lo >= 0 & ladder$ci90_hi <= 1),
          !any(main$benchmark_host), !any(all_histories$benchmark_host), !any(no_price$benchmark_host))
obsolete <- "reports/tables/segment_ladder_mature_sensitivity.csv"
if (file.exists(obsolete)) unlink(obsolete)
cat(sprintf("Benchmark reference: %s listings, %s hosts; P75 %.3f; common integer target %d.\n",
            comma(nrow(benchmark)), comma(uniqueN(benchmark$canonical_host_id)), benchmark_p75, REVIEW_TARGET))
cat(sprintf("Established analysis: %s listings, %s hosts, %d segments; %s meet target (%.4f%%); %s zero reviews.\n",
            comma(nrow(main)), comma(uniqueN(main$canonical_host_id)), nrow(ladder),
            comma(sum(main$meets_target)), 100 * mean(main$meets_target),
            comma(sum(main$reviews_365d == 0))))
cat(sprintf("All-history sensitivity: %s listings in %d eligible segments, %.4f%% meet the same target.\n",
            comma(nrow(all_histories)), nrow(all_history_ladder), 100 * mean(all_histories$meets_target)))
