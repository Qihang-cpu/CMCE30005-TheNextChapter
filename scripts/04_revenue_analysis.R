# ============================================================
# CMCE30005 Business Analytics Challenge
# Script: 04_revenue_analysis.R
# Purpose: Decompose Inside Airbnb's modelled listing revenue into price and
#          review-derived activity, and identify what is associated with
#          achieving any recent activity and with sustaining it
# Author: TheNextChapter (Group 2)
# Date: 14 August 2026
# ============================================================
#
# Input : data/processed/listings_clean.rds (from 01_data_cleaning.R)
# Output: reports/tables/revenue_*.csv, reports/figures/06-09_*.png
#
# TERMINOLOGY. This dataset observes reviews, not bookings. Every quantity
# below is named for what is actually measured:
#   "review activity"  = reviews recorded in the trailing 12 months
#   "modelled nights"  = Inside Airbnb's occupancy construct, not real nights
#   "modelled revenue" = price x modelled nights, not money actually earned
# Nothing is called a booking, and no coefficient is called an elasticity.
# ============================================================

library(data.table)
library(ggplot2)
library(scales)
library(sandwich)

listings <- readRDS("data/processed/listings_clean.rds")

SNAPSHOT <- as.Date("2026-06-16")

# Clustered covariance. sandwich::vcovCL exhausts the C stack on the logistic
# model at this size, so the sandwich is assembled directly from the score
# contributions, aggregated by host with rowsum.
cluster_vcov <- function(fit, cluster_ids) {
  ef <- estfun(fit)
  rows <- as.integer(rownames(ef))
  cl <- as.character(cluster_ids[rows])
  n <- NROW(ef); k <- NCOL(ef); G <- length(unique(cl))
  agg <- rowsum(ef, group = cl, reorder = FALSE)
  br <- bread(fit)
  V <- (br %*% (crossprod(agg) / n) %*% br) / n
  V * (G / (G - 1)) * ((n - 1) / (n - k))
}

# Coefficient table from a fit and a covariance matrix. Assembled directly
# rather than through lmtest::coeftest, which recurses past the C stack limit
# on the logistic model at this size.
coef_table <- function(fit, V) {
  b <- coef(fit); se <- sqrt(diag(V))[names(b)]
  data.table(term = names(b), estimate = unname(b), std_error = unname(se),
             statistic = unname(b / se),
             p_value = 2 * pnorm(-abs(unname(b / se))))
}

all_l <- copy(listings)
d <- listings[priced == TRUE]

# ============================================================
# 1. What the revenue field actually is
# ============================================================

chk <- d[!is.na(estimated_occupancy_l365d) & !is.na(number_of_reviews_ltm) &
         !is.na(minimum_nights) & number_of_reviews_ltm > 0]
chk[, occ_predicted := pmin(number_of_reviews_ltm * 2 * pmax(minimum_nights, 3), 255)]
occ_exact <- mean(abs(chk$occ_predicted - chk$estimated_occupancy_l365d) < 0.5)

rev_chk <- d[!is.na(estimated_revenue_l365d) & estimated_occupancy_l365d > 0]
rev_chk[, rev_predicted := price_num * estimated_occupancy_l365d]
rev_exact <- mean(abs(round(rev_chk$rev_predicted) - rev_chk$estimated_revenue_l365d) < 0.01)

cat("=== 1. Reconstruction of the published revenue field ===\n")
cat(sprintf("occupancy = min(reviews_ltm x 2 x max(min_nights, 3), 255): %.1f%% exact (n = %s)\n",
            100 * occ_exact, comma(nrow(chk))))
cat(sprintf("revenue   = round(price x occupancy):                       %.1f%% exact (n = %s)\n",
            100 * rev_exact, comma(nrow(rev_chk))))
cat("Revenue is a construct, not a measurement. It is never regressed on its\n")
cat("own inputs; the identity is decomposed and the components modelled.\n\n")

# ============================================================
# 2. Sample censoring - who the price filter leaves out
# ============================================================

