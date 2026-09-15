"""Compare six fixed model extensions on the validated primary sample.

Run after scripts/rq_scope_feasibility.py. The listing set, review outcome,
benchmark and outer host folds remain fixed. These additional comparisons use
an already explored snapshot; they are not an independent final test.
"""
from __future__ import annotations

import json
from pathlib import Path
import re
import tempfile

import numpy as np
import pandas as pd
from sklearn.calibration import CalibratedClassifierCV
from sklearn.compose import ColumnTransformer
from sklearn.ensemble import HistGradientBoostingClassifier, RandomForestClassifier
from sklearn.impute import SimpleImputer
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import average_precision_score, brier_score_loss, roc_auc_score
from sklearn.model_selection import GroupKFold
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import OneHotEncoder, StandardScaler
from threadpoolctl import threadpool_limits

import rq_scope_feasibility as baseline

ROOT = Path(__file__).resolve().parents[1]
PUBLIC = ROOT / "reports/tables"
PRIVATE = ROOT / "data/processed"
SEED = 30005
AMENITY_PATTERNS = {
    "has_wifi": (r"wi-?fi", None),
    "has_pool": (r"\bpool\b", r"pool table"),
    "has_aircon": (r"air conditioning", None),
    "has_free_parking": (r"free parking", None),
    "has_kitchen": (r"\bkitchen(?:ette)?\b", None),
    "has_washer": (r"\bwasher\b|\bwashing machine\b", None),
    "has_workspace": (r"\bworkspace\b", None),
    "has_dryer": (r"\bdryer\b", r"hair dryer"),
    "has_private_entrance": (r"private entrance", None),
}
PROPERTY_NUMERIC = baseline.NUMERIC_FEATURES + ["latitude", "longitude", "beds"] + list(AMENITY_PATTERNS)
HGB_SETTINGS = {
    "max_iter": 150, "learning_rate": 0.05, "max_leaf_nodes": 15,
    "min_samples_leaf": 20, "l2_regularization": 10,
    "early_stopping": False, "random_state": SEED,
}
CANDIDATES = [
    ("extended_property_only", "logistic", False, False),
    ("extended_property_only", "random_forest", False, False),
    ("extended_property_only", "hist_gradient_boosting", False, False),
    ("extended_property_only", "hist_gradient_boosting_sigmoid", False, True),
    ("extended_operating_controls", "hist_gradient_boosting", True, False),
    ("extended_operating_controls", "hist_gradient_boosting_sigmoid", True, True),
]


def amenity_flags(value):
    try:
        items = json.loads(value)
    except (TypeError, json.JSONDecodeError):
        items = None
    if not isinstance(items, list) or not all(isinstance(item, str) for item in items):
        return {name: np.nan for name in AMENITY_PATTERNS}
    return {
        name: float(any(re.search(pattern, item, re.I) and
                        (exclude is None or not re.search(exclude, item, re.I))
                        for item in items))
        for name, (pattern, exclude) in AMENITY_PATTERNS.items()
    }


