# CMCE30005 Business Analytics Challenge Project Plan

## TheNextChapter — Group 2

- **Subject:** CMCE30005 Business Analytics Challenge, Semester 2 2026
- **University:** University of Melbourne
- **Team Members:** EricH896, Qihang-cpu, maksym-xu, Leloc

---

## 1 Business Problem

*Proposed framing — to be confirmed by the team.*

The analytics task required to address our business problem is:
***Which Greater Melbourne LGA and dwelling type offers the highest probability of achieving a 50% first-year cash-on-cash ROI while maintaining non-negative operating cash flow?***


A client intends to list several properties on Airbnb in Melbourne and needs to
decide **where to invest, what property type to operate, and how to price it**.
The stakeholder is the prospective host; the question matters because entry cost
and location are effectively irreversible once committed.

The central question we take to the data is **whether revenue is driven by
pricing or by operations**. Inside Airbnb's revenue field turns out to be a
deterministic construct, so the analysis decomposes that identity rather than
regressing on it: dispersion in review activity accounts for about three times
as much variation in modelled revenue as dispersion in price. Full argument in [reports/revenue-analysis.md](reports/revenue-analysis.md).

Market structure, the hedonic price model and demand seasonality are in
[reports/findings.md](reports/findings.md), with open questions for the team at
the end of that file.

---

## 2 Dataset

