# Raw data validation on 15 September 2026

The complete workflow was rerun from the three school-supplied CSVs. This record supersedes the cached-data checks of 13–14 September. [The machine-readable record](validation/raw-rerun-2026-09-15.json) contains input hashes, raw integrity results and the 132 independent baseline checks, all of which passed.

## Source integrity and review window

| Check | Result |
|---|---|
| Listings | 25,728 rows; 14,113 distinct hosts; no missing or duplicated canonical listing IDs |
| Calendar | 9,390,720 rows; exactly 365 listing-date records per listing; no duplicate keys or unmatched listing IDs |
| Reviews | 1,026,690 rows; no duplicated canonical review IDs, invalid/future dates or unmatched listing IDs |
| Scrape dates | 17 June–1 July 2026, verified separately for every listing |
| Original review measures | Total counts and first/last review dates match the raw reviews for every listing |
| Source recent-review field | All 25,728 values match the inclusive 366-date window `[last_scraped − 365 days, last_scraped]` |
| Primary `reviews_365d` outcome | Reconstructed over `(last_scraped − 365 days, last_scraped]`; all R values match independent raw reconstruction |
| Boundary difference | 352 reviews on the excluded boundary date affect 350 listings; one primary analysis listing changes target label |
| Numeric features | All 25,728 price, bathroom and amenity-count values agree between R cleaning and fresh Python parsing |

The original recent-review field remains unchanged. A separate `reviews_365d` field provides the precisely defined primary outcome. This resolves a window-definition difference rather than treating the original counts as erroneous. Some source identifiers already use scientific notation; text normalisation cannot recover digits rounded before delivery.

## Scope and benchmark

Established listings have `first_review <= last_scraped − 365 days`. Entire-home, bedroom, standard-type and price restrictions leave 6,891 listings before the host partition. Reference hosts are excluded from every modelling pool. After the 50-analysis-listing support rule, the primary sample has 3,873 listings, 1,726 hosts and 14 segments, including 334 zero-review listings.

The separate reference group has 906 listings from 426 hosts within those 14 segments. Its linear-interpolated P75 is 29.75, giving a common integer threshold of 30. There are 981 primary positive outcomes (25.3292%) and 227 reference positives (25.0552%). All-history and no-price sensitivities retain that same event and contain 6,675 and 5,720 analysis listings respectively.

## Predictive and descriptive verification

All eight baseline model/scenario prediction files have exactly one finite out-of-fold probability per eligible listing. No reference host enters any model sample; each analysis host has one fold. Independent calculations reproduce ROC-AUC, average precision, Brier score, log loss, calibration bins and error, fold metrics, and all segment mean probabilities and conditional 95% intervals. The R descriptive ladders agree with independent counts, rates and review quantiles for all three scopes.

The main logistic model has AUC 0.573149, average precision 0.284642 and Brier score 0.188559, compared with training-fold-prevalence Brier 0.190719. Its ten-bin calibration error is 0.039183. Random forest AUC is 0.559629. These are exploratory host-grouped results; they do not establish accurate individual probabilities or a new operator’s future success.

## Reproducibility checks

Twelve Python checks, twelve R cleaning checks and seven R input-consistency checks passed. They cover the exact 365-day boundary, leap years, zero counts, source-field preservation, benchmark separation, failed validation, malformed amenities and recovery from interrupted output publication. Cleaning publishes a manifest only after source checks succeed; descriptive ranking requires matching raw, cleaned-file and configuration hashes.

Scripts 01, 02, 03, 04, 07, 08, 09 and the Python baseline workflow all completed on the restored inputs. The supporting revenue reconstruction intentionally uses the unchanged supplied field; its definitions are documented separately. The final cleaning run also completed with warnings treated as errors. No external market observations or rental assumptions were used.

## Additional model comparison

Six fixed extensions retain the original 3,873 primary listings, outcomes and outer host folds. Added features are coordinates, beds and nine amenities. Enhanced random forest improves AUC to 0.639589, Brier to 0.181316 and ten-bin calibration error to 0.016277. Enhanced gradient boosting reaches AUC 0.647491 with Brier 0.182098. Random forest is the provisional probability-ranking candidate because of its lower Brier score; all candidates remain reported, and the comparison follows inspection of the baseline.

With contemporaneous price and minimum stay, enhanced boosting reaches AUC 0.749290 and Brier 0.162356. Two boosting variants also test sigmoid calibration inside three host-disjoint inner folds; calibration does not improve every metric. These operating-controls results answer a broader information scenario than property-only screening.

All 51 independent extension checks passed, including frozen sample/threshold/folds, six complete OOF sets, recalculated metrics and segment summaries, and exclusion of outer validation rows from inner calibration. The original eight model outputs did not change. See [extension metrics](tables/rq_extension_metrics.csv), [rankings](tables/rq_extension_ranking.csv), [provenance](tables/rq_extension_provenance.json) and the extension checks in the machine-readable validation record. Repeated host splits and nested model selection remain necessary to assess stability; no independent final test is claimed.
