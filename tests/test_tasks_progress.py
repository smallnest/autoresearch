from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

from autoresearch.progress import ProgressManager
from autoresearch.tasks import TaskManager


class TaskManagerTests(unittest.TestCase):
    def test_save_and_advance_tasks(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            manager = TaskManager(Path(tmpdir))
            count = manager.save_payload(
                {
                    "issueNumber": 42,
                    "subtasks": [
                        {
                            "id": "T-002",
                            "title": "Second",
                            "description": "later",
                            "acceptanceCriteria": ["b"],
                            "priority": 2,
                            "passes": False,
                        },
                        {
                            "id": "T-001",
                            "title": "First",
                            "description": "first",
                            "acceptanceCriteria": ["a"],
                            "priority": 1,
                            "type": "ui",
                            "passes": False,
                        },
                    ],
                }
            )
            self.assertEqual(count, 2)
            self.assertEqual([item.id for item in manager.items()], ["T-001", "T-002"])
            self.assertEqual(manager.current_id(), "T-001")
            self.assertTrue(manager.is_ui_current())
            self.assertIn("UI 类型任务", manager.subtask_section())

            manager.mark_passed("T-001")
            self.assertEqual(manager.current_id(), "T-002")
            self.assertFalse(manager.all_passed())

            manager.mark_passed("T-002")
            self.assertTrue(manager.all_passed())

    def test_review_section_for_completed_tasks(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            manager = TaskManager(Path(tmpdir))
            manager.path.write_text(
                json.dumps(
                    {
                        "issueNumber": 1,
                        "subtasks": [
                            {
                                "id": "T-001",
                                "title": "Done",
                                "description": "done",
                                "acceptanceCriteria": ["ok"],
                                "priority": 1,
                                "passes": True,
                            }
                        ],
                    }
                ),
                encoding="utf-8",
            )
            self.assertIn("所有子任务已完成审核", manager.review_section())


class ProgressManagerTests(unittest.TestCase):
    def test_append_and_section(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            work_dir = Path(tmpdir)
            progress = ProgressManager(work_dir, issue_number=42)
            progress.init()
            log_file = work_dir / "iteration-1.log"
            log_file.write_text(
                "## Learnings\n- 先复用现有 service 层\n- 再补测试\n",
                encoding="utf-8",
            )
            progress.append(1, "claude", log_file, 88, "审核+修复", "修复 API 响应")
            content = progress.content()
            section = progress.section()
            self.assertIn("Iteration 1", content)
            self.assertIn("修复 API 响应", content)
            self.assertIn("先复用现有 service 层", content)
            self.assertIn("跨迭代经验", section)


if __name__ == "__main__":
    unittest.main()
