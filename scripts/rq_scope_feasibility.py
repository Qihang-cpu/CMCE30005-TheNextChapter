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
CONFIG_PATH = ROOT / "config" / "review_analysis.json"
CONFIG = json.loads(CONFIG_PATH.read_text(encoding="utf-8"))
SEED = int(CONFIG["seed"])
N_FOLDS = 5
ESTABLISHED_CUTOFF = pd.Timestamp(CONFIG["established_first_review_on_or_before"])
MINIMUM_SEGMENT_LISTINGS = int(CONFIG["minimum_segment_listings"])
BOOTSTRAP_REPLICATES = 500
CELL_KEYS = ["neighbourhood_cleansed", "configuration"]
NUMERIC_FEATURES = ["accommodates", "bathrooms_num", "n_amenities"]
PROPERTY_MAP = CONFIG["property_map"]
if CONFIG["benchmark_partition"]["hash_algorithm"] != "sha256":
    raise ValueError("The host partition requires SHA256.")
if not 0 < CONFIG["benchmark_quantile"] < 1:
    raise ValueError("The configured benchmark quantile must lie strictly between zero and one.")


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


def host_role(host_id):
    partition = CONFIG["benchmark_partition"]
    digest = hashlib.sha256((partition["hash_prefix"] + host_id).encode("utf-8")).hexdigest()
    bucket = int(digest[:int(partition["hex_characters"])], 16) % int(partition["modulus"])
    return "benchmark_development" if bucket == int(partition["benchmark_remainder"]) else "analysis"


def eligible_base(frame, *, price_filter=True, established=True):
    """Apply declared eligibility without using recent-review outcome values."""
    mask = frame["room_type"].eq(CONFIG["room_type"]) & frame["bedrooms"].isin(CONFIG["bedrooms"]) & frame["dwelling_class"].notna()
    if price_filter:
        mask &= frame["price_num"].between(CONFIG["minimum_price"], CONFIG["maximum_price"])
    if established:
        mask &= frame["first_review_date"].le(ESTABLISHED_CUTOFF)
    base = frame.loc[mask].copy()
    base["bedrooms"] = base["bedrooms"].astype(int)
    base["configuration"] = base["bedrooms"].astype(str) + "BR " + base["dwelling_class"]
    return base


def make_scope(analysis_frame, *, price_filter=True, established=True):
    if not analysis_frame["host_role"].eq("analysis").all():
        raise ValueError("Benchmark-development hosts must be removed before defining an analysis scope.")
    base = eligible_base(analysis_frame, price_filter=price_filter, established=established)
    counts = base.groupby(CELL_KEYS).size().rename("n").reset_index()
    cells = counts.loc[counts["n"] >= MINIMUM_SEGMENT_LISTINGS].copy()
    sample = base.merge(cells[CELL_KEYS], on=CELL_KEYS, how="inner", validate="many_to_one")
    if sample.empty:
        raise ValueError("No eligible segments remain after the declared filters.")
    if sample.groupby(CELL_KEYS).size().lt(MINIMUM_SEGMENT_LISTINGS).any():
        raise ValueError("An analysis segment is below the configured support requirement.")
    return sample, cells, len(base)


def develop_benchmark(benchmark_frame, analysis_cells):
    """Read only benchmark outcomes to calculate the common review-count event."""
    if not benchmark_frame["host_role"].eq("benchmark_development").all():
        raise ValueError("Threshold development accepts benchmark hosts only.")
    reference = eligible_base(benchmark_frame).merge(
        analysis_cells[CELL_KEYS], on=CELL_KEYS, how="inner", validate="many_to_one"
    )
    if reference.empty:
        raise ValueError("No eligible benchmark-development listings remain in the primary analysis cells.")
    quantile = float(reference["number_of_reviews_ltm"].quantile(CONFIG["benchmark_quantile"], interpolation="linear"))
    return reference, quantile, int(np.ceil(quantile))


def attach_outcome(sample, threshold):
    labelled = sample.copy()
    labelled["review_target_met"] = labelled["number_of_reviews_ltm"].ge(threshold).astype(int)
    return labelled


