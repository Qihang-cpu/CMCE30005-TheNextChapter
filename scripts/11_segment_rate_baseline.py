"""Compare every model with a segment historical-rate baseline, then repeat the host split.

Run after scripts/rq_scope_feasibility.py and scripts/10_model_extensions.py:
    python scripts/11_segment_rate_baseline.py [--repeats 20]

The 3,873-listing sample, the 30-review event and the five outer host folds are
unchanged. Within each fold the baseline reads training-host outcomes only: the
attainment rate of each LGA x configuration segment among training listings,
shrunk towards the training-set rate with a prior weight fixed before the run.
A segment absent from a training fold receives the training-set rate.

The repeated-split check reassigns analysis hosts to five folds under new seeds
and refits the provisionally preferred model, the original logistic baseline
and the segment-rate baseline, so that the stability of the top-ranked
segments can be read from many partitions rather than one.
"""
from __future__ import annotations

import argparse
import importlib
import json
from pathlib import Path
import tempfile

import numpy as np
import pandas as pd
from scipy.stats import spearmanr
from sklearn.metrics import average_precision_score, brier_score_loss, roc_auc_score
from threadpoolctl import threadpool_limits

import rq_scope_feasibility as baseline

extensions = importlib.import_module("10_model_extensions")

ROOT = Path(__file__).resolve().parents[1]
PUBLIC = ROOT / "reports/tables"
PRIVATE = ROOT / "data/processed"
SEED = baseline.SEED
N_FOLDS = baseline.N_FOLDS
CELL_KEYS = baseline.CELL_KEYS
PRIOR_WEIGHT = 10          # pseudo-listings at the training-set rate; fixed before the run
PREFERRED = ("extended_property_only", "random_forest")
COMPARATORS = [
    ("property_only", "logistic", PRIVATE / "rq_oof_property_only_logistic.csv"),
    ("property_only", "random_forest", PRIVATE / "rq_oof_property_only_random_forest.csv"),
    ("operating_controls", "logistic", PRIVATE / "rq_oof_operating_controls_logistic.csv"),
    ("operating_controls", "random_forest", PRIVATE / "rq_oof_operating_controls_random_forest.csv"),
    ("extended_property_only", "logistic", PRIVATE / "rq_extension_oof_extended_property_only_logistic.csv"),
    ("extended_property_only", "random_forest", PRIVATE / "rq_extension_oof_extended_property_only_random_forest.csv"),
    ("extended_property_only", "hist_gradient_boosting", PRIVATE / "rq_extension_oof_extended_property_only_hist_gradient_boosting.csv"),
    ("extended_property_only", "hist_gradient_boosting_sigmoid", PRIVATE / "rq_extension_oof_extended_property_only_hist_gradient_boosting_sigmoid.csv"),
    ("extended_operating_controls", "hist_gradient_boosting", PRIVATE / "rq_extension_oof_extended_operating_controls_hist_gradient_boosting.csv"),
    ("extended_operating_controls", "hist_gradient_boosting_sigmoid", PRIVATE / "rq_extension_oof_extended_operating_controls_hist_gradient_boosting_sigmoid.csv"),
]
REPEATED_MODELS = [
    ("segment_rate", "segment_rate_baseline"),
    ("property_only", "logistic"),
    PREFERRED,
]


