# Research question and analysis plan

## Primary research question

Among established standard entire-home listings with one to three bedrooms in Greater Melbourne, which LGA × dwelling-type × bedroom-count segments with at least 50 eligible listings have the highest mean out-of-sample predicted probability of meeting a common upper-quartile review-count benchmark in the 12 months preceding the snapshot?

The intended use is to screen comparable property segments for a prospective multi-property operator. The outcome concerns the twelve months preceding the supplied snapshot. Validation on hosts excluded from model training does not establish a new operator's future performance, lease availability or profit.

## Eligibility and reference date

[The shared configuration](../config/review_analysis.json) specifies the scope before the revised model evaluation.

| Item | Rule |
|---|---|
| Unit | One listing in the school-supplied June 2026 snapshot |
| Established | First review on or before 1 June 2025 |
| History reference | 1 June 2026, the start of the supplied snapshot month |
| Room and bedrooms | Entire home/apt, one to three bedrooms |
| Apartment/unit | Entire rental unit; Entire condo |
| House/townhouse | Entire home; Entire townhouse |
| Quoted price | AUD30–1,500 inclusive; an explicit scope assumption |
| Segment | LGA × dwelling class × bedroom count |
| Minimum support | At least 50 analysis listings after all filters and removal of benchmark hosts |
| Zero recent reviews | Retained |

The history condition establishes an earlier observed review, not an opening date or uninterrupted operation. The reference date is an eligibility convention; it does not replace a listing's scrape date when validating its trailing-year outcome. The four-type mapping describes comparable residential stock without asserting that other dwelling types cannot be leased. Wider-type and unrestricted-history summaries document composition changes. R displays Moreland as Merri-bek; Python retains the source label.

## Common benchmark without using validation outcomes

A deterministic host partition reserves approximately 20% of hosts for benchmark development. For a canonical host ID, take SHA256 of `30005|benchmark|` followed by that ID, interpret the first seven hexadecimal characters as an integer, and reserve hosts whose remainder modulo five is zero. All of a host's listings share the role. This partition is based on identifiers, not outcomes.

Remove those hosts from the analysis pool, then determine eligible cells using the remaining listings' covariates and the 50-listing rule. The reference sample contains benchmark-host listings that satisfy the same primary eligibility rules and belong to those final cells. It contains **899 listings from 424 hosts**. Its pooled review-count P75 is **30**, calculated using linear interpolation (R type 7). The common integer event is review count at least the ceiling of that P75.

Benchmark hosts determine the cutoff only. They are excluded from model fitting, out-of-fold evaluation, segment scoring and every sensitivity's analysis pool. Analysis outcomes cannot change the cutoff. The primary analysis contains **3,810 listings, 1,699 hosts and 14 segments**, including 333 zero-review listings. There are **957 outcomes at or above 30 (25.1181%)**. Its observed P75 also happens to be 30; this agreement is not required by the procedure. The reference attainment share is 25.2503%, with integer ties retained.

The common threshold is fixed across all segments, models and sensitivities. It is a school-data benchmark, not a whole-market P75, profitability standard or externally specified count. This design follows prior exploration of the same snapshot. Separating the current computations does not create a previously untouched final test or erase earlier research choices. Segment support uses full analysis-pool covariate counts, so results remain conditional on those supported segments.

## Descriptive analysis

Script 08 reports listing and distinct-host counts, zero-review counts, review quantiles, observed attainment and property attributes for the same analysis listings used in prediction. Pointwise 90% intervals use 1,000 within-segment host-cluster resamples. The profile compares listings meeting the common event with those below it. These are pooled associations, not causal effects.

## Prediction and probability validation

The Python workflow fits logistic regression and random forest using LGA, configuration, capacity, bathrooms and amenities. Current price and minimum stay enter a separate operating-controls sensitivity. Review counts, ratings, Superhost status, availability, estimated occupancy and estimated revenue are excluded from the primary predictors.

Five folds separate analysis hosts; each listing's prediction comes from a model trained without its host. Imputation, encoding and scaling are fitted inside each training fold. Fixed model settings are logistic C=1 and 250 forest trees with minimum leaf size 10 and square-root feature sampling. There is no hyperparameter search or independent final test set.

Evaluation reports ROC-AUC, average precision, Brier score, log loss, precision among the highest-scored quarter, and a confusion matrix at 0.5. Probability assessment compares mean predicted probabilities with observed rates in ten fixed-width bins, includes bin counts and weighted absolute calibration error, and compares Brier score with a training-fold-prevalence baseline. Sparse high-probability bins are not evidence of precise calibration. Any later recalibration must be fitted within training data, not to the evaluation outcomes.

Segments are ranked by mean out-of-fold probability. Conditional 95% intervals resample hosts 500 times while holding fitted scores and the common benchmark fixed. They omit model-fitting, benchmark-estimation and model-selection uncertainty and cannot establish a definitive best location. Listing predictions, benchmark membership and fold assignments remain in ignored processed-data files; public outputs are aggregate tables.

## Sensitivity analyses and remaining work

- Add current quoted price and minimum stay as contemporaneous operating characteristics.
- Remove the first-review restriction, exclude the same benchmark hosts and reapply minimum support: 6,675 listings in 22 segments.
- Remove the price filter while retaining the history condition, exclude the same benchmark hosts and reapply minimum support: 5,647 listings in 19 segments.

Both alternative-sample P75 values are 23, while the primary reference's 30-review cutoff remains fixed. The different samples have different prevalences; their metrics are not a like-for-like competition between scope definitions. Wider dwelling summaries assess the effect of the whitelist. Repeated host splits, training-only recalibration, nested tuning and ranking intervals with refitted models and reference thresholds remain future work.

## Reproducibility and methodological sources

The current run uses `data/processed/listings_clean.rds` because original CSV links are broken. Raw identifiers, parsing and per-listing review windows remain unverified. The original files must be restored for those checks; the revised workflow records their unavailable status.

Scikit-learn explains [validation for grouped observations](https://scikit-learn.org/stable/modules/cross_validation.html#cross-validation-iterators-for-grouped-data) and [probability calibration](https://scikit-learn.org/stable/modules/calibration.html). These support the validation approach, not an external numerical review threshold.

See [metrics](tables/rq_model_metrics.json), [scope and provenance](tables/rq_scope_summary.json), [segment scores](tables/rq_oof_segment_ranking.csv) and [validation record](data-validation-2026-09-13.md).
