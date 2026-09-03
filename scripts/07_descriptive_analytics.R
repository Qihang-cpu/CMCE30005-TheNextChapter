# ============================================================
# CMCE30005 Business Analytics Challenge
# Script: 07_descriptive_analytics.R
# Purpose: Week 5 workshop - descriptive analytics on the project dataset.
#          Summarises, aggregates and visualises the cleaned Melbourne
#          snapshot to establish what the data looks like before modelling.
# Author: TheNextChapter (Group 2)
# Date: 3 September 2026
# ============================================================
#
# Input  : data/processed/listings_clean.rds        (01_data_cleaning.R)
# Output : reports/tables/desc_numeric_summary.csv
#          reports/tables/desc_categorical_summary.csv
#          reports/tables/desc_by_room_type.csv
#          reports/tables/desc_by_lga.csv
#          reports/tables/desc_by_superhost.csv
#          reports/figures/11_price_distribution_raw_log.png
#          reports/figures/12_categorical_composition.png
#          reports/figures/13_price_by_lga_roomtype.png
#          reports/figures/14_numeric_distributions.png
#          reports/figures/15_price_vs_reviews.png
#
# Workshop tasks addressed, in order:
#   1. Identify key numerical variables of interest
#   2. Identify key categorical (factor) variables of interest
#   3. Generate summary statistics for key variables
#   4. Generate summary statistics by grouping variables
#   5. Create histograms, bar charts, box plots and other visualisations
#
# Sample convention: descriptive statistics that involve price use the project
# "priced" sample (a nightly rate present and within $30-$1,500, see
# reports/methodology.md). Counts and composition use the full snapshot, so
# the two are reported side by side rather than silently mixed.
# ============================================================

library(dplyr)
library(skimr)
library(ggplot2)
library(scales)
library(tidyr)
library(patchwork)

dir.create("reports/figures", showWarnings = FALSE, recursive = TRUE)
dir.create("reports/tables",  showWarnings = FALSE, recursive = TRUE)

theme_set(theme_minimal(base_size = 12))
PAL <- c("Entire home/apt" = "#0C6DCD", "Private room" = "#F59E0B",
         "Shared room" = "#64748B", "Hotel room" = "#C0504D")

listings <- readRDS("data/processed/listings_clean.rds") |> as_tibble()

# host_is_superhost arrives as the character flags "t"/"f"
df <- listings |>
  mutate(host_is_superhost = case_when(host_is_superhost == "t" ~ TRUE,
                                       host_is_superhost == "f" ~ FALSE,
                                       TRUE ~ NA),
         room_type = factor(room_type),
         lga       = factor(neighbourhood_cleansed))

priced_sample <- df |> filter(priced)

cat(sprintf("Full snapshot: %s listings | priced sample: %s listings\n",
            comma(nrow(df)), comma(nrow(priced_sample))))

# ---- Task 1: key numerical variables ----------------------------------------
# Chosen because each maps to a decision in the business problem: what the
# property is (capacity, bedrooms, baths, amenities), what it charges
# (price, price per person), how much trade it does (reviews, occupancy,
# revenue), and how guests rate it.
num_vars <- c("price_num", "price_per_person", "accommodates", "bedrooms",
              "bathrooms_num", "n_amenities", "minimum_nights",
              "availability_365", "number_of_reviews", "number_of_reviews_ltm",
              "reviews_per_month", "review_scores_rating",
              "review_scores_location", "estimated_occupancy_l365d",
              "estimated_revenue_l365d", "host_tenure_years")

# ---- Task 2: key categorical variables --------------------------------------
cat_vars <- c("room_type", "neighbourhood_cleansed", "host_is_superhost",
              "shared_bath", "min_nights_grp", "has_free_parking",
              "has_aircon", "has_pool")

# ---- Task 3: summary statistics for key variables ---------------------------
cat("\n--- skim(): numeric variables ---\n")
print(skim(df, all_of(num_vars)))

num_summary <- df |>
  select(all_of(num_vars)) |>
  pivot_longer(everything(), names_to = "variable", values_to = "value") |>
  group_by(variable) |>
  summarise(n            = sum(!is.na(value)),
            n_missing    = sum(is.na(value)),
            complete_rate = round(mean(!is.na(value)), 3),
            mean   = round(mean(value, na.rm = TRUE), 2),
            sd     = round(sd(value, na.rm = TRUE), 2),
            min    = round(min(value, na.rm = TRUE), 2),
            p25    = round(quantile(value, .25, na.rm = TRUE), 2),
            median = round(median(value, na.rm = TRUE), 2),
            p75    = round(quantile(value, .75, na.rm = TRUE), 2),
            max    = round(max(value, na.rm = TRUE), 2),
            .groups = "drop") |>
  arrange(match(variable, num_vars))

