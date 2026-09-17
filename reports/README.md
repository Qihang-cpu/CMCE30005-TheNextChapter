# Report directory guide

## Submission files

- [Interim report Word](Interim_Project_Report.docx)
- [Interim report PDF](Interim_Project_Report.pdf)
- [Matching report text](interim-project-report.md)

The report includes the short AI Use Acknowledgement and references. No separate declaration attachment is required for this version.

## Used in the interim report

Every number in the report comes from one of these files; each file names the script that writes it.

| Report element | File | Script |
| --- | --- | --- |
| Table 1 sample funnel | `tables/rq_sample_funnel.csv` | `rq_scope_feasibility.py` |
| Reference-group P75 (29.75 → 30), segment and LGA counts | `tables/rq_scope_summary.json` | `rq_scope_feasibility.py` |
| Missing price and bedroom counts | `tables/desc_numeric_summary.csv` | `07_descriptive_analytics.R` |
| 366-date field and the 365-day recount | [data-validation-2026-09-15.md](data-validation-2026-09-15.md), `validation/raw-rerun-2026-09-15.json` | `rq_scope_feasibility.py` |
| Figure 1 segment ladder; attainment range 8.25–36.60% | `figures/16_segment_ladder.png`, `tables/segment_ladder.csv` | `08_peer_ranking.R` |
| Sensitivity without the history or price rule (17.51%, 18.29%) | `tables/review_scope_summary.csv` | `08_peer_ranking.R` |
| Share of unpriced listings with no recent review (82%) | `supporting/tables/revenue_sample_censoring.csv` | `supporting/04_revenue_analysis.R` |
| Table 2 model comparison; boosting AUC 0.647; price/minimum-stay models AUC 0.749 | `tables/rq_baseline_comparison.csv`, `tables/rq_baseline_fold_comparison.csv` | `11_segment_rate_baseline.py` |
| Twenty further host splits (mean AUC 0.626, range 0.589–0.648; top-three recurrence) | `tables/rq_repeated_split_summary.csv`, `tables/rq_repeated_split_top3.csv` | `11_segment_rate_baseline.py` |
| Table 3 candidates, predicted probabilities and 95% ranges | `tables/rq_extension_ranking.csv` | `10_model_extensions.py` |
| Nested model selection (forest chosen in all five outer folds; AUC +0.059, Brier −0.0055 with host-resampled ranges) and probability-bin calibration | `tables/rq_nested_selection_summary.json`, `rq_nested_selection_folds.csv`, `rq_nested_selection_inner.csv`, `rq_nested_calibration.csv`, `rq_nested_segment_calibration.csv` | `13_nested_selection.py` |
| Same candidates under support rules of 30, 50 and 75 and without the history or price rule | `tables/rq_support_rule_sensitivity.csv`, `tables/rq_support_rule_top3.csv` | `12_support_rule_sensitivity.py` |
| Out-of-time check (2,657 listings; 34-review target; 27.1% vs 14.9%; 95% range 5.1–20.1; top-three set recurs in 51.5%) | `validation/temporal-holdout/validation_metrics.json`, `segment_cross_period.csv`, `sample_flow.csv`, `bootstrap_replicates.csv`, [method note](validation/temporal-holdout/method-note.md) | `scripts/validation/temporal_holdout.py` |

Design and method notes behind the report: [research question and analysis plan](rq-analysis-plan.md), [methodology](methodology.md), [current findings](findings.md), [data description and limitations](data-notes.md), [descriptive analysis and sample definitions](descriptive-analytics.md).

## Supporting outputs (not cited in the report)

Written by the same pipeline; kept so results can be checked without re-running it.

- `rq_scope_feasibility.py`: `tables/rq_model_metrics.json` (baseline model metrics), `rq_benchmark_scope.csv` (reference-group scope), `rq_eligible_lga_configurations.csv` (segment eligibility), `rq_observed_segment_outcomes.csv`, `rq_oof_segment_ranking.csv` (out-of-fold segment scores), `rq_property_type_counts.csv`, `rq_calibration.csv` (probability bins).
- `08_peer_ranking.R`: `tables/benchmark_partition_summary.csv` (reference-host partition), `benchmark_map_by_segment.csv` and `benchmark_map_citywide.csv` (where the 30-review target sits in each segment's review distribution), `excluded_dwelling_types.csv`, `type_whitelist_sensitivity.csv` and `type_whitelist_lga_bedrooms_comparison.csv` (dwelling-type rule checks), `review_exposure_sensitivity.csv`, `segment_ladder_all_histories_sensitivity.csv`, `segment_ladder_no_price_sensitivity.csv`, `segment_ladder_bedroom_class_citywide.csv`, `tier_profile.csv` (what top-quartile listings look like); `figures/17_top_quartile_profile.png`.
- `07_descriptive_analytics.R`: `tables/desc_by_lga.csv`, `desc_by_room_type.csv`, `desc_by_superhost.csv`, `desc_categorical_summary.csv`; `figures/11_price_distribution_raw_log.png`, `12_categorical_composition.png`, `13_price_by_lga_roomtype.png`, `14_numeric_distributions.png`, `15_price_vs_reviews.png`.
- `09_probability_calibration.R`: `figures/18_probability_calibration.png`.
- `10_model_extensions.py`: `tables/rq_extension_metrics.csv` and `rq_extension_metrics.json` (all six model variants), `rq_extension_calibration.csv`, `rq_extension_provenance.json` (input hashes and package versions).
- `11_segment_rate_baseline.py`: `tables/rq_baseline_calibration.csv`, `rq_baseline_ranking_comparison.csv`, `rq_baseline_segment_ranking.csv`, `rq_repeated_split_metrics.csv`, `rq_segment_rate_baseline.json`.
- `validation/review-design-2026-09-14.json`: machine-readable check of the review-window and partition rules.

## Supporting analyses of the modelled price and revenue fields

`supporting/` holds the earlier descriptive work on Inside Airbnb's modelled price, occupancy and revenue fields. It supplies data-quality diagnostics only — the report cites one figure from it, the 82% share above — and establishes nothing about bookings, occupancy or profit: those fields are constructed from price, minimum stay and review counts, as [supporting/revenue-analysis.md](supporting/revenue-analysis.md) explains.

- `scripts/supporting/02_exploratory_analysis.R`: `supporting/tables/area_summary.csv`, `segment_revenue.csv`, `superhost_comparison.csv`, `seasonality_index.csv`; `supporting/figures/01_price_distribution.png`, `02_price_by_area.png`, `03_price_capacity_roomtype.png`, `04_demand_seasonality.png`, `05_price_vs_occupancy.png`.
- `scripts/supporting/03_price_model.R`: `supporting/tables/price_model_coefficients.csv` (hedonic price regression).
- `scripts/supporting/04_revenue_analysis.R`: `supporting/tables/revenue_sample_censoring.csv`, `revenue_variance_decomposition.csv`, `revenue_extensive_margin.csv`, `revenue_intensive_margin.csv`, `revenue_price_association_robustness.csv`, `revenue_superhost_gap.csv`, `revenue_by_listing_age.csv`; `supporting/figures/06_revenue_variance_decomposition.png`, `07_sample_censoring.png`, `08_revenue_price_activity_grid.png`, `09_activity_by_listing_age.png`.

## Archive

`validation/archive/` keeps the 13 September build record ([data-validation-2026-09-13.md](validation/archive/data-validation-2026-09-13.md) and its integrity JSON). Its counts are superseded by the 15 September verification above.
