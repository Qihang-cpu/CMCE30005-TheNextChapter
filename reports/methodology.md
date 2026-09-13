# Analytical methodology

The project compares recent guest-review activity across residential Airbnb segments in Greater Melbourne. Its outcome is whether a listing recorded at least 22 guest reviews in the preceding 12 months. Reviews measure recorded guest engagement; they do not establish bookings, occupancy, revenue or profit.

## Sample and outcome

The primary cohort contains entire homes with one to three bedrooms, a quoted nightly price between AUD30 and AUD1,500, and one of four property types. Entire rental units and condos form the Apartment/unit class; entire homes and townhouses form House/townhouse. A segment is LGA × dwelling class × bedroom count and must contain at least 50 listings after these filters. The whitelist defines comparability, not whether a property is available to rent or can be sublet.

The resulting cohort has **8,967 listings, 4,081 hosts and 35 segments**, including **1,428 listings with zero recent reviews**. Its empirical review-count P75 is 22. The event `number_of_reviews_ltm >= 22` applies the same threshold to every segment; 2,315 listings, or 25.8169%, meet it. Ties explain why this exceeds exactly 25%. The threshold was identified during scope exploration and then fixed. Cross-validation does not independently validate the choice of 22, and 22 is not the P75 of all Melbourne listings.

The price window defines the primary quoted-listing population. Extreme quoted prices are excluded by a scope rule, not classified as verified errors. [Scope counts](tables/review_scope_summary.csv) document every restriction.

## Descriptive comparisons

[Script 08](../scripts/08_peer_ranking.R) reports segment review quantiles, zero-review counts, observed target shares and independent host counts. It resamples hosts with replacement, retaining each sampled host's listings, to obtain pointwise 90% percentile intervals from 1,000 draws. These intervals describe uncertainty in observed proportions; they are not probabilities that a segment ranks first.

Property-attribute profiles compare the two outcome groups without using review-derived features. These pooled contrasts remain subject to differences in location, configuration and other characteristics.

## Predictive validation

The [Python workflow](../scripts/rq_scope_feasibility.py) evaluates logistic regression and a random forest using five folds grouped by host. Every listing receives a prediction from a model trained without its host. Imputation, scaling and categorical encoding are fitted within each training fold. Main predictors are guest capacity, bathroom count, amenity count, LGA and bedroom–dwelling configuration.

ROC-AUC, average precision, Brier score, log loss, calibration bins and precision among the highest-scored quarter assess discrimination and probability quality. The baseline probability for each validation fold comes from its training fold. Full-sample prevalence is also reported as a descriptive reference.

This is exploratory cross-validation with fixed model settings; there is no independent final test set or hyperparameter search. Segment eligibility uses full-snapshot covariate counts. The target is observed activity before the snapshot, not a new operator's next-year outcome.

Mean out-of-fold probabilities provide a segment ranking. Its 95% bootstrap intervals resample hosts around existing predictions without refitting the models, so they omit model-fitting and model-selection uncertainty. They differ from script 08's 90% intervals for observed rates.

## Sensitivity and interpretation

A separate cohort requires first review on or before **1 June 2025**, then reapplies the 50-listing rule. It retains zero-review outcomes and the fixed threshold of 22. First review is a history measure, not a launch date or evidence of continuous operation. Further sensitivities remove the price restriction or add current price and minimum-stay settings as contemporaneous operating controls.

All numerical comparisons use the school-supplied data. [Data notes](data-notes.md) describe the missing raw files and resulting reproducibility limits. Financial feasibility and causal effects are outside what this dataset can establish.
