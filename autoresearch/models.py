from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path


SUPPORTED_AGENTS = ("claude", "codex", "opencode")
AGENT_DISPLAY_NAMES = {
    "claude": "Claude",
    "codex": "Codex",
    "opencode": "OpenCode",
}


@dataclass(slots=True)
class IssueInfo:
    number: int
    title: str
    body: str
    state: str
    labels: list[str]


@dataclass(slots=True)
class RuntimeConfig:
    issue_number: int
    project_root: Path
    max_iterations: int
    continue_mode: bool
    no_archive: bool
    agent_names: list[str]
    script_dir: Path
    github_repo: str | None = None
    default_max_iterations: int = 42
    passing_score: int = 85
    max_consecutive_failures: int = 3
    max_retries: int = 5
    retry_base_delay: int = 2
    retry_max_delay: int = 60
    max_context_retries: int = 3
    auto_merge_mode: str = "safe"
    metrics_enabled: bool = True
    lease_ttl_seconds: int = 1800
    queue_poll_interval: int = 60
    worker_id: str | None = None
    ui_verify_enabled: bool = True
    ui_verify_timeout: int = 60
    ui_dev_port: int | None = None


@dataclass(slots=True)
class WorkflowState:
    work_dir: Path | None = None
    branch_name: str = ""
    iteration: int = 0
    previous_feedback: str = ""
    final_score: int = 0
    final_review_report: str = ""
    consecutive_iteration_failures: int = 0
    context_retries: int = 0
    issue_info: IssueInfo | None = None


@dataclass(slots=True)
class IterationResult:
    passed: bool = False
    iteration_failed: bool = False
    subtask_advanced: bool = False
    hard_gate_failed: bool = False
    context_overflow: bool = False
    ui_verify_failed: bool = False
    score: int = 0
    review_log_file: Path | None = None
    review_feedback: str = ""
    extra_feedback: str = ""


@dataclass(slots=True)
class TaskItem:
    id: str
    title: str
    description: str
    acceptance_criteria: list[str] = field(default_factory=list)
    priority: int = 0
    task_type: str = "code"
    passes: bool = False

    @classmethod
    def from_payload(cls, payload: dict[str, object]) -> "TaskItem":
        criteria = payload.get("acceptanceCriteria") or []
        if not isinstance(criteria, list):
            criteria = []
        return cls(
            id=str(payload.get("id", "")),
            title=str(payload.get("title", "")),
            description=str(payload.get("description", "")),
            acceptance_criteria=[str(item) for item in criteria],
            priority=int(payload.get("priority", 0) or 0),
            task_type=str(payload.get("type", "code") or "code"),
            passes=bool(payload.get("passes", False)),
        )

    def to_payload(self) -> dict[str, object]:
        payload: dict[str, object] = {
            "id": self.id,
            "title": self.title,
            "description": self.description,
            "acceptanceCriteria": list(self.acceptance_criteria),
            "priority": self.priority,
            "passes": self.passes,
        }
        if self.task_type != "code":
            payload["type"] = self.task_type
        return payload
