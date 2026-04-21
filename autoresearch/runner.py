from __future__ import annotations

import os
import re
import time
from datetime import datetime
from pathlib import Path

from .logic import (
    annealing_delay,
    check_score_passed,
    detect_context_overflow_file,
    detect_language,
    find_last_iteration,
    get_required_tool,
    get_review_agent,
    get_test_command,
    has_api_failure,
    has_fatal_error,
    load_json_snippet,
    truncate_text,
)
from .gates import HardGateRunner
from .finalizer import FinalizationContext, Finalizer
from .github import GitHubClient, GitHubError
from .models import AGENT_DISPLAY_NAMES, IssueInfo, IterationResult, RuntimeConfig, WorkflowState
from .policy import evaluate_merge_policy
from .progress import ProgressManager
from .review_schema import format_review_feedback, parse_review_report, write_review_report
from .shell import command_exists, run_command, stream_command
from .tasks import TaskManager, TaskPayloadError
from .telemetry import MetricsRecorder
from .ui import run_ui_verification


class RunnerError(RuntimeError):
    pass


class WorkflowRunner:
    def __init__(self, config: RuntimeConfig):
        self.config = config
        self.state = WorkflowState()
        self.github = GitHubClient(config.project_root, repo=config.github_repo)
        self.metrics = MetricsRecorder(config.project_root, enabled=config.metrics_enabled)
        self.language = detect_language(config.project_root)
        self._load_api_keys_from_zshrc()

    @property
    def project_root(self) -> Path:
        return self.config.project_root

    @property
    def work_dir(self) -> Path:
        if self.state.work_dir is None:
            raise RunnerError("work directory has not been initialized")
        return self.state.work_dir

    @property
    def issue(self) -> IssueInfo:
        if self.state.issue_info is None:
            raise RunnerError("issue info is not loaded")
        return self.state.issue_info

    @property
    def tasks(self) -> TaskManager:
        return TaskManager(self.work_dir)

    @property
    def progress(self) -> ProgressManager:
        return ProgressManager(self.work_dir, self.config.issue_number)

    def log(self, message: str) -> None:
        print(f"[{datetime.now():%Y-%m-%d %H:%M:%S}] {message}")

    def error(self, message: str) -> None:
        print(f"[{datetime.now():%Y-%m-%d %H:%M:%S}] ERROR: {message}")

    def fail(self, message: str) -> None:
        self.error(message)
        raise RunnerError(message)

    def _load_api_keys_from_zshrc(self) -> None:
        zshrc = Path.home() / ".zshrc"
        if not zshrc.exists():
            return
        pattern = re.compile(r"^export (OPENROUTER_API_KEY|OPENAI_API_KEY|ANTHROPIC_API_KEY)=(.*)$")
        for line in zshrc.read_text(encoding="utf-8", errors="ignore").splitlines():
            match = pattern.match(line.strip())
            if not match:
                continue
            key, value = match.groups()
            value = value.strip().strip("'").strip('"')
            os.environ.setdefault(key, value)

    def _append_log(self, text: str) -> None:
        log_path = self.work_dir / "log.md"
        with log_path.open("a", encoding="utf-8") as handle:
            handle.write(text)

    def _read_optional_file(self, path: Path) -> str:
        if not path.exists():
            return ""
        return path.read_text(encoding="utf-8", errors="ignore")

    def get_agent_instructions_path(self, agent_name: str) -> Path | None:
        project_path = self.project_root / ".autoresearch" / "agents" / f"{agent_name}.md"
        if project_path.exists():
            return project_path
        default_path = self.config.script_dir / "agents" / f"{agent_name}.md"
        if default_path.exists():
            return default_path
        return None

    def get_agent_instructions(self, agent_name: str) -> str:
        path = self.get_agent_instructions_path(agent_name)
        if path:
            self.log(f"使用指令文件: {path}")
            return path.read_text(encoding="utf-8", errors="ignore")
        return ""

    def get_program_instructions(self) -> str:
        project_program = self.project_root / ".autoresearch" / "program.md"
        if project_program.exists():
            return project_program.read_text(encoding="utf-8", errors="ignore")
        default_program = self.config.script_dir / "program.md"
        if default_program.exists():
            return default_program.read_text(encoding="utf-8", errors="ignore")
        return ""

    def check_project(self) -> None:
        self.log("检查项目环境...")
        if not self.project_root.is_dir():
            self.fail(f"项目目录不存在: {self.project_root}")
        if run_command(["git", "rev-parse", "--is-inside-work-tree"], cwd=self.project_root).returncode != 0:
            self.fail(f"不是 git 仓库: {self.project_root}")
        try:
            remote_url = self.github.get_origin_remote_url()
        except GitHubError as exc:
            self.fail(str(exc))
        if not re.search(r"github\.com|github\.baidu\.com", remote_url):
            self.fail(f"origin 不是 GitHub 仓库: {remote_url}")
        self.log(f"项目目录: {self.project_root}")
        self.log(f"Git remote: {remote_url}")
        self.log(f"项目语言: {self.language}")

    def check_dependencies(self) -> None:
        self.log("检查依赖...")
        missing = False
        if not command_exists("gh"):
            self.error("gh (GitHub CLI) 未安装")
            missing = True
        else:
            try:
                self.github.ensure_authenticated()
            except GitHubError as exc:
                self.error(str(exc))
                missing = True
        for agent_name in self.config.agent_names:
            if not command_exists(agent_name):
                self.error(f"{agent_name} CLI 未安装 (在 -a 参数中指定)")
                missing = True
        required = get_required_tool(self.language)
        if required and not command_exists(required):
            self.error(f"{required} 未安装 (项目语言: {self.language})")
            missing = True

        if self.config.ui_verify_enabled:
            browser_tools_available = any(
                command_exists(name)
                for name in ("playwright", "npx", "google-chrome", "chromium", "chromium-browser")
            )
            if not browser_tools_available:
                self.log("警告: 未检测到浏览器截图工具 (playwright 或 chromium 类浏览器)")
                self.log("警告: UI 验证功能将被禁用，不影响主流程")
                self.config.ui_verify_enabled = False
            else:
                self.log("浏览器工具检测通过")
        else:
            self.log("UI 验证已禁用，跳过浏览器工具检测")

        if missing:
            raise RunnerError("依赖检查失败")
        self.log("依赖检查通过")

    def get_issue_info(self) -> None:
        self.log(f"获取 Issue #{self.config.issue_number} 信息...")
        try:
            issue = self.github.get_issue(self.config.issue_number)
        except GitHubError as exc:
            self.fail(str(exc))
        if issue.state != "OPEN":
            self.fail(f"Issue #{self.config.issue_number} 状态为 {issue.state}，不是 OPEN")
        self.state.issue_info = issue

    def archive_old_workflows(self) -> None:
        workflows_dir = self.project_root / ".autoresearch" / "workflows"
        archive_dir = self.project_root / ".autoresearch" / "archive"
        if not workflows_dir.exists():
            return
        archived_count = 0
        current_date = datetime.now().strftime("%Y-%m-%d")
        for path in workflows_dir.glob("issue-*"):
            if not path.is_dir():
                continue
            if path.name == f"issue-{self.config.issue_number}":
                continue
            match = re.search(r"([0-9]+)$", path.name)
            if not match:
                continue
            issue_number = match.group(1)
            target = archive_dir / f"{current_date}-issue-{issue_number}"
            suffix = 1
            while target.exists():
                target = archive_dir / f"{current_date}-issue-{issue_number}-{suffix}"
                suffix += 1
            archive_dir.mkdir(parents=True, exist_ok=True)
            path.rename(target)
            self.log(f"已归档: {path.name} -> {target}")
            archived_count += 1
        if archived_count:
            self.log(f"归档完成，共归档 {archived_count} 个 Issue 目录")

    def setup_work_directory(self) -> None:
        if not self.config.continue_mode and not self.config.no_archive:
            self.archive_old_workflows()
        self.state.work_dir = self.project_root / ".autoresearch" / "workflows" / f"issue-{self.config.issue_number}"
        self.work_dir.mkdir(parents=True, exist_ok=True)
        self.log(f"工作目录: {self.work_dir}")
        log_path = self.work_dir / "log.md"
        if self.config.continue_mode:
            if not log_path.exists():
                self.fail(f"未找到 Issue #{self.config.issue_number} 的工作日志，无法继续")
            self.log("继续模式: 追加到已有日志")
            return
        log_path.write_text(
            "# Issue #"
            f"{self.config.issue_number} 实现日志\n\n"
            "## 基本信息\n"
            f"- Issue: #{self.config.issue_number} - {self.issue.title}\n"
            f"- 项目: {self.project_root}\n"
            f"- 语言: {self.language}\n"
            f"- 开始时间: {datetime.now():%Y-%m-%d %H:%M:%S}\n"
            f"- 标签: {','.join(self.issue.labels)}\n\n"
            "## 迭代记录\n\n",
            encoding="utf-8",
        )
        self.progress.init()

    def create_branch(self) -> None:
        self.state.branch_name = f"feature/issue-{self.config.issue_number}"
        self.log(f"创建分支: {self.state.branch_name}")
        check = run_command(
            ["git", "show-ref", "--verify", "--quiet", f"refs/heads/{self.state.branch_name}"],
            cwd=self.project_root,
        )
        if check.returncode == 0:
            self.log(f"分支已存在，切换到: {self.state.branch_name}")
            result = run_command(["git", "checkout", self.state.branch_name], cwd=self.project_root)
        else:
            result = run_command(["git", "checkout", "-b", self.state.branch_name], cwd=self.project_root)
        if result.returncode != 0:
            self.fail(result.output.strip() or "创建分支失败")

    def restore_continue_state(self, requested_iterations: int | None) -> None:
        last_iter = find_last_iteration(self.work_dir)
        if last_iter <= 0:
            self.fail(f"未找到任何迭代记录，无法继续 (last_iter='{last_iter}')")
        self.log(f"上次运行到迭代 {last_iter}，从迭代 {last_iter + 1} 继续")
        self.state.iteration = last_iter
        last_score_path = self.work_dir / ".last_score"
        if last_score_path.exists():
            last_score_text = re.sub(r"[^0-9]", "", last_score_path.read_text(encoding="utf-8", errors="ignore"))
            self.state.final_score = int(last_score_text or "0")
            self.log(f"上次评分: {self.state.final_score}/100")
        self.state.consecutive_iteration_failures = 0
        review_logs = sorted(self.work_dir.glob(f"iteration-{last_iter}-*-review.log"), key=lambda item: item.stat().st_mtime, reverse=True)
        if review_logs:
            restored_feedback = review_logs[0].read_text(encoding="utf-8", errors="ignore")
            restored_report = parse_review_report(restored_feedback, self.config.passing_score)
            if restored_report.required_fixes or restored_report.findings or not restored_report.passed:
                restored_feedback = format_review_feedback(restored_report)
            self.state.previous_feedback = restored_feedback
            self.log("已恢复上次审核反馈")
        else:
            self.state.previous_feedback = "初始实现已完成，请审核代码质量并给出评分。如果有问题请直接修复。"
            self.log("未找到审核反馈，使用默认反馈")

        branch = f"feature/issue-{self.config.issue_number}"
        branch_check = run_command(["git", "show-ref", "--verify", "--quiet", f"refs/heads/{branch}"], cwd=self.project_root)
        if branch_check.returncode != 0:
            self.fail(f"未找到分支 {branch}，无法继续")
        checkout = run_command(["git", "checkout", branch], cwd=self.project_root)
        if checkout.returncode != 0:
            self.fail(checkout.output.strip() or f"切换分支 {branch} 失败")
        self.state.branch_name = branch
        self.log(f"已切换到分支: {branch}")

        with (self.work_dir / "log.md").open("a", encoding="utf-8") as handle:
            handle.write(
                "\n---\n\n"
                f"## 继续运行 (从迭代 {last_iter + 1} 继续)\n"
                f"- 继续时间: {datetime.now():%Y-%m-%d %H:%M:%S}\n"
                f"- 上次评分: {self.state.final_score}/100\n"
            )
            if self.tasks.has_subtasks():
                progress = self.tasks.progress_summary()
                handle.write(f"- 子任务: {progress}\n")
                self.log(progress)
            handle.write("\n")

        if requested_iterations is None:
            self.config.max_iterations = self.config.default_max_iterations
            remaining = self.config.max_iterations - self.state.iteration
            self.log(f"继续运行: 已完成 {self.state.iteration} 轮，再跑 {remaining} 轮 (总计 {self.config.max_iterations})")
        else:
            self.config.max_iterations = self.state.iteration + requested_iterations
            self.log(
                f"继续运行: 已完成 {self.state.iteration} 轮，再跑 {requested_iterations} 轮 (总计 {self.config.max_iterations})"
            )

    def build_planning_prompt(self) -> str:
        first_agent = self.config.agent_names[0]
        instructions = self.get_agent_instructions(first_agent)
        program_instructions = self.get_program_instructions()
        return (
            f"规划 GitHub Issue #{self.config.issue_number} 的子任务拆分\n\n"
            f"项目路径: {self.project_root}\n"
            f"项目语言: {self.language}\n"
            f"Issue 标题: {self.issue.title}\n"
            f"Issue 内容: {self.issue.body}\n\n"
            "---\n"
            "请分析此 Issue，将其拆分为可独立完成的子任务。每个子任务应能在一次迭代内完成。\n\n"
            "输出格式要求：在输出的最后，必须输出一个 JSON 代码块（用 ```json 和 ``` 包裹），格式如下：\n\n"
            "```json\n"
            "{\n"
            f'  "issueNumber": {self.config.issue_number},\n'
            '  "subtasks": [\n'
            "    {\n"
            '      "id": "T-001",\n'
            '      "title": "子任务标题",\n'
            '      "description": "详细描述此子任务需要完成的工作",\n'
            '      "acceptanceCriteria": ["验收条件1", "验收条件2"],\n'
            '      "priority": 1,\n'
            '      "type": "code",\n'
            '      "passes": false\n'
            "    }\n"
            "  ]\n"
            "}\n"
            "```\n\n"
            "拆分原则：\n"
            "1. 每个子任务应是一个可独立验证的、在一次迭代内能完成的小目标\n"
            "2. 子任务之间应有清晰的依赖顺序（通过 priority 排序）\n"
            "3. 每个子任务必须有明确的验收条件（acceptanceCriteria）\n"
            "4. 如果 Issue 简单，可以只拆分为 1-2 个子任务\n"
            "5. 如果 Issue 复杂，建议拆分为 3-5 个子任务\n"
            "6. id 格式为 T-001, T-002, ...\n\n"
            "UI 类型识别：\n"
            "- 分析 Issue 内容，如果涉及以下变更，对应子任务应标注 \"type\": \"ui\"：\n"
            "  * 页面布局、样式、组件的增删改\n"
            "  * 前端交互逻辑（表单、按钮、导航等）\n"
            "  * CSS/样式文件的新增或修改\n"
            "  * HTML/模板文件的修改\n"
            "  * 前端框架组件（React/Vue/Svelte 等）的修改\n"
            "- 不涉及 UI 变更的子任务不添加 type 字段（默认为 \"code\"）\n"
            "- 示例：{\"id\": \"T-001\", \"title\": \"添加登录页面\", \"type\": \"ui\", ...}\n\n"
            "---\n"
            f"{program_instructions}\n\n"
            f"{instructions}\n"
        )

    def build_implementation_prompt(self, agent_name: str, iteration: int, previous_feedback: str) -> str:
        issue = self.issue
        instructions = self.get_agent_instructions(agent_name)
        progress_section = self.progress.section()
        subtask_section = self.tasks.subtask_section()
        if not previous_feedback:
            program_instructions = self.get_program_instructions()
            return (
                f"实现 GitHub Issue #{self.config.issue_number}\n\n"
                f"项目路径: {self.project_root}\n"
                f"项目语言: {self.language}\n"
                f"Issue 标题: {issue.title}\n"
                f"Issue 内容: {issue.body}\n\n"
                f"迭代次数: {iteration}\n"
                f"{subtask_section}\n"
                f"{progress_section}\n\n"
                "---\n"
                "请按以下步骤执行:\n\n"
                "## 第一步：制定计划\n"
                "分析 Issue 需求，制定实现计划，拆解为具体的 tasks/todos，输出任务清单。\n\n"
                "## 第二步：逐步实现\n"
                "按照任务清单逐步实现，每完成一个任务标记为已完成。\n\n"
                "## 第三步：总结经验\n"
                "实现完成后，在输出末尾添加 ## Learnings 部分，总结本次迭代中发现的关键模式、踩过的坑和可复用的经验。\n\n"
                "---\n"
                f"{program_instructions}\n\n"
                f"{instructions}\n"
            )
        return (
            f"根据审核反馈改进 Issue #{self.config.issue_number} 的实现\n\n"
            f"项目路径: {self.project_root}\n"
            f"项目语言: {self.language}\n"
            f"Issue 标题: {issue.title}\n\n"
            f"审核反馈:\n{previous_feedback}\n"
            f"{subtask_section}\n"
            f"{progress_section}\n\n"
            "---\n"
            "请按以下步骤执行:\n\n"
            "## 第一步：制定计划\n"
            "分析审核反馈，制定修复计划，拆解为具体的 tasks/todos，输出任务清单。\n\n"
            "## 第二步：逐步实现\n"
            "按照任务清单逐步修复，每完成一个任务标记为已完成。\n\n"
            "## 第三步：总结经验\n"
            "修复完成后，在输出末尾添加 ## Learnings 部分，总结本次修复中发现的关键模式和经验。\n\n"
            "---\n"
            f"{instructions}\n"
        )

    def build_review_prompt(self, agent_name: str) -> str:
        return (
            f"审核 Issue #{self.config.issue_number} 的实现\n\n"
            f"项目路径: {self.project_root}\n"
            f"项目语言: {self.language}\n"
            f"Issue 标题: {self.issue.title}\n\n"
            f"{self.tasks.review_section()}\n"
            "---\n"
            "请按照以下指令执行审核。\n\n"
            "评分格式要求: 必须在审核报告的总体评价中使用 **评分: X/100** 格式输出分数，其中 X 为 0-100 的整数。\n\n"
            "评分维度与权重:\n"
            "- 正确性 (35%): 功能是否符合需求、边界情况处理、错误处理\n"
            "- 测试质量 (25%): 核心逻辑覆盖、边界测试、错误路径测试\n"
            "- 代码质量 (20%): 命名清晰、结构清晰、遵循项目规范\n"
            "- 安全性 (10%): 输入验证、无注入风险、无敏感信息泄露\n"
            "- 性能 (10%): 无明显性能问题、无不必要的内存分配\n\n"
            "评分标准: 90-100 优秀 | 85-89 良好(达标) | 70-84 及格偏上 | 50-69 及格 | 30-49 较差 | 0-29 不合格\n"
            f"注意: 评分 ≥ {self.config.passing_score} 才算达标。\n"
            "\n请先给出简洁的审核结论，然后在输出末尾追加一个 JSON 代码块，格式必须如下：\n"
            "```json\n"
            "{\n"
            '  "pass": true,\n'
            '  "score": 88,\n'
            '  "riskLevel": "low",\n'
            '  "findings": [\n'
            '    {\n'
            '      "severity": "medium",\n'
            '      "summary": "需要补充边界测试",\n'
            '      "path": "tests/test_example.py"\n'
            "    }\n"
            "  ],\n"
            '  "requiredFixes": [\n'
            '    "补充缺失的边界测试"\n'
            "  ]\n"
            "}\n"
            "```\n"
            "要求：\n"
            "- `pass` 必须明确表示是否达标\n"
            "- `score` 必须是 0-100 的整数\n"
            "- `findings` 应列出主要问题，没有问题可返回空数组\n"
            "- `requiredFixes` 应列出下一轮必须修复的事项，没有问题可返回空数组\n"
            f"{self.progress.section()}\n"
            f"{self.get_agent_instructions(agent_name)}\n"
        )

    def agent_command(self, agent_name: str, prompt: str) -> list[str]:
        if agent_name == "codex":
            return ["codex", "exec", "--full-auto", prompt]
        if agent_name == "opencode":
            return ["opencode", "run", prompt]
        return ["claude", "-p", prompt, "--dangerously-skip-permissions"]

    def run_with_retry(self, agent_name: str, prompt: str, log_file: Path) -> bool:
        success = False
        for retry in range(1, self.config.max_retries + 1):
            if retry > 1:
                delay = annealing_delay(retry, self.config.retry_base_delay, self.config.retry_max_delay)
                self.log(f"第 {retry}/{self.config.max_retries} 次重试，等待 {delay} 秒...")
                time.sleep(delay)

            self.log(f"调用 {agent_name} (尝试 {retry}/{self.config.max_retries})...")
            result = stream_command(self.agent_command(agent_name, prompt), cwd=self.project_root, log_file=log_file)
            output = result.output

            if detect_context_overflow_file(log_file):
                self.log("检测到上下文溢出，停止重试")
                break
            if result.returncode != 0:
                self.log(f"Agent {agent_name} 以非零退出码退出: {result.returncode}")
                self.log(f"{agent_name} 第 {retry} 次调用失败")
                continue
            if has_fatal_error(output):
                self.log("检测到致命错误，将重试")
                self.log(f"{agent_name} 第 {retry} 次调用失败")
                continue
            if has_api_failure(output):
                self.log("检测到 API 失败，将重试")
                self.log(f"{agent_name} 第 {retry} 次调用失败")
                continue
            content_lines = len([line for line in output.splitlines() if line.strip()])
            if content_lines < 5:
                self.log(f"警告: 输出内容过少 ({content_lines} 行)，将重试")
                self.log(f"{agent_name} 第 {retry} 次调用失败")
                continue
            success = True
            break

        if not success:
            self.error(f"{agent_name} 调用失败，已重试 {self.config.max_retries} 次")
        return success

    def handle_context_overflow(self, iteration: int, agent_name: str, log_file: Path) -> bool:
        if not detect_context_overflow_file(log_file):
            return False
        self.state.context_retries += 1
        if self.state.context_retries > self.config.max_context_retries:
            self.log(f"上下文溢出已达最大重试次数 ({self.config.max_context_retries})，计为正常失败")
            return False
        self.log(f"检测到上下文溢出，自动交接 (第 {self.state.context_retries}/{self.config.max_context_retries} 次)")
        self.progress.append(iteration, agent_name, log_file, "N/A", "上下文溢出交接", "")
        self.state.previous_feedback = "上一次迭代因上下文溢出中断。请继续当前子任务的实现，参考 progress.md 中的进度记录。"
        self.state.consecutive_iteration_failures = 0
        self._append_log(
            f"- 上下文溢出: 自动交接 (第 {self.state.context_retries}/{self.config.max_context_retries} 次)\n"
        )
        return True

    def run_planning_phase(self) -> bool:
        self.log(f"规划阶段: 拆分 Issue #{self.config.issue_number} 为子任务...")
        if self.tasks.has_subtasks():
            self.log("已有 tasks.json，跳过规划阶段")
            self.log(self.tasks.progress_summary())
            return True

        first_agent = self.config.agent_names[0]
        log_file = self.work_dir / "planning.log"
        if not self.run_with_retry(first_agent, self.build_planning_prompt(), log_file):
            self.log("规划阶段失败，将不拆分子任务（回退到原有模式）")
            return False

        payload = load_json_snippet(log_file.read_text(encoding="utf-8", errors="ignore"))
        if not payload:
            self.log("未能从规划输出中提取 tasks.json，回退到原有模式")
            return False

        try:
            count = self.tasks.save_payload(payload)
        except TaskPayloadError:
            self.log("提取的 JSON 格式无效，回退到原有模式")
            if self.tasks.path.exists():
                self.tasks.path.unlink()
            return False

        self.log(f"成功拆分为 {count} 个子任务")
        self._append_log(f"\n### 规划阶段\n\n已拆分为 {count} 个子任务，详见: [tasks.json](./tasks.json)\n")
        for item in self.tasks.items():
            self.log(f"  {item.id}: {item.title} (priority: {item.priority})")
        return True

    def run_agent_implementation(self, agent_name: str, iteration: int, previous_feedback: str) -> bool:
        self.log(f"迭代 {iteration}: {AGENT_DISPLAY_NAMES[agent_name]} 实现...")
        prompt = self.build_implementation_prompt(agent_name, iteration, previous_feedback)
        log_file = self.work_dir / f"iteration-{iteration}-{agent_name}.log"
        if not self.run_with_retry(agent_name, prompt, log_file):
            return False
        self._append_log(
            f"\n### 迭代 {iteration} - {AGENT_DISPLAY_NAMES[agent_name]} (实现)\n\n"
            f"详见: [iteration-{iteration}-{agent_name}.log](./iteration-{iteration}-{agent_name}.log)\n"
        )
        return True

    def run_agent_review(self, agent_name: str, iteration: int):
        self.log(f"迭代 {iteration}: {AGENT_DISPLAY_NAMES[agent_name]} 审核...")
        log_file = self.work_dir / f"iteration-{iteration}-{agent_name}-review.log"
        if not self.run_with_retry(agent_name, self.build_review_prompt(agent_name), log_file):
            (self.work_dir / ".last_score").write_text("0\n", encoding="utf-8")
            return False, None

        review_result = log_file.read_text(encoding="utf-8", errors="ignore")
        review_report = parse_review_report(review_result, self.config.passing_score)
        write_review_report(review_report, self.work_dir / f"iteration-{iteration}-{agent_name}-review.json")
        self._append_log(f"- 审核评分 ({AGENT_DISPLAY_NAMES[agent_name]}): {review_report.score}/100\n")
        self.log(f"审核评分: {review_report.score}/100")
        (self.work_dir / ".last_score").write_text(f"{review_report.score}\n", encoding="utf-8")
        print(review_result, end="" if review_result.endswith("\n") else "\n")
        return True, review_report

    def run_hard_gate_checks(self, iteration: int) -> bool:
        gate_runner = HardGateRunner(self.project_root, self.work_dir, self.language, self.log)
        return gate_runner.run(iteration).passed

    def record_final_result(self, status: str) -> None:
        tests_passed = "false"
        test_command = get_test_command(self.language)
        if test_command:
            result = run_command(test_command, cwd=self.project_root, shell=True)
            if result.returncode == 0:
                tests_passed = "true"
        results_path = self.project_root / ".autoresearch" / "results.tsv"
        results_path.parent.mkdir(parents=True, exist_ok=True)
        issue = self.issue
        row = "\t".join(
            [
                datetime.now().astimezone().isoformat(timespec="seconds"),
                str(self.config.issue_number),
                issue.title,
                status,
                str(self.state.iteration),
                tests_passed,
                str(self.state.final_score),
                str(self.state.final_score),
                self.state.branch_name,
                "",
            ]
        )
        with results_path.open("a", encoding="utf-8") as handle:
            handle.write(row + "\n")
        self._append_log(
            "\n## 最终结果\n"
            f"- 总迭代次数: {self.state.iteration}\n"
            f"- 最终评分: {self.state.final_score}/100\n"
            f"- 状态: {status}\n"
            f"- 分支: {self.state.branch_name}\n"
            f"- 结束时间: {datetime.now():%Y-%m-%d %H:%M:%S}\n"
        )
        self.metrics.record(
            "run_finished",
            issue_number=self.config.issue_number,
            issue_title=issue.title,
            status=status,
            iterations=self.state.iteration,
            final_score=self.state.final_score,
            branch=self.state.branch_name,
            tests_passed=(tests_passed == "true"),
        )

    def finalize_success(self) -> int:
        self.log("")
        self.log("==========================================")
        self.log("处理完成！")
        self.log("==========================================")
        self.log(f"分支: {self.state.branch_name}")
        self.log(f"评分: {self.state.final_score}/100")
        self.log(f"迭代次数: {self.state.iteration}")
        policy_decision = evaluate_merge_policy(self.issue, self.config)
        self.metrics.record(
            "merge_policy_decision",
            issue_number=self.config.issue_number,
            auto_merge=policy_decision.auto_merge,
            requires_human_approval=policy_decision.requires_human_approval,
            complexity=policy_decision.complexity,
            reasons=policy_decision.reasons,
        )
        finalizer = Finalizer(
            FinalizationContext(
                config=self.config,
                github=self.github,
                project_root=self.project_root,
                work_dir=self.work_dir,
                issue=self.issue,
                branch_name=self.state.branch_name,
                final_score=self.state.final_score,
                iteration=self.state.iteration,
                final_review_report=self.state.final_review_report,
                agent_names=self.config.agent_names,
                policy_decision=policy_decision,
                logger=self.log,
            )
        )
        finalization = finalizer.finalize()
        final_status = {
            "merged": "completed",
            "pr_open": "awaiting_approval",
            "push_failed": "finalize_failed",
            "pr_create_failed": "finalize_failed",
        }.get(finalization.status, "finalize_failed")
        self.record_final_result(final_status)
        self.metrics.record(
            "finalization",
            issue_number=self.config.issue_number,
            status=finalization.status,
            auto_merged=finalization.auto_merged,
            pr_url=finalization.pr_url,
            reasons=finalization.reasons,
        )
        return 0 if finalization.status in {"merged", "pr_open"} else 1

    def run_review_and_fix(self, agent_name: str, iteration: int) -> IterationResult:
        result = IterationResult()
        review_ok, review_report = self.run_agent_review(agent_name, iteration)
        review_log = self.work_dir / f"iteration-{iteration}-{agent_name}-review.log"
        if not review_ok:
            if self.handle_context_overflow(iteration, agent_name, review_log):
                result.context_overflow = True
                return result
            self.log(f"{agent_name} 审核失败，跳到下一次迭代")
            result.iteration_failed = True
            return result

        assert review_report is not None
        result.review_log_file = review_log
        result.review_feedback = review_report.raw_text
        result.score = review_report.score
        self.state.final_score = review_report.score

        if review_report.passed:
            self.log(f"审核通过！评分: {review_report.score}/100 (达标线: {self.config.passing_score})")
            self.state.consecutive_iteration_failures = 0
            result.passed = True
            self.state.final_review_report = review_report.raw_text

            current_task_id = self.tasks.current_id()
            if current_task_id:
                if self.tasks.is_ui_current():
                    ui_result = run_ui_verification(
                        project_root=self.project_root,
                        work_dir=self.work_dir,
                        language=self.language,
                        enabled=self.config.ui_verify_enabled,
                        timeout=self.config.ui_verify_timeout,
                        port_override=self.config.ui_dev_port,
                        log=self.log,
                        subtask_desc=self.tasks.current_title(),
                    )
                    ui_pass = bool(ui_result.get("pass", True))
                    ui_feedback = str(ui_result.get("feedback", ""))
                    self._append_log(f"- UI 验证: {ui_pass} - {ui_feedback}\n")
                    if not ui_pass:
                        self.log("UI 验证未通过，反馈传递给下一迭代")
                        result.ui_verify_failed = True
                        result.passed = False
                        self.state.previous_feedback = f"代码审核通过，但 UI 验证未通过：{ui_feedback}"
                        return result
                    self.log("UI 验证通过")

                self.tasks.mark_passed(current_task_id)
                self.log(f"子任务 {current_task_id} 审核通过")
                if self.tasks.all_passed():
                    self.log("所有子任务已通过！")
                else:
                    self.log(self.tasks.progress_summary())
                    result.passed = False
                    result.subtask_advanced = True
                    self.state.previous_feedback = ""
                    self.state.context_retries = 0
            return result

        self.log(f"评分未达标 ({review_report.score}/{self.config.passing_score})，{agent_name} 根据反馈修复...")
        review_feedback = format_review_feedback(review_report)
        if not self.run_agent_implementation(agent_name, iteration, review_feedback):
            impl_log = self.work_dir / f"iteration-{iteration}-{agent_name}.log"
            if self.handle_context_overflow(iteration, agent_name, impl_log):
                result.context_overflow = True
                return result
            self.log(f"{agent_name} 修复失败，跳到下一次迭代")
            self.state.previous_feedback = review_feedback
            result.iteration_failed = True
            return result

        if not self.run_hard_gate_checks(iteration):
            self.log("硬门禁检查未通过，跳过本轮审核")
            result.hard_gate_failed = True
            gate_log = self.work_dir / f"hard-gate-{iteration}.log"
            gate_text = self._read_optional_file(gate_log) or f"详见 hard-gate-{iteration}.log"
            self.state.previous_feedback = f"硬门禁检查未通过，请根据以下错误修复代码：\n\n{gate_text}"
            result.iteration_failed = True
            return result

        self.log("硬门禁检查通过")
        self.state.previous_feedback = ""
        return result

    def run_initial_iteration(self, iteration: int, has_subtasks: bool) -> IterationResult:
        result = IterationResult()
        agent_name = self.config.agent_names[0]
        if not self.run_agent_implementation(agent_name, iteration, ""):
            impl_log = self.work_dir / f"iteration-{iteration}-{agent_name}.log"
            if self.handle_context_overflow(iteration, agent_name, impl_log):
                result.context_overflow = True
            else:
                self.log(f"{agent_name} 初始实现失败，跳到下一次迭代")
                result.iteration_failed = True
        else:
            if not self.run_hard_gate_checks(iteration):
                self.log("硬门禁检查未通过，跳过本轮审核")
                result.hard_gate_failed = True
                gate_log = self.work_dir / f"hard-gate-{iteration}.log"
                gate_text = self._read_optional_file(gate_log) or f"详见 hard-gate-{iteration}.log"
                self.state.previous_feedback = f"硬门禁检查未通过，请根据以下错误修复代码：\n\n{gate_text}"
                result.iteration_failed = True
            else:
                self.log("硬门禁检查通过")
                self.state.previous_feedback = "初始实现完成，请审核代码质量并给出评分。如果有问题请直接修复。"

        if not result.context_overflow:
            impl_log = self.work_dir / f"iteration-{iteration}-{agent_name}.log"
            label = "初始实现"
            if has_subtasks and self.tasks.current_title():
                label = f"初始实现 - {self.tasks.current_title()}"
            self.progress.append(iteration, agent_name, impl_log, "N/A", label, "")
        return result

    def update_failure_counter(self, result: IterationResult) -> None:
        if result.context_overflow:
            return
        if result.iteration_failed and not result.hard_gate_failed and not result.ui_verify_failed:
            self.state.consecutive_iteration_failures += 1
            self.log(
                f"连续迭代失败次数: {self.state.consecutive_iteration_failures}/{self.config.max_consecutive_failures}"
            )
            return
        if not result.hard_gate_failed and not result.ui_verify_failed:
            self.state.consecutive_iteration_failures = 0

    def run(self, *, requested_continue_iterations: int | None = None) -> int:
        self.log("==========================================")
        self.log("autoresearch - 自动化 Issue 处理")
        self.log("==========================================")
        self.log(f"Issue: #{self.config.issue_number}")
        self.log(f"项目: {self.project_root}")
        self.log(f"模式: {'继续上次运行' if self.config.continue_mode else '全新运行'}")
        self.log(f"最大迭代次数: {self.config.max_iterations}")
        self.log(f"Agent 列表: {' '.join(self.config.agent_names)} (初始实现: {self.config.agent_names[0]})")

        self.check_project()
        self.check_dependencies()
        self.get_issue_info()
        self.setup_work_directory()

        if self.config.continue_mode:
            self.restore_continue_state(requested_continue_iterations)
        else:
            self.create_branch()

        if not self.config.continue_mode:
            self.log("")
            self.log("==========================================")
            self.log("规划阶段: 拆分子任务")
            self.log("==========================================")
            if not self.run_planning_phase():
                self.log("规划阶段未生成子任务，将使用原有模式（一次性实现整个 Issue）")

        while self.state.iteration < self.config.max_iterations:
            self.state.iteration += 1
            iteration = self.state.iteration
            has_subtasks = self.tasks.has_subtasks()
            self.log("")
            self.log("==========================================")
            self.log(f"迭代 {iteration}/{self.config.max_iterations}")
            if has_subtasks:
                self.log(self.tasks.progress_summary())
            if iteration == 1:
                self.log(f"本轮: {self.config.agent_names[0]} 初始实现")
            else:
                agent_idx = get_review_agent(iteration, len(self.config.agent_names))
                self.log(f"本轮: {self.config.agent_names[agent_idx]} 审核 + 修复")
            self.log("==========================================")

            if iteration == 1:
                result = self.run_initial_iteration(iteration, has_subtasks)
                self.update_failure_counter(result)
                continue

            agent_idx = get_review_agent(iteration, len(self.config.agent_names))
            agent_name = self.config.agent_names[agent_idx]
            result = self.run_review_and_fix(agent_name, iteration)
            if result.context_overflow:
                continue

            review_log = self.work_dir / f"iteration-{iteration}-{agent_name}-review.log"
            review_brief = self._read_optional_file(review_log)
            review_brief = truncate_text(review_brief, 800)
            subtask_label = f" - {self.tasks.current_id()}" if has_subtasks and self.tasks.current_id() else ""
            self.progress.append(iteration, agent_name, review_log, result.score, f"审核+修复{subtask_label}", review_brief)

            if has_subtasks and self.tasks.all_passed():
                break
            if result.passed and not has_subtasks:
                break

            self.update_failure_counter(result)
            if self.state.consecutive_iteration_failures >= self.config.max_consecutive_failures:
                self.error(f"连续 {self.state.consecutive_iteration_failures} 次迭代失败，停止运行")
                self.record_final_result("agent_failed")
                return 1

        if check_score_passed(self.state.final_score, self.config.passing_score):
            return self.finalize_success()

        self.log("")
        self.log("==========================================")
        self.log("达到最大迭代次数，仍未通过审核")
        self.log("==========================================")
        self.log(f"最终评分: {self.state.final_score}/100")
        self.log("请人工介入处理")
        self.record_final_result("blocked")
        return 1
