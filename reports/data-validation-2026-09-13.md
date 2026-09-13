# Analysis validation record

Updated 13 September 2026 after the review-activity pipeline revision.

## Conclusion

The current descriptive and predictive outputs reproduce from the saved school-data snapshot. The primary R and Python samples match listing by listing: 8,967 listings, 4,081 hosts and 35 segments, including 1,428 zero-review listings. Original CSV files are unavailable at their linked paths, so raw-to-clean validation remains incomplete. No result should be described as verified actual occupancy, income or profit.

## Checks completed

| Check | Result |
|---|---|
| Listing identifiers in the saved snapshot | 25,728 non-missing, unique values; 142 are represented in scientific notation upstream |
| Saved review aggregates | Monthly and listing totals both equal 1,026,690; listing totals and latest dates match the saved listings |
| Saved calendar aggregate | 9,390,720 rows represented in monthly totals |
| Price filter | 18,927 retained; 6,553 missing, 45 below AUD30 and 203 above AUD1,500 excluded |
| Quoted-price medians | AUD243.67 among 19,175 non-missing prices; AUD242.50 in the filtered sample |
| Occupancy formula | All 25,719 comparable rows match the supplied review-based formula; nine missing minimum stays cannot be checked |
| Estimated revenue formula | All 19,175 comparable rows match price × estimated nights within AUD0.50 |
| Primary scope | Independently reproduced 35 cells, 8,967 listings, 4,081 hosts and 2,315 outcomes of at least 22 reviews |
| Descriptive results | Nine new tables independently recalculated, including all segment quantiles, rates and profiles |
| Bootstrap | A segment's 1,000 host-cluster resamples independently recomputed by expanding the sampled hosts' listings |
| Predictive validation | All eight model/scenario OOF sets checked independently for ROC-AUC, tied-score average precision and Brier score |
| Host separation | Each host has one fold; no training/validation host overlap within a fold |
| R/Python consistency | Main and review-history sensitivity listing IDs, host IDs and outcomes match after lossless text-format normalisation |
| Public outputs | Aggregate tables only; listing predictions, host-fold assignments and review-ID diagnostics remain in ignored processed-data files |

The old price and review models were reproduced before revision. After the date-proxy correction, the exploratory review-intensity model now uses 12,651 observations, 6,252 host clusters and adjusted R² 0.403. That fit is descriptive and is not the primary classifier's accuracy.

## Corrections applied

The primary outcome is a fixed 22-review event, with its exploratory P75 origin stated as applying to the eligible sample. Zero-review listings are retained. Four standard dwelling types define the main scope without asserting lease availability. Every ranked main segment meets the 50-listing rule after all filters. Earlier external-rent calculations and external monetary comparison lines are outside the current submission tree.

The Python model now learns imputation, category encoding and scaling within training folds. Standard metric implementations handle tied probabilities. Current quoted price and minimum stay appear only in a labelled operating-controls sensitivity. Both fixed model specifications are reported, with no claim of an independently selected best model or an untouched final test set.

The cleaning script now preserves ID text, parses amenity JSON, recognises half-baths and uses a 90-date window for each listing. These raw-data transformations still need a full run when the original files are restored. The current saved availability aggregate is from the older window calculation and is not consumed by the primary analysis.

The seasonality calculation now uses June 2023 through May 2026, excluding the incomplete final observed month. The exploratory review-history model uses the latest observed review date, 28 June 2026, as a transparent reference, rather than assuming a 16 June scrape. First review is no longer treated as an opening date or used to infer continuous operating exposure. The variance-decomposition figure now shows the negative covariance component rather than clipping it.

## Interpretation and remaining limitations

Main property-only logistic regression has ROC-AUC 0.648870, AP 0.360910 and Brier score 0.181978. The forest has AUC 0.631423 and AP 0.347648. Adding current price and minimum stay gives logistic AUC 0.720489. The latter uses contemporaneous operating characteristics and does not establish performance at the time of property selection.

The descriptive 90% intervals estimate observed attainment uncertainty from 1,000 host resamples. The predictive 95% intervals resample hosts conditional on the existing OOF scores, using 500 draws. The latter omit model-fitting and model-selection uncertainty; neither set establishes a definitive rank winner.

The original files are required to check raw record duplication, scientific-notation identifier precision, amenity parsing, scraping dates and per-listing trailing-year review counts. The supplied field is used as the current outcome. The Python reconstruction check records its unavailable status instead of reporting a fabricated match rate.

Repeated host splits, nested tuning, broader property mappings, sparse-positive sensitivity and ranking intervals with model refitting remain future work. Cross-sectional scores do not establish new-operator outcomes, future demand or profitability.

## Evidence

- [Scope, source status, versions and hashes](tables/rq_scope_summary.json)
- [Predictive metrics](tables/rq_model_metrics.json)
- [Calibration summaries](tables/rq_calibration.csv)
- [OOF segment scores](tables/rq_oof_segment_ranking.csv)
- [Descriptive segment results](tables/segment_ladder.csv)
- [Review-history sensitivity](tables/review_exposure_sensitivity.csv)
- [Saved-data integrity checks](validation/processed-integrity-2026-09-13.json)
