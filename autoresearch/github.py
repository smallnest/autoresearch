from __future__ import annotations

import json
from pathlib import Path

from .models import IssueInfo
from .shell import run_command


class GitHubError(RuntimeError):
    pass


class GitHubClient:
    def __init__(self, project_root: Path, repo: str | None = None):
        self.project_root = project_root
        self.repo = repo

    def _with_repo(self, args: list[str]) -> list[str]:
        if not self.repo or "--repo" in args:
            return args
        return [*args, "--repo", self.repo]

    def get_origin_remote_url(self) -> str:
        result = run_command(["git", "remote", "get-url", "origin"], cwd=self.project_root)
        remote_url = result.output.strip()
        if result.returncode != 0 or not remote_url:
            raise GitHubError("未找到 git remote origin")
        return remote_url

    def ensure_authenticated(self) -> None:
        result = run_command(["gh", "auth", "status"], cwd=self.project_root)
        if result.returncode != 0:
            raise GitHubError("gh 未登录，请先执行 gh auth login")

    def get_issue(self, issue_number: int) -> IssueInfo:
        result = run_command(
            self._with_repo([
                "gh",
                "issue",
                "view",
                str(issue_number),
                "--json",
                "number,title,body,state,labels",
            ]),
            cwd=self.project_root,
        )
        if result.returncode != 0:
            raise GitHubError(f"无法获取 Issue #{issue_number}: {result.output.strip()}")
        payload = json.loads(result.output)
        labels = [item.get("name", "") for item in payload.get("labels", []) if isinstance(item, dict)]
        return IssueInfo(
            number=int(payload.get("number", issue_number)),
            title=str(payload.get("title", "")),
            body=str(payload.get("body", "")),
            state=str(payload.get("state", "")),
            labels=[str(item) for item in labels if item],
        )

    def create_pr(self, title: str, body: str) -> str:
        result = run_command(
            self._with_repo(["gh", "pr", "create", "--title", title, "--body", body]),
            cwd=self.project_root,
        )
        return result.output.strip()

    def merge_pr(self, pr_number: str) -> None:
        run_command(self._with_repo(["gh", "pr", "merge", pr_number, "--merge", "--delete-branch"]), cwd=self.project_root)

    def comment_issue(self, issue_number: int, body: str) -> None:
        run_command(self._with_repo(["gh", "issue", "comment", str(issue_number), "--body", body]), cwd=self.project_root)

    def close_issue(self, issue_number: int) -> None:
        run_command(self._with_repo(["gh", "issue", "close", str(issue_number), "--reason", "completed"]), cwd=self.project_root)

    def list_open_issues(self, limit: int = 100) -> list[dict[str, object]]:
        result = run_command(
            self._with_repo(
                [
                    "gh",
                    "issue",
                    "list",
                    "--state",
                    "open",
                    "--limit",
                    str(limit),
                    "--json",
                    "number,title,labels,body,createdAt,updatedAt",
                ]
            ),
            cwd=self.project_root,
        )
        if result.returncode != 0:
            raise GitHubError(f"无法获取 open issues: {result.output.strip()}")
        payload = json.loads(result.output)
        if not isinstance(payload, list):
            raise GitHubError("获取 issue 列表失败：返回格式无效")
        return [item for item in payload if isinstance(item, dict)]

    def create_issue(self, title: str, body: str, labels: list[str] | None = None) -> str:
        args = ["gh", "issue", "create", "--title", title, "--body", body]
        for label in labels or []:
            args.extend(["--label", label])
        result = run_command(self._with_repo(args), cwd=self.project_root)
        if result.returncode != 0:
            raise GitHubError(f"创建 issue 失败: {result.output.strip()}")
        return result.output.strip()
