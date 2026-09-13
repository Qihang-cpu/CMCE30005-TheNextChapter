# CMCE30005 Business Analytics Challenge

## TheNextChapter — Group 2

**Subject:** CMCE30005 Business Analytics Challenge, Semester 2 2026

**Team:** EricH896, Qihang-cpu, maksym-xu, Leloc

**Project status:** Interim analysis plan, updated 13 September 2026

## 1. Introduction

This project examines market-entry decisions for a prospective multi-property Airbnb operator in Greater Melbourne. The operator intends to lease standard residential properties, obtain the required authorisation, furnish them and operate them as entire-home short-stay accommodation. This model involves substantial fixed commitments before demand is known, so selecting the wrong location or dwelling configuration can create prolonged cash-flow pressure.

The original project framed success as a 50% first-year cash-on-cash return. We have revised this framing because the supplied Airbnb data do not observe market rent, fit-out expenditure, operating costs or actual profit. The project now focuses on a result the supplied data can support: the probability that a listing reaches a clearly defined high-demand benchmark. Profitability is retained only as a later client-input scenario, not as an observed outcome.

The analysis uses the Inside Airbnb Melbourne snapshot collected on 16 June 2026, supported by its review history. The final objective is to rank eligible location–property configurations by predicted demand probability and explain the uncertainty and limitations of that ranking.

## 2. Business Problem and Research Question

The client must decide which Local Government Area (LGA) and dwelling configuration to investigate before signing a lease. An LGA is a council-level administrative area. A dwelling configuration combines broad property class and bedroom count. We restrict attention to standard rental-arbitrage-compatible entire homes: rental units and condominiums are grouped as **Apartment/unit**, while entire homes and townhouses are grouped as **House/townhouse**. Properties have one to three bedrooms, and an LGA × configuration cell must contain at least 50 comparable listings.

### Primary research question

> Among Greater Melbourne standard entire-home rental segments with at least 50 comparable listings, which LGA × 1–3-bedroom dwelling configuration gives a prospective multi-property Airbnb operator the highest out-of-sample predicted probability of achieving at least 22 guest reviews over a 12-month period—the observed market-wide top-quartile benchmark?

The threshold of 22 reviews is the 75th percentile of `number_of_reviews_ltm` across the eligible analytical sample. It is a transparent, reproducible definition of strong recent demand rather than a claim that 22 reviews guarantees profit. Reviews are used as a proxy because completed bookings are not observed and not every guest leaves a review.

The project has four objectives:

1. define a defensible and reproducible comparison set;
2. estimate the probability of reaching the common high-demand benchmark for unseen listings;
3. aggregate out-of-sample predictions into decision-relevant LGA × configuration rankings; and
4. translate estimated revenue percentiles into optional rent scenarios only when the client supplies an actual lease quotation.

## 3. Data Description and Current EDA

The supplied data contain three files:

- `listings_airbnb.csv`: 25,728 active listings and approximately 90 listing, host, location, price, availability and review variables;
- `reviews_airbnb.csv`: dated guest reviews used to verify the trailing-12-month review outcome and, if retained, describe seasonality; and
- `calendar_airbnb.csv`: forward availability and asking-price records. Calendar availability is not treated as observed occupancy because unavailable dates may represent either bookings or dates blocked by the host.

Nightly prices are converted from text to numeric values. Bedrooms and accommodation capacity are checked for valid values, bathroom counts are reconstructed from `bathrooms_text`, and amenity counts are derived from the amenity list. Prices outside AUD 30–1,500 are excluded from the main comparison to reduce the influence of apparent errors and highly specialised luxury properties. No statistical imputation is applied to the target.

After applying the current property mapping, bedroom, price and minimum-comparable filters, the analytical sample contains **8,967 listings**, **4,081 hosts** and **35 eligible LGA × configuration cells**. The common high-demand threshold is **22 reviews in the previous 12 months**; 2,315 listings, or 25.8%, meet it. Reconstructing trailing-year review counts from the raw review dates gives an exact match for 99.5% of eligible listings, with a maximum difference of two reviews.

