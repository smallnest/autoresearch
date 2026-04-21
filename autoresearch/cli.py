from __future__ import annotations

import argparse
import os
from dataclasses import replace
from pathlib import Path

from .daemon import QueueDaemon
from .github import GitHubClient, GitHubError
from .issue_generator import generate_issue_drafts, write_issue_drafts
from .logic import parse_agent_list
from .models import RuntimeConfig
from .queue_runner import QueueRunner
from .reporting import format_metrics_summary, load_metrics, summarize_metrics
from .runner import RunnerError, WorkflowRunner
from .scheduler import CandidateIssue, schedule_issues
from .spec_parser import parse_prd_markdown
from .telemetry import MetricsRecorder


def _env_int(name: str, default: int) -> int:
    value = os.getenv(name)
    if value is None or value == "":
        return default
    try:
        return int(value)
    except ValueError:
        return default


def _env_bool(name: str, default: bool) -> bool:
    value = os.getenv(name)
    if value is None or value == "":
        return default
    return value.lower() in {"1", "true", "yes", "on"}


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="run.sh",
        description="通用自动化 Issue 处理工具，支持任意 Git + GitHub 项目。",
    )
    parser.add_argument("issue_number", nargs="?", type=int, help="GitHub Issue 编号")
    parser.add_argument("max_iterations", nargs="?", type=int, help="最大迭代次数")
    parser.add_argument("-p", "--project-path", default=".", help="项目路径 (默认: 当前目录)")
    parser.add_argument(
        "-a",
        "--agents",
        default="",
        help="逗号分隔的 agent 列表 (默认: claude,codex,opencode)",
    )
    parser.add_argument("-c", "--continue-mode", action="store_true", help="继续模式，从上次中断的迭代继续")
    parser.add_argument("--no-archive", action="store_true", help="跳过归档其他 Issue 的 workflows 数据")
    parser.add_argument("--next", dest="select_next", action="store_true", help="自动选择下一个可执行 Issue")
    parser.add_argument("--batch", type=int, default=0, help="自动选择并顺序处理前 N 个可执行 Issue")
    parser.add_argument("--repo", default=None, help="指定 GitHub 仓库（owner/repo）")
    parser.add_argument("--report", action="store_true", help="输出本地 metrics 汇总报告")
    parser.add_argument("--daemon", action="store_true", help="持续轮询并处理 issue 队列")
    parser.add_argument("--poll-interval", type=int, default=60, help="daemon 轮询间隔秒数")
    parser.add_argument("--lease-ttl", type=int, default=1800, help="worker lease 过期时间（秒）")
    parser.add_argument("--worker-id", default=None, help="指定 worker 标识")
    parser.add_argument("--plan-prd", default=None, help="从 PRD markdown 生成 issue 草案")
    parser.add_argument("--issue-output", default=None, help="issue 草案输出路径（JSON）")
    parser.add_argument("--create-issues", action="store_true", help="配合 --plan-prd 直接在 GitHub 创建 issues")
    parser.add_argument("--issue-label", action="append", default=None, help="创建 issue 时附加 label，可重复传入")
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        agent_names = parse_agent_list(args.agents)
    except ValueError as exc:
        parser.error(str(exc))

    project_root = Path(args.project_path).expanduser().resolve()
    default_max_iterations = 42
    max_iterations = args.max_iterations if args.max_iterations is not None else default_max_iterations
    auto_select_mode = args.select_next or args.batch > 0
    if args.daemon and not auto_select_mode:
        parser.error("--daemon 需要配合 --next 或 --batch")
    if args.report:
        if any([args.issue_number is not None, auto_select_mode, args.continue_mode, args.plan_prd, args.create_issues, args.daemon]):
            parser.error("--report 不能与其他执行参数同时使用")
        metrics_path = project_root / ".autoresearch" / "metrics.jsonl"
        print(format_metrics_summary(summarize_metrics(load_metrics(metrics_path))))
        return 0

    if args.plan_prd:
        if any([args.issue_number is not None, auto_select_mode, args.continue_mode]):
            parser.error("--plan-prd 不能与 issue 执行参数同时使用")
        return _plan_prd(
            project_root=project_root,
            prd_path=Path(args.plan_prd).expanduser().resolve(),
            repo=args.repo,
            output_path=Path(args.issue_output).expanduser().resolve() if args.issue_output else None,
            create_issues=args.create_issues,
            labels=args.issue_label or [],
        )

    if auto_select_mode and args.issue_number is not None:
        parser.error("使用 --next 或 --batch 时不能同时传 issue_number")
    if not auto_select_mode and args.issue_number is None:
        parser.error("必须提供 issue_number，或使用 --next / --batch")
    if auto_select_mode and args.continue_mode:
        parser.error("--next / --batch 不支持继续模式")
    if args.batch < 0:
        parser.error("--batch 必须是正整数")
    if args.poll_interval <= 0:
        parser.error("--poll-interval 必须是正整数")
    if args.lease_ttl <= 0:
        parser.error("--lease-ttl 必须是正整数")

    config = RuntimeConfig(
        issue_number=args.issue_number or 0,
        project_root=project_root,
        max_iterations=max_iterations,
        continue_mode=args.continue_mode,
        no_archive=args.no_archive,
        agent_names=agent_names,
        script_dir=Path(__file__).resolve().parents[1],
        github_repo=args.repo,
        default_max_iterations=default_max_iterations,
        passing_score=_env_int("PASSING_SCORE", 85),
        max_consecutive_failures=_env_int("MAX_CONSECUTIVE_FAILURES", 3),
        max_retries=_env_int("MAX_RETRIES", 5),
        retry_base_delay=_env_int("RETRY_BASE_DELAY", 2),
        retry_max_delay=_env_int("RETRY_MAX_DELAY", 60),
        max_context_retries=_env_int("MAX_CONTEXT_RETRIES", 3),
        auto_merge_mode=os.getenv("AUTO_MERGE_MODE", "safe"),
        metrics_enabled=_env_bool("METRICS_ENABLED", True),
        lease_ttl_seconds=args.lease_ttl,
        queue_poll_interval=args.poll_interval,
        worker_id=args.worker_id,
        ui_verify_enabled=_env_bool("UI_VERIFY_ENABLED", True),
        ui_verify_timeout=_env_int("UI_VERIFY_TIMEOUT", 60),
        ui_dev_port=_env_int("UI_DEV_PORT", 0) or None,
    )

    if auto_select_mode:
        batch_size = 1 if args.select_next else args.batch
        if args.daemon:
            return _run_daemon(config, batch_size=batch_size)
        return _run_auto_selected_issues(config, issue_limit=batch_size)

    runner = WorkflowRunner(config)
    try:
        return runner.run(requested_continue_iterations=args.max_iterations if args.continue_mode else None)
    except RunnerError:
        return 1


