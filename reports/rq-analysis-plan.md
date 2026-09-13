# Research Question and Analysis Plan — Working Specification

**Version:** 13 September 2026

**Purpose:** Shared contract between the research-question/report work and the modelling work.

## Primary research question

Among Greater Melbourne standard entire-home rental segments with at least 50 comparable listings, which LGA × 1–3-bedroom dwelling configuration gives a prospective multi-property Airbnb operator the highest out-of-sample predicted probability of achieving at least 22 guest reviews over a 12-month period—the observed market-wide top-quartile benchmark?

## Locked definitions

| Item | Definition |
|---|---|
| Unit of analysis | One Airbnb listing |
| Geography | `neighbourhood_cleansed`, interpreted as LGA |
| Room scope | `Entire home/apt` |
| Bedrooms | 1, 2 or 3 |
| Apartment/unit | `Entire rental unit`, `Entire condo` |
| House/townhouse | `Entire home`, `Entire townhouse` |
| Price scope | AUD 30–1,500 per night |
| Comparable-cell rule | At least 50 listings per LGA × configuration |
| Primary outcome | 1 when `number_of_reviews_ltm >= 22`; otherwise 0 |
| Benchmark basis | Market-wide P75 across the eligible sample, not a separate P75 within each segment |
| Validation unit | Host; no host may appear in both training and validation folds |

## Primary predictor set

Use only information observable or selectable before entry: LGA, property configuration, accommodates, bathrooms, amenity variables, price, minimum nights and local comparable-listing density.

Do not use reviews, ratings, Superhost status, estimated occupancy or estimated revenue in the primary model. Do not use availability unless its ambiguous meaning is explicitly resolved. Host scale or experience may be used only in a separately labelled operator-control model, because it is not part of the location/property choice.

## Model and validation requirements

1. Fit one pooled listing-level model; do not fit independent models to small cells.
2. Use logistic regression as the interpretable benchmark.
3. Compare it with a tree-based model using the same folds and predictors.
4. Generate out-of-fold probabilities for every eligible listing.
5. Report ROC-AUC, PR-AUC, calibration/Brier score and a confusion matrix at a declared threshold.
6. Aggregate only out-of-fold probabilities into the final segment ranking.
7. Report sample size, unique hosts, observed outcome rate, predicted probability and uncertainty for every reported segment.

## Required sensitivity checks

- narrow versus broader defensible property-type mappings;
- all eligible listings versus listings whose first review predates the outcome window, clearly noting that `first_review` is not launch date;
- alternative model classes and decision thresholds;
- ranking stability after removing cells with fewer than 10 observed positive outcomes.

## Separate scenario analysis

P75 estimated revenue and implied affordable rent under 1.5×, 2× and 2.5× revenue-to-rent assumptions may be reported separately. It must be labelled as scenario analysis, must accept the client's actual rent quotation, and must not be described as observed profit or ROI.