def segment_rate_probabilities(sample, folds, prior_weight):
    """Out-of-fold segment attainment rates learned from training hosts only."""
    y = sample["review_target_met"].to_numpy(dtype=int)
    probability = np.full(len(sample), np.nan)
    fold_rows = []
    for fold in range(N_FOLDS):
        train = folds.ne(fold).to_numpy()
        test = ~train
        if set(sample.loc[train, "host_id"]) & set(sample.loc[test, "host_id"]):
            raise ValueError("A host overlaps training and validation within a fold.")
        if y[train].sum() in (0, int(train.sum())) or y[test].sum() in (0, int(test.sum())):
            raise ValueError(f"Fold {fold} lacks one outcome class.")
        train_rate = float(y[train].mean())
        counts = sample.loc[train].groupby(CELL_KEYS)["review_target_met"].agg(positive_n="sum", n="size").reset_index()
        counts["rate"] = (counts["positive_n"] + prior_weight * train_rate) / (counts["n"] + prior_weight)
        mapped = sample.loc[test, CELL_KEYS].merge(counts[[*CELL_KEYS, "rate", "n"]], on=CELL_KEYS, how="left", validate="many_to_one")
        unseen = int(mapped["rate"].isna().sum())
        probability[test] = mapped["rate"].fillna(train_rate).to_numpy()
        fold_rows.append({
            "fold": fold, "n_train": int(train.sum()), "n_validation": int(test.sum()),
            "n_validation_hosts": int(sample.loc[test, "host_id"].nunique()),
            "training_rate": train_rate,
            "smallest_training_segment": int(counts["n"].min()),
            "validation_listings_in_unseen_segment": unseen,
            "roc_auc": float(roc_auc_score(y[test], probability[test])),
            "average_precision": float(average_precision_score(y[test], probability[test])),
            "brier_score": float(brier_score_loss(y[test], probability[test])),
        })
    if not np.isfinite(probability).all():
        raise ValueError("Every listing must receive one finite out-of-fold probability.")
    return probability, fold_rows


def fold_metrics(y, probability, folds):
    rows = []
    for fold in range(N_FOLDS):
        test = folds.eq(fold).to_numpy()
        rows.append({
            "fold": fold,
            "roc_auc": float(roc_auc_score(y[test], probability[test])),
            "average_precision": float(average_precision_score(y[test], probability[test])),
            "brier_score": float(brier_score_loss(y[test], probability[test])),
        })
    return pd.DataFrame(rows)


def comparator_probabilities(sample, path):
    """Align a stored out-of-fold prediction file with the frozen sample by listing id."""
    stored = pd.read_csv(path, dtype={"id": "string", "host_id": "string"})
    merged = sample[["id", "host_id", "fold", "review_target_met"]].merge(
        stored[["id", "host_id", "fold", "review_target_met", "oof_probability"]],
        on="id", how="left", suffixes=("", "_stored"), validate="one_to_one")
    if merged["oof_probability"].isna().any():
        raise ValueError(f"{path.name} does not cover every frozen listing.")
    for column in ("host_id", "fold", "review_target_met"):
        if not merged[column].eq(merged[f"{column}_stored"]).all():
            raise ValueError(f"{path.name} disagrees with the frozen sample on {column}.")
    return merged["oof_probability"].to_numpy(dtype=float)


def stored_metrics():
    rows = json.loads((PUBLIC / "rq_model_metrics.json").read_text()) + json.loads((PUBLIC / "rq_extension_metrics.json").read_text())
    return {(row["scenario"], row["model"]): row for row in rows}


def compact(row, scenario, model, label):
    return {
        "scenario": scenario, "model": model, "predictor_source": label,
        "roc_auc": row["roc_auc"], "average_precision": row["average_precision"],
        "brier_score": row["brier_score"], "log_loss": row["log_loss"],
        "expected_calibration_error_10_equal_width_bins": row["expected_calibration_error_10_equal_width_bins"],
        "precision_top_quarter": row["precision_top_quarter"],
        "mean_predicted_probability": row["mean_predicted_probability"],
        "observed_target_share": row["observed_target_share"],
    }


def ranking_agreement(reference_ranking, other_ranking):
    merged = reference_ranking[[*CELL_KEYS, "rank", "mean_oof_probability"]].merge(
        other_ranking[[*CELL_KEYS, "rank", "mean_oof_probability"]], on=CELL_KEYS, suffixes=("_baseline", "_model"), validate="one_to_one")
    if len(merged) != len(reference_ranking):
        raise ValueError("Rankings cover different segments.")
    top3 = lambda frame, column: set(map(tuple, frame.loc[frame[column].le(3), CELL_KEYS].to_numpy()))
    return {
        "spearman_rank_correlation": float(spearmanr(merged["rank_baseline"], merged["rank_model"]).statistic),
        "top_3_overlap": len(top3(merged, "rank_baseline") & top3(merged, "rank_model")),
        "same_first_ranked_segment": bool((merged.loc[merged["rank_baseline"].eq(1), CELL_KEYS].to_numpy() == merged.loc[merged["rank_model"].eq(1), CELL_KEYS].to_numpy()).all()),
        "largest_absolute_rank_change": int((merged["rank_baseline"] - merged["rank_model"]).abs().max()),
    }


