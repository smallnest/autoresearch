from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

from autoresearch.telemetry import MetricsRecorder


class TelemetryTests(unittest.TestCase):
    def test_record_metrics_event(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            root = Path(tmpdir)
            recorder = MetricsRecorder(root, enabled=True)
            recorder.record("issue_selected", issue_number=42, priority_score=110)
            path = root / ".autoresearch" / "metrics.jsonl"
            self.assertTrue(path.exists())
            lines = path.read_text(encoding="utf-8").splitlines()
            self.assertEqual(len(lines), 1)
            payload = json.loads(lines[0])
            self.assertEqual(payload["event"], "issue_selected")
            self.assertEqual(payload["issue_number"], 42)
            self.assertEqual(payload["priority_score"], 110)

    def test_disabled_recorder_does_not_write(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            root = Path(tmpdir)
            recorder = MetricsRecorder(root, enabled=False)
            recorder.record("run_finished", issue_number=1)
            self.assertFalse((root / ".autoresearch" / "metrics.jsonl").exists())


if __name__ == "__main__":
    unittest.main()
