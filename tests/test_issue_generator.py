from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

from autoresearch.issue_generator import generate_issue_drafts, write_issue_drafts
from autoresearch.spec_parser import ProductSpec, UserStory


class IssueGeneratorTests(unittest.TestCase):
    def test_generate_issue_drafts(self) -> None:
        spec = ProductSpec(
            title="PRD: Example",
            introduction="Intro",
            user_stories=[
                UserStory(
                    story_id="US-001",
                    title="Select project",
                    description="Choose a project directory",
                    acceptance_criteria=["Can choose a directory", "Remembers last project"],
                )
            ],
        )
        drafts = generate_issue_drafts(spec, default_labels=["desktop-app"])
        self.assertEqual(len(drafts), 1)
        self.assertEqual(drafts[0].title, "US-001: Select project")
        self.assertIn("## Acceptance Criteria", drafts[0].body)
        self.assertEqual(drafts[0].labels, ["desktop-app"])

    def test_write_issue_drafts(self) -> None:
        spec = ProductSpec(
            title="PRD: Example",
            introduction="Intro",
            user_stories=[
                UserStory(
                    story_id="US-001",
                    title="Select project",
                    description="Choose a project directory",
                    acceptance_criteria=["Can choose a directory"],
                )
            ],
        )
        drafts = generate_issue_drafts(spec)
        with tempfile.TemporaryDirectory() as tmpdir:
            path = Path(tmpdir) / "issues.json"
            write_issue_drafts(drafts, path)
            payload = json.loads(path.read_text(encoding="utf-8"))
            self.assertEqual(payload[0]["story_id"], "US-001")


if __name__ == "__main__":
    unittest.main()