The data remain cross-sectional. They support prediction for held-out listings under current market relationships, but not a causal claim, a future-quarter forecast or direct measurement of bookings and profit.

## 4. Methodology and Analytical Approach

The analysis follows four linked stages.

### 4.1 Descriptive analysis

We will document filtering, missingness and distributions, then compare supply, price and recent review activity across LGAs and dwelling configurations. All exclusions and property mappings will be defined before examining final rankings.

### 4.2 Predictive modelling

The binary outcome equals one when `number_of_reviews_ltm >= 22` and zero otherwise. Logistic regression will provide an interpretable benchmark. A tree-based model such as random forest will then test whether nonlinear relationships and interactions materially improve prediction.

Primary predictors will be limited to information observable or selectable before a new listing begins operating: LGA, dwelling configuration, accommodates, bathrooms, amenities, nightly price, minimum stay and local Airbnb supply. Reviews, ratings, Superhost status, estimated occupancy and estimated revenue are excluded from the primary new-entry model. Availability is also excluded because blocked and booked dates cannot be distinguished.

### 4.3 Validation and model selection

Listings operated by the same host may share pricing and management practices. Cross-validation will therefore keep each host entirely within one fold. This is more demanding and decision-relevant than a random row split. Models will be evaluated using ROC-AUC, precision–recall AUC, probability calibration and a confusion matrix at a stated decision threshold. Performance will be compared with a no-skill baseline. Final segment rankings will be calculated from out-of-fold probabilities, not fitted values from the training sample.

### 4.4 Decision translation and sensitivity analysis

For each eligible segment we will report listing count, host count, observed benchmark rate, mean predicted probability and an uncertainty interval. A separate sensitivity table may show the weekly rent supported by a segment's estimated P75 annual revenue under 1.5×, 2× and 2.5× revenue-to-rent assumptions. These are externally motivated scenarios, not measured profitability.

## 5. Progress and Next Steps

Completed work includes raw-data inspection, cleaning, property-scope definition, target reconstruction, cell-size checks, descriptive analysis and a preliminary host-grouped feasibility model. The preliminary logistic model achieved ROC-AUC 0.718 and precision–recall AUC 0.419, compared with a no-skill precision–recall baseline of 0.258. These results show that the proposed prediction is feasible, but they are not the final model or recommendation.

Remaining work is to implement the agreed model pipeline in R, compare logistic regression with a tree-based model, test calibration, estimate ranking uncertainty, conduct sensitivity checks for property mapping and listing exposure, and write the final interpretation. The team will also verify that every dataset and variable described in the report is actually used.

## 6. Reproducibility

Open `CMCE30005-Group2.Rproj` from the repository root. Raw files are intentionally excluded from GitHub because of their size. Existing numbered scripts reproduce the earlier cleaning and exploratory work. The next predictive script will implement the revised outcome, host-grouped validation and out-of-fold segment ranking described above. Preliminary scope-audit tables are stored under `reports/tables/`.

## 7. Important Limitations

- Reviews are an imperfect proxy for completed stays.
- The snapshot observes surviving listings and cannot identify the exact launch date of every listing.
- `first_review` is not equivalent to listing creation date, so a 12-month age filter will be treated as sensitivity analysis rather than the sole sample.
- Inside Airbnb occupancy and revenue are modelled estimates based partly on reviews, minimum stays and assumed review behaviour.
- Predictions describe associations in the June 2026 market and do not guarantee future demand, legal authorisation or profitability.

## 8. External Context

- [Victorian Parliamentary Budget Office: 90-day cap on short stay accommodation](https://static.pbo.vic.gov.au/files/PBO_Short-stay-cap_PUBLICATION.pdf)
- [Inside Airbnb data assumptions](https://insideairbnb.com/data-assumptions/)
- [AirROI rental-arbitrage unit economics](https://www.airroi.com/blog/airbnb-arbitrage-unit-economics-viral-2026)
- [Houst Australia rental-arbitrage guide](https://www.houst.com/blog/airbnb-arbitrage-australia)

Commercial sources are used only to motivate sensitivity scenarios. They are not treated as local causal evidence or as proof that a particular percentile is profitable in Melbourne.
