# Report directory guide

## Submission files

- [Interim report Word](Interim_Project_Report.docx)
- [Interim report PDF](Interim_Project_Report.pdf)
- [Matching report text](interim-project-report.md)

The report includes the short AI Use Acknowledgement and references. No separate declaration attachment is required for this version.

## Current research design and findings

- [Research question and analysis plan](rq-analysis-plan.md)
- [Methodology](methodology.md)
- [Current findings](findings.md)
- [Data description and limitations](data-notes.md)
- [Descriptive analysis and sample definitions](descriptive-analytics.md)

The primary outcome is preceding-year guest-review activity. The supported shortlist concerns established residential listings in the specified sample.

## Current numerical evidence

The `tables/` folder contains aggregate outputs. Main report evidence includes:

- `rq_sample_funnel.csv` and `rq_scope_summary.json`: eligible sample and benchmark.
- `segment_ladder.csv`: descriptive segment comparison.
- `rq_baseline_comparison.csv` and `rq_baseline_fold_comparison.csv`: models compared with training-host segment rates.
- `rq_extension_metrics.csv` and `rq_extension_ranking.csv`: enhanced model performance and candidate scores.
- `rq_repeated_split_summary.csv` and `rq_repeated_split_top3.csv`: repeated host-split checks.
- `rq_extension_calibration.csv`: probability-bin observations.

The `figures/` folder contains both current and supporting charts; filenames alone do not identify the primary analysis population. Use the relevant methods document and source table.

## Supporting analyses and validation history

[Revenue diagnostics](revenue-analysis.md) explain limitations of the supplied modelled revenue fields. Their broader sample differs from the primary cohort. Revenue, occupancy, price and seasonality outputs are supporting diagnostics, not profit estimates or current investment recommendations.

[Raw-data validation](data-validation-2026-09-15.md) and `validation/raw-rerun-2026-09-15.json` document the current rebuild and compatibility checks. Dated 13–14 September records preserve earlier validation history.

Older files are retained to preserve the analysis record. Formal submission and current conclusions should be read from the submission files and current findings above.
