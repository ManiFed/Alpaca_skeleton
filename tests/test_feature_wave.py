#!/usr/bin/env python3
"""Focused tests for the timeline/explanation/activity feature wave."""

import unittest

from cloud import scheduler, scoring


class ScoreExplanationTest(unittest.TestCase):
    def test_explain_score_ranks_weighted_factors(self):
        explanation = scoring.explain_score(
            {"target_type": "CV"},
            {"node_id": "node_a"},
            {
                "brightness": 0.4,
                "science": 1.0,
                "time": 0.8,
                "coverage": 0.2,
                "observe": 0.9,
                "best_alt_deg": 67.2,
                "visibility_minutes": 180,
                "reliability_score": 0.75,
            },
            {
                "brightness": 0.2,
                "science": 0.25,
                "time": 0.15,
                "coverage": 0.15,
                "observe": 0.25,
            },
        )

        self.assertIn("Strongest factors", explanation["summary"])
        self.assertEqual(explanation["factors"][0]["key"], "science")
        self.assertEqual(explanation["node_id"], "node_a")
        self.assertEqual(explanation["best_alt_deg"], 67.2)


class LongitudeDiversityTest(unittest.TestCase):
    def test_reserved_nearby_wraps_across_dateline(self):
        reservations = {"T": [179.0]}

        self.assertTrue(scheduler._reserved_nearby(reservations, "T", -179.0, 5.0))
        self.assertFalse(scheduler._reserved_nearby(reservations, "T", -150.0, 5.0))


if __name__ == "__main__":
    unittest.main()
