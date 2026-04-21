from __future__ import annotations

import re
from dataclasses import dataclass, field
from pathlib import Path


@dataclass(slots=True)
class UserStory:
    story_id: str
    title: str
    description: str
    acceptance_criteria: list[str] = field(default_factory=list)


@dataclass(slots=True)
class ProductSpec:
    title: str
    introduction: str
    user_stories: list[UserStory] = field(default_factory=list)


def parse_prd_markdown(path: Path) -> ProductSpec:
    content = path.read_text(encoding="utf-8")
    title = _extract_prd_title(content, path)
    introduction = _extract_section(content, "## Introduction")
    stories = _extract_user_stories(content)
    return ProductSpec(title=title, introduction=introduction, user_stories=stories)


def _extract_prd_title(content: str, path: Path) -> str:
    for line in content.splitlines():
        if line.startswith("# "):
            return line[2:].strip()
    return path.stem


def _extract_section(content: str, heading: str) -> str:
    match = re.search(rf"^{re.escape(heading)}\s*$", content, re.MULTILINE)
    if not match:
        return ""
    remaining = content[match.end() :].lstrip("\n")
    lines = []
    for line in remaining.splitlines():
        if line.startswith("## "):
            break
        lines.append(line)
    return "\n".join(lines).strip()


def _extract_user_stories(content: str) -> list[UserStory]:
    section = _extract_section(content, "## User Stories")
    if not section:
        return []
    blocks = re.split(r"(?=^###\s+US-\d+)", section, flags=re.MULTILINE)
    stories: list[UserStory] = []
    for block in blocks:
        block = block.strip()
        if not block.startswith("### "):
            continue
        header, *rest = block.splitlines()
        match = re.match(r"###\s+(US-\d+):\s+(.+)$", header.strip())
        if not match:
            continue
        story_id, title = match.groups()
        block_text = "\n".join(rest)
        description_match = re.search(r"\*\*Description:\*\*\s*(.+)", block_text)
        description = description_match.group(1).strip() if description_match else ""
        criteria = _extract_acceptance_criteria(block_text)
        stories.append(
            UserStory(
                story_id=story_id,
                title=title.strip(),
                description=description,
                acceptance_criteria=criteria,
            )
        )
    return stories


def _extract_acceptance_criteria(block_text: str) -> list[str]:
    match = re.search(r"\*\*Acceptance Criteria:\*\*(.*?)(?:\n\*\*|\Z)", block_text, re.DOTALL)
    if not match:
        return []
    lines = []
    for raw_line in match.group(1).splitlines():
        line = raw_line.strip()
        if line.startswith("- [ ] "):
            lines.append(line[6:].strip())
        elif line.startswith("- "):
            lines.append(line[2:].strip())
    return lines