def load_frozen_sample():
    summary_path = PUBLIC / "rq_scope_summary.json"
    summary = json.loads(summary_path.read_text())
    if not summary["provenance"]["raw_review_validation"]["passed"]:
        raise ValueError("The primary raw-data validation must pass before extensions run.")
    if summary["review_outcome"].split(",")[0] != "reviews_365d":
        raise ValueError("The primary outcome must be the reconstructed 365-day review count.")
    expected_hashes = summary["provenance"]["raw_file_sha256"].copy()
    expected_hashes["config/review_analysis.json"] = summary["config_sha256"]
    expected_hashes["scripts/rq_scope_feasibility.py"] = summary["script_sha256"]
    for relative, expected in expected_hashes.items():
        if baseline.file_sha256(ROOT / relative) != expected:
            raise ValueError(f"{relative} differs from the validated primary run.")
    cleaning = json.loads((PRIVATE / "cleaning_manifest.json").read_text())
    if not cleaning["review_reconstruction"]["passed"]:
        raise ValueError("The cleaning manifest does not record a passed review reconstruction.")
    for entry in cleaning["inputs"]:
        if expected_hashes.get(entry["path"]) != entry["sha256"]:
            raise ValueError("Cleaning and primary modelling used different raw inputs.")

    frozen_paths = [summary_path, PRIVATE / "cleaning_manifest.json",
                    PRIVATE / "rq_analysis_main_manifest.csv", PRIVATE / "rq_benchmark_reference.csv",
                    PRIVATE / "rq_host_fold_manifest.csv", PUBLIC / "rq_model_metrics.json",
                    PUBLIC / "rq_oof_segment_ranking.csv", PUBLIC / "rq_calibration.csv"]
    frozen_paths.extend(sorted(PRIVATE.glob("rq_oof_*.csv")))
    expected_hashes.update({str(path.relative_to(ROOT)): baseline.file_sha256(path)
                            for path in frozen_paths})
    sample = pd.read_csv(PRIVATE / "rq_analysis_main_manifest.csv", dtype={"id": "string", "host_id": "string"})
    reference = pd.read_csv(PRIVATE / "rq_benchmark_reference.csv", dtype={"id": "string", "host_id": "string"})
    host_manifest = pd.read_csv(PRIVATE / "rq_host_fold_manifest.csv", dtype={"host_id": "string"})
    if sample["id"].duplicated().any() or len(sample) != summary["eligible_listings"]:
        raise ValueError("The frozen primary listing manifest is incomplete or duplicated.")
    if not sample["host_role"].eq("analysis").all() or set(sample["host_id"]) & set(reference["host_id"]):
        raise ValueError("Reference hosts must be absent from the modelling sample.")
    host_folds = host_manifest.set_index("host_id")["fold"]
    if not sample["fold"].eq(sample["host_id"].map(host_folds)).all():
        raise ValueError("The frozen sample and host-fold manifest disagree.")
    threshold = summary["common_review_threshold"]
    if not sample["common_review_threshold"].eq(threshold).all() or not sample["review_target_met"].eq(sample["reviews_365d"].ge(threshold).astype(int)).all():
        raise ValueError("The frozen outcome labels do not match the common review threshold.")

    columns = ["id", "host_id", "accommodates", "bathrooms_text", "amenities", "latitude", "longitude", "beds", "price", "minimum_nights"]
    raw = pd.read_csv(ROOT / "data/raw/listings_airbnb.csv", usecols=columns,
                      dtype={"id": "string", "host_id": "string"}, low_memory=False)
    raw["id"] = raw["id"].map(baseline.canonical_id).astype("string")
    raw["raw_host_id"] = raw.pop("host_id").map(baseline.canonical_id).astype("string")
    raw["bathrooms_num"] = baseline.parse_bathrooms(raw["bathrooms_text"])
    raw["n_amenities"] = raw["amenities"].map(baseline.parse_amenities)
    flags = pd.DataFrame(raw["amenities"].map(amenity_flags).tolist(), index=raw.index)
    raw = pd.concat([raw, flags], axis=1)
    raw["price_num"] = pd.to_numeric(raw["price"].astype("string").str.replace(r"[$,]", "", regex=True), errors="coerce")
    raw["minimum_nights"] = pd.to_numeric(raw["minimum_nights"], errors="coerce")
    prices = raw["price_num"].to_numpy(dtype=float, na_value=np.nan)
    minimum_nights = raw["minimum_nights"].to_numpy(dtype=float, na_value=np.nan)
    raw["log_price"] = np.log(np.where(prices > 0, prices, np.nan))
    raw["log_minimum_nights"] = np.log1p(np.where(minimum_nights >= 0, minimum_nights, np.nan))
    for column in PROPERTY_NUMERIC:
        raw[column] = pd.to_numeric(raw[column], errors="coerce")
    sample = sample.merge(raw, on="id", how="left", validate="one_to_one")
    if not sample["host_id"].eq(sample["raw_host_id"]).all():
        raise ValueError("A frozen listing does not match its raw-source host.")
    if not sample["latitude"].dropna().between(-90, 90).all() or not sample["longitude"].dropna().between(-180, 180).all():
        raise ValueError("Unexpected geographic coordinates; resolve before fitting.")
    if sample.groupby(baseline.CELL_KEYS).size().lt(50).any():
        raise ValueError("The frozen sample violates the segment-support requirement.")
    return sample, summary, expected_hashes


def build_pipeline(model_name, controls):
    numeric = PROPERTY_NUMERIC + (["log_price", "log_minimum_nights"] if controls else [])
    preprocessing = ColumnTransformer([
        ("numeric", Pipeline([
            ("imputer", SimpleImputer(strategy="median", keep_empty_features=True)),
            ("scaler", StandardScaler()),
        ]), numeric),
        ("categorical", Pipeline([
            ("imputer", SimpleImputer(strategy="most_frequent", keep_empty_features=True)),
            ("encoder", OneHotEncoder(handle_unknown="ignore", sparse_output=False)),
        ]), baseline.CELL_KEYS),
    ])
    if model_name == "logistic":
        estimator = LogisticRegression(C=1.0, max_iter=2000, random_state=SEED)
    elif model_name == "random_forest":
        estimator = RandomForestClassifier(n_estimators=250, min_samples_leaf=10,
                                            max_features="sqrt", random_state=SEED, n_jobs=2)
    elif model_name.startswith("hist_gradient_boosting"):
        estimator = HistGradientBoostingClassifier(**HGB_SETTINGS)
    else:
        raise ValueError(model_name)
    return Pipeline([("preprocess", preprocessing), ("model", estimator)]), numeric + baseline.CELL_KEYS


