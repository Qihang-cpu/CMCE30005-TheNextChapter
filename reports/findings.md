# Current findings

The current research question compares established standard residential segments on a common upper-quartile review-count event in the twelve months preceding the snapshot. The count is derived from reference hosts, not fixed in the RQ. These results do not establish future income or profitability.

## Reference and analysis samples

The final reference contains **899 listings from 424 benchmark hosts**, with pooled **P75 = 30**. A fixed identifier hash assigned these hosts to reference development; none enters model training or evaluation. The primary analysis contains **3,810 listings, 1,699 hosts and 14 segments**, with at least 50 listings after all restrictions. It retains 333 zero-review outcomes. **957 listings (25.1181%)** meet the reference's 30-review event. The reference attainment share is 25.2503%; ties prevent an exact quarter.

Established means first review on or before 1 June 2025 relative to 1 June 2026. It is not evidence of listing launch or continuous operation. Dwelling and price rules define an explicit comparison population, not lease availability. [The analysis plan](rq-analysis-plan.md) gives every rule and the computational separation of reference and validation outcomes.

## Descriptive evidence

Melbourne 3BR Apartment/unit has the highest observed attainment, **111/304 = 36.51%**. Its pointwise 90% host-cluster interval is **26.54%–46.23%**. [All segments](tables/segment_ladder.csv) include independent-host counts, quantiles, zero outcomes and uncertainty.

Listings meeting the target have median amenity count 44 versus 43 below it, with median capacity four in both groups. These unadjusted contrasts provide limited separation and cannot establish the effects of changing amenities.

## Predictive performance and calibration

Five-fold host-grouped validation gives the following property-only results:

| Model | ROC-AUC | Average precision | Brier score | Precision in highest-scored quarter |
|---|---:|---:|---:|---:|
| Logistic regression | 0.568 | 0.278 | 0.188 | 28.75% |
| Random forest | 0.553 | 0.271 | 0.191 | 26.86% |

The sample prevalence is 25.12%; the training-fold-prevalence baseline Brier score is 0.189738. Logistic regression improves this probability-loss measure only slightly; the forest is worse. Discrimination is weak. These results cannot support a confident investment recommendation.

Logistic mean predicted probability is 24.76%, versus 25.12% observed. Its ten-bin weighted absolute calibration error is 3.66 percentage points; the forest's is 6.06. The 22 logistic scores above 0.5 average 57.4%, yet only 31.8% meet the review benchmark. These few observations illustrate high-score uncertainty and overprediction, not a stable estimate for all future cases. No post-hoc calibration has been fitted. See [bin counts](tables/rq_calibration.csv) and [metrics](tables/rq_model_metrics.json).

![Held-out probability calibration](figures/18_probability_calibration.png)

## Segment scores and sensitivities

The logistic reference ranking places Melbourne 3BR Apartment/unit first, with mean OOF score **34.60%** and conditional 95% interval **33.33%–35.86%**. Melbourne 2BR apartments follow at 31.15%, then Yarra Ranges 3BR houses/townhouses at 28.08%. These intervals hold fitted scores and the benchmark fixed, omit their estimation uncertainty, and do not establish a definitive winner. [The ranking table](tables/rq_oof_segment_ranking.csv) includes both models and all scenarios.

Adding contemporaneous price and minimum stay gives logistic AUC 0.713. This is a separate operating-controls sensitivity, not evidence of prediction from verified pre-opening information. Removing the history restriction yields 6,675 listings in 22 segments, with 17.53% meeting 30; removing the price filter while retaining history yields 5,647 in 19, with 18.06% meeting 30. Both samples have P75 23; the reference event remains unchanged.

The next stage must examine repeated host splits, calibration learned within training folds and broader dwelling mappings, and report uncertainty with models and thresholds refitted. The design follows prior snapshot exploration; it creates no untouched final test. Original CSVs are still required to verify parsing, identifier precision and review windows. Current conclusions are verified from the saved processed data onward.
