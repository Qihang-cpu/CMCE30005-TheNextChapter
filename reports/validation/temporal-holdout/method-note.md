# Temporal hold-out of the segment shortlist

## Purpose

We checked whether segments that led on review attainment in an earlier year still led the following year: an out-of-time check of the shortlist rule (`scripts/validation/temporal_holdout.py`), not a forecast of a new operator's profit.

## Windows and eligibility

With S each listing's own `last_scraped` date, we rebuilt from raw review dates two non-overlapping windows: earlier (S-730, S-365] and recent (S-365, S]. Room, bedroom, dwelling and price rules were unchanged; only listings with a first review on or before S-730 were eligible. Zero-review listings were kept; this does not prove continuous operation.

## Hosts, threshold, candidates

Hosts followed the primary sha256 split (about 20% benchmark). Segments needed 50 analysis listings; 10 of 153 qualified, fixed before ranking. The threshold was the ceiling of the benchmark listings' P75 of earlier-window reviews (34.00, so 34). It came from the earlier window so the outcome never touches it, and was held fixed everywhere; the primary design's 30 was not reused. The benchmark recent P75 (30.00) is informational only. Candidates were the three highest earlier-attainment segments, ties broken by more listings.

## Metrics

Each analysis listing was scored with its segment's raw earlier rate (a smoothed version, weight 10, is secondary); the outcome was recent attainment. We reported ROC AUC, Brier, the Brier of a constant at the overall earlier rate and the skill score, plus recent attainment of the earlier top-3 against the other retained segments, listing- and host-weighted.

## Bootstrap

2,000 replicates, seed 30005, resampling analysis hosts with replacement (all listings of a drawn host, with multiplicity); threshold and segment set held fixed in every interval. Interval A fixed the point-estimate top-3; interval B re-selected it per replicate.

## Headline numbers

2,657 analysis listings, 1,208 hosts; 613 benchmark listings. Overall attainment fell from 25.8% to 20.1%. Earlier top-3: Melbourne 3BR apartments (34.2% to 24.8%), Melbourne 2BR apartments (33.7% to 28.2%), Yarra Ranges 3BR houses (30.0% to 21.4%). Recent attainment: 27.1% against 14.9% for the rest, +12.3 pp listing-weighted, +8.7 pp host-weighted. Interval A +5.1 to +20.1 pp; interval B +5.4 to +20.2 pp. AUC 0.618; Brier 0.159 against 0.164, skill +0.028. The exact top-3 set recurred in 51.5% of replicates; the re-selected top-3 beat the rest in 99.95%. The primary design reproduced (906/3,873/1,726/14/30); 1,044 primary listings with shorter history could not be checked.

## Limitations

- Survivors only; exited listings are absent.
- Eligibility does not prove continuous operation.
- Both windows use the same surviving listings, not an independent sample.
- Review propensity may drift between years.
- Attainment declined market-wide between windows.
- Threshold and segment set were fixed inside the intervals.
- Not a new operator's future profit probability.