# The analysis sample keeps only listings with a usable price. That filter is
# not random with respect to the outcome, so it is quantified rather than left
# implicit.
cens <- rbind(
  data.table(sample = "All listings", n = nrow(all_l),
             pct_no_recent_reviews = round(100 * mean(all_l$number_of_reviews_ltm == 0), 1)),
  data.table(sample = "Priced sample (analysis set)", n = all_l[priced == TRUE, .N],
             pct_no_recent_reviews = round(100 * all_l[priced == TRUE,
                                                       mean(number_of_reviews_ltm == 0)], 1)),
  data.table(sample = "Excluded: no usable price", n = all_l[priced == FALSE, .N],
             pct_no_recent_reviews = round(100 * all_l[priced == FALSE,
                                                       mean(number_of_reviews_ltm == 0)], 1))
)

cat("=== 2. What the price filter removes ===\n")
print(cens)
cat("\nExcluded listings are overwhelmingly inactive, so this is not random\n")
cat("censoring. Activity rates below describe priced listings only and\n")
cat("understate inactivity across the market as a whole.\n\n")
fwrite(cens, "reports/tables/revenue_sample_censoring.csv")

# ============================================================
# 3. Where the variation in modelled revenue sits
# ============================================================

# modelled revenue = price x (2 x max(min_nights,3)) x reviews_ltm, capped at
# 255 nights. Below the cap the log form is exactly additive in three terms, so
# the host's minimum-night policy is separated from review activity instead of
# being bundled with it into a single "volume" term.
dec <- d[number_of_reviews_ltm > 0 & !is.na(minimum_nights)]
dec[, stay_multiplier := 2 * pmax(minimum_nights, 3)]
dec[, uncapped := number_of_reviews_ltm * stay_multiplier <= 255]

decompose3 <- function(x, label) {
  lp <- log(x$price_num); ls_ <- log(x$stay_multiplier); lr <- log(x$number_of_reviews_ltm)
  v <- var(lp + ls_ + lr)
  data.table(sample = label, n = nrow(x),
             price_share = round(var(lp) / v, 3),
             stay_policy_share = round(var(ls_) / v, 3),
             review_activity_share = round(var(lr) / v, 3),
             covariance_share = round((2 * cov(lp, ls_) + 2 * cov(lp, lr) +
                                       2 * cov(ls_, lr)) / v, 3))
}

var_decomp <- rbind(
  decompose3(dec[uncapped == TRUE], "Uncapped listings"),
  decompose3(dec[uncapped == TRUE & room_type == "Entire home/apt"], "Uncapped, entire homes")
)

cat("=== 3. Variance decomposition of log modelled revenue ===\n")
print(var_decomp)
cat(sprintf("\nRestricted to the %.1f%% of active listings below the 255-night cap, where\n",
            100 * mean(dec$uncapped)))
cat("the identity is exactly additive. These are shares of cross-sectional\n")
cat("dispersion in a modelled quantity, not a statement about what causes revenue.\n\n")
fwrite(var_decomp, "reports/tables/revenue_variance_decomposition.csv")

# ============================================================
# 4. Listing age and review activity
# ============================================================

# A listing younger than a year cannot have accrued twelve months of reviews,
# so raw trailing counts understate new listings. Activity is expressed per
# month of exposure to make ages comparable.
d[, listing_age_years := as.numeric(SNAPSHOT - as.Date(first_review)) / 365.25]
d[, exposure_months := pmin(12, pmax(1, listing_age_years * 12))]
d[, reviews_per_month := number_of_reviews_ltm / exposure_months]

age_tab <- d[number_of_reviews_ltm > 0 & !is.na(listing_age_years),
             .(listings = .N,
               median_reviews_ltm = as.numeric(median(number_of_reviews_ltm)),
               median_reviews_per_month = round(as.numeric(median(reviews_per_month)), 2),
               median_price = as.numeric(median(price_num))),
             by = .(age_band = cut(listing_age_years, c(0, 1, 2, 5, Inf),
                                   labels = c("under 1 year", "1-2 years",
                                              "2-5 years", "5+ years")))]
setorder(age_tab, age_band)

