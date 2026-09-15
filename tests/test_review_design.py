"""Regression checks for separation of benchmark development and model outcomes.

Run with: python -m unittest discover -s tests -v
"""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

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
                "last_scraped_date": pd.Timestamp("2026-07-01"),
                "reviews_365d": reviews[index % len(reviews)],
            })

    add("Cell A", 50, "analysis", [0, 10])
    add("Cell B", 49, "analysis", [0, 10])
    add("Cell A", len(benchmark_reviews), "benchmark_development", benchmark_reviews)
    add("Cell B", 4, "benchmark_development", [1000])
    return pd.DataFrame(rows)


class ReviewDesignTests(unittest.TestCase):
    def test_established_uses_each_scrape_date_and_keeps_zero_reviews(self):
        data = fixture().iloc[:4].copy()
        data["first_review_date"] = pd.Timestamp("2025-07-01")
        data["last_scraped_date"] = pd.to_datetime(["2026-07-01", "2026-06-30", "2026-07-02", "2026-07-01"])
        data.loc[data.index[-1], "first_review_date"] = pd.NaT
        data["reviews_365d"] = 0
        eligible = design.eligible_base(data)
        self.assertEqual(list(eligible.id), list(data.iloc[[0, 2]].id))
        self.assertTrue(eligible.reviews_365d.eq(0).all())
        self.assertEqual(len(design.eligible_base(data, established=False)), 4)

    def test_scrape_dates_are_required_and_first_review_is_not_launch_date(self):
        data = pd.DataFrame({"first_review": [None, "2025-07-01"], "last_scraped": ["2026-07-01"] * 2})
        self.assertTrue(pd.isna(design.observation_dates(data).iloc[0].first_review_date))
        with self.assertRaisesRegex(ValueError, "last_scraped"):
            design.observation_dates(data.drop(columns="last_scraped"))
        for value in (None, "2026-99-01", 20260617, "2026/06/17", "2026-6-17"):
            with self.subTest(scrape=value), self.assertRaisesRegex(ValueError, "last_scraped"):
                design.observation_dates(data.assign(last_scraped=value))
        for value in ("not a date", "2026-07-02"):
            with self.subTest(first_review=value), self.assertRaisesRegex(ValueError, "first_review"):
                design.observation_dates(data.assign(first_review=value))

    def test_analysis_outcomes_cannot_change_benchmark_cutoff(self):
        data = fixture()
        benchmark = data.loc[data.host_role.eq("benchmark_development")]
        analysis = data.loc[data.host_role.eq("analysis")]
        _, cells, _ = design.make_scope(analysis)
        reference, quantile, cutoff = design.develop_benchmark(benchmark, cells)
        changed = analysis.copy()
        changed["reviews_365d"] = range(1000, 1000 + len(changed))
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


