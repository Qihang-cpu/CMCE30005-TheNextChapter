"""Nested host-grouped validation of the model-selection step.

The extension comparison (script 10) chose the enhanced random forest after
looking at outer-fold results, so its reported advantage over the segment-rate
baseline may include a selection effect. This script re-runs the whole
selection process inside each outer training fold:

- outer folds: the five frozen host-grouped folds from the primary run, used
  only for evaluation;
- inner folds: three host-grouped folds inside each outer training set, used
  to choose among the four property-only candidates by pooled inner Brier
  score (rule fixed before the run);
- the chosen candidate is refitted on the full outer training fold and scored
  on the outer test fold, so no outer test listing influences any choice;
- the segment-rate baseline uses the same outer training and test folds and
  the same fixed prior weight as script 11.

Run from the project root after scripts 10 and 11:
    python scripts/13_nested_selection.py
Writes reports/tables/rq_nested_selection_folds.csv,
rq_nested_selection_summary.json, rq_nested_calibration.csv and
rq_nested_segment_calibration.csv. Listing-level predictions stay in
data/processed (ignored).
"""
from __future__ import annotations

import importlib.util
import json
import sys
from pathlib import Path

import numpy as np
import pandas as pd
from sklearn.calibration import CalibratedClassifierCV
from sklearn.metrics import average_precision_score, brier_score_loss, roc_auc_score
from threadpoolctl import threadpool_limits

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
import rq_scope_feasibility as baseline  # noqa: E402


def load_script(name):
    spec = importlib.util.spec_from_file_location(name.replace(".py", ""), ROOT / "scripts" / name)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


ext = load_script("10_model_extensions.py")
PUBLIC = ROOT / "reports" / "tables"
PRIVATE = ROOT / "data" / "processed"
SEED = 30005
PRIOR_WEIGHT = 10
BOOTSTRAP_REPLICATES = 1000
KEYS = baseline.CELL_KEYS
CANDIDATES = [c for c in ext.CANDIDATES if not c[2]]  # property-only candidates only


def fit_candidate(training, model_name, calibrated):
    pipeline, columns = ext.build_pipeline(model_name, controls=False)
    if calibrated:
        model = CalibratedClassifierCV(estimator=pipeline, method="sigmoid",
                                       cv=ext.inner_host_splits(training), ensemble=False, n_jobs=1)
    else:
        model = pipeline
    with threadpool_limits(limits=2):
        model.fit(training[columns], training["review_target_met"].to_numpy(dtype=int))
    return model, columns


def segment_rate(training, test):
    """Training-fold segment attainment with the fixed prior weight (script 11 rule)."""
    overall = training["review_target_met"].mean()
    grouped = training.groupby(KEYS)["review_target_met"].agg(["sum", "size"])
    smoothed = (grouped["sum"] + PRIOR_WEIGHT * overall) / (grouped["size"] + PRIOR_WEIGHT)
    key = pd.MultiIndex.from_frame(test[KEYS])
    return smoothed.reindex(key).fillna(overall).to_numpy(dtype=float)


def metrics(y, p):
    return {"roc_auc": float(roc_auc_score(y, p)), "average_precision": float(average_precision_score(y, p)),
            "brier_score": float(brier_score_loss(y, p))}


