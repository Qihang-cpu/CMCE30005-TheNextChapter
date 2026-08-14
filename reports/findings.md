# Interim findings

All figures come from `scripts/01`–`03`; the underlying tables are in
`reports/tables/` and the charts in `reports/figures/`. Sample definitions and
caveats are in `methodology.md`.

## 1. The market is run by professionals, not spare rooms

- 25,728 active listings held by 14,113 hosts.
- 73.2% are entire homes or apartments; 25.7% private rooms.
- **55.8% of listings belong to hosts running more than one property.** The
  competition is professional operators, not householders letting a spare room.

## 2. Price and occupancy have to be read together

Median values by LGA, priced sample (`reports/tables/area_summary.csv`):

| LGA | Listings | Median price | Median nights booked | Median annual revenue |
|---|---|---|---|---|
| Melbourne | 6,463 | $251 | 54 | $14,098 |
| Port Phillip | 1,805 | $244 | 30 | $8,232 |
| Yarra | 1,075 | $266 | 66 | $18,163 |
| Yarra Ranges | 984 | $343 | 63 | $21,038 |
| Stonnington | 823 | $237 | 42 | $10,611 |
| Moreland | 673 | $173 | 30 | $3,942 |
| Wyndham | 648 | $159 | 12 | $1,558 |

Port Phillip prices near the top of the market but books half as often as Yarra,
and earns far less. Wyndham is weak on both. Revenue, not nightly rate, is the
metric that ranks locations sensibly.

## 3. What actually drives price

Hedonic regression, n = 12,223, adjusted R-squared 0.558. All effects below are
significant at p < 0.001 (`reports/tables/price_model_coefficients.csv`).

| Factor | Effect on price |
|---|---|
| Hotel room (vs entire home) | +66.7% |
| Shared room (vs entire home) | −52.6% |
| Minimum stay 28+ nights (vs 1) | −36.7% |
| Private room (vs entire home) | −34.3% |
| Shared bathroom | −30.4% |
| Location score, per point | +18.4% |
| Each extra bedroom | +15.8% |
| Overall rating, per point | +8.8% |
| Each extra bathroom | +5.9% |
| Each extra guest of capacity | +4.1% |

Location premium against the Melbourne LGA, holding listing attributes constant:
Yarra Ranges +22.1%, Yarra +17.0%, Stonnington +7.2%, Port Phillip +6.8%;
Wyndham −24.5%, Maribyrnong −11.5%, Whitehorse −11.4%.

Note that **bedrooms carry roughly four times the price effect of guest capacity**.
Adding beds to an existing room is close to worthless; a genuine extra bedroom is
not.

## 4. The Superhost result is the interesting one

| | Regular host | Superhost |
|---|---|---|
| Listings | 11,685 | 7,242 |
| Booked at least once in 12m | 65.3% | 94.0% |
| Median price, active listings | $247.00 | $253.50 |
| Median bookings (reviews) in 12m | 6 | 17 |
| Median annual revenue, active listings | $9,478 | **$25,428** |

Among listings that are actually being booked, Superhosts earn **2.7 times** the
revenue of regular hosts while charging only 3% more. The advantage is volume,
not price — and once listing attributes are held constant, the Superhost price
coefficient is in fact **−6.0%**.

> **Correction.** An earlier version of this file reported a 7.7x revenue gap.
> That figure compared medians across *all* listings, including the 34.7% of
> regular-host listings with no bookings at all, and overstates the difference.
> The comparable figure is 2.7x. See `revenue-analysis.md` section 5.

Note also that Superhost status is awarded partly on booking performance, so
this is an association between two outcomes rather than an effect of the badge.

## 5. Demand is strongly seasonal

Review-volume index, mean month = 1 (`reports/tables/seasonality_index.csv`):

- Peak: March 1.26, January 1.22 — the Australian Open and Grand Prix window.
- Trough: June 0.71, August 0.83.

Roughly a 1.8x swing between the best and worst months. A flat annual rate leaves
money on the table in summer and occupancy on the table in winter.

## 6. Highest-revenue segments

Median annual revenue, segments with at least 30 listings
(`reports/tables/segment_revenue.csv`):

| Segment | Listings | Median price | Occupancy | Median revenue |
|---|---|---|---|---|
| Yarra Ranges · entire · 5+ guests | 378 | $485 | 19.7% | $31,917 |
| Yarra · entire · 5+ guests | 192 | $493 | 15.1% | $27,409 |
| Yarra Ranges · entire · 3–4 guests | 183 | $319 | 21.4% | $26,250 |
| Melbourne · entire · 5+ guests | 1,817 | $327 | 19.7% | $24,772 |
| Yarra · entire · 1–2 guests | 361 | $231 | 24.7% | $21,404 |
| Melbourne · entire · 3–4 guests | 2,408 | $268 | 18.1% | $17,798 |

Three defensible routes for the client:

1. **Large holiday houses in Yarra Ranges** — highest revenue ceiling, thinner
   competition, but seasonal and weekend-dependent.
2. **Three- to four-guest apartments in the Melbourne LGA** — the deepest market
   (2,408 comparable listings) and the easiest to fill, at the cost of the
   heaviest price competition.
3. **One- to two-guest apartments in Yarra** — lowest entry cost, the highest
   occupancy in the table at 24.7%, and a +17% location premium.

Avoid Wyndham, Whitehorse and Monash for short-stay, and shared rooms in any
location.

## Open questions for the team

- Should we model revenue directly rather than price? Price is only half the
  decision and the Superhost finding suggests revenue is where the story is.
- The review text (1.03 million comments) is untouched. Sentiment or topic
  analysis could explain what separates a 4.9 listing from a 4.7 one.
- Regulatory angle: Victoria's short-stay levy took effect in 2025 and the 28+
  night segment behaves like a workaround. Worth checking whether the brief
  wants that discussed.
