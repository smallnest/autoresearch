from __future__ import annotations

from dataclasses import dataclass, replace

from .github import GitHubClient, GitHubError
from .lease import LeaseManager, default_worker_id
from .models import RuntimeConfig
from .runner import RunnerError, WorkflowRunner
from .scheduler import CandidateIssue, ScheduledIssue, schedule_issues
from .telemetry import MetricsRecorder


@dataclass(slots=True)
class QueueRunResult:
    processed: int = 0
    succeeded: int = 0
    failed: int = 0
    skipped_leased: int = 0
    selected: int = 0


class QueueRunner:
    def __init__(
        self,
        config: RuntimeConfig,
        *,
        github: GitHubClient | None = None,
        metrics: MetricsRecorder | None = None,
        lease_manager: LeaseManager | None = None,
        runner_cls=WorkflowRunner,
    ):
        self.config = config
        self.github = github or GitHubClient(config.project_root, repo=config.github_repo)
        self.metrics = metrics or MetricsRecorder(config.project_root, enabled=config.metrics_enabled)
        self.lease_manager = lease_manager or LeaseManager(config.project_root / ".autoresearch" / "leases")
        self.runner_cls = runner_cls
        self.worker_id = config.worker_id or default_worker_id()

    def run_batch(self, batch_size: int) -> QueueRunResult:
        result = QueueRunResult()
        scheduled = self._fetch_candidates(max(batch_size * 5, 30))
        result.selected = len(scheduled)
        for item in scheduled:
            if result.processed >= batch_size:
                break
            if item.complexity.requires_human_approval:
                continue
            lease = self.lease_manager.acquire(f"issue-{item.issue.number}", self.worker_id, self.config.lease_ttl_seconds)
            if lease is None:
                result.skipped_leased += 1
                self.metrics.record(
                    "issue_skipped_leased",
                    issue_number=item.issue.number,
                    worker_id=self.worker_id,
                )
                continue
            with lease:
                self.metrics.record(
                    "issue_selected",
                    issue_number=item.issue.number,
                    priority_score=item.priority_score,
                    complexity=item.complexity.level,
                    requires_human_approval=item.complexity.requires_human_approval,
                    reasons=item.reasons,
                    worker_id=self.worker_id,
                )
                issue_config = replace(
                    self.config,
                    issue_number=item.issue.number,
                    max_iterations=(
                        self.config.max_iterations
                        if self.config.max_iterations != self.config.default_max_iterations
                        else item.complexity.max_iterations
                    ),
                    worker_id=self.worker_id,
                )
                runner = self.runner_cls(issue_config)
                try:
                    status = runner.run()
                except RunnerError:
                    status = 1
                result.processed += 1
                if status == 0:
                    result.succeeded += 1
                else:
                    result.failed += 1
        return result

    def _fetch_candidates(self, limit: int) -> list[ScheduledIssue]:
        self.github.ensure_authenticated()
        raw_issues = self.github.list_open_issues(limit=limit)
        issues = [CandidateIssue.from_payload(item) for item in raw_issues]
        return schedule_issues(issues, limit=limit)
