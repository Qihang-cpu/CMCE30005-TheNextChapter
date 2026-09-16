"""Out-of-time check of the segment shortlist: does an earlier-year review advantage persist?

Run from the repository root:
    .venv/bin/python scripts/validation/temporal_holdout.py

Purpose
-------
The primary design ranks LGA x configuration segments by the share of established
listings that reached a benchmark review count in the year before each listing's
scrape date. This script asks a narrower, checkable question: if the same rule had
been applied one year earlier, would the segments it picked still have led in the
following year? It is a persistence check on historical review attainment. It is
not a forecast of a new operator's revenue or profit.

Windows
-------
Each listing keeps its own last_scraped date S. Two non-overlapping 365-day
windows are rebuilt from raw review dates:
    EARLIER = (S - 730 days, S - 365 days]
    RECENT  = (S - 365 days, S]
Only listings whose first review is on or before S - 730 are eligible, so both
windows lie inside their recorded review history. Listings with zero reviews in a
window are kept. This does not establish continuous operation across the period.

Rules carried over unchanged from scripts/rq_scope_feasibility.py and
config/review_analysis.json: room type, bedrooms, dwelling map, price range,
identifier normalisation, host partition (sha256 bucket), and the minimum segment
support. The review threshold is the ceiling of the benchmark hosts' P75 of
EARLIER-window reviews; it is fixed before either window is scored and the primary
design's threshold is never reused here.

Outputs (reports/validation/temporal-holdout/):
    sample_flow.csv, segment_cross_period.csv, validation_metrics.json,
    bootstrap_replicates.csv
"""
from __future__ import annotations

from collections import Counter
import json
from pathlib import Path
import platform
import sys
import time

import numpy as np
import pandas as pd
import scipy
import sklearn
from sklearn.metrics import average_precision_score, brier_score_loss, roc_auc_score

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))
import rq_scope_feasibility as rq  # noqa: E402

OUT = ROOT / "reports" / "validation" / "temporal-holdout"
WINDOW = int(rq.CONFIG["review_window_days"])          # 365
HISTORY_DAYS = 2 * WINDOW                              # 730
KEYS = rq.CELL_KEYS                                    # ["neighbourhood_cleansed", "configuration"]
MIN_N = rq.MINIMUM_SEGMENT_LISTINGS                    # 50
QUANTILE = float(rq.CONFIG["benchmark_quantile"])      # 0.75
TOP_K = 3
PRIOR_WEIGHT = 10          # secondary smoothed score only; mirrors scripts/11_segment_rate_baseline.py
B = 2000
SEED = 30005
PRIMARY_EXPECTED = {"reference": 906, "analysis": 3873, "hosts": 1726, "segments": 14, "threshold": 30}


def segment_label(row):
    return f"{row[KEYS[0]]} | {row[KEYS[1]]}"


def rank_segments(rate, n):
    """Rank by attainment, higher first; ties broken by more listings first. Returns 1-based ranks."""
    order = np.lexsort((-np.asarray(n), -np.asarray(rate)))
    ranks = np.empty(len(order), dtype=int)
    ranks[order] = np.arange(1, len(order) + 1)
    return ranks


def weighted_rate(rate, n, mask):
    return float((rate[mask] * n[mask]).sum() / n[mask].sum())