write.csv(num_summary, "reports/tables/desc_numeric_summary.csv", row.names = FALSE)
cat("\n--- Numeric summary ---\n"); print(as.data.frame(num_summary))

cat_summary <- df |>
  select(all_of(cat_vars)) |>
  mutate(across(everything(), as.character)) |>
  pivot_longer(everything(), names_to = "variable", values_to = "level") |>
  count(variable, level, name = "n") |>
  group_by(variable) |>
  mutate(pct = round(100 * n / sum(n), 1)) |>
  arrange(variable, desc(n), .by_group = TRUE) |>
  ungroup()

write.csv(cat_summary, "reports/tables/desc_categorical_summary.csv", row.names = FALSE)
cat("\n--- Categorical levels (room_type) ---\n")
print(as.data.frame(filter(cat_summary, variable == "room_type")))

# ---- Task 4: summary statistics by grouping variables -----------------------
by_room <- priced_sample |>
  group_by(room_type) |>
  summarise(n              = n(),
            pct            = round(100 * n() / nrow(priced_sample), 1),
            median_price   = round(median(price_num, na.rm = TRUE), 2),
            mean_price     = round(mean(price_num, na.rm = TRUE)),
            sd_price       = round(sd(price_num, na.rm = TRUE)),
            median_price_pp = round(median(price_per_person, na.rm = TRUE), 2),
            pct_superhost  = round(100 * mean(host_is_superhost, na.rm = TRUE), 1),
            median_reviews = median(number_of_reviews, na.rm = TRUE),
            median_revenue = round(median(estimated_revenue_l365d, na.rm = TRUE)),
            .groups = "drop") |>
  arrange(desc(n))

write.csv(by_room, "reports/tables/desc_by_room_type.csv", row.names = FALSE)
cat("\n--- By room type ---\n"); print(as.data.frame(by_room))

by_lga <- priced_sample |>
  group_by(neighbourhood_cleansed) |>
  summarise(n_listings    = n(),
            median_price  = round(median(price_num, na.rm = TRUE), 2),
            iqr_price     = round(IQR(price_num, na.rm = TRUE), 2),
            median_rating = median(review_scores_rating, na.rm = TRUE),
            pct_superhost = round(100 * mean(host_is_superhost, na.rm = TRUE), 1),
            median_revenue = round(median(estimated_revenue_l365d, na.rm = TRUE)),
            .groups = "drop") |>
  arrange(desc(median_price))

write.csv(by_lga, "reports/tables/desc_by_lga.csv", row.names = FALSE)
cat("\n--- By LGA (top 10 by median price) ---\n")
print(as.data.frame(head(by_lga, 10)))

by_superhost <- priced_sample |>
  filter(!is.na(host_is_superhost)) |>
  group_by(host_is_superhost) |>
  summarise(n              = n(),
            median_price   = round(median(price_num, na.rm = TRUE), 2),
            median_rating  = median(review_scores_rating, na.rm = TRUE),
            median_reviews_ltm = median(number_of_reviews_ltm, na.rm = TRUE),
            median_occupancy   = median(estimated_occupancy_l365d, na.rm = TRUE),
            median_revenue = round(median(estimated_revenue_l365d, na.rm = TRUE)),
            .groups = "drop")

write.csv(by_superhost, "reports/tables/desc_by_superhost.csv", row.names = FALSE)
cat("\n--- By Superhost status ---\n"); print(as.data.frame(by_superhost))

# ---- Task 5: visualisations --------------------------------------------------

# 5a. Histogram - raw and log price, with mean and median marked
hist_data <- priced_sample |> select(price_num) |> filter(!is.na(price_num))
p_raw <- ggplot(hist_data, aes(price_num)) +
  geom_histogram(bins = 40, fill = "#0C6DCD", colour = "white", alpha = 0.85) +
  geom_vline(aes(xintercept = mean(price_num)), colour = "#F59E0B",
             linewidth = 1, linetype = "dashed") +
  geom_vline(aes(xintercept = median(price_num)), colour = "#E74C3C",
             linewidth = 1) +
  scale_x_continuous(labels = dollar_format()) +
  scale_y_continuous(labels = comma) +
  labs(title = "Nightly price distribution",
       subtitle = "Dashed amber = mean | solid red = median",
       x = "Price (AUD/night)", y = "Listings")

p_log <- ggplot(hist_data, aes(log(price_num))) +
  geom_histogram(bins = 40, fill = "#0C6DCD", colour = "white", alpha = 0.85) +
  geom_vline(aes(xintercept = mean(log(price_num))), colour = "#F59E0B",
             linewidth = 1, linetype = "dashed") +
  scale_y_continuous(labels = comma) +
  labs(title = "Log-transformed price",
       subtitle = "Right skew removed - why the price model logs its response",
       x = "log(Price)", y = "Listings")