def validate_raw_reviews(frame, sample, provenance, threshold):
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
    check["label_changed"] = check["rebuilt_reviews"].ge(threshold) != check["number_of_reviews_ltm"].ge(threshold)
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
    bins = calibration_table(y, probability)
    ece = float((bins["n"] * (bins["mean_predicted_probability"] - bins["observed_review_target_share"]).abs()).sum() / len(y))
    high_score = probability >= 0.5
    return {
        "mean_predicted_probability": float(probability.mean()),
        "observed_target_share": prevalence,
        "mean_prediction_minus_observed": float(probability.mean() - prevalence),
        "expected_calibration_error_10_equal_width_bins": ece,
        "calibration_status": "Uncalibrated model scores; bin summaries are exploratory and no post-hoc probability calibration has been fitted.",
        "high_score_at_least_0_5": {
            "n": int(high_score.sum()),
            "observed_target_share": float(y[high_score].mean()) if high_score.any() else None,
            "mean_predicted_probability": float(probability[high_score].mean()) if high_score.any() else None,
        },
        "calibration_limitations": "High-score bins may be sparse; ECE and bin means are sample-dependent summaries, not evidence of reliable probabilities throughout the score range.",
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
    grouped = data.groupby("probability_bin", observed=True).agg(
        n=("observed", "size"), positive_n=("observed", "sum"),
        mean_predicted_probability=("predicted", "mean"), observed_review_target_share=("observed", "mean")
    ).reset_index()
    grouped["absolute_calibration_gap"] = (grouped["mean_predicted_probability"] - grouped["observed_review_target_share"]).abs()
    grouped["fewer_than_50_listings"] = grouped["n"].lt(50)
    grouped["fewer_than_10_positive_listings"] = grouped["positive_n"].lt(10)
    return grouped


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


def evaluate(sample, host_folds, benchmark_hosts, *, threshold, scenario, model_name, controls=False):
    data = sample.copy()
    if set(data["host_id"]) & benchmark_hosts:
        raise ValueError("Benchmark-development hosts overlap the modelling/evaluation sample.")
    if not data["host_role"].eq("analysis").all() or data.groupby(CELL_KEYS).size().lt(MINIMUM_SEGMENT_LISTINGS).any():
        raise ValueError("The modelling scope violates role or minimum-support requirements.")
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
        if not set(data.loc[train, "host_id"]).isdisjoint(data.loc[test, "host_id"]):
            raise ValueError("A host overlaps training and validation within a fold.")
        if set(data.loc[train | test, "host_id"]) & benchmark_hosts:
            raise ValueError("A benchmark host entered cross-validation.")
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
        "common_review_threshold": threshold,
        "predictors": columns, "folds": fold_metrics,
        "training_fold_prevalence_baseline": {
            "brier_score": float(brier_score_loss(y, baseline_probability)),
            "log_loss": float(log_loss(y, baseline_probability, labels=[0, 1])),
        },
    })
    private = data[["id", "host_id", "host_role", "fold", *CELL_KEYS, "number_of_reviews_ltm", "review_target_met"]].copy()
    private["common_review_threshold"] = threshold
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
    frame["host_role"] = frame["host_id"].map(host_role)
    benchmark_frame = frame.loc[frame["host_role"].eq("benchmark_development")].copy()
    analysis_frame = frame.loc[frame["host_role"].eq("analysis")].copy()
    benchmark_hosts = set(benchmark_frame["host_id"])
    if benchmark_hosts & set(analysis_frame["host_id"]):
        raise ValueError("Host roles are not disjoint.")
    # Only eligibility and analysis-host counts define the primary reporting cells.
    sample, cells, n_before_cells = make_scope(analysis_frame)
    reference, benchmark_q75, threshold = develop_benchmark(benchmark_frame, cells)
    all_histories, _, _ = make_scope(analysis_frame, established=False)
    no_price_filter, _, _ = make_scope(analysis_frame, price_filter=False)
    sample, all_histories, no_price_filter = [attach_outcome(part, threshold) for part in (sample, all_histories, no_price_filter)]
    reference = attach_outcome(reference, threshold)
    # Benchmark hosts have no model fold. All other hosts retain a common fold
    # across primary models and sensitivity samples, including hosts outside the
    # primary reporting cells who become eligible in a sensitivity.
    analysis_hosts = np.array(sorted(analysis_frame["host_id"].unique()), dtype=object)
    np.random.default_rng(SEED).shuffle(analysis_hosts)
    host_folds = {host: index % N_FOLDS for index, host in enumerate(analysis_hosts)}
    host_manifest = frame[["host_id", "host_role"]].drop_duplicates().sort_values("host_id")
    host_manifest["fold"] = host_manifest["host_id"].map(host_folds).astype("Int64")
    host_manifest.to_csv(PRIVATE_OUTPUT / "rq_host_fold_manifest.csv", index=False)
    private_columns = ["id", "host_id", "host_role", *CELL_KEYS, "number_of_reviews_ltm", "review_target_met"]
    reference[private_columns].assign(common_review_threshold=threshold).to_csv(PRIVATE_OUTPUT / "rq_benchmark_reference.csv", index=False)
    sample[private_columns].assign(fold=sample["host_id"].map(host_folds), common_review_threshold=threshold).to_csv(PRIVATE_OUTPUT / "rq_analysis_main_manifest.csv", index=False)
    raw_validation = validate_raw_reviews(frame, pd.concat([sample, reference], ignore_index=True), provenance, threshold)
    provenance["raw_validation"] = raw_validation["status"] == "completed"
    provenance["raw_review_validation"] = raw_validation
    benchmark_details = {
        "n_listings": len(reference), "n_hosts": reference["host_id"].nunique(),
        "n_segments": reference.groupby(CELL_KEYS).ngroups,
        "quantile_probability": CONFIG["benchmark_quantile"], "pooled_review_quantile": benchmark_q75,
        "common_integer_review_threshold": threshold,
        "reference_share_meeting_threshold": float(reference["review_target_met"].mean()),
        "reference_zero_recent_reviews": int(reference["number_of_reviews_ltm"].eq(0).sum()),
        "host_partition": CONFIG["benchmark_partition"],
        "scope": "Primary listing eligibility within the final primary analysis cells. Benchmark hosts supply the common cutoff only and are excluded from every model fit, OOF prediction and sensitivity sample.",
    }
    summary = {
        "raw_listings_or_cached_snapshot_rows": len(frame),
        "established_eligible_all_roles_before_cell_filter": len(eligible_base(frame)),
        "analysis_eligible_before_cell_filter": n_before_cells,
        "eligible_cells_ge_50": len(cells), "eligible_listings": len(sample), "eligible_hosts": sample["host_id"].nunique(),
        "analysis_pool_descriptive_p75_reviews_ltm": float(sample["number_of_reviews_ltm"].quantile(.75)),
        "common_review_threshold": threshold, "positive_n": int(sample["review_target_met"].sum()),
        "positive_share_with_ties": float(sample["review_target_met"].mean()),
        "zero_recent_review_listings": int(sample["number_of_reviews_ltm"].eq(0).sum()),
        "benchmark_development": benchmark_details,
        "all_source_hosts_by_role": {role: int(count) for role, count in host_manifest["host_role"].value_counts().items()},
        "threshold_definition": CONFIG["threshold_usage"],
        "exploratory_status": CONFIG["exploratory_status"],
        "validation_definition": "Revised exploratory five-fold host-grouped cross-validation, with a computationally separate benchmark-development host partition. No independent untouched final test set or hyperparameter search.",
        "scope_support_definition": CONFIG["segment_support"],
        "ranking_intervals": f"95% percentile intervals from {BOOTSTRAP_REPLICATES} within-segment host-cluster resamples, conditional on existing OOF probabilities; models are not refitted and intervals exclude model-fitting and model-selection uncertainty.",
        "established_definition": f"First review on or before {ESTABLISHED_CUTOFF.date()}, using reference date {CONFIG['reference_date']}. This is a review-history criterion, not listing launch date or proof of continuous operation.",
        "main_model_interpretation": "Physical listing attributes associated with review activity in the preceding year, evaluated on held-out analysis hosts. These are not verified pre-opening measurements or forecasts of a new operator's next year.",
        "operating_controls_sensitivity": "Current quoted price and minimum stay are contemporaneous operating characteristics, included only as a separately labelled sensitivity.",
        "calibration_status": "No post-hoc calibration is fitted. ECE uses ten fixed equal-width bins; sparse high-score bins limit calibration interpretation.",
        "missingness_main_numeric": {column: int(sample[column].isna().sum()) for column in NUMERIC_FEATURES},
        "provenance": provenance, "seed": SEED,
        "versions": {"python": platform.python_version(), "numpy": np.__version__, "pandas": pd.__version__, "scipy": scipy.__version__, "scikit_learn": sklearn.__version__},
        "script_sha256": file_sha256(__file__), "config_file": "config/review_analysis.json", "config_sha256": file_sha256(CONFIG_PATH),
        "model_settings": {"logistic": {"C": 1.0, "max_iter": 2000}, "random_forest": {"n_estimators": 250, "min_samples_leaf": 10, "max_features": "sqrt", "n_jobs": 2}},
    }
    observations = sample.groupby(CELL_KEYS).agg(
        n=("id", "size"), n_hosts=("host_id", "nunique"), median_reviews_ltm=("number_of_reviews_ltm", "median"),
        p75_reviews_ltm=("number_of_reviews_ltm", lambda values: values.quantile(.75)),
        positive_n=("review_target_met", "sum"), observed_review_target_share=("review_target_met", "mean"),
        median_quoted_price=("price_num", "median"),
    ).reset_index().sort_values("observed_review_target_share", ascending=False)
    observations["common_review_threshold"] = threshold
    observations.to_csv(OUTPUT / "rq_observed_segment_outcomes.csv", index=False)
    cells.sort_values(CELL_KEYS).to_csv(OUTPUT / "rq_eligible_lga_configurations.csv", index=False)
    reference_cells = reference.groupby(CELL_KEYS).agg(n_benchmark_listings=("id", "size"), n_benchmark_hosts=("host_id", "nunique"), benchmark_cell_descriptive_p75=("number_of_reviews_ltm", lambda values: values.quantile(.75))).reset_index()
    reference_cells = cells.merge(reference_cells, on=CELL_KEYS, how="left", validate="one_to_one")
    reference_cells["common_review_threshold"] = threshold
    reference_cells.to_csv(OUTPUT / "rq_benchmark_scope.csv", index=False)
    frame.loc[frame["room_type"].eq(CONFIG["room_type"]) & frame["bedrooms"].isin(CONFIG["bedrooms"]), "property_type"].value_counts().rename_axis("property_type").reset_index(name="n").to_csv(OUTPUT / "rq_property_type_counts.csv", index=False)
    all_metrics, rankings, calibrations = [], [], []
    scenarios = [("property_only", sample, False), ("operating_controls", sample, True), ("all_review_histories", all_histories, False), ("no_price_filter", no_price_filter, False)]
    for scenario, data, controls in scenarios:
        for model_name in ["logistic", "random_forest"]:
            metrics, ranking, calibration = evaluate(data, host_folds, benchmark_hosts, threshold=threshold, scenario=scenario, model_name=model_name, controls=controls)
            all_metrics.append(metrics)
            rankings.append(ranking)
            calibrations.append(calibration)
    pd.concat(rankings, ignore_index=True).to_csv(OUTPUT / "rq_oof_segment_ranking.csv", index=False)
    pd.concat(calibrations, ignore_index=True).to_csv(OUTPUT / "rq_calibration.csv", index=False)
    (OUTPUT / "rq_scope_summary.json").write_text(json.dumps(summary, indent=2, allow_nan=False) + "\n", encoding="utf-8")
    (OUTPUT / "rq_model_metrics.json").write_text(json.dumps(all_metrics, indent=2, allow_nan=False) + "\n", encoding="utf-8")
    print(f"Benchmark development: {len(reference)} listings / {reference.host_id.nunique()} hosts; P75={benchmark_q75:g}, integer threshold={threshold}.", flush=True)
    print(f"Primary analysis: {len(sample)} listings / {sample.host_id.nunique()} hosts / {len(cells)} segments; analysis P75={summary['analysis_pool_descriptive_p75_reviews_ltm']:g}.", flush=True)
    print("Aggregate results written to reports/tables; reference identifiers, host roles and OOF rows remain in data/processed.", flush=True)


if __name__ == "__main__":
    main()