def analysis_host_pool():
    manifest = pd.read_csv(PRIVATE / "rq_host_fold_manifest.csv", dtype={"host_id": "string"})
    hosts = np.array(sorted(manifest.loc[manifest["host_role"].eq("analysis"), "host_id"]), dtype=object)
    shuffled = hosts.copy()
    np.random.default_rng(SEED).shuffle(shuffled)
    original = pd.Series({host: index % N_FOLDS for index, host in enumerate(shuffled)})
    stored = manifest.loc[manifest["host_role"].eq("analysis")].set_index("host_id")["fold"]
    if not original.reindex(stored.index).eq(stored).all():
        raise ValueError("The primary host folds cannot be reproduced from the manifest and seed.")
    return hosts


def fit_out_of_fold(sample, folds, scenario, model_name):
    if scenario == "segment_rate":
        probability, _ = segment_rate_probabilities(sample, folds, PRIOR_WEIGHT)
        return probability
    if scenario == "property_only":
        pipeline, columns = baseline.build_model(model_name, False)
    else:
        pipeline, columns = extensions.build_pipeline(model_name, False)
    y = sample["review_target_met"].to_numpy(dtype=int)
    probability = np.full(len(sample), np.nan)
    for fold in range(N_FOLDS):
        train, test = folds.ne(fold).to_numpy(), folds.eq(fold).to_numpy()
        if set(sample.loc[train, "host_id"]) & set(sample.loc[test, "host_id"]):
            raise ValueError("A host overlaps training and validation within a repeated fold.")
        with threadpool_limits(limits=2):
            pipeline.fit(sample.loc[train, columns], y[train])
            probability[test] = pipeline.predict_proba(sample.loc[test, columns])[:, 1]
    if not np.isfinite(probability).all():
        raise ValueError("A repeated fit left a listing without a prediction.")
    return probability


