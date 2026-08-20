# ============================================================
# CMCE30005 Business Analytics Challenge
# Script: 06_segment_roi_screen.R
# Purpose: Preliminary first-year cash-on-cash ROI screen for every eligible
#          LGA x dwelling-type segment that DFFH publishes a rent series for
# Author: TheNextChapter (Group 2)
# Date: 20 August 2026
# ============================================================
#
# Input  : data/processed/listings_clean.rds        (01_data_cleaning.R)
#          data/external/dffh_median_rents_sep2025.csv (05_rent_data.R)
# Output : reports/tables/segment_roi_screen.csv
#          reports/figures/10_segment_roi_screen.png
#
# This is a descriptive screen, not a prediction. Revenue percentiles come from
# Inside Airbnb's modelled revenue field, which is a construct - see
# reports/data-notes.md. Results are read as a ranking of segment economics
# under stated cost assumptions, never as forecast income.
# ============================================================

library(data.table)
library(ggplot2)
library(scales)

# ---- Cost assumptions (client-provided, all AUD) -----------------------------
FITOUT      <- c(`1` = 15000, `2` = 22000, `3` = 30000)  # furniture, appliances, styling
LAUNCH      <- 1000                          # photography and listing setup
BOND_WEEKS  <- 4                             # refundable, but ties up cash
UTILITIES   <- 4000                          # power, water, internet per year
CONSUMABLES <- 2000                          # linen, amenities per year
INSURANCE   <- 1500
TOOLS       <- 900                           # dynamic pricing, channel manager
HOST_FEE    <- 0.03                          # split-fee; 15.5% host-only scenario
MIN_LISTINGS <- 50                           # comparables required per segment

APARTMENT_TYPES <- c("Entire rental unit", "Entire condo",
                     "Entire serviced apartment", "Entire loft")

listings <- readRDS("data/processed/listings_clean.rds")

# ---- Scope and segment eligibility -------------------------------------------

# Scope is set by the rent data. DFFH publishes four series - 1BR flat, 2BR flat,
# 2BR house, 3BR house. One-bedroom houses have no series of their own, so their
# rent is derived below from the 2BR-house median scaled by the same LGA's own
# one-to-two-bedroom step in the flat series (median step 0.78 across 52 LGAs).
# Three-bedroom apartments are dropped outright: deriving them would need a
# dwelling-type step rather than a bedroom step, on a much smaller base.
RENT_SERIES <- c("1BR flat", "2BR flat", "2BR house", "3BR house", "1BR house")

scoped <- listings[room_type == "Entire home/apt" & bedrooms %in% 1:3]
scoped[, dwelling_class := fifelse(property_type %in% APARTMENT_TYPES,
                                   "apartment", "house")]
scoped[, rent_series := fifelse(dwelling_class == "apartment",
                                paste0(bedrooms, "BR flat"),
                                paste0(bedrooms, "BR house"))]

excluded <- scoped[!rent_series %in% RENT_SERIES]
cat(sprintf("Excluded, rent not derivable: %s listings (%s)\n",
            comma(nrow(excluded)),
            paste(sort(unique(excluded$rent_series)), collapse = ", ")))
scoped <- scoped[rent_series %in% RENT_SERIES]

eligible <- scoped[, .(n_scoped = .N),
                   by = .(lga = neighbourhood_cleansed, bedrooms, dwelling_class,
                          rent_series)][n_scoped >= MIN_LISTINGS]

cat(sprintf("Funnel: %s raw -> %s with an official rent series -> %d segments (%d LGAs)\n",
            comma(nrow(listings)), comma(nrow(scoped)), nrow(eligible),
            uniqueN(eligible$lga)))

# Revenue percentiles use the active, priced subset: a listing with no recent
# activity carries no information about what the segment can earn.
revenue <- scoped[number_of_reviews_ltm > 0 & priced == TRUE &
                  !is.na(estimated_revenue_l365d),
                  .(n_active_priced = .N,
                    p50_revenue = quantile(estimated_revenue_l365d, 0.50),
                    p75_revenue = quantile(estimated_revenue_l365d, 0.75),
                    p90_revenue = quantile(estimated_revenue_l365d, 0.90)),
                  by = .(lga = neighbourhood_cleansed, bedrooms, dwelling_class)]

seg <- merge(eligible, revenue, by = c("lga", "bedrooms", "dwelling_class"),
             all.x = TRUE)

# ---- Attach official rents ---------------------------------------------------

rents <- fread("data/external/dffh_median_rents_sep2025.csv")

# Inside Airbnb still uses the LGA's former name
seg[, lga_official := fifelse(lga == "Moreland", "Merri-bek", lga)]

