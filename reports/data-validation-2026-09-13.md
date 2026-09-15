# Analysis validation record

Historical record of the 13–14 September cached-data analysis. The [15 September raw-data verification](data-validation-2026-09-15.md) supersedes its source availability, date-window and primary sample results.

Updated 14 September 2026 after the established-history and reference-benchmark revision.

## Conclusion

The current descriptive and predictive outputs reproduce from the saved school-data snapshot. The primary R and Python samples match listing by listing: 3,810 listings, 1,699 hosts and 14 segments, including 333 zero-review listings. Original CSV files are unavailable at their linked paths, so raw-to-clean validation remains incomplete. No result should be described as verified actual occupancy, income or profit.

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
| Primary scope | Independently reproduced 14 cells, 3,810 analysis listings, 1,699 hosts and 957 outcomes meeting the computed 30-review benchmark |
| Descriptive results | New segment counts, quantiles, rates, reference mappings, profiles and scope sensitivities independently recalculated |
| Bootstrap | Host resampling logic was independently checked; revised tables use 1,000 descriptive and 500 conditional-score draws |
| Predictive validation | All eight revised model/scenario OOF sets checked independently for ROC-AUC, tied-score average precision, Brier score and ten-bin calibration error |
| Host separation | Each host has one fold; no training/validation host overlap within a fold |
| R/Python consistency | Main analysis and benchmark reference membership match after lossless text-format normalisation; aggregate counts and rates also match |
| Public outputs | Aggregate tables only; listing predictions, host-fold assignments and review-ID diagnostics remain in ignored processed-data files |

The old price and review models were reproduced before revision. After the date-proxy correction, the exploratory review-intensity model now uses 12,651 observations, 6,252 host clusters and adjusted R² 0.403. That fit is descriptive and is not the primary classifier's accuracy.

## Corrections applied

The primary question now uses established review history and a common upper-quartile benchmark rather than a numerical cutoff in the RQ. Approximately 20% of hosts are reserved by a fixed identifier hash. Final analysis cells require at least 50 listings after all filters and removal of those hosts. Their eligible reference listings in the same cells supply a pooled P75, rounded upward to define the event. The reference contains 899 listings from 424 hosts; P75 is 30. All 2,846 benchmark-role hosts in the source, including those outside that reference, are excluded from all eight model/OOF samples.

The primary outcome therefore uses 30 reviews, with 957 of 3,810 analysis listings meeting it. The primary analysis P75 also equals 30, but its outcomes do not determine the cutoff. Four regression tests check cutoff independence from analysis outcomes, host-role separation and mixed-pool rejection, minimum support after removing reference hosts, and fractional quantile rounding with ties. All four passed. Reference and validation samples were computationally separated after earlier exploration; this is not an untouched final test.

The Python model learns imputation, encoding and scaling within training folds. Metrics handle tied probabilities. Current price and minimum stay appear only in a separate operating-controls sensitivity. The revised calibration figure shows ten fixed-width bins and sparse-bin sizes. No recalibration or independent model selection has been claimed. Whitelist and history comparisons retain their explicit sample definitions; no dwelling type is asserted to be unavailable for leasing.

The cleaning script now preserves ID text, parses amenity JSON, recognises half-baths and uses a 90-date window for each listing. These raw-data transformations still need a full run when the original files are restored. The current saved availability aggregate is from the older window calculation and is not consumed by the primary analysis.

The seasonality calculation now uses June 2023 through May 2026, excluding the incomplete final observed month. The exploratory review-history model uses the latest observed review date, 28 June 2026, as a transparent reference, rather than assuming a 16 June scrape. First review is no longer treated as an opening date or used to infer continuous operating exposure. The variance-decomposition figure now shows the negative covariance component rather than clipping it.

## Interpretation and remaining limitations

Main property-only logistic regression has ROC-AUC 0.567879, AP 0.277968 and Brier score 0.188023. The forest has AUC 0.552869 and AP 0.271082. Logistic Brier loss is virtually equal to the descriptive constant-prevalence value of 0.188089, and only slightly better than the training-fold-prevalence baseline of 0.189738. Adding operating controls gives logistic AUC 0.713073. That sensitivity does not establish pre-opening prediction.

Logistic weighted absolute calibration error across ten fixed-width bins is 0.036633. Mean predicted probability is 24.7644% versus 25.1181% observed. Only 22 listings score at least 0.5, averaging 57.3768%, whereas 31.8182% meet the event. This high-score subset is sparse and overpredicted in the observed sample. No fitted calibration correction has been applied.

Descriptive 90% intervals use 1,000 host resamples. Predictive 95% intervals use 500 resamples conditional on fixed OOF scores and the fixed reference cutoff. They omit benchmark-estimation, model-fitting and selection uncertainty. Neither set establishes a definitive rank winner. The top primary logistic segment is Melbourne 3BR Apartment/unit, with mean score 34.6031% across 304 listings; weak overall prediction prevents a confident investment recommendation.

The original files are required to check raw record duplication, scientific-notation identifier precision, amenity parsing, scraping dates and per-listing trailing-year review counts. The supplied field is used as the current outcome. The Python reconstruction check records its unavailable status instead of reporting a fabricated match rate.

Repeated host splits, nested tuning, broader property mappings, sparse-positive sensitivity and ranking intervals with model refitting remain future work. Cross-sectional scores do not establish new-operator outcomes, future demand or profitability.

## Evidence

- [Revised design verification](validation/review-design-2026-09-14.json)
- [Scope, source status, versions and hashes](tables/rq_scope_summary.json)
- [Predictive metrics](tables/rq_model_metrics.json)
- [Calibration summaries](tables/rq_calibration.csv)
- [OOF segment scores](tables/rq_oof_segment_ranking.csv)
- [Descriptive segment results](tables/segment_ladder.csv)
- [Review-history sensitivity](tables/review_exposure_sensitivity.csv)
- [Saved-data integrity checks](validation/processed-integrity-2026-09-13.json)
