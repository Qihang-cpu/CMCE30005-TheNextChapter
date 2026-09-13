# Melbourne Airbnb Performance

Interim Project Report

CMCE30005 Business Analytics Challenge | Semester 2 2026 | TheNextChapter Group 2

Eric Huang, Loc Le, Qihang Sun and Maksym Xu

Repository: [Qihang-cpu/CMCE30005-TheNextChapter](https://github.com/Qihang-cpu/CMCE30005-TheNextChapter)

## Introduction

A prospective operator considering several Airbnb properties in Melbourne needs evidence about which property configurations attract stronger demand before committing to leases and furnishings. Our project compares existing listings using the three Inside Airbnb files supplied for the subject. The sample contains 25,728 listings, with substantial differences in prices, property types and recent review activity. These differences make a single citywide average an inadequate guide to property selection.

Work completed so far establishes a data-cleaning pipeline, descriptive comparisons and exploratory regression models. It also identifies a constraint that changes the project: reported revenue is estimated and operating costs are absent. We therefore focus on relative listing performance rather than profitability. The intended output is an internal benchmarking framework and a validated model for identifying listings with high estimated revenue.

## Problem Definition and Objectives

Our research question is: **Which observable property characteristics are associated with high estimated annual revenue among comparable Melbourne Airbnb listings, and how accurately can models identify upper-quartile listings belonging to hosts excluded from model training?**

The descriptive objective is to compare revenue distributions and property characteristics across local government areas (LGAs) and dwelling configurations. The predictive objective is to classify listings above their segment's 75th revenue percentile. We propose an entire-home sample with one to three bedrooms, comparing listings within LGA, bedroom count and broad dwelling type. Segment sizes and missing classifications will be reported before modelling.

The upper quartile has an industry benchmarking precedent. Cushman & Wakefield Georgia (2019, pp. 13–14) compares Airbnb revenue at the median, 75th and 90th percentiles. Hawthorne (2024), writing for Rabbu, explicitly uses the 75th percentile as a short-term rental assessment benchmark. These sources motivate our choice; they do not establish a universal success or profitability threshold. Cutoffs will be calculated from the supplied data, with the 90th percentile used as a sensitivity check. No external market observations or cost estimates enter the analysis.

## Data Description

The supplied June 2026 snapshot comprises 25,728 listing records, approximately 9.39 million calendar records and 1.03 million reviews. Listing identifiers connect the files. Relevant variables include LGA, room and property type, bedrooms, bathrooms, guest capacity, amenities, quoted nightly price, minimum stay, host characteristics and review counts. Calendar records describe availability, not confirmed bookings, and contain no price column.

Cleaning scripts convert textual missing values and currency strings, parse bathroom descriptions and count listed amenities. Thirteen entirely empty columns are removed. Prices and estimated revenue are missing for 6,553 listings (25.5%); bedrooms are missing for 4,679 (18.2%). Exploratory price models use an AUD30–1,500 range, retaining 18,927 listings. This is a working filter, not a market definition: 82.0% of excluded listings have no review in the preceding year, compared with 23.7% of retained listings. Selection bias must therefore accompany any comparison.

Quoted prices are positively skewed: the median is AUD243.67 and the mean AUD317.65 among 19,175 listings with a non-missing quoted price. Entire homes account for 73.2% of the full sample. Within the filtered sample, median estimated annual revenue is AUD14,664 for entire homes and AUD936 for private rooms. This motivates comparison within similar property groups rather than interpreting the difference as a return from switching property type.

We verified that estimated revenue equals quoted price multiplied by estimated occupied nights, allowing for rounding. Estimated nights are themselves constructed from reviews and minimum-stay assumptions. These measures are imperfect proxies, and their rankings inherit those assumptions. Actual rent, cleaning, utilities and furnishing costs are unavailable. The snapshot also cannot identify genuine rental-arbitrage operators or establish future performance.

## Methodology and Analytical Approach

The completed descriptive analysis uses medians, distribution plots and grouped summaries. A hedonic ordinary least squares model relates log quoted price to listing attributes. Two exploratory activity models examine whether a listing has any recent review and, among active listings, its log review count. The activity models cluster standard errors by host to account for listings sharing an operator. These models describe associations and have not been validated on held-out data.

For prediction, we will compare logistic regression, providing an interpretable baseline, with a random forest that can capture nonlinear relationships. The main predictors will describe properties and amenities. Price, review counts, minimum-stay variables, estimated occupancy and their derivatives will be excluded because they construct the revenue target. Superhost status and review scores will also be excluded from the main model because they reflect prior operating outcomes and are unavailable when selecting a property before hosting.

Hosts will be separated into training and test groups using an 80/20 split. Five-fold cross-validation will also keep hosts separate. Imputation, segment cutoffs and tuning will be learned within training folds and then applied to validation or test listings. Sparse or unseen segments will be flagged rather than assigned unsupported local thresholds. We will report ROC-AUC against 0.5, and precision-recall AUC and precision among the highest-ranked quarter against held-out prevalence. The task predicts held-out listings' observed-snapshot classifications, not next year's income. R, data.table, ggplot2, broom and sandwich support completed work; ranger is planned for the forest.

## Analysis Plan and Progress to Date

Cleaning, exploratory summaries and regression analyses are complete. The price model uses 12,223 listings and achieves an adjusted R-squared of 0.558 for log price. This is in-sample fit, not predictive accuracy. The review-intensity model uses 12,648 listings and an adjusted R-squared of 0.411, indicating substantial unexplained variation. Scripts and result tables provide an audit trail for these findings.

The main adjustment is to replace the earlier profit and cash-return framing with internal performance benchmarking. An earlier external-rent screen is excluded from the current research question. The proposed predictive analysis remains unfinished; no test-set accuracy or classifier results are claimed.

By the end of Week 9, we will finalise comparable segments, inspect ties at percentile cutoffs and implement the host-grouped baseline. Week 10 will cover the forest, cross-validation and threshold sensitivity. Weeks 11–12 will focus on model interpretation, limitations and final reporting. Missing data and sparse segments are the main implementation risks. The repository README reproduces this interim report and links to the scripts and supporting analyses.

## References

Cushman & Wakefield Georgia. (2019, June). *Tbilisi hospitality series: Airbnb* (pp. 13–14). [Report](https://cushwake.ge/wp-content/uploads/2025/06/MKTB_JUNE_AIRBNB.pdf).

Hawthorne, T. (2024, December 10). *How to accurately estimate Airbnb revenue*. Rabbu. [Article](https://rabbu.com/blog/how-rabbu-uses-our-airbnb-calculator-internally).

Inside Airbnb. (2026). *Melbourne listings, calendar and reviews* [June 2026 dataset supplied through CMCE30005 LMS].


---

## Repository guide

The report above is the current interim submission. Editable and submission copies:

- [Word report](reports/Interim_Project_Report.docx)
- [PDF report](reports/Interim_Project_Report.pdf)
- [Report source](reports/interim-project-report.md)

### Current data scope

The analysis uses only the three CSV files supplied through CMCE30005 LMS. External publications are cited for benchmarking methodology; their observations, market revenue levels and cost estimates are not used in the models. Raw files are excluded from GitHub. Place `listings_airbnb.csv`, `calendar_airbnb.csv` and `reviews_airbnb.csv` in `data/raw/` to reproduce the work.

### Completed analysis

- [Data cleaning](scripts/01_data_cleaning.R) and [descriptive analytics](scripts/07_descriptive_analytics.R).
- [Exploratory comparisons](scripts/02_exploratory_analysis.R), [price model](scripts/03_price_model.R) and [review activity analysis](scripts/04_revenue_analysis.R).
- [Descriptive tables](reports/tables/) and [figures](reports/figures/).
- [Revenue construction and limitations](reports/revenue-analysis.md) and [descriptive write-up](reports/descriptive-analytics.md).

Predictive classification and host-grouped validation are planned, not completed. The current report supersedes previous profitability and cash-return research questions. Historical external-rent and ROI scripts (`05` and `06`), tables and discussion are retained as prior work but are outside the current submission's evidence and run order.

### Reproduce the completed internal analysis

Open `CMCE30005-Group2.Rproj`, then run:

```r
source("scripts/00_packages.R")
source("scripts/01_data_cleaning.R")
source("scripts/02_exploratory_analysis.R")
source("scripts/03_price_model.R")
source("scripts/04_revenue_analysis.R")
source("scripts/07_descriptive_analytics.R")
```

The scripts use R with data.table, ggplot2, scales, stringr, broom and sandwich. Script 07 additionally uses dplyr, tidyr, skimr and patchwork. Processed R objects can be regenerated; the summary outputs are available for review without rerunning the pipeline.

### Data validation

[Validation record, 13 September 2026](reports/data-validation-2026-09-13.md): the current report's main statistics and 13 regenerated result tables match the saved processed data. Raw-to-clean validation remains incomplete because the local raw CSV links are currently broken. The record also identifies historical wording errors and a derived availability-window issue.
