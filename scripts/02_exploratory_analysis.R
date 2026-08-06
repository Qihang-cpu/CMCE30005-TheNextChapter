# ============================================================
# CMCE30005 Business Analytics Challenge
# Script: 02_exploratory_analysis.R
# Purpose: Describe supply, price, demand seasonality and the revenue
#          segments of the Melbourne Airbnb market
# Author: TheNextChapter (Group 2)
# Date: 6 August 2026
# ============================================================
#
# Input : data/processed/*.rds (from 01_data_cleaning.R)
# Output: reports/figures/*.png, reports/tables/*.csv
# ============================================================

library(data.table)
library(ggplot2)
library(scales)

dir.create("reports/figures", showWarnings = FALSE, recursive = TRUE)
dir.create("reports/tables", showWarnings = FALSE, recursive = TRUE)

listings <- readRDS("data/processed/listings_clean.rds")
calendar_monthly <- readRDS("data/processed/calendar_monthly.rds")
reviews_monthly <- readRDS("data/processed/reviews_monthly.rds")

priced <- listings[priced == TRUE]

theme_set(theme_minimal(base_size = 12))

# ---- 1. Price distribution ---------------------------------------------------

p <- ggplot(priced, aes(price_num)) +
  geom_histogram(bins = 60, fill = "steelblue", colour = "white") +
  scale_x_log10(labels = dollar) +
  labs(title = "Nightly price distribution (log scale)",
       subtitle = sprintf("n = %s priced listings, $30-$1,500", comma(nrow(priced))),
       x = "Price per night (AUD)", y = "Listings")
ggsave("reports/figures/01_price_distribution.png", p, width = 8, height = 5, dpi = 150)

# ---- 2. Price and supply by local government area ---------------------------

area_stats <- priced[, .(n = .N,
                         median_price = median(price_num),
                         median_occ = median(estimated_occupancy_l365d, na.rm = TRUE),
                         median_rev = median(estimated_revenue_l365d, na.rm = TRUE)),
                     by = neighbourhood_cleansed][order(-n)]
fwrite(area_stats, "reports/tables/area_summary.csv")

top_areas <- area_stats[1:15]
top_areas[, neighbourhood_cleansed := factor(neighbourhood_cleansed,
                                             levels = rev(neighbourhood_cleansed))]
p <- ggplot(top_areas, aes(median_price, neighbourhood_cleansed)) +
  geom_col(fill = "steelblue") +
  geom_text(aes(label = dollar(median_price)), hjust = -0.1, size = 3) +
  scale_x_continuous(labels = dollar, expand = expansion(mult = c(0, 0.15))) +
  labs(title = "Median nightly price by local government area",
       subtitle = "Top 15 LGAs by listing count",
       x = "Median price (AUD)", y = NULL)
ggsave("reports/figures/02_price_by_area.png", p, width = 8, height = 6, dpi = 150)

# ---- 3. Price by capacity and room type -------------------------------------

p <- ggplot(priced[accommodates %between% c(1, 8)],
            aes(factor(accommodates), price_num, fill = room_type)) +
  geom_boxplot(outlier.alpha = 0.1) +
  scale_y_log10(labels = dollar) +
  labs(title = "Price by capacity and room type",
       x = "Accommodates (guests)", y = "Price per night (log scale)", fill = NULL) +
  theme(legend.position = "bottom")
ggsave("reports/figures/03_price_capacity_roomtype.png", p, width = 9, height = 6, dpi = 150)

# ---- 4. Demand seasonality ---------------------------------------------------

# Review volume is used as the demand proxy. The forward calendar cannot be used
# for this: most hosts have not opened distant dates, so "unavailable" does not
# mean "booked".
rm3 <- reviews_monthly[month >= "2023-07" & month <= "2026-06"]
rm3[, date := as.Date(paste0(month, "-01"))]

p <- ggplot(rm3, aes(date, N)) +
  geom_line(colour = "steelblue", linewidth = 0.8) +
  geom_point(size = 1.2) +
  scale_x_date(date_breaks = "3 months", date_labels = "%b %y") +
  scale_y_continuous(labels = comma) +
  labs(title = "Monthly review volume (demand proxy), Jul 2023 - Jun 2026",
       x = NULL, y = "Reviews posted") +
  theme(axis.text.x = element_text(angle = 45, hjust = 1))
ggsave("reports/figures/04_demand_seasonality.png", p, width = 9, height = 5, dpi = 150)

# seasonality index: mean volume of each calendar month across three full years
rm3[, m := substr(month, 6, 7)]
rm3[, yr := substr(month, 1, 4)]
seas <- rm3[, .(n = sum(N)), by = .(m, yr)][, .(idx = mean(n)), by = m][order(m)]
seas[, idx := idx / mean(idx)]
fwrite(seas, "reports/tables/seasonality_index.csv")

# ---- 5. Price against occupancy ---------------------------------------------

rev_data <- priced[!is.na(estimated_occupancy_l365d) & estimated_occupancy_l365d > 0 &
                   room_type == "Entire home/apt" & number_of_reviews_ltm >= 3]
p <- ggplot(rev_data, aes(price_num, estimated_occupancy_l365d / 365)) +
  geom_point(alpha = 0.08, colour = "steelblue") +
  geom_smooth(method = "gam", colour = "firebrick") +
  scale_x_log10(labels = dollar) +
  scale_y_continuous(labels = percent) +
  labs(title = "Price vs estimated occupancy - entire homes with recent activity",
       subtitle = "Each point is a listing; occupancy estimated from trailing-365d bookings",
       x = "Price per night (log scale)", y = "Estimated occupancy")
ggsave("reports/figures/05_price_vs_occupancy.png", p, width = 8, height = 6, dpi = 150)

# ---- 6. Revenue by segment ---------------------------------------------------

seg <- priced[room_type %in% c("Entire home/apt", "Private room") &
              !is.na(estimated_revenue_l365d),
              .(n = .N,
                median_price = median(price_num),
                median_revenue = median(estimated_revenue_l365d),
                median_occ_pct = round(100 * median(estimated_occupancy_l365d / 365,
                                                    na.rm = TRUE), 1)),
              by = .(neighbourhood_cleansed, room_type,
                     size = fifelse(accommodates <= 2, "1-2 guests",
                            fifelse(accommodates <= 4, "3-4 guests", "5+ guests")))]
seg <- seg[n >= 30][order(-median_revenue)]
fwrite(seg, "reports/tables/segment_revenue.csv")

cat("Top revenue segments (n >= 30 listings):\n")
print(head(seg, 12))

# ---- 7. Superhost comparison -------------------------------------------------

sh <- priced[, .(n = .N,
                 median_price = median(price_num),
                 median_rating = median(review_scores_rating, na.rm = TRUE),
                 median_revenue = median(estimated_revenue_l365d, na.rm = TRUE),
                 median_occ = median(estimated_occupancy_l365d, na.rm = TRUE)),
             by = host_is_superhost]
print(sh)
fwrite(sh, "reports/tables/superhost_comparison.csv")

cat("Figures written to reports/figures/, tables to reports/tables/\n")
