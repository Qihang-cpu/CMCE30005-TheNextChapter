# CMCE30005 Business Analytics Challenge

## TheNextChapter — Group 2

- **Subject:** CMCE30005 Business Analytics Challenge, Semester 2 2026
- **University:** University of Melbourne
- **Team Members:** EricH896, Qihang-cpu, maksym-xu, LeLoc0602

---

# Project Plan

> **Status:** draft prepared for the Week 3 workshop (13 August 2026), for team
> sign-off. Two items still need a group decision and are marked **[decide]**
> below: the role allocation in Section 8, and whether the revenue model in
> Section 6 is in scope for the midterm.

The plan follows CRISP-DM. Sections 1–7 map to the first five phases; Section 8
covers project management and Section 9 fixes the boundary of the work.

---

## 1. Business Problem

A client intends to list **multiple properties on Airbnb in Melbourne** and has
engaged us as their business analytics consultant. Before committing capital
they face three decisions: **where to buy or lease, what property type and
configuration to operate, and how to price it.**

These decisions matter because they are close to irreversible. Location and
property size are fixed at purchase, entry cost is large, and the Melbourne
market is not made up of householders letting a spare room — **55.8% of active
listings belong to hosts running more than one property**, so a new entrant is
competing against professional operators. Choosing the wrong segment cannot be
corrected by adjusting the nightly rate later.

**Key questions:**

| # | Question | Why it is decision-relevant |
|---|---|---|
| Q1 | Which local government areas (LGAs) and property segments deliver the highest **expected annual revenue per listing**, rather than the highest nightly rate? | Determines where to buy |
| Q2 | Which property, host and location attributes drive nightly price, and by what percentage? | Determines what to buy and how to price it |
| Q3 | How much of the earnings gap between Superhosts and regular hosts is **price** and how much is **occupancy**? | Determines where to spend operating effort |
| Q4 | How seasonal is demand, and what does that imply for a pricing calendar? | Determines the annual pricing strategy |

**Objective.** Produce an evidence-based entry and pricing recommendation: a
shortlist of two to three location × property-type segments with expected annual
revenue, plus a pricing rule the client can apply from attributes that are known
*before* purchase.

---

## 2. Data

### 2.1 Dataset