def repeated_partitions(sample, hosts, n_repeats, private_stage):
    """Reassign hosts to folds under new seeds; hold the sample, event and models fixed."""
    y = sample["review_target_met"].to_numpy(dtype=int)
    metric_rows, rank_rows, manifest_rows = [], [], []
    for repeat in range(n_repeats):
        shuffled = hosts.copy()
        np.random.default_rng([SEED, repeat + 1]).shuffle(shuffled)
        host_folds = {host: index % N_FOLDS for index, host in enumerate(shuffled)}
        folds = sample["host_id"].map(host_folds).astype(int)
        manifest_rows.append(pd.DataFrame({"repeat": repeat + 1, "host_id": sample["host_id"], "fold": folds}).drop_duplicates())
        for scenario, model_name in REPEATED_MODELS:
            probability = fit_out_of_fold(sample, folds, scenario, model_name)
            metric_rows.append({
                "repeat": repeat + 1, "scenario": scenario, "model": model_name,
                "roc_auc": float(roc_auc_score(y, probability)),
                "average_precision": float(average_precision_score(y, probability)),
                "brier_score": float(brier_score_loss(y, probability)),
            })
            means = sample.assign(p=probability).groupby(CELL_KEYS)["p"].mean().sort_values(ascending=False).reset_index()
            means["rank"] = np.arange(1, len(means) + 1)
            rank_rows.append(means.assign(repeat=repeat + 1, scenario=scenario, model=model_name))
        print(f"repeat {repeat + 1}/{n_repeats} complete", flush=True)
    # Thread scheduling inside the forest can move the last digit of a score
    # between runs; published values are rounded so that reruns match exactly.
    metrics = pd.DataFrame(metric_rows).round({"roc_auc": 10, "average_precision": 10, "brier_score": 10})
    ranks = pd.concat(rank_rows, ignore_index=True)
    pd.concat(manifest_rows, ignore_index=True).to_csv(private_stage / "rq_repeated_split_host_folds.csv", index=False)
    ranks.to_csv(private_stage / "rq_repeated_split_segment_ranks.csv", index=False)
    summary = metrics.groupby(["scenario", "model"]).agg(
        repeats=("repeat", "size"),
        roc_auc_mean=("roc_auc", "mean"), roc_auc_min=("roc_auc", "min"), roc_auc_max=("roc_auc", "max"),
        average_precision_mean=("average_precision", "mean"), average_precision_min=("average_precision", "min"), average_precision_max=("average_precision", "max"),
        brier_mean=("brier_score", "mean"), brier_min=("brier_score", "min"), brier_max=("brier_score", "max"),
    ).reset_index()
    summary = summary.round({column: 10 for column in summary.columns if summary[column].dtype.kind == "f"})
    wide = metrics.pivot(index="repeat", columns=["scenario", "model"], values="roc_auc")
    summary["repeats_auc_above_segment_rate"] = summary.apply(
        lambda row: int((wide[(row["scenario"], row["model"])] > wide[("segment_rate", "segment_rate_baseline")]).sum()), axis=1)
    top3 = ranks.groupby(["scenario", "model", *CELL_KEYS]).agg(
        repeats=("repeat", "size"),
        share_ranked_first=("rank", lambda values: float(values.eq(1).mean())),
        share_in_top_3=("rank", lambda values: float(values.le(3).mean())),
        median_rank=("rank", "median"), best_rank=("rank", "min"), worst_rank=("rank", "max"),
        mean_of_segment_mean_probability=("p", "mean"),
    ).reset_index().sort_values(["scenario", "model", "share_in_top_3", "median_rank", *CELL_KEYS], ascending=[True, True, False, True, True, True])
    top3["mean_of_segment_mean_probability"] = top3["mean_of_segment_mean_probability"].round(8)
    return summary, top3, metrics


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--repeats", type=int, default=20, help="repeated host partitions; 0 skips the check")
    args = parser.parse_args()
    if args.repeats < 0:
        raise ValueError("--repeats must be non-negative.")
    sample, summary, frozen_hashes = extensions.load_frozen_sample()
    for name in ("rq_extension_metrics.json", "rq_extension_ranking.csv", "rq_extension_provenance.json"):
        frozen_hashes[f"reports/tables/{name}"] = baseline.file_sha256(PUBLIC / name)
    for _, _, path in COMPARATORS:
        frozen_hashes[path.relative_to(ROOT).as_posix()] = baseline.file_sha256(path)
    folds = sample["fold"].astype(int)
    y = sample["review_target_met"].to_numpy(dtype=int)
    threshold = int(sample["common_review_threshold"].iloc[0])
    stored = stored_metrics()

    with tempfile.TemporaryDirectory(prefix=".baseline-public-", dir=PUBLIC.parent) as public_dir, tempfile.TemporaryDirectory(prefix=".baseline-private-", dir=PRIVATE.parent) as private_dir:
        public_stage, private_stage = Path(public_dir), Path(private_dir)

        # 1. Segment-rate baseline on the unchanged folds.
        probability, baseline_folds = segment_rate_probabilities(sample, folds, PRIOR_WEIGHT)
        unsmoothed, _ = segment_rate_probabilities(sample, folds, 0)
        metrics = baseline.score_predictions(y, probability)
        metrics.update({
            "scenario": "segment_rate", "model": "segment_rate_baseline", "n": len(sample),
            "n_hosts": int(sample["host_id"].nunique()), "n_segments": int(sample.groupby(CELL_KEYS).ngroups),
            "common_review_threshold": threshold, "predictors": CELL_KEYS, "folds": baseline_folds,
            "prior_weight": PRIOR_WEIGHT,
            "rule": f"Within each fold: (training positives in the segment + {PRIOR_WEIGHT} x training-set rate) / (training listings in the segment + {PRIOR_WEIGHT}); a segment with no training listings receives the training-set rate. The prior weight was fixed before the run and not tuned.",
            "calibration_status": "Training-fold attainment rates; no fitted calibration.",
            "unsmoothed_reference": {
                "prior_weight": 0, "roc_auc": float(roc_auc_score(y, unsmoothed)),
                "average_precision": float(average_precision_score(y, unsmoothed)),
                "brier_score": float(brier_score_loss(y, unsmoothed)),
                "max_absolute_probability_difference": float(np.abs(unsmoothed - probability).max()),
                "note": "Shown only to record how little the pre-specified prior weight changes the baseline.",
            },
        })
        ranking = baseline.segment_ranking(sample, probability).assign(scenario="segment_rate", model="segment_rate_baseline")
        calibration = baseline.calibration_table(y, probability).assign(scenario="segment_rate", model="segment_rate_baseline")
        keys = ["id", "host_id", "host_role", "fold", *CELL_KEYS, "reviews_365d", "review_target_met", "common_review_threshold"]
        sample[keys].assign(oof_probability=probability).to_csv(private_stage / "rq_baseline_oof_segment_rate.csv", index=False)
        print(f"segment_rate baseline: AUC={metrics['roc_auc']:.6f}, AP={metrics['average_precision']:.6f}, Brier={metrics['brier_score']:.6f}, ECE={metrics['expected_calibration_error_10_equal_width_bins']:.6f}", flush=True)

        # 2. Side-by-side table, paired per-fold differences and ranking agreement.
        comparison = [compact(metrics, "segment_rate", "segment_rate_baseline", "training-fold segment attainment rates")]
        # Fold-specific constants differ across pooled validation rows; score them
        # rather than assigning the theoretical AUC of a single uniform constant.
        # AI-assisted correction: OpenAI (2026), ChatGPT/Codex project output,
        # 16 September; acknowledged in reports/ai-use-declaration.md.
        prevalence_probability = np.zeros(len(y), dtype=float)
        for fold in sorted(folds.unique()):
            validation = folds.to_numpy() == fold
            prevalence_probability[validation] = float(y[~validation].mean())
        comparison.append(compact(
            baseline.score_predictions(y, prevalence_probability), "constant",
            "training_prevalence_baseline", "training-fold prevalence, one value per fold",
        ))
        baseline_by_fold = fold_metrics(y, probability, folds)
        fold_rows, agreement_rows = [], []
        all_rankings = pd.concat([pd.read_csv(PUBLIC / "rq_oof_segment_ranking.csv"), pd.read_csv(PUBLIC / "rq_extension_ranking.csv")], ignore_index=True)
        for scenario, model_name, path in COMPARATORS:
            row = stored[(scenario, model_name)]
            label = "extended property features" if scenario.startswith("extended") else "baseline property features"
            label += " + current price and minimum stay" if "operating" in scenario else ""
            entry = compact(row, scenario, model_name, label)
            entry.update({
                "auc_minus_segment_rate": row["roc_auc"] - metrics["roc_auc"],
                "average_precision_minus_segment_rate": row["average_precision"] - metrics["average_precision"],
                "brier_minus_segment_rate": row["brier_score"] - metrics["brier_score"],
            })
            comparison.append(entry)
            model_by_fold = fold_metrics(y, comparator_probabilities(sample, path), folds)
            paired = baseline_by_fold.merge(model_by_fold, on="fold", suffixes=("_segment_rate", "_model"))
            for metric in ("roc_auc", "average_precision", "brier_score"):
                paired[f"{metric}_difference"] = paired[f"{metric}_model"] - paired[f"{metric}_segment_rate"]
            fold_rows.append(paired.assign(scenario=scenario, model=model_name))
            other = all_rankings.loc[all_rankings["scenario"].eq(scenario) & all_rankings["model"].eq(model_name)]
            agreement_rows.append({"scenario": scenario, "model": model_name, **ranking_agreement(ranking, other)})
        comparison = pd.DataFrame(comparison)
        fold_table = pd.concat(fold_rows, ignore_index=True)
        wins = fold_table.groupby(["scenario", "model"]).agg(
            folds_auc_above_segment_rate=("roc_auc_difference", lambda values: int((values > 0).sum())),
            folds_ap_above_segment_rate=("average_precision_difference", lambda values: int((values > 0).sum())),
            folds_brier_below_segment_rate=("brier_score_difference", lambda values: int((values < 0).sum())),
            mean_fold_auc_difference=("roc_auc_difference", "mean"),
            mean_fold_brier_difference=("brier_score_difference", "mean"),
        ).reset_index()
        comparison = comparison.merge(wins, on=["scenario", "model"], how="left")
        agreement = pd.DataFrame(agreement_rows)
        for frame in (comparison, fold_table, agreement):
            frame["baseline_comparison_note"] = "Paired descriptive differences on the same validation rows and folds; these are not significance tests."
        comparison.to_csv(public_stage / "rq_baseline_comparison.csv", index=False)
        fold_table.to_csv(public_stage / "rq_baseline_fold_comparison.csv", index=False)
        agreement.to_csv(public_stage / "rq_baseline_ranking_comparison.csv", index=False)
        ranking.to_csv(public_stage / "rq_baseline_segment_ranking.csv", index=False)
        calibration.to_csv(public_stage / "rq_baseline_calibration.csv", index=False)
        for _, row in comparison.iterrows():
            print(f"  {row['scenario']:28s} {row['model']:32s} AUC={row['roc_auc']:.4f} AP={row['average_precision']:.4f} Brier={row['brier_score']:.4f}", flush=True)

        # 3. Repeated host partitions.
        repeated = None
        if args.repeats:
            hosts = analysis_host_pool()
            repeat_summary, repeat_top3, repeat_metrics = repeated_partitions(sample, hosts, args.repeats, private_stage)
            repeat_summary.to_csv(public_stage / "rq_repeated_split_summary.csv", index=False)
            repeat_top3.to_csv(public_stage / "rq_repeated_split_top3.csv", index=False)
            repeat_metrics.to_csv(public_stage / "rq_repeated_split_metrics.csv", index=False)
            repeated = {
                "repeats": args.repeats, "models": [dict(scenario=scenario, model=model) for scenario, model in REPEATED_MODELS],
                "partition": f"Analysis hosts sorted by identifier, shuffled with numpy default_rng([{SEED}, repeat]) for repeat = 1..{args.repeats}, then fold = position mod {N_FOLDS}. Before the repeats, the primary assignment was reproduced from the stored host manifest with default_rng({SEED}) and verified.",
                "held_fixed": "Listing sample, reconstructed outcome, the 30-review event, model settings and features. Only the assignment of hosts to folds changes.",
                "ranking": "Mean out-of-fold probability by segment within each repeat; no host-cluster intervals are computed inside the repeats.",
            }
            for _, row in repeat_summary.iterrows():
                print(f"  repeats {row['scenario']:22s} {row['model']:24s} AUC {row['roc_auc_min']:.4f}-{row['roc_auc_max']:.4f} (mean {row['roc_auc_mean']:.4f}); above segment-rate in {row['repeats_auc_above_segment_rate']}/{row['repeats']}", flush=True)

        provenance = {
            "n_primary_listings": len(sample), "n_primary_hosts": int(sample["host_id"].nunique()),
            "n_segments": int(sample.groupby(CELL_KEYS).ngroups), "common_review_threshold": threshold,
            "reference_n": summary["benchmark_development"]["n_listings"],
            "prior_weight": PRIOR_WEIGHT, "smallest_training_segment_across_folds": int(min(row["smallest_training_segment"] for row in baseline_folds)),
            "validation_listings_in_unseen_segment": int(sum(row["validation_listings_in_unseen_segment"] for row in baseline_folds)),
            "frozen_inputs_sha256": frozen_hashes, "script_sha256": baseline.file_sha256(Path(__file__)),
            "validation": "The five outer host folds are those of the primary run. The baseline uses training-host outcomes only; validation outcomes never enter its rates.",
            "comparators": [dict(scenario=scenario, model=model) for scenario, model, _ in COMPARATORS],
            "repeated_partitions": repeated,
            "exploratory_status": "The baseline and repeated splits were added after the model results had been examined. They do not create an untouched final test.",
        }
        (public_stage / "rq_segment_rate_baseline.json").write_text(json.dumps({"metrics": metrics, "provenance": provenance}, indent=2, allow_nan=False) + "\n", encoding="utf-8")
        for relative, expected in frozen_hashes.items():
            if baseline.file_sha256(ROOT / relative) != expected:
                raise ValueError(f"Frozen input changed during the baseline run: {relative}")
        baseline.publish_outputs([(public_stage, PUBLIC), (private_stage, PRIVATE)])
    print("Segment-rate baseline comparison written to reports/tables; primary and extension outputs remain unchanged.", flush=True)


if __name__ == "__main__":
    main()
