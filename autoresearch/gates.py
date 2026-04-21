from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path

from .logic import get_build_command, get_lint_command, get_test_command
from .shell import run_command


@dataclass(slots=True)
class HardGateResult:
    passed: bool
    log_file: Path
    errors: list[str] = field(default_factory=list)


class HardGateRunner:
    def __init__(self, project_root: Path, work_dir: Path, language: str, log):
        self.project_root = project_root
        self.work_dir = work_dir
        self.language = language
        self.log = log

    def run(self, iteration: int) -> HardGateResult:
        log_file = self.work_dir / f"hard-gate-{iteration}.log"
        errors: list[str] = []
        log_lines = [
            f"=== 硬门禁检查 (迭代 {iteration}) ===",
            f"时间: {datetime.now():%Y-%m-%d %H:%M:%S}",
            "",
        ]
        failed = False
        stages = [
            ("构建", get_build_command(self.language)),
            ("Lint", get_lint_command(self.language)),
            ("测试", get_test_command(self.language)),
        ]
        for stage_name, command in stages:
            log_lines.append(f"--- {stage_name} ---")
            if not command:
                log_lines.append("结果: 跳过 (无对应命令)")
                log_lines.append("")
                self.log(f"硬门禁: 无{stage_name}命令，跳过")
                continue
            self.log(f"硬门禁: {stage_name} 检查 ({command})...")
            result = run_command(command, cwd=self.project_root, shell=True)
            log_lines.append(f"命令: {command}")
            log_lines.append(result.output.rstrip())
            if result.returncode == 0:
                log_lines.append("结果: 通过")
                self.log(f"硬门禁: {stage_name}通过")
            else:
                log_lines.append(f"结果: 失败 (exit code: {result.returncode})")
                tail = "\n".join(result.output.splitlines()[-20:])
                errors.append(f"## {stage_name}失败 ({command})\n\n```\n{tail}\n```\n")
                failed = True
                self.log(f"硬门禁: {stage_name}失败")
            log_lines.append("")

        log_lines.append("=== 汇总 ===")
        if failed:
            log_lines.append("状态: 失败")
            log_lines.extend(errors)
            self.log("硬门禁: 未通过")
        else:
            log_lines.append("状态: 全部通过")
            self.log("硬门禁: 全部通过")
        log_file.write_text("\n".join(log_lines) + "\n", encoding="utf-8")
        return HardGateResult(passed=not failed, log_file=log_file, errors=errors)
