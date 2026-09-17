# Melbourne Airbnb Market Screening

Interim Project Report

CMCE30005 Business Analytics Challenge | Semester 2 2026 | TheNextChapter Group 2

Eric Huang, Loc Le, Qihang Sun and Maksym Xu

Repository: https://github.com/Qihang-cpu/CMCE30005-TheNextChapter

## Introduction

Our goal of the project is supporting suggestions to our client who leases residential properties and runs them as Airbnb accommodation with the required permissions. The client has limited start-up funds, and a poor choice can tie up their money and delay the business. 

We use the Inside Airbnb Melbourne snapshot of June 2026 supplied through the subject’s LMS (Inside Airbnb, 2026): property details, locations and dated guest reviews. Because a review can only follow a completed stay, dated reviews are a countable record of past guest activity; the calendar cannot separate bookings from host-blocked dates.

Our final output will be a shortlist of property segments for further investigation. We will compare their past review activity and test whether models improve on simple segment averages. Then we can support shortlists to our clients for property searches and request lease quotations. 

## Problem Definition and Objectives

The research question of our project is: 1. Which Melbourne property segments — defined by council area (LGA), apartment or house, and number of bedrooms — show the strongest historical guest-review activity? 2. Can listing attributes improve prediction of high review activity beyond segment averages? “High” means at least 30 reviews in the year before the data were collected, the top quarter of a separate reference group of comparable listings.

We study standard entire homes with one to three bedrooms and separate the homes into apartment group and house group. Rental units and condos are in the apartment group; homes and townhouses are in the house group. Although there are differences within properties, these broad residential groups match the client's search and reduce fragmented categories. We choose at least 50 eligible listings as minimum comparison support for our analysis and narrow the exploratory sample price boundary to AUD30–1,500 based on the truth. The first review at least 365 days before collection gives us at least one year of observable review history. Therefore, we use sensitivity checks to assess these restrictions and conclude that none of them establishes the lease availability.

For the reviews, we call the share of listings reaching 30 reviews “attainment”, that means at least 30 reviewed stays, roughly one every 12 days. Attainment measures review activity, not bookings, occupancy or profit.

## Data Description

The Airbnb dataset contains 25,728 listings with 90 variables, 9,390,720 calendar records and 1,026,690 reviews (Inside Airbnb, 2026). The scrape dates range from 17 June to 1 July 2026. Calendar unavailability can include dates blocked by hosts. The calendar also contains no prices, so it cannot establish realized seasonal cash flow.

The variables we use in the dataset is LGA, property type, bedrooms, guest capacity, bathrooms, amenities and review dates. Cleaning converts price text to numbers, standardises missing values and extracts bathroom and amenity counts; price is missing for 6,553 listings and bedrooms for 4,679. The supplied last-12-months review field spans 366 dates, so we rebuilt counts over exactly 365 days from review dates (Table 1).

Table 1. Sample funnel

| Stage | Listings |
| --- | --- |
| All listings in the dataset | 25,728 |
| Entire homes, 1–3 bedrooms | 16,576 |
| Standard dwelling types | 14,895 |
| Quoted price AUD 30–1,500 | 11,099 |
| First review ≥ 365 days before collection | 6,891 |
| Analysis sample (50+ per segment, reference hosts excluded) | 3,873 |
| Reference group (separate, from the 6,891) | 906 |

The reference group’s 75th percentile is 29.75 reviews, giving a threshold of 30. The analysis sample (3,873 listings from 1,726 hosts) has 14 segments across six LGAs and keeps 334 listings with zero annual reviews. Overall, 981 listings (25.33%) reach the threshold, and attainment ranges from 8.25% to 36.60% across segments (Figure 1).

![Figure 1. Share of listings reaching 30 reviews by segment; lines are 90% host-resampled ranges, dashed line the pooled 25.33% rate.](reports/figures/16_segment_ladder.png)

Of the 6,801 listings with no usable price (missing or outside AUD 30–1,500), there are 82% of them had no review in the past year, so the priced sample is the more active part of the market. Listings that left Airbnb before collection are absent, which limits generalisation to new entrants.

## Methodology and Analytical Approach

During the analysis, a fixed rule based on host identifiers reserves about 20% of hosts to set the benchmark. These reference hosts are kept separate from model training and evaluation and the threshold stays fixed across comparisons. We use five-fold validation and keep each host's properties in one-fold. This prevents the same host appearing in training and validation (scikit-learn developers, n.d.). Each training fold learns its own missing-value treatment and category encoding.

