# ============================================================
# CMCE30005 Business Analytics Challenge
# Script: 04_revenue_analysis.R
# Purpose: Decompose host revenue into its pricing and booking-volume
#          components, and identify what drives each
# Author: TheNextChapter (Group 2)
# Date: 6 August 2026
# ============================================================
#
# Input : data/processed/listings_clean.rds (from 01_data_cleaning.R)
# Output: reports/tables/revenue_*.csv, reports/figures/06-08_*.png
#
# The revenue field published by Inside Airbnb is a construct, not a measured
# quantity. Section 1 reconstructs it exactly, which dictates the design of
# everything that follows: revenue is never regressed on its own inputs.
# ============================================================

library(data.table)
library(ggplot2)
library(scales)
library(broom)

listings <- readRDS("data/processed/listings_clean.rds")

d <- listings[priced == TRUE]

# ============================================================
# 1. What the revenue field actually is
# ============================================================

chk <- d[!is.na(estimated_occupancy_l365d) & !is.na(number_of_reviews_ltm) &
         !is.na(minimum_nights) & number_of_reviews_ltm > 0]

# Inside Airbnb's occupancy model: every review is assumed to represent two
# stays, each lasting the greater of the minimum-night rule and three nights,
# with total nights capped at 255 (70% of the year).
chk[, occ_predicted := pmin(number_of_reviews_ltm * 2 * pmax(minimum_nights, 3), 255)]
occ_exact <- mean(abs(chk$occ_predicted - chk$estimated_occupancy_l365d) < 0.5)

rev_chk <- d[!is.na(estimated_revenue_l365d) & estimated_occupancy_l365d > 0]
rev_chk[, rev_predicted := price_num * estimated_occupancy_l365d]
# the published field is rounded to whole dollars, so compare on that basis
rev_exact <- mean(abs(round(rev_chk$rev_predicted) - rev_chk$estimated_revenue_l365d) < 0.01)
rev_maxerr <- max(abs(rev_chk$rev_predicted - rev_chk$estimated_revenue_l365d) /
                    rev_chk$estimated_revenue_l365d)

cat("=== 1. Reconstruction of the published revenue field ===\n")
cat(sprintf("occupancy = min(reviews_ltm x 2 x max(min_nights, 3), 255): %.1f%% exact (n = %s)\n",
            100 * occ_exact, comma(nrow(chk))))
cat(sprintf("revenue   = round(price x occupancy):                       %.1f%% exact (n = %s)\n",
            100 * rev_exact, comma(nrow(rev_chk))))
cat(sprintf("largest relative discrepancy in revenue: %.3f%%\n", 100 * rev_maxerr))
cat("Revenue is therefore a deterministic function of price, review count and\n",
    "the minimum-night rule. It is treated here as an accounting identity, not\n",
    "as an outcome to be regressed on those same inputs.\n\n", sep = "")

# ============================================================
# 2. Where does revenue variation come from?
# ============================================================

# Because revenue = price x nights exactly, taking logs gives an additive
# identity whose variance splits into a pricing term, a volume term and their
# covariance. The three shares sum to one and require no model.
decompose <- function(dt, label) {
  x <- dt[estimated_occupancy_l365d > 0 & price_num > 0 & !is.na(estimated_revenue_l365d)]
  lp <- log(x$price_num)
  ln <- log(x$estimated_occupancy_l365d)
  lr <- log(x$price_num * x$estimated_occupancy_l365d)
  v <- var(lr)
  data.table(sample = label,
             n = nrow(x),
             var_log_revenue = round(v, 3),
             price_share = round(var(lp) / v, 3),
             volume_share = round(var(ln) / v, 3),
             covariance_share = round(2 * cov(lp, ln) / v, 3))
}

var_decomp <- rbind(
  decompose(d, "All priced listings with bookings"),
  decompose(d[room_type == "Entire home/apt"], "Entire homes only"),
  decompose(d[number_of_reviews_ltm >= 6], "Regularly booked (6+ reviews in 12m)")
)

cat("=== 2. Variance decomposition of log revenue ===\n")
print(var_decomp)
cat("\n")
fwrite(var_decomp, "reports/tables/revenue_variance_decomposition.csv")

# ============================================================
# 3. Getting booked at all - the extensive margin
# ============================================================

# A third of listings record no bookings in the trailing year. Whether a listing
# clears this hurdle is a larger revenue question than how it is priced, so it
# is modelled separately before turning to volume among those that do.
d[, is_active := number_of_reviews_ltm > 0]

cat("=== 3. Extensive margin: any bookings in the trailing 12 months ===\n")
cat(sprintf("Active: %s of %s listings (%.1f%%)\n",
            comma(d[is_active == TRUE, .N]), comma(nrow(d)), 100 * mean(d$is_active)))

m_sample <- d[!is.na(bedrooms) & !is.na(bathrooms_num) & !is.na(host_tenure_years)]

