from __future__ import annotations

import unittest

from autoresearch.logic import check_sentinel, extract_score, has_api_failure, has_fatal_error


class ExtractScoreTests(unittest.TestCase):
    def test_extract_percentage_score(self) -> None:
        self.assertEqual(extract_score("**评分: 88/100**"), 88)
        self.assertEqual(extract_score("Score: 91/100"), 91)

    def test_extract_total_line(self) -> None:
        self.assertEqual(extract_score("总分 | 正确性 | **8.5**"), 85)

    def test_extract_ten_point_score(self) -> None:
        self.assertEqual(extract_score("评分: 8.6/10"), 86)
        self.assertEqual(extract_score("**Score: 9**"), 90)

    def test_unknown_score_returns_zero(self) -> None:
        self.assertEqual(extract_score("没有任何分数"), 0)

    def test_sentinel_detection(self) -> None:
        self.assertEqual(check_sentinel("foo\nAUTORESEARCH_RESULT:PASS\n"), "pass")
        self.assertEqual(check_sentinel("foo\nAUTORESEARCH_RESULT:FAIL\n"), "fail")
        self.assertEqual(check_sentinel("foo\nbar\n"), "none")

    def test_error_detectors(self) -> None:
        self.assertTrue(has_fatal_error("Error: context length exceeded"))
        self.assertTrue(has_api_failure("HTTP 500 server error"))
        self.assertFalse(has_fatal_error("Use error handling for invalid input"))
        self.assertFalse(has_api_failure("request succeeded"))


if __name__ == "__main__":
    unittest.main()
