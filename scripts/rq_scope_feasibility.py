from pathlib import Path
import json

import numpy as np
import pandas as pd


ROOT = Path(__file__).resolve().parents[1]
LISTINGS = ROOT / "data" / "raw" / "listings_airbnb.csv"
REVIEWS = ROOT / "data" / "raw" / "reviews_airbnb.csv"
OUTPUT = ROOT / "reports" / "tables"
OUTPUT.mkdir(parents=True, exist_ok=True)


def parse_price(s):
    return pd.to_numeric(s.astype("string").str.replace(r"[$,]", "", regex=True), errors="coerce")


def parse_bathrooms(s):
    return pd.to_numeric(s.astype("string").str.extract(r"([0-9]+(?:\.[0-9]+)?)", expand=False), errors="coerce")


cols = [
    "id", "host_id", "last_scraped", "neighbourhood_cleansed", "property_type", "room_type",
    "accommodates", "bathrooms_text", "bedrooms", "beds", "amenities", "price",
    "minimum_nights", "maximum_nights", "availability_365", "number_of_reviews_ltm", "first_review",
    "review_scores_rating", "host_is_superhost", "calculated_host_listings_count",
]
df = pd.read_csv(LISTINGS, usecols=cols, low_memory=False)
df["price_num"] = parse_price(df["price"])
df["bathrooms_num"] = parse_bathrooms(df["bathrooms_text"])
df["n_amenities"] = df["amenities"].fillna("[]").map(lambda x: 0 if x == "[]" else x.count(",") + 1)

apartment_types = {
    "Entire rental unit", "Entire condo",
}
house_types = {
    "Entire home", "Entire townhouse",
}
df["dwelling_class"] = np.select(
    [df["property_type"].isin(apartment_types), df["property_type"].isin(house_types)],
    ["Apartment/unit", "House/townhouse"],
    default="Other",
)

base = df.loc[
    df["room_type"].eq("Entire home/apt")
    & df["bedrooms"].isin([1, 2, 3])
    & df["dwelling_class"].isin(["Apartment/unit", "House/townhouse"])
    & df["price_num"].between(30, 1500)
].copy()
base["bedrooms"] = base["bedrooms"].astype(int)
base["configuration"] = base["bedrooms"].astype(str) + "BR " + base["dwelling_class"]

cell_counts = base.groupby(["neighbourhood_cleansed", "configuration"]).size().rename("n").reset_index()
eligible_cells = cell_counts.loc[cell_counts["n"] >= 50].copy()
eligible = base.merge(
    eligible_cells[["neighbourhood_cleansed", "configuration"]],
    on=["neighbourhood_cleansed", "configuration"],
    how="inner",
)

q75 = float(eligible["number_of_reviews_ltm"].quantile(0.75))
eligible["top_quartile_demand"] = eligible["number_of_reviews_ltm"].ge(q75).astype(int)
eligible["first_review_date"] = pd.to_datetime(eligible["first_review"], errors="coerce")

segment = eligible.groupby(["neighbourhood_cleansed", "configuration"]).agg(
    n=("id", "size"),
    hosts=("host_id", "nunique"),
    median_reviews_ltm=("number_of_reviews_ltm", "median"),
    p75_reviews_ltm=("number_of_reviews_ltm", lambda x: x.quantile(.75)),
    success_n=("top_quartile_demand", "sum"),
    success_rate=("top_quartile_demand", "mean"),
    median_price=("price_num", "median"),
).reset_index().sort_values(["success_rate", "n"], ascending=[False, False])

top_types = (
    df.loc[df["room_type"].eq("Entire home/apt") & df["bedrooms"].isin([1, 2, 3]), "property_type"]
    .value_counts().rename_axis("property_type").reset_index(name="n")
)

miss_cols = [
    "price_num", "bedrooms", "accommodates", "bathrooms_num", "n_amenities", "minimum_nights",
    "availability_365", "number_of_reviews_ltm", "review_scores_rating", "host_is_superhost",
    "calculated_host_listings_count",
]
missing = {c: {"n": int(eligible[c].isna().sum()), "share": float(eligible[c].isna().mean())} for c in miss_cols}

