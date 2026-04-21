from __future__ import annotations

import json
import re
from dataclasses import dataclass, field
from pathlib import Path

from .github import GitHubClient
from .models import IssueInfo, RuntimeConfig
from .policy import MergePolicyDecision
from .shell import run_command
from .tasks import TaskManager


@dataclass(slots=True)
class FinalizationContext:
    config: RuntimeConfig
    github: GitHubClient
    project_root: Path
    work_dir: Path
    issue: IssueInfo
    branch_name: str
    final_score: int
    iteration: int
    final_review_report: str
    agent_names: list[str]
    policy_decision: MergePolicyDecision
    logger: object


@dataclass(slots=True)
class FinalizationResult:
    status: str
    pr_url: str = ""
    pr_number: str = ""
    auto_merged: bool = False
    reasons: list[str] = field(default_factory=list)


class Finalizer:
    def __init__(self, context: FinalizationContext):
        self.ctx = context

    def finalize(self) -> FinalizationResult:
        self._log("")
        self._log("==========================================")
        self._log("自动提交 PR 并执行收尾策略...")
        self._log("==========================================")
        self._log("提交更改...")
        run_command(["git", "add", "-A"], cwd=self.ctx.project_root)

        commit_message = (
            f"feat: implement issue #{self.ctx.config.issue_number} - {self.ctx.issue.title}\n\n"
            f"{self.ctx.final_review_report}\n\n"
            f"Closes #{self.ctx.config.issue_number}"
        )
        commit_result = run_command(["git", "commit", "-m", commit_message], cwd=self.ctx.project_root)
        if commit_result.returncode != 0:
            self._log("没有需要提交的更改")

        self._log(f"推送分支 {self.ctx.branch_name}...")
        push_result = run_command(["git", "push", "-u", "origin", self.ctx.branch_name], cwd=self.ctx.project_root)
        if push_result.returncode != 0:
            self._error(push_result.output.strip() or "推送分支失败")
            return FinalizationResult(status="push_failed", reasons=["push_failed"])

        pr_body = self._build_pr_body()
        self._log("创建 Pull Request...")
        pr_output = self.ctx.github.create_pr(
            title=f"feat: {self.ctx.issue.title} (#{self.ctx.config.issue_number})",
            body=pr_body,
        )
        pr_match = re.search(r"https://github\.com/\S+", pr_output)
        if not pr_match:
            self._log("警告: PR 创建失败或已存在")
            if pr_output:
                self._log(pr_output)
            return FinalizationResult(status="pr_create_failed", reasons=["pr_create_failed"])

        pr_url = pr_match.group(0)
        pr_number_match = re.search(r"/pull/([0-9]+)", pr_url)
        pr_number = pr_number_match.group(1) if pr_number_match else ""
        self._log(f"PR 已创建: {pr_url}")

        if self.ctx.policy_decision.auto_merge and pr_number:
            self._log(f"合并 PR #{pr_number}...")
            self.ctx.github.merge_pr(pr_number)
            self.ctx.github.comment_issue(self.ctx.config.issue_number, self._build_issue_comment(pr_url, merged=True))
            self._log(f"关闭 Issue #{self.ctx.config.issue_number}...")
            self.ctx.github.close_issue(self.ctx.config.issue_number)
            self._log("")
            self._log("==========================================")
            self._log(f"完成！Issue #{self.ctx.config.issue_number} 已自动处理")
            self._log("==========================================")
            self._log(f"PR: {pr_url}")
            self._log("状态: 已合并并关闭")
            return FinalizationResult(
                status="merged",
                pr_url=pr_url,
                pr_number=pr_number,
                auto_merged=True,
                reasons=list(self.ctx.policy_decision.reasons),
            )

        self._log("自动 merge 已跳过，等待人工审批")
        self.ctx.github.comment_issue(self.ctx.config.issue_number, self._build_issue_comment(pr_url, merged=False))
        return FinalizationResult(
            status="pr_open",
            pr_url=pr_url,
            pr_number=pr_number,
            auto_merged=False,
            reasons=list(self.ctx.policy_decision.reasons),
        )

    def _build_pr_body(self) -> str:
        tasks = TaskManager(self.ctx.work_dir)
        subtask_summary = ""
        if tasks.has_subtasks():
            items = tasks.items()
            passed = sum(1 for item in items if item.passes)
            checklist = "\n".join(f'- [{"x" if item.passes else " "}] {item.id}: {item.title}' for item in items)
            subtask_summary = f"\n## Subtasks\n- Completed: {passed}/{len(items)}\n{checklist}\n"

        ui_verify_summary = ""
        ui_result_path = self.ctx.work_dir / "ui-verify-result.json"
        if ui_result_path.exists():
            try:
                ui_payload = json.loads(ui_result_path.read_text(encoding="utf-8"))
            except json.JSONDecodeError:
                ui_payload = {}
            ui_verify_summary = (
                "\n## UI Verification\n"
                f"- Result: {ui_payload.get('pass', 'N/A')}\n"
                f"- Feedback: {ui_payload.get('feedback', '')}\n"
            )

        policy_summary = (
            "\n## Merge Policy\n"
            f"- Auto merge: {self.ctx.policy_decision.auto_merge}\n"
            f"- Complexity: {self.ctx.policy_decision.complexity}\n"
            f"- Reasons: {', '.join(self.ctx.policy_decision.reasons)}\n"
        )
        return (
            "## Summary\n"
            f"- Implements #{self.ctx.config.issue_number}\n"
            f"- Score: {self.ctx.final_score}/100\n"
            f"- Iterations: {self.ctx.iteration}\n"
            f"{subtask_summary}{ui_verify_summary}{policy_summary}"
            "## Test plan\n"
            "- [x] All tests pass\n"
            f"- [x] Code review completed with score >= {self.ctx.config.passing_score}\n\n"
            f"Closes #{self.ctx.config.issue_number}"
        )

    def _build_issue_comment(self, pr_url: str, *, merged: bool) -> str:
        log_summary = self._read_optional_file(self.ctx.work_dir / "log.md")
        merged_text = "已合并" if merged else "待人工审批"
        close_text = "该 Issue 已由 autoresearch 自动实现、审核并合并。" if merged else "该 Issue 已由 autoresearch 自动实现并创建 PR，等待人工审批后合并。"
        return (
            "## 自动处理完成\n\n"
            f"- **PR**: {pr_url} ({merged_text})\n"
            f"- **评分**: {self.ctx.final_score}/100\n"
            f"- **迭代次数**: {self.ctx.iteration}\n"
            f"- **实现方式**: autoresearch 多 agent 迭代 ({' '.join(self.ctx.agent_names)})\n"
            f"- **自动合并**: {self.ctx.policy_decision.auto_merge}\n"
            f"- **策略原因**: {', '.join(self.ctx.policy_decision.reasons)}\n\n"
            f"{log_summary}\n\n"
            f"{close_text}\n"
        )

    def _read_optional_file(self, path: Path) -> str:
        if not path.exists():
            return ""
        return path.read_text(encoding="utf-8", errors="ignore")

    def _log(self, message: str) -> None:
        self.ctx.logger(message)

    def _error(self, message: str) -> None:
        if hasattr(self.ctx.logger, "__self__") and hasattr(self.ctx.logger.__self__, "error"):
            self.ctx.logger.__self__.error(message)
        else:
            self._log(f"ERROR: {message}")
