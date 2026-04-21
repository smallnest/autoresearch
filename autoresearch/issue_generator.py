from __future__ import annotations

import json
from dataclasses import asdict, dataclass, field
from pathlib import Path

from .spec_parser import ProductSpec, UserStory


@dataclass(slots=True)
class IssueDraft:
    story_id: str
    title: str
    body: str
    labels: list[str] = field(default_factory=list)

    def to_payload(self) -> dict[str, object]:
        return asdict(self)


def generate_issue_drafts(spec: ProductSpec, default_labels: list[str] | None = None) -> list[IssueDraft]:
    labels = default_labels or []
    drafts: list[IssueDraft] = []
    for story in spec.user_stories:
        title = f"{story.story_id}: {story.title}"
        body = render_issue_body(story)
        drafts.append(IssueDraft(story_id=story.story_id, title=title, body=body, labels=list(labels)))
    return drafts


def render_issue_body(story: UserStory) -> str:
    acceptance = "\n".join(f"- [ ] {item}" for item in story.acceptance_criteria) or "- [ ] 待补充验收标准"
    technical_notes = (
        "- 从对应 User Story 落地实现\n"
        "- 与现有代码模式保持一致\n"
        "- 补充必要测试与验证"
    )
    return (
        "## Description\n"
        f"{story.description}\n\n"
        "## Acceptance Criteria\n"
        f"{acceptance}\n\n"
        "## Dependencies\n"
        "- [ ] 待补充依赖关系\n\n"
        "## Technical Notes\n"
        f"{technical_notes}\n"
    )


def write_issue_drafts(drafts: list[IssueDraft], output_path: Path) -> None:
    payload = [draft.to_payload() for draft in drafts]
    output_path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
