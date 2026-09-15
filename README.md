# Melbourne Airbnb Review Activity

Interim Project Report

CMCE30005 Business Analytics Challenge | Semester 2 2026 | TheNextChapter Group 2

Eric Huang, Loc Le, Qihang Sun and Maksym Xu

Repository: [Qihang-cpu/CMCE30005-TheNextChapter](https://github.com/Qihang-cpu/CMCE30005-TheNextChapter/tree/interim-report-2026-09-13)

Report body including table: 1,206 words | Updated 15 September 2026

## Introduction

A prospective operator considering several Melbourne Airbnb properties must compare locations and dwelling configurations before committing to leases, furnishings and launch costs. These choices are difficult to reverse and an unsuitable property can tie up limited capital. In this report, location is measured by Local Government Area (LGA), meaning a municipal area within Greater Melbourne. The business therefore needs a consistent way to compare similar properties rather than relying on nightly price alone.

The school-supplied Inside Airbnb snapshot shows substantial variation in quoted prices and guest reviews. We combine descriptive comparisons with predictive modelling to assess which market segments are associated with stronger review activity. Reviews are observable and provide a limited indicator of guest activity, but they are not bookings or profit. Because the supplied data contain neither actual rent nor operating costs, this interim analysis supports preliminary market screening rather than a financial investment recommendation.

## Problem Definition and Objectives

Our research question is: Among established standard entire-home listings with one to three bedrooms in Greater Melbourne, which LGA, dwelling-class and bedroom-count segments with at least 50 eligible analysis listings have the highest mean out-of-sample predicted probability of meeting a common upper-quartile review-count benchmark over the 365 days ending on each listing’s scrape date?

The descriptive objective is to compare review distributions, observed benchmark attainment and property attributes across eligible segments. The predictive objective is to test whether information available about a property's location, dwelling configuration, capacity, bathrooms and amenities can distinguish higher-activity listings when evaluated on hosts excluded from model training.

Established means the first observed review occurred at least 365 days before that listing’s scrape date. This indicates review history, not an opening date or continuous operation. We retain entire rental units, condos, homes and townhouses with one to three bedrooms and quoted prices of AUD30–1,500. Units and condos form the apartment class; homes and townhouses form the house class. These categories identify comparable residential stock without proving lease or subletting availability. Each reported segment needs at least 50 analysis listings after all restrictions.

A separate group of reference hosts supplies one common upper-quartile benchmark. Its numerical value is calculated from the supplied data, rather than fixed in the research question. It is neither a whole-market standard nor a profitability threshold.

## Data Description

The school’s June 2026 files contain 25,728 listings, 9,390,720 calendar records and 1,026,690 reviews. The 90 listing variables cover identifiers, LGA, property type, capacity, bathrooms, amenities, price, minimum stay and reviews. Scrape dates range from 17 June to 1 July 2026. Calendar availability cannot establish bookings and the calendar contains no prices.

Cleaning converts currency strings, standardises missing values, extracts bathroom counts and parses amenity lists without splitting names containing commas. Quoted price is missing for 6,553 listings and bedrooms for 4,679. Median price is AUD243.67 across 19,175 non-missing records. The price restriction supports comparability; it does not establish that excluded prices are errors. Source identifier text is preserved because scientific notation can already contain irrecoverable rounding.

The final reference group’s P75 is 29.75, rounded upward to a 30-review event. The separate analysis group contains 3,873 listings from 1,726 hosts across 14 segments, including 334 zero-review listings. Of these, 981 meet the benchmark (25.33%); ties are retained. Median amenity counts are 44 among listings meeting the benchmark and 43 below it, while median guest capacity is four in both groups. These pooled differences offer limited separation.

Full-source checks revealed a one-day boundary difference: the supplied recent-review field matches the inclusive interval from scrape date minus 365 days through scrape date, covering 366 dates. We retain that field and derive reviews_365d over the strict 365-day interval, excluding its start boundary. This removes 352 reviews across 350 listings and changes one analysis listing’s target label. Independent reconstruction agrees with every derived count; original total-review counts and first/last review dates also match.

Table 1. Sample filters and separate host branches

| Stage | Listings | Hosts | Role |
| --- | --- | --- | --- |
| Raw listings | 25,728 | 14,113 | Source snapshot |
| After scope filters | 6,891 | 3,488 | Before host partition |
| Analysis before support | 5,549 | 2,809 | Before 50-listing rule |
| Final analysis | 3,873 | 1,726 | 14 supported segments |
| Reference before support | 1,342 | 679 | Separate benchmark hosts |
| Final reference | 906 | 426 | Same 14 segments; defines P75 |

## Methodology and Analytical Approach

A fixed hash of host identifiers reserves approximately 20% of hosts for benchmark development. These hosts enter no model training, evaluation or sensitivity analysis. After removing them, analysis segments must contain at least 50 listings. Eligible reference listings in those supported segments supply one pooled P75, using linear interpolation and upward integer rounding. That cutoff remains fixed across segments and sensitivity samples.

Descriptive tables report listing and distinct-host counts, review quantiles, observed attainment and attribute profiles. Pointwise 90% intervals resample hosts to account for properties sharing an operator. Wider dwelling definitions and unrestricted review histories assess how the chosen scope affects comparisons.

Baseline logistic regression and random forest use LGA, dwelling–bedroom configuration, capacity, bathrooms and amenity counts. We then compare six fixed extensions adding coordinates, beds and nine specific facilities, including pool, parking and kitchen indicators; these also test histogram gradient boosting. These comparisons retain the same 3,873 listings and five host-disjoint outer folds. Preprocessing is learned within training folds. Ratings, review-derived predictors and host badges are excluded; price and minimum stay enter labelled operating-controls variants.

ROC-AUC and average precision assess discrimination; Brier score and calibration assess probability quality against a training-prevalence baseline. Two boosting variants fit sigmoid calibration using three host-disjoint folds inside each outer training set. Thus no outer validation outcome enters calibration. R supports cleaning and descriptive analysis; Python and scikit-learn support modelling.

## Analysis Plan and Progress to Date

The complete raw-data workflow and independent checks now agree on review counts, samples, benchmark and baseline metrics. Baseline logistic AUC is 0.573 and forest AUC is 0.560. Detailed property features improve forest AUC to 0.640, average precision to 0.350 and Brier score to 0.181, versus baseline logistic Brier 0.189. Its ten-bin calibration error is 1.63 percentage points. Boosting achieves AUC 0.647 but Brier 0.182. We provisionally prefer the enhanced forest for probability ranking because it has the lowest Brier score among the property-only extensions; discrimination remains moderate.

The enhanced forest ranks Melbourne three-bedroom apartments first: mean probability 34.4%, observed attainment 36.6%, and 306 listings. Its conditional 95% host-bootstrap interval is 33.0–35.8%; fixed scores and cutoff omit model-refitting and benchmark-estimation uncertainty. Removing the history restriction gives 6,675 analysis listings; removing the price filter gives 5,720. Adding current price and minimum stay to enhanced boosting raises AUC to 0.749. These contemporaneous settings provide useful context but do not establish a causal effect or a pre-opening forecast. Sigmoid calibration does not improve every metric.

All six extensions are reported. Their comparison follows baseline inspection, so model preference is exploratory and there is no untouched final test. Next steps are repeated host partitions, model selection within nested grouped validation, and ranking intervals with model refitting. Findings describe existing listings’ preceding-year review activity, not future income or profitability. The README reproduces this report and links the code, validation and outputs.

## References

Inside Airbnb. (2026). Melbourne listings, calendar and reviews [June 2026 dataset supplied through CMCE30005 LMS].

Scikit-learn developers. (n.d.). *Cross-validation* and *Probability calibration*. [Grouped validation](https://scikit-learn.org/stable/modules/cross_validation.html#cross-validation-iterators-for-grouped-data); [Calibration guidance](https://scikit-learn.org/stable/modules/calibration.html).


## Project files

- [Interim report Word](reports/Interim_Project_Report.docx) · [PDF](reports/Interim_Project_Report.pdf)
- [Research design](reports/rq-analysis-plan.md) · [Methodology](reports/methodology.md) · [Data notes](reports/data-notes.md)
- [Raw-data validation](reports/data-validation-2026-09-15.md) · [Machine-readable checks](reports/validation/raw-rerun-2026-09-15.json)
- [Sample funnel](reports/tables/rq_sample_funnel.csv) · [Descriptive segments](reports/tables/segment_ladder.csv)
- [Baseline metrics](reports/tables/rq_model_metrics.json) · [Extension comparison](reports/tables/rq_extension_metrics.csv) · [Extension rankings](reports/tables/rq_extension_ranking.csv)

### Reproducing the analysis

Place the original school-supplied `listings_airbnb.csv`, `calendar_airbnb.csv` and `reviews_airbnb.csv` in `data/raw/`. The 15 September run used these restored original files; their hashes are recorded in the validation output. Raw data and listing-level predictions are excluded from Git.

Install the R packages listed in `scripts/00_packages.R`, then run the following from the project root:

```sh
Rscript scripts/00_packages.R
Rscript scripts/01_data_cleaning.R
Rscript scripts/02_exploratory_analysis.R
Rscript scripts/03_price_model.R
Rscript scripts/04_revenue_analysis.R
Rscript scripts/07_descriptive_analytics.R
python -m pip install -r requirements-analysis.txt
python scripts/rq_scope_feasibility.py
Rscript scripts/08_peer_ranking.R
Rscript scripts/09_probability_calibration.R
python scripts/10_model_extensions.py
```

Script 01 stages cleaned files until all input checks pass and records their hashes. The supplied `number_of_reviews_ltm` matches a 366-date inclusive window; it is preserved. The primary `reviews_365d` outcome is reconstructed over `(last_scraped − 365 days, last_scraped]`. The Python workflow independently checks all source review counts and publishes results only after every baseline model finishes. Script 08 requires matching input and configuration hashes before ranking. Script 10 holds the primary sample, outcomes and outer host folds fixed while evaluating all six extensions in separate outputs.

The main screening model provisionally uses detailed property features and random forest. The original baselines remain available for comparison. Price/revenue scripts are supporting analyses of the supplied fields; they do not establish profit. All numerical inputs come from the school data. References concern methodology, and no external market or rent observations are added.

The shared scope and benchmark rules are in [config/review_analysis.json](config/review_analysis.json). The reference-host P75 is calculated once and its integer cutoff is held fixed across all comparisons; the RQ does not contain a fixed review count. Original identifiers, host-fold assignments and detailed review comparisons remain in ignored `data/processed/` files.

Run the regression checks separately; they use temporary synthetic data and do not overwrite report results:

```sh
python -m unittest discover -s tests -v
Rscript tests/test_cleaning_consistency.R
Rscript tests/test_peer_inputs.R
```

The dated 13–14 September validation records document the earlier cached-data analysis; the 15 September raw-data record is the current verification.
