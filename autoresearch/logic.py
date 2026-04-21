from __future__ import annotations

import json
import random
import re
from pathlib import Path

from .models import SUPPORTED_AGENTS


FATAL_ERROR_RE = re.compile(
    r"^(Error|ERROR|Fatal|Panic|Exception)[: ]"
    r"|^(timeout|rate.limit|authentication|unauthorized|API.key).*error"
    r"|context.length.exceeded"
    r"|maximum.context.length"
    r"|token.limit.exceeded"
    r"|model.is.overloaded"
    r"|server.error"
    r"|service.unavailable"
    r"|internal.server.error"
    r"|too.many.requests"
    r"|quota.exceeded"
    r"|billing.hard.limit"
    r"|connection.refused"
    r"|network.error"
    r"|DNS.resolution",
    re.MULTILINE,
)

API_FAILURE_RE = re.compile(
    r"status.4[0-9][0-9]"
    r"|status.5[0-9][0-9]"
    r"|HTTP.4[0-9][0-9]"
    r"|HTTP.5[0-9][0-9]"
    r"|curl.*error"
    r"|fetch.failed"
    r"|request.failed"
    r"|response.is.empty"
    r"|no.response.received",
    re.MULTILINE,
)

CONTEXT_OVERFLOW_RE = re.compile(
    r"context.length.exceeded"
    r"|context.window.exceeded"
    r"|maximum.context.length"
    r"|maximum.context.window"
    r"|token.limit.exceeded"
    r"|token.limit.reached"
    r"|too.many.tokens"
    r"|exceeds.the.maximum"
    r"|exceeded.the.maximum.number.of.tokens"
    r"|input.is.too.long",
    re.IGNORECASE | re.MULTILINE,
)


def parse_agent_list(agent_list: str | None) -> list[str]:
    if not agent_list:
        return list(SUPPORTED_AGENTS)

    normalized = "".join(agent_list.split())
    if not normalized:
        return list(SUPPORTED_AGENTS)

    if normalized.startswith(",") or normalized.endswith(",") or ",," in normalized:
        raise ValueError("agent 列表格式无效: 存在空项")

    items = normalized.split(",")
    for item in items:
        if not item:
            raise ValueError("agent 列表格式无效: 存在空项")
        if item not in SUPPORTED_AGENTS:
            raise ValueError(f"未知的 agent: {item} (支持: claude, codex, opencode)")
    return items


def get_review_agent(iteration: int, num_agents: int) -> int:
    if num_agents <= 0:
        raise ValueError("num_agents must be positive")
    return (iteration - 1) % num_agents


def detect_language(project_root: Path) -> str:
    if (project_root / "go.mod").exists():
        return "go"
    if (project_root / "package.json").exists():
        return "node"
    if any((project_root / name).exists() for name in ("requirements.txt", "pyproject.toml", "setup.py")):
        return "python"
    if (project_root / "Cargo.toml").exists():
        return "rust"
    if any((project_root / name).exists() for name in ("pom.xml", "build.gradle")):
        return "java"
    return "unknown"


def get_test_command(language: str) -> str:
    return {
        "go": "go test ./... -v",
        "node": "npm test",
        "python": "pytest",
        "rust": "cargo test",
        "java": "mvn test",
    }.get(language, "")


def get_build_command(language: str) -> str:
    return {
        "go": "go build ./...",
        "node": "npm run build",
        "rust": "cargo build",
        "java": "mvn compile",
    }.get(language, "")


def get_lint_command(language: str) -> str:
    return {
        "go": "go vet ./...",
        "node": "npm run lint",
        "python": "ruff check .",
        "rust": "cargo clippy -- -D warnings",
        "java": "mvn checkstyle:check",
    }.get(language, "")


def get_required_tool(language: str) -> str:
    return {
        "go": "go",
        "node": "node",
        "python": "python3",
        "rust": "cargo",
        "java": "mvn",
    }.get(language, "")


def annealing_delay(retry: int, base: int, max_delay: int) -> int:
    delay = base * (1 << (retry - 1))
    jitter = delay // 4
    if jitter > 0:
        delay += random.randint(0, jitter - 1)
    return min(delay, max_delay)


def has_fatal_error(text: str) -> bool:
    return bool(FATAL_ERROR_RE.search(text))


def has_api_failure(text: str) -> bool:
    return bool(API_FAILURE_RE.search(text))


def detect_context_overflow_text(text: str) -> bool:
    return bool(CONTEXT_OVERFLOW_RE.search(text))


