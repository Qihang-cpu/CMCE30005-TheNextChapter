# Data notes: Inside Airbnb Melbourne

Snapshot collected 16 June 2026, covering active listings across Greater Melbourne
and surrounding local government areas.

## Getting the data

The three raw files total roughly 700 MB and are **not** committed to this
repository. Download them from Inside Airbnb (Melbourne, 16 June 2026 snapshot)
and place them in `data/raw/`:

```text
data/raw/listings_airbnb.csv     68 MB    25,728 rows
data/raw/calendar_airbnb.csv    361 MB     9,390,720 rows
data/raw/reviews_airbnb.csv     266 MB     1,026,690 rows
```

All three join on the listing key: `calendar.listing_id` and `reviews.listing_id`
match `listings.id`.

| File | Grain | Coverage |
|---|---|---|
| listings | one row per listing, ~90 columns | snapshot at 16 June 2026 |
| calendar | listing x night | 17 Jun 2026 – 30 Jun 2027 |
| reviews | one row per review | 4 Aug 2010 – 28 Jun 2026 |

## Quality issues found

These cost us time, so they are worth knowing before writing any new script.

1. **Missing values arrive as the literal string `"NA"`.** Every numeric column is
   read as text unless `na.strings = c("NA", "", "N/A")` is set. Affects
   `bedrooms` (4,679 missing), all `review_scores_*` (4,477), and others.
2. **`price` is text**, formatted `$1,234.00`. Strip `$` and commas before
   converting. 6,553 listings (25.5%) have no price at all.
3. **Thirteen columns are entirely empty** in this snapshot — every value is
   `"NA"`. They are dropped in cleaning rather than carried through:
   `calendar_updated`, `host_acceptance_rate`, `host_neighbourhood`,
   `host_response_rate`, `host_response_time`, `host_since`,
   `host_thumbnail_url`, `host_total_listings_count`, `instant_bookable`,
   `license`, `neighborhood_overview`, `neighbourhood`,
   `neighbourhood_group_cleansed`.
   Note that this removes every direct measure of host responsiveness. Host
   tenure survives only because `hosts_time_as_host_years` and
   `hosts_time_as_host_months` are populated even though `host_since` is not.
4. **The calendar file has no price column**, contrary to the project brief. It
   carries only availability and the min/max night rules, so all price analysis
   relies on the listings snapshot.
5. **`bathrooms` is empty**; the information sits in `bathrooms_text`
   ("1.5 shared baths", "Half-bath") and needs parsing.
6. **Long free-text fields contain embedded newlines** and `<br/>` tags, so the
   physical line count of listings_airbnb.csv (62,204) is far higher than its
   record count (25,728). Any parser must handle quoted newlines — `fread` and
   `read_csv` both do; naive line splitting does not.
7. **`estimated_occupancy_l365d` and `estimated_revenue_l365d` are constructed
   fields, not measurements.** They are computed as

   ```
   occupancy = min( reviews_ltm x 2 x max(minimum_nights, 3), 255 )
   revenue   = round( price x occupancy )
   ```

   We verified this against the data: the occupancy formula reproduces the
   published field exactly for 100% of listings with a booking, and the revenue
   formula for 99.1% (the rest is rounding to whole dollars).

   The practical consequence is that **regressing revenue on price, review count
   or minimum nights is circular** — those variables are revenue by
   construction, and such a model returns a meaningless near-perfect fit. Model
   the components instead. See `revenue-analysis.md` section 1.

## Derived variables

Created in `scripts/01_data_cleaning.R`:

| Variable | Definition |
|---|---|
| `price_num` | numeric nightly price |
| `priced` | flag: price present and between $30 and $1,500 |
| `bathrooms_num`, `shared_bath` | parsed from `bathrooms_text` |
| `n_amenities` | count of items in the amenities list |
| `min_nights_grp` | 1 / 2-6 / 7-27 / 28+ nights |


## External data: DFFH median rents