cat("=== 4. Review activity by listing age (active listings) ===\n")
print(age_tab)
fwrite(age_tab, "reports/tables/revenue_by_listing_age.csv")

# ============================================================
# 5. Achieving any recent review activity
# ============================================================

d[, has_recent_activity := number_of_reviews_ltm > 0]

m_sample <- d[!is.na(bedrooms) & !is.na(bathrooms_num) & !is.na(host_tenure_years) &
              !is.na(min_nights_grp)]
big_lgas <- m_sample[, .N, by = neighbourhood_cleansed][N >= 200, neighbourhood_cleansed]
m_sample[, lga := relevel(factor(fifelse(neighbourhood_cleansed %in% big_lgas,
                                         neighbourhood_cleansed, "Other")), ref = "Melbourne")]
m_sample[, room_type := relevel(factor(room_type), ref = "Entire home/apt")]
m_sample[, superhost := host_is_superhost == "t"]

cat("\n=== 5. Any recent review activity (logistic) ===\n")
cat(sprintf("%.1f%% of priced listings recorded at least one review in 12 months\n",
            100 * mean(d$has_recent_activity)))

m_active <- glm(has_recent_activity ~ log(price_num) + room_type + accommodates +
                  bedrooms + bathrooms_num + n_amenities + superhost +
                  host_tenure_years + log1p(calculated_host_listings_count) +
                  min_nights_grp + availability_365 + lga,
                data = m_sample, family = binomial())

# listings of the same host are not independent observations
act <- coef_table(m_active, cluster_vcov(m_active, m_sample$host_id))
act[, odds_ratio := round(exp(estimate), 3)]
fwrite(act, "reports/tables/revenue_extensive_margin.csv")

cat("Odds ratios, host-clustered standard errors, p < 0.001:\n")
print(act[p_value < 0.001 & term != "(Intercept)",
          .(term, odds_ratio, p_value = signif(p_value, 2))][order(-abs(log(odds_ratio)))][1:8])

# ============================================================
# 6. Sustaining review activity among active listings
# ============================================================

act_sample <- m_sample[has_recent_activity == TRUE & !is.na(review_scores_rating) &
                       !is.na(listing_age_years) & listing_age_years > 0]

m_volume <- lm(log(number_of_reviews_ltm) ~ log(price_num) + room_type + accommodates +
                 bedrooms + bathrooms_num + n_amenities + superhost +
                 host_tenure_years + log(listing_age_years) +
                 log1p(calculated_host_listings_count) + review_scores_rating +
                 min_nights_grp + availability_365 + lga,
               data = act_sample)

vol_cl <- coef_table(m_volume, cluster_vcov(m_volume, act_sample$host_id))
vol_cl[, pct_difference := round(100 * (exp(estimate) - 1), 1)]
fwrite(vol_cl, "reports/tables/revenue_intensive_margin.csv")

cat("\n=== 6. Review intensity among active listings ===\n")
cat(sprintf("n = %s, adjusted R-squared = %.3f, %s host clusters\n",
            comma(nobs(m_volume)), summary(m_volume)$adj.r.squared,
            comma(uniqueN(act_sample$host_id))))
cat("\nDifferences in review count, host-clustered SEs, p < 0.001:\n")
print(vol_cl[p_value < 0.001 & abs(pct_difference) > 5 & term != "(Intercept)",
             .(term, pct_difference, p_value = signif(p_value, 2))][order(-abs(pct_difference))][1:12])

# ============================================================
# 7. The price-activity association
# ============================================================

# The price coefficient is a cross-sectional association, not a demand
# elasticity. The response counts reviews accumulated over the previous twelve
# months while the regressor is the price observed on a single day at the end
# of that window, so the two are not aligned in time. Price is also set by the
# host in response to demand and to quality we do not observe. It is reported
# for what it is and is not used to compute any counterfactual.
assoc <- vol_cl[term == "log(price_num)"]
ci <- assoc$estimate + c(-1.96, 1.96) * assoc$std_error

cat("\n=== 7. Price-activity association ===\n")
cat(sprintf("Coefficient on log(price): %.3f (95%% CI %.3f to %.3f, host-clustered)\n",
            assoc$estimate, ci[1], ci[2]))
