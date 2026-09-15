# Descriptive analysis of guest-review activity

[Script 07](../scripts/07_descriptive_analytics.R) summarises the full supplied snapshot and its original review fields. [Script 08](../scripts/08_peer_ranking.R) implements the established residential scope and benchmark partition used by the primary research question, using reconstructed `reviews_365d`. Their populations and review definitions differ and are identified separately below.

## From the snapshot to the primary analysis

| Stage | Listings |
|---|---:|
| All raw listings | 25,728 |
| Entire homes with 1–3 bedrooms | 16,576 |
| Four standard dwelling types | 14,895 |
| Quoted price AUD30–1,500 | 11,099 |
| First review on or before each listing's scrape date minus 365 days | 6,891 |
| Analysis hosts after removing benchmark hosts, before minimum support | 5,549 |
| Final analysis cells with at least 50 listings | 3,873 |
| Separate benchmark reference in those final cells | 906 |

The reference row is a separate population, not a further restriction of the analysis row. Of the 6,891 history-and-price-eligible listings, 1,342 belong to benchmark hosts. Restricting those to the final 14 analysis cells leaves 906. The minimum-support rule excludes 1,676 analysis listings in smaller cells; the same supported-cell restriction excludes 436 reference-role listings. The final analysis has 1,726 hosts and the reference 426, with no overlap. See [scope counts](tables/review_scope_summary.csv) and [partition counts](tables/benchmark_partition_summary.csv).

Established means an observed first review at least 365 days before the listing's own scrape date. It does not establish opening date or continuous operation. Rental units and condos form Apartment/unit; homes and townhouses form House/townhouse. These categories describe comparable residential stock, not whether a lease or sublet is available.

## Reference distribution and common target

The benchmark reference's P50, P75 and P90 are **14, 29.75 and 49 reviews**. Rounding the P75 upward defines the shared integer event of at least 30 reviews. Of the reference listings, 227 meet it (25.0552%), including ties. The main analysis has P75 30, but its outcomes do not determine the cutoff. It contains **981 qualifying outcomes (25.3292%)** and **334 zero-review listings**, which remain in the denominator.

For the strict 365-day count, the full snapshot P75 is 13 reviews and the entire-home, 1–3-bedroom population's P75 is 17. These differ from the scoped reference. The count of 30 is not a whole-market or profitability standard. [Benchmark mappings](tables/benchmark_map_citywide.csv) count listings below, at and above common reference thresholds; segment quantiles do not redefine the outcome.

## Segment comparisons and property attributes

Melbourne 3BR Apartment/unit has the highest observed attainment: **112 of 306 listings (36.60%)**, from 139 hosts. Its pointwise 90% host-cluster interval is **27.30%–45.74%**. These intervals hold the reference cutoff fixed and do not establish a uniquely best location. [The complete ladder](tables/segment_ladder.csv) includes all 14 supported cells.

![Observed review activity by segment](figures/16_segment_ladder.png)

Listings meeting the target have median amenity count 44 versus 43 below it. Both groups have median capacity four, two beds and one bathroom. Parking shares are 43.53% and 43.12%. These pooled contrasts describe composition rather than causal effects; [the profile table](tables/tier_profile.csv) includes missing-value counts.

![Property attributes by benchmark attainment](figures/17_top_quartile_profile.png)

## Link to predictive ranking

The predictive extensions retain the same listings, host folds and review event, then add coordinates, beds and nine amenity indicators to the original property features. The extended property-only random forest is provisionally preferred for probability ranking because it has the lowest Brier score among the property-only candidates. It gives Melbourne 3BR Apartment/unit a mean OOF probability of **34.45%**, compared with the observed **36.60%**. Its conditional 95% host-bootstrap interval is **33.00%–35.81%**, holding model scores and the benchmark fixed. This differs from the descriptive 90% interval above, and neither establishes a definitive best segment. The six fixed extension candidates were compared after baseline inspection, without an untouched final test. [All extension rankings](tables/rq_extension_ranking.csv) and [model results](findings.md) show the full comparison; the original baseline logistic ranking remains available separately.

## Dwelling composition and history sensitivity

Across all 772 Yarra Ranges entire-home, 1–3-bedroom listings, the four-type whitelist excludes 415 (53.76%). Cottages, guesthouses and farm stays together account for 200 (25.91%). These denominators precede history, price and host-partition filters. They do not show that excluded properties cannot be rented. [The dwelling inventory](tables/excluded_dwelling_types.csv) gives the exact scope.

Two tables compare the whitelist before and after, keeping the same history, quoted-price and non-benchmark-host conditions. [The broad-class table](tables/type_whitelist_sensitivity.csv) groups rental units, condos, serviced apartments and lofts as Apartment-like and all other entire-home types separately. [The paired LGA–bedroom table](tables/type_whitelist_lga_bedrooms_comparison.csv) pools dwelling types to compare the same area and bedroom count. Both mark whether each stage has at least 50 listings. They are composition checks at their stated aggregation levels, not the primary dwelling-class ranking or estimates of a filtering effect.

Removing the history restriction and reapplying minimum support gives **6,675 listings in 22 cells**, including 1,007 zero-review listings. Its P75 is 23, while 1,169 (17.51%) meet the fixed 30-review event. Removing the price restriction but retaining history gives **5,720 listings in 19 cells**, including 1,660 zero-review listings; 1,046 (18.29%) meet the same target. Reference hosts remain excluded in both cases. See [all-history results](tables/segment_ladder_all_histories_sensitivity.csv), [no-price-filter results](tables/segment_ladder_no_price_sensitivity.csv) and [history comparisons](tables/review_exposure_sensitivity.csv).

## Broader data context and limits

The median quoted price is AUD243.67 among 19,175 non-missing values and AUD242.50 among 18,927 within AUD30–1,500. Price and modelled revenue each have 6,553 missing values; bedrooms have 4,679. The review-volume seasonal index uses June 2023–May 2026, excluding the incomplete final observed month. March is 1.252 and June 0.784 relative to an average month of one. These are observed review patterns, not booking forecasts.

The 15 September run reconstructs the primary count from raw reviews over `(last_scraped - 365 days, last_scraped]`. The source's original trailing-review field includes the extra boundary date, a 366-date interval; broader source diagnostics preserve that field. All source counts match their reconstructed 366-date window, and the primary 365-date outcome removes 352 boundary reviews across 350 listings. Original identifier digits rounded before delivery cannot be restored. The revised design follows prior exploration of this snapshot and provides no untouched final test.
