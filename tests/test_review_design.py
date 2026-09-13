"""Regression checks for separation of benchmark development and model outcomes.

Run with: python -m unittest discover -s tests -v
"""
import importlib.util
from pathlib import Path
import unittest

import pandas as pd

SCRIPT = Path(__file__).resolve().parents[1] / "scripts" / "rq_scope_feasibility.py"
spec = importlib.util.spec_from_file_location("review_design", SCRIPT)
design = importlib.util.module_from_spec(spec)
spec.loader.exec_module(design)


def fixture(benchmark_reviews=(0, 1, 2, 3)):
    """Cell A has 50 analysis rows; B reaches 50 only if benchmark rows leak in."""
    roles = {"analysis": [], "benchmark_development": []}
    for value in range(1, 100):
        host = str(value)
        roles[design.host_role(host)].append(host)
    rows = []

    def add(cell, n, role, reviews):
        for index in range(n):
            rows.append({
                "id": str(len(rows) + 1), "host_id": roles[role][index % 2], "host_role": role,
                "room_type": "Entire home/apt", "bedrooms": 1,
                "dwelling_class": "Apartment/unit", "property_type": "Entire rental unit",
                "neighbourhood_cleansed": cell, "price_num": 100,
                "first_review_date": pd.Timestamp("2024-01-01"),
                "number_of_reviews_ltm": reviews[index % len(reviews)],
            })

    add("Cell A", 50, "analysis", [0, 10])
    add("Cell B", 49, "analysis", [0, 10])
    add("Cell A", len(benchmark_reviews), "benchmark_development", benchmark_reviews)
    add("Cell B", 4, "benchmark_development", [1000])
    return pd.DataFrame(rows)


class ReviewDesignTests(unittest.TestCase):
    def test_analysis_outcomes_cannot_change_benchmark_cutoff(self):
        data = fixture()
        benchmark = data.loc[data.host_role.eq("benchmark_development")]
        analysis = data.loc[data.host_role.eq("analysis")]
        _, cells, _ = design.make_scope(analysis)
        reference, quantile, cutoff = design.develop_benchmark(benchmark, cells)
        changed = analysis.copy()
        changed["number_of_reviews_ltm"] = range(1000, 1000 + len(changed))
        _, changed_cells, _ = design.make_scope(changed)
        changed_reference, changed_quantile, changed_cutoff = design.develop_benchmark(benchmark, changed_cells)
        self.assertEqual((quantile, cutoff), (changed_quantile, changed_cutoff))
        self.assertEqual(set(reference.id), set(changed_reference.id))
        self.assertEqual(set(reference.neighbourhood_cleansed), {"Cell A"})

    def test_roles_are_host_level_and_guards_reject_mixed_pools(self):
        data = fixture()
        self.assertEqual(data.groupby("host_id").host_role.nunique().max(), 1)
        benchmark_hosts = set(data.loc[data.host_role.eq("benchmark_development"), "host_id"])
        analysis_hosts = set(data.loc[data.host_role.eq("analysis"), "host_id"])
        self.assertFalse(benchmark_hosts & analysis_hosts)
        self.assertEqual(design.host_role(design.canonical_id("1e5")), design.host_role(design.canonical_id("100000")))
        with self.assertRaisesRegex(ValueError, "removed before"):
            design.make_scope(data)
        _, cells, _ = design.make_scope(data.loc[data.host_role.eq("analysis")])
        with self.assertRaisesRegex(ValueError, "benchmark hosts only"):
            design.develop_benchmark(data, cells)

    def test_minimum_support_is_applied_after_benchmark_removal(self):
        data = fixture()
        self.assertGreaterEqual(len(data.loc[data.neighbourhood_cleansed.eq("Cell B")]), 50)
        analysis = data.loc[data.host_role.eq("analysis")]
        sample, cells, _ = design.make_scope(analysis)
        self.assertEqual(len(sample), 50)
        self.assertEqual(set(cells.neighbourhood_cleansed), {"Cell A"})
        self.assertTrue(sample.groupby(design.CELL_KEYS).size().ge(50).all())
        with self.assertRaisesRegex(ValueError, "No eligible segments"):
            design.make_scope(analysis.drop(analysis.index[0]))

    def test_fractional_quantile_is_rounded_up_and_ties_are_retained(self):
        data = fixture([0, 1, 2, 3])
        _, cells, _ = design.make_scope(data.loc[data.host_role.eq("analysis")])
        reference, quantile, cutoff = design.develop_benchmark(data.loc[data.host_role.eq("benchmark_development")], cells)
        self.assertEqual(quantile, 2.25)
        self.assertEqual(cutoff, 3)
        labelled = design.attach_outcome(reference, cutoff)
        self.assertEqual(int(labelled.review_target_met.sum()), 1)
        tied = fixture([0, 2, 2, 2])
        reference, quantile, cutoff = design.develop_benchmark(tied.loc[tied.host_role.eq("benchmark_development")], cells)
        self.assertEqual((quantile, cutoff), (2, 2))
        self.assertEqual(design.attach_outcome(reference, cutoff).review_target_met.mean(), .75)


if __name__ == "__main__":
    unittest.main()
