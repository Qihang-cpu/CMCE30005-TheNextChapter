# CMCE30005: descriptive comparison of recent guest-review activity.
# Run from the repository root after 01_data_cleaning.R.
# Input: school-supplied listings in data/processed/listings_clean.rds.
# Segments are LGA x dwelling class x bedroom count, with at least 50
# eligible listings. Zero-review listings are retained. Predictive validation
# is a separate step; this script reports observed associations.

library(data.table)
library(ggplot2)
library(scales)

dir.create("reports/tables", showWarnings = FALSE, recursive = TRUE)
dir.create("reports/figures", showWarnings = FALSE, recursive = TRUE)

MIN_LISTINGS <- 50L
REVIEW_THRESHOLD <- 22L
BOOT_REPS <- 1000L
BOOT_SEED <- 30005L
FIRST_REVIEW_CUTOFF <- as.Date("2025-06-01")
APARTMENT_TYPES <- c("Entire rental unit", "Entire condo")
HOUSE_TYPES <- c("Entire home", "Entire townhouse")
SEGMENT_COLS <- c("lga", "dwelling_class", "bedrooms")
MAIN_SCOPE <- "Standard entire homes, 1-3 bedrooms, price AUD30-1500, segment n>=50"
MATURE_SCOPE <- paste0(MAIN_SCOPE, "; first review on/before 2025-06-01")

listings <- readRDS("data/processed/listings_clean.rds")
required <- c("id", "host_id", "room_type", "property_type", "bedrooms",
              "neighbourhood_cleansed", "price_num", "number_of_reviews_ltm",
              "first_review", "accommodates", "beds", "bathrooms_num",
              "n_amenities", "has_wifi", "has_pool", "has_aircon", "has_free_parking")
stopifnot(all(required %in% names(listings)), !anyDuplicated(listings$id))

entire13 <- copy(listings[room_type == "Entire home/apt" & bedrooms %in% 1:3])
entire13[, lga := fifelse(neighbourhood_cleansed == "Moreland", "Merri-bek",
                         neighbourhood_cleansed)]
entire13[, dwelling_class := fcase(
  property_type %in% APARTMENT_TYPES, "Apartment/unit",
  property_type %in% HOUSE_TYPES, "House/townhouse", default = NA_character_)]
entire13[, standard_type := !is.na(dwelling_class)]
# The whitelist defines comparable residential types, not availability to
# lease or permission to sublet.
standard <- entire13[standard_type == TRUE]
priced <- standard[!is.na(price_num) & price_num >= 30 & price_num <= 1500]
stopifnot(!anyNA(priced$number_of_reviews_ltm), !anyNA(priced$host_id),
          !anyNA(priced$lga), all(priced$number_of_reviews_ltm >= 0))

eligible_cohort <- function(x) {
  cells <- x[, .(n_listings = .N), by = SEGMENT_COLS][n_listings >= MIN_LISTINGS]
  x[cells[, ..SEGMENT_COLS], on = SEGMENT_COLS, nomatch = 0]
}
main <- eligible_cohort(priced)
main[, meets_22 := number_of_reviews_ltm >= REVIEW_THRESHOLD]

# First-review history does not establish launch date or continuous operation.
# This sensitivity cohort reapplies n>=50 after its date restriction and
# includes listings with zero reviews in the preceding 12 months.
mature_before_size <- priced[!is.na(first_review) & first_review <= FIRST_REVIEW_CUTOFF]
mature <- eligible_cohort(mature_before_size)
mature[, meets_22 := number_of_reviews_ltm >= REVIEW_THRESHOLD]