cat(sprintf("Reading: among comparable active listings, those priced 10%% higher\n"))
cat(sprintf("recorded about %.1f%% fewer reviews over the same window.\n",
            -100 * (1.10 ^ assoc$estimate - 1)))
cat("This is NOT a demand elasticity. It does not support any claim about what\n")
cat("would happen to a listing's revenue if its host changed the price.\n\n")

robust <- rbindlist(lapply(
  list(list("Main specification", m_volume, act_sample),
       list("Without availability", update(m_volume, . ~ . - availability_365), act_sample),
       list("Without availability or Superhost",
            update(m_volume, . ~ . - availability_365 - superhost), act_sample)),
  function(sp) {
    ct <- coef_table(sp[[2]], cluster_vcov(sp[[2]], sp[[3]]$host_id))
    data.table(specification = sp[[1]], n = nobs(sp[[2]]),
               coefficient = round(ct[term == "log(price_num)", estimate], 3),
               clustered_se = round(ct[term == "log(price_num)", std_error], 3))
  }))
ent <- act_sample[room_type == "Entire home/apt"]
fit_ent <- lm(update(formula(m_volume), . ~ . - room_type), data = ent)
ct_ent <- coef_table(fit_ent, cluster_vcov(fit_ent, ent$host_id))
robust <- rbind(robust, data.table(specification = "Entire homes only", n = nobs(fit_ent),
                                   coefficient = round(ct_ent[term == "log(price_num)", estimate], 3),
                                   clustered_se = round(ct_ent[term == "log(price_num)", std_error], 3)))

cat("Stability across specifications (host-clustered SEs):\n")
print(robust)
cat("Stability speaks to the choice of controls only. It does not address the\n")
cat("timing mismatch, reverse causation or unobserved quality.\n\n")
fwrite(robust, "reports/tables/revenue_price_association_robustness.csv")

# ============================================================
# 8. Superhost comparison
# ============================================================

sh_all <- d[, .(listings = .N,
                pct_with_recent_activity = round(100 * mean(has_recent_activity), 1),
                median_price = as.numeric(median(price_num)),
                median_reviews_ltm = as.numeric(median(number_of_reviews_ltm)),
                median_modelled_revenue = as.numeric(median(estimated_revenue_l365d, na.rm = TRUE))),
            by = .(superhost = host_is_superhost == "t")]
sh_all[, scope := "all priced listings"]

sh_act <- d[has_recent_activity == TRUE,
            .(listings = .N, pct_with_recent_activity = 100,
              median_price = as.numeric(median(price_num)),
              median_reviews_ltm = as.numeric(median(number_of_reviews_ltm)),
              median_modelled_revenue = as.numeric(median(estimated_revenue_l365d, na.rm = TRUE))),
            by = .(superhost = host_is_superhost == "t")]
sh_act[, scope := "active listings only"]

sh <- rbind(sh_all, sh_act); setcolorder(sh, "scope")
cat("=== 8. Superhost comparison (descriptive) ===\n")
print(sh)
cat(sprintf("\nModelled revenue ratio, active listings only: %.1fx\n",
            sh_act[superhost == TRUE, median_modelled_revenue] /
            sh_act[superhost == FALSE, median_modelled_revenue]))
cat("Superhost status is awarded partly on booking performance, so this compares\n")
cat("two outcomes and is not an effect of the badge.\n\n")
fwrite(sh, "reports/tables/revenue_superhost_gap.csv")

# ============================================================
# Figures
# ============================================================

theme_set(theme_minimal(base_size = 12))

vd <- melt(var_decomp[, .(sample, Price = price_share,
                          `Stay-length policy` = stay_policy_share,
                          `Review activity` = review_activity_share,
                          Covariance = covariance_share)],
           id.vars = "sample", variable.name = "component", value.name = "share")
vd[, sample := factor(sample, levels = rev(var_decomp$sample))]

