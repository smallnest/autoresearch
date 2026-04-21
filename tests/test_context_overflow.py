from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from autoresearch.logic import detect_context_overflow_file, detect_context_overflow_text
from autoresearch.models import RuntimeConfig
from autoresearch.runner import WorkflowRunner


class ContextOverflowDetectionTests(unittest.TestCase):
    def test_detect_context_overflow_signals(self) -> None:
        positive_cases = [
            "Error: context length exceeded",
            "context_length_exceeded",
            "maximum context length is 128000 tokens",
            "token_limit_reached: input too long",
            "too many tokens in request",
            "input exceeds the maximum number of tokens allowed",
            "CONTEXT WINDOW EXCEEDED",
        ]
        for value in positive_cases:
            with self.subTest(value=value):
                self.assertTrue(detect_context_overflow_text(value))

    def test_ignore_normal_output(self) -> None:
        negative_cases = [
            "Implementation complete\nTests passing",
            "The context object provides request-scoped data",
            "JWT token generation",
            "Maximum retry attempts should be 3",
        ]
        for value in negative_cases:
            with self.subTest(value=value):
                self.assertFalse(detect_context_overflow_text(value))

    def test_detect_from_file(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            path = Path(tmpdir) / "overflow.log"
            path.write_text("Error: token limit exceeded", encoding="utf-8")
            self.assertTrue(detect_context_overflow_file(path))
            self.assertFalse(detect_context_overflow_file(Path(tmpdir) / "missing.log"))


class HandleContextOverflowTests(unittest.TestCase):
    def make_runner(self, tmpdir: str) -> WorkflowRunner:
        config = RuntimeConfig(
            issue_number=42,
            project_root=Path(tmpdir),
            max_iterations=5,
            continue_mode=False,
            no_archive=False,
            agent_names=["claude"],
            script_dir=Path(tmpdir),
        )
        runner = WorkflowRunner(config)
        runner.state.work_dir = Path(tmpdir) / ".autoresearch" / "workflows" / "issue-42"
        runner.work_dir.mkdir(parents=True, exist_ok=True)
        runner.progress.init()
        (runner.work_dir / "log.md").write_text("# Issue #42 实现日志\n", encoding="utf-8")
        return runner

    def test_handle_context_overflow(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            runner = self.make_runner(tmpdir)
            overflow_log = runner.work_dir / "overflow.log"
            overflow_log.write_text("Error: context length exceeded", encoding="utf-8")

            handled = runner.handle_context_overflow(1, "claude", overflow_log)

            self.assertTrue(handled)
            self.assertEqual(runner.state.context_retries, 1)
            self.assertEqual(runner.state.consecutive_iteration_failures, 0)
            self.assertIn("上下文溢出", runner.state.previous_feedback)
            self.assertIn("上下文溢出交接", (runner.work_dir / "progress.md").read_text(encoding="utf-8"))
            self.assertIn("自动交接", (runner.work_dir / "log.md").read_text(encoding="utf-8"))

    def test_handle_context_overflow_respects_max_retries(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            runner = self.make_runner(tmpdir)
            runner.state.context_retries = runner.config.max_context_retries
            overflow_log = runner.work_dir / "overflow.log"
            overflow_log.write_text("Error: context length exceeded", encoding="utf-8")

            handled = runner.handle_context_overflow(1, "claude", overflow_log)

            self.assertFalse(handled)
            self.assertEqual(runner.state.context_retries, runner.config.max_context_retries + 1)


if __name__ == "__main__":
    unittest.main()