# Derived 1BR-house rents. DFFH publishes no 1BR-house series, so the rent is
# the LGA's 2BR-house median scaled down by a one-to-two-bedroom step.
#
# The step is observable only for flats, and flats are not houses: comparing the
# two-to-three-bedroom step where BOTH are published shows flats rise more per
# bedroom than houses (median 1.20 vs 1.15, higher in 40 of 51 LGAs, paired
# t = 3.4). Applying a flat step to a house therefore understates the house rent
# and flatters ROI. The flat step is calibrated by the house-to-flat ratio
# measured at the two-to-three step, then clipped to its interquartile range.
# Steps are estimated from the raw September 2025 medians, not the projected
# ones: each series is projected by its own growth rate, which would distort the
# ratios between series. The projected 2BR-house rent is what the step is
# applied to.
raw <- dcast(rents[dwelling %in% c("1BR flat", "2BR flat", "3BR flat",
                                   "2BR house", "3BR house")],
             lga ~ dwelling, value.var = "median_weekly_rent")
setnames(raw, make.names(names(raw)))
proj <- rents[dwelling == "2BR house", .(lga, house_2br_projected = uplifted_to_jun2026)]

cal <- raw[!is.na(X2BR.flat) & !is.na(X3BR.flat) &
           !is.na(X2BR.house) & !is.na(X3BR.house)]
cal[, ratio := (X2BR.house / X3BR.house) / (X2BR.flat / X3BR.flat)]
CALIB <- median(cal$ratio)
cat(sprintf("Dwelling-type calibration: %.3f (median across %d LGAs, %d above 1)\n",
            CALIB, nrow(cal), sum(cal$ratio > 1)))

steps <- merge(raw[!is.na(X1BR.flat) & !is.na(X2BR.flat)], proj, by = "lga")
steps[, step_raw := (X1BR.flat / X2BR.flat) * CALIB]
STEP_LO <- quantile(steps$step_raw, 0.25)
STEP_HI <- quantile(steps$step_raw, 0.75)
steps[, step_used := pmin(pmax(step_raw, STEP_LO), STEP_HI)]
steps[, derived := round(house_2br_projected * step_used)]
cat(sprintf("Calibrated bedroom step: median %.3f, clipped to %.3f-%.3f, %d LGAs\n",
            median(steps$step_raw), STEP_LO, STEP_HI, nrow(steps)))

rent_lookup <- rbind(
  rents[, .(lga_official = lga, rent_series = dwelling,
            weekly_rent = uplifted_to_jun2026, rent_derived = FALSE)],
  steps[, .(lga_official = lga, rent_series = "1BR house",
            weekly_rent = derived, rent_derived = TRUE)]
)

seg <- merge(seg, rent_lookup, by = c("lga_official", "rent_series"), all.x = TRUE)

unmatched <- seg[is.na(weekly_rent), .N]
cat(sprintf("Segments matched to an official rent series: %d of %d\n",
            nrow(seg) - unmatched, nrow(seg)))

# ---- First-year cash-on-cash ROI ---------------------------------------------
#
#   upfront cash  = fit-out + bond + launch      (reserve held separately)
#   annual cost   = rent + utilities + consumables + insurance + tools
#   ROI           = (revenue net of host fee - annual cost) / upfront cash

seg[, upfront_cash := FITOUT[as.character(bedrooms)] + weekly_rent * BOND_WEEKS + LAUNCH]
OPERATING <- UTILITIES + CONSUMABLES + INSURANCE + TOOLS
seg[, annual_cost  := weekly_rent * 52 + OPERATING]

# Absolute annual cash matters alongside the ratio: cash-on-cash ROI has a
# denominator the operator controls, so a cheaper fit-out can rank above a
# segment that simply earns more. Both are reported and both are used.
seg[, net_cash_p50 := round(p50_revenue * (1 - HOST_FEE) - annual_cost)]
seg[, net_cash_p75 := round(p75_revenue * (1 - HOST_FEE) - annual_cost)]
seg[, net_cash_p90 := round(p90_revenue * (1 - HOST_FEE) - annual_cost)]
seg[, roi_at_p50 := round(100 * net_cash_p50 / upfront_cash)]
seg[, roi_at_p75 := round(100 * net_cash_p75 / upfront_cash)]
seg[, roi_at_p90 := round(100 * net_cash_p90 / upfront_cash)]

# How good does the operator have to be? Owners face a different sum: no rent,
# only the long-let income they give up.
seg[, owner_uplift_p75 := round(p75_revenue * (1 - HOST_FEE) - OPERATING - weekly_rent * 52)]
seg[, owner_uplift_p90 := round(p90_revenue * (1 - HOST_FEE) - OPERATING - weekly_rent * 52)]
# The main screen covers the four configurations DFFH publishes a rent for, so
# no segment depends on a derived cost. 1BR houses use a derived rent and are
# marked for sensitivity analysis instead.
seg[, dffh_published := !(dwelling_class == "house" & bedrooms == 1)]

seg[, zone := fifelse(is.na(roi_at_p75), "no revenue data",
              fifelse(roi_at_p75 >= 50, "viable (>=50%)",
              fifelse(roi_at_p75 >= 0,  "marginal (0-50%)", "below break-even")))]

cat("\nSegments by zone, at P75 performance (all screened):\n")
print(seg[, .N, by = zone][order(-N)])
cat("\nMain screen only (configurations with a published rent):\n")
print(seg[dffh_published == TRUE, .N, by = zone][order(-N)])

