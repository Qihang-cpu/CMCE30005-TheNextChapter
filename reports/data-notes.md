# Data notes

The school-supplied Melbourne Airbnb data are represented locally by saved processed files. The three paths in `data/raw/` currently point to unavailable original CSV files. The latest checks therefore verify **processed data → analysis outputs**, not raw data → cleaned data. Restoring the school's original files is necessary before making an end-to-end reproducibility claim.

## Available data and provenance

| Data object | Unit | Records supported by saved files |
|---|---|---:|
| Listings | Listing | 25,728 |
| Calendar aggregates | Listing-date records aggregated by month | 9,390,720 |
| Review aggregates | Reviews aggregated by month and listing | 1,026,690 |

The saved listing IDs are unique, with no missing IDs or host IDs; there are 14,113 distinct hosts. Saved aggregate joins have no unmatched listing IDs. These checks do not prove that every original identifier retained its full precision: 142 saved listing IDs use scientific notation, and their original spelling cannot be checked without the source files.

The collection is described as a June 2026 snapshot. Saved reviews extend through **28 June 2026**, later than the 16 June date previously used in some scripts. The actual scrape date for each listing and the precise trailing-review window require raw-source verification. Script 04 uses the latest saved review date as its history reference; this is an analytical reference date, not a claim about the scrape date.

The calendar contains availability and minimum/maximum-stay fields, not nightly prices. Unavailable dates can reflect bookings or host restrictions. Review counts do not directly count bookings or stays.

## Cleaning and missingness

`scripts/01_data_cleaning.R` specifies numeric price parsing, missing-value handling, bathroom-text parsing, amenity counts and the price eligibility flag. These transformations cannot currently be rerun against the original files. Key counts in the saved listing table are:

| Variable | Missing |
|---|---:|
| Quoted price and modelled revenue | 6,553 each |
| Bedrooms | 4,679 |
| Overall rating and reviews per month | 4,477 each |
| Location and value ratings | 4,484 each |
| Parsed bathrooms | 26 |
| Minimum nights | 9 |

There are 19,175 non-missing quoted prices, with median **AUD243.67**. The inclusive AUD30–AUD1,500 filter retains 18,927, with median **AUD242.50**; it excludes 6,553 missing prices, 45 below AUD30 and 203 above AUD1,500. The extremes are scope exclusions, not verified data-entry errors.

The earlier source inventory recorded 13 entirely empty fields, including host-response measures and instant-bookability. That inventory remains unverified against the currently unavailable raw files. No replacement values or external observations are introduced into the current analysis.

## Main cohort and outcome

The main scope uses entire rental units, condos, homes and townhouses with one to three bedrooms, a quoted price of AUD30–1,500 and first review on or before 1 June 2025. The 1 June 2026 reference defines a review-history eligibility convention. It is not a verified scrape or opening date.

A deterministic hash reserves approximately 20% of hosts for benchmark development. They are excluded from every model training and evaluation sample. Final LGA × class × bedroom cells need at least 50 analysis listings after all restrictions. The resulting analysis has **3,810 listings in 14 cells across 1,699 hosts**, including **333 zero-review listings**.

A separate reference of **899 eligible listings from 424 benchmark hosts** in those same cells gives **P75 = 30**. The event is `number_of_reviews_ltm >= 30`, with **957 analysis listings (25.1181%)** meeting it. The threshold is calculated only from reference outcomes and held fixed across segments and sensitivity samples. It is not a whole-market or profitability standard. See [configuration](../config/review_analysis.json), [scope counts](tables/review_scope_summary.csv) and [analysis plan](rq-analysis-plan.md).

Removing the first-review condition leaves 6,675 analysis listings in 22 cells; removing the price restriction while retaining history leaves 5,647 in 19 cells. Benchmark hosts remain excluded and the 50-listing rule is reapplied. First review measures observed history, not uninterrupted operation.

## Limits of the financial fields

The saved occupancy estimate matches a review-based formula for all 25,719 comparable records. Revenue matches price multiplied by supplied modelled nights within AUD0.50 for all 19,175 comparable records. [The supporting diagnostic note](revenue-analysis.md) explains why these constructed fields are excluded from the primary outcome.

The data do not establish property ownership, lease availability, subletting permission, or actual rental and operating costs. The current workflow uses only the supplied internal data and cannot calculate observed profit. Historic external-rent and ROI work is outside the current analysis.
