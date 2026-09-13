"""Reproduce the review-activity scope audit and exploratory host-grouped validation.

Run from any directory: python scripts/rq_scope_feasibility.py
Public outputs contain aggregate results only. Listing-level predictions and the
host-fold manifest are written to the ignored data/processed directory.
"""
from __future__ import annotations

from collections import Counter
from decimal import Decimal, InvalidOperation
import hashlib
import json
from pathlib import Path
import platform
import re
import shutil
import subprocess
import tempfile

import numpy as np
import pandas as pd
import scipy
import sklearn
from sklearn.compose import ColumnTransformer
from sklearn.ensemble import RandomForestClassifier
from sklearn.impute import SimpleImputer
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import (
    average_precision_score, brier_score_loss, confusion_matrix, log_loss,
    roc_auc_score,
)
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import OneHotEncoder, StandardScaler

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "reports" / "tables"
PRIVATE_OUTPUT = ROOT / "data" / "processed"
SEED = 30005
N_FOLDS = 5
REVIEW_TARGET = 22
ESTABLISHED_CUTOFF = pd.Timestamp("2025-06-01")
BOOTSTRAP_REPLICATES = 500
CELL_KEYS = ["neighbourhood_cleansed", "configuration"]
NUMERIC_FEATURES = ["accommodates", "bathrooms_num", "n_amenities"]
PROPERTY_MAP = {
    "Entire rental unit": "Apartment/unit",
    "Entire condo": "Apartment/unit",
    "Entire home": "House/townhouse",
    "Entire townhouse": "House/townhouse",
}