# The capital ceiling is a decision, not a fixed constraint, so its consequence
# is priced: what does each extra dollar of per-property capital reach?
cat("\nWhat each per-property capital ceiling reaches (published configurations):\n")
pub <- seg[dffh_published == TRUE & !is.na(roi_at_p75)]
print(rbindlist(lapply(c(20000, 26000, 30000, 36000), function(cap) {
  a <- pub[upfront_cash <= cap]
  data.table(ceiling = cap, reachable = nrow(a), clearing_50 = sum(a$roi_at_p75 >= 50),
             best_net_cash = if (nrow(a)) max(a$net_cash_p75) else NA_integer_)
})))

# The percentile matters more than the segment for apartments, so both are shown.
cat("\nHow much execution is required - segments clearing 50% ROI:\n")
print(seg[, .(segments = .N,
              at_p75 = sum(roi_at_p75 >= 50), at_p90 = sum(roi_at_p90 >= 50),
              owner_better_p75 = sum(owner_uplift_p75 > 0),
              owner_better_p90 = sum(owner_uplift_p90 > 0)),
          by = dwelling_class])

# Ranking by ratio and by dollars is not the same ordering, so both are shown.
cat("\nRatio versus dollars - top 5 by each, all bedroom counts:\n")
rank_cmp <- merge(
  seg[order(-roi_at_p75)][1:5, .(segment = paste(lga, bedrooms, dwelling_class),
                                 by_roi = roi_at_p75, cash = net_cash_p75)],
  seg[order(-net_cash_p75)][1:5, .(segment = paste(lga, bedrooms, dwelling_class),
                                   by_cash = net_cash_p75)],
  by = "segment", all = TRUE)
print(rank_cmp[order(-by_cash)])

cat("\nScope test - 3-bedroom segments clearing the hurdle (outside client scope):\n")
print(seg[bedrooms == 3 & roi_at_p75 >= 50,
          .(lga, dwelling_class, upfront_cash, net_cash_p75, roi_at_p75)][order(-net_cash_p75)])

setorder(seg, -roi_at_p75, na.last = TRUE)
out <- seg[, .(lga, bedrooms, dwelling_class, n_scoped, n_active_priced,
               rent_series, weekly_rent, rent_derived,
               dffh_published,
               p50_revenue = round(p50_revenue), p75_revenue = round(p75_revenue),
               p90_revenue = round(p90_revenue),
               upfront_cash, annual_cost, net_cash_p50, net_cash_p75, net_cash_p90,
               roi_at_p50, roi_at_p75, roi_at_p90,
               owner_uplift_p75, owner_uplift_p90, zone)]
fwrite(out, "reports/tables/segment_roi_screen.csv")

ranked <- out[!is.na(roi_at_p75)]
cat(sprintf("\nBest: %s %dBR %s at %+d%% ($%s)   Worst: %s %dBR %s at %+d%%\n",
            ranked$lga[1], ranked$bedrooms[1], ranked$dwelling_class[1],
            ranked$roi_at_p75[1], comma(ranked$net_cash_p75[1]),
            ranked$lga[nrow(ranked)], ranked$bedrooms[nrow(ranked)],
            ranked$dwelling_class[nrow(ranked)], ranked$roi_at_p75[nrow(ranked)]))

# ---- Figure: best and worst segments -----------------------------------------

ranked_all <- out[dffh_published == TRUE & !is.na(roi_at_p75)]
plot_dt <- rbind(head(ranked_all, 5), tail(ranked_all, 4))
plot_dt[, label := sprintf("%s %dBR %s", fifelse(lga == "Moreland", "Merri-bek", lga),
                           bedrooms, fifelse(dwelling_class == "house", "hse", "apt"))]
plot_dt[, label := factor(label, levels = rev(label))]
plot_dt[, band := fifelse(roi_at_p75 >= 50, "Viable (>=50%)",
                  fifelse(roi_at_p75 >= 0, "Marginal (0-50%)", "Below break-even"))]

p <- ggplot(plot_dt, aes(roi_at_p75, label, fill = band)) +
  geom_col(width = 0.7) +
  geom_vline(xintercept = 0, colour = "grey40", linewidth = 0.4) +
  geom_text(aes(label = sprintf("%+d%%", roi_at_p75),
                hjust = ifelse(roi_at_p75 < 0, 1.15, -0.15)), size = 3.6) +
  scale_fill_manual(values = c("Viable (>=50%)" = "#2E7D4F",
                               "Marginal (0-50%)" = "#B07C1F",
                               "Below break-even" = "#A6453A")) +
  scale_x_continuous(limits = c(-115, 135), breaks = seq(-100, 120, 40),
                     labels = function(x) paste0(x, "%")) +
  labs(title = "First-year ROI at P75 performance",
       subtitle = sprintf("Best and worst of %d segments with a published rent; P75 is the 75th percentile, not a ceiling",
                          nrow(ranked_all)),
       x = NULL, y = NULL, fill = NULL) +
  theme_minimal(base_size = 12) +
  theme(legend.position = "bottom", panel.grid.major.y = element_blank())
ggsave("reports/figures/10_segment_roi_screen.png", p, width = 9, height = 5, dpi = 150)

cat("Table and figure written.\n")
