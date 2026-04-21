from __future__ import annotations

import unittest
from datetime import datetime, timedelta, timezone

from autoresearch.scheduler import CandidateIssue, assess_complexity, calculate_priority, exclusion_reason, schedule_issues


class SchedulerTests(unittest.TestCase):
    def make_issue(
        self,
        *,
        number: int,
        title: str,
        body: str,
        labels: list[str],
        created_days_ago: int = 1,
        updated_days_ago: int = 1,
    ) -> CandidateIssue:
        now = datetime(2026, 4, 20, tzinfo=timezone.utc)
        created_at = (now - timedelta(days=created_days_ago)).isoformat().replace("+00:00", "Z")
        updated_at = (now - timedelta(days=updated_days_ago)).isoformat().replace("+00:00", "Z")
        return CandidateIssue(
            number=number,
            title=title,
            body=body,
            labels=labels,
            created_at=created_at,
            updated_at=updated_at,
        )

    def test_exclusion_rules(self) -> None:
        now = datetime(2026, 4, 20, tzinfo=timezone.utc)
        blocked = self.make_issue(number=1, title="Fix login", body="desc", labels=["blocked"])
        self.assertEqual(exclusion_reason(blocked, now), "excluded_label")

        draft = self.make_issue(number=2, title="[WIP] Refactor auth", body="desc", labels=[])
        self.assertEqual(exclusion_reason(draft, now), "draft_issue")

        stale = self.make_issue(number=3, title="Fix auth", body="desc", labels=[], updated_days_ago=200)
        self.assertEqual(exclusion_reason(stale, now), "stale_over_6_months")

    def test_priority_scoring(self) -> None:
        now = datetime(2026, 4, 20, tzinfo=timezone.utc)
        issue = self.make_issue(
            number=42,
            title="Fix login bug",
            body="short body",
            labels=["bug", "priority: high"],
            created_days_ago=2,
            updated_days_ago=1,
        )
        score, reasons = calculate_priority(issue, now)
        self.assertEqual(score, 110)
        self.assertIn("priority_label=+50", reasons)
        self.assertIn("type_label=+30", reasons)

    def test_complexity_assessment(self) -> None:
        simple = self.make_issue(number=1, title="Fix typo", body="tiny", labels=[])
        medium = self.make_issue(number=2, title="Implement user profile", body="x" * 180, labels=[])
        complex_issue = self.make_issue(number=3, title="Architecture redesign", body="x" * 600, labels=[])

        self.assertEqual(assess_complexity(simple).level, "simple")
        self.assertEqual(assess_complexity(medium).level, "medium")
        self.assertTrue(assess_complexity(complex_issue).requires_human_approval)

    def test_schedule_issues_orders_by_score(self) -> None:
        now = datetime(2026, 4, 20, tzinfo=timezone.utc)
        issues = [
            self.make_issue(number=1, title="Fix login bug", body="short", labels=["bug", "priority: high"]),
            self.make_issue(number=2, title="Update readme", body="tiny", labels=["documentation"]),
            self.make_issue(number=3, title="Implement export", body="medium body" * 20, labels=["feature"]),
        ]
        scheduled = schedule_issues(issues, limit=2, now=now)
        self.assertEqual([item.issue.number for item in scheduled], [1, 3])


if __name__ == "__main__":
    unittest.main()
