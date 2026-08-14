# What drives host revenue — pricing or operations?

Produced by `scripts/04_revenue_analysis.R`. Supporting tables are in
`reports/tables/revenue_*.csv`, figures 06–08 in `reports/figures/`.

---

## The question

A prospective host has two levers. They can change what they charge per night,
and they can change how often the property is booked. Both raise revenue, and
effort spent on one is effort not spent on the other. The question is which
lever moves more money in the Melbourne market, and under what conditions.

---

## 1. A finding that dictates the method: revenue is constructed, not measured

Before modelling anything, we reconstructed the revenue field Inside Airbnb
publishes. It is not a measured quantity. It is calculated:

```
occupancy = min( reviews_ltm × 2 × max(minimum_nights, 3), 255 )
revenue   = round( price × occupancy )
```

The occupancy formula reproduces the published field **exactly for 100% of the
14,431 listings** that have a booking in the trailing year. The revenue formula
matches for 99.1%, with a largest relative discrepancy of 0.154% — that residual
is rounding to whole dollars, not disagreement.

The constants encode Inside Airbnb's assumptions: every review is taken to
represent two stays (a 50% review rate), each stay lasts the greater of the
host's minimum-night rule and three nights, and annual occupancy is capped at
255 nights (70% of the year).

**This has three consequences that shape everything below.**

First, regressing revenue on price, review count or minimum nights would be
circular. Those three variables *are* revenue, by construction. Such a model
would return a near-perfect R² that measures nothing but our own arithmetic.
We therefore never regress revenue on its own inputs.

Second, "occupancy" carries no information beyond review count and the
minimum-night rule. It is those two variables rescaled. Any model of occupancy
is a model of review counts wearing a disguise, so we model review counts
directly, where the units are honest.

Third, the revenue *levels* inherit Inside Airbnb's assumptions and should not
be read as dollars actually earned. What survives is the *ranking* between
listings, which depends only on price, reviews and the minimum-night rule.

---

## 2. Where revenue variation actually comes from

Because `revenue = price × nights` holds exactly, taking logs gives an additive
identity:

```
log(revenue) = log(price) + log(nights)
```

and the variance of the left side splits into three shares that sum to one. This
is arithmetic on an identity, not a fitted model — there is nothing to specify
wrongly and no causal claim involved.

| Sample | n | Pricing | Volume | Covariance |
|---|---:|---:|---:|---:|
| All priced listings with bookings | 14,440 | 22% | 78% | 0% |
| Entire homes only | 11,756 | 16% | 98% | −14% |
| Regularly booked (6+ reviews in 12m) | 9,568 | **44%** | **57%** | −2% |

**Across the market, booking volume accounts for roughly three to four times as
much revenue variation as pricing does.** Two listings chosen at random differ
far more in how often they are booked than in what they charge — which is
unsurprising once you notice that Melbourne prices cluster tightly (interquartile
range $159–$348) while annual bookings run from zero to more than a hundred.

**But the gap closes sharply among listings that are already working.** Restrict
to properties with at least six bookings a year and pricing rises to 44% against
volume's 57%. The negative covariance in the entire-home column is the visible
price–demand tradeoff: dearer homes book less often.

This is the central result, and it is a two-stage story rather than a single
verdict. *Getting booked* is the dominant problem for a listing that is not yet
established. *Pricing* becomes nearly as important once it is.

---

## 3. The two stages, modelled separately

76.3% of priced listings recorded at least one booking in the trailing year;
23.7% recorded none. Pooling those two groups is what produces misleading
headline comparisons, so they are modelled separately.

### Stage one — getting booked at all

Logistic regression on whether a listing had any booking in the trailing year
(`reports/tables/revenue_extensive_margin.csv`). Odds ratios, all p < 0.001:

| Factor | Odds ratio | Reading |
|---|---:|---|
| Minimum stay 28+ nights | 0.09 | **11x less likely to be booked** |
| Hotel room (vs entire home) | 0.16 | |
| Minimum stay 7–27 nights | 0.23 | |
| Superhost | **4.38** | 4.4x more likely |
| Private room (vs entire home) | 0.33 | |
| Price (per log unit) | 0.45 | dearer listings book less often |

The minimum-night rule is the single most destructive control a host holds. A
28-night minimum cuts the odds of being booked at all by roughly eleven times.
Hosts adopting it to sidestep short-stay regulation are trading away most of
their demand.

### Stage two — booking more often

Among active listings, OLS on log review count over twelve months
(`reports/tables/revenue_intensive_margin.csv`). n = 12,651, adjusted R² = 0.299:

| Factor | Effect on booking volume |
|---|---:|
| Superhost | +98.1% |
| Minimum stay 28+ nights | −75.0% |
| Minimum stay 7–27 nights | −71.5% |
| Shared room (vs entire home) | −71.1% |
| Private room (vs entire home) | −61.2% |
| Price (per log unit) | −44.7% |
| Overall rating, per point | +41.8% |

