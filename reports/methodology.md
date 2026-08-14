# Methodology

## Question

A client intends to list several properties on Airbnb in Melbourne. Three
decisions follow: where to buy or lease, what property type to run, and how to
price it. The analysis addresses them in that order.

## Sample definition

| Stage | Rule | Remaining |
|---|---|---|
| Full snapshot | Inside Airbnb, 16 June 2026 | 25,728 |
| Priced sample | price present and within $30–$1,500 | 18,927 |
| Model sample | plus bedrooms, baths, capacity, both review scores and a minimum-nights group present, and at least 3 reviews | 12,223 |

Two judgement calls worth defending in the report:

- **The $30–$1,500 window.** Below $30 the listings are mis-entered rates or
  monthly figures divided oddly; above $1,500 sit 248 luxury outliers. Both tails
  distort a logged price distribution.
- **At least three reviews.** Listings that have never been booked still carry an
  asking price, but that price has had no market test. Requiring three reviews
  keeps the model on prices someone has actually paid.

## Price model

```r
lm(log(price) ~ room_type + accommodates + bedrooms + bathrooms_num +
     shared_bath + n_amenities + host_is_superhost + review_scores_rating +
     review_scores_location + min_nights_grp + lga)
```

- The response is logged because price is heavily right skewed; each coefficient
  reads as a percentage effect via `exp(beta) - 1`.
- LGAs with fewer than 200 listings are pooled into "Other"; the reference level
  is the Melbourne LGA, so every area coefficient is a premium or discount
  relative to the central city.
- `instant_bookable` is dropped — see `data-notes.md`, it is entirely missing.

## Demand seasonality

Monthly review volume over three full years (Jul 2023 – Jun 2026) is used as the
demand proxy, indexed so the mean month equals 1. The forward calendar cannot
serve this purpose: most hosts have not opened distant dates, so an unavailable
night usually means "not yet listed" rather than "booked".

## Revenue analysis (script 04)

The revenue question needs a different design from the price model, because the
revenue field is not a measurement. It is computed by Inside Airbnb as
`round(price x min(reviews_ltm x 2 x max(minimum_nights, 3), 255))`, which we
verified reproduces the published values exactly. Three rules follow:

- **Never regress revenue on price, review count or minimum nights.** They are
  revenue by construction; the fit would be tautological.
- **Model review counts, not occupancy.** Occupancy is the review count rescaled
  by the host's own minimum-night rule.
- **Read rankings, not levels.** Dollar amounts inherit Inside Airbnb's
  assumptions about review rates and stay lengths.

The design is then:

1. **Three-way variance decomposition.** Below the 255-night cap,
   `log(revenue) = log(price) + log(stay multiplier) + log(reviews)` holds
   exactly, so the host's minimum-night policy is separated from review activity
   instead of being bundled into a single "volume" term. This is arithmetic on
   an identity — no specification, no causal claim.
2. **Sample censoring is reported, not assumed away.** The priced sample excludes
   6,801 listings that are 82% inactive, against 23.7% in the analysis set. Every
   activity rate is therefore conditional on having a usable price.
3. **A two-part model.** The extensive margin (any recent review activity,
   logistic) and the intensive margin (review count among active listings, OLS on
   logs) are estimated separately, because pooling them produces inflated group
   comparisons.
4. **Host-clustered standard errors throughout.** 55.8% of listings belong to
   multi-property hosts, so listings are not independent observations. Clustering
   roughly doubles the standard errors relative to the classical ones.
5. **Exposure-adjusted listing age.** Listings under a year old cannot accrue
   twelve months of reviews, so age comparisons use reviews per month of exposure.

**Terminology is deliberate.** The data observe reviews, not bookings. The
analysis says "review activity", "modelled nights" and "modelled revenue"
throughout, and never calls a coefficient an elasticity.

**What the design does not fix.** The price coefficient is a cross-sectional
association: the response accumulates over twelve months while the regressor is
a single-day snapshot at the end of that window, price is chosen by the host in
response to unobserved demand, and quality that drives both is not measured.
Robustness across control sets does not address any of this, so no counterfactual
is computed from it.

## Limitations to state in the report

1. Occupancy and revenue are Inside Airbnb estimates, not booking records, and
   understate true occupancy. They support relative comparison only.
2. The regression is cross-sectional. Coefficients describe association in a
   market equilibrium, not the causal return on adding a bedroom.
3. Adjusted R-squared is 0.558. Roughly 44% of price variation is unexplained,
   most plausibly fit-out quality, photography and views — none of which the
   data captures.
4. The snapshot is a single day in June. Prices carry no seasonal adjustment
   the hosts may apply later in the year.