scope_row <- function(x, stage) data.table(
  stage = stage, n_listings = nrow(x), n_hosts = uniqueN(x$host_id),
  n_segments = uniqueN(x[, ..SEGMENT_COLS]),
  n_zero_reviews = sum(x$number_of_reviews_ltm == 0),
  n_at_least_22 = sum(x$number_of_reviews_ltm >= REVIEW_THRESHOLD),
  observed_rate_22 = mean(x$number_of_reviews_ltm >= REVIEW_THRESHOLD),
  reviews_median = median(x$number_of_reviews_ltm),
  reviews_p75 = unname(quantile(x$number_of_reviews_ltm, .75, type = 7)))
scope <- rbindlist(list(
  scope_row(entire13, "Entire homes with 1-3 bedrooms"),
  scope_row(standard, "Four standard dwelling types"),
  scope_row(priced, "Standard types with a price from AUD30 to AUD1500"),
  scope_row(main, "Main cohort after segment n>=50"),
  scope_row(mature_before_size, "Earlier first review, before segment size rule"),
  scope_row(mature, "Earlier first review, after segment n>=50")))
fwrite(scope, "reports/tables/review_scope_summary.csv")

type_counts <- entire13[, .(n_listings = .N), by = .(property_type, standard_type)]
type_counts[, scope := "All entire homes with 1-3 bedrooms"]
type_counts[, lga := "All LGAs"]
type_counts[, share_of_scope := n_listings / nrow(entire13)]
excluded_by_lga <- entire13[, .(n_listings = sum(!standard_type),
                                 share_of_scope = mean(!standard_type)), by = lga]
excluded_by_lga[, scope := "Excluded types within LGA"]
excluded_by_lga[, property_type := "All excluded types"]
excluded_by_lga[, standard_type := FALSE]
excluded <- rbindlist(list(type_counts, excluded_by_lga), use.names = TRUE)
setcolorder(excluded, c("scope", "lga", "property_type", "standard_type", "n_listings", "share_of_scope"))
fwrite(excluded, "reports/tables/excluded_dwelling_types.csv")

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
    q <- quantile(number_of_reviews_ltm, c(.25, .50, .75, .90), type = 7, names = FALSE)
    ci <- cluster_rate_ci(meets_22, host_id)
    .(n_listings = .N, n_hosts = uniqueN(host_id),
      n_at_least_22 = sum(meets_22), n_zero_reviews = sum(number_of_reviews_ltm == 0),
      reviews_p25 = q[1], reviews_median = q[2], reviews_p75 = q[3], reviews_p90 = q[4],
      observed_rate_22 = mean(meets_22), ci90_lo = ci[1], ci90_hi = ci[2])
  }, by = by_cols]
  ans[, scope := scope_text]
  ans[, review_threshold := REVIEW_THRESHOLD]
  ans[, interval_method := "Host-cluster percentile bootstrap, 1000 draws, pointwise 90%"]
  ans
}

set.seed(BOOT_SEED)
ladder <- summarise_groups(main, SEGMENT_COLS, MAIN_SCOPE)
ladder[, rank_observed_rate := frank(-observed_rate_22, ties.method = "min")]
ladder[, rank_within_bedrooms := frank(-observed_rate_22, ties.method = "min"), by = bedrooms]
setorder(ladder, bedrooms, -observed_rate_22, lga, dwelling_class)
fwrite(ladder, "reports/tables/segment_ladder.csv")

city <- summarise_groups(main, c("dwelling_class", "bedrooms"),
                         paste("Main eligible segments pooled by class and bedrooms;", MAIN_SCOPE))
setorder(city, dwelling_class, bedrooms)
fwrite(city, "reports/tables/segment_ladder_bedroom_class_citywide.csv")
mature_ladder <- summarise_groups(mature, SEGMENT_COLS, MATURE_SCOPE)
mature_ladder[, rank_observed_rate := frank(-observed_rate_22, ties.method = "min")]
setorder(mature_ladder, bedrooms, -observed_rate_22, lga, dwelling_class)
fwrite(mature_ladder, "reports/tables/segment_ladder_mature_sensitivity.csv")
sensitivity <- merge(
  ladder[, c(SEGMENT_COLS, "n_listings", "observed_rate_22"), with = FALSE],
  mature_ladder[, c(SEGMENT_COLS, "n_listings", "observed_rate_22"), with = FALSE],
  by = SEGMENT_COLS, all = TRUE, suffixes = c("_main", "_earlier_first_review"))
