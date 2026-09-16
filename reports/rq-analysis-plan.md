# Research question and analysis plan

The date rules below were implemented and rerun from the three school-supplied raw CSV files on 15 September 2026. The primary outcome is reconstructed from raw review dates. All sample, threshold and model results use the listing-specific date rule defined below.

## Primary research question

Among established standard entire-home listings with one to three bedrooms in Greater Melbourne, which LGA × dwelling-class × bedroom-count segments with at least 50 eligible analysis listings have the highest mean out-of-sample predicted probability of meeting a common upper-quartile review-count benchmark over the 365 days ending on each listing's scrape date?

The intended use is to screen comparable property segments for a prospective multi-property operator. The outcome concerns the 365-day period ending on each listing's scrape date. Validation on hosts excluded from model training does not establish a new operator's future performance, lease availability or profit.

## Eligibility and reference date

[The shared configuration](../config/review_analysis.json) specifies the scope before the revised model evaluation.

| Item | Rule |
|---|---|
| Unit | One listing in the school-supplied June 2026 snapshot |
| Established | `first_review <= last_scraped - 365 days` for each listing |
| Review window | `last_scraped - 365 days < review date <= last_scraped` |
| Outcome field | `reviews_365d`, reconstructed from raw review dates |
| Date quality | Require valid scrape dates; reject malformed dates and future first reviews |
| Room and bedrooms | Entire home/apt, one to three bedrooms |
| Apartment/unit | Entire rental unit; Entire condo |
| House/townhouse | Entire home; Entire townhouse |
| Quoted price | AUD30–1,500 inclusive; an explicit scope assumption |
| Segment | LGA × dwelling class × bedroom count |
| Minimum support | At least 50 analysis listings after all filters and removal of benchmark hosts |
| Zero recent reviews | Retained |

The history condition establishes an earlier observed review, not an opening date or uninterrupted operation. The review window includes exactly 365 calendar dates, including the scrape date and excluding the date 365 days before it; it is not a calendar-year offset around leap days. The raw `number_of_reviews_ltm` field instead matches the closed interval including both endpoints, containing 366 calendar dates. It is retained unchanged for source diagnostics. The primary count excludes 352 boundary-date reviews across 350 listings; all other source counts agree. The four-type mapping describes comparable residential stock without asserting that other dwelling types cannot be leased. Wider-type and unrestricted-history summaries document composition changes. Both R and Python display Moreland as Merri-bek.

## Common benchmark without using validation outcomes

A deterministic host partition reserves approximately 20% of hosts for benchmark development. For a canonical host ID, take SHA256 of `30005|benchmark|` followed by that ID, interpret the first seven hexadecimal characters as an integer, and reserve hosts whose remainder modulo five is zero. All of a host's listings share the role. This partition is based on identifiers, not outcomes.

Remove those hosts from the analysis pool, then determine eligible cells using the remaining listings' covariates and the 50-listing rule. The reference sample contains benchmark-host listings that satisfy the same primary eligibility rules and belong to those final cells. Its pooled review-count P75 uses linear interpolation (R type 7); the common integer event is review count at least the ceiling of that P75. The reference contains **906 listings from 426 hosts**, with **P75 = 29.75**, giving a computed integer cutoff of **30**.

Benchmark hosts determine the cutoff only. They are excluded from model fitting, out-of-fold evaluation, segment scoring and every sensitivity's analysis pool. Analysis outcomes cannot change the cutoff. The primary analysis contains **3,873 listings, 1,726 hosts and 14 segments**, including 334 zero-review listings, with **981 outcomes at or above 30 (25.3292%)**. Its observed P75 is 30, but it does not determine the cutoff. The reference attainment share is 25.0552%, with integer ties retained.

The common threshold is fixed across all segments, models and sensitivities. It is a school-data benchmark, not a whole-market P75, profitability standard or externally specified count. This design follows prior exploration of the same snapshot. Separating the current computations does not create a previously untouched final test or erase earlier research choices. Segment support uses full analysis-pool covariate counts, so results remain conditional on those supported segments.

## Descriptive analysis

Script 08 reports listing and distinct-host counts, zero-review counts, review quantiles, observed attainment and property attributes for the same analysis listings used in prediction. Pointwise 90% intervals use 1,000 within-segment host-cluster resamples. The profile compares listings meeting the common event with those below it. These are pooled associations, not causal effects.

## Prediction and probability validation

The baseline Python workflow fits logistic regression and random forest using LGA, configuration, capacity, bathrooms and amenity count. Current price and minimum stay enter a separate operating-controls sensitivity. Review counts, ratings, Superhost status, availability, estimated occupancy and estimated revenue are excluded from the primary predictors.

