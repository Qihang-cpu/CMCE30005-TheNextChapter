# Melbourne Airbnb Review Activity

Interim Project Report

CMCE30005 Business Analytics Challenge | Semester 2 2026 | TheNextChapter Group 2

Eric Huang, Loc Le, Qihang Sun and Maksym Xu

Repository: [Qihang-cpu/CMCE30005-TheNextChapter](https://github.com/Qihang-cpu/CMCE30005-TheNextChapter/tree/interim-report-2026-09-13)

## Introduction

A prospective operator considering several Melbourne Airbnb properties needs to compare locations and dwelling configurations before committing to leases and furnishings. The school-supplied Inside Airbnb snapshot shows substantial variation in quoted prices and guest reviews. Comparisons across conventional apartments and specialised holiday accommodation may reflect different property mixes.

Our project combines descriptive comparisons with predictive modelling of review activity to develop a preliminary segment shortlist. Reviews are observable, but they do not measure profit. The supplied data lack actual rental and operating costs, so financial viability and externally sourced rent scenarios are outside this analysis.

## Problem Definition and Objectives

Our research question is: **Among established standard entire-home listings with one to three bedrooms in Greater Melbourne, which LGA × dwelling-type × bedroom-count segments with at least 50 eligible listings have the highest mean out-of-sample predicted probability of meeting a common upper-quartile review-count benchmark in the 12 months preceding the snapshot?**

The descriptive objective is to compare review distributions, observed benchmark attainment and property attributes. The predictive objective is to test how well property information distinguishes higher-activity listings whose hosts are excluded from training.

Established means first review on or before 1 June 2025, relative to the start of the June 2026 snapshot month. This indicates review history, not an opening date or continuous operation. We retain entire rental units, condos, homes and townhouses with quoted prices of AUD30–1,500. Units and condos form one dwelling class; homes and townhouses form the other. These rules define comparable residential stock without establishing lease or subletting availability. Every reported segment needs at least 50 analysis listings after all eligibility and host-partition restrictions.

The common benchmark is calculated from a separate group of reference hosts. It is not hard-coded in the research question or taken from a whole-market P75. Industry percentile comparisons provide methodological context (Cushman & Wakefield Georgia, 2019), but the numerical review threshold comes solely from the supplied data and does not indicate profitability.

## Data Description

The saved June 2026 data contain 25,728 listings, approximately 9.39 million calendar records and 1.03 million reviews. Variables include listing and host identifiers, LGA, dwelling type, bedrooms, capacity, bathrooms, amenities, quoted price, first review and recent review counts. Calendar availability does not establish bookings, and the calendar contains no prices.

Cleaning addresses currency strings, missing values, bathroom descriptions and amenity lists. Revised parsers preserve identifier text, recognise half-baths and avoid counting commas inside amenity names as extra amenities. Quoted price is missing for 6,553 listings and bedrooms for 4,679. The median quoted price is AUD243.67 among 19,175 non-missing values. Price eligibility is a scope assumption, not proof that excluded values are erroneous.

After dwelling, price and history restrictions, 6,786 listings remain before partition and minimum-support rules. The final reference group has 899 listings from 424 hosts; its pooled P75 is 30 reviews. The separate analysis group contains 3,810 listings, 1,699 hosts and 14 segments, including 333 zero-review listings. Of these, 957 meet the benchmark (25.12%); integer ties are retained. Their median amenity count is 44 versus 43 below the benchmark. Both groups have median guest capacity four, so these pooled contrasts offer limited separation.

The original CSV links remain broken. This update uses saved cleaned data and aggregates; raw identifier precision, parsing and per-listing trailing-year review windows still require source verification. The history reference date does not substitute for an actual scrape date.

## Methodology and Analytical Approach

A fixed hash of host identifiers reserves approximately 20% of hosts for benchmark development. After removing those hosts, we apply the 50-listing rule to analysis cells. Reference listings satisfy the same primary eligibility and belong to those supported cells. Their pooled P75, rounded upward to an integer, supplies one common cutoff. Reference hosts enter no model training, evaluation or sensitivity analysis pool, and analysis outcomes cannot change the cutoff.

Descriptive tables report listing and distinct-host counts, quantiles, actual attainment and attribute profiles. Host-cluster bootstrap intervals account for shared operators. Wider dwelling and unrestricted-history comparisons assess composition sensitivity without claiming that excluded properties cannot be rented.

We fitted logistic regression and random forest using LGA, dwelling–bedroom configuration, capacity, bathrooms and amenities. Five-fold cross-validation separates analysis hosts. Imputation, encoding and scaling are fitted within training folds. Review-derived fields, ratings and host badges are excluded. Current price and minimum stay enter only an operating-controls sensitivity. Both models use fixed settings; no hyperparameter search has been conducted.

Evaluation covers ROC-AUC, average precision, Brier score, calibration bins and precision among the highest-scored quarter. Main logistic AUC is 0.568, average precision 0.278 and top-quarter precision 28.8%, against prevalence 25.1%. Its Brier score is 0.188, only slightly below the training-prevalence baseline of 0.190; forest AUC is 0.553. Calibration error across ten fixed-width bins is 3.66 percentage points for logistic regression. Only 22 listings receive scores of at least 0.5; these average 57.4%, but observed attainment is 31.8%, illustrating sparse and unreliable high-score estimates. Calibration has been assessed, not corrected.

Mean out-of-fold scores rank Melbourne three-bedroom apartments first at 34.6%, versus 36.5% observed across 304 listings. Conditional 95% host-bootstrap intervals hold fitted scores and the benchmark fixed, omitting model-fitting and benchmark-estimation uncertainty. The weak discrimination and calibration results do not establish a reliable best location. R supports cleaning and descriptive analysis; Python and scikit-learn support modelling.

## Analysis Plan and Progress to Date

The revised scope, reference partition, descriptive comparisons, two predictive baselines and three sensitivities have been implemented. Separate R and Python calculations agree on sample membership and the benchmark. Tests check host separation, minimum support and the cutoff's independence from analysis outcomes. Earlier corrections include the 90-date calendar window and exclusion of the incomplete final month from seasonality.

Removing the history restriction gives 6,675 analysis listings in 22 segments; removing the price filter gives 5,647 in 19. Their P75 values are both 23, while the reference cutoff remains 30. Adding operating controls raises logistic AUC to 0.713, which does not establish comparable performance using pre-opening information.

This design follows earlier exploration of the snapshot and provides no untouched final test. Week 9 will address raw-source verification and sparse outcomes. Week 10 will examine repeated host splits, broader dwelling definitions and calibration fitted within training data. Weeks 11–12 will cover nested tuning, refitted ranking uncertainty and final reporting. The README reproduces this report and links the code and outputs. Findings concern existing listings' preceding-year activity, not a new operator's future income.

## References

Cushman & Wakefield Georgia. (2019, June). *Tbilisi hospitality series: Airbnb* (pp. 13–14). [Report](https://cushwake.ge/wp-content/uploads/2025/06/MKTB_JUNE_AIRBNB.pdf).

Inside Airbnb. (2026). *Melbourne listings, calendar and reviews* [June 2026 dataset supplied through CMCE30005 LMS].

Scikit-learn developers. (n.d.). *Cross-validation* and *Probability calibration*. Retrieved 13 September 2026. [Grouped validation](https://scikit-learn.org/stable/modules/cross_validation.html#cross-validation-iterators-for-grouped-data); [Calibration guidance](https://scikit-learn.org/stable/modules/calibration.html).