For the model, we use logistic regression model to provides a simple reference model and forest and boosting models to capture nonlinear relationships. Basic features include location, configuration, capacity, bathrooms and amenity counts. Six extensions add coordinates, beds and nine facilities. We exclude review-based predictors, ratings and host badges. Separate operating-condition models include current price and minimum stay, whose timing limits pre-opening interpretation. Every model is compared with a segment-average baseline: each listing gets its segment’s attainment among training hosts. We use AUC as measurement of the ranking ability. Average precision summarises identification of listings reaching the target and the Brier score measures probability error: lower values are better. Calibration checks predicted probabilities against observed rates. We use R to support cleaning and tables and Python to pipeline keep validation steps consistent across models.

## Analysis Plan and Progress to Date

We dropped the earlier rent-versus-revenue (ROI) design, which needed external rental data, and now compare only within the snapshot. Cleaning, review reconstruction, descriptive analysis and validation are complete. Therefore, during the analysis, we use two hypotheses: (H1) segments differ materially in the share of listings reaching that level; (H2) a model using listing attributes ranks listings better than the segment average alone.

Table 2 uses the same sample and folds.


| Predictor | AUC | Average precision | Brier score |
| --- | --- | --- | --- |
| Segment average (training hosts) | 0.581 | 0.285 | 0.1868 |
| Basic property-only logistic | 0.573 | 0.285 | 0.1886 |
| Enhanced property-only random forest | 0.640 | 0.350 | 0.1813 |

After the detect, we find the enhanced random forest raises AUC by 0.059 and lowers Brier by 0.0055, beating the segment average in all five folds; across 20 further host splits it wins on AUC every time (mean 0.626, range 0.589–0.648) and on Brier in 16. Adding current price and minimum stay lifts boosting to AUC 0.749 and Brier 0.162, but these are present-day settings, not pre-opening attributes, so they stay out of the shortlist.

Table 3 answers the RQ using the enhanced forest's mean predictions. Each prediction comes from a model trained without that listing's host. All property-only models identify the same main top-three set as the segment baseline.

| Segment | Listings / hosts | Observed attainment | Predicted probability | 95% range |
| --- | --- | --- | --- | --- |
| Melbourne 3BR apartments | 306 / 139 | 36.60% | 34.45% | 33.0–35.8% |
| Melbourne 2BR apartments | 1,235 / 482 | 32.79% | 31.41% | 29.6–33.0% |
| Yarra Ranges 3BR houses/townhouses | 90 / 77 | 30.00% | 27.82% | 26.1–29.3% |

We find that Melbourne three-bedroom apartments rank first in all 20 further forest splits. The top-three set appears in 19. Yarra Ranges has a smaller evidence base. Descriptive evidence supports H1: segments differ (8.25% to 36.60%), though neighboring segments overlap. H2 is supported by exploratory host-grouped validation on ranking metrics but not on the shortlist: the model changes no candidate, so segment comparison carries the decision, and the model adds a supplementary historical score.

The out-of-time check (2,657 listings, 1,208 hosts, 10 segments, two years of reviews) uses two non-overlapping 365-day windows and a 34-review target set from the reference hosts’ earlier window. The earlier year’s top three segments reached it in 27.1% of listings the following year against 14.9% elsewhere, a 12.3-point lead (host-resampled 95% range 5.1–20.1); the exact top-three set recurred in 51.5% of resamples. This is a persisting historical advantage, not a new operator’s profit.

For the works in the next stage, inner training folds will select models and outer folds will evaluate that process. Refitted uncertainty estimates and wider dwelling/support rules will test the shortlist. We will report paired Brier differences, calibration-bin rates and candidate recurrence. Confirmed gains require lower Brier without worse calibration. Stable candidates across scope checks support stronger search priorities. More specific plan will be showed on the GitHub README page.


## References

Anthropic. (2026). Claude Code assistance with analysis-code development
[Generative AI output].

Inside Airbnb. (2026). Melbourne listings, calendar and reviews [June
2026 dataset supplied through CMCE30005 LMS].

OpenAI. (2026). ChatGPT/Codex assistance with project planning, report
drafting, and code review [Generative AI output].

Scikit-learn developers. (n.d.). Cross-validation: Evaluating estimator
performance. https://scikit-learn.org/stable/modules/cross_validation.html#cross-validation-iterators-for-grouped-data

Scikit-learn developers. (n.d.). Probability calibration.
https://scikit-learn.org/stable/modules/calibration.html


## AI Use Acknowledgement

We used OpenAI ChatGPT/Codex and Anthropic Claude Code to support project planning, analysis-code development, additional source searching and editing. This included refining the research question and reviewing the validation approach. The group is responsible for the accuracy and content of the final submission.

## Project files