def inner_host_splits(training):
    splits = list(GroupKFold(n_splits=3).split(training, training["review_target_met"], groups=training["host_id"]))
    validation_visits = np.zeros(len(training), dtype=int)
    for train, validation in splits:
        if set(training.iloc[train]["host_id"]) & set(training.iloc[validation]["host_id"]):
            raise ValueError("A host overlaps an inner calibration training and validation fold.")
        if training.iloc[train]["review_target_met"].nunique() != 2 or training.iloc[validation]["review_target_met"].nunique() != 2:
            raise ValueError("An inner calibration split has only one outcome class.")
        validation_visits[validation] += 1
    if not np.all(validation_visits == 1):
        raise ValueError("Inner calibration folds must predict each training row exactly once.")
    return splits


def evaluate_extension(sample, scenario, model_name, controls, calibrated, private_stage):
    target = sample["review_target_met"].to_numpy(dtype=int)
    predictions = np.full(len(sample), np.nan)
    visits = np.zeros(len(sample), dtype=int)
    folds, inner_assignments = [], []
    for fold in range(5):
        training = sample.loc[sample["fold"].ne(fold)].reset_index(drop=True)
        validation = sample["fold"].eq(fold)
        if set(training["host_id"]) & set(sample.loc[validation, "host_id"]):
            raise ValueError("A host overlaps outer training and validation.")
        pipeline, columns = build_pipeline(model_name, controls)
        if calibrated:
            splits = inner_host_splits(training)
            for inner_fold, (_, inner_validation) in enumerate(splits):
                assignment = training.iloc[inner_validation][["id", "host_id"]].copy()
                assignment["outer_fold"] = fold
                assignment["inner_fold"] = inner_fold
                inner_assignments.append(assignment)
            model = CalibratedClassifierCV(estimator=pipeline, method="sigmoid",
                                           cv=splits, ensemble=False, n_jobs=1)
        else:
            model = pipeline
        with threadpool_limits(limits=2):
            model.fit(training[columns], training["review_target_met"].to_numpy(dtype=int))
            predictions[validation] = model.predict_proba(sample.loc[validation, columns])[:, 1]
        visits[validation] += 1
        folds.append({
            "fold": fold, "n_train": len(training), "n_validation": int(validation.sum()),
            "n_validation_hosts": sample.loc[validation, "host_id"].nunique(),
            "roc_auc": float(roc_auc_score(target[validation], predictions[validation])),
            "average_precision": float(average_precision_score(target[validation], predictions[validation])),
            "brier_score": float(brier_score_loss(target[validation], predictions[validation])),
            "inner_host_folds": 3 if calibrated else 0,
        })
    if not np.all(visits == 1) or not np.isfinite(predictions).all():
        raise ValueError("Every primary listing must receive one finite outer-fold prediction.")
    metrics = baseline.score_predictions(target, predictions)
    metrics.update({
        "scenario": scenario, "model": model_name, "n": len(sample),
        "n_hosts": sample["host_id"].nunique(), "n_segments": sample.groupby(baseline.CELL_KEYS).ngroups,
        "common_review_threshold": int(sample["common_review_threshold"].iloc[0]),
        "predictors": columns, "folds": folds,
        "calibration_status": "Sigmoid calibration fitted on inner host-grouped OOF predictions within each outer training fold; the underlying pipeline is then refitted on that entire outer training fold." if calibrated else "Raw model scores; no fitted probability calibration.",
        "exploratory_status": "Six fixed extensions evaluated after examination of the baseline results. There is no untouched final test set or hyperparameter search.",
    })
    keys = ["id", "host_id", "host_role", "fold", *baseline.CELL_KEYS, "reviews_365d", "review_target_met", "common_review_threshold"]
    sample[keys].assign(oof_probability=predictions).to_csv(private_stage / f"rq_extension_oof_{scenario}_{model_name}.csv", index=False)
    if inner_assignments:
        pd.concat(inner_assignments, ignore_index=True).to_csv(private_stage / f"rq_extension_inner_folds_{scenario}_{model_name}.csv", index=False)
    ranks = baseline.segment_ranking(sample, predictions).assign(scenario=scenario, model=model_name)
    bins = baseline.calibration_table(target, predictions).assign(scenario=scenario, model=model_name)
    print(f"{scenario} / {model_name}: AUC={metrics['roc_auc']:.6f}, AP={metrics['average_precision']:.6f}, Brier={metrics['brier_score']:.6f}, ECE={metrics['expected_calibration_error_10_equal_width_bins']:.6f}", flush=True)
    return metrics, ranks, bins


