# Descriptive analysis of guest-review activity

[Script 07](../scripts/07_descriptive_analytics.R) describes the broader supplied snapshot. [Script 08](../scripts/08_peer_ranking.R) applies the residential segment definition used by the primary research question. Their populations differ and should not be combined without stating the relevant filters.

## From the supplied snapshot to comparable segments

| Stage | Listings |
|---|---:|
| All saved listings | 25,728 |
| Entire homes with 1–3 bedrooms | 16,576 |
| Four standard dwelling types | 14,895 |
| Quoted price AUD30–AUD1,500 | 11,099 |
| Final LGA × dwelling class × bedrooms cells with at least 50 listings | 8,967 |

The four retained types are entire rental unit, condo, home and townhouse. They describe dwelling categories; the dataset cannot establish whether an operator could lease or sublet an individual property. In Yarra Ranges, the whitelist excludes 415 of 772 entire-home, 1–3-bedroom listings (53.76%). This is the exclusion share across all other property types, not the share of cottages, guesthouses and farm stays alone. See [type counts](tables/excluded_dwelling_types.csv).

## Review distribution and common target

The final cohort contains 4,081 hosts across 35 segments. Review-count P50, P75 and P90 are **9, 22 and 39**. A common target of at least 22 reviews is met by **2,315 listings (25.8169%)**. The remaining 6,652 include **1,428 zero-review listings**. Threshold ties are retained; the classification is not forced to divide the sample into an exact quarter.

[Internal benchmark mappings](tables/benchmark_map_citywide.csv) report counts below, at and above each common threshold. Segment-specific quantiles describe distributions but do not redefine the classification target.

## Segment comparisons

The highest observed target share is Melbourne 3BR Apartment/unit: **216 of 543 listings, or 39.78%**. Its pointwise 90% host-cluster bootstrap interval is 32.57%–46.57%. Yarra Ranges 3BR House/townhouse records 35.77%, and its 2BR counterpart records 34.48%.

These are observed proportions. Differences in sample composition and overlapping intervals limit conclusions about a uniquely superior location. [The full segment table](tables/segment_ladder.csv) includes counts, independent hosts and uncertainty for all eligible cells.

![Observed review activity by segment](figures/16_segment_ladder.png)

## Property attributes and review history

Listings meeting the target have a median of 46 amenities, compared with 42 below the target. Both groups have median guest capacity four, two beds and one bathroom. These are unadjusted group summaries, not evidence that changing an amenity count causes higher activity. [The profile table](tables/tier_profile.csv) records other attributes and missing-value counts.

Restricting first review to on or before 1 June 2025 and reapplying segment eligibility leaves **4,812 listings in 16 segments**. This sensitivity retains 463 zero-review listings; 35.83% meet the unchanged 22-review target and its review-count P75 is 29. The change reflects a different population, not an estimate of what newer listings would achieve after a year. See [scope summary](tables/review_scope_summary.csv) and [sensitivity comparisons](tables/review_exposure_sensitivity.csv).

## Broader data context

Among all 19,175 non-missing quoted prices, the median is AUD243.67. Among the 18,927 prices within AUD30–AUD1,500, it is AUD242.50. Price and modelled revenue each have 6,553 missing values; bedrooms have 4,679. Overall rating has 4,477 missing values, while location and value ratings each have 4,484.

The monthly review index uses **June 2023–May 2026**, excluding the incomplete final month. March is 1.252 and June 0.784 relative to an average month of one. These are review-volume patterns, not identified event effects or booking forecasts. See [seasonality index](tables/seasonality_index.csv).

All results here are reproducible from the saved processed files. The unavailable original CSV files prevent renewed verification of raw parsing and the review-count construction.