lga_counts <- m_sample[, .N, by = neighbourhood_cleansed]
big_lgas <- lga_counts[N >= 200, neighbourhood_cleansed]
m_sample[, lga := fifelse(neighbourhood_cleansed %in% big_lgas,
                          neighbourhood_cleansed, "Other")]
m_sample[, lga := relevel(factor(lga), ref = "Melbourne")]
m_sample[, room_type := relevel(factor(room_type), ref = "Entire home/apt")]
m_sample[, superhost := host_is_superhost == "t"]

m_active <- glm(is_active ~ log(price_num) + room_type + accommodates + bedrooms +
                  bathrooms_num + n_amenities + superhost + host_tenure_years +
                  log1p(calculated_host_listings_count) + min_nights_grp +
                  availability_365 + lga,
                data = m_sample, family = binomial())

act <- as.data.table(tidy(m_active))
act[, odds_ratio := round(exp(estimate), 3)]
fwrite(act, "reports/tables/revenue_extensive_margin.csv")

cat("\nOdds ratios, strongest effects (p < 0.001):\n")
print(act[p.value < 0.001 & term != "(Intercept)",
          .(term, odds_ratio, p.value = signif(p.value, 2))][order(-abs(log(odds_ratio)))][1:10])

# ============================================================
# 4. Booking volume among active listings - the intensive margin
# ============================================================

# Review count is the observed quantity here; occupancy is only that count
# rescaled by the host's own minimum-night rule, so modelling reviews avoids
# building the policy multiplier into the response.
act_sample <- m_sample[is_active == TRUE & !is.na(review_scores_rating)]

m_volume <- lm(log(number_of_reviews_ltm) ~ log(price_num) + room_type + accommodates +
                 bedrooms + bathrooms_num + n_amenities + superhost +
                 host_tenure_years + log1p(calculated_host_listings_count) +
                 review_scores_rating + min_nights_grp + availability_365 + lga,
               data = act_sample)

vol <- as.data.table(tidy(m_volume))
vol[, pct_effect := round(100 * (exp(estimate) - 1), 1)]
fwrite(vol, "reports/tables/revenue_intensive_margin.csv")

cat("\n=== 4. Intensive margin: log(reviews in trailing 12m) ===\n")
cat(sprintf("n = %s, adjusted R-squared = %.3f\n",
            comma(nrow(act_sample)), summary(m_volume)$adj.r.squared))
cat("\nStrongest effects (p < 0.001, |effect| > 5%):\n")
print(vol[p.value < 0.001 & abs(pct_effect) > 5 & term != "(Intercept)",
          .(term, pct_effect, p.value = signif(p.value, 2))][order(-abs(pct_effect))])

# ============================================================
# 5. Does raising price cost enough volume to be self-defeating?
# ============================================================

# The price coefficient in the volume model is an elasticity. Revenue rises with
# price whenever that elasticity is greater than -1; below -1 the lost nights
# outweigh the higher rate.
elast <- vol[term == "log(price_num)", estimate]
elast_se <- vol[term == "log(price_num)", std.error]
ci <- elast + c(-1.96, 1.96) * elast_se

cat("\n=== 5. Price elasticity of booking volume ===\n")
cat(sprintf("Elasticity: %.3f (95%% CI %.3f to %.3f)\n", elast, ci[1], ci[2]))
cat(sprintf("Net effect of a 10%% price rise on revenue: %+.1f%%\n",
            100 * ((1.10) * (1.10 ^ elast) - 1)))
cat("An elasticity above -1 means the rate increase outweighs the nights lost.\n")
cat("This is an observational estimate: better properties both charge and book\n")
cat("more, so the true causal elasticity is likely more negative than this.\n\n")

elast_tab <- data.table(elasticity = round(elast, 3),
                        ci_low = round(ci[1], 3), ci_high = round(ci[2], 3),
                        revenue_effect_of_10pct_price_rise =
                          round(100 * (1.10 * 1.10 ^ elast - 1), 2))
fwrite(elast_tab, "reports/tables/revenue_price_elasticity.csv")

# ============================================================
# 6. The Superhost gap, decomposed
# ============================================================

# The headline gap compares medians across the whole market. Splitting it into
# the two margins shows how much survives once dormant listings are set aside.
sh_raw <- d[, .(listings = .N,
                median_price = as.numeric(median(price_num)),
                pct_active = round(100 * mean(is_active), 1),
                median_reviews_ltm = as.numeric(median(number_of_reviews_ltm)),
                median_revenue = as.numeric(median(estimated_revenue_l365d, na.rm = TRUE))),
            by = .(superhost = host_is_superhost == "t")]

sh_active <- d[is_active == TRUE,
               .(listings = .N,
                 median_price = as.numeric(median(price_num)),
                 median_reviews_ltm = as.numeric(median(number_of_reviews_ltm)),
                 median_revenue = as.numeric(median(estimated_revenue_l365d, na.rm = TRUE))),
               by = .(superhost = host_is_superhost == "t")]

cat("=== 6. Superhost comparison ===\n")
cat("All priced listings:\n"); print(sh_raw)
cat("\nActive listings only:\n"); print(sh_active)

