# Research question and analysis plan

## Primary research question

Among Greater Melbourne standard entire-home segments with at least 50 eligible listings, which LGA × dwelling-type × bedroom configurations have the highest mean out-of-sample predicted probability of recording at least 22 guest reviews in the twelve months preceding the snapshot?

The intended use is to screen comparable property segments for a prospective operator. Cross-sectional validation on existing listings does not establish a new operator's future performance, lease availability or profit.

## Sample and outcome

| Item | Rule |
|---|---|
| Unit | One listing in the school-supplied June 2026 snapshot |
| Room and bedrooms | Entire home/apt, one to three bedrooms |
| Apartment/unit | Entire rental unit; Entire condo |
| House/townhouse | Entire home; Entire townhouse |
| Quoted price | AUD30–1,500 inclusive |
| Segment | LGA × dwelling class × bedroom count |
| Minimum support | At least 50 listings after all main-sample filters |
| Outcome | One if number_of_reviews_ltm >=22; otherwise zero |
| Zero reviews | Retained in the analytical sample |

The main sample contains 8,967 listings, 4,081 hosts and 35 segments. Its descriptive P75 is 22 reviews; 2,315 listings (25.82%) reach or exceed that value. The event remains fixed at 22 in every model and sensitivity. Its selection followed sample exploration, so cross-validation assesses models for that event rather than independently validating the threshold choice. Segment support is defined using full-snapshot covariate counts; results are conditional on this reported scope.

The dwelling mapping defines a comparable residential sample. It does not establish that excluded types cannot be rented. The R tables display the original Moreland label as Merri-bek; the Python tables retain the source label.

## Descriptive analysis

Script 08 reports review quantiles, sample sizes, hosts, zero-review counts and observed attainment rates. Its 90% pointwise intervals use 1,000 within-segment host-cluster resamples. The profile table compares capacity, beds, bathrooms, amenities and parking between listings at or above 22 and below 22. These are unadjusted property comparisons, not causal effects or fitted predictions.

## Prediction and evaluation

`scripts/rq_scope_feasibility.py` fits pooled logistic regression and random forest models. Main predictors are LGA, configuration, capacity, bathroom count and amenity count. Current quoted price and minimum stay enter only the operating-controls sensitivity. Reviews, ratings, Superhost, availability and estimated revenue or occupancy do not enter the primary model.

Five host-grouped folds use seed 30005. Every host retains the same fold across models and sensitivities. Imputation, category encoding and scaling are fitted only on the training fold. Logistic regression uses C=1; the forest uses 250 trees, minimum leaf size 10 and square-root feature sampling. No hyperparameter search or independent final test set has been completed.

Outputs report ROC-AUC, average precision with tied scores handled as groups, Brier score, log loss, calibration bins, a confusion matrix at 0.5 and precision among the highest-scored quarter. A training-fold prevalence predictor supplies an additional Brier/log-loss reference. Listing-level OOF probabilities and fold assignments remain in ignored processed-data files; public tables contain aggregates.

The logistic main model provides the reference segment ranking. Its mean OOF probabilities describe the observed mix of eligible properties within each segment. The 95% score intervals use 500 host-cluster resamples conditional on the existing OOF scores, with no model refitting. They are distinct from the descriptive 90% attainment intervals and omit model-fitting, model-selection and rank-selection uncertainty.

## Completed sensitivities

- Add contemporaneous price and minimum stay to the predictor set.
- Require first review on or before 1 June 2025 and reapply the 50-listing rule: 4,812 listings in 16 segments. This is a review-history criterion, not an opening date or proof of uninterrupted trading. The sample P75 is 29, while the event remains 22.
- Remove the price filter and reapply minimum support: 13,075 listings in 53 segments. Its P75 is 17; the event again remains 22.

Metrics from different samples should be interpreted against their own prevalence and composition, not used as a like-for-like competition between sample definitions. Broader property mappings, repeated splits, nested tuning and refitted ranking uncertainty remain future work.

## Reproducibility status

The current run used `data/processed/listings_clean.rds` because the raw CSV links are broken. Raw IDs, original cleaning and per-listing review windows remain unverified in this rerun. The Python reader preserves identifiers as text, parses amenity JSON and half-baths when raw files are restored, and records review-count mismatches against each listing's scrape date. It does not substitute a claimed exact match while sources are unavailable.

See [model metrics](tables/rq_model_metrics.json), [scope and provenance](tables/rq_scope_summary.json), [segment scores](tables/rq_oof_segment_ranking.csv) and [validation record](data-validation-2026-09-13.md).
