# ============================================================
# CMCE30005 Business Analytics Challenge
# Script: 06_segment_roi_screen.R
# Purpose: Preliminary first-year cash-on-cash ROI screen for every
#          eligible LGA x dwelling-class x 1-2-bedroom segment
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

# The client brief is 1-2 bedrooms. 3-bedroom segments are screened alongside as
# a documented scope test, flagged in the output rather than silently included.
scoped <- listings[room_type == "Entire home/apt" & bedrooms %in% 1:3]
scoped[, dwelling_class := fifelse(property_type %in% APARTMENT_TYPES,
                                   "apartment", "house")]

eligible <- scoped[, .(n_scoped = .N),
                   by = .(lga = neighbourhood_cleansed, bedrooms, dwelling_class)
                   ][n_scoped >= MIN_LISTINGS]

cat(sprintf("Funnel: %s raw -> %s scoped 1-3BR entire homes -> %d segments (%d LGAs)\n",
            comma(nrow(listings)), comma(nrow(scoped)), nrow(eligible),
            uniqueN(eligible$lga)))
cat(sprintf("  of which in client scope (1-2BR): %d segments\n",
            nrow(eligible[bedrooms %in% 1:2])))

# Revenue percentiles use the active, priced subset: a listing with no recent
# activity carries no information about what the segment can earn.
revenue <- scoped[number_of_reviews_ltm > 0 & priced == TRUE &
                  !is.na(estimated_revenue_l365d),
                  .(n_active_priced = .N,
                    p50_revenue = quantile(estimated_revenue_l365d, 0.50),
                    p75_revenue = quantile(estimated_revenue_l365d, 0.75)),
                  by = .(lga = neighbourhood_cleansed, bedrooms, dwelling_class)]

seg <- merge(eligible, revenue, by = c("lga", "bedrooms", "dwelling_class"),
             all.x = TRUE)

# ---- Attach official rents ---------------------------------------------------

rents <- fread("data/external/dffh_median_rents_sep2025.csv")

# Inside Airbnb still uses the LGA's former name
seg[, lga_official := fifelse(lga == "Moreland", "Merri-bek", lga)]

# There is no official 1-bedroom-house series, so those segments take the
# 2BR-house rent as a deliberately conservative upper bound.
seg[, rent_series := fifelse(dwelling_class == "apartment", paste0(bedrooms, "BR flat"),
                      fifelse(bedrooms >= 3, "3BR house", "2BR house"))]
seg[, rent_is_upper_bound := dwelling_class == "house" & bedrooms == 1]

seg <- merge(seg, rents[, .(lga_official = lga, rent_series = dwelling,
                            weekly_rent = uplifted_to_jun2026)],
             by = c("lga_official", "rent_series"), all.x = TRUE)

unmatched <- seg[is.na(weekly_rent), .N]
cat(sprintf("Segments matched to an official rent series: %d of %d\n",
            nrow(seg) - unmatched, nrow(seg)))

# ---- First-year cash-on-cash ROI ---------------------------------------------
#
#   upfront cash  = fit-out + bond + launch      (reserve held separately)
#   annual cost   = rent + utilities + consumables + insurance + tools
#   ROI           = (revenue net of host fee - annual cost) / upfront cash

seg[, upfront_cash := FITOUT[as.character(bedrooms)] + weekly_rent * BOND_WEEKS + LAUNCH]
seg[, annual_cost  := weekly_rent * 52 + UTILITIES + CONSUMABLES + INSURANCE + TOOLS]

# Absolute annual cash matters alongside the ratio: cash-on-cash ROI has a
# denominator the operator controls, so a cheaper fit-out can rank above a
# segment that simply earns more. Both are reported and both are used.
seg[, net_cash_p50 := round(p50_revenue * (1 - HOST_FEE) - annual_cost)]
seg[, net_cash_p75 := round(p75_revenue * (1 - HOST_FEE) - annual_cost)]
seg[, roi_at_p50 := round(100 * net_cash_p50 / upfront_cash)]
seg[, roi_at_p75 := round(100 * net_cash_p75 / upfront_cash)]
seg[, in_client_scope := bedrooms %in% 1:2]

seg[, zone := fifelse(is.na(roi_at_p75), "no revenue data",
              fifelse(roi_at_p75 >= 50, "viable (>=50%)",
              fifelse(roi_at_p75 >= 0,  "marginal (0-50%)", "below break-even")))]

cat("\nSegments by zone, at P75 performance (client scope, 1-2BR):\n")
print(seg[in_client_scope == TRUE, .N, by = zone][order(-N)])

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
out <- seg[, .(lga, bedrooms, dwelling_class, in_client_scope, n_scoped, n_active_priced,
               weekly_rent, rent_is_upper_bound,
               p50_revenue = round(p50_revenue), p75_revenue = round(p75_revenue),
               upfront_cash, annual_cost, net_cash_p50, net_cash_p75,
               roi_at_p50, roi_at_p75, zone)]
fwrite(out, "reports/tables/segment_roi_screen.csv")

ranked <- out[!is.na(roi_at_p75)]
cat(sprintf("\nBest: %s %dBR %s at %+d%% ($%s)   Worst: %s %dBR %s at %+d%%\n",
            ranked$lga[1], ranked$bedrooms[1], ranked$dwelling_class[1],
            ranked$roi_at_p75[1], comma(ranked$net_cash_p75[1]),
            ranked$lga[nrow(ranked)], ranked$bedrooms[nrow(ranked)],
            ranked$dwelling_class[nrow(ranked)], ranked$roi_at_p75[nrow(ranked)]))

# ---- Figure: best and worst segments -----------------------------------------

in_scope <- out[in_client_scope == TRUE & !is.na(roi_at_p75)]
plot_dt <- rbind(head(in_scope, 5), tail(in_scope, 4))
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
  scale_x_continuous(limits = c(-110, 90), breaks = seq(-100, 80, 40),
                     labels = function(x) paste0(x, "%")) +
  labs(title = "First-year ROI at P75 performance",
       subtitle = sprintf("Best and worst of %d in-scope 1-2BR segments; P75 is the 75th percentile, not a ceiling",
                          nrow(in_scope)),
       x = NULL, y = NULL, fill = NULL) +
  theme_minimal(base_size = 12) +
  theme(legend.position = "bottom", panel.grid.major.y = element_blank())
ggsave("reports/figures/10_segment_roi_screen.png", p, width = 9, height = 5, dpi = 150)

cat("Table and figure written.\n")
