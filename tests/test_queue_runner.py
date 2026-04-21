from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from autoresearch.github import GitHubClient
from autoresearch.lease import LeaseManager
from autoresearch.models import RuntimeConfig
from autoresearch.queue_runner import QueueRunner


class FakeGitHub(GitHubClient):
    def __init__(self, project_root: Path, issues: list[dict[str, object]]):
        super().__init__(project_root)
        self._issues = issues

    def ensure_authenticated(self) -> None:
        return None

    def list_open_issues(self, limit: int = 100) -> list[dict[str, object]]:
        return self._issues[:limit]


class FakeRunner:
    runs: list[int] = []

    def __init__(self, config: RuntimeConfig):
        self.config = config

    def run(self, requested_continue_iterations=None) -> int:
        FakeRunner.runs.append(self.config.issue_number)
        return 0


class QueueRunnerTests(unittest.TestCase):
    def make_issue(self, number: int, title: str, body: str, labels: list[str]) -> dict[str, object]:
        return {
            "number": number,
            "title": title,
            "body": body,
            "labels": [{"name": label} for label in labels],
            "createdAt": "2026-04-20T00:00:00Z",
            "updatedAt": "2026-04-20T00:00:00Z",
        }

    def test_run_batch_processes_unleased_issues(self) -> None:
        FakeRunner.runs = []
        with tempfile.TemporaryDirectory() as tmpdir:
            root = Path(tmpdir)
            config = RuntimeConfig(
                issue_number=0,
                project_root=root,
                max_iterations=42,
                continue_mode=False,
                no_archive=False,
                agent_names=["claude"],
                script_dir=root,
            )
            github = FakeGitHub(
                root,
                [
                    self.make_issue(1, "Fix login bug", "short body", ["bug"]),
                    self.make_issue(2, "Implement export", "x" * 200, ["feature"]),
                ],
            )
            lease_manager = LeaseManager(root / ".autoresearch" / "leases")
            leased = lease_manager.acquire("issue-1", "other-worker", ttl_seconds=60)
            assert leased is not None
            runner = QueueRunner(
                config,
                github=github,
                lease_manager=lease_manager,
                runner_cls=FakeRunner,
            )
            result = runner.run_batch(2)
            self.assertEqual(result.processed, 1)
            self.assertEqual(result.skipped_leased, 1)
            self.assertEqual(FakeRunner.runs, [2])


if __name__ == "__main__":
    unittest.main()