def file_sha256(path):
    digest = hashlib.sha256()
    with Path(path).open("rb") as stream:
        for chunk in iter(lambda: stream.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def canonical_id(value):
    """Normalise text identifiers without a floating-point conversion.

    A scientific-notation value is preserved at the precision supplied. This
    cannot recover digits already rounded in an upstream source.
    """
    if pd.isna(value) or not str(value).strip():
        return pd.NA
    text = str(value).strip()
    if re.fullmatch(r"[0-9]+", text):
        return str(int(text))
    try:
        number = Decimal(text)
        if number.is_finite() and number == number.to_integral_value() and number >= 0:
            return format(number, "f").split(".")[0]
    except InvalidOperation:
        pass
    raise ValueError(f"Invalid identifier format: {text!r}")


def parse_bathrooms(values):
    text = values.astype("string")
    parsed = pd.to_numeric(text.str.extract(r"([0-9]+(?:\.[0-9]+)?)", expand=False), errors="coerce")
    return parsed.mask(text.str.contains("half", case=False, na=False), 0.5)


def parse_amenities(value):
    if pd.isna(value) or not str(value).strip():
        return np.nan
    try:
        items = json.loads(value)
    except (TypeError, json.JSONDecodeError):
        return np.nan
    return len(items) if isinstance(items, list) else np.nan


def read_source():
    raw_path = ROOT / "data/raw/listings_airbnb.csv"
    cached_path = ROOT / "data/processed/listings_clean.rds"
    if raw_path.is_file():
        frame = pd.read_csv(raw_path, dtype={"id": "string", "host_id": "string"}, low_memory=False)
        frame["price_num"] = pd.to_numeric(
            frame["price"].astype("string").str.replace(r"[$,]", "", regex=True), errors="coerce"
        )
        frame["bathrooms_num"] = parse_bathrooms(frame["bathrooms_text"])
        frame["n_amenities"] = frame["amenities"].map(parse_amenities)
        provenance = {"source_kind": "raw_listings", "source_file": "data/raw/listings_airbnb.csv"}
        source_path = raw_path
    elif cached_path.is_file():
        executable = shutil.which("Rscript")
        if executable is None:
            raise RuntimeError("Rscript is required to read the available listings_clean.rds snapshot.")
        with tempfile.TemporaryDirectory(prefix="cmce30005-review-") as directory:
            exported = Path(directory) / "listings.csv"
            expression = (
                'args <- commandArgs(trailingOnly=TRUE); d <- readRDS(args[1]); '
                'd$id <- as.character(d$id); d$host_id <- as.character(d$host_id); '
                'write.csv(as.data.frame(d), args[2], row.names=FALSE, na="")'
            )
            subprocess.run([executable, "-e", expression, str(cached_path), str(exported)], check=True)
            frame = pd.read_csv(exported, dtype={"id": "string", "host_id": "string"}, low_memory=False)
        provenance = {
            "source_kind": "processed_snapshot",
            "source_file": "data/processed/listings_clean.rds",
            "limitation": (
                "Raw CSV files are unavailable. Cached cleaning features are reused; raw parsing, "
                "original identifier precision and review-date reconstruction have not been revalidated."
            ),
        }
        source_path = cached_path
    else:
        raise FileNotFoundError("Provide raw listings_airbnb.csv or the existing listings_clean.rds snapshot.")
    provenance["source_sha256"] = file_sha256(source_path)
    provenance["scientific_notation_listing_ids"] = int(frame["id"].str.contains(r"[eE]", na=False).sum())
    for column in ["id", "host_id"]:
        frame[column] = frame[column].map(canonical_id).astype("string")
        if frame[column].isna().any():
            raise ValueError(f"Missing {column}; resolve identifiers before modelling.")
    if frame["id"].duplicated().any():
        raise ValueError("Listing identifiers are duplicated after text normalisation.")
    required = ["price_num", "bedrooms", "accommodates", "bathrooms_num", "n_amenities", "minimum_nights", "number_of_reviews_ltm"]
    for column in required:
        frame[column] = pd.to_numeric(frame[column], errors="coerce")
    reviews = frame["number_of_reviews_ltm"]
    if reviews.isna().any() or (reviews < 0).any() or (reviews % 1 != 0).any():
        raise ValueError("The review-count outcome must contain non-missing, non-negative integers.")
    frame["first_review_date"] = pd.to_datetime(frame["first_review"], errors="coerce").dt.normalize()
    frame["dwelling_class"] = frame["property_type"].map(PROPERTY_MAP)
    return frame, provenance


def make_scope(frame, *, price_filter=True, established=False):
    mask = frame["room_type"].eq("Entire home/apt") & frame["bedrooms"].isin([1, 2, 3]) & frame["dwelling_class"].notna()
    if price_filter:
        mask &= frame["price_num"].between(30, 1500)
    if established:
        mask &= frame["first_review_date"].le(ESTABLISHED_CUTOFF)
    base = frame.loc[mask].copy()
    base["bedrooms"] = base["bedrooms"].astype(int)
    base["configuration"] = base["bedrooms"].astype(str) + "BR " + base["dwelling_class"]
    counts = base.groupby(CELL_KEYS).size().rename("n").reset_index()
    cells = counts.loc[counts["n"] >= 50].copy()
    sample = base.merge(cells[CELL_KEYS], on=CELL_KEYS, how="inner", validate="many_to_one")
    sample["review_target_met"] = sample["number_of_reviews_ltm"].ge(REVIEW_TARGET).astype(int)
    if sample.empty:
        raise ValueError("No eligible segments remain after the declared filters.")
    return sample, cells, len(base)


def validate_raw_reviews(frame, sample, provenance):
    path = ROOT / "data/raw/reviews_airbnb.csv"
    if provenance["source_kind"] != "raw_listings" or not path.is_file() or "last_scraped" not in frame:
        return {"status": "blocked", "reason": "Raw listings, review dates and per-listing scrape dates are required; they are not all available."}
    dates = pd.to_datetime(frame["last_scraped"], errors="coerce").dt.normalize()
    snapshot_by_id = pd.Series(dates.to_numpy(), index=frame["id"])
    if snapshot_by_id.loc[sample["id"]].isna().any():
        return {"status": "blocked", "reason": "At least one eligible listing has no valid last_scraped date."}
    ids = set(sample["id"])
    cutoff_by_id = snapshot_by_id.map(lambda date: date - pd.DateOffset(years=1) if pd.notna(date) else pd.NaT)
    counts = Counter()
    invalid_dates = 0
    for chunk in pd.read_csv(path, usecols=["listing_id", "date"], dtype={"listing_id": "string"}, chunksize=250_000):
        chunk["listing_id"] = chunk["listing_id"].map(canonical_id)
        chunk = chunk.loc[chunk["listing_id"].isin(ids)].copy()
        review_dates = pd.to_datetime(chunk["date"], errors="coerce").dt.normalize()
        invalid_dates += int(review_dates.isna().sum())
        valid = review_dates.gt(chunk["listing_id"].map(cutoff_by_id)) & review_dates.le(chunk["listing_id"].map(snapshot_by_id))
        counts.update(chunk.loc[valid, "listing_id"].value_counts().to_dict())
    check = sample[["id", "number_of_reviews_ltm"]].copy()
    check["rebuilt_reviews"] = check["id"].map(counts).fillna(0).astype(int)
    check["difference"] = check["rebuilt_reviews"] - check["number_of_reviews_ltm"]
    check["label_changed"] = check["rebuilt_reviews"].ge(REVIEW_TARGET) != check["number_of_reviews_ltm"].ge(REVIEW_TARGET)
    check.loc[check["difference"].ne(0)].to_csv(PRIVATE_OUTPUT / "rq_review_reconstruction_mismatches.csv", index=False)
    return {
        "status": "completed", "review_file_sha256": file_sha256(path),
        "window": "(each listing last_scraped minus one calendar year, last_scraped]",
        "exact_match_share": float(check["difference"].eq(0).mean()),
        "mismatched_listings": int(check["difference"].ne(0).sum()),
        "max_absolute_difference": int(check["difference"].abs().max()),
        "target_label_changes": int(check["label_changed"].sum()), "invalid_review_dates": invalid_dates,
        "qualification": "Matching cannot recover digits rounded in the supplied identifier fields.",
    }


def build_model(name, controls):
    numeric = NUMERIC_FEATURES + (["log_price", "log_minimum_nights"] if controls else [])
    numeric_pipeline = Pipeline([("imputer", SimpleImputer(strategy="median", keep_empty_features=True)), ("scaler", StandardScaler())])
    categorical_pipeline = Pipeline([
        ("imputer", SimpleImputer(strategy="most_frequent", keep_empty_features=True)),
        ("encoder", OneHotEncoder(handle_unknown="ignore", sparse_output=False)),
    ])
    preprocessor = ColumnTransformer([("numeric", numeric_pipeline, numeric), ("categorical", categorical_pipeline, CELL_KEYS)])
    if name == "logistic":
        estimator = LogisticRegression(C=1.0, solver="lbfgs", max_iter=2000, random_state=SEED)
    elif name == "random_forest":
        estimator = RandomForestClassifier(n_estimators=250, min_samples_leaf=10, max_features="sqrt", random_state=SEED, n_jobs=2)
    else:
        raise ValueError(name)
    return Pipeline([("preprocess", preprocessor), ("model", estimator)]), numeric + CELL_KEYS


def precision_top_quarter(y, probability):
    """Select exactly ceil(n/4) in expectation, sharing the boundary weight across ties."""
    k = int(np.ceil(len(y) / 4))
    boundary = np.partition(probability, len(y) - k)[len(y) - k]
    above, tied = probability > boundary, probability == boundary
    weight = (k - int(above.sum())) / int(tied.sum())
    return float((y[above].sum() + weight * y[tied].sum()) / k)


def score_predictions(y, probability):
    prevalence = float(y.mean())
    return {
        "roc_auc": float(roc_auc_score(y, probability)),
        "average_precision": float(average_precision_score(y, probability)),
        "brier_score": float(brier_score_loss(y, probability)),
        "log_loss": float(log_loss(y, probability, labels=[0, 1])),
        "precision_top_quarter": precision_top_quarter(y, probability),
        "confusion_matrix_at_0_5": confusion_matrix(y, probability >= 0.5, labels=[0, 1]).tolist(),
        "descriptive_constant_probability_baseline": {
            "roc_auc": 0.5, "average_precision": prevalence, "precision_top_quarter": prevalence,
            "brier_score": float(prevalence * (1 - prevalence)),
            "log_loss": float(log_loss(y, np.full(len(y), prevalence), labels=[0, 1])),
            "note": "Uses the evaluated sample prevalence as a descriptive no-skill reference.",
        },
    }


def calibration_table(y, probability):
    data = pd.DataFrame({"observed": y, "predicted": probability})
    data["probability_bin"] = pd.cut(data["predicted"], np.linspace(0, 1, 11), include_lowest=True)
    return data.groupby("probability_bin", observed=True).agg(
        n=("observed", "size"), mean_predicted_probability=("predicted", "mean"), observed_review_target_share=("observed", "mean")
    ).reset_index()


def segment_ranking(sample, probability):
    rows = []
    rng = np.random.default_rng(SEED)
    scored = sample.assign(oof_probability=probability)
    for key, group in scored.groupby(CELL_KEYS, sort=True):
        hosts = group.groupby("host_id").agg(n=("id", "size"), probability_sum=("oof_probability", "sum"))
        values = hosts.to_numpy()
        choices = rng.integers(0, len(hosts), size=(BOOTSTRAP_REPLICATES, len(hosts)))
        draws = values[choices]
        conditional_means = draws[:, :, 1].sum(axis=1) / draws[:, :, 0].sum(axis=1)
        lower, upper = np.quantile(conditional_means, [0.025, 0.975])
        rows.append({
            CELL_KEYS[0]: key[0], CELL_KEYS[1]: key[1], "n": len(group), "n_hosts": len(hosts),
            "positive_n": int(group["review_target_met"].sum()),
            "observed_review_target_share": float(group["review_target_met"].mean()),
            "mean_oof_probability": float(group["oof_probability"].mean()),
            "median_oof_probability": float(group["oof_probability"].median()),
            "conditional_bootstrap_lower_95": float(lower), "conditional_bootstrap_upper_95": float(upper),
            "fewer_than_10_positive_listings": bool(group["review_target_met"].sum() < 10),
            "fewer_than_10_hosts": bool(len(hosts) < 10),
        })
    ranking = pd.DataFrame(rows).sort_values("mean_oof_probability", ascending=False)
    ranking.insert(0, "rank", np.arange(1, len(ranking) + 1))
    return ranking


def evaluate(sample, host_folds, *, scenario, model_name, controls=False):
    data = sample.copy()
    if controls:
        data["log_price"] = np.log(data["price_num"].where(data["price_num"] > 0))
        data["log_minimum_nights"] = np.log1p(data["minimum_nights"].where(data["minimum_nights"] >= 0))
    data["fold"] = data["host_id"].map(host_folds).astype(int)
    y = data["review_target_met"].to_numpy()
    probability = np.full(len(data), np.nan)
    fold_metrics = []
    baseline_probability = np.full(len(data), np.nan)
    for fold in range(N_FOLDS):
        train, test = data["fold"].ne(fold), data["fold"].eq(fold)
        assert set(data.loc[train, "host_id"]).isdisjoint(data.loc[test, "host_id"])
        if y[train].sum() in (0, int(train.sum())) or y[test].sum() in (0, int(test.sum())):
            raise ValueError(f"{scenario}: fold {fold} lacks one outcome class.")
        pipeline, columns = build_model(model_name, controls)
        pipeline.fit(data.loc[train, columns], y[train])
        probability[test] = pipeline.predict_proba(data.loc[test, columns])[:, 1]
        baseline_probability[test] = y[train].mean()
        fold_metrics.append({
            "fold": fold, "n_train": int(train.sum()), "n_validation": int(test.sum()),
            "n_validation_hosts": int(data.loc[test, "host_id"].nunique()),
            "validation_positive_share": float(y[test].mean()),
            "roc_auc": float(roc_auc_score(y[test], probability[test])),
        })
    assert np.isfinite(probability).all()
    metrics = score_predictions(y, probability)
    metrics.update({
        "scenario": scenario, "model": model_name, "n": len(data), "n_hosts": data["host_id"].nunique(),
        "n_segments": data.groupby(CELL_KEYS).ngroups,
        "descriptive_review_p75_in_this_scope": float(data["number_of_reviews_ltm"].quantile(0.75)),
        "fixed_review_target": REVIEW_TARGET,
        "predictors": columns, "folds": fold_metrics,
        "training_fold_prevalence_baseline": {
            "brier_score": float(brier_score_loss(y, baseline_probability)),
            "log_loss": float(log_loss(y, baseline_probability, labels=[0, 1])),
        },
    })
    private = data[["id", "host_id", "fold", "number_of_reviews_ltm", "review_target_met"]].copy()
    private["oof_probability"] = probability
    private.to_csv(PRIVATE_OUTPUT / f"rq_oof_{scenario}_{model_name}.csv", index=False)
    ranking = segment_ranking(data, probability).assign(scenario=scenario, model=model_name)
    calibration = calibration_table(y, probability).assign(scenario=scenario, model=model_name)
    print(f"{scenario} / {model_name}: n={len(data)}, AUC={metrics['roc_auc']:.6f}, AP={metrics['average_precision']:.6f}, Brier={metrics['brier_score']:.6f}", flush=True)
    return metrics, ranking, calibration


def main():
    OUTPUT.mkdir(parents=True, exist_ok=True)
    PRIVATE_OUTPUT.mkdir(parents=True, exist_ok=True)
    frame, provenance = read_source()
    sample, cells, n_before_cells = make_scope(frame)
    established, _, _ = make_scope(frame, established=True)
    no_price_filter, _, _ = make_scope(frame, price_filter=False)
    # One reproducible host assignment is shared by models and scope sensitivities.
    all_hosts = np.array(sorted(frame["host_id"].unique()), dtype=object)
    np.random.default_rng(SEED).shuffle(all_hosts)
    host_folds = {host: index % N_FOLDS for index, host in enumerate(all_hosts)}
    pd.DataFrame({"host_id": list(host_folds), "fold": list(host_folds.values())}).to_csv(PRIVATE_OUTPUT / "rq_host_fold_manifest.csv", index=False)
    raw_validation = validate_raw_reviews(frame, sample, provenance)
    provenance["raw_validation"] = raw_validation["status"] == "completed"
    provenance["raw_review_validation"] = raw_validation
    summary = {
        "raw_listings_or_cached_snapshot_rows": len(frame), "narrow_scope_before_cell_filter": n_before_cells,
        "eligible_cells_ge_50": len(cells), "eligible_listings": len(sample), "eligible_hosts": sample["host_id"].nunique(),
        "descriptive_p75_reviews_ltm": float(sample["number_of_reviews_ltm"].quantile(0.75)),
        "fixed_review_target": REVIEW_TARGET, "positive_n": int(sample["review_target_met"].sum()),
        "positive_share_with_ties": float(sample["review_target_met"].mean()),
        "zero_recent_review_listings": int(sample["number_of_reviews_ltm"].eq(0).sum()),
        "threshold_definition": "A fixed 22-review operational target, motivated by the P75 observed during scope exploration. Cross-validation does not independently validate selection of this threshold.",
        "validation_definition": "Exploratory five-fold host-grouped cross-validation; no independent final test set or hyperparameter search.",
        "scope_support_definition": "The >=50-listing rule uses all snapshot covariate counts to define the segments reported. It does not use outcome labels, but evaluation is conditional on this full-snapshot scope rather than discovery of eligible segments in unseen markets.",
        "ranking_intervals": f"95% percentile intervals from {BOOTSTRAP_REPLICATES} within-segment host-cluster resamples, conditional on existing OOF probabilities; models are not refitted and intervals exclude model-fitting and model-selection uncertainty.",
        "established_sensitivity": f"First review on or before {ESTABLISHED_CUTOFF.date()}, then recompute cell counts >=50. This is a historical-review criterion, not listing launch date; the 22-review event remains fixed.",
        "main_model_interpretation": "Physical listing attributes associated with review activity in the preceding year, evaluated on held-out hosts. These are not verified pre-opening measurements or forecasts of a new operator's next year.",
        "operating_controls_sensitivity": "Current quoted price and minimum stay are contemporaneous operating characteristics, included only as a separately labelled sensitivity.",
        "missingness_main_numeric": {column: int(sample[column].isna().sum()) for column in NUMERIC_FEATURES},
        "provenance": provenance, "seed": SEED,
        "versions": {"python": platform.python_version(), "numpy": np.__version__, "pandas": pd.__version__, "scipy": scipy.__version__, "scikit_learn": sklearn.__version__},
        "script_sha256": file_sha256(__file__),
        "model_settings": {"logistic": {"C": 1.0, "max_iter": 2000}, "random_forest": {"n_estimators": 250, "min_samples_leaf": 10, "max_features": "sqrt", "n_jobs": 2}},
    }
    observations = sample.groupby(CELL_KEYS).agg(
        n=("id", "size"), n_hosts=("host_id", "nunique"), median_reviews_ltm=("number_of_reviews_ltm", "median"),
        p75_reviews_ltm=("number_of_reviews_ltm", lambda values: values.quantile(.75)),
        positive_n=("review_target_met", "sum"), observed_review_target_share=("review_target_met", "mean"),
        median_quoted_price=("price_num", "median"),
    ).reset_index().sort_values("observed_review_target_share", ascending=False)
    observations.to_csv(OUTPUT / "rq_observed_segment_outcomes.csv", index=False)
    cells.sort_values(CELL_KEYS).to_csv(OUTPUT / "rq_eligible_lga_configurations.csv", index=False)
    frame.loc[frame["room_type"].eq("Entire home/apt") & frame["bedrooms"].isin([1, 2, 3]), "property_type"].value_counts().rename_axis("property_type").reset_index(name="n").to_csv(OUTPUT / "rq_property_type_counts.csv", index=False)
    all_metrics, rankings, calibrations = [], [], []
    scenarios = [("property_only", sample, False), ("operating_controls", sample, True), ("established_history", established, False), ("no_price_filter", no_price_filter, False)]
    for scenario, data, controls in scenarios:
        for model_name in ["logistic", "random_forest"]:
            metrics, ranking, calibration = evaluate(data, host_folds, scenario=scenario, model_name=model_name, controls=controls)
            all_metrics.append(metrics)
            rankings.append(ranking)
            calibrations.append(calibration)
    pd.concat(rankings, ignore_index=True).to_csv(OUTPUT / "rq_oof_segment_ranking.csv", index=False)
    pd.concat(calibrations, ignore_index=True).to_csv(OUTPUT / "rq_calibration.csv", index=False)
    (OUTPUT / "rq_scope_summary.json").write_text(json.dumps(summary, indent=2, allow_nan=False) + "\n", encoding="utf-8")
    (OUTPUT / "rq_model_metrics.json").write_text(json.dumps(all_metrics, indent=2, allow_nan=False) + "\n", encoding="utf-8")
    print("Aggregate results written to reports/tables; identifiers and OOF rows remain in data/processed.", flush=True)


if __name__ == "__main__":
    main()
