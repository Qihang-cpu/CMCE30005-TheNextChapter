# ============================================================
# CMCE30005 Business Analytics Challenge
# Script: 05_rent_data.R
# Purpose: Download official Victorian median rents and project them
#          forward to the June 2026 entry date
# Author: TheNextChapter (Group 2)
# Date: 20 August 2026
# ============================================================
#
# Source : Homes Victoria Rental Report, quarterly median rents by LGA
#          https://www.dffh.vic.gov.au/publications/rental-report
# Output : data/external/dffh_median_rents_sep2025.csv
#
# The latest published edition is the September 2025 quarter, three quarters
# behind our June 2026 entry date. Each LGA x dwelling series is projected
# forward using its own year-on-year growth, clipped to 0-8% so that thin
# markets with volatile medians cannot swing the cost side of the screen.
# ============================================================

library(data.table)
library(readxl)

dir.create("data/external", showWarnings = FALSE, recursive = TRUE)

URL <- paste0("https://www.dffh.vic.gov.au/",
              "quarterly-median-rents-local-government-area-september-quarter-2025-excel")
XLSX <- "data/external/dffh_quarterly_median_rents.xlsx"

GROWTH_CAP <- 0.08      # thin-market noise guard
QUARTERS_AHEAD <- 3     # Sep 2025 -> Jun 2026

if (!file.exists(XLSX)) {
  cat("Downloading DFFH rental report...\n")
  download.file(URL, XLSX, mode = "wb", quiet = TRUE)
}
cat("Workbook:", XLSX, "\n")

# Sheets are one per dwelling type. Row 2 holds paired quarter labels and row 3
# alternates Count / Median, so the median columns are every second column.
read_sheet <- function(sheet, label) {
  raw <- as.data.table(read_excel(XLSX, sheet = sheet, col_names = FALSE,
                                  .name_repair = "minimal"))
  quarters <- unlist(raw[2], use.names = FALSE)
  kinds    <- unlist(raw[3], use.names = FALSE)
  med_cols <- which(kinds == "Median")
  latest   <- med_cols[length(med_cols)]
  year_ago <- med_cols[length(med_cols) - 4]      # four quarters back

  body <- raw[4:.N]
  num <- function(x) suppressWarnings(as.numeric(gsub("[$,]", "", x)))
  data.table(lga      = unlist(body[, 2], use.names = FALSE),
             dwelling = label,
             quarter  = quarters[latest],
             median_weekly_rent = num(unlist(body[, ..latest], use.names = FALSE)),
             quarter_year_ago   = quarters[year_ago],
             median_year_ago    = num(unlist(body[, ..year_ago], use.names = FALSE)))
}

rents <- rbindlist(list(
  read_sheet("1br flat",  "1BR flat"),
  read_sheet("2br Flat",  "2BR flat"),
  read_sheet("2br House", "2BR house"),
  read_sheet("3br House", "3BR house")
))
rents <- rents[!is.na(lga) & !is.na(median_weekly_rent)]

rents[, yoy_growth := median_weekly_rent / median_year_ago - 1]
rents[, growth_used := pmin(pmax(fifelse(is.na(yoy_growth), 0, yoy_growth), 0), GROWTH_CAP)]
rents[, uplifted_to_jun2026 :=
        round(median_weekly_rent * (1 + growth_used) ^ (QUARTERS_AHEAD / 4))]

# Every LGA the report publishes is exported; the segment screen selects what it
# needs. Inside Airbnb still labels Merri-bek as Moreland, and that mapping is
# applied where the two sources are joined, not here.
out <- copy(rents)
setorder(out, lga, dwelling)

cat(sprintf("LGAs: %d  ·  dwelling types: %d  ·  rows: %d  (quarter: %s)\n",
            uniqueN(out$lga), uniqueN(out$dwelling), nrow(out), out$quarter[1]))

fwrite(out[, .(lga, dwelling, quarter, median_weekly_rent, quarter_year_ago,
               median_year_ago, yoy_growth_pct = round(100 * yoy_growth, 1),
               growth_used_pct = round(100 * growth_used, 1), uplifted_to_jun2026)],
       "data/external/dffh_median_rents_sep2025.csv")

cat("Written to data/external/dffh_median_rents_sep2025.csv\n")