- **Dataset name:** Inside Airbnb — Melbourne
- **Source:** [Inside Airbnb](https://insideairbnb.com)
- **Coverage:** Snapshot of 16 June 2026; active listings across Greater
  Melbourne and surrounding local government areas

| File | Grain | Rows | Size | Coverage |
|---|---|---:|---:|---|
| `listings_airbnb.csv` | One row per active listing, ~90 attributes | 25,728 | 68 MB | Snapshot at 16 Jun 2026 |
| `calendar_airbnb.csv` | Listing × night | 9,390,720 | 361 MB | 17 Jun 2026 – 30 Jun 2027 |
| `reviews_airbnb.csv` | One row per review | 1,026,690 | 266 MB | 4 Aug 2010 – 28 Jun 2026 |

All three join on the listing key: `calendar.listing_id` and
`reviews.listing_id` match `listings.id`.

> Large raw data files are not committed to this repository. Download the three
> files from Inside Airbnb and place them in `data/raw/`. See
> [reports/data-notes.md](reports/data-notes.md) for the full data dictionary notes.

### 2.2 Key variables and features

| Role in the analysis | Variables |
|---|---|
| **Outcomes** | `price` (nightly rate), `estimated_revenue_l365d`, `estimated_occupancy_l365d` |
| **Property attributes** | `room_type`, `property_type`, `accommodates`, `bedrooms`, `beds`, `bathrooms_text`, `amenities` |
| **Location** | `neighbourhood_cleansed` (LGA), `latitude`, `longitude`, `review_scores_location` |
| **Host attributes** | `host_is_superhost`, `host_since`, `host_total_listings_count`, `calculated_host_listings_count`, `host_response_rate`, `host_acceptance_rate` |
| **Quality and traction** | `review_scores_rating`, `number_of_reviews`, `number_of_reviews_ltm`, `reviews_per_month`, `first_review`, `last_review` |
| **Availability and rules** | `availability_90`, `availability_365`, `minimum_nights`, `maximum_nights`, `calendar.available`, `calendar.date` |
| **Demand proxy** | `reviews.date` (monthly review volume) |

### 2.3 Limitations and potential data-quality issues

Identified during initial exploration; each is documented with its fix in
[reports/data-notes.md](reports/data-notes.md).

1. **Missing values arrive as the literal string `"NA"`.** Every numeric column
   is read as text unless `na.strings` is set explicitly.
2. **`price` is stored as text** (`$1,234.00`), and **6,553 listings (25.5%)
   have no price at all**.
3. **`instant_bookable` is 100% missing** in this snapshot and cannot be used.
4. **`bathrooms` is empty**; the information sits in the free-text
   `bathrooms_text` ("1.5 shared baths", "Half-bath") and must be parsed.
5. **The calendar file has no price column**, contrary to the project brief, so
   all price analysis relies on the listings snapshot and no realised-price time
   series is available.
6. **Free-text fields contain embedded newlines and `<br/>` tags**, so the
   physical line count of the listings file (62,204) far exceeds its record
   count (25,728). Naive line-splitting parsers fail on this file.
7. **`estimated_occupancy_l365d` and `estimated_revenue_l365d` are Inside Airbnb
   estimates** derived from review volume, not booking records. They understate
   true occupancy and support relative comparison only.
8. **Survivorship bias.** Only listings active on 16 June 2026 appear. Listings
   that failed and were withdrawn are absent, so observed performance is
   optimistic relative to the outcome a new entrant should expect.
9. **Volume.** The calendar file is 9.4 million rows; it needs a memory-efficient
   reader (`data.table::fread`) and aggregation before use.
10. **Single-day cross-section.** The snapshot supports association, not causal
    estimates, and carries no seasonal adjustment hosts may apply later in the year.

### 2.4 Assumptions

- The listed nightly price approximates the transacted price; discounts, cleaning
  fees and platform fees are not observable.
- A listing with **at least three reviews** has had its asking price tested by
  the market; listings with fewer are excluded from modelling.
- The **$30–$1,500** nightly band defines the short-stay market. Below $30 the
  values are mis-entered or long-let rates; above $1,500 sit 248 luxury outliers.
- **Review volume is proportional to bookings**, with a review rate that is
  stable across months. This is what makes review counts usable as a demand proxy.
- **LGA is a meaningful unit** for an investment decision — granular enough to
  guide a purchase, coarse enough to estimate reliably.
- Market conditions at 16 June 2026 hold over the client's decision horizon.

---

## 3. Analytics Task

The client's decision variables — price and annual revenue — are continuous, so
the core task is **regression**, supported by descriptive and exploratory work
that defines the segments and a time-series description of demand. Classification
is not appropriate here: there is no meaningful class label the client needs
predicted.

| Business question | Analytics task | Output |
|---|---|---|
| Market context | Descriptive analytics | Supply, concentration and competition profile |
| Q1 | Exploratory data analysis + segment aggregation | Revenue-ranked location × room type × capacity segments |
| Q2 | **Hedonic regression** (log-linear OLS) | Percentage price effect of each attribute, and an LGA premium |
| Q3 | Group comparison + regression coefficient | Decomposition of the Superhost gap into price and occupancy |
| Q4 | Time-series descriptive analysis | Monthly demand index and a seasonal pricing implication |

**Why hedonic regression.** It prices attributes rather than properties: each
coefficient reads directly as "an extra bedroom is worth *x*%", which is exactly
the form the client needs to compare candidate purchases. Logging the response
converts coefficients to percentage effects and handles the strong right skew in
price.

**Planned extension [decide].** Price is only half of the client's objective.
Modelling **annual revenue** directly would answer Q1 in one step rather than
inferring it from price and occupancy separately, and the Superhost result
(Section 6) suggests revenue is where the substantive story is.

---

## 4. Data Understanding

Completed in `scripts/01`–`02`; outputs are in `reports/figures/` and
`reports/tables/`.

- **Initial exploration** — dimensions, column types and the 90-variable
  dictionary reviewed against the Inside Airbnb definitions.
- **Variable types and distributions** — nightly price is heavily right skewed
  and is examined on a log scale (`01_price_distribution.png`); capacity and
  bedroom counts are discrete with a long right tail.
- **Missing values** — quantified per column: `price` 6,553, `bedrooms` 4,679,
  all `review_scores_*` 4,477, `instant_bookable` 25,728 (all).
- **Duplicate records** — `listings.id` verified unique; the calendar is checked
  for duplicate listing × date pairs before aggregation.
- **Outliers** — the price tails are inspected and bounded at $30 and $1,500;
  `minimum_nights` has implausible extreme values and is binned rather than used
  as a raw count.
- **Relationships between variables** — price against capacity and room type
  (`03_price_capacity_roomtype.png`), price against estimated occupancy
  (`05_price_vs_occupancy.png`), and price against location
  (`02_price_by_area.png`).
- **Potential biases** — survivorship bias in the active-listing snapshot, and
  the review-based construction of the occupancy and revenue estimates.
- **Descriptive statistics** — listing counts, median price, median occupancy and
  median annual revenue by LGA (`reports/tables/area_summary.csv`), and the
  Superhost comparison (`reports/tables/superhost_comparison.csv`).
- **Demand over time** — monthly review volume, July 2023 to June 2026
  (`04_demand_seasonality.png`).

**What this stage established:** 25,728 active listings held by 14,113 hosts;
73.2% entire homes or apartments and 25.7% private rooms; and the concentration
result that 55.8% of listings belong to multi-property hosts.

---

## 5. Data Preparation

Implemented in `scripts/01_data_cleaning.R`, which writes analysis-ready tables
to `data/processed/`.

| Activity | What we do | Status |
|---|---|---|
| Data type conversion | Declare `na.strings = c("NA", "", "N/A")`; coerce 14 numeric columns read as text | Done |
| Cleaning text fields | Strip `$` and `,` from `price`; convert response and acceptance rates from `%` to proportions | Done |
| Feature extraction | Parse `bathrooms_num` and `shared_bath` from `bathrooms_text`; count amenities into `n_amenities` | Done |
| Variable transformation | Log the price response; bin `minimum_nights` into `1 / 2–6 / 7–27 / 28+` | Done |
| Outlier treatment | `priced` flag restricting the sample to $30–$1,500 | Done |
| Categorical encoding | Pool LGAs with fewer than 200 listings into "Other"; set reference levels (`Melbourne`, `Entire home/apt`) | Done |
| Data integration | Aggregate the 9.4 M-row calendar to monthly availability and a 90-day open rate; aggregate reviews to monthly counts and per-listing totals; join on the listing key | Done |
| Missing-value handling | Listwise deletion for the model sample; missingness reported rather than imputed | Done |
| Feature engineering | Distance to the CBD from `latitude`/`longitude`; host tenure from `host_since` | Planned |
| Train/test split | Required once predictive models are compared (Section 6) | Planned |
| Scaling | Standardise inputs before any distance-based clustering | Planned if clustering is used |

**Sample definition.** Three nested samples, with the reduction documented so it
can be defended in the report:

| Stage | Rule | Remaining |
|---|---|---:|
| Full snapshot | Inside Airbnb, 16 June 2026 | 25,728 |
| Priced sample | Price present and within $30–$1,500 | 18,927 |
| Model sample | Plus bedrooms, bathrooms, capacity, both review scores and a minimum-nights group present, and at least 3 reviews | 12,223 |

---

## 6. Modelling

### Current model

A hedonic regression of logged nightly price on property, host and location
attributes (`scripts/03_price_model.R`):

```r
lm(log(price_num) ~ room_type + accommodates + bedrooms + bathrooms_num +
     shared_bath + n_amenities + host_is_superhost + review_scores_rating +
     review_scores_location + min_nights_grp + lga)
```

- **Target variable:** `log(price_num)`. Each coefficient converts to a
  percentage effect via `exp(beta) - 1`.
- **Sample:** n = 12,223. **Adjusted R² = 0.558.**
- `instant_bookable` is excluded because it is entirely missing.
- Interim results are in [reports/findings.md](reports/findings.md); the
  specification and its justification are in
  [reports/methodology.md](reports/methodology.md).

The result that drives the extension below: Superhosts earn **7.7× the annual
revenue** of regular hosts, yet once listing attributes are held constant the
Superhost price coefficient is **−6.0%**. The gap is occupancy, not price.

### Models proposed

| Model | Purpose | Why it is appropriate |
|---|---|---|
| Log-linear OLS (hedonic) | Explain price | Interpretable percentage effects; the client needs attribution, not just prediction |
| **Revenue model [decide]** — log annual revenue on the same predictors plus occupancy drivers | Answer Q1 directly | Revenue is the client's actual objective; price alone ignores half the decision |
| Regularised regression (ridge / lasso) | Benchmark | Tests whether the OLS specification is over-fitted given correlated predictors |
| Tree-based model (random forest or gradient boosting) | Benchmark | Detects non-linearity and interactions that the linear form would miss; if it does not beat OLS materially, that justifies keeping the interpretable model |
| k-means clustering | Segment definition | Derives segments from the data instead of the manual location × room type × capacity bins used so far |

We expect to **compare multiple models** and to report the comparison, not only
the winner.

### Assumptions and considerations

- Linearity in logs, and additive attribute effects.
- `bedrooms`, `beds` and `accommodates` are correlated; multicollinearity is
  checked with VIF before interpreting individual coefficients.
- Heteroskedasticity is checked by mean absolute residual across fitted-value
  bands (already implemented in `scripts/03`).
- The model is **cross-sectional**: coefficients describe association in a market
  equilibrium, not the causal return on adding a bedroom.
- Roughly 44% of price variation is unexplained, most plausibly fit-out quality,
  photography and views — none of which the data captures.

---

## 7. Evaluation

Evaluation runs on two levels, and a model must pass both.

**Technical criteria**

| Measure | Applied to | Target |
|---|---|---|
| Adjusted R² | Explanatory price model | Currently 0.558; report honestly rather than inflate |
| RMSE and MAE | Predictive models, on a held-out test set | Compared across candidate models on the same split |
| Cross-validation | Model comparison | k-fold, so the comparison is not an artefact of one split |
| Residual diagnostics | All regressions | No systematic pattern across fitted-value bands |
| Coefficient significance and sign | Hedonic model | Effects significant at p < 0.001 and directionally plausible |
| VIF | Hedonic model | Multicollinearity below conventional thresholds |
| Cluster validity (silhouette) | Clustering, if used | Segments that are separable, not arbitrary cuts |

**Business criteria** — the test that actually matters:

- Does the recommended shortlist beat a naive "buy an apartment in the Melbourne
  LGA" baseline on expected annual revenue?
- Can the client **apply** the pricing rule using attributes known before
  purchase? A model needing post-listing variables is useless for the decision.
- Are the effect sizes commercially material? A +15.8% per-bedroom effect changes
  a purchase decision; a 2% effect does not.
- Are the conclusions **robust** to the judgement calls — the $30–$1,500 window,
  the three-review threshold, and the 200-listing LGA pooling rule?

A model is not successful merely because it scores well. With 44% of price
variation unexplained, the deliverable is judged on whether it improves the
client's location, property-type and pricing decisions relative to what they
would do without it.

---

## 8. Project Milestones and Team Responsibilities

**Proposed roles [decide]** — to be confirmed at the Week 3 workshop, based on
contributions to date. Responsibilities are indicative; all members review and
contribute to the final report.

| Member | Role | Responsibility |
|---|---|---|
| Qihang-cpu | Project lead | Coordination, deadlines, repository owner, merging branches |
| maksym-xu | Data lead | Cleaning pipeline, feature engineering, data documentation |
| EricH896 | Modelling lead | Model specification, comparison and diagnostics |
| LeLoc0602 | Report and visualisation lead | Figures, README report, presentation deck |

**Milestones**

| Project stage | Key activities | Responsible | Target | Expected output | Depends on |
|---|---|---|---|---|---|
| Business Understanding | Agree the problem statement, questions and scope | All | **Week 3 — 13 Aug** | This project plan, signed off in `README.md` | — |
| Data Understanding | Explore and assess the three files; document quality issues | Data lead | **Week 3 — 13 Aug** | `reports/data-notes.md`, EDA figures | Data downloaded |
| Data Preparation | Clean, parse, aggregate and join; define the samples | Data lead | **Week 4 — 20 Aug** | `scripts/01`, `data/processed/*.rds` | Data Understanding |
| Modelling (baseline) | Hedonic price model and diagnostics | Modelling lead | **Week 4 — 20 Aug** | `scripts/03`, coefficient table | Data Preparation |
| Midterm presentation | Consolidate plan, scope and interim findings into a deck | All | **Week 5 — 27 Aug** | Presentation; every member presents | All of the above |
| Modelling (extension) | Revenue model; compare regularised and tree-based models | Modelling lead | Week 7 | Model comparison table | Midterm feedback |
| Evaluation | Held-out testing, robustness checks, business assessment | Modelling + Data leads | Week 9 | Evaluation section of the report | Modelling (extension) |
| Finalisation | Recommendations, report write-up, final presentation | Report lead + all | Week 11–12 | Final report in `README.md`, final deck | Evaluation |

Dates from Week 6 onward follow the LMS teaching calendar and should be confirmed
against it, as the mid-semester break shifts them.

**Risks and contingencies**

| Risk | Contingency |
|---|---|
| Occupancy and revenue are estimates, not booking records | Frame all revenue results as relative comparisons; state the limitation in every table that uses them |
| The calendar file has no price column, so no realised-price series exists | Rely on the listings snapshot; drop any analysis that assumed observed price over time |
| 25.5% of listings have no price | Report the reduction explicitly and test whether priced and unpriced listings differ systematically |
| Scope creep into review-text analysis (1.03 M comments) | Explicitly out of scope for the midterm; revisit only if Sections 1–7 are complete |
| Uneven workload across members | Roles assigned above; the project lead checks contributions against the commit history each week |

Analytics projects are **iterative**, so this table is not a strictly linear
sequence. Exploring the data may force the business question to be refined, and
data-quality problems may send us back to Data Understanding or Data Preparation.

---

## 9. Project Scope

This project investigates **where a prospective multi-property host should invest
in the Melbourne short-stay market, what property configuration to operate, and
how to price it.** Within scope are the three Inside Airbnb files for the 16 June
2026 Melbourne snapshot; a descriptive profile of supply, concentration and
competition; a hedonic regression that quantifies the percentage price effect of
property, host and location attributes; a comparison of Superhost and regular-host
performance; a monthly demand index built from review volume; and a
revenue-ranked shortlist of location × property-type segments. The deliverable is
a recommendation the client can act on: a shortlist of two to three segments with
expected annual revenue, and a pricing rule based on attributes observable before
purchase.

Out of scope are several things the data cannot support. We will not attempt
causal estimates of the return on renovation — the snapshot is cross-sectional,
so a bedroom coefficient is an equilibrium association, not the payoff from
adding a bedroom. We will not analyse realised transaction prices or booking
records, because the calendar file carries availability only and the occupancy
and revenue fields are Inside Airbnb estimates derived from review volume.
Natural-language analysis of the 1.03 million review comments, property-purchase
cost and financing, regulatory and tax modelling of Victoria's short-stay levy,
and any geography outside Greater Melbourne are all excluded. Sentiment analysis
of review text is the one exclusion we would revisit if time allows after
Section 7 is complete.

The main constraints are the data and the timeline. Only listings active on 16
June 2026 are observed, so failed listings are invisible and performance figures
are optimistic; 25.5% of listings carry no price and are excluded from price
analysis; and all revenue and occupancy figures are estimates that support
relative ranking but not absolute forecasting. The project runs to the end of
Semester 2, 2026 with four members working alongside other subjects, which is why
the scope is deliberately bounded to the questions in Section 1. Holding that
boundary is what makes the remaining questions answerable to a defensible
standard rather than all of them answerable badly.

---

## Running the Analysis

Open `CMCE30005-Group2.Rproj` so the working directory is the project root, then
run the scripts in order:

```r
source("scripts/00_packages.R")          # once, to install and load packages
source("scripts/01_data_cleaning.R")     # ~2 min, writes data/processed/
source("scripts/02_exploratory_analysis.R")
source("scripts/03_price_model.R")
```

Script 01 additionally requires `data.table` and `stringr`; script 03 requires
`broom`. Charts land in `reports/figures/` and summary tables in
`reports/tables/`, both of which are committed so results can be reviewed
without re-running the pipeline.

**Before you start work each session,** pull first:

```bash
git pull origin main
```

---

## Repository Structure

```text
CMCE30005-Group2/
├── data/
│   ├── raw/        # Source CSVs (not committed - download separately)
│   └── processed/  # Cleaned tables rebuilt by scripts/01 (not committed)
├── scripts/        # R analysis scripts, run in numbered order
├── reports/
│   ├── figures/    # Charts
│   ├── tables/     # Summary tables and model output
│   ├── data-notes.md
│   ├── methodology.md
│   └── findings.md # Interim results
├── README.md
├── .gitignore
└── CMCE30005-Group2.Rproj
```

---

*Last updated: 13 August 2026*