The submission files are `reports/The%20interim%20report.docx` and its PDF. Both include the AI Use Acknowledgement. `reports/interim-project-report.md` is the matching text version. See the [report directory guide](reports/README.md) for current evidence and supporting analyses.

- [Interim report Word](reports/The%20interim%20report.docx) · [PDF](reports/The%20interim%20report.pdf)
- [Research design](reports/rq-analysis-plan.md) · [Methodology](reports/methodology.md) · [Data notes](reports/data-notes.md)
- [Raw-data validation](reports/data-validation-2026-09-15.md) · [Machine-readable checks](reports/validation/raw-rerun-2026-09-15.json) · [Figure 1](reports/figures/16_segment_ladder.png)
- [Sample funnel](reports/tables/rq_sample_funnel.csv) · [Descriptive segments](reports/tables/segment_ladder.csv)
- [Baseline metrics](reports/tables/rq_model_metrics.json) · [Extension comparison](reports/tables/rq_extension_metrics.csv) · [Extension rankings](reports/tables/rq_extension_ranking.csv)
- [Segment-rate baseline comparison](reports/tables/rq_baseline_comparison.csv) · [Per-fold differences](reports/tables/rq_baseline_fold_comparison.csv) · [Repeated host partitions](reports/tables/rq_repeated_split_top3.csv)
- [Support-rule sensitivity](reports/tables/rq_support_rule_sensitivity.csv) · [Out-of-time check](reports/validation/temporal-holdout/method-note.md)

### Reproducing the analysis

Place the original school-supplied `listings_airbnb.csv`, `calendar_airbnb.csv` and `reviews_airbnb.csv` in `data/raw/`. The source rebuild used these restored original files on 15 September, followed by a cross-platform compatibility rerun on 16 September; their hashes are recorded in the validation output. Raw data and listing-level predictions are excluded from Git.

Install the R packages listed in `scripts/00_packages.R`, then run the following from the project root:

```sh
Rscript scripts/00_packages.R
Rscript scripts/01_data_cleaning.R
Rscript scripts/07_descriptive_analytics.R
python -m pip install -r requirements-analysis.txt
python scripts/rq_scope_feasibility.py
Rscript scripts/08_peer_ranking.R
Rscript scripts/09_probability_calibration.R      # supporting figure only
python scripts/10_model_extensions.py
python scripts/11_segment_rate_baseline.py --repeats 20
python scripts/12_support_rule_sensitivity.py
python scripts/validation/temporal_holdout.py
Rscript scripts/supporting/04_revenue_analysis.R  # supplies the unpriced-listing review share
```

Supporting analyses of Inside Airbnb's modelled price and revenue fields (`scripts/supporting/02_exploratory_analysis.R`, `03_price_model.R`, `04_revenue_analysis.R`) are data-quality diagnostics, not part of the candidate ranking; the report cites one descriptive statistic from them (the share of unpriced listings with no recent review). They run from the project root after script 01 and write to `reports/supporting/`. See [reports/README.md](reports/README.md) for which files the report uses.

Script 01 stages cleaned files until all input checks pass and records their hashes. The supplied `number_of_reviews_ltm` matches a 366-date inclusive window; it is preserved. The primary `reviews_365d` outcome is reconstructed over `(last_scraped − 365 days, last_scraped]`. The Python workflow independently checks all source review counts and publishes results only after every baseline model finishes. Script 08 requires matching input and configuration hashes before ranking. Script 10 holds the primary sample, outcomes and outer host folds fixed while evaluating the six model variants in separate outputs. Script 11 scores a segment-rate baseline on those same folds, using training-host outcomes only, places it beside every model, and then reassigns hosts to folds under 20 further seeds to check how stable the metrics and the top-ranked segments are.

The main screening model provisionally uses detailed property features and random forest; the original baselines remain available for comparison. The supporting price/revenue scripts describe Inside Airbnb's modelled fields only and establish nothing about bookings, occupancy or profit. All numerical inputs come from the school data. References concern methodology, and no external market or rent observations are added.

The shared scope and benchmark rules are in [config/review_analysis.json](config/review_analysis.json). The reference-host P75 is calculated once and its integer cutoff is held fixed across all comparisons; the 30-review level in the research question is that computed cutoff, not an externally chosen number. Original identifiers, host-fold assignments and detailed review comparisons remain in ignored `data/processed/` files.

Run the regression checks separately; they use temporary synthetic data and do not overwrite report results:

```sh
python -m unittest discover -s tests -v
Rscript tests/test_cleaning_consistency.R
Rscript tests/test_peer_inputs.R
```

The dated 13–14 September validation records document the earlier cached-data analysis. The 15 September raw-data record, including the 16 September compatibility rerun, is the current verification.
