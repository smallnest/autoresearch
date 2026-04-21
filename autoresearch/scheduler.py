from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timezone


EXCLUDED_LABELS = {
    "wontfix",
    "duplicate",
    "invalid",
    "blocked",
    "needs discussion",
    "on hold",
    "external",
    "documentation",
}

PRIORITY_LABEL_WEIGHTS = {
    "priority: critical": 100,
    "priority: p0": 100,
    "urgent": 100,
    "priority: high": 50,
    "priority: p1": 50,
    "priority: medium": 20,
    "priority: p2": 20,
    "priority: low": 10,
    "priority: p3": 10,
    "enhancement": 5,
}

TYPE_LABEL_WEIGHTS = {
    "bug": 30,
    "fix": 30,
    "feature": 20,
    "enhancement": 20,
    "refactor": 10,
    "tech debt": 10,
    "test": 5,
    "testing": 5,
    "documentation": 3,
    "docs": 3,
}


@dataclass(slots=True)
class ComplexityAssessment:
    level: str
    max_iterations: int
    time_budget: str
    requires_human_approval: bool = False


@dataclass(slots=True)
class CandidateIssue:
    number: int
    title: str
    body: str
    labels: list[str]
    created_at: str
    updated_at: str

    @classmethod
    def from_payload(cls, payload: dict[str, object]) -> "CandidateIssue":
        labels_payload = payload.get("labels") or []
        labels: list[str] = []
        if isinstance(labels_payload, list):
            for item in labels_payload:
                if isinstance(item, dict) and "name" in item:
                    labels.append(str(item["name"]))
                elif isinstance(item, str):
                    labels.append(item)
        return cls(
            number=int(payload.get("number", 0) or 0),
            title=str(payload.get("title", "")),
            body=str(payload.get("body", "")),
            labels=labels,
            created_at=str(payload.get("createdAt", "")),
            updated_at=str(payload.get("updatedAt", "")),
        )


@dataclass(slots=True)
class ScheduledIssue:
    issue: CandidateIssue
    priority_score: int
    complexity: ComplexityAssessment
    reasons: list[str]


def filter_issues(issues: list[CandidateIssue], now: datetime | None = None) -> list[CandidateIssue]:
    current_time = now or datetime.now(timezone.utc)
    selected: list[CandidateIssue] = []
    for issue in issues:
        if exclusion_reason(issue, current_time) is None:
            selected.append(issue)
    return selected


def exclusion_reason(issue: CandidateIssue, now: datetime | None = None) -> str | None:
    current_time = now or datetime.now(timezone.utc)
    labels = {label.lower() for label in issue.labels}
    if labels & EXCLUDED_LABELS:
        return "excluded_label"
    title = issue.title.strip()
    body = issue.body.strip()
    if not title or not body:
        return "missing_content"
    if "[wip]" in title.lower() or "[draft]" in title.lower():
        return "draft_issue"
    if "do not implement" in body.lower():
        return "do_not_implement"
    updated_at = _parse_datetime(issue.updated_at)
    if updated_at and (current_time - updated_at).days > 180:
        return "stale_over_6_months"
    return None


def calculate_priority(issue: CandidateIssue, now: datetime | None = None) -> tuple[int, list[str]]:
    current_time = now or datetime.now(timezone.utc)
    score = 15
    reasons = ["base=15"]
    labels = {label.lower() for label in issue.labels}

    label_weight = max((weight for label, weight in PRIORITY_LABEL_WEIGHTS.items() if label in labels), default=0)
    if label_weight:
        score += label_weight
        reasons.append(f"priority_label=+{label_weight}")

    type_weight = max((weight for label, weight in TYPE_LABEL_WEIGHTS.items() if label in labels), default=0)
    if type_weight:
        score += type_weight
        reasons.append(f"type_label=+{type_weight}")

    created_at = _parse_datetime(issue.created_at)
    updated_at = _parse_datetime(issue.updated_at)
    if created_at and (current_time - created_at).days <= 7:
        score += 10
        reasons.append("new_issue=+10")
    if updated_at and (current_time - updated_at).days >= 30:
        score += 15
        reasons.append("stale_issue=+15")
    if updated_at and (current_time - updated_at).days <= 3:
        score += 5
        reasons.append("recently_updated=+5")

    return score, reasons


def assess_complexity(issue: CandidateIssue) -> ComplexityAssessment:
    title = issue.title.lower()
    body = issue.body.lower()
    body_length = len(issue.body.strip())
    if any(keyword in title for keyword in ("redesign", "migrate", "architecture")) or body_length > 500:
        return ComplexityAssessment(level="complex", max_iterations=5, time_budget="60m", requires_human_approval=True)
    if any(keyword in title for keyword in ("add", "implement", "refactor")) or 100 <= body_length <= 500:
        return ComplexityAssessment(level="medium", max_iterations=5, time_budget="30m")
    if any(keyword in title for keyword in ("fix", "typo", "update")) or body_length < 100:
        return ComplexityAssessment(level="simple", max_iterations=3, time_budget="10m")
    return ComplexityAssessment(level="medium", max_iterations=5, time_budget="30m")


def schedule_issues(issues: list[CandidateIssue], limit: int = 1, now: datetime | None = None) -> list[ScheduledIssue]:
    current_time = now or datetime.now(timezone.utc)
    eligible = filter_issues(issues, current_time)
    scheduled: list[ScheduledIssue] = []
    for issue in eligible:
        score, reasons = calculate_priority(issue, current_time)
        scheduled.append(
            ScheduledIssue(
                issue=issue,
                priority_score=score,
                complexity=assess_complexity(issue),
                reasons=reasons,
            )
        )
    scheduled.sort(
        key=lambda item: (
            -item.priority_score,
            item.complexity.requires_human_approval,
            item.issue.number,
        )
    )
    return scheduled[:limit]


def _parse_datetime(value: str) -> datetime | None:
    if not value:
        return None
    normalized = value.replace("Z", "+00:00")
    try:
        parsed = datetime.fromisoformat(normalized)
    except ValueError:
        return None
    if parsed.tzinfo is None:
        return parsed.replace(tzinfo=timezone.utc)
    return parsed