p <- ggplot(vd, aes(share, sample, fill = component)) +
  geom_col(position = position_dodge(0.8), width = 0.75) +
  geom_vline(xintercept = 0, colour = "grey40", linewidth = 0.4) +
  geom_text(aes(label = percent(share, accuracy = 1),
                hjust = ifelse(share < 0, 1.15, -0.15)),
            position = position_dodge(0.8), size = 2.9, colour = "grey20") +
  scale_x_continuous(labels = percent, limits = c(-0.2, 1.05)) +
  scale_fill_manual(values = c("Price" = "#4878A8", "Stay-length policy" = "#E0A458",
                               "Review activity" = "#C0504D", "Covariance" = "#9BA7B0")) +
  labs(title = "Where variation in modelled revenue sits",
       subtitle = "Shares of cross-sectional variance in log modelled revenue, uncapped listings",
       x = NULL, y = NULL, fill = NULL) +
  theme(legend.position = "bottom")
ggsave("reports/figures/06_revenue_variance_decomposition.png", p,
       width = 9.5, height = 4, dpi = 150)

cens_plot <- cens[sample != "All listings"]
p <- ggplot(cens_plot, aes(reorder(sample, pct_no_recent_reviews), pct_no_recent_reviews)) +
  geom_col(fill = "#4878A8", width = 0.55) +
  geom_text(aes(label = paste0(pct_no_recent_reviews, "%")), hjust = -0.15, size = 3.4) +
  coord_flip() +
  scale_y_continuous(limits = c(0, 100), expand = expansion(mult = c(0, 0.12))) +
  labs(title = "The price filter removes mostly inactive listings",
       subtitle = "Share with no reviews in the trailing 12 months",
       x = NULL, y = NULL)
ggsave("reports/figures/07_sample_censoring.png", p, width = 8, height = 3.2, dpi = 150)

rev_plot <- d[estimated_occupancy_l365d > 0]
rev_plot[, price_band := cut(price_num, quantile(price_num, 0:4 / 4), include.lowest = TRUE,
                             labels = c("Q1 cheapest", "Q2", "Q3", "Q4 dearest"))]
rev_plot[, activity_band := cut(number_of_reviews_ltm, c(0, 2, 6, 15, Inf),
                                labels = c("1-2", "3-6", "7-15", "16+"))]
grid <- rev_plot[!is.na(activity_band),
                 .(median_revenue = median(estimated_revenue_l365d), n = .N),
                 by = .(price_band, activity_band)][n >= 20]
p <- ggplot(grid, aes(price_band, activity_band, fill = median_revenue)) +
  geom_tile(colour = "white", linewidth = 1) +
  geom_text(aes(label = dollar(median_revenue, accuracy = 1)), size = 3.1,
            colour = "white", fontface = "bold") +
  scale_fill_gradient(low = "#B8CBDD", high = "#1F4E79", labels = dollar) +
  labs(title = "Median modelled revenue by price and review activity",
       subtitle = "Cells with at least 20 listings",
       x = "Price quartile", y = "Reviews in trailing 12 months",
       fill = "Modelled revenue")
ggsave("reports/figures/08_revenue_price_activity_grid.png", p, width = 8.5, height = 5, dpi = 150)

age_plot <- d[number_of_reviews_ltm > 0 & !is.na(listing_age_years) & listing_age_years <= 10]
age_plot[, band := cut(listing_age_years, seq(0, 10, 0.5))]
age_curve <- age_plot[, .(median_rpm = median(reviews_per_month), n = .N),
                      by = .(age_mid = as.numeric(band) * 0.5 - 0.25)][n >= 40]
p <- ggplot(age_curve, aes(age_mid, median_rpm)) +
  geom_line(colour = "#C0504D", linewidth = 0.9) +
  geom_point(size = 1.3) +
  scale_y_continuous(limits = c(0, NA)) +
  labs(title = "Review activity by listing age",
       subtitle = "Median reviews per month of exposure; active listings under 10 years old",
       x = "Listing age (years since first review)", y = "Reviews per month")
ggsave("reports/figures/09_activity_by_listing_age.png", p, width = 8, height = 5, dpi = 150)

cat("Tables written to reports/tables/, figures to reports/figures/\n")