# Reconstruct trailing-year review counts from the supplied review file to verify the target.
cutoff = pd.Timestamp("2025-06-16")
snapshot = pd.Timestamp("2026-06-16")
ids = set(eligible["id"].astype("int64"))
review_counts = {}
for chunk in pd.read_csv(REVIEWS, usecols=["listing_id", "date"], chunksize=750_000):
    chunk = chunk.loc[chunk["listing_id"].isin(ids)].copy()
    chunk["date"] = pd.to_datetime(chunk["date"], errors="coerce")
    chunk = chunk.loc[chunk["date"].gt(cutoff) & chunk["date"].le(snapshot)]
    counts = chunk.groupby("listing_id").size()
    for k, v in counts.items():
        review_counts[int(k)] = review_counts.get(int(k), 0) + int(v)

eligible["reviews_rebuilt_ltm"] = eligible["id"].map(review_counts).fillna(0).astype(int)
target_match = eligible["reviews_rebuilt_ltm"].eq(eligible["number_of_reviews_ltm"].fillna(-1))

summary = {
    "raw_listings": int(len(df)),
    "narrow_scope_before_cell_filter": int(len(base)),
    "eligible_cells_ge_50": int(len(eligible_cells)),
    "eligible_listings": int(len(eligible)),
    "eligible_hosts": int(eligible["host_id"].nunique()),
    "global_q75_reviews_ltm": q75,
    "positive_n": int(eligible["top_quartile_demand"].sum()),
    "positive_share_with_ties": float(eligible["top_quartile_demand"].mean()),
    "cells_with_at_least_10_successes": int((segment["success_n"] >= 10).sum()),
    "cells_with_fewer_than_10_successes": int((segment["success_n"] < 10).sum()),
    "largest_host_listing_share": float(eligible.groupby("host_id").size().max() / len(eligible)),
    "multi_listing_host_listing_share": float(eligible["calculated_host_listings_count"].gt(1).mean()),
    "rebuilt_target_exact_match_share": float(target_match.mean()),
    "rebuilt_target_max_abs_difference": int((eligible["reviews_rebuilt_ltm"] - eligible["number_of_reviews_ltm"]).abs().max()),
    "first_review_missing_share": float(eligible["first_review_date"].isna().mean()),
    "no_recent_review_share": float(eligible["number_of_reviews_ltm"].eq(0).mean()),
    "active_with_first_review_under_12m_share": float(
        (
            eligible["number_of_reviews_ltm"].gt(0)
            & eligible["first_review_date"].gt(cutoff)
        ).sum()
        / eligible["number_of_reviews_ltm"].gt(0).sum()
    ),
    "missingness": missing,
}

print("SUMMARY")
print(json.dumps(summary, indent=2))
print("\nPROPERTY TYPES IN ENTIRE-HOME 1-3BR UNIVERSE")
print(top_types.head(20).to_string(index=False))
print("\nELIGIBLE CELLS")
print(eligible_cells.sort_values(["configuration", "n"], ascending=[True, False]).to_string(index=False))
print("\nSEGMENT OUTCOME CHECK")
print(segment.to_string(index=False, formatters={"success_rate": "{:.1%}".format, "median_price": "{:.0f}".format}))

# A small proof-of-feasibility model. It deliberately excludes reviews, ratings,
# Superhost status and availability so that inputs are observable or selectable
# before a new listing begins operating. The implementation is dependency-light
# ridge logistic regression with five host-grouped folds.
model_df = eligible.copy()
model_df["log_price"] = np.log(model_df["price_num"])
model_df["log_minimum_nights"] = np.log1p(model_df["minimum_nights"])
num_features = ["log_price", "accommodates", "bathrooms_num", "n_amenities", "log_minimum_nights"]
for c in num_features:
    model_df[c] = model_df[c].fillna(model_df[c].median())
cats = pd.get_dummies(
    model_df[["neighbourhood_cleansed", "configuration"]],
    drop_first=True,
    dtype=float,
)
X_num = model_df[num_features].astype(float).to_numpy()
X_cat = cats.to_numpy()
y = model_df["top_quartile_demand"].to_numpy(dtype=float)

rng = np.random.default_rng(30005)
host_ids = model_df["host_id"].drop_duplicates().to_numpy().copy()
rng.shuffle(host_ids)
host_fold = {host: i % 5 for i, host in enumerate(host_ids)}
folds = model_df["host_id"].map(host_fold).to_numpy()
prob = np.zeros(len(model_df))