- **Dataset name:** Inside Airbnb — Melbourne
- **Source:** [Inside Airbnb](https://insideairbnb.com)
- **Coverage:** Snapshot of 16 June 2026; active listings across Greater
  Melbourne and surrounding local government areas

### 2.1 Data Files
The data used in the project is obtained from Inside Airbnb, the platform collects and publishes Airbnb listing information for 
research and market analysis.
| File | Description | Role in Analysis |
|:---:|:---:|:---:|
| `listings_airbnb.csv` | property characteristics, host information, location, nightly price, availability and review scores| The main dataset |
| `calendar_airbnb.csv` | Daily availability for future dates, 17 Jun 2026 – 30 Jun 2027 | Used to examine market availability and potential demand patterns|
| `reviews_airbnb.csv` | All guest reviews, Aug 2010 – Jun 2026 | Proxy for market demand |


| File | Description | Role in Analysis |
|:---:|:---:|:---:|
| `listings_airbnb.csv` | One row per active listing, ~90 attributes | 68 MB |
| `calendar_airbnb.csv` | Daily availability, 17 Jun 2026 – 30 Jun 2027 | 361 MB |
| `reviews_airbnb.csv` | All guest reviews, Aug 2010 – Jun 2026 | 266 MB |

> Large raw data files are not committed to this repository. Download the three
> files from Inside Airbnb and place them in `data/raw/`. See
> [reports/data-notes.md](reports/data-notes.md) for the join keys and the data quality
> problems worth knowing before you write any new script.

### 2.2 Key variables and features
For this project, variables relevant to the business problem were retained and organised into five groups:
| Dimension | Selected Variables | Business Meaning |
|:---:|:---:|:---:|
| Location | 'neighbourhood_cleansed', 'latitude', 'longitude' | To identify geographic differences in Airbnb prices and market conditions |
| Property | 'property_type', 'room_type', 'accommodates', 'bedrooms', <br> 'beds', 'bathrooms_num', 'n_amenities' | Describes the physical characteristics and capacity of each property |
| Host | 'host_is_superhost', 'host_tenure_years', 'host_identity_verified', <br>'host_identity_verified', 'host_listings_count' | To get host experience and professionalisation  |
| Price and Availability | 'price_num', 'minimum_nights', 'availability_365',<br> 'availability_90' | To get listing  price, booking restrictions and market availability|
| Reviews| 'number_of_reviews', 'reviews_per_month', 'reviews_scores_rating',<br> 'review_scores_location', 'review_scores_value', 'estimated_occupancy_1365d', 'estimated_revenue_1365d' | Provides customer activity, preceived quality and historical listing performance|

### 2.3 Limitations and potential problems 

1. There are missing values in several forms and thirteen variables that are completely empty in the Melbourne snapshot 
were excluded from the analytical dataset, including fields such as 'host_since', 'host_response_rate', 'instant_bookable', 'license' and varaibles 
like 'bathroom'.

2. There are too many variables in the raw data, the calendar dataset contains a substantially larger volume of observations 
than the listings dataset, with approximately 9.4 million rows. This makes it really hard to get a specific project question. 

3. Issues with the format of the original data are also existed, like Nightly price was originally stored as text but not the numeric form.

### 2.4 Assumptions 

1. Listings with valid nightly prices between AUD 30 and AUD 1,500 are assumed to represent the relevant Melbourne short-term Airbnb market.

2. Airbnb price, occupancy and revenue distributions may contain extreme values, so the median provides a more representative measure of a typical listing than the mean.

3. The number of active Airbnb listings in an area is used as an indicator of Airbnb supply and market concentration. A listing with at least one review in the last 12 months 
is assumed to have recent market activity and is classified as an active listing.

4. Monthly review volume is assumed to provide a reasonable proxy for guest demand. However, it does not represent actual bookings because not every guest leaves a review.

5. Review activity from July 2023 to June 2026 provides a sufficiently representative period for identifying recurring seasonal demand patterns.

6. Inside Airbnb's estimated occupancy is assumed to provide a useful indicator for comparing relative listing performance, but it is not treated as directly observed occupancy.

---

## 3 Analytics Task

The analytics task required to address our business problem is:
### Which Greater Melbourne LGA and dwelling type offers the highest probability of achieving a 50% first-year cash-on-cash ROI while maintaining non-negative operating cash flow?

The reason choosing the task:

1. According to the background, The main objective is to develop the most suitable plan for the client rather than simply identifying the location with the highest rental income. 
Since the client manages multiple properties, the profitability of different property types also needs to be considered. So we take dwelling type into the consideration.

2. In addition, cash flow is an important factor, the market suggestions made by us need to benefit our client, especially the funds. Therefore, the analysis should focus 
on striving for the maximum profit without incurring losses. That is the reason why we need to make sure there is a non-negative operating cash flow under 50% first-year cash-on-cash ROI.

## 4 Data Prepration

### 4.1 Change the form of data:<br>
  Several variables that may have been imported in inconsistent formats, so we explicitly converted them to numeric values.
  The converted variables:<br>
  'bedrooms beds' <br>
  'minimum_nights' <br>
  'maximum_nights' <br>
  'review_scores_rating' <br>
  'review_scores_accuracy' <br>
  'review_scores_cleanliness' <br>
  'review_scores_checkin' <br>
  'review_scores_communication' <br>
  'review_scores_location' <br>
  'review_scores_value' <br>
  'reviews_per_month' <br>
  'estimated_revenue_l365d'


### 4.2 Solve the missing values: <br>
- For the file 'listings_airbnb.csv' contains missing information represented in several different forms, we standardised all the different representations of NA as null values
during the import process. 

- For variables with reliable alternative fields, missing or inconsistent values are reconstructed using valid information available from corresponding alternative variables.
For example, missing bathroom information was reconstructed from 'bathrooms_text' rather than statistically imputed. That means we only retained the numerical part of the number of bathrooms.
For "Half-bath", there are no ordinary numbers in the string, we use '0.5' to represent it. 

- For the variables that are completely empty, we just delete all of them. 

- For Amenities, we count the number of separators between amenity items and add one to estimate the total number of amenities. Empty or missing amenity lists are assigned a count of zero.

- For the key variables like 'price', 'revenue', and 'occupancy', we did not conduct statistical filling but only excluded in the correlation analysis. For example, we will only use the
listing that has a price during analysis, the missing price will not be taken into consideration.

- For the predictor with the common part missing, we keep the null value.

### 4.3 The outliers: <br>

- The processing of outliers mainly focuses on the nightly price (price_num). We build a rather reasonable price range for the analysis, we set the minimum price as 30 dollars because normally if the 
cost per night is less than 30 dollars, it is generally considered an incorrect entry when it comes to living expenses in Melbourne. The maximum price is 1500 dollars, there are only a few luxury 
listings will have a nightly price that is over 1500. These listings will significantly increase the price distribution and affect the judgment of the general Airbnb market. So we did not take them in.

- From the perspective of current affairs, we assume the total price distribution is right-skewed, so we use log scale to make the lower and higher price range is more easily to be observed.

### 4.4 Integrated variable：<br>

- Due to there are too many variables in the files, the cleaned dataset retained variables relevant to the intended market and financial analysis. The final listing-level variables cover five main dimensions:<br> 

  Location <br>
  Property <br>
  Host <br>
  Price and Availability <br>
  Reviews

  The variables used are showed in the key variable part above.

- For the calendar data, we compressed an extremely large daily calendar dataset into monthly market indicators suitable for analysis and 90-day availability indicators at the listing level.

  We did not use every variables in the file `calendar_airbnb.csv`, but choose three variables that are important to our analystic question: <br>
  'listing_id', <br>
  'date', <br>
  'available'(t for available, f for unavailable)

- For the variable date, we converted the dates of each day into months to subsequent monthly aggregation and reduces the amount of data at the same time.


- For the review data, we also only use the two variables 'listing_id' and 'date' in the file `reviews_airbnb.csv`. 
We conducted two types of aggregations based on these two variables. The first type of aggregation mainly uses date here to summarize all reviews by month for analyzing demand seasonality.
The second type of aggregation uses listing_id grouping, along with the number of reviews each listing has and the date of the most recent review. 


---

## 5 Running the Analysis

Open `CMCE30005-Group2.Rproj` so the working directory is the project root, then
run the scripts in order:

```r
source("scripts/00_packages.R")          # once, to install and load packages
source("scripts/01_data_cleaning.R")     # ~2 min, writes data/processed/
source("scripts/02_exploratory_analysis.R")
source("scripts/03_price_model.R")
source("scripts/04_revenue_analysis.R")
```

Script 01 additionally requires `data.table` and `stringr`; script 03 requires
`broom`. Charts land in `reports/figures/` and summary tables in
`reports/tables/`, both of which are committed so results can be reviewed
without re-running the pipeline.


### 5.1 Descriptive Analytics
- Nightly price distribution
  * Examine the overall distribution of Airbnb nightly prices.
  * A log scale is used because prices are highly dispersed across listings.

- Supply and performance by LGA
  * Calculate the number of listings in each Local Government Area.
  * Compare median nightly price, median estimated occupancy and median estimated annual revenue across LGAs.

- Price by property characteristics
  * Compare nightly prices across different accommodation capacities and room types.
  * This helps identify how property size and accommodation format are related to pricing.

- Revenue by market segment
  * Group listings by LGA, room type and accommodation capacity.
  * Calculate the number of comparable listings, median price, median revenue and median occupancy for each segment.

### 5.2 Exploratory Data Analysis

- Demand seasonality
  * Monthly review volume from July 2023 to June 2026 is used as a proxy for Airbnb demand.
  * Review activity is used instead of forward calendar availability

- Seasonality index
  * A monthly seasonality index is calculated using average review activity across three years.
  * This identifies relatively strong and weak demand months.

- Price and occupancy relationship
  * Examine the relationship between nightly price and estimated occupancy for active entire-home listings.
  * This helps identify whether higher prices may be associated with lower booking activity.

- Market segmentation
  * Compare different combinations of location, room type and accommodation capacity.
  * Segments with fewer than 30 observations are excluded from the exploratory comparison to reduce the influence of very small groups.

- Superhost comparison
  * Compare Superhost and non-Superhost listings in terms of price, ratings, revenue and occupancy.
  * Active listings are analysed separately to reduce distortion caused by listings with no recent booking activity.

### 5.3 Classification

The outcome can be defined as:
- Successful property
  * First-year cash-on-cash ROI ≥ 50%
  * Operating cash flow remains non-negative throughout the seasonal cycle

- Unsuccessful property
  * The property fails to satisfy one or both of these conditions.


### 5.4 Regression

We used a two-part modelling regressions approach to investigate the factors associated with Airbnb listing activity. Rather than directly modelling estimated revenue, 
the analysis focuses on review activity because the revenue and occupancy variables published by Inside Airbnb are constructed from price, minimum-night requirements and review counts.

- **How we do the regression:**
  * We use the first Logistic Regression to detect whether a listing can generate any recent review activities
  * For the second regression, we choose OLS Regression on log reviews to analyze in the already active listings which factors are related to the strength of the review activity.

- **Model 1: Logistic Regression**

$$
\text{logit}\left[P(Active_i = 1)\right] =
\beta_0
+\beta_1 \log(Price_i)
+\beta_2 RoomType_i
+\beta_3 Accommodates_i
+\beta_4 Bedrooms_i
+\beta_5 Bathrooms_i
+\beta_6 Amenities_i
+\beta_7 Superhost_i
+\beta_8 HostTenure_i
+\beta_9 \log(1 + HostListings_i)
+\beta_{10} MinimumStay_i
+\beta_{11} Availability365_i
+\beta_{12} LGA_i
$$

*Because the outcome is binary, a Logistic Regression model is used.*
The first model examines the probability that a listing records any review activity during the trailing 12 months.

  * **Dependent Variable:**<br>
    | Value | Description |
    |:---|:---|
    | 1 | the listing recorded at least one review during the previous 12 months |
    | 0 | the listing recorded no recent review activity |

  * **Independent Variable:**<br>
    | Category | Variables | Description |
    |:---|:---|:---|
    | Price | log(price) | Represent the nightly price of Airbnb listings. |
    | Property | room_type, accommodates, bedrooms, bathrooms_num, n_amenities | Description of the property assets |
    | Host | superhost, host_tenure_years, log1p(calculated_host_listings_count) | Description of the host |
    | Location | lga | Location of the property in Great Melbourne |
    | Availability | min_nights_grp, availability_365 | Indicates the situation of the listing |


  * **Statistical Treatment:**
    * Standard errors are clustered by host.
    * Listings owned by the same host may therefore not be statistically independent, so we use Host-clustered standard errors to make sure the host is the independent cluster


- **Model 2: OLS Regression on log reviews**<br>
Model 2 only analyzes Airbnb listings that already have recent review activities, it what to detect the question **Among Airbnb listings that are already active, what listing, host, pricing and operating characteristics are associated with higher or lower review activity?**

$$
\log(Reviews_i) =
\beta_0
+\beta_1 \log(Price_i)
+\beta_2 RoomType_i
+\beta_3 Accommodates_i
+\beta_4 Bedrooms_i
+\beta_5 Bathrooms_i
+\beta_6 Amenities_i
+\beta_7 Superhost_i
+\beta_8 HostTenure_i
+\beta_9 \log(ListingAge_i)
+\beta_{10} \log(1+HostListings_i)
+\beta_{11} Rating_i
+\beta_{12} MinimumStay_i
+\beta_{13} Availability365_i
+\beta_{14} LGA_i
+\epsilon_i
$$

  * **Dependent Variable:**
$log(number_of_reviews_ltm)$ <br>
It describes the intensity of review activity of an already active Airbnb listing over the past 12 months.

  * **Independent Variable:**<br>
    | Category | Variables | Description |
    |:---|:---|:---|
    | Price | log(price) | Represent the nightly price of Airbnb listings. |
    | Property | room_type, accommodates, bedrooms, bathrooms_num, n_amenities | Description of the property assets |
    | Host | superhost, host_tenure_years, log1p(calculated_host_listings_count) | Description of the host |
    | Location | lga | Location of the property in Great Melbourne |
    | Availability | min_nights_grp, availability_365 | Indicates the situation of the listing |
    | Reviews | log(listing_age_years), review_scores_rating | Controls for how long the listing has been active on Airbnb and its observed guest rating |

### 5.5 Analysis task and Business Problem

The selected analytics task is appropriate because the business problem requires us to identify which Airbnb property characteristics are associated with stronger market activity and therefore greater revenue potential.
By controlling for pricing, property characteristics, host characteristics, operating settings and location, the models help identify which factors are associated with stronger listing activity. 
This provides useful evidence for comparing property segments and supports the broader rental-arbitrage decision, while recognising that the results describe associations rather than causal effects.

---

## 6 Modeling 

---

## 7 Evaluation

---

## 8 Project Scope

### Repository Structure 

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
│   ├── findings.md          # Market structure, price model, seasonality
│   └── revenue-analysis.md  # Price vs review activity
├── README.md
├── .gitignore
└── CMCE30005-Group2.Rproj
```

---
*Last updated: 6 August 2026*
