# What is associated with modelled listing revenue — price or review activity?

Produced by `scripts/04_revenue_analysis.R`. Tables in `reports/tables/revenue_*.csv`,
figures 06–09 in `reports/figures/`.

> **Terminology.** This dataset observes reviews, not bookings. Nothing below is
> called a booking. "Review activity" means reviews recorded in the trailing
> twelve months; "modelled nights" and "modelled revenue" are Inside Airbnb
> constructs, not nights sold or money earned.

---

## 1. The revenue field is constructed, not measured

Before modelling, we reconstructed the revenue field Inside Airbnb publishes:

```
occupancy = min( reviews_ltm × 2 × max(minimum_nights, 3), 255 )
revenue   = round( price × occupancy )
```

The occupancy formula reproduces the published field **exactly for 100%** of the
14,431 listings with a review in the trailing year; the revenue formula for
99.1%, the remainder being rounding to whole dollars. The constants are Inside
Airbnb's stated assumptions: a 50% review rate, a minimum stay length of three
nights, and a 70%-of-year occupancy ceiling.

Three consequences follow, and they govern everything below.

1. **Revenue is never regressed on price, review count or minimum nights.** Those
   variables *are* revenue by construction; such a model returns a near-perfect
   R² that measures only our own arithmetic.
2. **We model review counts, not occupancy.** Occupancy is the review count
   rescaled by the host's own minimum-night rule.
3. **Only rankings are evidence, not dollar levels.** The levels inherit Inside
   Airbnb's assumptions.

---

## 2. What the price filter removes

The analysis keeps only listings with a usable price. That filter is strongly
related to the outcome, so it is reported rather than left implicit:

| Sample | n | No reviews in trailing 12m |
|---|---:|---:|
| All listings | 25,728 | 39.1% |
| Priced sample (analysis set) | 18,927 | 23.7% |
| **Excluded: no usable price** | 6,801 | **82.0%** |

Listings without a price are overwhelmingly inactive. **This is not random
censoring**, and every activity rate in this document therefore describes priced
listings and understates inactivity across the market as a whole.

---

## 3. Where the variation in modelled revenue sits

Below the 255-night cap the identity is exactly additive in three terms, which
lets the host's minimum-night policy be separated from review activity rather
than bundled with it:

```
log(modelled revenue) = log(price) + log(2 × max(min_nights, 3)) + log(reviews_ltm)
```

Shares of cross-sectional variance, uncapped listings (92.3% of active listings):

| Sample | n | Price | Stay-length policy | Review activity | Covariance |
|---|---:|---:|---:|---:|---:|
| Uncapped listings | 13,316 | 23.6% | 5.0% | 78.9% | −7.5% |
| Uncapped, entire homes | 10,719 | 17.0% | 6.2% | 99.4% | −22.6% |

Dispersion in review activity accounts for roughly three times as much variation
in modelled revenue as dispersion in price. The stay-length policy contributes
only about 5%, so the result is not an artefact of the minimum-night multiplier
inside Inside Airbnb's formula.

**This is a decomposition of variance in a modelled quantity.** It says where the
spread sits — not what causes revenue, and not what would happen if a host
changed anything.

---

## 4. Listing age: the apparent lifecycle is an exposure artefact

A listing younger than a year cannot have accrued twelve months of reviews, so
raw trailing counts understate new listings. Expressed per month of exposure:

| Listing age | n | Median reviews (12m) | **Median reviews per month** |
|---|---:|---:|---:|
| Under 1 year | 4,661 | 6 | **1.27** |
| 1–2 years | 2,731 | 13 | 1.08 |
| 2–5 years | 4,497 | 13 | 1.08 |
| 5+ years | 2,548 | 12 | 1.00 |

The raw counts suggest new listings do badly and established ones do well. **Once
exposure is accounted for, that pattern disappears and mildly reverses.** An
earlier version of this analysis interpreted a performance grouping ("6+ reviews")
as a lifecycle stage and recommended treating the first year as a volume problem.
That recommendation was not supported, and the exposure-adjusted figures point
the other way. It has been withdrawn.

---

## 5. Two margins, modelled separately

23.7% of priced listings recorded no review activity. All standard errors are
clustered by host, since 55.8% of listings belong to multi-property hosts and
observations within a host are not independent.

### Achieving any recent review activity (logistic, host-clustered)

| Factor | Odds ratio |
|---|---:|
| Minimum stay 28+ nights | 0.09 |
| Hotel room (vs entire home) | 0.16 |
| Minimum stay 7–27 nights | 0.23 |
| Private room (vs entire home) | 0.33 |
| Price (per log unit) | 0.45 |
| Superhost | 4.38 |