def main():
    sample, summary, frozen_hashes = load_frozen_sample()
    baseline_metrics = json.loads((PUBLIC / "rq_model_metrics.json").read_text())
    with tempfile.TemporaryDirectory(prefix=".extensions-public-", dir=PUBLIC.parent) as public_dir, tempfile.TemporaryDirectory(prefix=".extensions-private-", dir=PRIVATE.parent) as private_dir:
        public_stage, private_stage = Path(public_dir), Path(private_dir)
        metrics, rankings, calibrations = [], [], []
        for scenario, model, controls, calibrated in CANDIDATES:
            result, ranks, bins = evaluate_extension(sample, scenario, model, controls, calibrated, private_stage)
            comparator = next(row for row in baseline_metrics if row["scenario"] == ("operating_controls" if controls else "property_only") and row["model"] == "logistic")
            result["baseline_comparison"] = {
                "scenario": comparator["scenario"], "model": "logistic",
                "auc_difference": result["roc_auc"] - comparator["roc_auc"],
                "average_precision_difference": result["average_precision"] - comparator["average_precision"],
                "brier_difference": result["brier_score"] - comparator["brier_score"],
                "interpretation": "Paired descriptive differences on the same outer validation rows; these are not significance tests.",
            }
            metrics.append(result); rankings.append(ranks); calibrations.append(bins)
        (public_stage / "rq_extension_metrics.json").write_text(json.dumps(metrics, indent=2) + "\n")
        compact_fields = ["scenario", "model", "n", "n_hosts", "n_segments", "common_review_threshold", "roc_auc", "average_precision", "brier_score", "log_loss", "expected_calibration_error_10_equal_width_bins", "mean_predicted_probability", "observed_target_share", "precision_top_quarter"]
        pd.DataFrame([{field: row[field] for field in compact_fields} for row in metrics]).to_csv(public_stage / "rq_extension_metrics.csv", index=False)
        pd.concat(rankings, ignore_index=True).to_csv(public_stage / "rq_extension_ranking.csv", index=False)
        pd.concat(calibrations, ignore_index=True).to_csv(public_stage / "rq_extension_calibration.csv", index=False)
        provenance = {
            "n_primary_listings": len(sample), "n_primary_hosts": sample["host_id"].nunique(),
            "reference_n": summary["benchmark_development"]["n_listings"],
            "common_review_threshold": summary["common_review_threshold"],
            "primary_source_and_outputs_sha256": frozen_hashes,
            "extension_script_sha256": baseline.file_sha256(Path(__file__)),
            "candidates": [dict(scenario=scenario, model=model, operating_controls=controls, sigmoid_calibration=calibrated) for scenario, model, controls, calibrated in CANDIDATES],
            "hist_gradient_boosting_settings": HGB_SETTINGS,
            "logistic_settings": {"C": 1.0, "max_iter": 2000},
            "random_forest_settings": {"n_estimators": 250, "min_samples_leaf": 10, "max_features": "sqrt"},
            "features_added": ["latitude", "longitude", "beds", *AMENITY_PATTERNS],
            "amenity_patterns": AMENITY_PATTERNS,
            "numeric_missingness": {column: int(sample[column].isna().sum()) for column in PROPERTY_NUMERIC},
            "validation": "The original five outer host folds are unchanged. Sigmoid calibration uses three host-disjoint folds inside each outer training subset, with training-only preprocessing and no outer validation outcomes supplied to calibration.",
            "scope": "All features are extracted from the supplied listing snapshot. Current price and minimum stay occur only in the labelled operating-controls sensitivity.",
            "intervals": "95% conditional host-cluster intervals use fixed outer-fold scores; models are not refitted in the bootstrap.",
            "selection_limit": "These extensions follow baseline inspection; selection of a preferred variant requires confirmation on a later independent dataset. All six comparisons are reported.",
        }
        (public_stage / "rq_extension_provenance.json").write_text(json.dumps(provenance, indent=2) + "\n")
        for relative, expected in frozen_hashes.items():
            if baseline.file_sha256(ROOT / relative) != expected:
                raise ValueError(f"Frozen input changed during extension fitting: {relative}")
        baseline.publish_outputs([(public_stage, PUBLIC), (private_stage, PRIVATE)])
    print("Six extension results written separately; primary model outputs remain unchanged.", flush=True)


if __name__ == "__main__":
    main()
