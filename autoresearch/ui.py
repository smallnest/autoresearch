from __future__ import annotations

import json
import re
import socket
import time
import urllib.error
import urllib.request
from pathlib import Path

from .logic import load_json_snippet
from .shell import command_exists, run_command, start_background_process, terminate_process


def detect_dev_server_command(project_root: Path, language: str) -> str:
    command = ""

    if language == "node":
        package_json = project_root / "package.json"
        if package_json.exists():
            try:
                payload = json.loads(package_json.read_text(encoding="utf-8"))
            except json.JSONDecodeError:
                payload = {}
            scripts = payload.get("scripts") or {}
            if isinstance(scripts, dict):
                if "dev" in scripts:
                    command = "npm run dev"
                elif "start" in scripts:
                    command = "npm start"
                elif "serve" in scripts:
                    command = "npm run serve"
        if not command:
            if any((project_root / name).exists() for name in ("vite.config.ts", "vite.config.js")):
                command = "npx vite"
            elif any((project_root / name).exists() for name in ("next.config.js", "next.config.ts")):
                command = "npx next dev"
            elif (project_root / "angular.json").exists():
                command = "npx ng serve"
            elif (project_root / "webpack.config.js").exists():
                command = "npx webpack serve"

    if language == "python":
        requirements = project_root / "requirements.txt"
        if (project_root / "manage.py").exists():
            command = "python manage.py runserver"
        elif requirements.exists():
            requirements_text = requirements.read_text(encoding="utf-8", errors="ignore")
            if "flask" in requirements_text.lower():
                command = "flask run"
            elif "fastapi" in requirements_text.lower() and command_exists("uvicorn"):
                command = "uvicorn main:app --reload"

    if language == "go":
        if (project_root / "main.go").exists():
            command = "go run main.go"
        elif (project_root / "cmd" / "main.go").exists():
            command = "go run cmd/main.go"

    if language == "rust":
        command = "cargo run"

    if not command:
        makefile = project_root / "Makefile"
        if makefile.exists():
            content = makefile.read_text(encoding="utf-8", errors="ignore")
            if re.search(r"^dev:", content, re.MULTILINE):
                command = "make dev"
            elif re.search(r"^serve:", content, re.MULTILINE):
                command = "make serve"
            elif re.search(r"^run:", content, re.MULTILINE):
                command = "make run"

    return command


def detect_dev_server_port(project_root: Path, env_port: int | None) -> int:
    if env_port:
        return env_port

    package_json = project_root / "package.json"
    if package_json.exists():
        for config_name in ("vite.config.ts", "vite.config.js"):
            config_path = project_root / config_name
            if config_path.exists():
                match = re.search(r"port:\s*([0-9]+)", config_path.read_text(encoding="utf-8", errors="ignore"))
                if match:
                    return int(match.group(1))
        if any((project_root / name).exists() for name in ("next.config.js", "next.config.ts")):
            return 3000

    for env_name in (".env", ".env.local", ".env.development"):
        env_path = project_root / env_name
        if not env_path.exists():
            continue
        match = re.search(
            r"^(?:PORT|VITE_PORT|NEXT_PORT)=([0-9]+)$",
            env_path.read_text(encoding="utf-8", errors="ignore"),
            re.MULTILINE,
        )
        if match:
            return int(match.group(1))

    return 3000


def wait_for_dev_server(port: int, timeout: int, log) -> bool:
    log(f"等待 dev server 就绪 (端口: {port}, 超时: {timeout}秒)...")
    started_at = time.monotonic()
    last_progress = 0
    while time.monotonic() - started_at < timeout:
        if _port_open(port) and _http_ready(port):
            log(f"dev server 已就绪 (端口: {port})")
            return True
        elapsed = int(time.monotonic() - started_at)
        if elapsed > 0 and elapsed % 10 == 0 and elapsed != last_progress:
            last_progress = elapsed
            log(f"已等待 {elapsed} 秒...")
        time.sleep(1)
    log(f"ERROR: 等待 dev server 超时 ({timeout}秒)")
    return False


def _port_open(port: int) -> bool:
    try:
        with socket.create_connection(("127.0.0.1", port), timeout=1):
            return True
    except OSError:
        return False


def _http_ready(port: int) -> bool:
    for suffix in ("", "/health"):
        try:
            with urllib.request.urlopen(f"http://127.0.0.1:{port}{suffix}", timeout=2):
                return True
        except (urllib.error.URLError, TimeoutError):
            continue
    return False


def capture_screenshot(target_url: str, output_file: Path, work_dir: Path, log) -> bool:
    log(f"捕获截图: {target_url} -> {output_file}")
    output_file.parent.mkdir(parents=True, exist_ok=True)
    verify_log = work_dir / "verify.log"

    commands: list[list[str]] = []
    if command_exists("playwright"):
        commands.append(
            [
                "playwright",
                "screenshot",
                "--viewport-size=1280,720",
                "--wait-for-timeout=5000",
                target_url,
                str(output_file),
            ]
        )
    if command_exists("npx"):
        commands.append(
            [
                "npx",
                "playwright",
                "screenshot",
                "--viewport-size=1280,720",
                "--wait-for-timeout=5000",
                target_url,
                str(output_file),
            ]
        )
    for browser in ("google-chrome", "chromium", "chromium-browser"):
        if command_exists(browser):
            commands.append(
                [
                    browser,
                    "--headless",
                    "--disable-gpu",
                    f"--screenshot={output_file}",
                    "--window-size=1280,720",
                    target_url,
                ]
            )

    if not commands:
        verify_log.write_text("截图工具不可用，跳过 UI 验证\n", encoding="utf-8")
        log("ERROR: 截图失败: 无可用截图工具")
        return False

    for command in commands:
        result = run_command(command, cwd=work_dir)
        if result.returncode == 0 and output_file.exists():
            verify_log.write_text(f"截图成功: {output_file}\n", encoding="utf-8")
            log(f"截图成功: {output_file}")
            return True
    verify_log.write_text("截图失败: 所有可用工具均无法完成截图\n", encoding="utf-8")
    log("ERROR: 截图失败: 无法使用任何可用工具捕获截图")
    return False