def sigmoid(v):
    v = np.clip(v, -30, 30)
    return 1.0 / (1.0 + np.exp(-v))

def fit_ridge_logit(X, target, ridge=1.0, max_iter=60):
    beta = np.zeros(X.shape[1])
    # Unweighted likelihood preserves probability calibration. Class weighting
    # can improve a chosen classification threshold but distorts raw probabilities.
    class_weight = np.ones_like(target)
    penalty = np.eye(X.shape[1]) * ridge
    penalty[0, 0] = 0
    for _ in range(max_iter):
        p = sigmoid(X @ beta)
        w = np.clip(p * (1 - p) * class_weight, 1e-6, None)
        z = X @ beta + (target - p) / np.clip(p * (1 - p), 1e-6, None)
        lhs = X.T @ (w[:, None] * X) + penalty
        rhs = X.T @ (w * z)
        updated = np.linalg.solve(lhs, rhs)
        if np.max(np.abs(updated - beta)) < 1e-7:
            beta = updated
            break
        beta = updated
    return beta

for fold in range(5):
    train = folds != fold
    test = ~train
    means = X_num[train].mean(axis=0)
    sds = X_num[train].std(axis=0)
    sds[sds == 0] = 1
    train_x = np.column_stack([np.ones(train.sum()), (X_num[train] - means) / sds, X_cat[train]])
    test_x = np.column_stack([np.ones(test.sum()), (X_num[test] - means) / sds, X_cat[test]])
    beta = fit_ridge_logit(train_x, y[train])
    prob[test] = sigmoid(test_x @ beta)

def auc_score(target, score):
    ranks = pd.Series(score).rank(method="average").to_numpy()
    n1 = target.sum()
    n0 = len(target) - n1
    return (ranks[target == 1].sum() - n1 * (n1 + 1) / 2) / (n1 * n0)

def average_precision(target, score):
    order = np.argsort(-score)
    ranked = target[order]
    precision = np.cumsum(ranked) / np.arange(1, len(ranked) + 1)
    return precision[ranked == 1].mean()

pred = (prob >= 0.5).astype(int)
cm = [
    [int(((y == 0) & (pred == 0)).sum()), int(((y == 0) & (pred == 1)).sum())],
    [int(((y == 1) & (pred == 0)).sum()), int(((y == 1) & (pred == 1)).sum())],
]
print("\nHOST-GROUPED OUT-OF-SAMPLE PROOF OF FEASIBILITY")
model_metrics = {
    "roc_auc": float(auc_score(y, prob)),
    "average_precision": float(average_precision(y, prob)),
    "no_skill_average_precision": float(y.mean()),
    "confusion_matrix_at_0_5": cm,
    "fold_positive_shares": [float(y[folds == i].mean()) for i in range(5)],
}
print(json.dumps(model_metrics, indent=2))

model_df["oof_probability_preliminary"] = prob
ranking = model_df.groupby(["neighbourhood_cleansed", "configuration"]).agg(
    n=("id", "size"),
    hosts=("host_id", "nunique"),
    observed_success_rate=("top_quartile_demand", "mean"),
    mean_oof_probability=("oof_probability_preliminary", "mean"),
    median_oof_probability=("oof_probability_preliminary", "median"),
).reset_index().sort_values("mean_oof_probability", ascending=False)

with (OUTPUT / "rq_scope_summary.json").open("w", encoding="utf-8") as f:
    json.dump(summary, f, indent=2)
with (OUTPUT / "rq_preliminary_model_metrics.json").open("w", encoding="utf-8") as f:
    json.dump(model_metrics, f, indent=2)
eligible_cells.sort_values(["configuration", "n"], ascending=[True, False]).to_csv(
    OUTPUT / "rq_eligible_lga_configurations.csv", index=False
)
segment.to_csv(OUTPUT / "rq_observed_segment_outcomes.csv", index=False)
ranking.to_csv(OUTPUT / "rq_preliminary_oof_segment_ranking.csv", index=False)
top_types.to_csv(OUTPUT / "rq_property_type_counts.csv", index=False)

print("\nPRELIMINARY OOF SEGMENT RANKING (TOP 10)")
print(ranking.head(10).to_string(index=False, formatters={
    "observed_success_rate": "{:.1%}".format,
    "mean_oof_probability": "{:.1%}".format,
    "median_oof_probability": "{:.1%}".format,
}))
