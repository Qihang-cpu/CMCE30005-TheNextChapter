"""Regression checks for the segment historical-rate baseline.

Run with: python -m unittest discover -s tests -v
"""
import importlib.util
from pathlib import Path
import sys
import unittest

import numpy as np
import pandas as pd

SCRIPTS = Path(__file__).resolve().parents[1] / "scripts"
sys.path.insert(0, str(SCRIPTS))
spec = importlib.util.spec_from_file_location("segment_rate_baseline", SCRIPTS / "11_segment_rate_baseline.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


def fixture():
    """Forty hosts with two listings each, five host folds, two segments, mixed outcomes."""
    rows = []
    for host in range(40):
        for index in range(2):
            rows.append({
                "id": str(len(rows)), "host_id": str(host), "fold": host % 5,
                "neighbourhood_cleansed": "Cell", "configuration": "A" if host % 2 == 0 else "B",
                "review_target_met": int((host // 2 + index) % 3 == 0),
            })
    return pd.DataFrame(rows)


class SegmentRateBaselineTests(unittest.TestCase):
    def test_rates_come_from_training_hosts_only(self):
        data = fixture()
        probability, folds = module.segment_rate_probabilities(data, data["fold"], 0)
        for fold in range(5):
            train, test = data["fold"].ne(fold), data["fold"].eq(fold)
            expected = data.loc[train].groupby("configuration")["review_target_met"].mean()
            observed = data.loc[test].assign(p=probability[test.to_numpy()]).groupby("configuration")["p"].agg(["min", "max"])
            for segment in ("A", "B"):
                self.assertAlmostEqual(observed.loc[segment, "min"], expected[segment])
                self.assertAlmostEqual(observed.loc[segment, "max"], expected[segment])
        self.assertEqual(sum(row["validation_listings_in_unseen_segment"] for row in folds), 0)

    def test_validation_outcomes_cannot_change_their_own_prediction(self):
        data = fixture()
        probability, _ = module.segment_rate_probabilities(data, data["fold"], module.PRIOR_WEIGHT)
        flipped = data.copy()
        target = flipped["fold"].eq(2).to_numpy()
        flipped.loc[target, "review_target_met"] = 1 - flipped.loc[target, "review_target_met"]
        changed, _ = module.segment_rate_probabilities(flipped, flipped["fold"], module.PRIOR_WEIGHT)
        np.testing.assert_allclose(changed[target], probability[target])
        self.assertFalse(np.allclose(changed[~target], probability[~target]))

    def test_prior_weight_shrinks_every_segment_towards_its_training_rate(self):
        data = fixture()
        raw, folds = module.segment_rate_probabilities(data, data["fold"], 0)
        shrunk, _ = module.segment_rate_probabilities(data, data["fold"], module.PRIOR_WEIGHT)
        training_rate = data["fold"].map({row["fold"]: row["training_rate"] for row in folds}).to_numpy()
        self.assertTrue(np.all(np.abs(shrunk - training_rate) <= np.abs(raw - training_rate) + 1e-12))
        self.assertFalse(np.allclose(shrunk, raw))

    def test_unseen_segment_receives_the_training_rate(self):
        data = fixture()
        data["configuration"] = "A"
        unseen = (data["fold"].eq(1) & data["host_id"].eq("1")).to_numpy()
        data.loc[unseen, "configuration"] = "B"
        probability, folds = module.segment_rate_probabilities(data, data["fold"], module.PRIOR_WEIGHT)
        np.testing.assert_allclose(probability[unseen], data.loc[data["fold"].ne(1), "review_target_met"].mean())
        self.assertEqual(folds[1]["validation_listings_in_unseen_segment"], int(unseen.sum()))

    def test_host_overlap_between_training_and_validation_is_rejected(self):
        data = fixture()
        data.loc[data.index[0], "fold"] = 1
        with self.assertRaisesRegex(ValueError, "overlaps"):
            module.segment_rate_probabilities(data, data["fold"], 0)


if __name__ == "__main__":
    unittest.main()
