# Melbourne Airbnb Review Activity

Interim Project Report

CMCE30005 Business Analytics Challenge | Semester 2 2026 | TheNextChapter Group 2

Eric Huang, Loc Le, Qihang Sun and Maksym Xu

Repository: [Qihang-cpu/CMCE30005-TheNextChapter](https://github.com/Qihang-cpu/CMCE30005-TheNextChapter/tree/interim-report-2026-09-13)

## Introduction

A prospective operator considering several Airbnb properties in Melbourne needs a way to compare locations and dwelling configurations before committing to leases and furnishings. The school-supplied Inside Airbnb snapshot contains considerable variation in quoted prices and recent guest reviews. Citywide averages conceal these differences, while comparisons between conventional apartments and specialised holiday accommodation can be misleading.

Our project combines descriptive comparisons with predictive modelling of review activity. The business output is a shortlist of comparable residential segments for further investigation. Reviews provide an observable activity measure, but they do not measure profit. Because actual leases and operating costs are unavailable, we have removed external-rent scenarios from the current analysis.

## Problem Definition and Objectives

Our research question is: **Among Greater Melbourne standard entire-home segments with at least 50 eligible listings, which LGA × dwelling-type × bedroom configurations have the highest mean out-of-sample predicted probability of recording at least 22 guest reviews in the twelve months preceding the snapshot?**

The descriptive objective is to compare review distributions, attainment rates and property attributes. The predictive objective is to assess whether property information distinguishes higher-activity listings belonging to hosts excluded from training.

Eligible listings are entire homes with one to three bedrooms, quoted prices of AUD30–1,500, and one of four dwelling types: rental unit, condo, home or townhouse. Apartments and condos form one class; homes and townhouses form the other. At least 50 listings must remain in each LGA–class–bedroom cell after these filters. This defines comparable residential stock without claiming that particular properties are available to lease.

The eligible sample's observed 75th percentile is 22 reviews. We retain that fixed event across modelling and sensitivity analyses. Because of ties, 25.82% meet it. Industry reports use percentile comparisons for revenue benchmarking (Cushman & Wakefield Georgia, 2019), but our review threshold comes from the supplied data. It is neither a whole-market benchmark nor a profitability threshold, and cross-validation does not independently establish the choice of 22.

## Data Description

The June 2026 dataset comprises 25,728 listings, approximately 9.39 million calendar records and 1.03 million reviews. Relevant variables include listing and host identifiers, LGA, dwelling type, bedrooms, capacity, bathroom descriptions, amenities, quoted price and recent review counts. Calendar availability does not establish bookings, and the calendar file contains no prices.

Cleaning converts currency strings and missing values and derives bathroom counts and amenity counts. The revised parsers preserve identifiers as text, recognise half-baths and parse amenity lists without treating commas inside names as additional amenities. Price and estimated revenue are each missing for 6,553 listings; bedrooms are missing for 4,679. The median quoted price is AUD243.67 among 19,175 non-missing values, compared with AUD242.50 in the 18,927-listing price-filtered sample.

The main scope contains 8,967 listings, 4,081 hosts and 35 eligible segments. It retains 1,428 listings with zero reviews in the preceding year. Excluding these would remove relevant low-activity outcomes. There are 2,315 listings with at least 22 reviews. Their median amenity count is 46, compared with 42 below the threshold; both groups have a median capacity of four guests. These pooled differences describe composition rather than causal effects.

A current reproducibility limitation is that the local links to the original CSV files are broken. This update was rerun from the saved cleaned snapshot and aggregates. Their results can be reproduced, but original identifier precision, parsing and per-listing review windows still require verification against restored source files. First-review dates also indicate review history, not opening dates or continuous operation.

## Methodology and Analytical Approach

The descriptive stage reports each segment's sample size, distinct hosts, review quantiles and observed attainment rate. Host-cluster bootstrap intervals account for listings sharing an operator. The same eligible listings and fixed outcome feed the predictive stage, linking the segment comparisons to a common classification task.

We fitted a regularised logistic regression and a random forest using LGA, configuration, guest capacity, bathroom count and amenity count. Reviews, ratings, Superhost status and estimated occupancy or revenue are excluded as predictors. Current price and minimum stay enter only a separate operating-controls sensitivity because they describe contemporaneous business settings.

Five-fold cross-validation separates hosts: no host appears in both training and validation within a fold. Imputation, category encoding and standardisation are fitted inside each training fold, following the scikit-learn guidance on avoiding information leakage. Both models use the same folds and fixed settings. These are exploratory cross-validation results, with no hyperparameter search or independent final test set.

Evaluation includes ROC-AUC, average precision, Brier score, calibration summaries and precision among the highest-scored quarter. The main logistic model achieves AUC 0.649, average precision 0.361 and Brier score 0.182. Its top-quarter precision is 37.8%, compared with the sample prevalence of 25.8%. The forest achieves AUC 0.631 and average precision 0.348. Adding operating controls raises logistic AUC to 0.720; this does not establish equivalent performance using information verified before opening.

Segment rankings average out-of-fold probabilities. Melbourne three-bedroom apartments have the highest mean logistic score, 39.5%, compared with an observed attainment rate of 39.8% across 543 listings. The accompanying intervals resample hosts while holding fitted scores fixed; they omit model-fitting uncertainty and do not establish a definitive best location. R supports cleaning and descriptive analysis; Python, pandas and scikit-learn support predictive validation.

## Analysis Plan and Progress to Date

The audit of the available cleaned data, descriptive segment comparisons, two predictive baselines and three sensitivity scenarios are complete. R and Python implementations agree on the main sample and labels. Separate calculations reproduce the model metrics and grouped predictions. Earlier cleaning issues identified during review include a 91-date availability window and an incomplete final month in the seasonality calculation; the code now uses 90 dates and excludes the final observed month respectively.

Restricting first reviews to on or before 1 June 2025 and reapplying the 50-listing rule leaves 4,812 listings in 16 segments. Their P75 is 29, demonstrating that review-history restrictions change the benchmark. The sensitivity retains the fixed 22-review event and zero-review outcomes. Removing the price filter gives a further check on sample selection.

Week 9 will focus on restoring raw files, verifying identifiers and review windows, and assessing sparse positive outcomes. Week 10 will test repeated host splits, broader dwelling mappings and model tuning within nested validation. Weeks 11–12 will cover ranking uncertainty and final reporting. The README reproduces this report and links to the scripts, tables and figures. The findings support screening existing comparable listings; they do not forecast a new operator's future income.

## References

Cushman & Wakefield Georgia. (2019, June). *Tbilisi hospitality series: Airbnb* (pp. 13–14). [Report](https://cushwake.ge/wp-content/uploads/2025/06/MKTB_JUNE_AIRBNB.pdf).

Inside Airbnb. (2026). *Melbourne listings, calendar and reviews* [June 2026 dataset supplied through CMCE30005 LMS].

Scikit-learn developers. (2025). *Cross-validation* and *Common pitfalls and recommended practices*. [Validation guidance](https://scikit-learn.org/1.7/modules/cross_validation.html); [Preprocessing guidance](https://scikit-learn.org/1.7/common_pitfalls.html).
