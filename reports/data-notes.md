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
3. **`instant_bookable` is 100% missing** in this snapshot — every value is `"NA"`.
   It cannot be used and is excluded from the model.
4. **The calendar file has no price column**, contrary to the project brief. It
   carries only availability and the min/max night rules, so all price analysis
   relies on the listings snapshot.
5. **`bathrooms` is empty**; the information sits in `bathrooms_text`
   ("1.5 shared baths", "Half-bath") and needs parsing.
6. **Long free-text fields contain embedded newlines** and `<br/>` tags, so the
   physical line count of listings_airbnb.csv (62,204) is far higher than its
   record count (25,728). Any parser must handle quoted newlines — `fread` and
   `read_csv` both do; naive line splitting does not.
7. **`estimated_occupancy_l365d` and `estimated_revenue_l365d` are Inside Airbnb
   estimates** derived from review volume, not booking records. They understate
   true occupancy and should only be used to compare listings against each other.

## Derived variables

Created in `scripts/01_data_cleaning.R`:

| Variable | Definition |
|---|---|
| `price_num` | numeric nightly price |
| `priced` | flag: price present and between $30 and $1,500 |
| `bathrooms_num`, `shared_bath` | parsed from `bathrooms_text` |
| `n_amenities` | count of items in the amenities list |
| `min_nights_grp` | 1 / 2-6 / 7-27 / 28+ nights |