ggsave("reports/figures/11_price_distribution_raw_log.png", p_raw + p_log,
       width = 11, height = 4.5, dpi = 150)

# 5b. Bar charts - composition of the main categorical variables
comp <- cat_summary |>
  filter(variable %in% c("room_type", "min_nights_grp", "host_is_superhost",
                         "shared_bath")) |>
  filter(!is.na(level), level != "NA") |>
  mutate(variable = recode(variable,
                           room_type = "Room type",
                           min_nights_grp = "Minimum nights",
                           host_is_superhost = "Superhost",
                           shared_bath = "Shared bathroom"))

p <- ggplot(comp, aes(x = reorder(level, n), y = n)) +
  geom_col(fill = "#0C6DCD", alpha = 0.85) +
  geom_text(aes(label = paste0(comma(n), " (", pct, "%)")),
            hjust = -0.08, size = 3) +
  coord_flip() +
  facet_wrap(~variable, scales = "free_y") +
  scale_y_continuous(labels = comma, expand = expansion(mult = c(0, 0.28))) +
  labs(title = "Composition of key categorical variables",
       subtitle = sprintf("Full snapshot, n = %s listings", comma(nrow(df))),
       x = NULL, y = "Listings")
ggsave("reports/figures/12_categorical_composition.png", p,
       width = 10, height = 6, dpi = 150)

# 5c. Box plot - price by LGA and room type (top LGAs by listing count)
top_lgas <- priced_sample |> count(neighbourhood_cleansed, sort = TRUE) |>
  slice_head(n = 12) |> pull(neighbourhood_cleansed)

box_data <- priced_sample |>
  filter(neighbourhood_cleansed %in% top_lgas,
         room_type %in% c("Entire home/apt", "Private room"))

p <- ggplot(box_data, aes(x = reorder(neighbourhood_cleansed, price_num, median),
                          y = price_num, fill = room_type)) +
  geom_boxplot(alpha = 0.75, outlier.alpha = 0.15, outlier.size = 0.8) +
  scale_y_continuous(labels = dollar_format()) +
  scale_fill_manual(values = PAL) +
  coord_flip(ylim = c(0, 800)) +
  labs(title = "Nightly price by LGA and room type",
       subtitle = "12 LGAs with the most listings; sorted by median price",
       x = NULL, y = "Price (AUD/night)", fill = "Room type",
       caption = "Axis clipped at $800 for readability; boxes and whiskers computed on the full priced sample") +
  theme(legend.position = "bottom")
ggsave("reports/figures/13_price_by_lga_roomtype.png", p,
       width = 9, height = 6.5, dpi = 150)

# 5d. Small-multiple histograms of the other key numeric variables
dist_vars <- c("accommodates", "bedrooms", "bathrooms_num", "n_amenities",
               "number_of_reviews_ltm", "review_scores_rating")
dist_long <- priced_sample |>
  select(all_of(dist_vars)) |>
  pivot_longer(everything(), names_to = "variable", values_to = "value") |>
  filter(!is.na(value))

p <- ggplot(dist_long, aes(value)) +
  geom_histogram(bins = 30, fill = "#0C6DCD", colour = "white", alpha = 0.85) +
  facet_wrap(~variable, scales = "free") +
  scale_y_continuous(labels = comma) +
  labs(title = "Distributions of key numeric variables",
       subtitle = "Priced sample", x = NULL, y = "Listings")
ggsave("reports/figures/14_numeric_distributions.png", p,
       width = 10, height = 6, dpi = 150)

# 5e. Scatter - price against trailing-year review activity
scat <- priced_sample |>
  filter(!is.na(number_of_reviews_ltm), number_of_reviews_ltm > 0,
         room_type %in% c("Entire home/apt", "Private room"))

p <- ggplot(scat, aes(price_num, number_of_reviews_ltm, colour = room_type)) +
  geom_point(alpha = 0.12, size = 0.8) +
  geom_smooth(method = "gam", formula = y ~ s(x, bs = "cs"), se = FALSE,
              linewidth = 1.1) +
  scale_x_log10(labels = dollar_format(accuracy = 1)) +
  scale_colour_manual(values = PAL) +
  coord_cartesian(ylim = c(0, 90)) +
  labs(title = "Price against review activity",
       subtitle = "Reviews in the trailing 12 months; listings with recent activity only",
       x = "Price (AUD/night, log scale)", y = "Reviews in last 12 months",
       colour = "Room type",
       caption = "Y axis clipped at 90 reviews; smoothers fitted on all points") +
  theme(legend.position = "bottom")
ggsave("reports/figures/15_price_vs_reviews.png", p,
       width = 8.5, height = 5.5, dpi = 150)

cat("\nTables written to reports/tables/, figures to reports/figures/\n")