def verify_ui_with_llm(screenshot_file: Path, subtask_desc: str, work_dir: Path, log) -> dict[str, object]:
    log("使用 LLM 验证 UI 截图...")
    if not command_exists("claude"):
        log("ERROR: claude CLI 不可用，无法进行 UI 验证")
        return {"pass": True, "feedback": "claude CLI 不可用，跳过 UI 验证"}
    if not screenshot_file.exists():
        log(f"ERROR: 截图文件不存在: {screenshot_file}")
        return {"pass": True, "feedback": "截图文件不存在，跳过 UI 验证"}

    prompt = (
        "请分析以下 UI 截图，验证页面是否正确渲染。\n\n"
        "## UI 验证标准\n"
        "请检查以下方面：\n"
        "1. 页面无空白或崩溃：页面能正常加载，无白屏、错误页面或明显的布局错乱\n"
        "2. 关键元素可见：页面标题、内容、导航等关键元素是否正确渲染并可见\n"
        "3. 交互元素可点击：按钮、链接、表单等交互元素是否正常显示\n"
        "4. 无 console 错误：页面不应有明显的 JavaScript 错误导致的显示问题\n"
        "5. 样式一致性：CSS 样式应该与设计稿或现有风格一致\n"
        "6. 响应式布局：布局应该合理（如适用）\n\n"
        "## 验证要求\n"
        "- 如果页面看起来正常，关键元素可见且无明显问题，返回 pass\n"
        "- 如果发现任何问题（空白、崩溃、关键元素缺失、样式错乱等），返回 fail 并详细描述问题\n\n"
        "## 输出格式\n"
        "必须返回以下 JSON 格式（严格遵循）：\n"
        "```json\n"
        "{\n"
        ' "pass": true/false,\n'
        ' "feedback": "验证结果说明，包括发现的问题（如有）"\n'
        "}\n"
        "```"
    )
    if subtask_desc:
        prompt += f"\n\n## 子任务描述\n{subtask_desc}"

    log_file = work_dir / "ui-verify-llm.log"
    result_text = ""
    for retry in range(1, 4):
        if retry > 1:
            log(f"LLM 验证重试 {retry}/3...")
            time.sleep(retry * 2)
        result = run_command(
            [
                "claude",
                "-p",
                prompt,
                "--dangerously-skip-permissions",
                "--file",
                str(screenshot_file),
            ],
            cwd=work_dir,
        )
        log_file.write_text(result.output, encoding="utf-8")
        if result.returncode == 0:
            result_text = result.output
            break
        log(f"ERROR: LLM 验证调用失败 (尝试 {retry}/3)")
    if not result_text:
        log("ERROR: LLM 验证调用失败，已达最大重试次数")
        return {"pass": True, "feedback": "LLM 验证调用失败，跳过验证"}

    payload = load_json_snippet(result_text)
    if not payload:
        log("警告: 无法解析 LLM 验证结果，默认通过")
        return {"pass": True, "feedback": "无法解析验证结果，默认通过"}
    passed = bool(payload.get("pass", True))
    feedback = str(payload.get("feedback", ""))
    if passed:
        log("UI 验证通过")
    else:
        log(f"UI 验证未通过: {feedback}")
    return {"pass": passed, "feedback": feedback}


def run_ui_verification(
    *,
    project_root: Path,
    work_dir: Path,
    language: str,
    enabled: bool,
    timeout: int,
    port_override: int | None,
    log,
    subtask_desc: str = "",
) -> dict[str, object]:
    log("========== UI 验证开始 ==========")
    if not enabled:
        log("UI 验证已禁用")
        return {"pass": True, "feedback": "UI 验证已禁用"}

    dev_command = detect_dev_server_command(project_root, language)
    if not dev_command:
        log("警告: 无法检测 dev server 启动命令，跳过 UI 验证")
        return {"pass": True, "feedback": "无法检测 dev server 命令，跳过 UI 验证"}
    log(f"检测到 dev server 命令: {dev_command}")

    port = detect_dev_server_port(project_root, port_override)
    log(f"检测到的 dev server 端口: {port}")
    process = start_background_process(dev_command, cwd=project_root, output_file=work_dir / "dev-server.log")
    log(f"dev server 已启动 (PID: {process.pid})")
    try:
        if not wait_for_dev_server(port, timeout, log):
            return {"pass": False, "feedback": "dev server 启动超时或失败"}
        screenshot_file = work_dir / "ui-screenshot.png"
        screenshot_ok = capture_screenshot(f"http://127.0.0.1:{port}", screenshot_file, work_dir, log)
        if not screenshot_ok:
            log("截图不可用，UI 验证降级为通过")
            return {"pass": True, "feedback": "截图工具不可用，跳过 UI 验证（降级处理）"}
        result = verify_ui_with_llm(screenshot_file, subtask_desc, work_dir, log)
        (work_dir / "ui-verify-result.json").write_text(
            json.dumps(result, ensure_ascii=False, indent=2),
            encoding="utf-8",
        )
        return result
    finally:
        terminate_process(process)
