# Melbourne Airbnb Market Screening

Interim Project Report

CMCE30005 Business Analytics Challenge | Semester 2 2026 | TheNextChapter Group 2

Eric Huang, Loc Le, Qihang Sun and Maksym Xu

Repository: https://github.com/Qihang-cpu/CMCE30005-TheNextChapter/tree/interim-report-2026-09-13

## Introduction

Our client leases residential properties and runs them as Airbnb accommodation with the required permissions. This business model is called rental arbitrage. The client has limited start-up funds. They need to choose which Melbourne areas and property types to investigate before signing leases and buying furniture. A poor choice can tie up their money and delay the business. Our project helps the client narrow this search.

We use the Inside Airbnb dataset supplied by the school. It includes property details, locations and dated guest reviews. These fields allow us to compare existing listings. We group locations by Local Government Area (LGA), which means a municipal area. Each LGA can contain several suburbs. All numerical analysis uses the supplied dataset.

Our final output will be a shortlist of property segments for further investigation. We will compare their past review activity and test whether models improve on simple segment averages. The client can use the shortlist to guide property searches and request lease quotations. Financial assessment will require actual rent, furnishing costs and operating expenses, which this dataset does not contain.

## Problem Definition and Objectives

Our research question is: Which LGA, dwelling-type and bedroom-count segments have the highest average predicted probability of reaching a common upper-quartile review benchmark among eligible Melbourne listings? Predictions are tested on hosts excluded from model training. The outcome covers the year before each listing's scrape date.

We study standard entire homes with one to three bedrooms. Each segment needs at least 50 eligible analysis listings. We define established listings by a first review at least 365 days before the scrape date. This condition provides review history but cannot confirm continuous operation. Rental units and condos form the apartment group. Homes and townhouses form the house group. We retain quoted prices of AUD30–1,500. These rules define our comparison sample; they do not confirm lease availability.

The target records whether a listing reaches a common review-count threshold over the previous 365 days. The upper-quartile rule is our analytical benchmark. Reviews provide a limited signal of guest activity. Review willingness and stay length can affect the count. We therefore cannot use it to measure bookings, occupancy or profit.

We aim to compare segment performance, test the value of property features, and identify consistent search candidates. The results support further investigation before any lease commitment.

## Data Description

The school dataset contains 25,728 listings with 90 variables, 9,390,720 calendar records and 1,026,690 reviews (Inside Airbnb, 2026). Scrape dates range from 17 June to 1 July 2026. We use LGA, property type, bedrooms, guest capacity, bathrooms, amenities and review dates. Calendar unavailability can include dates blocked by hosts. The calendar also contains no prices, so it cannot establish realised seasonal cash flow.

Cleaning converts price text into numbers, standardises missing values and extracts bathroom and amenity information. Price is missing for 6,553 listings and bedrooms for 4,679. We rebuild annual review counts from review dates. The supplied recent-review field covers 366 calendar dates. Using a strict 365-day window changes one analysis target. GitHub contains the detailed checks and sample-filtering table.

The separate reference sample contains 906 listings. Its 75th percentile is 29.75 reviews, giving an integer threshold of 30. The analysis sample contains 3,873 listings from 1,726 hosts in 14 segments. We keep 334 listings with zero annual reviews to include low-activity outcomes. Overall, 981 listings reach the threshold (25.33%).

Segment attainment ranges from 8.25% to 36.60%. This variation supports comparing property segments. However, our supported sample covers only six LGAs. About 64% of listings are in Melbourne LGA. Missing prices and the history rule affect which listings enter the sample. Exited listings are absent. These limits reduce the relevance of results to other areas and new operators.

## Methodology and Analytical Approach

A fixed rule based on host identifiers reserves about 20% of hosts to set the benchmark. These reference hosts are kept separate from model training and evaluation. The threshold stays fixed across comparisons. We use five-fold validation and keep each host's properties in one fold. This prevents the same host appearing in training and validation (scikit-learn developers, n.d.). Each training fold learns its own missing-value treatment and category encoding.

Logistic regression provides a simple reference model. Random forest and histogram gradient boosting can capture nonlinear relationships. Basic features include location, configuration, capacity, bathrooms and amenity counts. Six model extensions add coordinates, beds and nine facilities. We exclude review-based predictors, ratings and host badges. Current price and minimum stay enter separate operating-condition models. Their timing limits interpretation as pre-opening information.

We compare models with a simple segment-rate baseline. It uses each segment's attainment among training hosts, with a fixed smoothing weight of ten. AUC measures ranking ability. Average precision summarises identification of listings reaching the target. Brier score measures probability error; lower values are better. Calibration checks predicted probabilities against observed rates. R supports cleaning and tables. Python pipelines keep validation steps consistent across models.

We refit models under 20 further host splits to check sensitivity to the split. These runs reuse the same data. Current intervals hold predictions fixed and omit model-selection and benchmark uncertainty. Model choice remains exploratory.

## Analysis Plan and Progress to Date

We have completed cleaning, review reconstruction, descriptive comparisons, grouped prediction and repeated-split checks. The table compares models on the same main sample and folds.

| Predictor | AUC | Average precision | Brier score |
| --- | --- | --- | --- |
| Training-host segment rate | 0.581 | 0.285 | 0.1868 |
| Original property-only logistic | 0.573 | 0.285 | 0.1886 |
| Enhanced property-only forest | 0.640 | 0.350 | 0.1813 |

The original logistic and forest models perform worse than segment rates on main-split AUC and Brier. The enhanced forest improves both measures in all five folds. We provisionally use it for probability scoring because it has the lowest Brier among property-only extensions. Boosting has a slightly higher AUC of 0.647. Across 20 further splits, forest AUC averages 0.626 and ranges from 0.589 to 0.648. It exceeds the segment baseline each time. Its overall predictive ability remains moderate.

All property-only models identify the same main top three: Melbourne three-bedroom apartments, Melbourne two-bedroom apartments and Yarra Ranges three-bedroom houses/townhouses. Their observed attainment is 36.6%, 32.8% and 30.0%, respectively. Under the enhanced forest, Melbourne three-bedroom apartments rank first in all 20 further splits. The same top-three set appears in 19 splits. Yarra Ranges has only 90 listings in this segment, so its evidence is thinner. The model improves overall prediction while keeping the principal search candidates unchanged. We have not separately tested prediction within segments.

The client can start property searches in these three segments and request lease quotations. Before signing, they must check permission, availability and actual costs. Our results cannot estimate address-level profit or ROI.

For the final report, we will select models within training data and recalculate ranking intervals while refitting models. We will also test wider dwelling definitions and different minimum sample sizes. We will assess success through lower probability error, calibration and candidate stability. If model gains disappear, we will use segment rates as the main screening evidence. If rankings change substantially, we will present several candidates and explain the uncertainty. The README and outputs will record these decisions.

## References

Inside Airbnb. (2026). Melbourne listings, calendar and reviews [June 2026 dataset supplied through CMCE30005 LMS].

Scikit-learn developers. (n.d.). Cross-validation and probability calibration. https://scikit-learn.org/stable/modules/cross_validation.html#cross-validation-iterators-for-grouped-data ; https://scikit-learn.org/stable/modules/calibration.html