class RawReviewValidationTests(unittest.TestCase):
    def test_raw_csv_preserves_identifiers_amenity_names_and_lga_alignment(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "data/raw").mkdir(parents=True)
            listing = {
                "id": "1000000000000000001", "host_id": "1234567890123456789", "price": "$120.00",
                "bathrooms_text": "1.5 baths", "amenities": json.dumps(["Wifi", 'TV, 43" screen']),
                "bedrooms": 1, "accommodates": 2, "minimum_nights": 1, "number_of_reviews_ltm": 0,
                "first_review": "2025-07-01", "last_scraped": "2026-07-01",
                "neighbourhood_cleansed": "Moreland", "property_type": "Entire rental unit",
            }
            pd.DataFrame([listing]).to_csv(root / "data/raw/listings_airbnb.csv", index=False)
            for name in ("calendar", "reviews"):
                (root / f"data/raw/{name}_airbnb.csv").write_text("listing_id,date\n")
            with patch.object(design, "ROOT", root):
                frame, provenance = design.read_source()
            self.assertEqual(frame.iloc[0].id, listing["id"])
            self.assertEqual(frame.iloc[0].host_id, listing["host_id"])
            self.assertEqual(frame.iloc[0].n_amenities, 2)
            self.assertEqual(frame.iloc[0].bathrooms_num, 1.5)
            self.assertEqual(frame.iloc[0].neighbourhood_cleansed, "Merri-bek")
            self.assertEqual(len(provenance["raw_file_sha256"]), 3)

    def validate(self, frame, reviews):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "data/raw").mkdir(parents=True)
            reviews.to_csv(root / "data/raw/reviews_airbnb.csv", index=False)
            with patch.object(design, "ROOT", root), patch.object(design, "PRIVATE_OUTPUT", root):
                return design.reconstruct_raw_reviews(frame, {"source_kind": "raw_listings"})

    def test_365_dates_boundary_leap_year_and_zero_counts(self):
        frame = pd.DataFrame({"id": ["1", "2", "3"], "last_scraped": ["2026-07-01", "2024-03-01", "2026-07-01"], "number_of_reviews_ltm": [3, 3, 0]})
        reviews = pd.DataFrame({
            "listing_id": ["1", "1", "1", "2", "2", "2"],
            "date": ["2025-07-01", "2025-07-02", "2026-07-01", "2023-03-02", "2023-03-03", "2024-03-01"],
        })
        rebuilt, result = self.validate(frame, reviews)
        self.assertEqual(list(rebuilt.reviews_365d), [2, 2, 0])
        self.assertEqual(list(rebuilt.number_of_reviews_ltm), [3, 3, 0])
        self.assertTrue(result["passed"])
        self.assertEqual(result["validation_listings"], 3)
        self.assertEqual(result["validation_population"], "all source listings")
        self.assertEqual(result["source_ltm_exact_match_share"], 1)
        self.assertEqual(result["listings_with_boundary_day_reviews"], 2)

    def test_completed_check_does_not_pass_mismatches_or_invalid_rows(self):
        frame = pd.DataFrame({"id": ["1"], "last_scraped": ["2026-07-01"], "number_of_reviews_ltm": [0]})
        cases = [
            ("1", "2026-07-01", "source_ltm_mismatched_listings"),
            ("1", "2026-07-02", "future_review_dates"),
            ("1", "invalid", "invalid_review_dates"),
            ("999", "2026-07-01", "unknown_listing_id_rows"),
            (None, "2026-07-01", "missing_listing_id_rows"),
        ]
        for listing_id, date, failure in cases:
            with self.subTest(failure=failure):
                _, result = self.validate(frame, pd.DataFrame({"listing_id": [listing_id], "date": [date]}))
                self.assertEqual(result["status"], "completed")
                self.assertFalse(result["passed"])
                self.assertEqual(result[failure], 1)

    def test_missing_raw_inputs_do_not_fall_back_to_cached_data(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "data/processed").mkdir(parents=True)
            (root / "data/processed/listings_clean.rds").write_text("stale snapshot")
            with patch.object(design, "ROOT", root), self.assertRaisesRegex(FileNotFoundError, "school-supplied"):
                design.read_source()


class OutputPublicationTests(unittest.TestCase):
    def test_failed_analysis_leaves_previous_outputs_unchanged(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            public, private = root / "reports/tables", root / "data/processed"
            public.mkdir(parents=True)
            private.mkdir(parents=True)
            (public / "old.csv").write_text("old public")
            (private / "old.csv").write_text("old private")

            def failed_run():
                (design.OUTPUT / "old.csv").write_text("partial public")
                (design.PRIVATE_OUTPUT / "new.csv").write_text("partial private")
                raise ValueError("Validation failed")

            with patch.object(design, "OUTPUT", public), patch.object(design, "PRIVATE_OUTPUT", private), patch.object(design, "run_analysis", failed_run):
                with self.assertRaisesRegex(ValueError, "Validation failed"):
                    design.main()
                self.assertEqual(design.OUTPUT, public)
                self.assertEqual(design.PRIVATE_OUTPUT, private)
            self.assertEqual((public / "old.csv").read_text(), "old public")
            self.assertEqual((private / "old.csv").read_text(), "old private")
            self.assertEqual(sorted(path.name for path in private.iterdir()), ["old.csv"])

    def test_publication_error_rolls_back_files_already_replaced(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            stage, destination = root / "stage", root / "destination"
            stage.mkdir()
            destination.mkdir()
            (stage / "a.csv").write_text("new a")
            (stage / "b.csv").write_text("new b")
            (destination / "a.csv").write_text("original a")
            replace = Path.replace

            def fail_second(source, target):
                if source.name == "b.csv":
                    raise OSError("Disk write failed")
                return replace(source, target)

            with patch.object(Path, "replace", fail_second), self.assertRaisesRegex(OSError, "Disk write failed"):
                design.publish_outputs([(stage, destination)])
            self.assertEqual((destination / "a.csv").read_text(), "original a")
            self.assertFalse((destination / "b.csv").exists())


if __name__ == "__main__":
    unittest.main()
