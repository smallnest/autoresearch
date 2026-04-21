from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from autoresearch.review_schema import format_review_feedback, parse_review_report, write_review_report


class ReviewSchemaTests(unittest.TestCase):
    def test_parse_structured_review_report(self) -> None:
        review_text = """
总体结论：实现存在缺陷，需要继续修复。

```json
{
  "pass": false,
  "score": 72,
  "riskLevel": "medium",
  "findings": [
    {
      "severity": "high",
      "summary": "缺少 404 分支测试",
      "path": "tests/test_api.py"
    }
  ],
  "requiredFixes": [
    "补充 404 分支测试",
    "修复错误响应格式"
  ]
}
```
"""
        report = parse_review_report(review_text, passing_score=85)
        self.assertFalse(report.passed)
        self.assertEqual(report.score, 72)
        self.assertEqual(report.risk_level, "medium")
        self.assertEqual(len(report.findings), 1)
        self.assertEqual(report.findings[0].path, "tests/test_api.py")
        self.assertEqual(report.required_fixes, ["补充 404 分支测试", "修复错误响应格式"])
        self.assertEqual(report.source, "json")

    def test_parse_sentinel_review_report(self) -> None:
        report = parse_review_report("AUTORESEARCH_RESULT:PASS", passing_score=85)
        self.assertTrue(report.passed)
        self.assertEqual(report.score, 100)
        self.assertEqual(report.source, "sentinel")

    def test_parse_heuristic_review_report(self) -> None:
        report = parse_review_report("**评分: 87/100**", passing_score=85)
        self.assertTrue(report.passed)
        self.assertEqual(report.score, 87)
        self.assertEqual(report.source, "heuristic")

    def test_format_review_feedback(self) -> None:
        report = parse_review_report(
            """
```json
{
  "pass": false,
  "score": 68,
  "riskLevel": "high",
  "findings": [
    {"severity": "high", "summary": "空值处理错误", "path": "src/service.py"}
  ],
  "requiredFixes": ["修复空值处理"]
}
```
""",
            passing_score=85,
        )
        feedback = format_review_feedback(report)
        self.assertIn("必修复项", feedback)
        self.assertIn("修复空值处理", feedback)
        self.assertIn("src/service.py", feedback)

    def test_write_review_report(self) -> None:
        report = parse_review_report("**评分: 91/100**", passing_score=85)
        with tempfile.TemporaryDirectory() as tmpdir:
            path = Path(tmpdir) / "review.json"
            write_review_report(report, path)
            content = path.read_text(encoding="utf-8")
            self.assertIn('"score": 91', content)
            self.assertIn('"passed": true', content)


if __name__ == "__main__":
    unittest.main()
