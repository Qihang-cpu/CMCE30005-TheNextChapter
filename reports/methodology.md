# Analytical methodology

The project compares review activity among established standard residential Airbnb listings in Greater Melbourne. It asks which supported property segments have the highest mean out-of-fold probability of meeting a common upper-quartile review-count benchmark in the year preceding the supplied snapshot. Reviews do not establish occupancy, income or profit.

## Sample and common outcome

The [shared configuration](../config/review_analysis.json) defines entire homes with one to three bedrooms, a quoted price of AUD30–1,500 and four property types. Rental units and condos form Apartment/unit; homes and townhouses form House/townhouse. Established means first review on or before 1 June 2025, relative to 1 June 2026. This is review history, not an opening date or continuous exposure. Neither the whitelist nor the quoted-price range establishes lease availability or verified data errors.

Approximately 20% of hosts are assigned to benchmark development using a fixed hash of their text identifiers. These hosts are excluded from all model training and analysis samples. Among the remaining hosts, every reported LGA × dwelling class × bedroom cell must contain at least 50 listings after all eligibility filters. This support criterion uses covariates, not review outcomes.

Benchmark-host listings must satisfy the primary eligibility rules and belong to the supported primary cells. Their pooled P75, calculated by linear interpolation and rounded upward to an integer, defines one common event for all segments and models. The reference comprises **899 listings from 424 hosts**, with **P75 = 30 reviews**. No validation-host outcomes enter that calculation.

The primary analysis contains **3,810 listings, 1,699 hosts and 14 segments**. It retains **333 zero-review listings**. The fixed event `number_of_reviews_ltm >= 30` occurs for **957 listings (25.1181%)**. Threshold ties are retained; neither the reference nor the analysis is forced into an exact 25% positive class. The count of 30 is a computed result, not part of the wording of the research question. [The analysis plan](rq-analysis-plan.md) records the full partition algorithm.

## Descriptive comparison and composition checks

[Script 08](../scripts/08_peer_ranking.R) describes the same analysis listings used by the predictive workflow. It reports counts, distinct hosts, review quantiles, zero outcomes, actual attainment and property-attribute profiles. Host-cluster resampling retains all listings of each sampled host. Its pointwise 90% percentile intervals use 1,000 draws and do not measure confidence in a segment's rank.

Wider dwelling and unrestricted-history summaries show how inclusion rules change composition. These comparisons do not demonstrate that excluded dwellings cannot be rented, or that younger review histories would perform like established histories after another year. Pooled attribute differences do not establish causal effects.

## Predictive validation and calibration

The [Python workflow](../scripts/rq_scope_feasibility.py) evaluates logistic regression and random forest with five host-grouped folds. Every scored listing is excluded from training together with its host. Preprocessing is learned inside each training fold. Main predictors are guest capacity, bathrooms, amenities, LGA and bedroom–dwelling configuration. Current price and minimum stay are reserved for a labelled operating-controls sensitivity.

ROC-AUC and average precision assess discrimination. Brier score, log loss, mean predicted versus observed rates, ten fixed-width calibration bins and their weighted absolute error assess probability quality. A training-fold-prevalence baseline provides a comparison. Bin sizes must accompany calibration summaries, especially where high predicted probabilities are sparse. Calibration is assessed, not assumed; later recalibration must use training data only.

Mean out-of-fold probabilities provide the reference segment ranking. Its conditional 95% intervals use 500 host-cluster resamples around fixed predictions and a fixed benchmark. They omit uncertainty from estimating the benchmark, fitting or choosing models, and selecting the highest rank. They differ from the descriptive 90% intervals for observed rates.

## Sensitivity and limits

Removing the history restriction gives 6,675 analysis listings in 22 segments. Removing the price filter but retaining established history gives 5,647 in 19 segments. Both exclude all benchmark hosts, recalculate minimum support and retain the primary reference's 30-review event. Adding current price and minimum stay changes the predictor set rather than the primary sample. Comparisons between different samples require attention to prevalence and composition.

The revised design follows prior exploration of the snapshot. Computational separation of reference and validation hosts does not create an untouched final test. Fixed models have been evaluated without hyperparameter search; repeated splits, nested tuning, training-only calibration and refitted uncertainty remain future work. Cross-sectional scores describe existing listings in the preceding year, not new operators' future performance.

All numerical inputs are from the school's supplied data. The unavailable original CSV files prevent verification of raw parsing, identifier precision and per-listing review windows; see [data notes](data-notes.md). Financial feasibility, subletting eligibility and causal effects remain outside the evidence.
