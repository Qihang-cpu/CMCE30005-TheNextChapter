# Melbourne Airbnb Market Screening

Interim Project Report

CMCE30005 Business Analytics Challenge | Semester 2 2026 | TheNextChapter Group 2

Eric Huang, Loc Le, Qihang Sun and Maksym Xu

Repository: https://github.com/Qihang-cpu/CMCE30005-TheNextChapter

## Introduction

Our client leases residential properties and runs them as Airbnb accommodation with the required permissions. This business model is called rental arbitrage. The client has limited start-up funds. They need to choose which Melbourne areas and property types to investigate before signing leases and buying furniture. A poor choice can tie up their money and delay the business. Our project helps the client narrow this search.

We use the Inside Airbnb dataset supplied by the school. It includes property details, locations and dated guest reviews. These fields allow us to compare existing listings. We group locations by Local Government Area (LGA), which means a municipal area. Each LGA can contain several suburbs. All numerical analysis uses the supplied dataset.

Our final output will be a shortlist of property segments for further investigation. We will compare their past review activity and test whether models improve on simple segment averages. The client can use the shortlist to guide property searches and request lease quotations. Financial assessment will require actual rent, furnishing costs and operating expenses, which this dataset does not contain.

## Problem Definition and Objectives

Our research question is: Which LGA, dwelling-type and bedroom-count segments have the highest average predicted probability of reaching a common upper-quartile review benchmark among eligible Melbourne listings? Predictions are tested on hosts excluded from model training. The outcome covers the year before each listing's scrape date.

We study standard entire homes with one to three bedrooms. Rental units and condos form the apartment group; homes and townhouses form the house group. These broad residential groups match the client's search and reduce fragmented categories, although properties still differ within them. At least 50 eligible listings provides minimum comparison support. This is an analytical choice, so we also report independent host counts. A first review at least 365 days earlier limits short review histories without proving continuous operation. Quoted prices of AUD30–1,500 define an exploratory sample boundary. Sensitivity checks assess these restrictions; none establishes lease availability.

The target records whether a listing reaches a common review-count threshold over the previous 365 days. Dated reviews give us an observable measure of guest-review activity across the supplied listings. This supports an initial comparison of areas and property types. The upper quartile defines relatively high activity within our reference sample. Short stays can generate more reviews than long stays with similar guest nights. Review willingness also varies. These differences limit comparisons and prevent estimates of bookings, occupancy or profit.

We will deliver a segment comparison table, a model-versus-baseline assessment and a shortlist with evidence strength and uncertainty. These outputs guide property searches before lease commitment.

## Data Description

The school dataset contains 25,728 listings with 90 variables, 9,390,720 calendar records and 1,026,690 reviews (Inside Airbnb, 2026). Scrape dates range from 17 June to 1 July 2026. We use LGA, property type, bedrooms, guest capacity, bathrooms, amenities and review dates. Calendar unavailability can include dates blocked by hosts. The calendar also contains no prices, so it cannot establish realised seasonal cash flow.

Cleaning converts price text into numbers, standardises missing values and extracts bathroom and amenity information. Price is missing for 6,553 listings and bedrooms for 4,679. We rebuild review counts over the preceding 365 days. GitHub records date-window checks and the sample-filtering table.

The separate reference sample contains 906 listings. Its 75th percentile is 29.75 reviews, giving an integer threshold of 30. The analysis sample contains 3,873 listings from 1,726 hosts in 14 segments. We keep 334 listings with zero annual reviews to include low-activity outcomes. Overall, 981 listings reach the threshold (25.33%).

Segment attainment ranges from 8.25% to 36.60%, supporting segment comparison. The sample covers six LGAs, with about 64% in Melbourne LGA. Holding the 30-review target fixed, removing the history rule gives 6,675 listings and 17.51% attainment. Removing the price restriction gives 5,720 listings and 18.29%. Both differ substantially from the primary 25.33%. Eligibility changes the population and its measured performance. These checks support limiting the shortlist to the stated sample; they have not established ranking stability under wider rules. Exited listings are absent.

## Methodology and Analytical Approach

A fixed rule based on host identifiers reserves about 20% of hosts to set the benchmark. These reference hosts are kept separate from model training and evaluation. The threshold stays fixed across comparisons. We use five-fold validation and keep each host's properties in one fold. This prevents the same host appearing in training and validation (scikit-learn developers, n.d.). Each training fold learns its own missing-value treatment and category encoding.

