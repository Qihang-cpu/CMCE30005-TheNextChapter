# Descriptive analytics

Week 5 workshop stage. Produced by `scripts/07_descriptive_analytics.R`; tables
in `reports/tables/desc_*.csv`, figures 11–15 in `reports/figures/`.

This note covers what the data *looks like*. The substantive results — the price
model, the revenue decomposition, seasonality and the ROI screen — are in
[findings.md](findings.md) and [revenue-analysis.md](revenue-analysis.md).

## Samples

| Sample | Rule | n |
|---|---|---:|
| Full snapshot | Inside Airbnb, 16 June 2026 | 25,728 |
| Priced sample | Nightly rate present and within $30–$1,500 | 18,927 |

Composition uses the full snapshot; anything involving price uses the priced
sample. The two are labelled separately in every table rather than mixed.

## 1. Key numerical variables

Sixteen variables, chosen because each maps to a decision in the business
problem: what the property is, what it charges, how much trade it does, and how
guests rate it. Full statistics in `desc_numeric_summary.csv`.

Completeness is the headline. Four blocks of missingness matter:

| Variable | Complete | Missing |
|---|---:|---:|
| `bathrooms_num` | 99.9% | 26 |
| `review_scores_*`, `reviews_per_month` | 82.6% | 4,477 |
| `bedrooms` | 81.8% | 4,679 |
| `price_num`, `price_per_person`, `estimated_revenue_l365d` | 74.5% | 6,553 |

Two distributions justify decisions made elsewhere in the pipeline:

- **Price is extremely right skewed** — on the full snapshot the median is
  \$243.67 but the mean is \$317.65 and the maximum \$50,093.56. Figure 11 shows
  the raw and logged distributions side by side; the log is near symmetric,
  which is why the price model logs its response and why the $30–$1,500 window
  exists.
- **`minimum_nights` reaches 1,000**, so it is binned into `1 / 2–6 / 7–27 / 28+`
  rather than used as a raw count.

## 2. Key categorical variables

Eight variables; levels and shares in `desc_categorical_summary.csv`, charted in
figure 12.

| Variable | Dominant levels |
|---|---|
| Room type | Entire home/apt 73.2%, private room 25.7%, shared 0.9%, hotel 0.2% |
| Minimum nights | 2–6 nights 49.5%, 1 night 41.8%, 7–27 6.3%, 28+ 2.4% |
| Superhost | 30.6% of listings |
| Shared bathroom | 14.3% of listings |

Shared and hotel rooms are together barely 1% of the market. They are reported
for completeness but are too thin to support segment conclusions.

## 3. Summary statistics by group

### By room type (priced sample)

| Room type | n | % | Median price | Median $/person | % Superhost | Median revenue |
|---|---:|---:|---:|---:|---:|---:|
| Entire home/apt | 14,278 | 75.4 | $278.90 | $72.50 | 42.2 | $14,664 |
| Private room | 4,411 | 23.3 | $109.00 | $63.00 | 27.2 | $936 |
| Shared room | 197 | 1.0 | $50.00 | $28.00 | 6.1 | $0 |
| Hotel room | 41 | 0.2 | $324.00 | $109.50 | 7.3 | $0 |

Entire homes charge 2.6× the nightly rate of private rooms but only 1.15× the
rate *per guest* — most of the headline price gap is capacity, not premium.

### By Superhost status (priced sample)

| | Regular host | Superhost |
|---|---:|---:|
| Listings | 11,685 | 7,242 |
| Median price | $234.50 | $254.00 |
| Median rating | 4.75 | 4.91 |
| Median reviews (last 12 months) | 2 | 15 |
| Median nights booked | 12 | 96 |
| Median annual revenue | $3,048 | $23,445 |

Price differs by 8% between the two groups; booked nights differ by a factor of
eight. This is the descriptive form of the result the revenue analysis develops.

### By LGA

`desc_by_lga.csv` ranks all LGAs. Yarra Ranges leads on median price ($343, 984
listings, 63.2% Superhost), ahead of Bayside ($325) and Nillumbik ($287).
Melbourne LGA is by far the largest market (6,463 priced listings) at a median
of $251. Figure 13 shows the full price spread by LGA and room type.

## 4. Relationship worth carrying forward

Figure 15 plots price against trailing-year review activity. The two room types
behave differently:

- **Entire homes** peak in review activity at roughly **$200–250 per night**,
  then decline. Both cheaper and more expensive listings show less trade.
- **Private rooms** decline monotonically across the whole price range.

Activity is a proxy for bookings, so this is the first direct evidence that the
revenue-maximising price is interior rather than "as high as possible" — the
question the modelling stage takes up.

## Caveats

1. Occupancy and revenue are Inside Airbnb estimates derived from review volume,
   not booking records. They support relative comparison only.
2. The snapshot covers listings active on one day, so listings that failed and
   were withdrawn are absent. Observed performance is optimistic.
3. Median is reported throughout in preference to mean, because every monetary
   variable here is heavily right skewed.