def detect_context_overflow_file(log_file: Path) -> bool:
    if not log_file.exists():
        return False
    return detect_context_overflow_text(log_file.read_text(encoding="utf-8", errors="ignore"))


def check_sentinel(review_result: str) -> str:
    lines = [line.strip() for line in review_result.splitlines() if line.strip()]
    last_lines = lines[-5:]
    if "AUTORESEARCH_RESULT:PASS" in last_lines:
        return "pass"
    if "AUTORESEARCH_RESULT:FAIL" in last_lines:
        return "fail"
    return "none"


def extract_score(review_result: str) -> int:
    match = re.search(r"([0-9]+(?:\.[0-9]+)?)\s*/\s*100", review_result)
    if match:
        return round(float(match.group(1)))

    for line in review_result.splitlines():
        if re.search(r"\*\*(评分|Score)[^*]*100", line):
            numbers = re.findall(r"[0-9]+(?:\.[0-9]+)?", line)
            if numbers:
                return round(float(numbers[0]))

    for line in review_result.splitlines():
        if (re.search(r"(\*\*)?总分(\*\*)?\s*\|", line) and re.search(r"\*\*[0-9]", line)) or re.search(r"总分.*→", line):
            numbers = re.findall(r"[0-9]+(?:\.[0-9]+)?", line)
            if numbers:
                return round(float(numbers[-1]) * 10)

    match = re.search(r"([0-9]+(?:\.[0-9]+)?)\s*/\s*10", review_result)
    if match:
        return round(float(match.group(1)) * 10)

    for line in review_result.splitlines():
        if re.search(r"\*\*(评分|Score)", line):
            numbers = re.findall(r"[0-9]+(?:\.[0-9]+)?", line)
            if numbers:
                value = float(numbers[0])
                return round(value * 10 if value <= 10 else value)

    for line in review_result.splitlines():
        if re.search(r"(评分|Score)\s*:", line) and not re.search(r"各维度|维度", line):
            numbers = re.findall(r"[0-9]+(?:\.[0-9]+)?", line)
            if numbers:
                value = float(numbers[0])
                return round(value * 10 if value <= 10 else value)
    return 0


def check_score_passed(score: int, passing_score: int) -> bool:
    return score >= passing_score


def extract_markdown_json_block(text: str) -> str:
    match = re.search(r"```json\s*(.*?)```", text, re.DOTALL | re.IGNORECASE)
    if match:
        return match.group(1).strip()
    return ""


def extract_json_snippet(text: str) -> str:
    block = extract_markdown_json_block(text)
    if block:
        return block

    start = text.find("{")
    end = text.rfind("}")
    if start != -1 and end != -1 and end > start:
        return text[start : end + 1]
    return ""


def load_json_snippet(text: str) -> dict[str, object] | None:
    snippet = extract_json_snippet(text)
    if not snippet:
        return None
    try:
        payload = json.loads(snippet)
    except json.JSONDecodeError:
        return None
    if isinstance(payload, dict):
        return payload
    return None


def extract_learnings(text: str) -> str:
    lines = text.splitlines()
    start = None
    for idx, line in enumerate(lines):
        if line.startswith("## Learnings"):
            start = idx
            break
    if start is not None:
        collected: list[str] = []
        for idx in range(start, len(lines)):
            line = lines[idx]
            if idx > start and line.startswith("## "):
                break
            collected.append(line)
        return "\n".join(collected).strip()

    non_empty = [line for line in lines if line.strip()]
    return "\n".join(non_empty[:30]).strip()


def truncate_text(text: str, max_chars: int) -> str:
    if len(text) <= max_chars:
        return text
    return text[:max_chars]


def extract_section(markdown: str, heading: str) -> str:
    pattern = re.compile(rf"^{re.escape(heading)}\s*$", re.MULTILINE)
    match = pattern.search(markdown)
    if not match:
        return ""
    start = match.start()
    lines = markdown[start:].splitlines()
    collected: list[str] = []
    for idx, line in enumerate(lines):
        if idx > 0 and line.startswith("## "):
            break
        collected.append(line)
    return "\n".join(collected).strip()


def find_last_iteration(work_dir: Path) -> int:
    if not work_dir.exists():
        return 0
    last = 0
    for path in work_dir.iterdir():
        match = re.match(r"iteration-(\d+).+\.log$", path.name)
        if match:
            last = max(last, int(match.group(1)))
    return last
