"""Check whether the candidate shortlist depends on the segment-support rule.

Re-derives the segment ranking under minimum-support rules of 30, 50 and 75
analysis listings, holding everything else fixed: the primary eligibility
rules, the host partition and the common 30-review target from the primary
analysis. The two existing scope sensitivities (no history rule, no price
rule) are read from the segment-ladder tables written by script 08 so all
five variants can be compared on one page. A second table repeats the primary
ranking under alternative review targets (25, 35, and the reference group's P70
and P80 rounded up) with everything else fixed.

Run from the project root: python scripts/12_support_rule_sensitivity.py
Writes reports/tables/rq_support_rule_sensitivity.csv,
reports/tables/rq_support_rule_top3.csv and reports/tables/rq_threshold_sensitivity.csv. Listing-level data stay in
data/processed (ignored).
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

import numpy as np
import pandas as pd

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
import rq_scope_feasibility as rq  # noqa: E402

OUTPUT = ROOT / "reports" / "tables"
SUPPORT_RULES = (30, 50, 75)
KEYS = rq.CELL_KEYS


def main():
    scope = json.loads((OUTPUT / "rq_scope_summary.json").read_text())
    threshold = int(scope["common_review_threshold"])
    primary_top3 = pd.read_csv(OUTPUT / "rq_extension_ranking.csv")
    primary_top3 = primary_top3[(primary_top3["scenario"] == "extended_property_only") & (primary_top3["model"] == "random_forest")]
    primary_top3 = primary_top3.sort_values("rank").head(3)[KEYS]
    primary_set = set(map(tuple, primary_top3.to_numpy()))

    frame, provenance = rq.read_source()
    frame, _check = rq.reconstruct_raw_reviews(frame, provenance)
    frame["host_role"] = frame["host_id"].map(rq.host_role)
    base = rq.eligible_base(frame[frame["host_role"].eq("analysis")])
    base["met"] = base["reviews_365d"].ge(threshold).astype(int)

    summary_rows, top_rows = [], []

    def record(label, sample, note):
        seg = sample.groupby(KEYS).agg(n=("id", "size"), hosts=("host_id", "nunique"), rate=("met", "mean")).reset_index()
        seg = seg.sort_values(["rate", "n"], ascending=[False, False]).reset_index(drop=True)
        seg["rank"] = seg.index + 1
        top3 = seg.head(3)
        overlap = len(primary_set & set(map(tuple, top3[KEYS].to_numpy())))
        summary_rows.append({
            "variant": label, "listings": int(len(sample)), "hosts": int(sample["host_id"].nunique()),
            "segments": int(len(seg)), "attainment": float(sample["met"].mean()),
            "top3": "; ".join(f"{r.neighbourhood_cleansed} {r.configuration} ({r.rate:.1%})" for r in top3.itertuples()),
            "top3_overlap_with_primary": overlap, "review_target": threshold, "note": note,
        })
        for r in seg.itertuples():
            if (r.neighbourhood_cleansed, r.configuration) in primary_set:
                top_rows.append({"variant": label, "segment": f"{r.neighbourhood_cleansed} {r.configuration}",
                                 "n": int(r.n), "hosts": int(r.hosts), "attainment": float(r.rate), "rank": int(r.rank)})

    for min_n in SUPPORT_RULES:
        counts = base.groupby(KEYS).size().rename("n").reset_index()
        keep = counts.loc[counts["n"] >= min_n, KEYS]
        sample = base.merge(keep, on=KEYS, how="inner")
        record(f"support >= {min_n}", sample, "primary eligibility, primary host partition, fixed 30-review target"
               + (" (primary analysis)" if min_n == rq.MINIMUM_SEGMENT_LISTINGS else ""))

    # Scope sensitivities: recompute from the same frame so listing and host counts
    # use one definition (unique hosts). Listing totals are checked against the
    # segment-ladder tables written by script 08.
    for label, fname, kwargs, note in [
        ("no history rule (support >= 50)", "segment_ladder_all_histories_sensitivity.csv", {"established": False}, "first-review history rule removed"),
        ("no price rule (support >= 50)", "segment_ladder_no_price_sensitivity.csv", {"price_filter": False}, "price boundary removed"),
    ]:
        variant = rq.eligible_base(frame[frame["host_role"].eq("analysis")], **kwargs)
        variant["met"] = variant["reviews_365d"].ge(threshold).astype(int)
        counts = variant.groupby(KEYS).size().rename("n").reset_index()
        keep = counts.loc[counts["n"] >= rq.MINIMUM_SEGMENT_LISTINGS, KEYS]
        sample = variant.merge(keep, on=KEYS, how="inner")
        path = OUTPUT / fname
        if path.is_file():
            ladder_total = int(pd.read_csv(path)["n_listings"].sum())
            if ladder_total != len(sample):
                raise ValueError(f"{label}: {len(sample)} listings here but {ladder_total} in {fname}")
        record(label, sample, note + "; listing total matches " + fname)

    # Review-target sensitivity: primary sample and support rule, alternative targets.
    reference = pd.read_csv(ROOT / "data" / "processed" / "rq_benchmark_reference.csv")
    counts = base.groupby(KEYS).size().rename("n").reset_index()
    keep = counts.loc[counts["n"] >= rq.MINIMUM_SEGMENT_LISTINGS, KEYS]
    primary_sample = base.merge(keep, on=KEYS, how="inner")
    targets = {"reference P70": int(np.ceil(reference["reviews_365d"].quantile(0.70, interpolation="linear"))),
               "fixed 25": 25, "primary (reference P75)": threshold, "fixed 35": 35,
               "reference P80": int(np.ceil(reference["reviews_365d"].quantile(0.80, interpolation="linear")))}
    threshold_rows = []
    for label, target in targets.items():
        met = primary_sample["reviews_365d"].ge(target).astype(int)
        seg = primary_sample.assign(met=met).groupby(KEYS).agg(n=("id", "size"), rate=("met", "mean")).reset_index()
        seg = seg.sort_values(["rate", "n"], ascending=[False, False]).reset_index(drop=True)
        seg["rank"] = seg.index + 1
        top3 = seg.head(3)
        ranks = {f"{r.neighbourhood_cleansed} {r.configuration}": int(r.rank) for r in seg.itertuples()
                 if (r.neighbourhood_cleansed, r.configuration) in primary_set}
        threshold_rows.append({
            "target_rule": label, "review_target": int(target), "listings": int(len(primary_sample)),
            "attainment": float(met.mean()),
            "top3": "; ".join(f"{r.neighbourhood_cleansed} {r.configuration} ({r.rate:.1%})" for r in top3.itertuples()),
            "top3_overlap_with_primary": len(primary_set & set(map(tuple, top3[KEYS].to_numpy()))),
            "primary_candidate_ranks": "; ".join(f"{k}: {v}" for k, v in ranks.items()),
            "note": "primary eligibility, host partition and 50-listing support rule held fixed; descriptive ranking by observed attainment",
        })
    thresholds = pd.DataFrame(threshold_rows)
    thresholds.to_csv(OUTPUT / "rq_threshold_sensitivity.csv", index=False)

    summary = pd.DataFrame(summary_rows)
    tops = pd.DataFrame(top_rows)
    summary.to_csv(OUTPUT / "rq_support_rule_sensitivity.csv", index=False)
    tops.to_csv(OUTPUT / "rq_support_rule_top3.csv", index=False)
    pd.set_option("display.width", 200)
    print(summary[["variant", "listings", "hosts", "segments", "attainment", "top3_overlap_with_primary", "top3"]].to_string(index=False))
    print()
    print(tops.pivot(index="segment", columns="variant", values="rank").to_string())
    print()
    print(thresholds[["target_rule", "review_target", "attainment", "top3_overlap_with_primary", "top3"]].to_string(index=False))
    print(thresholds[["target_rule", "primary_candidate_ranks"]].to_string(index=False))


if __name__ == "__main__":
    main()