Logistic regression provides a simple reference model. Forest and boosting models capture nonlinear relationships. Basic features include location, configuration, capacity, bathrooms and amenity counts. Six extensions add coordinates, beds and nine facilities. We exclude review-based predictors, ratings and host badges. Separate operating-condition models include current price and minimum stay, whose timing limits pre-opening interpretation.

We compare models with a simple segment-rate baseline. It uses each segment's attainment among training hosts, with a fixed smoothing weight of ten. AUC measures ranking ability. Average precision summarises identification of listings reaching the target. Brier score measures probability error; lower values are better. Calibration checks predicted probabilities against observed rates. R supports cleaning and tables. Python pipelines keep validation steps consistent across models.

We refit models under 20 further host splits to check split sensitivity. These runs reuse the same data. We assume current property details are relevant to preceding-year activity, although they may have changed during that year. Property-only models therefore remain historical comparisons. Current intervals hold predictions fixed and omit model-selection and benchmark uncertainty. Model choice remains exploratory, with no untouched final test.

## Analysis Plan and Progress to Date

We replaced the original ROI and quarterly design with historical review analysis from the school snapshot. Weak basic-model results prompted the segment baseline. Cleaning, review reconstruction, descriptive analysis and grouped validation are complete. Table 1 uses the same sample and folds.

Table 1. Predictive performance

| Predictor | AUC | Average precision | Brier score |
| --- | --- | --- | --- |
| Training-host segment rate | 0.581 | 0.285 | 0.1868 |
| Original property-only logistic | 0.573 | 0.285 | 0.1886 |
| Enhanced property-only forest | 0.640 | 0.350 | 0.1813 |

Basic logistic and forest models underperform segment rates. The enhanced forest raises AUC by 0.059 and reduces Brier by 0.0055, a 2.9% reduction in probability error. Both improve in all five folds. We provisionally select it for the lowest property-only Brier; boosting has higher AUC at 0.647. Across 20 further host splits, forest AUC averages 0.626 (range 0.589–0.648), exceeding the segment baseline each time. The consistent, moderate gain supports further validation.

Table 2 answers the RQ using the enhanced forest's mean predictions. Each prediction comes from a model trained without that listing's host. All property-only models identify the same main top-three set as the segment baseline.

Table 2. Initial search candidates

| Segment | Listings / hosts | Observed attainment | Mean predicted probability |
| --- | --- | --- | --- |
| Melbourne three-bedroom apartments | 306 / 139 | 36.60% | 34.45% |
| Melbourne two-bedroom apartments | 1,235 / 482 | 32.79% | 31.41% |
| Yarra Ranges three-bedroom houses/townhouses | 90 / 77 | 30.00% | 27.82% |

Melbourne three-bedroom apartments rank first in all 20 further forest splits. The top-three set appears in 19. Yarra Ranges has a smaller evidence base. Split checks support the initial candidates, while wider-rule ranking sensitivity remains pending. Scores describe historical attainment among existing listings. Improvement within individual segments and future new-operator outcomes remain untested.

Segment rates provide a transparent starting shortlist. The forest adds property-level scores based on recorded attributes and improves overall prediction, with no change to the main candidates. We have not measured better investigation decisions or financial returns. The client can prioritise searches and lease enquiries in these segments, then check permissions, availability and actual costs before signing.

Next, inner training folds will select models and outer folds will evaluate that process. Refitted uncertainty estimates and wider dwelling/support rules will test the shortlist. We will report paired Brier differences, calibration-bin rates and candidate recurrence. Confirmed gains require lower Brier without worse calibration. Stable candidates across scope checks support stronger search priorities. If gains disappear, segment rates lead the screening. Unstable rankings produce a broader candidate list. These tasks remain planned; repeated splits have already tested one source of uncertainty.

## References

Inside Airbnb. (2026). Melbourne listings, calendar and reviews [June 2026 dataset supplied through CMCE30005 LMS].

Scikit-learn developers. (n.d.). Cross-validation and probability calibration. https://scikit-learn.org/stable/modules/cross_validation.html#cross-validation-iterators-for-grouped-data ; https://scikit-learn.org/stable/modules/calibration.html

OpenAI. (2026). ChatGPT/Codex assistance with project planning, report drafting and code review [Generative AI outputs, September 2026].