An adjusted R² of 0.299 is worth stating plainly: seven-tenths of the variation
in how often a property is booked is *not* explained by anything in this
dataset. Photography, listing copy, responsiveness and pricing dynamics through
the year are all invisible here.

---

## 4. Is raising the price self-defeating?

The price coefficient in the volume model is an elasticity: **−0.592**
(95% CI −0.644 to −0.540). Revenue rises with price whenever the elasticity is
greater than −1, because the higher rate more than compensates for the nights
lost.

| Move | Effect on booking volume | Net effect on revenue |
|---|---:|---:|
| Raise price 10% | −5.5% | **+4.0%** |
| Cut price 10% | +6.4% | **−4.2%** |

**Discounting to fill the calendar destroys revenue in this market.** A host who
cuts rates 10% gains bookings but ends up roughly 4% worse off.

This estimate is observational, not causal. Better properties both charge more
and book more, and the model controls for size, type, location, amenity count
and rating but cannot control for quality it never observes. The true causal
elasticity is likely more negative than −0.592, so the +4.0% figure should be
read as an upper bound on the gain from raising prices, not a promise.

Because the whole pricing recommendation rests on this one number, it was
re-estimated dropping the controls most open to challenge — `availability_365`
is partly an outcome of being booked, and Superhost status is awarded on booking
performance (`reports/tables/revenue_elasticity_robustness.csv`):

| Specification | n | Elasticity | Revenue effect of +10% price |
|---|---:|---:|---:|
| Main specification | 12,651 | −0.592 | +4.0% |
| Without availability | 12,651 | −0.606 | +3.8% |
| Without availability or Superhost | 12,651 | −0.666 | +3.2% |
| Entire homes only | 11,439 | −0.695 | +3.0% |
| Regularly booked only (6+) | 8,479 | −0.379 | +6.1% |

**Every specification sits well above −1.** The size of the gain moves, but the
direction of the recommendation does not depend on the choice of controls.

---

## 5. The Superhost gap, corrected

Comparing median revenue across all listings gives Superhosts a 7.7x advantage.
**That figure is an artefact and should not be used.** It compares a group that
is 94% active against one that is 65% active, so most of the gap is simply the
dormant listings dragging down the regular-host median.

| | Regular host | Superhost | Ratio |
|---|---:|---:|---:|
| **All priced listings** | | | |
| Listings | 11,685 | 7,242 | |
| Booked at least once | 65.3% | 94.0% | |
| Median revenue | $3,048 | $23,445 | 7.7x |
| **Active listings only** | | | |
| Listings | 7,630 | 6,810 | |
| Median price | $247.00 | $253.50 | 1.03x |
| Median reviews (12m) | 6 | 17 | 2.8x |
| Median revenue | $9,478 | $25,428 | **2.7x** |

The defensible number is **2.7x**, and its composition is the interesting part:
Superhosts charge 3% more and are booked 2.8 times as often. The advantage is
essentially all volume and essentially no price.

**This association cannot be read as an effect of the badge.** Superhost status
is awarded on booking performance among other criteria, so status and volume are
two symptoms of the same underlying operation. The honest statement is that
Superhosts and high-volume listings are the same population, not that earning
the badge causes bookings.

---

## 6. What this means for the client

**Do not compete on price.** With demand elasticity at −0.592, discounting
loses money. Price at or slightly above the local median for comparable
properties and hold it.

**Do not set a long minimum stay.** A 28-night minimum reduces the odds of being
booked at all by a factor of eleven and cuts volume by three quarters among
those still booked. It is the most damaging single setting available.

**Treat the first year as a volume problem, not a pricing problem.** For a
listing not yet established, volume drives 78% of revenue variation. Once it is
booking regularly, pricing carries 44% and deserves real attention. The right
sequence is to establish occupancy first, then optimise rate.

**Where the two levers meet** (figure 08): among the cheapest quartile, moving
from 1–2 bookings a year to 16+ takes median revenue from $936 to $20,850 — a
22-fold gain. Among listings with 1–2 bookings, moving from the cheapest to the
dearest quartile takes $936 to $4,478 — under 5-fold. Volume is the larger lever,
but note that the two compound: the top-right cell reaches $77,044.

---

## 7. Limitations

1. Revenue and occupancy are Inside Airbnb constructs built on a 50% review rate
   and a three-night minimum stay. Levels are assumptions; only rankings are
   evidence.
2. Review count proxies bookings. Guests who do not review are invisible, and
   the review rate may itself differ between Superhosts and regular hosts —
   which would inflate the volume gap reported in section 5.
3. All models are cross-sectional. Coefficients are associations.
4. The price elasticity is not causal, for the reason given in section 4.
5. Superhost status is endogenous to booking performance and cannot be treated
   as a treatment.
6. Thirteen columns in the source file are entirely empty, including
   `instant_bookable`, `host_response_time` and `host_response_rate` — the three
   variables that would have measured host responsiveness directly. The
   operations side of this question is therefore measured more weakly than the
   pricing side.
7. A single June snapshot. Prices carry no seasonal adjustment applied later in
   the year.