gap_all <- sh_raw[superhost == TRUE, median_revenue] / sh_raw[superhost == FALSE, median_revenue]
gap_act <- sh_active[superhost == TRUE, median_revenue] / sh_active[superhost == FALSE, median_revenue]
cat(sprintf("\nRevenue ratio, all listings:    %.1fx\n", gap_all))
cat(sprintf("Revenue ratio, active only:    %.1fx\n", gap_act))
cat("Superhost status is awarded partly on booking performance, so this is an\n")
cat("association between two outcomes, not an effect of the badge.\n\n")

fwrite(rbind(cbind(scope = "all", sh_raw[, !"pct_active"]),
             cbind(scope = "active", sh_active)),
       "reports/tables/revenue_superhost_gap.csv")

# ============================================================
# Figures
# ============================================================

theme_set(theme_minimal(base_size = 12))

vd <- melt(var_decomp[, .(sample, Pricing = price_share, Volume = volume_share,
                          Covariance = covariance_share)],
           id.vars = "sample", variable.name = "component", value.name = "share")
vd[, sample := factor(sample, levels = rev(var_decomp$sample))]

# grouped rather than stacked: the covariance term can be negative, and a
# stacked bar crossing zero reads as an error
p <- ggplot(vd, aes(share, sample, fill = component)) +
  geom_col(position = position_dodge(0.75), width = 0.7) +
  geom_vline(xintercept = 0, colour = "grey40", linewidth = 0.4) +
  geom_text(aes(label = percent(share, accuracy = 1),
                hjust = ifelse(share < 0, 1.15, -0.15)),
            position = position_dodge(0.75), size = 3, colour = "grey20") +
  scale_x_continuous(labels = percent, limits = c(-0.25, 1.12)) +
  scale_fill_manual(values = c(Pricing = "#4878A8", Volume = "#C0504D",
                               Covariance = "#9BA7B0")) +
  labs(title = "Where revenue variation comes from",
       subtitle = "Variance of log revenue split into pricing and booking-volume components",
       x = "Share of variance in log revenue", y = NULL, fill = NULL) +
  theme(legend.position = "bottom")
ggsave("reports/figures/06_revenue_variance_decomposition.png", p,
       width = 9, height = 4.5, dpi = 150)

active_rates <- d[, .(pct_active = 100 * mean(is_active), n = .N),
                  by = .(superhost = fifelse(host_is_superhost == "t",
                                             "Superhost", "Regular host"),
                         price_band = cut(price_num, quantile(price_num, 0:4 / 4),
                                          include.lowest = TRUE,
                                          labels = c("Q1 cheapest", "Q2", "Q3",
                                                     "Q4 dearest")))]
p <- ggplot(active_rates, aes(price_band, pct_active, fill = superhost)) +
  geom_col(position = position_dodge(0.75), width = 0.7) +
  geom_text(aes(label = sprintf("%.0f%%", pct_active)),
            position = position_dodge(0.75), vjust = -0.4, size = 3) +
  scale_y_continuous(limits = c(0, 105), labels = function(x) paste0(x, "%")) +
  scale_fill_manual(values = c("Regular host" = "#9BA7B0", "Superhost" = "#4878A8")) +
  labs(title = "Share of listings booked at least once in the trailing year",
       subtitle = "By price quartile and host status",
       x = NULL, y = "Listings with any bookings", fill = NULL) +
  theme(legend.position = "bottom")
ggsave("reports/figures/07_active_rate_by_price_and_host.png", p,
       width = 8, height = 5, dpi = 150)

rev_plot <- d[estimated_occupancy_l365d > 0]
rev_plot[, price_band := cut(price_num, quantile(price_num, 0:4 / 4),
                             include.lowest = TRUE,
                             labels = c("Q1 cheapest", "Q2", "Q3", "Q4 dearest"))]
rev_plot[, volume_band := cut(number_of_reviews_ltm,
                              c(0, 2, 6, 15, Inf),
                              labels = c("1-2", "3-6", "7-15", "16+"))]
grid <- rev_plot[!is.na(volume_band),
                 .(median_revenue = median(estimated_revenue_l365d), n = .N),
                 by = .(price_band, volume_band)][n >= 20]

p <- ggplot(grid, aes(price_band, volume_band, fill = median_revenue)) +
  geom_tile(colour = "white", linewidth = 1) +
  geom_text(aes(label = dollar(median_revenue, accuracy = 1)), size = 3.1,
            colour = "white", fontface = "bold") +
  scale_fill_gradient(low = "#B8CBDD", high = "#1F4E79", labels = dollar) +
  labs(title = "Median annual revenue by price and booking volume",
       subtitle = "Cells with at least 20 listings; volume measured in reviews over 12 months",
       x = "Price quartile", y = "Reviews in trailing 12 months",
       fill = "Median revenue")
ggsave("reports/figures/08_revenue_price_volume_grid.png", p,
       width = 8.5, height = 5, dpi = 150)

cat("Tables written to reports/tables/, figures to reports/figures/\n")
