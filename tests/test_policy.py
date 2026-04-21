from __future__ import annotations

import unittest
from pathlib import Path

from autoresearch.models import IssueInfo, RuntimeConfig
from autoresearch.policy import evaluate_merge_policy


class MergePolicyTests(unittest.TestCase):
    def make_config(self, auto_merge_mode: str = "safe") -> RuntimeConfig:
        return RuntimeConfig(
            issue_number=1,
            project_root=Path(".").resolve(),
            max_iterations=3,
            continue_mode=False,
            no_archive=False,
            agent_names=["claude"],
            script_dir=Path(".").resolve(),
            auto_merge_mode=auto_merge_mode,
        )

    def make_issue(self, *, title: str, body: str, labels: list[str]) -> IssueInfo:
        return IssueInfo(number=1, title=title, body=body, state="OPEN", labels=labels)

    def test_safe_issue_auto_merges(self) -> None:
        decision = evaluate_merge_policy(
            self.make_issue(title="Fix login bug", body="short body", labels=["bug"]),
            self.make_config(),
        )
        self.assertTrue(decision.auto_merge)
        self.assertFalse(decision.requires_human_approval)

    def test_complex_issue_requires_human_approval(self) -> None:
        decision = evaluate_merge_policy(
            self.make_issue(title="Architecture redesign", body="x" * 700, labels=["feature"]),
            self.make_config(),
        )
        self.assertFalse(decision.auto_merge)
        self.assertTrue(decision.requires_human_approval)
        self.assertIn("complexity=complex", decision.reasons)

    def test_high_risk_label_requires_human_approval(self) -> None:
        decision = evaluate_merge_policy(
            self.make_issue(title="Update auth flow", body="short body", labels=["auth"]),
            self.make_config(),
        )
        self.assertFalse(decision.auto_merge)
        self.assertTrue(decision.requires_human_approval)

    def test_always_mode_overrides_policy(self) -> None:
        decision = evaluate_merge_policy(
            self.make_issue(title="Architecture redesign", body="x" * 700, labels=["auth"]),
            self.make_config(auto_merge_mode="always"),
        )
        self.assertTrue(decision.auto_merge)
        self.assertFalse(decision.requires_human_approval)

    def test_never_mode_disables_auto_merge(self) -> None:
        decision = evaluate_merge_policy(
            self.make_issue(title="Fix login bug", body="short body", labels=["bug"]),
            self.make_config(auto_merge_mode="never"),
        )
        self.assertFalse(decision.auto_merge)
        self.assertTrue(decision.requires_human_approval)


if __name__ == "__main__":
    unittest.main()