sensitivity[, rate_difference := observed_rate_22_earlier_first_review - observed_rate_22_main]
sensitivity[, first_review_cutoff := as.character(FIRST_REVIEW_CUTOFF)]
fwrite(sensitivity, "reports/tables/review_exposure_sensitivity.csv")

# Internal mapping: fixed 22 equals this exploratory cohort's empirical P75.
# It is not an external standard, profitability cutoff or training-fold
# estimate. Ties make the observed target share exceed exactly 25%.
benchmark_values <- data.table(
  benchmark = c("Main-cohort P50", "Fixed common target; main-cohort P75", "Main-cohort P90"),
  review_threshold = c(unname(quantile(main$number_of_reviews_ltm, .5)), REVIEW_THRESHOLD,
                       unname(quantile(main$number_of_reviews_ltm, .9))))
map_benchmarks <- function(x, cols = character()) rbindlist(lapply(seq_len(nrow(benchmark_values)), function(i) {
  cut <- benchmark_values$review_threshold[i]
  x[, .(benchmark = benchmark_values$benchmark[i], review_threshold = cut,
        n_listings = .N, n_below = sum(number_of_reviews_ltm < cut),
        n_at_threshold = sum(number_of_reviews_ltm == cut),
        n_at_least = sum(number_of_reviews_ltm >= cut),
        share_below = mean(number_of_reviews_ltm < cut),
        share_at_least = mean(number_of_reviews_ltm >= cut),
        reference_scope = "Fixed thresholds from the pooled main cohort"), by = cols]
}))
fwrite(map_benchmarks(main, SEGMENT_COLS), "reports/tables/benchmark_map_by_segment.csv")
fwrite(map_benchmarks(main), "reports/tables/benchmark_map_citywide.csv")

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
), by = .(group = fifelse(meets_22, "At least 22 reviews", "Fewer than 22 reviews"))]
profile[, scope := MAIN_SCOPE]
setorder(profile, group)
fwrite(profile, "reports/tables/tier_profile.csv")

theme_set(theme_minimal(base_size = 11))
pal <- c("Apartment/unit" = "#236A9F", "House/townhouse" = "#327553")
plot_dt <- copy(ladder)
plot_dt[, label := paste(lga, dwelling_class, sep = " | ")]
plot_dt[, label_key := paste(label, bedrooms, sep = "___")]
setorder(plot_dt, bedrooms, observed_rate_22, lga, dwelling_class)
plot_dt[, label_key := factor(label_key, levels = unique(label_key))]
plot_dt[, bedroom_group := factor(paste0(bedrooms, " bedroom"), levels = paste0(1:3, " bedroom"))]
pooled_rate <- mean(main$meets_22)
p16 <- ggplot(plot_dt, aes(y = label_key, colour = dwelling_class)) +
  geom_vline(xintercept = pooled_rate, linetype = "dashed", colour = "grey50", linewidth = .4) +
  geom_segment(aes(x = ci90_lo, xend = ci90_hi, yend = label_key), linewidth = .7) +
  geom_point(aes(x = observed_rate_22, size = n_listings)) +
  facet_wrap(~bedroom_group, ncol = 1, scales = "free_y", space = "free_y") +
  scale_y_discrete(labels = function(x) sub("___.*$", "", x)) +
  scale_x_continuous(labels = label_percent(accuracy = 1), limits = c(0, NA),
                     expand = expansion(mult = c(.01, .03))) +
  scale_colour_manual(values = pal, name = NULL) +
  scale_size_continuous(range = c(2, 5), breaks = c(50, 250, 1000), labels = comma,
                        name = "Eligible listings") +
  guides(colour = guide_legend(order = 1, override.aes = list(size = 3)),
         size = guide_legend(order = 2)) +
  labs(title = "Observed review activity across comparable residential segments",
       subtitle = sprintf("At least 22 guest reviews in the preceding 12 months | %s listings in %d segments",
                          comma(nrow(main)), nrow(ladder)),
       x = "Observed proportion with at least 22 reviews", y = NULL,
       caption = sprintf(paste0("Dots: observed proportions. Lines: pointwise 90%% host-cluster bootstrap intervals (1,000 draws).\n",
                                "Dashed line: pooled rate, %.2f%%. Each segment has at least 50 eligible listings; zero-review listings are retained.\n",
                                "School-supplied June 2026 snapshot. Descriptive results do not establish future performance or profit."),
                         100 * pooled_rate)) +
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
profile_plot[, group := factor(group, levels = c("At least 22 reviews", "Fewer than 22 reviews"))]
profile_plot[, value_label := fifelse(attribute == "Free parking (%)", sprintf("%.1f%%", value),
                                      sprintf("%g", value))]
