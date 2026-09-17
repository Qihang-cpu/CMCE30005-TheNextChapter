# Melbourne Airbnb Market Screening

Interim Project Report

CMCE30005 Business Analytics Challenge | Semester 2 2026 | TheNextChapter Group 2

Eric Huang, Loc Le, Qihang Sun and Maksym Xu

Repository: <https://github.com/Qihang-cpu/CMCE30005-TheNextChapter>

## Introduction

Our client leases residential properties and runs them as Airbnb accommodation ("rental arbitrage"), which needs lease and council permission. With limited start-up funds, the client must choose which Melbourne areas and property types to investigate before signing leases; a poor choice ties up money.

We use the Inside Airbnb Melbourne snapshot of June 2026 supplied through the subject's LMS (Inside Airbnb, 2026): property details, locations and dated guest reviews. Dated reviews are a countable record of past guest activity; the calendar cannot separate bookings from host-blocked dates.

The shortlist helps the client decide where to spend limited search and due-diligence time before seeking lease quotations.

## Problem Definition and Objectives

Research questions: (1) Which Melbourne property segments, defined by council area (LGA), apartment or house, and number of bedrooms, show the strongest historical guest-review activity? (2) Can listing attributes improve prediction of high review activity beyond segment averages? "High" means at least 30 reviews in the year before the data were collected, the top quarter of a separate reference group of comparable listings.

Hypotheses: (H1) segments differ materially in the share of listings reaching that level; (H2) a model using listing attributes ranks listings better than the segment average alone.

Objectives: a segment comparison table, a model-versus-average test and a shortlist with ranges.

We study entire homes with one to three bedrooms (1–3BR), what a small operator can furnish and let whole; rental units and condos are the apartment group, homes and townhouses the house group. Each segment needs at least 50 listings as minimum comparison support; quoted prices of AUD 30–1,500 are an exploratory boundary; and a first review at least 365 days before collection gives at least one year of observable review history, not proof of continuous operation.

We call the share of listings reaching 30 reviews (at least 30 reviewed stays) "attainment". Attainment measures review activity, not bookings, occupancy or profit. For an operator paying fixed rent, the main risk is a property that attracts few stays; segments where more comparable listings reach high review activity show such demand is achievable.

## Data Description

The dataset contains 25,728 listings and 1,026,690 reviews, collected between 17 June and 1 July 2026. Its modelled occupancy and revenue fields are built from price, minimum stay and review counts, so ranking on them would reproduce that construction; we rank on review counts.

Cleaning converts price text to numbers and extracts bathroom and amenity counts; price is missing for 6,553 listings and bedrooms for 4,679. The supplied last-12-months review field spans 366 dates, so we rebuilt counts over exactly 365 days from review dates (Table 1).

Table 1. Sample funnel

| Stage | Listings |
| ---------------------------------------- | ---------- |
| All listings in the dataset | 25,728 |
| Entire homes, 1–3 bedrooms | 16,576 |
| Standard dwelling types | 14,895 |
| Quoted price AUD 30–1,500 | 11,099 |
| First review ≥ 365 days before collection | 6,891 |
| Analysis sample (50+ per segment, reference hosts excluded) | 3,873 |
| Reference group (separate, from the 6,891) | 906 |

The reference group's 75th percentile, 29.75 reviews, gives a threshold of 30. The analysis sample (3,873 listings from 1,726 hosts) has 14 segments across six LGAs, about 64% in Melbourne LGA, and keeps 334 listings with zero annual reviews. Overall, 981 listings (25.33%) reach the threshold, and attainment ranges from 8.25% to 36.60% across segments (Figure 1).

![Figure 1. Share of listings reaching 30 reviews by segment; lines are 90% host-resampled ranges, dashed line the pooled 25.33% rate.](figures/16_segment_ladder.png)

Of the 6,801 listings with no usable price (missing or outside AUD 30–1,500), 82% had no review last year: the priced sample is the more active part of the market. Listings that left Airbnb before collection are absent, limiting generalisation to new entrants.

## Methodology and Analytical Approach

A fixed rule on host identifiers sets aside about 20% of hosts as the reference group that defines the 30-review target; they are excluded from all training and testing. We use five-fold validation, each part tested in turn on a model trained on the other four, with each host's properties kept in one fold so a host with many near-identical apartments cannot sit in both training and test data (scikit-learn developers, n.d.). Missing-value treatment and category encoding are learned from training data only.

Logistic regression is the reference; random forest and gradient boosting capture nonlinear patterns. Basic features are location, configuration, capacity, bathrooms and amenity count; an enhanced set adds coordinates, beds and nine amenities. We compare six variants, with and without probability calibration and with and without current price and minimum stay. Review-based predictors, ratings and host badges are excluded.