Five folds separate analysis hosts; each listing's prediction comes from a model trained without its host. Imputation, encoding and scaling are fitted inside each training fold. Fixed baseline model settings are logistic C=1 and 250 forest trees with minimum leaf size 10 and square-root feature sampling. There is no hyperparameter search or independent final test set.

Evaluation reports ROC-AUC, average precision, Brier score, log loss, precision among the highest-scored quarter, and a confusion matrix at 0.5. Probability assessment compares mean predicted probabilities with observed rates in ten fixed-width bins, includes bin counts and weighted absolute calibration error, and compares every model with a training-fold-prevalence baseline and with a segment-rate baseline that predicts each validation listing from its segment's training-host attainment rate under a pre-specified shrinkage rule. Sparse high-probability bins are not evidence of precise calibration. Fitted recalibration must use training data rather than evaluation outcomes; the sigmoid extensions below follow this rule.

Segments are ranked by mean out-of-fold probability. Conditional 95% intervals resample hosts 500 times while holding fitted scores and the common benchmark fixed. They omit model-fitting, benchmark-estimation and model-selection uncertainty and cannot establish a definitive best location. Listing predictions, benchmark membership and fold assignments remain in ignored processed-data files; public outputs are aggregate tables.

## Extensions evaluated after the baseline

[Script 10](../scripts/10_model_extensions.py) retains the same cohort, reference cutoff and five outer host folds, adding latitude, longitude, beds and nine individual amenity indicators from the supplied snapshot. It evaluates six fixed candidates: property-only logistic regression, random forest, histogram gradient boosting and sigmoid-calibrated boosting, plus operating-controls boosting with and without sigmoid calibration. Both calibrated variants use three host-disjoint folds inside each outer training subset, with preprocessing and calibration fitted without access to outer validation outcomes. All six candidates and all eight original baseline/scenario results remain available; no hyperparameter search was performed.

The extended property-only random forest is provisionally selected for probability ranking on its Brier score of **0.181316**, the lowest among the property-only candidates, with AUC **0.640**, average precision **0.350** and ten-bin calibration error **1.63 percentage points**. The forest has no fitted calibration correction. Boosting has higher AUC but higher Brier loss; sigmoid calibration does not improve every metric or both feature scenarios. Under the extended forest, Melbourne three-bedroom apartments have the highest mean OOF score, **34.45%**, with a conditional 95% interval of **33.00%–35.81%**. This is an exploratory preference following baseline inspection, not independent confirmation of the best model or location. [Extension metrics](tables/rq_extension_metrics.csv), [rankings](tables/rq_extension_ranking.csv) and [provenance](tables/rq_extension_provenance.json) document every comparison.

## Sensitivity analyses and remaining work

- Add current quoted price and minimum stay as contemporaneous operating characteristics.
- Remove the first-review restriction, exclude the same benchmark hosts and reapply minimum support.
- Remove the price filter while retaining the history condition, exclude the same benchmark hosts and reapply minimum support.

Both scope sensitivities use the primary reference's 30-review cutoff. Removing the history restriction yields 6,675 analysis listings in 22 segments, with 1,169 meeting the event. Removing the price filter yields 5,720 in 19 segments, with 1,046 meeting it. The different samples have different prevalences; their metrics are not a like-for-like competition between scope definitions. Wider dwelling summaries assess composition under the whitelist. Repeated host splits, further calibration assessment, nested model selection and ranking intervals with refitted models and reference thresholds remain future work.

## Reproducibility and methodological sources

The 15 September run used all three raw files and rebuilt the processed data. The workflow requires those files and does not fall back to an earlier cache. Cleaning stages outputs until all inputs pass; Python verifies the supplied review field's observed 366-date window and independently reconstructs the strict 365-date count for every source listing before publishing analysis. The descriptive script checks matching input and configuration hashes before producing rankings. The baseline execution order is cleaning, Python modelling, descriptive ranking and the calibration plot. Script 10 then checks the stored cohort and folds before evaluating extensions. The raw review validation passed for all 25,728 listings, with no invalid review dates, future reviews or unmatched listing IDs. Scientific notation already present in the source limits recoverable identifier precision.

Scikit-learn explains [validation for grouped observations](https://scikit-learn.org/stable/modules/cross_validation.html#cross-validation-iterators-for-grouped-data) and [probability calibration](https://scikit-learn.org/stable/modules/calibration.html). These support the validation approach, not an external numerical review threshold.

See [metrics](tables/rq_model_metrics.json), [scope and provenance](tables/rq_scope_summary.json), [segment scores](tables/rq_oof_segment_ranking.csv) and [data notes](data-notes.md).
