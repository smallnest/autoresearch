from __future__ import annotations

import tempfile
import unittest
from datetime import date
from pathlib import Path

from autoresearch.models import RuntimeConfig
from autoresearch.runner import WorkflowRunner


class ArchiveWorkflowTests(unittest.TestCase):
    def make_runner(self, tmpdir: str, issue_number: int = 3) -> WorkflowRunner:
        root = Path(tmpdir)
        config = RuntimeConfig(
            issue_number=issue_number,
            project_root=root,
            max_iterations=3,
            continue_mode=False,
            no_archive=False,
            agent_names=["claude"],
            script_dir=root,
        )
        return WorkflowRunner(config)

    def test_archive_old_workflows(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            root = Path(tmpdir)
            workflows = root / ".autoresearch" / "workflows"
            (workflows / "issue-1").mkdir(parents=True)
            (workflows / "issue-2").mkdir(parents=True)
            (workflows / "issue-3").mkdir(parents=True)

            runner = self.make_runner(tmpdir, issue_number=3)
            runner.archive_old_workflows()

            current_date = date.today().strftime("%Y-%m-%d")
            archive = root / ".autoresearch" / "archive"
            self.assertTrue((archive / f"{current_date}-issue-1").exists())
            self.assertTrue((archive / f"{current_date}-issue-2").exists())
            self.assertTrue((workflows / "issue-3").exists())
            self.assertFalse((workflows / "issue-1").exists())

    def test_archive_adds_suffix_when_target_exists(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            root = Path(tmpdir)
            workflows = root / ".autoresearch" / "workflows"
            archive = root / ".autoresearch" / "archive"
            (workflows / "issue-1").mkdir(parents=True)
            current_date = date.today().strftime("%Y-%m-%d")
            existing = archive / f"{current_date}-issue-1"
            existing.mkdir(parents=True)
            (existing / "old.txt").write_text("old", encoding="utf-8")

            runner = self.make_runner(tmpdir, issue_number=2)
            runner.archive_old_workflows()

            self.assertTrue((archive / f"{current_date}-issue-1-1").exists())
            self.assertTrue((existing / "old.txt").exists())


if __name__ == "__main__":
    unittest.main()