def main():
    sample, summary, _hashes = ext.load_frozen_sample()
    sample = sample.reset_index(drop=True)
    y_all = sample["review_target_met"].to_numpy(dtype=int)
    nested = np.full(len(sample), np.nan)
    base = np.full(len(sample), np.nan)
    fold_rows, inner_rows = [], []

    for fold in sorted(sample["fold"].unique()):
        train_mask = sample["fold"].ne(fold)
        training = sample.loc[train_mask].reset_index(drop=True)
        test = sample.loc[~train_mask]
        if set(training["host_id"]) & set(test["host_id"]):
            raise ValueError("A host overlaps outer training and test folds.")

        # inner selection: pooled inner-OOF Brier per candidate, training data only
        inner_splits = ext.inner_host_splits(training)
        inner_scores = {}
        for scenario, model_name, _controls, calibrated in CANDIDATES:
            inner_pred = np.full(len(training), np.nan)
            for inner_train, inner_val in inner_splits:
                inner_training = training.iloc[inner_train].reset_index(drop=True)
                model, columns = fit_candidate(inner_training, model_name, calibrated)
                inner_pred[inner_val] = model.predict_proba(training.iloc[inner_val][columns])[:, 1]
            if not np.isfinite(inner_pred).all():
                raise ValueError("Every inner listing must receive one prediction.")
            inner_scores[model_name] = metrics(training["review_target_met"].to_numpy(dtype=int), inner_pred)
            inner_rows.append({"outer_fold": int(fold), "candidate": model_name, **inner_scores[model_name]})
        chosen = min(inner_scores, key=lambda m: inner_scores[m]["brier_score"])
        calibrated = dict((c[1], c[3]) for c in CANDIDATES)[chosen]

        # refit the chosen candidate on the full outer training fold, score the outer test fold
        model, columns = fit_candidate(training, chosen, calibrated)
        nested[~train_mask] = model.predict_proba(test[columns])[:, 1]
        base[~train_mask] = segment_rate(training, test)
        y = test["review_target_met"].to_numpy(dtype=int)
        m_sel, m_base = metrics(y, nested[~train_mask]), metrics(y, base[~train_mask])
        fold_rows.append({
            "outer_fold": int(fold), "n_test": int(len(test)), "n_test_hosts": int(test["host_id"].nunique()),
            "selected_candidate": chosen, "inner_brier_of_selected": inner_scores[chosen]["brier_score"],
            **{f"selected_{k}": v for k, v in m_sel.items()},
            **{f"baseline_{k}": v for k, v in m_base.items()},
            "auc_difference": m_sel["roc_auc"] - m_base["roc_auc"],
            "average_precision_difference": m_sel["average_precision"] - m_base["average_precision"],
            "brier_difference": m_sel["brier_score"] - m_base["brier_score"],
        })
        print(f"fold {fold}: selected {chosen} (inner Brier {inner_scores[chosen]['brier_score']:.4f}); "
              f"outer AUC {m_sel['roc_auc']:.3f} vs baseline {m_base['roc_auc']:.3f}; "
              f"Brier {m_sel['brier_score']:.4f} vs {m_base['brier_score']:.4f}", flush=True)

    if not (np.isfinite(nested).all() and np.isfinite(base).all()):
        raise ValueError("Every listing must receive one nested and one baseline prediction.")

    # the baseline must reproduce script 11's out-of-fold segment rates exactly
    stored = pd.read_csv(PRIVATE / "rq_baseline_oof_segment_rate.csv", dtype={"id": "string"}).set_index("id")["oof_probability"]
    if not np.allclose(base, stored.reindex(sample["id"]).to_numpy(), atol=1e-12):
        raise ValueError("The segment-rate baseline does not reproduce script 11's out-of-fold probabilities.")

    folds = pd.DataFrame(fold_rows)
    pooled_sel, pooled_base = metrics(y_all, nested), metrics(y_all, base)

    # host bootstrap of the pooled differences, predictions held fixed (no refitting)
    rng = np.random.default_rng(SEED)
    hosts = sample["host_id"].to_numpy()
    unique_hosts = np.unique(hosts)
    host_index = pd.Series(np.arange(len(sample))).groupby(hosts).apply(np.array)
    diffs = []
    for _ in range(BOOTSTRAP_REPLICATES):
        draw = rng.choice(unique_hosts, size=len(unique_hosts), replace=True)
        idx = np.concatenate([host_index[h] for h in draw])
        yb, nb, bb = y_all[idx], nested[idx], base[idx]
        if yb.min() == yb.max():
            continue
        diffs.append((roc_auc_score(yb, nb) - roc_auc_score(yb, bb), brier_score_loss(yb, nb) - brier_score_loss(yb, bb)))
    diffs = np.array(diffs)

    selection = folds["selected_candidate"].value_counts().to_dict()
    result = {
        "design": "Outer: five frozen host-grouped folds (evaluation only). Inner: three host-grouped folds within each outer training fold; the candidate with the lowest pooled inner Brier score is selected, refitted on the whole outer training fold and scored on the outer test fold. Baseline: training-fold segment attainment with prior weight 10 on the same outer folds.",
        "candidates": [c[1] for c in CANDIDATES], "selection_rule": "lowest pooled inner-fold Brier score (fixed before the run)",
        "selected_per_fold": folds.set_index("outer_fold")["selected_candidate"].to_dict(),
        "selection_frequency": selection,
        "pooled": {"selected_process": pooled_sel, "segment_rate_baseline": pooled_base,
                   "auc_difference": pooled_sel["roc_auc"] - pooled_base["roc_auc"],
                   "average_precision_difference": pooled_sel["average_precision"] - pooled_base["average_precision"],
                   "brier_difference": pooled_sel["brier_score"] - pooled_base["brier_score"]},
        "per_fold": {"folds_auc_above_baseline": int((folds["auc_difference"] > 0).sum()),
                     "folds_brier_below_baseline": int((folds["brier_difference"] < 0).sum()),
                     "mean_auc_difference": float(folds["auc_difference"].mean()),
                     "min_auc_difference": float(folds["auc_difference"].min()),
                     "max_auc_difference": float(folds["auc_difference"].max()),
                     "mean_brier_difference": float(folds["brier_difference"].mean())},
        "host_bootstrap": {
            "replicates": int(len(diffs)), "seed": SEED, "unit": "hosts resampled with replacement; all of a host's listings enter together",
            "predictions_held_fixed": True,
            "note": "Intervals describe sampling variation of the pooled comparison with the nested predictions held fixed; they do not include refitting, inner re-selection or threshold estimation.",
            "auc_difference_95": [float(np.percentile(diffs[:, 0], 2.5)), float(np.percentile(diffs[:, 0], 97.5))],
            "brier_difference_95": [float(np.percentile(diffs[:, 1], 2.5)), float(np.percentile(diffs[:, 1], 97.5))],
            "share_replicates_auc_above_baseline": float((diffs[:, 0] > 0).mean()),
            "share_replicates_brier_below_baseline": float((diffs[:, 1] < 0).mean()),
        },
        "reference_from_script_11": "extended_property_only random_forest chosen after inspection: pooled AUC 0.6396, Brier 0.1813 (rq_baseline_comparison.csv)",
        "n": int(len(sample)), "n_hosts": int(sample["host_id"].nunique()),
        "common_review_threshold": int(summary["common_review_threshold"]),
        "note": "Selection is exploratory in the sense that the four candidates were defined after the baseline results were seen; the nested procedure removes the outer-fold selection effect only.",
    }

    # calibration: five equal-count bins of the selected process's predictions; hosts counted once
    # per bin. The baseline takes only one value per segment and fold, so equal-count bins would
    # split tied listings arbitrarily; its calibration is reported by segment below instead.
    cal_rows = []
    for label, pred in [("selected_process", nested)]:
        bins = pd.qcut(pd.Series(pred).rank(method="first"), 5, labels=False)
        frame = pd.DataFrame({"bin": bins, "pred": pred, "y": y_all, "host": hosts})
        for b, g in frame.groupby("bin"):
            cal_rows.append({"model": label, "bin": int(b) + 1, "n": int(len(g)), "n_hosts": int(g["host"].nunique()),
                             "mean_predicted": float(g["pred"].mean()), "observed_rate": float(g["y"].mean()),
                             "gap": float(g["pred"].mean() - g["y"].mean()),
                             "predicted_range": f"{g['pred'].min():.3f}-{g['pred'].max():.3f}"})
    calibration = pd.DataFrame(cal_rows)

    seg = sample[KEYS + ["host_id"]].assign(y=y_all, nested=nested, base=base)
    seg_cal = seg.groupby(KEYS).agg(n=("y", "size"), n_hosts=("host_id", "nunique"), observed_rate=("y", "mean"),
                                    nested_mean_predicted=("nested", "mean"), baseline_mean_predicted=("base", "mean")).reset_index()
    seg_cal["nested_gap"] = seg_cal["nested_mean_predicted"] - seg_cal["observed_rate"]
    seg_cal = seg_cal.sort_values("nested_mean_predicted", ascending=False).reset_index(drop=True)
    seg_cal["nested_rank"] = seg_cal.index + 1

    folds.to_csv(PUBLIC / "rq_nested_selection_folds.csv", index=False)
    pd.DataFrame(inner_rows).to_csv(PUBLIC / "rq_nested_selection_inner.csv", index=False)
    (PUBLIC / "rq_nested_selection_summary.json").write_text(json.dumps(result, indent=2))
    calibration.to_csv(PUBLIC / "rq_nested_calibration.csv", index=False)
    seg_cal.to_csv(PUBLIC / "rq_nested_segment_calibration.csv", index=False)
    keys = ["id", "host_id", "fold", *KEYS, "reviews_365d", "review_target_met"]
    sample[keys].assign(nested_probability=nested, baseline_probability=base).to_csv(PRIVATE / "rq_nested_oof_predictions.csv", index=False)

    print("\nselection per fold:", result["selected_per_fold"])
    print(f"pooled selected-process AUC {pooled_sel['roc_auc']:.4f} AP {pooled_sel['average_precision']:.4f} Brier {pooled_sel['brier_score']:.5f}")
    print(f"pooled baseline         AUC {pooled_base['roc_auc']:.4f} AP {pooled_base['average_precision']:.4f} Brier {pooled_base['brier_score']:.5f}")
    print(f"difference AUC {result['pooled']['auc_difference']:+.4f} (95% {result['host_bootstrap']['auc_difference_95']}), "
          f"Brier {result['pooled']['brier_difference']:+.5f} (95% {result['host_bootstrap']['brier_difference_95']}); "
          f"folds AUC above {result['per_fold']['folds_auc_above_baseline']}/5, Brier below {result['per_fold']['folds_brier_below_baseline']}/5")
    print("\ncalibration (five equal-count bins):")
    print(calibration.to_string(index=False))
    print("\ntop segments by nested prediction:")
    print(seg_cal.head(5).to_string(index=False))


if __name__ == "__main__":
    main()
