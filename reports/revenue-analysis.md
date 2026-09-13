# Review activity and the limits of modelled revenue

[Script 04](../scripts/04_revenue_analysis.R) provides supporting diagnostics for the decision to use recorded review activity as the primary outcome. Its broader priced sample differs from the 8,967-listing residential cohort used in the main classification analysis.

## Reconstruction of the supplied estimates

The saved occupancy and revenue estimates closely follow:

```text
modelled nights = min(reviews_ltm × 2 × max(minimum_nights, 3), 255)
modelled revenue = price × modelled nights, rounded to whole dollars
```

The occupancy reconstruction matches **all 25,719 comparable listings** with the required inputs. For **all 19,175 comparable revenue records**, the absolute difference from price multiplied by supplied modelled nights is no more than AUD0.50, apart from floating-point tolerance. These checks apply to the processed files; they do not substitute for checking the unavailable original CSVs.

The formula contains assumptions about review frequency, stay duration and a ceiling on nights. Regressing modelled revenue on the same components would reproduce that construction rather than validate realised income. Relative revenue ranks also inherit these assumptions and are not the current decision criterion.

## Price selection and review activity

The broad price filter retains 18,927 listings and excludes 6,801. Zero recent reviews occur in **23.7%** of retained listings, **82.0%** of excluded listings and **39.1%** of the full snapshot. Price availability and the filter are therefore associated with the outcome. All priced-sample results are conditional on that selection; absence of reviews does not establish absence of bookings.

The [sample comparison](tables/revenue_sample_censoring.csv) and [variance decomposition](tables/revenue_variance_decomposition.csv) document these diagnostics. The latter separates price, the stay multiplier, review activity and covariance within the constructed log-revenue identity. It is arithmetic, not a causal attribution.

## Supporting association models

Script 04 estimates a logistic model for any recent review and an OLS model of log review count among positive-count listings, with host-clustered standard errors. The latter uses **12,651 observations and 6,252 host clusters**, with in-sample adjusted R² approximately **0.403**. This fit statistic is not held-out predictive performance. Coefficients are provided in the [extensive-margin](tables/revenue_extensive_margin.csv) and [positive-count](tables/revenue_intensive_margin.csv) tables.

The history variable is elapsed time since first review, calculated relative to the latest saved review date, **28 June 2026**. It is named `review_history_years`; it does not measure listing launch or continuous exposure. History plots use recorded trailing-year counts without annualising them by assumed operating months.

Current price, minimum stay, ratings and host status may reflect the same activity period as the response. Their associations do not establish the effect of changing a price, earning a badge or adding capacity. The primary predictive workflow instead reports a property-only model and separately labelled operating-control sensitivity; see [methodology](methodology.md).

No rent, platform-fee, cleaning, utility or furnishing cost data are available for an observed profit calculation. The project therefore reports review activity rather than a revenue-to-rent or ROI recommendation.
