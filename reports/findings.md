# Current findings

The primary analysis concerns the probability of recording at least 22 guest reviews in the preceding 12 months. It supports a preliminary comparison of listing segments; it does not estimate profitability or a new operator's future success.

## Descriptive evidence

The primary cohort contains **8,967 standard entire-home listings, 4,081 hosts and 35 LGA × dwelling class × bedroom segments**. Every segment has at least 50 eligible listings after the property-type, bedroom and price filters. Zero-review listings remain in the analysis.

The cohort's empirical review-count P75 is 22. The common event `reviews >= 22` occurs for **2,315 listings (25.8169%)**, including threshold ties. This is a scoped internal benchmark, not a market-wide or externally prescribed standard.

Melbourne 3BR Apartment/unit has the highest observed target share, **39.78% (216/543)**. Its 90% host-cluster interval is 32.57%–46.57%. The [descriptive segment table](tables/segment_ladder.csv) reports all groups and their uncertainty.

## Exploratory predictive results

Five-fold host-grouped cross-validation evaluates previously unseen hosts within the supplied snapshot. The main models use property attributes, LGA and bedroom–dwelling configuration.

| Main model | ROC-AUC | Average precision | Brier score | Precision in highest-scored quarter |
|---|---:|---:|---:|---:|
| Logistic regression | 0.649 | 0.361 | 0.182 | 37.82% |
| Random forest | 0.631 | 0.348 | 0.184 | 34.74% |

The descriptive prevalence reference is 25.82%. The training-fold-prevalence baseline has Brier score 0.192. The models therefore show useful but limited discrimination in this evaluation. The [metrics](tables/rq_model_metrics.json) and [calibration table](tables/rq_calibration.csv) also show that probabilities are imperfectly calibrated, particularly in some higher-probability bins. A 0.5 classification cutoff identifies few positives and is not used as an entry decision rule.

The property-only logistic ranking places Melbourne 3BR Apartment/unit first, with mean out-of-fold probability **39.54%**. Yarra Ranges 2BR House/townhouse follows at **36.71%**, then its 3BR counterpart at **33.76%**. These predictions describe different quantities from observed rates. The [ranking table](tables/rq_oof_segment_ranking.csv) contains conditional 95% intervals, which hold the fitted out-of-fold probabilities fixed and omit model-fitting uncertainty.

## Sensitivity and remaining work

Adding current price and minimum-stay settings increases logistic ROC-AUC to 0.720. Those settings are contemporaneous operating characteristics, so this result is a separate sensitivity rather than evidence about information available before a property starts operating.

The earlier-first-review cohort has 4,812 listings, 16 segments and a 35.83% target share. Its own P75 is 29, but the target remains 22 to preserve the event being compared. Removing the price filter gives another distinct population, with 13,075 listings in 53 segments and a 19.44% target share.

The next stage should assess the stability of rankings across host splits, improve probability calibration using training data only, and evaluate a final prespecified model on independent data if available. The threshold and scope were chosen during exploration; present cross-validation does not independently validate those choices.

The original CSV files must also be restored to verify identifiers, parsing and trailing-year review counts. Current results have been checked from the saved processed data onward. Missing rental and operating costs prevent a profit calculation, and the data do not establish which properties can be leased or sublet.