def main():
    t0 = time.time()
    OUT.mkdir(parents=True, exist_ok=True)

    # ------------------------------------------------------------------
    # 1. Listings, host roles, and the two review windows from raw dates
    # ------------------------------------------------------------------
    frame, provenance = rq.read_source()
    frame["host_role"] = frame["host_id"].map(rq.host_role)
    snapshot = pd.Series(frame["last_scraped_date"].to_numpy(), index=frame["id"])
    recent_start = snapshot - pd.Timedelta(days=WINDOW)
    earlier_start = snapshot - pd.Timedelta(days=HISTORY_DAYS)
    recent_counts, earlier_counts = Counter(), Counter()
    review_rows = unknown_ids = invalid_dates = 0
    for chunk in pd.read_csv(ROOT / "data/raw/reviews_airbnb.csv", usecols=["listing_id", "date"],
                             dtype={"listing_id": "string"}, chunksize=250_000):
        review_rows += len(chunk)
        chunk["listing_id"] = chunk["listing_id"].map(rq.canonical_id)
        unknown_ids += int((~chunk["listing_id"].isin(snapshot.index)).sum())
        dates = rq.iso_dates(chunk["date"])
        invalid_dates += int(dates.isna().sum())
        end = chunk["listing_id"].map(snapshot)
        mid = chunk["listing_id"].map(recent_start)
        start = chunk["listing_id"].map(earlier_start)
        recent_counts.update(chunk.loc[dates.gt(mid) & dates.le(end), "listing_id"].value_counts().to_dict())
        earlier_counts.update(chunk.loc[dates.gt(start) & dates.le(mid), "listing_id"].value_counts().to_dict())
    frame["reviews_recent"] = frame["id"].map(recent_counts).fillna(0).astype(int)
    frame["reviews_earlier"] = frame["id"].map(earlier_counts).fillna(0).astype(int)

    # ------------------------------------------------------------------
    # 2. Primary-design self-check (365-day history, recent window only)
    # ------------------------------------------------------------------
    primary = rq.eligible_base(frame)
    primary_an = primary[primary["host_role"].eq("analysis")]
    primary_cells = primary_an.groupby(KEYS).size().rename("n").reset_index()
    primary_cells = primary_cells[primary_cells["n"] >= MIN_N]
    primary_an = primary_an.merge(primary_cells[KEYS], on=KEYS)
    primary_bm = primary[primary["host_role"].eq("benchmark_development")].merge(primary_cells[KEYS], on=KEYS)
    primary_q = float(primary_bm["reviews_recent"].quantile(QUANTILE, interpolation="linear"))
    primary_check = {
        "reference": len(primary_bm), "analysis": len(primary_an), "hosts": int(primary_an["host_id"].nunique()),
        "segments": len(primary_cells), "threshold": int(np.ceil(primary_q)),
    }
    primary_self_check = {
        "observed": {**primary_check, "benchmark_p75": primary_q},
        "expected": PRIMARY_EXPECTED,
        "matches": primary_check == PRIMARY_EXPECTED,
    }

    # ------------------------------------------------------------------
    # 3. Validation eligibility and sample flow
    # ------------------------------------------------------------------
    flow = []

    def record(step, data, note):
        flow.append({"step": step, "listings": len(data), "hosts": int(data["host_id"].nunique()), "note": note})

    record("source_listings", frame, "all rows in data/raw/listings_airbnb.csv")
    step = frame[frame["room_type"].eq(rq.CONFIG["room_type"]) & frame["bedrooms"].isin(rq.CONFIG["bedrooms"])]
    record("entire_home_1_to_3_bedrooms", step, "room_type and bedrooms rules from config")
    step = step[step["dwelling_class"].notna()]
    record("standard_dwelling_types", step, "property_type in the four-type map")
    step = step[step["price_num"].between(rq.CONFIG["minimum_price"], rq.CONFIG["maximum_price"])]
    record("quoted_price_range", step, f"price {rq.CONFIG['minimum_price']}-{rq.CONFIG['maximum_price']}")
    base = rq.eligible_base(frame, established=False)
    assert len(base) == len(step)
    validation = base[base["first_review_date"].le(base["last_scraped_date"] - pd.Timedelta(days=HISTORY_DAYS))].copy()
    record("review_history_730_days", validation, f"first_review <= last_scraped - {HISTORY_DAYS} days; both windows inside recorded history")
    val_an = validation[validation["host_role"].eq("analysis")]
    val_bm = validation[validation["host_role"].eq("benchmark_development")]
    record("analysis_hosts", val_an, "sha256 host bucket != 0")
    record("benchmark_hosts", val_bm, "sha256 host bucket == 0; threshold development only")
    cells = val_an.groupby(KEYS).size().rename("n").reset_index()
    kept = cells[cells["n"] >= MIN_N].copy()
    an = val_an.merge(kept[KEYS], on=KEYS).reset_index(drop=True)
    bm = val_bm.merge(kept[KEYS], on=KEYS).reset_index(drop=True)
    record("analysis_retained_segments", an, f"{len(kept)} of {len(cells)} segments with >= {MIN_N} analysis listings, fixed before ranking")
    record("benchmark_retained_segments", bm, "benchmark listings inside the retained segments")
    pd.DataFrame(flow).to_csv(OUT / "sample_flow.csv", index=False)

    primary_ids = set(primary_an["id"])
    validation_ids = set(an["id"])
    not_in_validation = primary_an[~primary_an["id"].isin(validation_ids)]
    short_history = not_in_validation[not_in_validation["first_review_date"].gt(
        not_in_validation["last_scraped_date"] - pd.Timedelta(days=HISTORY_DAYS))]
    primary_not_in_validation = {
        "primary_analysis_listings": len(primary_an),
        "not_in_validation_sample": len(not_in_validation),
        "of_which_history_365_to_730_days": len(short_history),
        "of_which_segment_below_support_in_validation": len(not_in_validation) - len(short_history),
        "validation_listings_not_in_primary": int(len(validation_ids - primary_ids)),
        "note": "Listings with 365-730 days of review history are in the primary sample but cannot be scored in the earlier window; the validation says nothing about them.",
    }

    # ------------------------------------------------------------------
    # 4. Threshold from benchmark hosts' EARLIER window; fixed thereafter
    # ------------------------------------------------------------------
    bm_q_earlier = float(bm["reviews_earlier"].quantile(QUANTILE, interpolation="linear"))
    threshold = int(np.ceil(bm_q_earlier))
    bm_q_recent_info = float(bm["reviews_recent"].quantile(QUANTILE, interpolation="linear"))
    an["met_earlier"] = an["reviews_earlier"].ge(threshold).astype(int)
    an["met_recent"] = an["reviews_recent"].ge(threshold).astype(int)
    overall_earlier = float(an["met_earlier"].mean())
    overall_recent = float(an["met_recent"].mean())

    # ------------------------------------------------------------------
    # 5. Segment table, ranking, candidates
    # ------------------------------------------------------------------
    seg = an.groupby(KEYS).agg(
        n_listings=("id", "size"), n_hosts=("host_id", "nunique"),
        zero_reviews_earlier=("reviews_earlier", lambda v: int(v.eq(0).sum())),
        zero_reviews_recent=("reviews_recent", lambda v: int(v.eq(0).sum())),
        positives_earlier=("met_earlier", "sum"), positives_recent=("met_recent", "sum"),
        earlier_rate=("met_earlier", "mean"), recent_rate=("met_recent", "mean"),
    ).reset_index()
    seg["change_pp"] = (seg["recent_rate"] - seg["earlier_rate"]) * 100
    seg["rank_earlier"] = rank_segments(seg["earlier_rate"], seg["n_listings"])
    seg["rank_recent"] = rank_segments(seg["recent_rate"], seg["n_listings"])
    seg["candidate_earlier"] = seg["rank_earlier"].le(TOP_K)
    seg["earlier_rate_smoothed"] = (seg["positives_earlier"] + PRIOR_WEIGHT * overall_earlier) / (seg["n_listings"] + PRIOR_WEIGHT)
    seg = seg.sort_values("rank_earlier").reset_index(drop=True)
    seg["label"] = seg.apply(segment_label, axis=1)
    top3_labels = seg.loc[seg["candidate_earlier"], "label"].tolist()

    # ------------------------------------------------------------------
    # 6. Listing-level prediction metrics (score = segment earlier rate)
    # ------------------------------------------------------------------
    an = an.merge(seg[KEYS + ["earlier_rate", "earlier_rate_smoothed", "label", "candidate_earlier"]], on=KEYS)
    y = an["met_recent"].to_numpy()
    score_raw = an["earlier_rate"].to_numpy()
    score_smooth = an["earlier_rate_smoothed"].to_numpy()
    reference_score = np.full(len(y), overall_earlier)
    brier_reference = float(brier_score_loss(y, reference_score))

    def scored(score):
        brier = float(brier_score_loss(y, score))
        return {"roc_auc": float(roc_auc_score(y, score)), "average_precision": float(average_precision_score(y, score)),
                "brier": brier, "brier_skill_score_vs_reference": float(1 - brier / brier_reference)}

    prediction = {
        "primary_score": "raw segment earlier attainment rate",
        "outcome": f"recent-window reviews >= {threshold}",
        "raw_segment_rate": scored(score_raw),
        "smoothed_segment_rate": {**scored(score_smooth), "prior_weight": PRIOR_WEIGHT,
                                  "rule": f"(segment earlier positives + {PRIOR_WEIGHT} x overall earlier rate) / (segment listings + {PRIOR_WEIGHT}); secondary only"},
        "reference_constant_prediction": {"value": overall_earlier, "brier": brier_reference,
                                          "note": "Every listing receives the overall earlier rate; no segment information."},
        "constant_at_recent_prevalence_for_information": {"value": overall_recent, "brier": float(overall_recent * (1 - overall_recent)),
                                                          "note": "Uses the recent outcome itself, so it is not a fair reference; shown to size the market-wide decline."},
    }

    # ------------------------------------------------------------------
    # 7. Earlier top-3 vs other retained segments in the recent window
    # ------------------------------------------------------------------
    rate = seg["recent_rate"].to_numpy()
    n = seg["n_listings"].to_numpy()
    cand = seg["candidate_earlier"].to_numpy()
    top_listing = weighted_rate(rate, n, cand)
    rest_listing = weighted_rate(rate, n, ~cand)

    def host_weighted(data, mask):
        # each host counts once inside a group, via the mean of its listings' outcomes in that group
        return float(data[mask].groupby("host_id")["met_recent"].mean().mean())

    top_host = host_weighted(an, an["candidate_earlier"].to_numpy())
    rest_host = host_weighted(an, ~an["candidate_earlier"].to_numpy())
    hosts_in_both = int(len(set(an.loc[an["candidate_earlier"], "host_id"]) & set(an.loc[~an["candidate_earlier"], "host_id"])))
    top3_vs_rest = {
        "earlier_top3": top3_labels,
        "listing_weighted": {"top3_recent_rate": top_listing, "rest_recent_rate": rest_listing,
                             "difference_pp": (top_listing - rest_listing) * 100},
        "host_weighted": {"top3_recent_rate": top_host, "rest_recent_rate": rest_host,
                          "difference_pp": (top_host - rest_host) * 100,
                          "hosts_with_listings_in_both_groups": hosts_in_both,
                          "note": "A host counts once per group as the mean of its listings' recent outcomes in that group; a host with listings in both groups appears in both."},
        "top3_earlier_rate_listing_weighted": weighted_rate(seg["earlier_rate"].to_numpy(), n, cand),
        "rest_earlier_rate_listing_weighted": weighted_rate(seg["earlier_rate"].to_numpy(), n, ~cand),
    }

    # ------------------------------------------------------------------
    # 8. Host bootstrap: threshold and retained segment set held fixed
    # ------------------------------------------------------------------
    K = len(seg)
    seg_index = {label: i for i, label in enumerate(seg["label"])}
    an["seg_i"] = an["label"].map(seg_index).astype(int)
    hosts = np.array(sorted(an["host_id"].unique()), dtype=object)
    host_index = {h: i for i, h in enumerate(hosts)}
    H = len(hosts)
    hs = an.groupby(["host_id", "seg_i"]).agg(n=("id", "size"), e=("met_earlier", "sum"), r=("met_recent", "sum")).reset_index()
    N_hs = np.zeros((H, K)); E_hs = np.zeros((H, K)); R_hs = np.zeros((H, K))
    rows_i = hs["host_id"].map(host_index).to_numpy(); cols_i = hs["seg_i"].to_numpy()
    N_hs[rows_i, cols_i] = hs["n"]; E_hs[rows_i, cols_i] = hs["e"]; R_hs[rows_i, cols_i] = hs["r"]
    assert N_hs.sum() == len(an)
    cand_fixed = cand.copy()

    def group_rates(counts, top_mask):
        """Listing- and host-weighted recent rates for top and rest under host multiplicities `counts`."""
        out = {}
        for name, mask in (("top", top_mask), ("rest", ~top_mask)):
            n_h = N_hs[:, mask].sum(axis=1)
            r_h = R_hs[:, mask].sum(axis=1)
            present = n_h > 0
            listing = (counts * r_h).sum() / (counts * n_h).sum()
            host = (counts[present] * (r_h[present] / n_h[present])).sum() / counts[present].sum()
            out[name] = (listing, host)
        return out

    rng = np.random.default_rng(SEED)
    rows = []
    rank_draws = np.zeros((B, K), dtype=int)
    for b in range(B):
        draw = rng.integers(0, H, size=H)
        counts = np.bincount(draw, minlength=H).astype(float)
        n_b = counts @ N_hs
        e_b = counts @ E_hs
        rate_b = np.where(n_b > 0, e_b / np.maximum(n_b, 1), 0.0)
        ranks_b = rank_segments(rate_b, n_b)
        rank_draws[b] = ranks_b
        top_b = ranks_b <= TOP_K
        fixed = group_rates(counts, cand_fixed)
        resel = group_rates(counts, top_b)
        rows.append({
            "replicate": b + 1,
            "diff_fixed_candidates": (fixed["top"][0] - fixed["rest"][0]) * 100,
            "diff_reselected": (resel["top"][0] - resel["rest"][0]) * 100,
            "diff_fixed_candidates_host_weighted": (fixed["top"][1] - fixed["rest"][1]) * 100,
            "diff_reselected_host_weighted": (resel["top"][1] - resel["rest"][1]) * 100,
            "reselected_top3": ";".join(seg["label"].iloc[np.flatnonzero(top_b)[np.argsort(ranks_b[top_b])]]),
            "set_reproduced": bool(set(np.flatnonzero(top_b)) == set(np.flatnonzero(cand_fixed))),
        })
    reps = pd.DataFrame(rows)
    reps.to_csv(OUT / "bootstrap_replicates.csv", index=False)

    def interval(values):
        lo, hi = np.percentile(values, [2.5, 97.5])
        return {"lower_95_pp": float(lo), "upper_95_pp": float(hi), "bootstrap_mean_pp": float(np.mean(values))}

    held_fixed = f"threshold ({threshold} reviews) and retained segment set ({K} segments) held fixed at their point-estimate values inside every replicate"
    top3_share = (rank_draws <= TOP_K).mean(axis=0)
    rank_pct = np.percentile(rank_draws, [2.5, 50, 97.5], axis=0)
    seg["bootstrap_share_top3"] = top3_share
    seg["rank_p2_5"] = rank_pct[0].astype(int); seg["rank_p50"] = rank_pct[1].astype(int); seg["rank_p97_5"] = rank_pct[2].astype(int)

    bootstrap = {
        "replicates": B, "seed": SEED,
        "resampling_unit": "analysis hosts with replacement; every listing of a drawn host enters with the host's multiplicity",
        "held_fixed": held_fixed,
        "interval_A_fixed_candidates": {
            **interval(reps["diff_fixed_candidates"]), "point_estimate_pp": top3_vs_rest["listing_weighted"]["difference_pp"],
            "candidates": "point-estimate earlier top-3 held fixed; only attainment rates resampled", "weighting": "listing", "held_fixed": held_fixed},
        "interval_B_reselected_candidates": {
            **interval(reps["diff_reselected"]), "point_estimate_pp": top3_vs_rest["listing_weighted"]["difference_pp"],
            "candidates": "top-3 re-selected inside each replicate from its own earlier rates (selection uncertainty included)", "weighting": "listing", "held_fixed": held_fixed},
        "interval_A_fixed_candidates_host_weighted": {
            **interval(reps["diff_fixed_candidates_host_weighted"]), "point_estimate_pp": top3_vs_rest["host_weighted"]["difference_pp"],
            "weighting": "host", "held_fixed": held_fixed},
        "interval_B_reselected_candidates_host_weighted": {
            **interval(reps["diff_reselected_host_weighted"]), "point_estimate_pp": top3_vs_rest["host_weighted"]["difference_pp"],
            "weighting": "host", "held_fixed": held_fixed},
        "share_replicates_reproducing_point_estimate_top3_set": float(reps["set_reproduced"].mean()),
        "share_replicates_reselected_top3_beats_rest_recent": float(reps["diff_reselected"].gt(0).mean()),
        "share_replicates_fixed_top3_beats_rest_recent": float(reps["diff_fixed_candidates"].gt(0).mean()),
        "per_segment_share_in_top3_and_rank_percentiles": "see segment_cross_period.csv",
    }

    # ------------------------------------------------------------------
    # 9. Write outputs
    # ------------------------------------------------------------------
    cross = seg.rename(columns={KEYS[0]: "lga"})[[
        "lga", "configuration", "n_listings", "n_hosts", "zero_reviews_earlier", "zero_reviews_recent",
        "earlier_rate", "recent_rate", "change_pp", "rank_earlier", "rank_recent", "candidate_earlier",
        "bootstrap_share_top3", "rank_p2_5", "rank_p50", "rank_p97_5",
    ]]
    cross.to_csv(OUT / "segment_cross_period.csv", index=False)

    metrics = {
        "purpose": "Out-of-time persistence check of the segment shortlist rule. Not a forecast of a new operator's future profit or revenue.",
        "windows": {"earlier": f"(last_scraped - {HISTORY_DAYS} days, last_scraped - {WINDOW} days]", "recent": f"(last_scraped - {WINDOW} days, last_scraped]",
                    "basis": "per-listing last_scraped; both windows rebuilt from raw review dates"},
        "eligibility": {"room_type": rq.CONFIG["room_type"], "bedrooms": rq.CONFIG["bedrooms"], "property_map": rq.PROPERTY_MAP,
                        "price": [rq.CONFIG["minimum_price"], rq.CONFIG["maximum_price"]],
                        "history_rule": f"first_review <= last_scraped - {HISTORY_DAYS} days",
                        "zero_review_listings": "kept in both windows; this does not prove continuous operation"},
        "sample": {"analysis_listings": len(an), "analysis_hosts": H, "benchmark_listings": len(bm), "benchmark_hosts": int(bm["host_id"].nunique()),
                   "segments_retained": K, "segments_before_support": len(cells),
                   "zero_reviews_earlier_analysis": int(an["reviews_earlier"].eq(0).sum()), "zero_reviews_recent_analysis": int(an["reviews_recent"].eq(0).sum())},
        "threshold": {"value": threshold, "benchmark_earlier_p75": bm_q_earlier,
                      "derived_from": "ceil of the linear-interpolation P75 of EARLIER-window reviews among benchmark-development listings in the retained segments; fixed for both windows and every later step",
                      "benchmark_recent_p75_for_information_only": bm_q_recent_info,
                      "primary_design_threshold_not_reused": True},
        "overall_attainment": {"earlier": overall_earlier, "recent": overall_recent, "change_pp": (overall_recent - overall_earlier) * 100},
        "candidate_rule": f"rank retained segments by EARLIER attainment among analysis listings, ties broken by more listings; top {TOP_K} are the candidates",
        "prediction": prediction,
        "top3_vs_rest_recent_window": top3_vs_rest,
        "bootstrap": bootstrap,
        "primary_design_self_check": primary_self_check,
        "primary_not_in_validation": primary_not_in_validation,
        "review_stream": {"rows": review_rows, "rows_with_unknown_listing_id": unknown_ids, "invalid_dates": invalid_dates},
        "provenance": {"source_sha256": provenance["raw_file_sha256"], "config": "config/review_analysis.json", "seed": SEED,
                       "versions": {"python": platform.python_version(), "numpy": np.__version__, "pandas": pd.__version__,
                                    "scipy": scipy.__version__, "scikit_learn": sklearn.__version__}},
        "runtime_seconds": round(time.time() - t0, 1),
    }
    (OUT / "validation_metrics.json").write_text(json.dumps(metrics, indent=2, allow_nan=False, default=lambda o: o.item() if hasattr(o, "item") else str(o)) + "\n", encoding="utf-8")

    # ------------------------------------------------------------------
    # 10. Console summary
    # ------------------------------------------------------------------
    pc = primary_self_check["observed"]
    print(f"primary self-check: {pc['reference']} ref / {pc['analysis']} analysis / {pc['hosts']} hosts / {pc['segments']} segments / "
          f"P75 {pc['benchmark_p75']:.2f} -> {pc['threshold']}  [{'match' if primary_self_check['matches'] else 'MISMATCH'}]")
    print(f"primary listings not in validation: {primary_not_in_validation['not_in_validation_sample']} "
          f"(history 365-730 days: {primary_not_in_validation['of_which_history_365_to_730_days']}, segment below support: {primary_not_in_validation['of_which_segment_below_support_in_validation']})")
    print(f"validation sample: {len(an):,} analysis listings / {H:,} hosts; {len(bm)} benchmark listings / {bm['host_id'].nunique()} hosts; {K} of {len(cells)} segments")
    print(f"threshold: benchmark EARLIER P75 {bm_q_earlier:.2f} -> {threshold} (benchmark recent P75 {bm_q_recent_info:.2f}, information only)")
    print(f"overall attainment: earlier {overall_earlier:.2%}, recent {overall_recent:.2%}")
    print(seg[["label", "n_listings", "n_hosts", "earlier_rate", "recent_rate", "change_pp", "rank_earlier", "rank_recent", "bootstrap_share_top3", "rank_p50"]]
          .to_string(index=False, formatters={"earlier_rate": "{:.1%}".format, "recent_rate": "{:.1%}".format, "change_pp": "{:+.1f}".format, "bootstrap_share_top3": "{:.3f}".format}))
    r = prediction["raw_segment_rate"]
    print(f"prediction (raw segment rate): AUC {r['roc_auc']:.3f}, Brier {r['brier']:.4f} vs reference {brier_reference:.4f}, skill {r['brier_skill_score_vs_reference']:+.3f}; "
          f"smoothed AUC {prediction['smoothed_segment_rate']['roc_auc']:.3f}, Brier {prediction['smoothed_segment_rate']['brier']:.4f}")
    lw, hw = top3_vs_rest["listing_weighted"], top3_vs_rest["host_weighted"]
    print(f"earlier top-3 recent {lw['top3_recent_rate']:.2%} vs rest {lw['rest_recent_rate']:.2%}: {lw['difference_pp']:+.2f} pp listing-weighted; "
          f"host-weighted {hw['top3_recent_rate']:.2%} vs {hw['rest_recent_rate']:.2%}: {hw['difference_pp']:+.2f} pp")
    A, Bi = bootstrap["interval_A_fixed_candidates"], bootstrap["interval_B_reselected_candidates"]
    print(f"bootstrap B={B} seed={SEED} ({held_fixed}): A fixed candidates 95% [{A['lower_95_pp']:+.2f}, {A['upper_95_pp']:+.2f}] pp; "
          f"B re-selected 95% [{Bi['lower_95_pp']:+.2f}, {Bi['upper_95_pp']:+.2f}] pp; set reproduced {bootstrap['share_replicates_reproducing_point_estimate_top3_set']:.1%}; "
          f"re-selected top-3 > rest {bootstrap["share_replicates_reselected_top3_beats_rest_recent"]:.2%}")
    print(f"written to {OUT.relative_to(ROOT)} in {time.time() - t0:.0f}s")


if __name__ == "__main__":
    main()
