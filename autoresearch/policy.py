from __future__ import annotations

from dataclasses import dataclass, field

from .models import IssueInfo, RuntimeConfig
from .scheduler import CandidateIssue, assess_complexity


HIGH_RISK_LABELS = {
    "security",
    "auth",
    "authentication",
    "billing",
    "payment",
    "database",
    "db",
    "migration",
    "infra",
    "production",
    "release",
}


@dataclass(slots=True)
class MergePolicyDecision:
    auto_merge: bool
    requires_human_approval: bool
    complexity: str
    reasons: list[str] = field(default_factory=list)


def evaluate_merge_policy(issue: IssueInfo, config: RuntimeConfig) -> MergePolicyDecision:
    labels = {label.lower() for label in issue.labels}
    reasons: list[str] = []
    complexity = _assess_issue_complexity(issue).level

    if config.auto_merge_mode == "always":
        return MergePolicyDecision(
            auto_merge=True,
            requires_human_approval=False,
            complexity=complexity,
            reasons=["auto_merge_mode=always"],
        )

    if config.auto_merge_mode == "never":
        return MergePolicyDecision(
            auto_merge=False,
            requires_human_approval=True,
            complexity=complexity,
            reasons=["auto_merge_mode=never"],
        )

    risk_hits = sorted(labels & HIGH_RISK_LABELS)
    if risk_hits:
        reasons.append(f"high_risk_labels={','.join(risk_hits)}")

    if complexity == "complex":
        reasons.append("complexity=complex")

    requires_human = bool(risk_hits or complexity == "complex")
    auto_merge = not requires_human
    if not reasons:
        reasons.append("safe_default")

    return MergePolicyDecision(
        auto_merge=auto_merge,
        requires_human_approval=requires_human,
        complexity=complexity,
        reasons=reasons,
    )


def _assess_issue_complexity(issue: IssueInfo):
    candidate = CandidateIssue(
        number=issue.number,
        title=issue.title,
        body=issue.body,
        labels=list(issue.labels),
        created_at="",
        updated_at="",
    )
    return assess_complexity(candidate)