def _run_auto_selected_issues(base_config: RuntimeConfig, issue_limit: int) -> int:
    queue_runner = QueueRunner(base_config)
    try:
        result = queue_runner.run_batch(issue_limit)
    except GitHubError as exc:
        print(exc)
        return 1
    if result.processed == 0:
        print("未找到可自动执行的 Issue。")
        return 1
    return 0 if result.failed == 0 else 1


def _run_daemon(base_config: RuntimeConfig, *, batch_size: int) -> int:
    queue_runner = QueueRunner(base_config)
    daemon = QueueDaemon(queue_runner, poll_interval=base_config.queue_poll_interval)
    try:
        daemon.run(batch_size=batch_size)
    except KeyboardInterrupt:
        print("daemon stopped")
        return 0
    return 0


def _plan_prd(
    *,
    project_root: Path,
    prd_path: Path,
    repo: str | None,
    output_path: Path | None,
    create_issues: bool,
    labels: list[str],
) -> int:
    spec = parse_prd_markdown(prd_path)
    drafts = generate_issue_drafts(spec, default_labels=labels)
    if output_path:
        write_issue_drafts(drafts, output_path)
        print(f"已生成 {len(drafts)} 个 issue 草案: {output_path}")
    else:
        for draft in drafts:
            print(f"# {draft.title}\n\n{draft.body}\n")

    if create_issues:
        github = GitHubClient(project_root, repo=repo)
        try:
            github.ensure_authenticated()
            for draft in drafts:
                url = github.create_issue(draft.title, draft.body, draft.labels)
                print(f"created: {url}")
        except GitHubError as exc:
            print(exc)
            return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