Anthropic. (2026). Claude Code assistance with analysis-code development [Generative AI outputs, September 2026].

## AI Use Acknowledgement

We used OpenAI ChatGPT/Codex and Anthropic Claude Code to support project planning, analysis-code development, interpretation of results, report drafting and English editing. This included refining the research question and reviewing the validation approach. AI-assisted text and code are included in the project. The group is responsible for the accuracy and content of the final submission.

## Project files

The submission files are `reports/Interim_Project_Report.docx` and its PDF. Both include the AI Use Acknowledgement. `reports/interim-project-report.md` is the matching text version. See the [report directory guide](reports/README.md) for current evidence and supporting analyses.

- [Interim report Word](reports/Interim_Project_Report.docx) · [PDF](reports/Interim_Project_Report.pdf)
- [Research design](reports/rq-analysis-plan.md) · [Methodology](reports/methodology.md) · [Data notes](reports/data-notes.md)
- [Raw-data validation](reports/data-validation-2026-09-15.md) · [Machine-readable checks](reports/validation/raw-rerun-2026-09-15.json)
- [Sample funnel](reports/tables/rq_sample_funnel.csv) · [Descriptive segments](reports/tables/segment_ladder.csv)
- [Baseline metrics](reports/tables/rq_model_metrics.json) · [Extension comparison](reports/tables/rq_extension_metrics.csv) · [Extension rankings](reports/tables/rq_extension_ranking.csv)
- [Segment-rate baseline comparison](reports/tables/rq_baseline_comparison.csv) · [Per-fold differences](reports/tables/rq_baseline_fold_comparison.csv) · [Repeated host partitions](reports/tables/rq_repeated_split_top3.csv)

### Reproducing the analysis

Place the original school-supplied `listings_airbnb.csv`, `calendar_airbnb.csv` and `reviews_airbnb.csv` in `data/raw/`. The source rebuild used these restored original files on 15 September, followed by a cross-platform compatibility rerun on 16 September; their hashes are recorded in the validation output. Raw data and listing-level predictions are excluded from Git.

Install the R packages listed in `scripts/00_packages.R`, then run the following from the project root:

```sh
Rscript scripts/00_packages.R
Rscript scripts/01_data_cleaning.R
Rscript scripts/02_exploratory_analysis.R
Rscript scripts/03_price_model.R
Rscript scripts/04_revenue_analysis.R
Rscript scripts/07_descriptive_analytics.R
python -m pip install -r requirements-analysis.txt
python scripts/rq_scope_feasibility.py
Rscript scripts/08_peer_ranking.R
Rscript scripts/09_probability_calibration.R
python scripts/10_model_extensions.py
python scripts/11_segment_rate_baseline.py --repeats 20
```

Script 01 stages cleaned files until all input checks pass and records their hashes. The supplied `number_of_reviews_ltm` matches a 366-date inclusive window; it is preserved. The primary `reviews_365d` outcome is reconstructed over `(last_scraped − 365 days, last_scraped]`. The Python workflow independently checks all source review counts and publishes results only after every baseline model finishes. Script 08 requires matching input and configuration hashes before ranking. Script 10 holds the primary sample, outcomes and outer host folds fixed while evaluating all six extensions in separate outputs. Script 11 scores a segment-rate baseline on those same folds, using training-host outcomes only, places it beside every model, and then reassigns hosts to folds under 20 further seeds to check how stable the metrics and the top-ranked segments are.

The main screening model provisionally uses detailed property features and random forest. The original baselines remain available for comparison. Price/revenue scripts are supporting analyses of the supplied fields; they do not establish profit. All numerical inputs come from the school data. References concern methodology, and no external market or rent observations are added.

The shared scope and benchmark rules are in [config/review_analysis.json](config/review_analysis.json). The reference-host P75 is calculated once and its integer cutoff is held fixed across all comparisons; the RQ does not contain a fixed review count. Original identifiers, host-fold assignments and detailed review comparisons remain in ignored `data/processed/` files.

Run the regression checks separately; they use temporary synthetic data and do not overwrite report results:

```sh
python -m unittest discover -s tests -v
Rscript tests/test_cleaning_consistency.R
Rscript tests/test_peer_inputs.R
```

The dated 13–14 September validation records document the earlier cached-data analysis. The 15 September raw-data record, including the 16 September compatibility rerun, is the current verification.
