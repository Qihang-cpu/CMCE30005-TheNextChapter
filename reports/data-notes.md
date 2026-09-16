# Data notes

The analysis was rerun on 15 September 2026 from the three school-supplied CSV files in `data/raw/`. Cleaning, review reconstruction, modelling and descriptive ranking use the same input hashes. The [scope and provenance record](tables/rq_scope_summary.json) records the sources and full-listing validation results.

## Available data and provenance

| Data object | Unit | Raw records checked |
|---|---|---:|
| Listings | Listing | 25,728 |
| Calendar | Listing-date | 9,390,720 |
| Reviews | Guest review | 1,026,690 |

Listing IDs are unique, with no missing listing or host IDs; there are 14,113 distinct hosts. Calendar and review records have no unmatched listing IDs. The raw listings file already contains 142 listing IDs and two host IDs in scientific notation. Their source text is preserved and canonicalised without floating-point conversion for joins and host partitioning. Digits rounded before delivery cannot be recovered, so successful joins do not establish the identifiers' original precision.

The collection is described as a June 2026 snapshot. Listing scrape dates range from **17 June to 1 July 2026**. Raw review dates contain no invalid dates or dates later than their listing's scrape date. The calendar has 365 unique dates per listing, with no duplicate listing-date keys.

The supplied `number_of_reviews_ltm` field matches raw reviews over the closed interval `[last_scraped - 365 days, last_scraped]` for all 25,728 listings. That interval contains **366 calendar dates**. The primary outcome, `reviews_365d`, is reconstructed over `(last_scraped - 365 days, last_scraped]`, which contains exactly 365 dates. Excluding the extra boundary date removes 352 reviews across 350 listings. It changes one primary analysis listing's classification at the common cutoff. The supplied field remains unchanged for source diagnostics and reconstruction of the supplied financial estimates.

The calendar contains availability and minimum/maximum-stay fields, not nightly prices. Unavailable dates can reflect bookings or host restrictions. Review counts do not directly count bookings or stays.

## Cleaning and missingness

`scripts/01_data_cleaning.R` parses currency, missing values, bathroom descriptions and amenity lists, creates the price eligibility flag and reconstructs `reviews_365d`. It stages processed outputs until all three inputs pass validation, then records their hashes in a cleaning manifest. Key counts in the rebuilt listing table are:

| Variable | Missing |
|---|---:|
| Quoted price and modelled revenue | 6,553 each |
| Bedrooms | 4,679 |
| Overall rating and reviews per month | 4,477 each |
| Location and value ratings | 4,484 each |
| Parsed bathrooms | 26 |
| Minimum nights | 9 |

There are 19,175 non-missing quoted prices, with median **AUD243.67**. The inclusive AUD30–AUD1,500 filter retains 18,927, with median **AUD242.50**; it excludes 6,553 missing prices, 45 below AUD30 and 203 above AUD1,500. The extremes are scope exclusions, not verified data-entry errors.

The raw listings file contains 13 entirely empty fields, including host-response measures and instant-bookability. Model imputers are fitted inside training folds; no external observations are introduced.

## Main cohort and outcome

The main scope uses entire rental units, condos, homes and townhouses with one to three bedrooms, a quoted price of AUD30–1,500 and `first_review <= last_scraped - 365 days` for each listing. This establishes earlier observed review history, not an opening date or uninterrupted operation.

A deterministic hash reserves approximately 20% of hosts for benchmark development. They are excluded from every model training and evaluation sample. Final LGA × class × bedroom cells need at least 50 analysis listings after all restrictions. The resulting analysis has **3,873 listings in 14 cells across 1,726 hosts**, including **334 zero-review listings**.

A separate reference of **906 eligible listings from 426 benchmark hosts** in those same cells gives **P75 = 29.75**. Rounding upward defines the integer event `reviews_365d >= 30`, with **981 analysis listings (25.3292%)** meeting it. The reference attainment share is 227/906, or 25.0552%; integer ties are retained. The threshold is calculated only from reference outcomes and held fixed across segments and sensitivity samples. It is not a whole-market or profitability standard. See [configuration](../config/review_analysis.json), [scope counts](tables/review_scope_summary.csv) and [analysis plan](rq-analysis-plan.md).

Removing the first-review condition leaves 6,675 analysis listings in 22 cells; removing the price restriction while retaining history leaves 5,720 in 19 cells. Benchmark hosts remain excluded and the 50-listing rule is reapplied.

The [model extensions](methodology.md#property-features-and-model-extensions) use the same primary sample, outcome, cutoff and host folds. Additional coordinates, beds and individual amenity indicators come from the supplied listings file; 125 bed counts are missing in the primary cohort and are imputed within training folds. [Extension provenance](tables/rq_extension_provenance.json) records feature definitions, missingness and input hashes.

## Limits of the financial fields

The supplied occupancy estimate matches a review-based formula for all 25,719 comparable records. Revenue matches price multiplied by supplied modelled nights within AUD0.50 for all 19,175 comparable records. These checks preserve the supplied 366-date review field used in that construction. [The supporting diagnostic note](supporting/revenue-analysis.md) explains why these constructed fields are excluded from the primary outcome.

The data do not establish property ownership, lease availability, subletting permission, or actual rental and operating costs. The current workflow uses only the supplied internal data and cannot calculate observed profit. Historic external-rent and ROI work is outside the current analysis.