`data/external/dffh_median_rents_sep2025.csv` holds official quarterly median
rents by LGA and dwelling type from the Homes Victoria Rental Report
(https://www.dffh.vic.gov.au/publications/rental-report), September quarter
2025 — the latest published edition, which lags our June 2026 entry date by
three quarters. The `uplifted_to_jun2026` column compounds each segment's own
Sep-24 to Sep-25 growth (clipped to 0–8% to damp thin-market noise) over that
lag. There is no official 1-bedroom-house series; analyses bound it by the
1BR-flat and 2BR-house series and say so wherever it is used. Note the DFFH
tables use the LGA's current name Merri-bek where Inside Airbnb still says
Moreland.

## Segment ROI screen

Produced by `scripts/06_segment_roi_screen.R` from the cleaned listings and the
official rents that `scripts/05_rent_data.R` downloads and projects forward.

Scope follows the rent data. DFFH publishes four series - 1BR flat, 2BR flat,
2BR house, 3BR house - and a segment is only screened if a like-for-like rent
exists or can be derived on a defensible basis:

- Apartments and 2-3 bedroom houses map straight onto a published series.
- One-bedroom houses have no series. Their rent is derived as the LGA's own
  2BR-house median scaled down by a one-to-two-bedroom step. The step is
  observable only for flats, and flats are not houses: where both are published,
  flats rise more per bedroom than houses (two-to-three-bedroom step 1.20 versus
  1.15 at the median, higher in 40 of 51 LGAs, paired t = 3.4). An uncalibrated
  flat step therefore understates house rent and flatters ROI. The step is
  calibrated by the house-to-flat ratio measured at the two-to-three step
  (factor 1.023) and clipped to its interquartile range, giving a median step of
  0.79 (0.74-0.84). These rows carry `rent_derived = TRUE`.

  For the largest affected segment, Yarra Ranges 1BR houses, the three
  approaches give: 2BR-house rent used as an upper bound, $583/week and 62% ROI;
  an uncalibrated flat step, $420 and 112%; the calibrated step, $429 and 109%.
  The upper bound understates the segment badly; the calibration removes a
  smaller bias in the opposite direction.
- Three-bedroom apartments are excluded: deriving them needs a dwelling-type
  step rather than a bedroom step, on a much smaller base (961 listings).

Revenue percentiles come from the active, priced subset of each segment; where
that subset is small the percentile is indicative only. `dffh_published` marks the four
configurations DFFH publishes a rent for - 1BR flat, 2BR flat, 2BR house, 3BR
house - which form the main screen. One-bedroom houses use a derived rent and
are reported as sensitivity rather than carried into the recommendation, so no
segment in the main screen rests on a cost we had to estimate.

The per-property capital ceiling is treated as a decision rather than a fixed
constraint, because it determines which market the operator can reach at all:
$20k reaches 12 segments and none clear the hurdle; $26k reaches 31 and one
clears; $36k reaches 52 and two clear, the additional one carrying the highest
net cash in the screen. The marginal $8.1k of capital returns about $5.4k a
year.

At P75 performance under baseline costs, 3 of 57 segments clear a 50% first-year
cash-on-cash return, 7 more are positive, and 47 sit below break-even.

## What the data cannot tell us: ownership

Nothing in the 90 listing columns records whether a host owns the property or
leases it. `license` is empty for all 25,728 rows and `property_type` describes
the dwelling, not the tenure. The screen therefore prices one model explicitly -
an operator paying market rent - and reports owner economics separately as a
counterfactual, where the rent line is replaced by forgone long-let income. No
claim is made about how much of the observed supply is owner-operated, because
the data cannot support one.

## Amenity index: what "time-valid" would and would not mean

The neighbourhood amenity index is built from Google Places in June 2026.
Timestamping and caching the queries records when we pulled the data; it does
not establish that a given venue was trading at each historical snapshot date.
The index is therefore treated as a June 2026 measurement assumed to be
approximately time-stable over the nine-month window, and the assumption is
sensitivity-tested rather than asserted. Scraped review volumes, which move
much faster than venue counts, stay out of the temporal models entirely and are
used only for June cross-sectional exploration.
