from __future__ import annotations

from datetime import date
from pathlib import Path

from .logic import extract_learnings, extract_section, truncate_text


class ProgressManager:
    def __init__(self, work_dir: Path, issue_number: int):
        self.work_dir = work_dir
        self.issue_number = issue_number

    @property
    def path(self) -> Path:
        return self.work_dir / "progress.md"

    def init(self) -> None:
        self.path.write_text(
            f"# Issue #{self.issue_number} 经验日志\n\n"
            "## Codebase Patterns\n\n"
            "> 此区域汇总最重要的可复用经验和模式。Agent 可在实现过程中更新此区域。\n",
            encoding="utf-8",
        )

    def append(self, iteration: int, agent_name: str, log_file: Path, score: str | int, entry_type: str, review_summary: str) -> None:
        if not self.path.exists():
            self.init()
        raw_log = ""
        if log_file.exists():
            raw_log = log_file.read_text(encoding="utf-8", errors="ignore")
        learnings = truncate_text(extract_learnings(raw_log), 1500) if raw_log else ""
        if len(raw_log) > 1500 and len(learnings) == 1500:
            learnings += "\n\n... (内容过长，已截断)"
        entry = [
            "",
            f"## Iteration {iteration} - {date.today():%Y-%m-%d}",
            "",
            f"- **Agent**: {agent_name}",
            f"- **类型**: {entry_type}",
            f"- **评分**: {score}/100",
        ]
        if review_summary:
            entry.extend(["- **审核要点**:", "", truncate_text(review_summary, 800)])
        if learnings:
            entry.extend(["- **经验与发现**:", "", learnings])
        with self.path.open("a", encoding="utf-8") as handle:
            handle.write("\n".join(entry) + "\n")

    def content(self) -> str:
        if not self.path.exists():
            return ""
        content = self.path.read_text(encoding="utf-8")
        if len(content) <= 5000:
            return content
        patterns = extract_section(content, "## Codebase Patterns")
        recent = content[-3000:]
        return f"{patterns}\n\n... (中间迭代记录已省略)\n\n{recent}"

    def section(self) -> str:
        content = self.content()
        if not content:
            return ""
        return (
            "\n## 跨迭代经验\n\n"
            "以下是之前迭代中积累的经验和发现，请优先参考，避免重复踩坑：\n\n"
            f"{content}"
        )
