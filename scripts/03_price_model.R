# ============================================================
# CMCE30005 Business Analytics Challenge
# Script: 03_price_model.R
# Purpose: Hedonic regression of nightly price - which listing, host and
#          location attributes drive price variation across Melbourne
# Author: TheNextChapter (Group 2)
# Date: 6 August 2026
# ============================================================
#
# Input : data/processed/listings_clean.rds (from 01_data_cleaning.R)
# Output: reports/tables/price_model_coefficients.csv
#         data/processed/price_model.rds
# ============================================================

library(data.table)
library(broom)

listings <- readRDS("data/processed/listings_clean.rds")

# Modelling sample: a usable price, the core attributes present, and at least
# three reviews so that the asking price has had some market test.
d <- listings[priced == TRUE &
              !is.na(bedrooms) & !is.na(bathrooms_num) & !is.na(accommodates) &
              !is.na(review_scores_rating) & !is.na(review_scores_location) &
              !is.na(min_nights_grp) & number_of_reviews >= 3]

# LGAs with fewer than 200 listings are pooled so the factor stays estimable
lga_counts <- d[, .N, by = neighbourhood_cleansed]
big_lgas <- lga_counts[N >= 200, neighbourhood_cleansed]
d[, lga := fifelse(neighbourhood_cleansed %in% big_lgas,
                   neighbourhood_cleansed, "Other")]
d[, lga := relevel(factor(lga), ref = "Melbourne")]
d[, room_type := relevel(factor(room_type), ref = "Entire home/apt")]

cat("Model sample:", nrow(d), "listings across", length(unique(d$lga)), "LGA groups\n")

# The price distribution is heavily right skewed, so the response is logged and
# coefficients read as percentage effects.
# instant_bookable is excluded: it is 100% missing in this snapshot.
m1 <- lm(log(price_num) ~ room_type + accommodates + bedrooms + bathrooms_num +
           shared_bath + n_amenities + host_is_superhost +
           review_scores_rating + review_scores_location + min_nights_grp + lga,
         data = d)

cat(sprintf("Adjusted R-squared: %.3f\n", summary(m1)$adj.r.squared))

coefs <- as.data.table(tidy(m1))
coefs[, pct_effect := round(100 * (exp(estimate) - 1), 1)]   # exp(beta) - 1
fwrite(coefs, "reports/tables/price_model_coefficients.csv")

cat("\nLargest effects (|effect| > 10%, p < 0.001):\n")
print(coefs[p.value < 0.001 & abs(pct_effect) > 10 & term != "(Intercept)",
            .(term, pct_effect, p.value = signif(p.value, 2))][order(-abs(pct_effect))])

cat(sprintf("\nEach extra guest of capacity: %+.1f%% (bedrooms and baths held constant)\n",
            100 * (exp(coefs[term == "accommodates", estimate]) - 1)))
cat(sprintf("Each extra bedroom: %+.1f%%\n",
            100 * (exp(coefs[term == "bedrooms", estimate]) - 1)))
cat(sprintf("Superhost: %+.1f%%\n",
            100 * (exp(coefs[term == "host_is_superhostt", estimate]) - 1)))

# Residual spread across the fitted range - a simple check that the log
# specification has not left obvious heteroskedasticity at either tail.
d[, fitted := fitted(m1)]
d[, resid := resid(m1)]
fit_check <- d[, .(mean_abs_resid = round(mean(abs(resid)), 3), n = .N),
               by = .(band = cut(fitted, quantile(fitted, 0:5 / 5), include.lowest = TRUE))]
print(fit_check[order(band)])

saveRDS(m1, "data/processed/price_model.rds")
cat("\nModel and coefficient table written.\n")
