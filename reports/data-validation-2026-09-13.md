# Data validation — 13 September 2026

**Result: the current interim report's main statistics and reported models reproduce from the saved processed data. End-to-end validation from the original CSV files remains incomplete because the three local raw-data links are broken.** No raw or processed data, analysis scripts, or historical reports were changed during this audit.

## Scope and procedure

The audit checked `data/processed/*.rds`, the current interim report, README, analysis scripts, committed result tables, and the older `CMCE30005_Interim_Report_Group2.md` and `.docx` in the parent course directory. Scripts 03, 04 and 07 were rerun in an isolated temporary directory from the saved `listings_clean.rds`. Thirteen regenerated CSV tables matched the committed tables at a numerical tolerance of 1e-10. Saved price-model coefficients reproduced, and the activity models' host-clustered covariance calculation matched `sandwich::vcovCL(type="HC1", cadjust=TRUE)`.

The audit used no external market data. [Machine-readable integrity checks](validation/processed-integrity-2026-09-13.json) record the additional checks on saved data. Matching saved outputs establishes computational consistency; it does not establish that a listing's quoted price, estimated occupancy or estimated revenue is a verified transaction.

## Verified statistics

| Quantity | Recomputed result and denominator |
|---|---|
| Listings | 25,728 records and 25,728 distinct, non-missing listing IDs |
| Hosts | 14,113 distinct hosts; no missing host IDs |
| Calendar records | 9,390,720, summed from the saved monthly aggregate |
| Reviews | 1,026,690 in both monthly and listing-level saved aggregates |
| Review joins | No orphan listing IDs; per-listing review totals and latest dates match the saved listings |
| Missing price / estimated revenue | 6,553 each; missingness patterns coincide |
| Non-missing quoted prices | 19,175; median AUD243.67, mean AUD317.65037 |
| AUD30–1,500 price sample | 18,927; filter flags have zero discrepancies |
| Excluded prices | 6,553 missing + 45 below AUD30 + 203 above AUD1,500 = 6,801 excluded |
| Missing bedrooms | 4,679 |
| No review in preceding year | Retained sample: 4,487/18,927 = 23.7069%; excluded sample: 5,574/6,801 = 81.9585% |
| Entire homes | 18,829/25,728 = 73.2% of the full sample |
| Entire-home median estimated annual revenue | AUD14,664; 14,278 listings in the price-filtered sample |
| Private-room median estimated annual revenue | AUD936; 4,411 listings in the price-filtered sample |
| Log quoted-price model | n = 12,223; adjusted R² = 0.5580295275 |
| Log recent-review-count model | n = 12,648; adjusted R² = 0.4109740370; 6,250 host clusters |

Both R² values describe in-sample fit in log units. Neither is held-out predictive accuracy. Predictive classification remains planned.

For 25,719 records with all required inputs, estimated occupied nights equal `min(reviews_ltm × 2 × max(minimum_nights, 3), 255)` with zero mismatches. The nine missing minimum-stay records cannot be checked against this formula. For all 19,175 comparable revenue records, `quoted price × estimated occupied nights` matches estimated annual revenue within AUD0.50, allowing floating-point tolerance. Consequently, these fields cannot establish actual occupancy, receipts or profit.

## Issues found

1. **Original CSV files unavailable in this run.** `data/raw/` contains three symlinks to `../Project` in the course directory, but their targets currently do not exist. Searches of the course directory, Desktop, Documents, Downloads and Spotlight did not locate another copy. The original files are required to recheck parsing, original-row duplicates, calendar date coverage, raw-to-clean transformations and the thirteen reportedly empty original columns. The aggregate counts above are not a fresh count of raw CSV records.

2. **The derived 90-day availability window has an endpoint error.** `scripts/01_data_cleaning.R:124` selects `date <= min(date) + 90`, including the start day and potentially 90 subsequent days. One saved proportion is exactly 68/91; 25,254 saved proportions multiplied by 91 are integers, compared with 8,266 multiplied by 90. The intended horizon and differing listing start dates should be checked against the original calendar before correction. This derived file is not used by scripts 02, 03, 04 or 07, so it does not alter the interim report's main statistics or model fits.

3. **Several older documents have incorrect labels or denominators.** `reports/methodology.md` incorrectly calls all 248 out-of-range prices high-price outliers; the correct split is 203 high and 45 low. `reports/descriptive-analytics.md` says all price statistics use the filtered sample, whereas its overall numeric table uses all non-missing prices (median AUD243.67); the filtered sample's median is AUD242.50. General rating is missing for 4,477 listings, but location and value ratings are each missing for 4,484, so the old blanket statement about all rating fields is incorrect. The current interim report avoids these mistakes.

4. **Some historical interpretation exceeds the evidence.** Older prose calls modelled nights “booked nights” and treats a cross-sectional price–review relationship as evidence of an optimal price. Neither follows from these data. `reports/revenue-analysis.md` also reverses the price-filter selection effect in one sentence: retained listings have a higher recent-review activity rate (76.3%) than the full sample (60.9%), not a lower rate.

5. **The fixed date and seasonality assumptions need review.** Script 04 uses 16 June 2026 as its date anchor, but 66 saved listings have a last review after that date; the latest saved review date is 28 June. Two first reviews also follow that anchor. Its active-listing age summary includes three unclassified records with zero or negative age. Moreover, time since first review is not actual time since listing creation. Script 02 includes June 2026 in a period described as three full years, despite evidence that the last June is incomplete; the old June seasonality index should not be read as a clean seasonal effect. The current interim report does not quote that index or claim a single-day scrape.

## Two report versions must not be confused

The course-directory `CMCE30005_Interim_Report_Group2.md` and `.docx` are the **older ROI version**. They combine external DFFH rent data with operating-cost assumptions and a 50% cash-return hurdle, and propose predicting upper-quartile review activity. They do not meet the current internal-data-only scope.

Their principal ROI counts do match the saved scenario table: 57 segments comprise 52 with published rent categories and five with derived rents. The 52-segment subset has two above the 50% hurdle, five positive but below it and 45 negative; the complete 57-segment set has three, seven and 47 respectively. This is consistency with a scenario model, not verification of real profitability. The old wording that adjusted R² of 0.558 explains dollar-price variation should also refer to log quoted price.

The current submission is [interim-project-report.md](interim-project-report.md), with its linked Word/PDF and matching README. It uses internal estimated-revenue comparisons and treats the upper quartile as a research benchmark, not a profitability cutoff.

## Outstanding verification

Restore the three original school-supplied CSV files or identify their new local location, then compare them with the saved clean data. Only then can the raw-to-clean pipeline be signed off. The availability-window and historical prose issues above are recorded findings, not silently applied fixes.