p17 <- ggplot(profile_plot, aes(x = group, y = value, fill = group)) +
  geom_col(width = .65) + geom_text(aes(label = value_label), vjust = -.4, size = 3.5) +
  facet_wrap(~attribute, nrow = 1, scales = "free_y") +
  scale_fill_manual(values = c("At least 22 reviews" = "#236A9F", "Fewer than 22 reviews" = "#ADC4D5"), name = NULL) +
  scale_x_discrete(labels = c("At least 22 reviews" = "22 or more", "Fewer than 22 reviews" = "Below 22")) +
  scale_y_continuous(expand = expansion(mult = c(0, .18))) +
  labs(title = "Listing attributes by recent review activity",
       subtitle = sprintf("Common target: at least 22 reviews | %s meet the target; %s fall below it",
                          comma(sum(main$meets_22)), comma(sum(!main$meets_22))),
       x = "Guest reviews in the preceding 12 months", y = NULL,
       caption = "Pooled, unadjusted attribute comparisons in the main cohort. Available values are used for each attribute.\nDifferences describe composition and are not causal effects. No revenue estimates or review-derived attributes enter these profiles.") +
  theme(legend.position = "none", panel.grid.major.x = element_blank(),
        panel.grid.minor = element_blank(), strip.text = element_text(face = "bold", size = 10),
        plot.title.position = "plot", plot.caption = element_text(hjust = 0, size = 9))
ggsave("reports/figures/17_top_quartile_profile.png", p17, width = 12.5, height = 4.5, dpi = 150)

stopifnot(all(ladder$n_listings >= MIN_LISTINGS), sum(ladder$n_listings) == nrow(main),
          sum(ladder$n_at_least_22) == sum(main$meets_22),
          sum(ladder$n_zero_reviews) == sum(main$number_of_reviews_ltm == 0),
          all(ladder$ci90_lo >= 0 & ladder$ci90_hi <= 1),
          all(mature_ladder$n_listings >= MIN_LISTINGS))
cat(sprintf("Main cohort: %s listings, %s hosts, %d segments; %s have at least 22 reviews (%.4f%%).\n",
            comma(nrow(main)), comma(uniqueN(main$host_id)), nrow(ladder),
            comma(sum(main$meets_22)), 100 * pooled_rate))
cat(sprintf("Review P50/P75/P90: %s; zero reviews: %s.\n",
            paste(quantile(main$number_of_reviews_ltm, c(.5, .75, .9)), collapse = "/"),
            comma(sum(main$number_of_reviews_ltm == 0))))
cat(sprintf("Earlier-first-review sensitivity: %s listings in %d eligible segments, %.4f%% meet 22.\n",
            comma(nrow(mature)), nrow(mature_ladder), 100 * mean(mature$meets_22)))