Every model is compared with a segment-average baseline: each listing gets its segment's training-host attainment. AUC is how well the model orders listings that reach the target above those that do not; 0.5 is a coin toss. Average precision summarises precision across prediction thresholds. Brier score is how far its percentages are from what happened; lower is better. R handles cleaning and tables; Python (scikit-learn 1.7.2) runs the models.

Because candidates were compared after seeing fold results, selection is repeated in a nested check where models are selected using only each outer training fold; property details may have changed during the outcome year.

## Analysis Plan and Progress to Date

Following Week 5 feedback, we dropped the earlier rent-versus-revenue (ROI) design, which needed external rental data.

Table 2. Predictive performance

| Predictor | AUC | Average precision | Brier score |
| --- | --- | --- | --- |
| Segment average (training hosts) | 0.581 | 0.285 | 0.1868 |
| Basic property-only logistic | 0.573 | 0.285 | 0.1886 |
| Enhanced property-only random forest | 0.640 | 0.350 | 0.1813 |

The enhanced random forest beats the segment average in all five folds and, across 20 further host splits on AUC every time and on Brier in 16. A nested check that re-selects the model inside each outer training fold chooses the forest every time: AUC +0.059 (host-resampled 95% range +0.02 to +0.10), Brier −0.0055 (−0.010 to −0.001). Across five probability bins, predicted and observed rates differ by about two percentage points.

Table 3. Initial search candidates (host-grouped forest predictions)

| Segment | Listings / hosts | Observed attainment | Predicted probability | 95% range |
| ---------------------------- | ------------ | ------------ | ------------ | ------------ |
| Melbourne 3BR apartments | 306 / 139 | 36.60% | 34.45% | 33.0–35.8% |
| Melbourne 2BR apartments | 1,235 / 482 | 32.79% | 31.41% | 29.6–33.0% |
| Yarra Ranges 3BR houses/townhouses | 90 / 77 | 30.00% | 27.82% | 26.1–29.3% |

All reported host-resampled ranges hold predictions fixed and exclude refitting, selection and threshold uncertainty; Table 3's are much narrower than Figure 1's observed-rate ranges. Descriptive evidence supports H1: segments differ (8.25% to 36.60%), though neighbours overlap. H2 is supported by nested host-grouped validation on ranking metrics: the model improves overall listing-level prediction but leaves the shortlist unchanged. Segment rates guide the search; the model provides a supplementary historical score for individual listings (within-segment AUC 0.555). Descriptively, the same three segments lead under support rules of 30, 50 and 75 listings, without the history or price rule, and at review targets of 25, 30, 34 and 35 (the top two swap at 34 and 35); the forest's top three recur in 19 of 20 host splits.

An out-of-time check (2,657 listings, 1,208 hosts, 10 segments) uses two non-overlapping 365-day windows and a 34-review target set from the reference hosts' earlier window. The earlier year's top three segments reached it in 27.1% of listings the following year against 14.9% elsewhere, a 12.3-point lead (host-resampled 95% range 5.1–20.1); the exact top-three set recurred in 51.5% of resamples: a persisting historical advantage, not a new operator's profit.

Before signing, the client must verify permissions, rent, costs and availability.

Remaining work:

1. Refit the fixed forest and re-rank under wider property-type and history rules: Eric Huang (modelling lead) and Maksym Xu (data lead), Weeks 9–10 (by 2 Oct).
2. One-page client brief with search priorities and pre-lease checklist: Loc Le (report lead), Week 11 (by 13 Oct).
3. Final report and presentation: all, Qihang Sun coordinating, Weeks 11–12.

If the gain does not persist under wider rules, segment rates remain the main screening tool; if rankings change, we present a broader candidate set.


## References

Inside Airbnb. (2026). Melbourne listings, calendar and reviews [June 2026 dataset supplied through CMCE30005 LMS].

Scikit-learn developers. (n.d.). Cross-validation and probability calibration. https://scikit-learn.org/stable/modules/cross_validation.html

OpenAI. (2026). ChatGPT/Codex assistance with project planning, report drafting and code review [Generative AI outputs, September 2026].

Anthropic. (2026). Claude Code assistance with analysis-code development [Generative AI outputs, September 2026].

## AI Use Acknowledgement

The business problem, research questions, scope rules, choice of methods, data decisions and interpretation of results are the group's own. We used OpenAI ChatGPT/Codex and Anthropic Claude Code to polish the English of report text written from our results, to implement and debug analysis scripts to our specification, and to check quoted figures against the repository tables. The group reviewed all AI-assisted text and code and is responsible for the accuracy and content of this submission.