### Sustaining review activity among active listings (OLS on log reviews)

n = 12,648, adjusted R² = 0.411, 6,250 host clusters.

| Factor | Difference in review count |
|---|---:|
| Superhost | +88.2% |
| Minimum stay 28+ nights | −76.0% |
| Minimum stay 7–27 nights | −74.4% |
| Private room (vs entire home) | −54.6% |
| Overall rating, per point | +46.8% |
| Price (per log unit) | −43.4% |
| Listing age (per log year) | +43.3% |

Roughly six-tenths of the variation in review intensity is unexplained.
Photography, listing copy, host responsiveness and pricing through the year are
not observable here.

---

## 6. The price–activity association

**This coefficient is not a demand elasticity and is not used to compute any
counterfactual.** Among comparable active listings, those priced 10% higher
recorded about **5.3% fewer reviews** over the same window
(coefficient −0.569, 95% CI −0.668 to −0.470, host-clustered).

Three reasons it cannot be read as the effect of changing a price:

1. **The windows do not align.** The response counts reviews accumulated over the
   previous twelve months; the regressor is the price observed on a single day at
   the end of that window. Hosts change prices.
2. **Price is chosen, not assigned.** Hosts set prices in response to demand they
   observe and we do not.
3. **Unobserved quality moves both.** Better properties charge more and are
   reviewed more; the controls cannot capture fit-out, photography or view.

Stability across specifications (host-clustered):

| Specification | n | Coefficient | SE |
|---|---:|---:|---:|
| Main | 12,648 | −0.569 | 0.051 |
| Without availability | 12,648 | −0.581 | 0.051 |
| Without availability or Superhost | 12,648 | −0.634 | 0.052 |
| Entire homes only | 11,436 | −0.648 | 0.060 |

Stability across these specifications speaks only to the choice of controls. It
does not address the timing mismatch, reverse causation or unobserved quality,
and it is not evidence of a causal price effect.

---

## 7. Superhosts

Descriptive comparison only:

| | Regular host | Superhost |
|---|---:|---:|
| Listings | 11,685 | 7,242 |
| With recent review activity | 65.3% | 94.0% |
| *Active listings only* | | |
| Median price | $247.00 | $253.50 |
| Median reviews (12m) | 6 | 17 |
| Median modelled revenue | $9,478 | $25,428 |

Among active listings the ratio is **2.7x**, of which almost all is review
activity and about 3% is price. Comparing across all listings would give 7.7x,
but that contrasts a 94%-active group with a 65%-active one; an earlier version
of this analysis reported the 7.7x figure and it has been corrected.

Superhost status is awarded partly on booking performance, so this compares two
outcomes. It is **not** evidence that earning the badge raises revenue, and we do
not recommend it as an intervention.

---

## 8. What can and cannot be said

**Supported by this analysis**

- Inside Airbnb's revenue and occupancy fields are deterministic constructs, and
  we can reproduce them exactly.
- Dispersion in modelled revenue sits about three times more in review activity
  than in price, and the minimum-night multiplier contributes little.
- Listings currently requiring 28+ nights show far lower recent review activity
  than otherwise comparable listings.
- Superhosts and high-activity listings are the same population.

**Not supported, and deliberately absent**

- Any claim that raising or cutting a price would change a given listing's
  revenue by a stated amount.
- Any lifecycle claim about a listing's first year.
- Any claim that hosts set 28-night minimums to avoid the short-stay levy. The
  Victorian levy does apply to stays under 28 days, which makes this a plausible
  hypothesis worth testing against data on when hosts changed their rules — but
  this snapshot records only the current setting, and weak demand could equally
  have prompted a switch to longer lets.
- Any recommendation about where to buy, which would require acquisition costs
  this dataset does not contain.

---

## 9. Limitations

1. Revenue and occupancy are constructs; only rankings are evidence.
2. Reviews proxy bookings imperfectly. Guests who do not review are invisible,
   and if review rates differ between Superhosts and regular hosts, the activity
   gap in section 7 is overstated.
3. The priced sample excludes listings that are 82% inactive — non-random
   censoring that biases every activity rate downward.
4. All models are cross-sectional; every coefficient is an association.
5. Thirteen source columns are entirely empty, including `host_response_time` and
   `host_response_rate`, so the operations side is measured more weakly than the
   pricing side.
6. A single June snapshot, with no seasonal adjustment.
7. The positive-count model is OLS on log reviews. A zero-truncated negative
   binomial would suit the count structure better; the trade-off is
   interpretability, and the ranking of factors is unlikely to change.
