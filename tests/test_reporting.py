from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from autoresearch.reporting import format_metrics_summary, load_metrics, summarize_metrics


class ReportingTests(unittest.TestCase):
    def test_empty_metrics_summary(self) -> None:
        summary = summarize_metrics([])
        self.assertEqual(format_metrics_summary(summary), "暂无运行指标。")

    def test_summary_from_metrics(self) -> None:
        events = [
            {"event": "run_finished", "status": "completed", "iterations": 3, "final_score": 92},
            {"event": "run_finished", "status": "awaiting_approval", "iterations": 4, "final_score": 88},
            {"event": "run_finished", "status": "finalize_failed", "iterations": 2, "final_score": 75},
            {"event": "finalization", "auto_merged": True},
            {"event": "finalization", "auto_merged": False},
        ]
        summary = summarize_metrics(events)
        formatted = format_metrics_summary(summary)
        self.assertEqual(summary.total_runs, 3)
        self.assertEqual(summary.completed_runs, 1)
        self.assertEqual(summary.awaiting_approval_runs, 1)
        self.assertEqual(summary.failed_runs, 1)
        self.assertIn("Auto merged: 1", formatted)
        self.assertIn("Avg score: 85.00", formatted)

    def test_load_metrics(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            path = Path(tmpdir) / "metrics.jsonl"
            path.write_text('{"event":"run_finished","status":"completed","iterations":1,"final_score":90}\n', encoding="utf-8")
            metrics = load_metrics(path)
            self.assertEqual(len(metrics), 1)
            self.assertEqual(metrics[0]["status"], "completed")


if __name__ == "__main__":
    unittest.main()
