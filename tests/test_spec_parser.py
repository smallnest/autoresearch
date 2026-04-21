from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from autoresearch.spec_parser import parse_prd_markdown


class SpecParserTests(unittest.TestCase):
    def test_parse_prd_markdown(self) -> None:
        content = """# PRD: Example Product

## Introduction

Build a dashboard for engineers.

## User Stories

### US-001: Select project
**Description:** As a developer, I want to select a project directory.

**Acceptance Criteria:**
- [ ] Can choose a directory
- [ ] Remembers last project

### US-002: Start run
**Description:** As a developer, I want to start an issue run.

**Acceptance Criteria:**
- [ ] Can start a run
"""
        with tempfile.TemporaryDirectory() as tmpdir:
            path = Path(tmpdir) / "prd.md"
            path.write_text(content, encoding="utf-8")
            spec = parse_prd_markdown(path)
            self.assertEqual(spec.title, "PRD: Example Product")
            self.assertIn("dashboard", spec.introduction)
            self.assertEqual(len(spec.user_stories), 2)
            self.assertEqual(spec.user_stories[0].story_id, "US-001")
            self.assertEqual(spec.user_stories[0].acceptance_criteria[0], "Can choose a directory")


if __name__ == "__main__":
    unittest.main()
