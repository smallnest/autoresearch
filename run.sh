#!/bin/bash
# autoresearch/run.sh - 自动化处理 GitHub Issue
#
# 通用版本 - 可处理任意 Git + GitHub 项目
#
# 用法:
#   ./run.sh [-p project_path] [-a agents] [-c] [--no-archive] [--no-ui-verify] [--no-hard-gate] [--issue-source=<mode>] [--space=<prefixCode>] [--target-branch=<name>] <issue_number> [max_iterations]
#
# 示例:
#   ./run.sh 42                              # 处理当前目录项目的 Issue #42
#   ./run.sh -p /path/to/project 42         # 处理指定项目的 Issue #42
#   ./run.sh -p /path/to/project 42 10      # 最多迭代 10 次
#   ./run.sh -a claude,codex 42              # 只启用 Claude 和 Codex
#   ./run.sh -a claude 42                    # 单 agent 模式
#   ./run.sh -a claude,opencode,codex 42     # 自定义 agent 顺序
# ./run.sh --no-archive 42 # 跳过归档（调试用）
#   ./run.sh --issue-source=baidu --space=cloud-iCafe 22210  # 百度 iCafe 模式
#
# 环境变量配置:
# AGENT_TIMEOUT: agent 调用超时秒数 (默认: 600)
# UI_VERIFY_ENABLED: 是否启用 UI 验证 (默认: yes)
# UI_VERIFY_TIMEOUT: dev server 等待超时秒数 (默认: 60)
# UI_DEV_PORT: dev server 端口 (默认自动检测或使用 3000)
#
# 要求:
# - 项目目录必须是 git 仓库
# - 项目目录必须有 GitHub remote (origin)
#
# 配置文件 (可选):
#   在项目根目录创建 .autoresearch/ 目录，可以放置:
#   - .autoresearch/agents/codex.md     自定义 Codex 指令
#   - .autoresearch/agents/claude.md    自定义 Claude 指令
#   - .autoresearch/agents/opencode.md  自定义 OpenCode 指令
#   - .autoresearch/program.md          自定义实现规则与约束

set -e
set -o pipefail

# 设置 locale 避免 awk/sed/grep 的多字节转换错误
export LC_ALL=C
export LANG=C

# ==================== 环境变量处理 ====================
if [ -f "$HOME/.zshrc" ]; then
    eval "$(grep -E '^export (OPENROUTER_API_KEY|OPENAI_API_KEY|ANTHROPIC_API_KEY)=' "$HOME/.zshrc" 2>/dev/null)" || true
fi

# ==================== 配置 ====================
DEFAULT_MAX_ITERATIONS=42
PASSING_SCORE=85
MAX_CONSECUTIVE_FAILURES=3
MAX_RETRIES=5
RETRY_BASE_DELAY=2
RETRY_MAX_DELAY=60
MAX_CONTEXT_RETRIES=${MAX_CONTEXT_RETRIES:-3}
CONTEXT_COMPRESS_THRESHOLD=${CONTEXT_COMPRESS_THRESHOLD:-150000}
CONTEXT_KEEP_RECENT=${CONTEXT_KEEP_RECENT:-3}
AGENT_TIMEOUT=${AGENT_TIMEOUT:-600}
PROMPT_TRIMMED=0  # 上下文溢出后的裁剪级别 (0=无, 1=轻度, 2=中度, 3=重度)

# 脚本所在目录（用于查找默认 agents 配置和 program.md）
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 共享 agent 逻辑
AGENT_LOGIC_LIB="$SCRIPT_DIR/lib/agent_logic.sh"
if [ ! -f "$AGENT_LOGIC_LIB" ]; then
    echo "ERROR: 缺少 agent 逻辑文件: $AGENT_LOGIC_LIB" >&2
    exit 1
fi
# shellcheck source=/dev/null
source "$AGENT_LOGIC_LIB"

GIT_PUSH_LIB="$SCRIPT_DIR/lib/git_push.sh"
if [ ! -f "$GIT_PUSH_LIB" ]; then
    echo "ERROR: 缺少 git push 逻辑文件: $GIT_PUSH_LIB" >&2
    exit 1
fi
# shellcheck source=/dev/null
source "$GIT_PUSH_LIB"

BRANCH_CLEANUP_LIB="$SCRIPT_DIR/lib/branch_cleanup.sh"
if [ ! -f "$BRANCH_CLEANUP_LIB" ]; then
    echo "ERROR: 缺少 branch cleanup 逻辑文件: $BRANCH_CLEANUP_LIB" >&2
    exit 1
fi
# shellcheck source=/dev/null
source "$BRANCH_CLEANUP_LIB"

# 特性开关（CLI 参数可禁用）
FEATURE_UI_VERIFY=1
FEATURE_HARD_GATE=1

# Issue 来源模式: "github" (默认) | "local" (本地文件) | "baidu" (iCafe + iCode)
ISSUE_SOURCE="github"
# 本地 Issue 目录 (由 --issues-dir 设置或自动检测)
ISSUES_DIR=""
# 本地 Issue 文件路径 (由 get_local_issue_info 设置)
ISSUE_FILE=""
# 百度 iCafe 空间前缀代码 (由 --space 设置或 ICAFE_SPACE 环境变量)
ICAFE_SPACE="${ICAFE_SPACE:-}"
# 百度 iCafe 卡片类型 (由 get_baidu_issue_info 设置)
ICAFE_CARD_TYPE=""
# 百度 iCode CR 目标分支 (由 --target-branch 设置或自动检测)
ICODE_TARGET_BRANCH=""
# 百度 iCode CR 编号 (由 push_cr 流程设置)
ICODE_CR_NUMBER=""
# 百度 iCode 仓库路径 (由 check_project 从 remote URL 提取)
ICODE_REPO=""

# 共享库：核心逻辑
for _lib in scoring context progress subtask prompt ui_verify; do
    _lib_path="$SCRIPT_DIR/lib/${_lib}.sh"
    if [ ! -f "$_lib_path" ]; then
        echo "ERROR: 缺少库文件: $_lib_path" >&2
        exit 1
    fi
    # shellcheck source=/dev/null
    source "$_lib_path"
done
unset _lib _lib_path

# 默认项目根目录 = 当前工作目录 (可通过 -p 参数覆盖)
PROJECT_ROOT="$(pwd)"

# ==================== 函数 ====================

# 日志只写入文件，不输出到终端
log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    if [ -n "$WORK_DIR" ] && [ -d "$WORK_DIR" ]; then
        echo "$msg" >> "$WORK_DIR/terminal.log"
    fi
}

# 关键信息输出到终端并写入文件
log_console() {
    local msg="$1"
    local timestamp
    timestamp=$(date '+%H:%M:%S')
    # 使用 UTF-8 locale 输出中文
    LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8 echo "[$timestamp] $msg"
    if [ -n "$WORK_DIR" ] && [ -d "$WORK_DIR" ]; then
        LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8 echo "[$(date '+%Y-%m-%d %H:%M:%S')] $msg" >> "$WORK_DIR/terminal.log"
    fi
}

error() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1"
    LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8 echo "$msg" >&2
    if [ -n "$WORK_DIR" ] && [ -d "$WORK_DIR" ]; then
        LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8 echo "$msg" >> "$WORK_DIR/terminal.log"
    fi
}

# 检测项目使用的编程语言
detect_language() {
    if [ -f "$PROJECT_ROOT/go.mod" ]; then
        echo "go"
    elif [ -f "$PROJECT_ROOT/package.json" ]; then
        echo "node"
    elif [ -f "$PROJECT_ROOT/requirements.txt" ] || [ -f "$PROJECT_ROOT/pyproject.toml" ] || [ -f "$PROJECT_ROOT/setup.py" ]; then
        echo "python"
    elif [ -f "$PROJECT_ROOT/Cargo.toml" ]; then
        echo "rust"
    elif [ -f "$PROJECT_ROOT/pom.xml" ] || [ -f "$PROJECT_ROOT/build.gradle" ]; then
        echo "java"
    else
        echo "unknown"
    fi
}

# 检测测试命令
get_test_command() {
    local lang=$(detect_language)
    case "$lang" in
        go)     echo "go test ./... -v" ;;
        node)   echo "npm test" ;;
        python) echo "pytest" ;;
        rust)   echo "cargo test" ;;
        java)   echo "mvn test" ;;
        *)      echo "" ;;
    esac
}

# 检测构建命令
get_build_command() {
    local lang=$(detect_language)
    case "$lang" in
        go)     echo "go build ./..." ;;
        node)   echo "npm run build" ;;
        rust)   echo "cargo build" ;;
        java)   echo "mvn compile" ;;
        *)      echo "" ;;
    esac
}

# 检测 lint 命令
get_lint_command() {
    local lang=$(detect_language)
    case "$lang" in
        go)     echo "go vet ./..." ;;
        node)   echo "npm run lint" ;;
        python) echo "ruff check ." ;;
        rust)   echo "cargo clippy -- -D warnings" ;;
        java)   echo "mvn checkstyle:check" ;;
        *)      echo "" ;;
    esac
}

# 硬门禁检查：依次执行 build → lint → test
# 参数: $1 = 迭代号
# 返回: 0 = 全部通过, 1 = 有阶段失败
# 日志: $WORK_DIR/hard-gate-$iteration.log
run_hard_gate_checks() {
    local iteration=$1
    local log_file="$WORK_DIR/hard-gate-$iteration.log"
    local errors=""
    local failed=0

    cd "$PROJECT_ROOT"

    : > "$log_file"
    echo "=== 硬门禁检查 (迭代 $iteration) ===" >> "$log_file"
    echo "时间: $(date '+%Y-%m-%d %H:%M:%S')" >> "$log_file"
    echo "" >> "$log_file"

    # --- 构建检查 ---
    local build_cmd
    build_cmd=$(get_build_command)
    echo "--- 构建 ---" >> "$log_file"
    if [ -n "$build_cmd" ]; then
        start_spinner "构建中..."
        echo "命令: $build_cmd" >> "$log_file"
        local build_out build_rc
        build_out=$($build_cmd 2>&1) ; build_rc=$?
        echo "$build_out" >> "$log_file"
        stop_spinner
        if [ $build_rc -eq 0 ]; then
            echo "结果: 通过" >> "$log_file"
        else
            echo "结果: 失败 (exit code: $build_rc)" >> "$log_file"
            local build_tail
            build_tail=$(echo "$build_out" | tail -20)
            errors="${errors}## 构建失败 ($build_cmd)\n\n\`\`\`\n${build_tail}\n\`\`\`\n\n"
            failed=1
            log_console "❌ 构建失败"
        fi
    else
        echo "结果: 跳过 (无构建命令)" >> "$log_file"
    fi
    echo "" >> "$log_file"

    # --- Lint 检查 ---
    if [ $failed -eq 0 ]; then
        local lint_cmd
        lint_cmd=$(get_lint_command)
        echo "--- Lint ---" >> "$log_file"
        if [ -n "$lint_cmd" ]; then
            start_spinner "Lint 检查中..."
            echo "命令: $lint_cmd" >> "$log_file"
            local lint_out lint_rc
            lint_out=$($lint_cmd 2>&1) ; lint_rc=$?
            echo "$lint_out" >> "$log_file"
            stop_spinner
            if [ $lint_rc -eq 0 ]; then
                echo "结果: 通过" >> "$log_file"
            else
                echo "结果: 失败 (exit code: $lint_rc)" >> "$log_file"
                local lint_tail
                lint_tail=$(echo "$lint_out" | tail -20)
                errors="${errors}## Lint 失败 ($lint_cmd)\n\n\`\`\`\n${lint_tail}\n\`\`\`\n\n"
                failed=1
                log_console "❌ Lint 失败"
            fi
        else
            echo "结果: 跳过 (无 lint 命令)" >> "$log_file"
        fi
    fi
    echo "" >> "$log_file"

    # --- 测试 ---
    if [ $failed -eq 0 ]; then
        local test_cmd
        test_cmd=$(get_test_command)
        echo "--- 测试 ---" >> "$log_file"
        if [ -n "$test_cmd" ]; then
            start_spinner "运行测试中..."
            echo "命令: $test_cmd" >> "$log_file"
            local test_out test_rc
            test_out=$($test_cmd 2>&1) ; test_rc=$?
            echo "$test_out" >> "$log_file"
            stop_spinner
            if [ $test_rc -eq 0 ]; then
                echo "结果: 通过" >> "$log_file"
            else
                echo "结果: 失败 (exit code: $test_rc)" >> "$log_file"
                local test_tail
                test_tail=$(echo "$test_out" | tail -20)
                errors="${errors}## 测试失败 ($test_cmd)\n\n\`\`\`\n${test_tail}\n\`\`\`\n\n"
                failed=1
                log_console "❌ 测试失败"
            fi
        else
            echo "结果: 跳过 (无测试命令)" >> "$log_file"
        fi
    fi
    echo "" >> "$log_file"

    # --- 汇总 ---
    echo "=== 汇总 ===" >> "$log_file"
    if [ $failed -eq 0 ]; then
        echo "状态: 全部通过" >> "$log_file"
    else
        echo "状态: 失败" >> "$log_file"
        echo -e "$errors" >> "$log_file"
    fi

    return $failed
}

# 检测项目语言用于依赖检查
get_required_tools() {
    local lang=$(detect_language)
    case "$lang" in
        go)     echo "go" ;;
        node)   echo "node" ;;
        python) echo "python3" ;;
        rust)   echo "cargo" ;;
        java)   echo "mvn" ;;
        *)      echo "" ;;
    esac
}

annealing_delay() {
    local retry=$1
    local delay=$((RETRY_BASE_DELAY * (1 << (retry - 1))))
    local jitter=$((delay / 4))
    if [ $jitter -gt 0 ]; then
        jitter=$((RANDOM % jitter))
    fi
    delay=$((delay + jitter))
    if [ $delay -gt $RETRY_MAX_DELAY ]; then
        delay=$RETRY_MAX_DELAY
    fi
    echo $delay
}

# 检测 Agent 输出是否包含致命错误（区分代码讨论中的 "error" 与真正的运行时错误）
has_fatal_error() {
    local log_file="$1"
    # 匹配 API/模型级别的致命错误，排除工具操作级别的非致命错误（如文件不存在、权限拒绝等）
    # Agent 日志中常有 "Error: File not found" / "read failed" 等工具操作错误，这些不是致命错误
    local pattern='context.length.exceeded'
    pattern+='|maximum.context.length'
    pattern+='|token.limit.exceeded'
    pattern+='|model.is.overloaded'
    pattern+='|server.error'
    pattern+='|service.unavailable'
    pattern+='|internal.server.error'
    pattern+='|too.many.requests'
    pattern+='|quota.exceeded'
    pattern+='|billing.hard.limit'
    pattern+='|connection.refused'
    pattern+='|network.error'
    pattern+='|DNS.resolution'
    pattern+='|Timed.out'
    pattern+='|Command.timed.out'
    pattern+='|authentication.error'
    pattern+='|unauthorized.access'
    pattern+='|API.key.(invalid|missing|expired)'
    pattern+='|rate.limit.exceeded'
    pattern+='|Fatal.error'
    pattern+='|Panic[: ]'
    # 排除缩进行(代码块)和代码特征行
    grep -vE '^[[:space:]]' "$log_file" 2>/dev/null \
        | grep -vE '(fmt\.|strings\.|errors\.|io\.|net/http|func |type |struct|\*http\.|//.*return|//.*if|//.*error|\+\s*(func|type|var|const) )' \
        | grep -vE '(File not found|read failed|Permission denied|No such file|command not found|auto.reject)' \
        | grep -vE 'codex_core::session: failed to record rollout' \
        | grep -qE "$pattern"
}

# 检测 Agent 输出是否包含 API/网络级别的失败（区分于可恢复的内容错误）
has_api_failure() {
    local log_file="$1"
    # 仅匹配非缩进、非代码行的 API/网络失败模式，避免误判代码中的字符串（如 "status 503"）
    # 先排除缩进行(代码块)和常见代码模式行，再匹配 CLI 错误输出
    local pattern='status.4[0-9][0-9]'
    pattern+='|status.5[0-9][0-9]'
    pattern+='|HTTP.4[0-9][0-9]'
    pattern+='|HTTP.5[0-9][0-9]'
    pattern+='|curl.*error'
    pattern+='|fetch.failed'
    pattern+='|request.failed'
    pattern+='|response.is.empty'
    pattern+='|no.response.received'
    # 排除缩进行(空格/tab开头)和代码特征行
    grep -vE '^[[:space:]]' "$log_file" 2>/dev/null \
        | grep -vE '(fmt\.|strings\.|errors\.|io\.|net/http|func |type |struct|\*http\.|//.*return|//.*if|//.*error|\+\s*(func|type|var|const) )' \
        | grep -qE "$pattern"
}

# 超时包裹器：优先使用 GNU timeout/gtimeout，回退到 shell 原生方案
# 用法: timeout_wrapper <seconds> <command> [args...]
# 返回值: 命令退出码，超时时返回 124
timeout_wrapper() {
    local timeout_sec=$1
    shift

    if command -v timeout &>/dev/null; then
        timeout "$timeout_sec" "$@"
    elif command -v gtimeout &>/dev/null; then
        gtimeout "$timeout_sec" "$@"
    else
        # Shell 原生方案：后台进程 + sleep + kill
        "$@" &
        local cmd_pid=$!
        (
            sleep "$timeout_sec"
            kill "$cmd_pid" 2>/dev/null
        ) &
        local watchdog_pid=$!

        wait "$cmd_pid" 2>/dev/null
        local cmd_exit=$?
        kill "$watchdog_pid" 2>/dev/null
        wait "$watchdog_pid" 2>/dev/null

        # 如果命令被 SIGTERM (143) 或 SIGKILL (137) 终止，视为超时
        if [ $cmd_exit -eq 143 ] || [ $cmd_exit -eq 137 ]; then
            return 124
        fi
        return $cmd_exit
    fi
}

# 检测 Codex 是否因无效 tool call 参数导致 400 错误（不可通过相同 prompt 重试）
has_invalid_tool_call() {
    local log_file="$1"
    grep -qE 'invalid.function.arguments|invalid params.*tool_call' "$log_file" 2>/dev/null
}

# 裁剪 prompt 以避免 Codex 生成相同的 malformed tool call
# 策略：截断 prompt 到最后 4000 字符，并加上禁止 tool call 的前缀
trim_prompt_for_codex_retry() {
    local prompt="$1"
    local trimmed="${prompt: -4000}"
    echo "IMPORTANT: Do NOT use any tool/function calls. Output plain text only. If you need to reference files, describe them in text instead of reading them.

---

$trimmed"
}

# 检测 MiniMax 等模型的 tool_call 格式错误（重试无意义，需要终止当前调用）
has_toolcall_format_error() {
    local log_file="$1"
    # MiniMax 模型返回 malformed tool_call arguments（数组格式、多余逗号等）
    # 这类错误在 agent 内部会话中累积，重试同样的 prompt 无法解决
    local pattern='invalid.function.arguments.json'
    pattern+='|invalid.params.*tool_call'
    pattern+='|bad_request_error.*tool_call'
    pattern+='|MinimaxException'
    grep -qE "$pattern" "$log_file" 2>/dev/null
}

# 检测 Agent 输出是否包含上下文溢出信号
# Context overflow & compression functions are in lib/context.sh

# 等待动画帧 - 火箭发射动画
SPINNER_ROCKET=(
    "🚀     "
    " 🚀    "
    "  🚀   "
    "   🚀  "
    "    🚀 "
    "     🚀"
    "    ✨  "
    "   ✨   "
)
SPINNER_PID=""

# 全局临时文件追踪（用于 cleanup 函数清理）
GLOBAL_TEMP_FILES=""

# 启动等待动画
start_spinner() {
    local msg="$1"
    (
        i=0
        while true; do
            local frame=$((i % 8))
            local rocket="${SPINNER_ROCKET[$frame]}"
            printf "\r  %s %s  " "$rocket" "$msg"
            sleep 0.12
            i=$((i + 1))
        done
    ) &
    SPINNER_PID=$!
}

# 停止等待动画
stop_spinner() {
    if [ -n "$SPINNER_PID" ] && kill -0 "$SPINNER_PID" 2>/dev/null; then
        kill "$SPINNER_PID" 2>/dev/null || true
        wait "$SPINNER_PID" 2>/dev/null || true
    fi
    SPINNER_PID=""
    # 清除当前行并换行，避免残留
    printf "\r                                                          \r"
}

# 注册临时文件/目录，用于 cleanup 时自动清理
# 用法: register_temp_file /path/to/temp/file
register_temp_file() {
    local temp_path="$1"
    if [ -n "$temp_path" ]; then
        if [ -z "$GLOBAL_TEMP_FILES" ]; then
            GLOBAL_TEMP_FILES="$temp_path"
        else
            GLOBAL_TEMP_FILES="$GLOBAL_TEMP_FILES"$'\n'"$temp_path"
        fi
    fi
}

# 标记脚本是否正常完成（用于 cleanup 函数判断是否记录中断）
SCRIPT_COMPLETED_NORMALLY=0
CLEANUP_ALREADY_RAN=0

# 列出某个父进程的直接子进程 PID，优先使用 pgrep，失败时回退到 ps
list_child_pids() {
    local parent_pid="$1"
    local child_pids=""

    if command -v pgrep >/dev/null 2>&1; then
        child_pids=$(pgrep -P "$parent_pid" 2>/dev/null) || child_pids=""
    fi

    if [ -z "$child_pids" ] && command -v ps >/dev/null 2>&1; then
        child_pids=$(ps -eo pid=,ppid= 2>/dev/null | awk -v ppid="$parent_pid" '$2 == ppid { print $1 }') || child_pids=""
    fi

    if [ -n "$child_pids" ]; then
        printf '%s\n' "$child_pids"
    fi
}

# 递归收集某个进程的所有后代进程 PID（深度优先，子孙在前）
collect_descendant_pids() {
    local parent_pid="$1"
    local child_pid

    while IFS= read -r child_pid; do
        [ -z "$child_pid" ] && continue
        collect_descendant_pids "$child_pid"
        echo "$child_pid"
    done < <(list_child_pids "$parent_pid")
}

# 全局清理函数
# 当脚本被中断或退出时调用，清理所有资源
# 使用方法：trap 'cleanup EXIT' EXIT
cleanup() {
    local exit_signal="${1:-EXIT}"
    local exit_code=$?  # 必须在函数开始时捕获，后续命令会覆盖

    if [ "$CLEANUP_ALREADY_RAN" -eq 1 ]; then
        return 0
    fi
    CLEANUP_ALREADY_RAN=1

    # 1. 清理 spinner 进程（复用 stop_spinner 函数）
    stop_spinner

    # 2. 清理 dev server 进程（复用 cleanup_dev_server 函数）
    cleanup_dev_server

    # 3. 清理残留 agent 子进程
    # 查找并清理可能残留的 claude/codex/opencode 进程
    # 使用进程组清理，避免误杀其他进程
    local descendant_pids
    descendant_pids=$(collect_descendant_pids "$$") || true
    if [ -n "$descendant_pids" ]; then
        for pid in $descendant_pids; do
            if kill -0 "$pid" 2>/dev/null; then
                kill "$pid" 2>/dev/null || true
            fi
        done
        # 等待子进程退出
        sleep 1
        # 强制清理未退出的子进程
        for pid in $descendant_pids; do
            if kill -0 "$pid" 2>/dev/null; then
                kill -9 "$pid" 2>/dev/null || true
            fi
        done
    fi

    # 4. 清理全局临时文件/目录
    # 遍历 GLOBAL_TEMP_FILES 中注册的所有临时路径并清理
    if [ -n "$GLOBAL_TEMP_FILES" ]; then
        while IFS= read -r temp_path; do
            if [ -z "$temp_path" ]; then
                continue
            fi
            if [ -d "$temp_path" ]; then
                rm -rf "$temp_path" 2>/dev/null || true
            elif [ -f "$temp_path" ]; then
                rm -f "$temp_path" 2>/dev/null || true
            fi
        done <<< "$GLOBAL_TEMP_FILES"
    fi

    # 5. 记录中断位置到 log.md（仅当非正常退出时）
    # EXIT 信号在正常退出时也会触发，所以需要检查 SCRIPT_COMPLETED_NORMALLY
    # 连续失败硬停和达到最大迭代次数会在 exit 前设置 SCRIPT_COMPLETED_NORMALLY=1
    if [ -n "$WORK_DIR" ] && [ -d "$WORK_DIR" ] && [ "$SCRIPT_COMPLETED_NORMALLY" -eq 0 ]; then
        local log_file="$WORK_DIR/log.md"
        local interrupt_time
        interrupt_time=$(date '+%Y-%m-%d %H:%M:%S')

        # 获取当前状态信息
        local current_iteration="${ITERATION:-0}"
        local current_score="${FINAL_SCORE:-0}"
        local current_branch="${BRANCH_NAME:-unknown}"
        local issue_num="${ISSUE_NUMBER:-unknown}"

        # 分析退出原因
        local exit_reason="未知"
        case "$exit_code" in
            0)   exit_reason="正常退出（但 SCRIPT_COMPLETED_NORMALLY 未设置）" ;;
            1)   exit_reason="通用错误" ;;
            2)   exit_reason="误用 shell 命令" ;;
            126) exit_reason="命令无法执行" ;;
            127) exit_reason="命令未找到" ;;
            128) exit_reason="退出参数无效" ;;
            130) exit_reason="被 SIGINT (Ctrl+C) 中断" ;;
            137) exit_reason="被 SIGKILL 终止" ;;
            143) exit_reason="被 SIGTERM 终止" ;;
            *)   exit_reason="退出码 $exit_code" ;;
        esac

        # 检查是否是 set -e 导致的退出（命令返回非零）
        if [ "$exit_signal" = "EXIT" ] && [ "$exit_code" -ne 0 ] && [ "$exit_code" -lt 128 ]; then
            exit_reason="命令失败（set -e 触发）- $exit_reason"
        fi

        # 追加中断记录
        {
            echo ""
            echo "---"
            echo ""
            echo "## ⚠️ 脚本被中断"
            echo ""
            echo "- **中断信号**: $exit_signal"
            echo "- **退出码**: $exit_code"
            echo "- **退出原因**: $exit_reason"
            echo "- **中断时间**: $interrupt_time"
            echo "- **Issue**: #$issue_num"
            echo "- **当前迭代**: $current_iteration"
            echo "- **当前评分**: $current_score/100"
            echo "- **当前分支**: $current_branch"
            if [ -n "$LAST_COMMAND" ]; then
                echo "- **最后执行命令**: \`$LAST_COMMAND\`"
            fi
            echo ""
            echo "> 使用 \`./run.sh -c $issue_num\` 可继续运行"
        } >> "$log_file" 2>/dev/null || true

        log_console ""
        log_console "⚠️ 脚本被 $exit_signal 信号中断"
        log_console "📋 退出码: $exit_code ($exit_reason)"
        if [ -n "$LAST_COMMAND" ]; then
            log_console "🔧 最后执行命令: $LAST_COMMAND"
        fi
        log_console "📝 中断信息已记录到 $log_file"
        log_console "💡 使用 ./run.sh -c $issue_num 可继续运行"
    fi

    # 清除终端行
    printf "\r                                                          \r"
}

# ==================== 全局 Trap 设置 ====================
# 在脚本入口处设置 trap，确保在任何阶段中断都能正确清理资源
# cleanup 函数已设计为能安全处理所有未初始化变量的情况
# EXIT 信号在正常退出时也会触发，cleanup 内部通过 SCRIPT_COMPLETED_NORMALLY 区分
# INT/TERM 信号处理：先调用 cleanup，再禁用 EXIT trap 避免重复执行，最后以特定退出码退出
# DEBUG trap 用于记录最后执行的命令，帮助定位 set -e 触发的具体命令
LAST_COMMAND=""
trap 'LAST_COMMAND="$BASH_COMMAND"' DEBUG
trap 'cleanup EXIT' EXIT
trap 'cleanup INT; trap - EXIT; exit 130' INT
trap 'cleanup TERM; trap - EXIT; exit 143' TERM

run_with_retry() {
    local agent=$1
    local prompt="$2"
    local log_file="$3"
    local retry=0
    local success=0
    local skip_agent=0

    while [ $retry -lt $MAX_RETRIES ]; do
        retry=$((retry + 1))

        if [ $retry -gt 1 ]; then
            local delay
            delay=$(annealing_delay $retry)
            log_console "重试 $retry/$MAX_RETRIES，等待 ${delay} 秒..."
            sleep $delay
        fi

        log_console "调用 $agent (尝试 $retry/$MAX_RETRIES)..."

        # Truncate log file before each attempt so we only capture this attempt's output
        : > "$log_file"

        local exit_code=1

        # 启动等待动画
        start_spinner "$agent 正在工作中..."

        if [ "$agent" = "codex" ]; then
            timeout_wrapper "$AGENT_TIMEOUT" codex exec --full-auto "$prompt" > "$log_file" 2>&1 && exit_code=0 || exit_code=$?
        elif [ "$agent" = "opencode" ]; then
            timeout_wrapper "$AGENT_TIMEOUT" opencode run --dangerously-skip-permissions "$prompt" > "$log_file" 2>&1 && exit_code=0 || exit_code=$?
        else
            timeout_wrapper "$AGENT_TIMEOUT" claude -p "$prompt" --dangerously-skip-permissions > "$log_file" 2>&1 && exit_code=0 || exit_code=$?
        fi

        # 停止等待动画
        stop_spinner

        # Check for context overflow first (non-retryable)
        if detect_context_overflow "$log_file"; then
            log_console "检测到上下文溢出，停止重试"
            break
        fi

        # Check for MiniMax tool_call format errors (non-retryable: model bug, skip this agent)
        if has_toolcall_format_error "$log_file"; then
            local error_tail
            error_tail=$(tail -10 "$log_file" 2>/dev/null)
            log_console "⚠️ $agent 遇到 MiniMax tool_call 格式错误，终止并跳过此 agent"
            if [ -n "$error_tail" ]; then
                log_console "错误信息:"
                echo "$error_tail" | while read -r line; do log_console "  $line"; done
            fi
            skip_agent=1
            break
        fi

        # Check for non-zero exit code from the agent
        if [ $exit_code -ne 0 ]; then
            local error_tail
            error_tail=$(tail -10 "$log_file" 2>/dev/null)

            # Timeout exit code 124 is retryable
            if [ $exit_code -eq 124 ]; then
                log_console "⏱️ $agent 调用超时 (超时限制: ${AGENT_TIMEOUT}s)，将重试"
                continue
            fi

            # Special handling for Codex invalid tool call: trim prompt and retry
            if [ "$agent" = "codex" ] && has_invalid_tool_call "$log_file"; then
                log_console "⚠️ Codex 生成无效 tool call 参数，裁剪 prompt 重试"
                prompt=$(trim_prompt_for_codex_retry "$prompt")
                continue
            fi

            log_console "❌ $agent 调用失败 (退出码: $exit_code)"
            if [ -n "$error_tail" ]; then
                log_console "错误信息:"
                echo "$error_tail" | while read -r line; do log_console "  $line"; done
            fi
            continue
        fi

        # Check for fatal errors in output
        if has_fatal_error "$log_file"; then
            local error_tail
            error_tail=$(tail -10 "$log_file" 2>/dev/null)

            # Special handling for Codex invalid tool call: trim prompt and retry once
            if [ "$agent" = "codex" ] && has_invalid_tool_call "$log_file"; then
                log_console "⚠️ Codex 生成无效 tool call 参数，裁剪 prompt 重试"
                prompt=$(trim_prompt_for_codex_retry "$prompt")
                continue
            fi

            log_console "❌ $agent 调用失败 (检测到致命错误)"
            if [ -n "$error_tail" ]; then
                log_console "错误信息:"
                echo "$error_tail" | while read -r line; do log_console "  $line"; done
            fi
            continue
        fi

        # Check for API failures in output
        if has_api_failure "$log_file"; then
            local error_tail
            error_tail=$(tail -10 "$log_file" 2>/dev/null)

            # Special handling for Codex invalid tool call in API failure path
            if [ "$agent" = "codex" ] && has_invalid_tool_call "$log_file"; then
                log_console "⚠️ Codex 生成无效 tool call 参数，裁剪 prompt 重试"
                prompt=$(trim_prompt_for_codex_retry "$prompt")
                continue
            fi

            log_console "❌ $agent 调用失败 (API 错误)"
            if [ -n "$error_tail" ]; then
                log_console "错误信息:"
                echo "$error_tail" | while read -r line; do log_console "  $line"; done
            fi
            continue
        fi

        # Check file existence and non-empty (guards against filesystem errors / race conditions)
        if [ ! -f "$log_file" ] || [ ! -s "$log_file" ]; then
            log_console "❌ $agent 调用失败 (输出文件不存在或为空，将重试)"
            continue
        fi

        # Check output quality: must have meaningful content
        local content_lines
        content_lines=$(grep -vE '^\s*$' "$log_file" | wc -l)
        if [ "$content_lines" -lt 5 ]; then
            log_console "❌ $agent 调用失败 (输出内容过少: $content_lines 行)"
            continue
        fi

        success=1
        break
    done

    if [ $success -eq 1 ]; then
        return 0
    elif [ $skip_agent -eq 1 ]; then
        error "$agent 遇到不可恢复的模型错误，跳过此 agent"
        return 2
    else
        error "$agent 调用失败，已重试 $MAX_RETRIES 次"
        return 1
    fi
}

usage() {
    echo "用法: $0 [-p project_path] [-a agents] [-c] [--no-archive] [--no-ui-verify] [--no-hard-gate] [--issue-source=<mode>] [--space=<prefixCode>] [--target-branch=<name>] <issue_number> [max_iterations]"
    echo ""
    echo "通用自动化 Issue 处理工具，支持 GitHub / 本地 / 百度 iCafe 三种来源。"
    echo ""
    echo "参数:"
    echo "  -p <path>        项目路径 (默认: 当前目录)"
    echo "  -a <agents>      逗号分隔的 agent 列表 (默认: claude,codex,opencode)"
    echo "                   第一个 agent 用于初始实现，后续 agent 按顺序轮流审核+修复"
    echo "  -c               继续模式，从上次中断的迭代继续"
    echo "  --no-archive     跳过归档其他 Issue 的 workflows 数据 (调试用)"
    echo "  --no-ui-verify   禁用 UI 验证 (默认启用)"
    echo "  --no-hard-gate   禁用硬门禁检查 (build/lint/test 预检, 默认启用)"
    echo "  --issues-dir=<path>  本地 Issue 目录 (启用本地模式，不使用 GitHub)"
    echo "  --issue-source=<mode>  Issue 来源: github (默认) | local | baidu"
    echo "  --space=<prefixCode>   iCafe 空间前缀代码 (baidu 模式必需，也可用 ICAFE_SPACE 环境变量)"
    echo "  --target-branch=<name> iCode CR 目标分支 (默认: 自动检测远程 HEAD 分支，回退到 master)"
    echo "  issue_number     Issue 编号 (GitHub / 本地 / iCafe 卡片序号)"
    echo "  max_iterations   最大迭代次数 (默认: $DEFAULT_MAX_ITERATIONS)"
    echo ""
    echo "配置 (环境变量):"
    echo "  PASSING_SCORE=85              达标评分线 (百分制)"
    echo "  AGENT_TIMEOUT=600             agent 调用超时秒数"
    echo "  MAX_CONSECUTIVE_FAILURES=3    连续失败最大次数"
    echo "  MAX_CONTEXT_RETRIES=3         上下文溢出自动交接最大次数"
    echo "  CONTEXT_COMPRESS_THRESHOLD=150000  Prompt token 估算阈值（超过则压缩）"
    echo "  CONTEXT_KEEP_RECENT=3         压缩时保留最近 N 次迭代日志"
    echo ""
    echo "自定义配置文件 (放在项目目录 .autoresearch/ 下):"
    echo "  agents/codex.md              Codex 指令"
    echo "  agents/claude.md             Claude 指令"
    echo "  agents/opencode.md           OpenCode 指令"
    echo "  program.md                   实现规则与约束"
    echo ""
    echo "示例:"
    echo "  $0 42                                  # 默认: Claude 实现，Codex/OpenCode/Claude 轮流审核"
    echo "  $0 -a claude,codex 42                  # 只启用 Claude 和 Codex"
    echo "  $0 -a claude,opencode,codex 42         # 自定义顺序"
    echo "  $0 -a claude 42                        # 单 agent 模式"
    echo "  $0 -p /path/to/project 42             # 处理指定项目的 Issue #42"
    echo "  $0 -p /path/to/project 42 10          # 最多迭代 10 次"
    echo "  $0 -c 42                              # 继续处理 Issue #42"
    echo "  $0 -c 42 10                           # 继续处理，追加 10 次迭代"
    echo "  $0 --issues-dir=.autoresearch/issues 8  # 处理本地 Issue #8"
    echo "  $0 --issue-source=baidu --space=cloud-iCafe 22210  # 百度 iCafe 模式"
    echo "  $0 --issue-source=baidu --space=cloud-iCafe --target-branch=develop 22210 16"
    echo "  PASSING_SCORE=90 $0 42                # 提高达标线到 90"
    exit 1
}

check_project() {
    log "检查项目环境..."

    if [ ! -d "$PROJECT_ROOT" ]; then
        error "项目目录不存在: $PROJECT_ROOT"
        exit 1
    fi

    cd "$PROJECT_ROOT"

    if ! git rev-parse --is-inside-work-tree &> /dev/null; then
        error "不是 git 仓库: $PROJECT_ROOT"
        exit 1
    fi

    local remote_url
    remote_url=$(git remote get-url origin 2>/dev/null || true)

    if [ -z "$remote_url" ]; then
        if [ "$ISSUE_SOURCE" = "local" ]; then
            log "本地 Issue 模式，跳过 GitHub remote 检查"
        else
            error "未找到 git remote origin"
            exit 1
        fi
    elif echo "$remote_url" | grep -q 'icode\.baidu\.com'; then
        # 百度 iCode 仓库
        if [ "$ISSUE_SOURCE" = "baidu" ]; then
            log "百度 iCode 仓库检测: $remote_url"
            # 从 iCode remote URL 提取仓库路径 (格式: https://icode.baidu.com/path/to/repo 或 git@icode.baidu.com:path/to/repo)
            if echo "$remote_url" | grep -q '^https\?://'; then
                ICODE_REPO=$(echo "$remote_url" | sed 's|^[^:]*://||' | sed 's|\.git$||')
            else
                ICODE_REPO=$(echo "$remote_url" | sed 's|^[^:]*:||' | sed 's|\.git$||')
            fi
            log "iCode 仓库路径: $ICODE_REPO"
        else
            log "检测到 iCode remote，但未启用 baidu 模式 (使用 --issue-source=baidu --space=<space>)"
        fi
    elif ! echo "$remote_url" | grep -qE 'github\.com|github\.baidu\.com'; then
        if [ "$ISSUE_SOURCE" = "local" ]; then
            log "本地 Issue 模式，跳过 GitHub remote 校验 (remote: $remote_url)"
        elif [ "$ISSUE_SOURCE" = "baidu" ]; then
            log "百度 iCafe 模式，跳过 GitHub remote 校验 (remote: $remote_url)"
        else
            error "origin 不是 GitHub 仓库: $remote_url"
            exit 1
        fi
    fi

    # 拉取 autoresearch 最新代码（continue 模式、本地模式和百度模式跳过，避免冲突）
    if [ $CONTINUE_MODE -eq 0 ] && [ "$ISSUE_SOURCE" != "local" ] && [ "$ISSUE_SOURCE" != "baidu" ]; then
        local autoresearch_dir
        autoresearch_dir="$(cd "$SCRIPT_DIR" && git rev-parse --show-toplevel 2>/dev/null || true)"
        if [ -n "$autoresearch_dir" ] && git -C "$autoresearch_dir" rev-parse --is-inside-work-tree &> /dev/null; then
            log "拉取 autoresearch 最新代码..."
            if git -C "$autoresearch_dir" pull --rebase origin master &> /dev/null; then
                log "autoresearch 代码已更新"
            else
                log_console "⚠️  autoresearch git pull 失败，继续使用当前版本"
            fi
        fi
    else
        log "continue 模式，跳过 autoresearch 代码更新"
    fi

    local lang=$(detect_language)
    log "项目目录: $PROJECT_ROOT"
    log "Git remote: $remote_url"
    log "项目语言: $lang"
}

check_dependencies() {
 log "检查依赖..."

 local missing=0

 # 磁盘空间预检
 local disk_min_mb="${DISK_MIN_MB:-1024}"
 local available_kb
 available_kb=$(df -k . 2>/dev/null | awk 'NR==2 {print $4}') || available_kb=0
 local available_mb=$((available_kb / 1024))
 log "磁盘空间检查: 可用 ${available_mb}MB, 阈值 ${disk_min_mb}MB"
 if [ "$available_kb" -gt 0 ] && [ "$available_mb" -lt "$disk_min_mb" ]; then
     error "磁盘空间不足: 可用 ${available_mb}MB, 最低要求 ${disk_min_mb}MB"
     missing=1
 fi

 if [ "$ISSUE_SOURCE" = "github" ] && ! command -v gh &> /dev/null; then
 error "gh (GitHub CLI) 未安装"
 missing=1
 fi

 # 百度模式依赖检查
 if [ "$ISSUE_SOURCE" = "baidu" ]; then
 if ! command -v icafe-cli &> /dev/null; then
     error "icafe-cli 未安装 (baidu 模式必需，请参考 https://icode.baidu.com/articles/help/icafe-cli)"
     missing=1
 else
     # 检查 icafe-cli 登录状态
     if ! icafe-cli login status &> /dev/null 2>&1; then
         error "icafe-cli 未登录，请先运行 icafe-cli login"
         missing=1
     else
         log "icafe-cli 依赖检查通过"
     fi
 fi
 if ! command -v icode-cli &> /dev/null; then
     error "icode-cli 未安装 (baidu 模式必需，请参考 https://icode.baidu.com/articles/help/icode-cli)"
     missing=1
 else
     # 检查 icode-cli 登录状态
     if ! icode-cli login status &> /dev/null 2>&1; then
         error "icode-cli 未登录，请先运行 icode-cli login"
         missing=1
     else
         log "icode-cli 依赖检查通过"
     fi
 fi
 fi

 # 只检查启用的 agent 是否已安装
 local agent_name
 for agent_name in "${AGENT_NAMES[@]}"; do
 if ! command -v "$agent_name" &> /dev/null; then
 error "$agent_name CLI 未安装 (在 -a 参数中指定)"
 missing=1
 fi
 done

 # 检查语言特定工具
 local required
 required=$(get_required_tools)
 if [ -n "$required" ] && ! command -v "$required" &> /dev/null; then
 error "$required 未安装 (项目语言: $(detect_language))"
 missing=1
 fi

 # 检查浏览器工具依赖（仅输出警告，不阻止运行）
 local ui_verify_disabled=0
 if [ "${UI_VERIFY_ENABLED:-yes}" != "yes" ] && [ "${UI_VERIFY_ENABLED:-yes}" != "true" ]; then
 log "UI 验证已禁用，跳过浏览器工具检测"
 ui_verify_disabled=1
 fi

 if [ $ui_verify_disabled -eq 0 ]; then
 local browser_tools_available=0
 local browser_tool_name=""

 # 检查 playwright
 if command -v playwright &> /dev/null || command -v npx &> /dev/null; then
 browser_tools_available=1
 browser_tool_name="playwright"
 log "浏览器工具检测: playwright 可用"
 fi

 # 检查 chrome-devtools MCP
 if [ $browser_tools_available -eq 0 ] && command -v npx &> /dev/null; then
 if npx -y @anthropic-ai/chrome-devtools-mcp --help &> /dev/null 2>&1; then
 browser_tools_available=1
 browser_tool_name="chrome-devtools-mcp"
 log "浏览器工具检测: chrome-devtools-mcp 可用"
 fi
 fi

 if [ $browser_tools_available -eq 0 ]; then
 log "警告: 未检测到浏览器截图工具 (playwright 或 chrome-devtools-mCP)"
 log "警告: UI 验证功能将被禁用，不影响主流程"
 UI_VERIFY_ENABLED="no"
 else
 log "浏览器工具检测通过: $browser_tool_name"
 fi
 fi

 if [ $missing -eq 1 ]; then
 exit 1
 fi

 log "依赖检查通过"
}

# 检测 Issue 来源模式 (在 check_project 之前调用)
detect_issue_source_mode() {
    # 如果显式指定 baidu 模式
    if [ "$ISSUE_SOURCE" = "baidu" ]; then
        if [ -z "$ICAFE_SPACE" ]; then
            error "baidu 模式需要指定 --space=<prefixCode> 或设置 ICAFE_SPACE 环境变量"
            exit 1
        fi
        log "百度 iCafe 模式 (空间: $ICAFE_SPACE)"
        return 0
    fi

    # 自动检测 baidu 模式: git remote 包含 icode.baidu.com 且 ICAFE_SPACE 已设置
    if [ "$ISSUE_SOURCE" = "github" ] && [ -n "$ICAFE_SPACE" ]; then
        local remote_url
        remote_url=$(git -C "$PROJECT_ROOT" remote get-url origin 2>/dev/null || true)
        if echo "$remote_url" | grep -q 'icode\.baidu\.com'; then
            ISSUE_SOURCE="baidu"
            log "百度 iCafe 模式 (自动检测: remote 含 icode.baidu.com 且 ICAFE_SPACE 已设置, 空间: $ICAFE_SPACE)"
            return 0
        fi
    fi

    # 如果 --issues-dir 已设置，强制本地模式
    if [ -n "$ISSUES_DIR" ]; then
        ISSUE_SOURCE="local"
        if [[ "$ISSUES_DIR" != /* ]]; then
            ISSUES_DIR="$PROJECT_ROOT/$ISSUES_DIR"
        fi
        log "本地 Issue 模式 (指定目录: $ISSUES_DIR)"
        return 0
    fi

    # 自动检测: 检查默认目录是否有匹配的 issue 文件
    local default_dir="$PROJECT_ROOT/.autoresearch/issues"
    if [ -d "$default_dir" ]; then
        local padded_number
        padded_number=$(printf "%03d" "$ISSUE_NUMBER" 2>/dev/null) || true
        if ls "$default_dir"/issue-${padded_number}-*.md &>/dev/null 2>&1 || \
           ls "$default_dir"/issue-${ISSUE_NUMBER}-*.md &>/dev/null 2>&1; then
            ISSUE_SOURCE="local"
            ISSUES_DIR="$default_dir"
            log "本地 Issue 模式 (自动检测: $ISSUES_DIR)"
            return 0
        fi
    fi

    ISSUE_SOURCE="github"
}

# 从本地文件获取 Issue 信息
get_local_issue_info() {
    local issue_number=$1
    local issues_dir="$ISSUES_DIR"

    if [ -z "$issues_dir" ]; then
        issues_dir="$PROJECT_ROOT/.autoresearch/issues"
    fi

    # 相对路径转绝对路径
    if [[ "$issues_dir" != /* ]]; then
        issues_dir="$PROJECT_ROOT/$issues_dir"
    fi

    if [ ! -d "$issues_dir" ]; then
        return 1
    fi

    # 查找匹配的 issue 文件: issue-NNN-*.md
    local padded_number
    padded_number=$(printf "%03d" "$issue_number" 2>/dev/null) || true

    local issue_file=""
    # 优先匹配零填充格式: issue-008-*.md
    issue_file=$(ls "$issues_dir"/issue-${padded_number}-*.md 2>/dev/null | head -1) || true

    # 回退: 不带零填充格式: issue-8-*.md
    if [ -z "$issue_file" ]; then
        issue_file=$(ls "$issues_dir"/issue-${issue_number}-*.md 2>/dev/null | head -1) || true
    fi

    if [ -z "$issue_file" ] || [ ! -f "$issue_file" ]; then
        return 1
    fi

    log "找到本地 Issue 文件: $issue_file"

    # 解析标题: 第一个 "# " 开头的行
    ISSUE_TITLE=""
    ISSUE_BODY=""
    local found_title=0
    local body_lines=""

    while IFS= read -r line; do
        if [ $found_title -eq 0 ] && [[ "$line" =~ ^#[[:space:]]+ ]]; then
            ISSUE_TITLE="${line#\# }"
            ISSUE_TITLE="${ISSUE_TITLE#\#}"
            found_title=1
        elif [ $found_title -eq 1 ]; then
            body_lines="${body_lines}${line}"$'\n'
        fi
    done < "$issue_file"

    # 没有标题行时，用文件名作为标题，整个文件内容作为 body
    if [ $found_title -eq 0 ]; then
        local basename
        basename=$(basename "$issue_file" .md)
        ISSUE_TITLE="${basename#issue-[0-9]*-}"
        ISSUE_BODY=$(cat "$issue_file")
    else
        ISSUE_BODY="${body_lines%$'\n'}"
    fi

    # 设置兼容性全局变量
    ISSUE_STATE="OPEN"
    ISSUE_LABELS=""
    ISSUE_SOURCE="local"
    ISSUE_FILE="$issue_file"
    ISSUE_INFO=""

    log "本地 Issue 标题: $ISSUE_TITLE"
    return 0
}

# 将处理结果追加到本地 Issue 文件
append_result_to_local_issue() {
    if [ -z "$ISSUE_FILE" ] || [ ! -f "$ISSUE_FILE" ]; then
        log "警告: 本地 Issue 文件不存在，跳过结果追加"
        return 1
    fi

    # 构建子任务摘要
    local subtask_summary=""
    if has_subtasks; then
        local tasks_file
        tasks_file=$(get_tasks_file)
        local total passed
        total=$(jq '.subtasks | length' "$tasks_file" 2>/dev/null)
        passed=$(jq '[.subtasks[] | select(.passes == true)] | length' "$tasks_file" 2>/dev/null)
        subtask_summary="- 子任务: ${passed}/${total} 完成"
    fi

    # 构建 UI 验证摘要
    local ui_summary=""
    if [ -f "$WORK_DIR/ui-verify-result.json" ]; then
        local ui_pass_status
        ui_pass_status=$(jq -r '.pass // "N/A"' "$WORK_DIR/ui-verify-result.json" 2>/dev/null)
        ui_summary="- UI 验证: $ui_pass_status"
    fi

    # 构建日志摘要
    local log_summary=""
    if [ -f "$WORK_DIR/log.md" ]; then
        log_summary=$(cat "$WORK_DIR/log.md")
    fi

    cat >> "$ISSUE_FILE" << EOF

---

## 自动处理结果

- **评分**: $FINAL_SCORE/100
- **迭代次数**: $ITERATION
- **实现方式**: autoresearch 多 agent 迭代 (${AGENT_NAMES[@]})
- **分支**: $BRANCH_NAME
- **完成时间**: $(date '+%Y-%m-%d %H:%M:%S')
$subtask_summary
$ui_summary

${log_summary}

该 Issue 已由 autoresearch 自动实现。
EOF

    log "结果已追加到: $ISSUE_FILE"
    return 0
}

# 检测 iCode CR 目标分支
detect_icode_target_branch() {
    if [ -n "$ICODE_TARGET_BRANCH" ]; then
        echo "$ICODE_TARGET_BRANCH"
        return 0
    fi

    # 尝试从 git remote 推断
    local head_branch
    head_branch=$(git remote show origin 2>/dev/null | grep 'HEAD branch' | cut -d':' -f2 | tr -d ' ')
    if [ -n "$head_branch" ]; then
        echo "$head_branch"
        return 0
    fi

    # 回退到 master
    echo "master"
}

# 从百度 iCafe 获取 Issue 信息
get_baidu_issue_info() {
    local issue_number=$1

    log "获取 iCafe 卡片 #$issue_number 信息 (空间: $ICAFE_SPACE)..."

    # 调用 icafe-cli 获取卡片信息
    local card_info
    card_info=$(icafe-cli card get --space "$ICAFE_SPACE" --sequence "$issue_number" --brief 2>&1)

    if [ $? -ne 0 ]; then
        error "无法获取 iCafe 卡片 #$issue_number: $card_info"
        error "提示: 请检查空间名称 ($ICAFE_SPACE) 和卡片序号是否正确"
        exit 1
    fi

    # 解析 JSON 响应
    ISSUE_TITLE=$(echo "$card_info" | jq -r '.title // empty')
    ISSUE_BODY=$(echo "$card_info" | jq -r '.description // empty')
    ISSUE_STATE=$(echo "$card_info" | jq -r '.status // empty')
    ICAFE_CARD_TYPE=$(echo "$card_info" | jq -r '.cardType // "Task"')

    # iCafe 描述是 HTML 格式，去除 HTML 标签
    if [ -n "$ISSUE_BODY" ]; then
        ISSUE_BODY=$(echo "$ISSUE_BODY" | sed 's/<[^>]*>//g' | sed 's/&nbsp;/ /g' | sed 's/&lt;/</g' | sed 's/&gt;/>/g' | sed 's/&amp;/\&/g' | sed 's/&quot;/"/g')
    fi

    ISSUE_LABELS=""
    ISSUE_FILE=""
    ISSUE_INFO="$card_info"

    # 验证卡片状态 (已关闭的卡片不应再处理)
    # iCafe 状态可能是中文，如 "已关闭"、"开发中" 等
    if echo "$ISSUE_STATE" | grep -qiE '已关闭|closed'; then
        error "iCafe 卡片 #$issue_number 状态为 ${ISSUE_STATE}，已关闭"
        exit 1
    fi

    log "iCafe 卡片标题: $ISSUE_TITLE"
    log "iCafe 卡片类型: $ICAFE_CARD_TYPE"
    log "iCafe 卡片状态: $ISSUE_STATE"
    return 0
}

get_issue_info() {
    local issue_number=$1

    log "获取 Issue #$issue_number 信息..."

    # 百度 iCafe 模式
    if [ "$ISSUE_SOURCE" = "baidu" ]; then
        get_baidu_issue_info "$issue_number"
        return 0
    fi

    # 优先尝试本地 Issue
    if get_local_issue_info "$issue_number"; then
        log "使用本地 Issue 模式"
        log "Issue 标题: $ISSUE_TITLE"
        log "Issue 标签: ${ISSUE_LABELS:-无} (本地模式无标签)"
        return 0
    fi

    # 回退到 GitHub
    ISSUE_SOURCE="github"

    ISSUE_INFO=$(gh issue view $issue_number --json number,title,body,state,labels 2>&1)

    if [ $? -ne 0 ]; then
        error "无法获取 Issue #$issue_number: $ISSUE_INFO"
        error "提示: 如果要使用本地 Issue，请在 .autoresearch/issues/ 目录下放置 issue-NNN-xxx.md 文件"
        error "提示: 如果要使用百度 iCafe，请使用 --issue-source=baidu --space=<prefixCode>"
        exit 1
    fi

    ISSUE_TITLE=$(echo "$ISSUE_INFO" | jq -r '.title')
    ISSUE_BODY=$(echo "$ISSUE_INFO" | jq -r '.body')
    ISSUE_STATE=$(echo "$ISSUE_INFO" | jq -r '.state')
    ISSUE_LABELS=$(echo "$ISSUE_INFO" | jq -r '.labels[].name' | tr '\n' ',' | sed 's/,$//')
    ISSUE_FILE=""

    if [ "$ISSUE_STATE" != "OPEN" ]; then
        error "Issue #$issue_number 状态为 ${ISSUE_STATE}，不是 OPEN"
        exit 1
    fi

    log "Issue 标题: $ISSUE_TITLE"
    log "Issue 标签: $ISSUE_LABELS"
}

# 归档 workflows 目录下其他 Issue 的数据
# 将非当前 Issue 的 issue-* 目录移动到 .autoresearch/archive/YYYY-MM-DD-issue-N/
archive_old_workflows() {
    local current_issue=$1
    local workflows_dir="$PROJECT_ROOT/.autoresearch/workflows"
    local archive_dir="$PROJECT_ROOT/.autoresearch/archive"

    if [ ! -d "$workflows_dir" ]; then
        return 0
    fi

    local archived_count=0
    local current_date
    current_date=$(date '+%Y-%m-%d')

    for dir in "$workflows_dir"/issue-*; do
        [ -d "$dir" ] || continue

        local dirname
        dirname=$(basename "$dir")
        # 跳过当前 Issue 的目录
        if [ "$dirname" = "issue-$current_issue" ]; then
            continue
        fi

        # 从目录名提取 Issue 编号
        local issue_num
        issue_num=$(echo "$dirname" | grep -oE '[0-9]+$')
        [ -z "$issue_num" ] && continue

        local target_dir="$archive_dir/${current_date}-issue-${issue_num}"

        # 处理目标目录已存在的情况：追加数字后缀
        if [ -d "$target_dir" ]; then
            local suffix=1
            while [ -d "${target_dir}-${suffix}" ]; do
                suffix=$((suffix + 1))
            done
            target_dir="${target_dir}-${suffix}"
        fi

        mkdir -p "$archive_dir"
        mv "$dir" "$target_dir"
        log "已归档: $dirname -> $archive_dir/${current_date}-issue-${issue_num}"
        archived_count=$((archived_count + 1))
    done

    if [ $archived_count -gt 0 ]; then
        log "归档完成，共归档 $archived_count 个 Issue 目录"
    fi
}

setup_work_directory() {
    local issue_number=$1

    # 归档其他 Issue 的 workflows 数据（非继续模式且未禁用归档时）
    if [ $CONTINUE_MODE -eq 0 ] && [ $NO_ARCHIVE -eq 0 ]; then
        archive_old_workflows "$issue_number"
    fi

    WORK_DIR="$PROJECT_ROOT/.autoresearch/workflows/issue-$issue_number"
    mkdir -p "$WORK_DIR"

    log "工作目录: $WORK_DIR"

    if [ $CONTINUE_MODE -eq 1 ]; then
        if [ ! -f "$WORK_DIR/log.md" ]; then
            log_console "⚠️ 未找到 Issue #$issue_number 的工作日志，回退为全新运行"
            CONTINUE_MODE=0
        else
            log "继续模式: 追加到已有日志"
            return
        fi
    fi

    cat > "$WORK_DIR/log.md" << EOF
# Issue #$issue_number 实现日志

## 基本信息
- Issue: #$issue_number - $ISSUE_TITLE
- 项目: $PROJECT_ROOT
- 语言: $(detect_language)
- 开始时间: $(date '+%Y-%m-%d %H:%M:%S')
- 标签: ${ISSUE_LABELS:-无}

## 迭代记录

EOF

    # 初始化跨迭代经验日志
    init_progress
}

# 获取 agent 指令文件路径
# 优先级: 项目 .autoresearch/ > 脚本目录 agents/
get_agent_instructions() {
    local agent_name=$1

    local project_agent="$PROJECT_ROOT/.autoresearch/agents/$agent_name.md"
    if [ -f "$project_agent" ]; then
        echo "$project_agent"
        return
    fi

    local default_agent="$SCRIPT_DIR/agents/$agent_name.md"
    if [ -f "$default_agent" ]; then
        echo "$default_agent"
        return
    fi

    echo ""
}

# 获取 program.md 内容
# 当 PROMPT_TRIMMED=1 时按优先级裁剪（保留当前语言相关部分，移除无关语言规则）
# Prompt trimming & program instructions functions are in lib/prompt.sh

create_branch() {
    local issue_number=$1

    BRANCH_NAME="feature/issue-$issue_number"

    log "创建分支: $BRANCH_NAME"

    cd "$PROJECT_ROOT"

    if git show-ref --verify --quiet "refs/heads/$BRANCH_NAME"; then
        log "分支已存在，切换到: $BRANCH_NAME"
        git checkout "$BRANCH_NAME"
    else
        git checkout -b "$BRANCH_NAME"
    fi
}

# Subtask (tasks.json) functions are in lib/subtask.sh

# Progress tracking functions are in lib/progress.sh

# ==================== 规划阶段 ====================

run_planning_phase() {
    local issue_number=$1

    log "规划阶段: 拆分 Issue #$issue_number 为子任务..."

    # 如果已有 tasks.json（继续模式），跳过规划
    if has_subtasks; then
        log "已有 tasks.json，跳过规划阶段"
        local progress
        progress=$(get_subtask_progress_summary)
        log "$progress"
        return 0
    fi

    local first_agent="${AGENT_NAMES[0]}"
    local agent_instructions_file
    agent_instructions_file=$(get_agent_instructions "$first_agent")

    local agent_instructions=""
    if [ -n "$agent_instructions_file" ]; then
        agent_instructions=$(cat "$agent_instructions_file")
        log "使用指令文件: $agent_instructions_file"
    fi

    local program_instructions
    program_instructions=$(get_program_instructions)

    local prompt="规划 $ISSUE_REF 的子任务拆分

项目路径: $PROJECT_ROOT
项目语言: $(detect_language)
Issue 标题: $ISSUE_TITLE
Issue 内容: $ISSUE_BODY

---
请分析此 Issue，将其拆分为可独立完成的子任务。每个子任务应能在一次迭代内完成。

输出格式要求：在输出的最后，必须输出一个 JSON 代码块（用 \`\`\`json 和 \`\`\` 包裹），格式如下：

\`\`\`json
{
  \"issueNumber\": $issue_number,
  \"subtasks\": [
    {
      \"id\": \"T-001\",
      \"title\": \"子任务标题\",
      \"description\": \"详细描述此子任务需要完成的工作\",
      \"acceptanceCriteria\": [\"验收条件1\", \"验收条件2\"],
      \"priority\": 1,
      \"type\": \"code\",
      \"passes\": false
    },
    {
      \"id\": \"T-002\",
      \"title\": \"子任务标题\",
      \"description\": \"详细描述\",
      \"acceptanceCriteria\": [\"验收条件1\"],
      \"priority\": 2,
      \"passes\": false
    }
  ]
}
\`\`\`

拆分原则：
1. 每个子任务应是一个可独立验证的、在一次迭代内能完成的小目标
2. 子任务之间应有清晰的依赖顺序（通过 priority 排序）
3. 每个子任务必须有明确的验收条件（acceptanceCriteria）
4. 如果 Issue 简单，可以只拆分为 1-2 个子任务
5. 如果 Issue 复杂，建议拆分为 3-5 个子任务
6. id 格式为 T-001, T-002, ...

UI 类型识别：
- 分析 Issue 内容，如果涉及以下变更，对应子任务应标注 \"type\": \"ui\"：
  * 页面布局、样式、组件的增删改
  * 前端交互逻辑（表单、按钮、导航等）
  * CSS/样式文件的新增或修改
  * HTML/模板文件的修改
  * 前端框架组件（React/Vue/Svelte 等）的修改
- 不涉及 UI 变更的子任务不添加 type 字段（默认为 \"code\"）
- 示例：{\"id\": \"T-001\", \"title\": \"添加登录页面\", \"type\": \"ui\", ...}

---
$program_instructions

$agent_instructions
"

    log_file="$WORK_DIR/planning.log"

    cd "$PROJECT_ROOT"
    agent_ret=0
    run_with_retry "$first_agent" "$prompt" "$log_file" || agent_ret=$?
    if [ $agent_ret -eq 2 ]; then
        log "规划阶段 agent 被跳过，将不拆分子任务（回退到原有模式）"
        return 1
    elif [ $agent_ret -ne 0 ]; then
        log "规划阶段失败，将不拆分子任务（回退到原有模式）"
        return 1
    fi

    # 从 agent 输出中提取 tasks.json
    tasks_file=$(get_tasks_file)

    # 防御性检查：确保日志文件存在且非空
    if [ ! -f "$log_file" ] || [ ! -s "$log_file" ]; then
        log "警告: 规划阶段输出文件不存在或为空，回退到原有模式"
        return 1
    fi

    # 尝试提取第一个 ```json ... ``` 代码块（避免多个 JSON 块拼接导致无效 JSON）
    json_content=$(awk '/^```json$/{n++; next} n==1 && /^```$/{exit} n==1{print}' "$log_file" | head -200)

    if [ -n "$json_content" ]; then
        echo "$json_content" > "$tasks_file"

        # 验证 JSON 格式
        if jq '.' "$tasks_file" > /dev/null 2>&1; then
            count=$(jq '.subtasks | length' "$tasks_file")
            log_console "✅ 成功拆分为 $count 个子任务"

            # 记录到日志
            echo "" >> "$WORK_DIR/log.md"
            echo "### 规划阶段" >> "$WORK_DIR/log.md"
            echo "" >> "$WORK_DIR/log.md"
            echo "已拆分为 $count 个子任务，详见: [tasks.json](./tasks.json)" >> "$WORK_DIR/log.md"

            # 打印子任务列表
            log_console "子任务列表:"
            jq -r '.subtasks[] | "  \(.id): \(.title)"' "$tasks_file" | while read -r line; do
                log_console "$line"
            done

            return 0
        else
            log_console "⚠️ 提取的 JSON 格式无效，回退到原有模式"
            rm -f "$tasks_file"
            return 1
        fi
    fi

    log_console "⚠️ 未能从规划输出中提取 tasks.json，回退到原有模式"
    return 1
}

# ==================== Agent 实现/修复函数 ====================

run_codex() {
    local issue_number=$1
    local iteration=$2
    local previous_feedback=$3

    log "迭代 $iteration: Codex 实现..."

    local codex_instructions_file
    codex_instructions_file=$(get_agent_instructions "codex")

    local codex_instructions=""
    if [ -n "$codex_instructions_file" ]; then
        codex_instructions=$(cat "$codex_instructions_file")
        log "使用指令文件: $codex_instructions_file"
    fi

    local program_instructions
    program_instructions=$(get_program_instructions)

    local progress_section
    progress_section=$(get_progress_section)

    local prompt
    local subtask_section
    subtask_section=$(get_subtask_section)

    if [ -z "$previous_feedback" ]; then
        prompt="实现 $ISSUE_REF

项目路径: $PROJECT_ROOT
项目语言: $(detect_language)
Issue 标题: $ISSUE_TITLE
Issue 内容: $ISSUE_BODY

迭代次数: $iteration
$subtask_section
$progress_section

---
请按以下步骤执行:

## 第一步：制定计划
分析 Issue 需求，制定实现计划，拆解为具体的 tasks/todos，输出任务清单。

## 第二步：逐步实现
按照任务清单逐步实现，每完成一个任务标记为已完成。

## 第三步：总结经验
实现完成后，在输出末尾添加 ## Learnings 部分，总结本次迭代中发现的关键模式、踩过的坑和可复用的经验。

---
$program_instructions

$codex_instructions
"
    else
        prompt="根据审核反馈改进 Issue #$issue_number 的实现

项目路径: $PROJECT_ROOT
项目语言: $(detect_language)
Issue 标题: $ISSUE_TITLE

审核反馈:
$previous_feedback
$subtask_section
$progress_section

---
请按以下步骤执行:

## 第一步：制定计划
分析审核反馈，制定修复计划，拆解为具体的 tasks/todos，输出任务清单。

## 第二步：逐步实现
按照任务清单逐步修复，每完成一个任务标记为已完成。

## 第三步：总结经验
修复完成后，在输出末尾添加 ## Learnings 部分，总结本次修复中发现的关键模式和经验。

---
$codex_instructions
"
    fi

    local log_file="$WORK_DIR/iteration-$iteration-codex.log"

    prompt=$(apply_prompt_trimming "$prompt")
    check_and_compress_prompt "$prompt" "$WORK_DIR"
    cd "$PROJECT_ROOT"
    local agent_ret=0
    run_with_retry codex "$prompt" "$log_file" || agent_ret=$?
    if [ $agent_ret -eq 2 ]; then
        return 2
    elif [ $agent_ret -ne 0 ]; then
        return 1
    fi

    echo "" >> "$WORK_DIR/log.md"
    echo "### 迭代 $iteration - Codex (实现)" >> "$WORK_DIR/log.md"
    echo "" >> "$WORK_DIR/log.md"
    echo "详见: [iteration-$iteration-codex.log](./iteration-$iteration-codex.log)" >> "$WORK_DIR/log.md"
    return 0
}

run_claude() {
    local issue_number=$1
    local iteration=$2
    local previous_feedback=$3

    log "迭代 $iteration: Claude 实现..."

    local claude_instructions_file
    claude_instructions_file=$(get_agent_instructions "claude")

    local claude_instructions=""
    if [ -n "$claude_instructions_file" ]; then
        claude_instructions=$(cat "$claude_instructions_file")
        log "使用指令文件: $claude_instructions_file"
    fi

    local program_instructions
    program_instructions=$(get_program_instructions)

    local progress_section
    progress_section=$(get_progress_section)

    local prompt
    local subtask_section
    subtask_section=$(get_subtask_section)

    if [ -z "$previous_feedback" ]; then
        prompt="实现 $ISSUE_REF

项目路径: $PROJECT_ROOT
项目语言: $(detect_language)
Issue 标题: $ISSUE_TITLE
Issue 内容: $ISSUE_BODY

迭代次数: $iteration
$subtask_section
$progress_section

---
请按以下步骤执行:

## 第一步：制定计划
分析 Issue 需求，制定实现计划，拆解为具体的 tasks/todos，输出任务清单。

## 第二步：逐步实现
按照任务清单逐步实现，每完成一个任务标记为已完成。

## 第三步：总结经验
实现完成后，在输出末尾添加 ## Learnings 部分，总结本次迭代中发现的关键模式、踩过的坑和可复用的经验。

---
$program_instructions

$claude_instructions
"
    else
        prompt="根据审核反馈改进 Issue #$issue_number 的实现

项目路径: $PROJECT_ROOT
项目语言: $(detect_language)
Issue 标题: $ISSUE_TITLE

审核反馈:
$previous_feedback
$subtask_section
$progress_section

---
请按以下步骤执行:

## 第一步：制定计划
分析审核反馈，制定修复计划，拆解为具体的 tasks/todos，输出任务清单。

## 第二步：逐步实现
按照任务清单逐步修复，每完成一个任务标记为已完成。

## 第三步：总结经验
修复完成后，在输出末尾添加 ## Learnings 部分，总结本次修复中发现的关键模式和经验。

---
$claude_instructions
"
    fi

    local log_file="$WORK_DIR/iteration-$iteration-claude.log"

    prompt=$(apply_prompt_trimming "$prompt")
    check_and_compress_prompt "$prompt" "$WORK_DIR"
    cd "$PROJECT_ROOT"
    local agent_ret=0
    run_with_retry claude "$prompt" "$log_file" || agent_ret=$?
    if [ $agent_ret -eq 2 ]; then
        return 2
    elif [ $agent_ret -ne 0 ]; then
        return 1
    fi

    echo "" >> "$WORK_DIR/log.md"
    echo "### 迭代 $iteration - Claude (实现)" >> "$WORK_DIR/log.md"
    echo "" >> "$WORK_DIR/log.md"
    echo "详见: [iteration-$iteration-claude.log](./iteration-$iteration-claude.log)" >> "$WORK_DIR/log.md"
    return 0
}

run_opencode() {
    local issue_number=$1
    local iteration=$2
    local previous_feedback=$3

    log "迭代 $iteration: OpenCode 实现..."

    local opencode_instructions_file
    opencode_instructions_file=$(get_agent_instructions "opencode")

    local opencode_instructions=""
    if [ -n "$opencode_instructions_file" ]; then
        opencode_instructions=$(cat "$opencode_instructions_file")
        log "使用指令文件: $opencode_instructions_file"
    fi

    local program_instructions
    program_instructions=$(get_program_instructions)

    local progress_section
    progress_section=$(get_progress_section)

    local prompt
    local subtask_section
    subtask_section=$(get_subtask_section)

    if [ -z "$previous_feedback" ]; then
        prompt="实现 $ISSUE_REF

项目路径: $PROJECT_ROOT
项目语言: $(detect_language)
Issue 标题: $ISSUE_TITLE
Issue 内容: $ISSUE_BODY

迭代次数: $iteration
$subtask_section
$progress_section

---
请按以下步骤执行:

## 第一步：制定计划
分析 Issue 需求，制定实现计划，拆解为具体的 tasks/todos，输出任务清单。

## 第二步：逐步实现
按照任务清单逐步实现，每完成一个任务标记为已完成。

## 第三步：总结经验
实现完成后，在输出末尾添加 ## Learnings 部分，总结本次迭代中发现的关键模式、踩过的坑和可复用的经验。

---
$program_instructions

$opencode_instructions
"
    else
        prompt="根据审核反馈改进 Issue #$issue_number 的实现

项目路径: $PROJECT_ROOT
项目语言: $(detect_language)
Issue 标题: $ISSUE_TITLE

审核反馈:
$previous_feedback
$subtask_section
$progress_section

---
请按以下步骤执行:

## 第一步：制定计划
分析审核反馈，制定修复计划，拆解为具体的 tasks/todos，输出任务清单。

## 第二步：逐步实现
按照任务清单逐步修复，每完成一个任务标记为已完成。

## 第三步：总结经验
修复完成后，在输出末尾添加 ## Learnings 部分，总结本次修复中发现的关键模式和经验。

---
$opencode_instructions
"
    fi

    local log_file="$WORK_DIR/iteration-$iteration-opencode.log"

    prompt=$(apply_prompt_trimming "$prompt")
    check_and_compress_prompt "$prompt" "$WORK_DIR"
    cd "$PROJECT_ROOT"
    local agent_ret=0
    run_with_retry opencode "$prompt" "$log_file" || agent_ret=$?
    if [ $agent_ret -eq 2 ]; then
        return 2
    elif [ $agent_ret -ne 0 ]; then
        return 1
    fi

    echo "" >> "$WORK_DIR/log.md"
    echo "### 迭代 $iteration - OpenCode (实现)" >> "$WORK_DIR/log.md"
    echo "" >> "$WORK_DIR/log.md"
    echo "详见: [iteration-$iteration-opencode.log](./iteration-$iteration-opencode.log)" >> "$WORK_DIR/log.md"
    return 0
}

# ==================== Agent 审核函数 ====================

run_opencode_review() {
    local issue_number=$1
    local iteration=$2

    log "迭代 $iteration: OpenCode 审核..."

    local opencode_instructions_file
    opencode_instructions_file=$(get_agent_instructions "opencode")

    local opencode_instructions=""
    if [ -n "$opencode_instructions_file" ]; then
        opencode_instructions=$(cat "$opencode_instructions_file")
        log "使用指令文件: $opencode_instructions_file"
    fi

    local subtask_review_section
    subtask_review_section=$(get_subtask_review_section)

    local prompt="审核 Issue #$issue_number 的实现

项目路径: $PROJECT_ROOT
项目语言: $(detect_language)
Issue 标题: $ISSUE_TITLE

$subtask_review_section
---
请按照以下指令执行审核。

评分格式要求: 必须在审核报告的总体评价中使用 **评分: X/100** 格式输出分数，其中 X 为 0-100 的整数。

评分维度与权重:
- 正确性 (35%): 功能是否符合需求、边界情况处理、错误处理
- 测试质量 (25%): 核心逻辑覆盖、边界测试、错误路径测试
- 代码质量 (20%): 命名清晰、结构清晰、遵循项目规范
- 安全性 (10%): 输入验证、无注入风险、无敏感信息泄露
- 性能 (10%): 无明显性能问题、无不必要的内存分配

评分标准: 90-100 优秀 | 85-89 良好(达标) | 70-84 及格偏上 | 50-69 及格 | 30-49 较差 | 0-29 不合格
注意: 评分 ≥ 85 才算达标。
$(get_progress_section)
$opencode_instructions
"

    local log_file="$WORK_DIR/iteration-$iteration-opencode-review.log"

    prompt=$(apply_prompt_trimming "$prompt")
    check_and_compress_prompt "$prompt" "$WORK_DIR"
    cd "$PROJECT_ROOT"
    local agent_ret=0
    run_with_retry opencode "$prompt" "$log_file" || agent_ret=$?
    if [ $agent_ret -eq 2 ]; then
        echo "0" > "$WORK_DIR/.last_score"
        return 2
    elif [ $agent_ret -ne 0 ]; then
        echo "0" > "$WORK_DIR/.last_score"
        return 1
    fi

    local score=0
    local review_result
    if [ ! -f "$log_file" ] || [ ! -s "$log_file" ]; then
        log "警告: 审核输出文件不存在或为空，默认评分 50"
        review_result=""
        score=50
    else
        review_result=$(cat "$log_file")

        # 先检测 sentinel 标记
        local sentinel
        sentinel=$(check_sentinel "$review_result")
        if [ "$sentinel" = "pass" ]; then
            log_console "Sentinel 通道: 检测到 AUTORESEARCH_RESULT:PASS，直接判定通过"
            score=100
        elif [ "$sentinel" = "fail" ]; then
            log_console "Sentinel 通道: 检测到 AUTORESEARCH_RESULT:FAIL，直接判定不通过"
            score=0
        else
            score=$(extract_score "$review_result")

            if [ -z "$score" ] || [ "$score" = "0" ]; then
                log "警告: 无法从审核结果中提取评分，默认为 50"
                score=50
            fi
        fi
    fi

    echo "- 审核评分 (OpenCode): $score/100" >> "$WORK_DIR/log.md"

    log_console "审核评分: $score/100"

    echo "$review_result"
    echo "$score" > "$WORK_DIR/.last_score"
    return 0
}

run_tests() {
    local iteration=$1

    log "迭代 $iteration: 运行测试..."

    cd "$PROJECT_ROOT"

    local log_file="$WORK_DIR/test-$iteration.log"
    local test_cmd
    test_cmd=$(get_test_command)

    if [ -n "$test_cmd" ]; then
        if $test_cmd > "$log_file" 2>&1; then
            log_console "✅ 测试通过"
            echo "- 测试: ✅ 通过" >> "$WORK_DIR/log.md"
            return 0
        else
            log_console "❌ 测试失败"
            echo "- 测试: ❌ 失败" >> "$WORK_DIR/log.md"
            return 1
        fi
    else
        log "未检测到测试命令，跳过测试"
        echo "- 测试: ⏭️ 跳过 (未检测到测试框架)" >> "$WORK_DIR/log.md"
        return 0
    fi
}

run_claude_review() {
    local issue_number=$1
    local iteration=$2

    log "迭代 $iteration: Claude 审核..."

    local claude_instructions_file
    claude_instructions_file=$(get_agent_instructions "claude")

    local claude_instructions=""
    if [ -n "$claude_instructions_file" ]; then
        claude_instructions=$(cat "$claude_instructions_file")
        log "使用指令文件: $claude_instructions_file"
    fi

    local subtask_review_section
    subtask_review_section=$(get_subtask_review_section)

    local prompt="审核 Issue #$issue_number 的实现

项目路径: $PROJECT_ROOT
项目语言: $(detect_language)
Issue 标题: $ISSUE_TITLE

$subtask_review_section
---
请按照以下指令执行审核。

评分格式要求: 必须在审核报告的总体评价中使用 **评分: X/100** 格式输出分数，其中 X 为 0-100 的整数。

评分维度与权重:
- 正确性 (35%): 功能是否符合需求、边界情况处理、错误处理
- 测试质量 (25%): 核心逻辑覆盖、边界测试、错误路径测试
- 代码质量 (20%): 命名清晰、结构清晰、遵循项目规范
- 安全性 (10%): 输入验证、无注入风险、无敏感信息泄露
- 性能 (10%): 无明显性能问题、无不必要的内存分配

评分标准: 90-100 优秀 | 85-89 良好(达标) | 70-84 及格偏上 | 50-69 及格 | 30-49 较差 | 0-29 不合格
注意: 评分 ≥ 85 才算达标。
$(get_progress_section)
$claude_instructions
"

    local log_file="$WORK_DIR/iteration-$iteration-claude-review.log"

    prompt=$(apply_prompt_trimming "$prompt")
    check_and_compress_prompt "$prompt" "$WORK_DIR"
    cd "$PROJECT_ROOT"
    local agent_ret=0
    run_with_retry claude "$prompt" "$log_file" || agent_ret=$?
    if [ $agent_ret -eq 2 ]; then
        echo "0" > "$WORK_DIR/.last_score"
        return 2
    elif [ $agent_ret -ne 0 ]; then
        echo "0" > "$WORK_DIR/.last_score"
        return 1
    fi

    local score=0
    local review_result
    if [ ! -f "$log_file" ] || [ ! -s "$log_file" ]; then
        log "警告: 审核输出文件不存在或为空，默认评分 50"
        review_result=""
        score=50
    else
        review_result=$(cat "$log_file")

        # 先检测 sentinel 标记
        local sentinel
        sentinel=$(check_sentinel "$review_result")
        if [ "$sentinel" = "pass" ]; then
            log_console "Sentinel 通道: 检测到 AUTORESEARCH_RESULT:PASS，直接判定通过"
            score=100
        elif [ "$sentinel" = "fail" ]; then
            log_console "Sentinel 通道: 检测到 AUTORESEARCH_RESULT:FAIL，直接判定不通过"
            score=0
        else
            score=$(extract_score "$review_result")

            if [ -z "$score" ] || [ "$score" = "0" ]; then
                log "警告: 无法从审核结果中提取评分，默认为 50"
                score=50
            fi
        fi
    fi

    echo "- 审核评分 (Claude): $score/100" >> "$WORK_DIR/log.md"

    log_console "审核评分: $score/100"

    echo "$review_result"
    echo "$score" > "$WORK_DIR/.last_score"
    return 0
}

run_codex_review() {
    local issue_number=$1
    local iteration=$2

    log "迭代 $iteration: Codex 审核..."

    local codex_instructions_file
    codex_instructions_file=$(get_agent_instructions "codex")

    local codex_instructions=""
    if [ -n "$codex_instructions_file" ]; then
        codex_instructions=$(cat "$codex_instructions_file")
        log "使用指令文件: $codex_instructions_file"
    fi

    local subtask_review_section
    subtask_review_section=$(get_subtask_review_section)

    local prompt="审核 Issue #$issue_number 的实现

项目路径: $PROJECT_ROOT
项目语言: $(detect_language)
Issue 标题: $ISSUE_TITLE

$subtask_review_section
---
请按照以下指令执行审核。

评分格式要求: 必须在审核报告的总体评价中使用 **评分: X/100** 格式输出分数，其中 X 为 0-100 的整数。

评分维度与权重:
- 正确性 (35%): 功能是否符合需求、边界情况处理、错误处理
- 测试质量 (25%): 核心逻辑覆盖、边界测试、错误路径测试
- 代码质量 (20%): 命名清晰、结构清晰、遵循项目规范
- 安全性 (10%): 输入验证、无注入风险、无敏感信息泄露
- 性能 (10%): 无明显性能问题、无不必要的内存分配

评分标准: 90-100 优秀 | 85-89 良好(达标) | 70-84 及格偏上 | 50-69 及格 | 30-49 较差 | 0-29 不合格
注意: 评分 ≥ 85 才算达标。
$(get_progress_section)
$codex_instructions
"

    local log_file="$WORK_DIR/iteration-$iteration-codex-review.log"

    prompt=$(apply_prompt_trimming "$prompt")
    check_and_compress_prompt "$prompt" "$WORK_DIR"
    cd "$PROJECT_ROOT"
    local agent_ret=0
    run_with_retry codex "$prompt" "$log_file" || agent_ret=$?
    if [ $agent_ret -eq 2 ]; then
        echo "0" > "$WORK_DIR/.last_score"
        return 2
    elif [ $agent_ret -ne 0 ]; then
        echo "0" > "$WORK_DIR/.last_score"
        return 1
    fi

    local score=0
    local review_result
    if [ ! -f "$log_file" ] || [ ! -s "$log_file" ]; then
        log "警告: 审核输出文件不存在或为空，默认评分 50"
        review_result=""
        score=50
    else
        review_result=$(cat "$log_file")

        # 先检测 sentinel 标记
        local sentinel
        sentinel=$(check_sentinel "$review_result")
        if [ "$sentinel" = "pass" ]; then
            log_console "Sentinel 通道: 检测到 AUTORESEARCH_RESULT:PASS，直接判定通过"
            score=100
        elif [ "$sentinel" = "fail" ]; then
            log_console "Sentinel 通道: 检测到 AUTORESEARCH_RESULT:FAIL，直接判定不通过"
            score=0
        else
            score=$(extract_score "$review_result")

            if [ -z "$score" ] || [ "$score" = "0" ]; then
                log "警告: 无法从审核结果中提取评分，默认为 50"
                score=50
            fi
        fi
    fi

    echo "- 审核评分 (Codex): $score/100" >> "$WORK_DIR/log.md"

    log_console "审核评分: $score/100"

    echo "$review_result"
    echo "$score" > "$WORK_DIR/.last_score"
    return 0
}

# ==================== UI 验证相关 ====================

# UI 验证配置变量（可通过环境变量覆盖）
UI_VERIFY_ENABLED="${UI_VERIFY_ENABLED:-yes}"
UI_VERIFY_TIMEOUT="${UI_VERIFY_TIMEOUT:-60}"
UI_DEV_PORT="${UI_DEV_PORT:-}"

# 存储 dev server 进程 ID 的全局变量（用于清理）
_UI_DEV_SERVER_PID=""

# 从项目配置推断 dev server 启动命令
# 返回: dev server 命令字符串，如果无法推断则返回空
# UI verification functions are in lib/ui_verify.sh


# Scoring functions (check_sentinel, extract_score, check_score_passed) are in lib/scoring.sh

get_last_score() {
    if [ -f "$WORK_DIR/.last_score" ]; then
        cat "$WORK_DIR/.last_score"
    else
        echo "0"
    fi
}

record_final_result() {
    local issue_number=$1
    local status=$2
    local iterations=$3
    local final_score=$4

    cd "$PROJECT_ROOT"

    local tests_passed="false"
    local test_cmd
    test_cmd=$(get_test_command)
    if [ -n "$test_cmd" ] && $test_cmd &> /dev/null; then
        tests_passed="true"
    fi

    local results_file="$PROJECT_ROOT/.autoresearch/results.tsv"
    printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
        "$(date -Iseconds)" \
        "$issue_number" \
        "$ISSUE_TITLE" \
        "$status" \
        "$iterations" \
        "$tests_passed" \
        "$final_score" \
        "$final_score" \
        "$BRANCH_NAME" \
        "" >> "$results_file"

    cat >> "$WORK_DIR/log.md" << EOF

## 最终结果
- 总迭代次数: $iterations
- 最终评分: $final_score/100
- 状态: $status
- 分支: $BRANCH_NAME
- 结束时间: $(date '+%Y-%m-%d %H:%M:%S')
EOF
}

# ==================== 继续模式：恢复状态 ====================

find_last_iteration() {
    local last=0
    if [ ! -d "$WORK_DIR" ]; then
        echo 0
        return
    fi
    for f in "$WORK_DIR"/iteration-*.log; do
        [ -f "$f" ] || continue
        local num
        num=$(basename "$f" | grep -oE 'iteration-[0-9]+' | grep -oE '[0-9]+')
        if [ -n "$num" ] && [ "$num" -gt "$last" ] 2>/dev/null; then
            last=$num
        fi
    done
    echo "$last"
}

restore_continue_state() {
    local last_iter
    last_iter=$(find_last_iteration)

    # 清洗：只保留数字
    last_iter=$(echo "$last_iter" | tr -cd '0-9')

    if [ -z "$last_iter" ] || ! [ "$last_iter" -gt 0 ] 2>/dev/null; then
        log_console "⚠️ 未找到任何迭代记录，回退为全新运行 (last_iter='$last_iter')"
        CONTINUE_MODE=0
        return
    fi

    log_console "上次运行到迭代 ${last_iter}，从迭代 $((last_iter + 1)) 继续"

    # 恢复迭代计数
    ITERATION=$last_iter

    # 恢复最终评分
    if [ -f "$WORK_DIR/.last_score" ]; then
        FINAL_SCORE=$(cat "$WORK_DIR/.last_score" | tr -cd '0-9')
        [ -z "$FINAL_SCORE" ] && FINAL_SCORE=0
        log_console "上次评分: $FINAL_SCORE/100"
    fi

    # 继续模式重置连续失败计数
    CONSECUTIVE_ITERATION_FAILURES=0

    # 恢复上次的审核反馈：从最后一个 review log 中提取
    # 使用通配符搜索，避免 continue 模式更改 agent 列表后找不到之前 agent 的日志
    local last_review_log=""
    last_review_log=$(ls -t "$WORK_DIR/iteration-${last_iter}-"*-review.log 2>/dev/null | head -1) || true

    if [ -n "$last_review_log" ] && [ -f "$last_review_log" ]; then
        PREVIOUS_FEEDBACK=$(cat "$last_review_log")
        log "已恢复上次审核反馈"
    else
        # 没有审核反馈，可能是迭代 1 就中断了
        PREVIOUS_FEEDBACK="初始实现已完成，请审核代码质量并给出评分。如果有问题请直接修复。"
        log "未找到审核反馈，使用默认反馈"
    fi

    # 确保在正确的分支上
    cd "$PROJECT_ROOT"
    local branch="feature/issue-$ISSUE_NUMBER"
    if git show-ref --verify --quiet "refs/heads/$branch"; then
        git checkout "$branch"
        BRANCH_NAME="$branch"
        log_console "已切换到分支: $branch"
    else
        log_console "⚠️ 未找到分支 ${branch}，将创建新分支"
        git checkout -b "$branch"
        BRANCH_NAME="$branch"
    fi

    # 检测本地分支与 remote tracking branch 的分叉状态
    local remote_branch="origin/$branch"
    if git show-ref --verify --quiet "refs/remotes/$remote_branch" 2>/dev/null; then
        local rev_count
        rev_count=$(git rev-list --left-right --count "$remote_branch...$branch" 2>/dev/null || echo "0	0")
        local ahead behind
        ahead=$(echo "$rev_count" | awk '{print $2}')
        behind=$(echo "$rev_count" | awk '{print $1}')
        if [ "$ahead" -gt 0 ] && [ "$behind" -gt 0 ]; then
            log_console "⚠️ 本地分支与远程分支已分叉: ahead $ahead, behind $behind"
            log "分支分叉检测: $branch 与 $remote_branch 分叉 (ahead=$ahead, behind=$behind)"
            log_console "建议执行: git rebase $remote_branch 或手动合并后再继续"
        elif [ "$behind" -gt 0 ]; then
            log_console "⚠️ 本地分支落后远程 $behind 个提交"
            log "分支落后检测: $branch 落后 $remote_branch $behind 个提交"
            log_console "建议执行: git pull $remote_branch 后再继续"
        fi
    else
        log "远程分支 $remote_branch 不存在，跳过分叉检测"
    fi

    # 检测是否有残留的 autoresearch stash（上次中断遗留）
    # 只警告，不自动 pop，避免冲突导致脚本中断
    local residual_stash
    residual_stash=$(git stash list 2>/dev/null | grep 'autoresearch-temp-' | head -1 || true)
    if [ -n "$residual_stash" ]; then
        local stash_index
        stash_index=$(echo "$residual_stash" | grep -oE 'stash@\{[0-9]+\}' | head -1)
        log_console "⚠️ 发现上次中断遗留的 stash: $residual_stash"
        log_console "   如需恢复，请手动执行: git stash pop $stash_index"
        log "发现残留 stash: $residual_stash (未自动恢复)"
    fi

    # 追加继续标记到日志
    echo "" >> "$WORK_DIR/log.md"
    echo "---" >> "$WORK_DIR/log.md"
    echo "" >> "$WORK_DIR/log.md"
    echo "## 继续运行 (从迭代 $((last_iter + 1)) 继续)" >> "$WORK_DIR/log.md"
    echo "- 继续时间: $(date '+%Y-%m-%d %H:%M:%S')" >> "$WORK_DIR/log.md"
    echo "- 上次评分: $FINAL_SCORE/100" >> "$WORK_DIR/log.md"

    # 报告子任务状态（如有）
    if has_subtasks; then
        local progress
        progress=$(get_subtask_progress_summary)
        echo "- 子任务: $progress" >> "$WORK_DIR/log.md"
        log_console "$progress"
    fi

    echo "" >> "$WORK_DIR/log.md"
}

# ==================== 参数解析 ====================

CONTINUE_MODE=0
NO_ARCHIVE=0
AGENT_LIST=""

while getopts "p:a:c-:" opt; do
    case $opt in
        p) PROJECT_ROOT="$(cd "$OPTARG" && pwd)" ;;
        a) AGENT_LIST="$OPTARG" ;;
        c) CONTINUE_MODE=1 ;;
        -)
            case "$OPTARG" in
                no-archive) NO_ARCHIVE=1 ;;
                no-ui-verify) FEATURE_UI_VERIFY=0 ;;
                no-hard-gate) FEATURE_HARD_GATE=0 ;;
                issues-dir=*)
                    ISSUES_DIR="${OPTARG#issues-dir=}"
                    ;;
                issue-source=*)
                    ISSUE_SOURCE="${OPTARG#issue-source=}"
                    ;;
                space=*)
                    ICAFE_SPACE="${OPTARG#space=}"
                    ;;
                target-branch=*)
                    ICODE_TARGET_BRANCH="${OPTARG#target-branch=}"
                    ;;
                *) usage ;;
            esac
            ;;
        *) usage ;;
    esac
done
shift $((OPTIND - 1))

if [ -z "$1" ]; then
    usage
fi

ISSUE_NUMBER=$1
MAX_ITERATIONS=${2:-$DEFAULT_MAX_ITERATIONS}

log_console ""
log_console "  ╔══════════════════════════════════════╗"
log_console "  ║  autoresearch - 自动化开发工具       ║"
log_console "  ╚══════════════════════════════════════╝"
log_console ""
log_console "🤖 Issue: #$ISSUE_NUMBER"
log_console "📁 项目: $PROJECT_ROOT"
if [ $CONTINUE_MODE -eq 1 ]; then
    log_console "🔄 模式: 继续上次运行"
else
    log_console "🚀 模式: 全新运行"
fi
log_console "🔢 最大迭代次数: $MAX_ITERATIONS"

# 构建 AGENT_NAMES 数组（必须在 check_dependencies 和日志输出之前）
if ! parse_agent_list "$AGENT_LIST"; then
    error "$AGENT_LIST_ERROR"
    exit 1
fi

log_console "Agent 列表: ${AGENT_NAMES[*]} (初始实现: ${AGENT_NAMES[0]})"

# 检测本地 Issue 模式 (必须在 check_project 之前，因为需要设置 ISSUE_SOURCE)
detect_issue_source_mode

# 检查项目环境
check_project

# 检查依赖
check_dependencies

# 获取 Issue 信息
get_issue_info "$ISSUE_NUMBER"

# Issue 引用字符串 (用于 prompt)
if [ "$ISSUE_SOURCE" = "local" ]; then
    ISSUE_REF="本地 Issue #$ISSUE_NUMBER"
    log_console "📂 Issue 来源: 本地文件 ($ISSUE_FILE)"
elif [ "$ISSUE_SOURCE" = "baidu" ]; then
    ISSUE_REF="百度 iCafe 卡片 #$ISSUE_NUMBER (空间: $ICAFE_SPACE)"
    log_console "📂 Issue 来源: 百度 iCafe (空间: $ICAFE_SPACE, 卡片: #$ISSUE_NUMBER)"
else
    ISSUE_REF="GitHub Issue #$ISSUE_NUMBER"
fi

# 设置工作目录
setup_work_directory "$ISSUE_NUMBER"

# 创建分支
create_branch "$ISSUE_NUMBER"

# ==================== 继续模式：恢复状态 ====================

ITERATION=0
PREVIOUS_FEEDBACK=""
FINAL_SCORE=0
CONSECUTIVE_ITERATION_FAILURES=0
CONTEXT_RETRIES=0

if [ $CONTINUE_MODE -eq 1 ]; then
    restore_continue_state

    # 如果 restore_continue_state 已将 CONTINUE_MODE 重置为 0，跳过后续继续模式处理
    # 这意味着没有找到迭代记录，将作为全新运行处理
    if [ $CONTINUE_MODE -eq 0 ]; then
        log_console "将以全新模式运行..."
    else
        # 防御：确保 ITERATION 是有效数字
        if [ -z "$ITERATION" ] || ! [ "$ITERATION" -gt 0 ] 2>/dev/null; then
            error "无法恢复迭代状态，ITERATION=$ITERATION"
            exit 1
        fi

        # 校验 tasks.json 完整性，损坏则删除并回退到原始模式
        tasks_file=$(get_tasks_file)
        if [ -f "$tasks_file" ]; then
            if ! validate_tasks_json; then
                log "⚠️ tasks.json 已损坏，删除并回退到原始模式"
                log_console "⚠️ tasks.json 已损坏，回退到原始模式（无子任务拆分）"
                rm -f "$tasks_file"
            fi
        fi

        # 不指定轮数时，总迭代数=默认值；指定时，总迭代数=已有+指定轮数
        if [ -z "$2" ]; then
            MAX_ITERATIONS=$DEFAULT_MAX_ITERATIONS
            remaining=$((MAX_ITERATIONS - ITERATION))
            log_console "继续运行: 已完成 $ITERATION 轮，再跑 $remaining 轮 (总计 $MAX_ITERATIONS)"
        else
            MAX_ITERATIONS=$((ITERATION + $2))
            log_console "继续运行: 已完成 $ITERATION 轮，再跑 $2 轮 (总计 $MAX_ITERATIONS)"
        fi
    fi
fi

# ==================== 规划阶段 ====================

# 非继续模式时执行规划阶段
if [ $CONTINUE_MODE -eq 0 ]; then
    log_console ""
    log_console "📋 规划阶段: 拆分子任务..."
    log_console ""

    if ! run_planning_phase "$ISSUE_NUMBER"; then
        log_console "⚠️ 规划阶段未生成子任务，使用原有模式"
    fi
fi

# ==================== 迭代循环 ====================

# Agent 列表: 第一个用于初始实现，后续按顺序轮流审核
# 有子任务时: 每个子任务独立进入实现→审核→修复循环
# 无子任务时: 迭代 1 第一个 agent 初始实现，迭代 2+ 轮流审核+修复

run_review_and_fix() {
    local agent_idx=$1
    local agent_name="${AGENT_NAMES[$agent_idx]}"
    local review_func="run_${agent_name}_review"
    local impl_func="run_${agent_name}"

    # 审核
    $review_func "$ISSUE_NUMBER" "$ITERATION" || true
    local review_ret=$?
    if [ $review_ret -ne 0 ]; then
        local review_log="$WORK_DIR/iteration-$ITERATION-${agent_name}-review.log"
        if handle_context_overflow "$ITERATION" "$agent_name" "$review_log"; then
            return
        fi
        if [ $review_ret -eq 2 ]; then
            log_console "⚠️ $agent_name 审核被跳过 (模型错误)，尝试下一个 agent"
            SKIPPED_AGENT=1
            return
        fi
        log "$agent_name 审核失败，跳到下一次迭代"
        ITERATION_FAILED=1
        return
    fi

    REVIEW_LOG_FILE="$WORK_DIR/iteration-$ITERATION-${agent_name}-review.log"
    SCORE=$(get_last_score)
    FINAL_SCORE=$SCORE

    if check_score_passed "$SCORE"; then
        log_console "✅ 审核通过！评分: $SCORE/100 (达标线: $PASSING_SCORE)"
        CONSECUTIVE_ITERATION_FAILURES=0
        PASSED=1
        FINAL_REVIEW_REPORT=$(cat "$REVIEW_LOG_FILE" 2>/dev/null || echo "")

        # 如果有子任务，标记当前子任务为通过
        if has_subtasks; then
            local current_subtask_id
            current_subtask_id=$(get_current_subtask_id)
            if [ -n "$current_subtask_id" ]; then
                # UI 类型子任务：先进行浏览器验证
                if is_ui_subtask; then
                    local subtask_title
                    subtask_title=$(get_current_subtask_title)
                    local ui_result
                    if [ $FEATURE_UI_VERIFY -eq 1 ]; then
                        ui_result=$(run_ui_verification "$WORK_DIR" "$subtask_title") || true
                    else
                        ui_result='{"pass": true, "feedback": "UI 验证已通过 --no-ui-verify 禁用"}'
                    fi
                    local ui_pass
                    ui_pass=$(echo "$ui_result" | jq -r '.pass // "true"' 2>/dev/null) || ui_pass="true"

                    # 记录 UI 验证结果到日志
                    local ui_feedback
                    ui_feedback=$(echo "$ui_result" | jq -r '.feedback // ""' 2>/dev/null) || ui_feedback=""
                    echo "- UI 验证: $ui_pass - $ui_feedback" >> "$WORK_DIR/log.md"

                    if [ "$ui_pass" != "true" ]; then
                        # UI 验证失败：不标记 passed，反馈传递给下一迭代
                        log_console "❌ UI 验证未通过"
                        UI_VERIFY_FAILED=1
                        PREVIOUS_FEEDBACK="代码审核通过，但 UI 验证未通过：$ui_feedback"
                        PASSED=0
                        return
                    fi
                    log_console "✅ UI 验证通过"
                fi

                mark_subtask_passed "$current_subtask_id"
                log_console "✅ 子任务 $current_subtask_id 审核通过"

                # 检查是否还有未通过的子任务
                if all_subtasks_passed; then
                    log_console "🎉 所有子任务已通过！"
                    ALL_SUBTASKS_DONE=1
                else
                    # 还有子任务，重置状态准备下一个
                    local progress
                    progress=$(get_subtask_progress_summary)
                    log_console "$progress"
                    # 重置审核状态，下一个子任务需要新的审核
                    PASSED=0
                    PREVIOUS_FEEDBACK=""
                    SUBTASK_ADVANCED=1
                    CONTEXT_RETRIES=0
                fi
            fi
        fi

        return
    fi

    log_console "评分未达标 ($SCORE/$PASSING_SCORE)，$agent_name 根据反馈修复..."

    REVIEW_FEEDBACK=$(cat "$REVIEW_LOG_FILE")
    $impl_func "$ISSUE_NUMBER" "$ITERATION" "$REVIEW_FEEDBACK" || true
    local impl_ret=$?
    if [ $impl_ret -ne 0 ]; then
        local impl_log="$WORK_DIR/iteration-$ITERATION-${agent_name}.log"
        if handle_context_overflow "$ITERATION" "$agent_name" "$impl_log"; then
            return
        fi
        if [ $impl_ret -eq 2 ]; then
            log_console "⚠️ $agent_name 修复被跳过 (模型错误)，尝试下一个 agent"
            SKIPPED_AGENT=1
            return
        fi
        log_console "$agent_name 修复失败，跳到下一次迭代"
        PREVIOUS_FEEDBACK="$REVIEW_FEEDBACK"
        ITERATION_FAILED=1
        return
    fi

    log_console "$agent_name 修复完成"

    # 硬门禁检查：修复后先跑 build → lint → test
    if [ $FEATURE_HARD_GATE -eq 1 ] && ! run_hard_gate_checks "$ITERATION"; then
        log_console "❌ 硬门禁检查未通过"
        HARD_GATE_FAILED=1
        local gate_log="$WORK_DIR/hard-gate-$ITERATION.log"
        PREVIOUS_FEEDBACK="硬门禁检查未通过，请根据以下错误修复代码：\n\n$(cat "$gate_log" 2>/dev/null || echo "详见 hard-gate-$ITERATION.log")"
        ITERATION_FAILED=1
        return
    fi
    log_console "✅ 硬门禁检查通过"
    PREVIOUS_FEEDBACK=""
}

# 有子任务时的循环逻辑
ALL_SUBTASKS_DONE=0

while [ $ITERATION -lt $MAX_ITERATIONS ]; do
    ITERATION=$((ITERATION + 1))
    PASSED=0
    ITERATION_FAILED=0
    SUBTASK_ADVANCED=0
    HARD_GATE_FAILED=0
    CONTEXT_OVERFLOW=0
    # PROMPT_TRIMMED 不在此处重置：溢出后的裁剪效果需持续到上下文压力解除
    # 在迭代成功完成时（非溢出退出）重置
    UI_VERIFY_FAILED=0
    SKIPPED_AGENT=0

    log_console ""
    log_console "──────────────────────────────────────────"
    log_console "🔄 迭代 $ITERATION/$MAX_ITERATIONS"
    if has_subtasks; then
        subtask_progress=$(get_subtask_progress_summary)
        log_console "$subtask_progress"
    fi
    if [ $ITERATION -eq 1 ]; then
        log_console "👤 ${AGENT_NAMES[0]} 开始实现..."
    else
        agent_idx=$(get_review_agent $ITERATION)
        log_console "🔍 ${AGENT_NAMES[$agent_idx]} 开始审核..."
    fi
    log_console "──────────────────────────────────────────"

    # ---- 无子任务模式：迭代 1 第一个 agent 初始实现 ----
    if [ $ITERATION -eq 1 ] && ! has_subtasks; then
        HARD_GATE_FAILED=0
        first_agent="${AGENT_NAMES[0]}"
        first_impl_func="run_${first_agent}"
        $first_impl_func "$ISSUE_NUMBER" "$ITERATION" "" || true
        first_ret=$?
        if [ $first_ret -ne 0 ]; then
            impl_log="$WORK_DIR/iteration-$ITERATION-${first_agent}.log"
            if handle_context_overflow "$ITERATION" "$first_agent" "$impl_log"; then
                : # 上下文溢出已自动交接
            elif [ $first_ret -eq 2 ]; then
                log_console "⚠️ $first_agent 被跳过 (模型错误)，尝试其他 agent..."
                for skip_idx in $(seq 1 $((${#AGENT_NAMES[@]} - 1))); do
                    skip_agent="${AGENT_NAMES[$skip_idx]}"
                    log_console "尝试 $skip_agent..."
                    SKIPPED_AGENT=0
                    skip_func="run_${skip_agent}"
                    $skip_func "$ISSUE_NUMBER" "$ITERATION" "" || true
                    skip_ret=$?
                    if [ $skip_ret -eq 0 ]; then
                        first_agent="$skip_agent"
                        first_ret=0
                        break
                    elif [ $skip_ret -ne 2 ]; then
                        log_console "❌ $skip_agent 初始实现失败"
                        ITERATION_FAILED=1
                        break
                    fi
                    log_console "⚠️ $skip_agent 也被跳过"
                done
                if [ $first_ret -ne 0 ] && [ $ITERATION_FAILED -eq 0 ]; then
                    log_console "❌ 所有 agent 均被跳过，标记为失败"
                    ITERATION_FAILED=1
                fi
            else
                log_console "❌ $first_agent 初始实现失败"
                ITERATION_FAILED=1
            fi
        fi
        if [ $first_ret -eq 0 ]; then
            # 硬门禁检查：build → lint → test
            if [ $FEATURE_HARD_GATE -eq 1 ] && ! run_hard_gate_checks "$ITERATION"; then
                log_console "❌ 硬门禁检查未通过"
                HARD_GATE_FAILED=1
                gate_log="$WORK_DIR/hard-gate-$ITERATION.log"
                PREVIOUS_FEEDBACK="硬门禁检查未通过，请根据以下错误修复代码：\n\n$(cat "$gate_log" 2>/dev/null || echo "详见 hard-gate-$ITERATION.log")"
                ITERATION_FAILED=1
            else
                log_console "✅ 硬门禁检查通过"
                PREVIOUS_FEEDBACK="初始实现完成，请审核代码质量并给出评分。如果有问题请直接修复。"
            fi
        fi

        # 追加经验到 progress.md（溢出时已由 handle_context_overflow 追加）
        if [ $CONTEXT_OVERFLOW -eq 0 ]; then
            impl_log="$WORK_DIR/iteration-$ITERATION-${first_agent}.log"
            append_to_progress "$ITERATION" "$first_agent" "$impl_log" "N/A" "初始实现" ""
        fi

        if [ $CONTEXT_OVERFLOW -eq 0 ]; then
            if [ $ITERATION_FAILED -eq 1 ] && [ $HARD_GATE_FAILED -eq 0 ]; then
                CONSECUTIVE_ITERATION_FAILURES=$((CONSECUTIVE_ITERATION_FAILURES + 1))
            elif [ $HARD_GATE_FAILED -eq 0 ]; then
                CONSECUTIVE_ITERATION_FAILURES=0
            fi
        fi
        continue
    fi

    # ---- 有子任务模式：迭代 1 第一个 agent 实现当前子任务 ----
    if [ $ITERATION -eq 1 ] && has_subtasks; then
        HARD_GATE_FAILED=0
        first_agent="${AGENT_NAMES[0]}"
        first_impl_func="run_${first_agent}"
        $first_impl_func "$ISSUE_NUMBER" "$ITERATION" "" || true
        first_ret=$?
        if [ $first_ret -ne 0 ]; then
            impl_log="$WORK_DIR/iteration-$ITERATION-${first_agent}.log"
            if handle_context_overflow "$ITERATION" "$first_agent" "$impl_log"; then
                : # 上下文溢出已自动交接
            elif [ $first_ret -eq 2 ]; then
                log_console "⚠️ $first_agent 被跳过 (模型错误)，尝试其他 agent..."
                for skip_idx in $(seq 1 $((${#AGENT_NAMES[@]} - 1))); do
                    skip_agent="${AGENT_NAMES[$skip_idx]}"
                    log_console "尝试 $skip_agent..."
                    SKIPPED_AGENT=0
                    skip_func="run_${skip_agent}"
                    $skip_func "$ISSUE_NUMBER" "$ITERATION" "" || true
                    skip_ret=$?
                    if [ $skip_ret -eq 0 ]; then
                        first_agent="$skip_agent"
                        first_ret=0
                        break
                    elif [ $skip_ret -ne 2 ]; then
                        log_console "❌ $skip_agent 初始实现失败"
                        ITERATION_FAILED=1
                        break
                    fi
                    log_console "⚠️ $skip_agent 也被跳过"
                done
                if [ $first_ret -ne 0 ] && [ $ITERATION_FAILED -eq 0 ]; then
                    log_console "❌ 所有 agent 均被跳过，标记为失败"
                    ITERATION_FAILED=1
                fi
            else
                log_console "❌ $first_agent 初始实现失败"
                ITERATION_FAILED=1
            fi
        else
            # 硬门禁检查：build → lint → test
            if [ $FEATURE_HARD_GATE -eq 1 ] && ! run_hard_gate_checks "$ITERATION"; then
                log_console "❌ 硬门禁检查未通过"
                HARD_GATE_FAILED=1
                gate_log="$WORK_DIR/hard-gate-$ITERATION.log"
                PREVIOUS_FEEDBACK="硬门禁检查未通过，请根据以下错误修复代码：\n\n$(cat "$gate_log" 2>/dev/null || echo "详见 hard-gate-$ITERATION.log")"
                ITERATION_FAILED=1
            else
                log_console "✅ 硬门禁检查通过"
                PREVIOUS_FEEDBACK="初始实现完成，请审核代码质量并给出评分。如果有问题请直接修复。"
            fi
        fi

        # 追加经验到 progress.md（溢出时已由 handle_context_overflow 追加）
        if [ $CONTEXT_OVERFLOW -eq 0 ]; then
            impl_log="$WORK_DIR/iteration-$ITERATION-${first_agent}.log"
            subtask_title=
            subtask_title=$(get_current_subtask_title)
            append_to_progress "$ITERATION" "$first_agent" "$impl_log" "N/A" "初始实现 - $subtask_title" ""
        fi

        if [ $CONTEXT_OVERFLOW -eq 0 ]; then
            if [ $ITERATION_FAILED -eq 1 ] && [ $HARD_GATE_FAILED -eq 0 ]; then
                CONSECUTIVE_ITERATION_FAILURES=$((CONSECUTIVE_ITERATION_FAILURES + 1))
            elif [ $HARD_GATE_FAILED -eq 0 ]; then
                CONSECUTIVE_ITERATION_FAILURES=0
            fi
        fi
        continue
    fi

    # ---- 迭代 >=2: agent 轮流审核 + 修复 ----
    agent_idx=$(get_review_agent $ITERATION)
    agent_name="${AGENT_NAMES[$agent_idx]}"
    run_review_and_fix $agent_idx

    # 跳过的 agent：尝试其他可用 agent
    if [ $SKIPPED_AGENT -eq 1 ]; then
        log_console "⚠️ $agent_name 被跳过，尝试其他 agent..."
        for skip_idx in $(seq 0 $((${#AGENT_NAMES[@]} - 1))); do
            if [ $skip_idx -eq $agent_idx ]; then
                continue
            fi
            skip_agent="${AGENT_NAMES[$skip_idx]}"
            log_console "尝试 $skip_agent..."
            SKIPPED_AGENT=0
            run_review_and_fix $skip_idx
            if [ $SKIPPED_AGENT -eq 0 ]; then
                agent_name="$skip_agent"
                break
            fi
            log_console "⚠️ $skip_agent 也被跳过"
        done
    fi

    # 上下文溢出时跳过正常处理（进度已由 handle_context_overflow 保存）
    if [ $CONTEXT_OVERFLOW -eq 1 ]; then
        continue
    fi

    # 追加经验到 progress.md
    review_log="$WORK_DIR/iteration-$ITERATION-${agent_name}-review.log"
    review_feedback_brief=""
    if [ -f "$review_log" ]; then
        # 避免 SIGPIPE: head 直接读取文件，而非通过 cat 管道
        review_feedback_brief=$(head -c 800 "$review_log" 2>/dev/null || true)
    fi

    subtask_label=""
    if has_subtasks; then
        current_id=
        current_id=$(get_current_subtask_id)
        if [ -n "$current_id" ]; then
            subtask_label=" - $current_id"
        fi
    fi
    append_to_progress "$ITERATION" "$agent_name" "$review_log" "$SCORE" "审核+修复${subtask_label}" "$review_feedback_brief"

    # 所有子任务完成，跳出循环
    if [ $ALL_SUBTASKS_DONE -eq 1 ]; then
        break
    fi

    if [ $PASSED -eq 1 ] && ! has_subtasks; then
        break
    fi

    # CONTEXT_OVERFLOW=1: 不增加也不重置计数器（保留现场等特殊处理）
    # UI_VERIFY_FAILED=1: 不增加也不重置计数器（与 hard gate 失败同等待遇）
    if [ $CONTEXT_OVERFLOW -eq 0 ]; then
        if [ $ITERATION_FAILED -eq 1 ] && [ $HARD_GATE_FAILED -eq 0 ] && [ $UI_VERIFY_FAILED -eq 0 ]; then
            CONSECUTIVE_ITERATION_FAILURES=$((CONSECUTIVE_ITERATION_FAILURES + 1))
            log_console "⚠️ 连续迭代失败次数: $CONSECUTIVE_ITERATION_FAILURES/$MAX_CONSECUTIVE_FAILURES"
        elif [ $HARD_GATE_FAILED -eq 0 ] && [ $UI_VERIFY_FAILED -eq 0 ]; then
            # 只有非 hard gate 失败且非 UI 验证失败时才重置
            CONSECUTIVE_ITERATION_FAILURES=0
        fi
        # 迭代成功完成（非溢出），重置 prompt 裁剪标志
        PROMPT_TRIMMED=0
    fi

    if [ $CONSECUTIVE_ITERATION_FAILURES -ge $MAX_CONSECUTIVE_FAILURES ]; then
        error "连续 $CONSECUTIVE_ITERATION_FAILURES 次迭代失败，停止运行"
        record_final_result "$ISSUE_NUMBER" "agent_failed" "$ITERATION" "$FINAL_SCORE"
        SCRIPT_COMPLETED_NORMALLY=1
        exit 1
    fi
done

# ==================== 最终处理 ====================

if check_score_passed "$FINAL_SCORE"; then
    record_final_result "$ISSUE_NUMBER" "completed" "$ITERATION" "$FINAL_SCORE"

    echo ""
    log_console "  ╔══════════════════════════════════════╗"
    log_console "  ║          处理完成！                   ║"
    log_console "  ╚══════════════════════════════════════╝"
    log_console ""
    log_console "🎉 分支: $BRANCH_NAME"
    log_console "📊 评分: $FINAL_SCORE/100"
    log_console "🔄 迭代次数: $ITERATION"

    # 自动提交
    log_console ""
    if [ "$ISSUE_SOURCE" = "local" ]; then
        log_console "📦 本地模式: 提交更改并记录结果..."
    else
        log_console "📦 自动提交 PR 并合并..."
    fi
    log_console ""

    cd "$PROJECT_ROOT"

    # 提交所有更改
    log_console "提交更改..."
    git add -A

    # 构建 commit message：包含审核报告
    if [ "$ISSUE_SOURCE" = "local" ]; then
        COMMIT_MSG="feat: implement local issue #$ISSUE_NUMBER - $ISSUE_TITLE

$FINAL_REVIEW_REPORT"
    elif [ "$ISSUE_SOURCE" = "baidu" ]; then
        # iCafe 自动绑定格式: {space}-{sequence} [{type}] {title}
        COMMIT_MSG="$ICAFE_SPACE-$ISSUE_NUMBER [$ICAFE_CARD_TYPE] $ISSUE_TITLE

$FINAL_REVIEW_REPORT"
    else
        COMMIT_MSG="feat: implement issue #$ISSUE_NUMBER - $ISSUE_TITLE

$FINAL_REVIEW_REPORT

Closes #$ISSUE_NUMBER"
    fi

    git commit -m "$COMMIT_MSG" 2>/dev/null || log_console "没有需要提交的更改"

    # ===== 本地模式: 追加结果到 Issue 文件 =====
    if [ "$ISSUE_SOURCE" = "local" ]; then
        append_result_to_local_issue

        log_console ""
        log_console "  ╔══════════════════════════════════════╗"
        log_console "  ║      本地模式处理完成！              ║"
        log_console "  ╚══════════════════════════════════════╝"
        log_console ""
        log_console "🎉 分支: $BRANCH_NAME (本地)"
        log_console "📊 评分: $FINAL_SCORE/100"
        log_console "🔄 迭代次数: $ITERATION"
        log_console "📝 结果已追加到: $ISSUE_FILE"

        SCRIPT_COMPLETED_NORMALLY=1
        exit 0
    fi

    # ===== 百度 iCafe/iCode 模式: push_cr/评分/合入/关闭卡片 =====
    if [ "$ISSUE_SOURCE" = "baidu" ]; then
        log_console "百度模式: 推送代码并创建 CR..."

        # 检测目标分支
        local target_branch
        target_branch=$(detect_icode_target_branch)
        log "iCode CR 目标分支: $target_branch"

        # 推送代码并创建 CR
        local push_cr_output
        push_cr_output=$(icode-cli git push_cr --branch "$target_branch" 2>&1)

        if [ $? -ne 0 ]; then
            log_console "⚠️ icode-cli git push_cr 失败: $push_cr_output"
            record_final_result "$ISSUE_NUMBER" "push_cr_failed" "$ITERATION" "$FINAL_SCORE"
            SCRIPT_COMPLETED_NORMALLY=1
            exit 1
        fi

        log "push_cr 输出: $push_cr_output"

        # 从 push_cr 输出中解析 CR 编号
        ICODE_CR_NUMBER=$(echo "$push_cr_output" | grep -oE '[0-9]+' | tail -1)

        if [ -z "$ICODE_CR_NUMBER" ]; then
            log_console "⚠️ 无法从 push_cr 输出中解析 CR 编号"
            log_console "push_cr 输出: $push_cr_output"
            record_final_result "$ISSUE_NUMBER" "cr_parse_failed" "$ITERATION" "$FINAL_SCORE"
            SCRIPT_COMPLETED_NORMALLY=1
            exit 1
        fi

        log_console "✅ CR 已创建: #$ICODE_CR_NUMBER"

        # 评分 +2
        log_console "评分 CR #$ICODE_CR_NUMBER (+2)..."
        if ! icode-cli api set_review_score --repo "$ICODE_REPO" -n "$ICODE_CR_NUMBER" --score 2 2>&1; then
            log_console "⚠️ CR 评分失败，尝试继续合入"
        fi

        # 提交合入
        log_console "提交合入 CR #$ICODE_CR_NUMBER..."
        local submit_output
        submit_output=$(icode-cli api submit_review --repo "$ICODE_REPO" -n "$ICODE_CR_NUMBER" 2>&1)

        if [ $? -ne 0 ]; then
            log_console "⚠️ CR 合入失败: $submit_output"
            log_console "CR 编号: #$ICODE_CR_NUMBER，请手动合入"
        else
            log_console "✅ CR #$ICODE_CR_NUMBER 已合入"
        fi

        # 关闭 iCafe 卡片
        log_console "关闭 iCafe 卡片 #$ISSUE_NUMBER..."

        # 检查可用的状态转换
        local next_statuses
        next_statuses=$(icafe-cli card next-statuses --space "$ICAFE_SPACE" --sequence "$ISSUE_NUMBER" 2>&1 || true)
        log "卡片可转换状态: $next_statuses"

        # 尝试更新卡片状态为"已关闭"
        if icafe-cli card update --space "$ICAFE_SPACE" --sequence "$ISSUE_NUMBER" --status "已关闭" 2>&1; then
            log_console "✅ iCafe 卡片已关闭"
        else
            log_console "⚠️ 关闭卡片失败，可能需要手动关闭"
        fi

        # 添加评论到卡片
        log_console "添加评论到 iCafe 卡片 #$ISSUE_NUMBER..."
        local log_summary=""
        if [ -f "$WORK_DIR/log.md" ]; then
            log_summary=$(cat "$WORK_DIR/log.md")
        fi

        # 构建子任务摘要
        local subtask_summary=""
        if has_subtasks; then
            local tasks_file
            tasks_file=$(get_tasks_file)
            local total passed
            total=$(jq '.subtasks | length' "$tasks_file" 2>/dev/null)
            passed=$(jq '[.subtasks[] | select(.passes == true)] | length' "$tasks_file" 2>/dev/null)
            subtask_summary="- 子任务: ${passed}/${total} 完成"
        fi

        icafe-cli comment create --space "$ICAFE_SPACE" --sequence "$ISSUE_NUMBER" --content "$(cat <<EOF
## autoresearch 自动处理完成

- **CR**: #$ICODE_CR_NUMBER
- **评分**: $FINAL_SCORE/100
- **迭代次数**: $ITERATION
- **实现方式**: autoresearch 多 agent 迭代 (${AGENT_NAMES[@]})
$subtask_summary

该卡片已由 autoresearch 自动实现、审核并合入。
EOF
)" 2>/dev/null || log "警告: 添加评论失败"

        log_console ""
        log_console "  ╔══════════════════════════════════════╗"
        log_console "  ║    百度模式处理完成！iCafe + iCode   ║"
        log_console "  ╚══════════════════════════════════════╝"
        log_console ""
        log_console "✅ CR: #$ICODE_CR_NUMBER"
        log_console "📂 iCafe 卡片: #$ISSUE_NUMBER (空间: $ICAFE_SPACE)"
        log_console "🔗 状态: 已合入并关闭"

        SCRIPT_COMPLETED_NORMALLY=1
        exit 0
    fi

    # ===== GitHub 模式: 推送/PR/合并/关闭 =====
    if ! push_branch_with_recovery; then
        record_final_result "$ISSUE_NUMBER" "push_failed" "$ITERATION" "$FINAL_SCORE"
        SCRIPT_COMPLETED_NORMALLY=1
        exit 1
    fi

    # 创建 PR
    log_console "创建 Pull Request..."

    # 构建子任务摘要（如有）
    subtask_summary=""
    if has_subtasks; then
        tasks_file=$(get_tasks_file)
        total= passed=
        total=$(jq '.subtasks | length' "$tasks_file" 2>/dev/null)
        passed=$(jq '[.subtasks[] | select(.passes == true)] | length' "$tasks_file" 2>/dev/null)
        subtask_summary="
## Subtasks
- Completed: $passed/$total
$(jq -r '.subtasks[] | "- [\(.passes | if true then "x" else " " end)] \(.id): \(.title)"' "$tasks_file" 2>/dev/null)
"
    fi

    # 构建 UI 验证摘要（如有）
    ui_verify_summary=""
    if [ -f "$WORK_DIR/ui-verify-result.json" ]; then
        ui_pass_status=$(jq -r '.pass // "N/A"' "$WORK_DIR/ui-verify-result.json" 2>/dev/null)
        ui_feedback_text=$(jq -r '.feedback // ""' "$WORK_DIR/ui-verify-result.json" 2>/dev/null)
        ui_verify_summary="
## UI Verification
- Result: $ui_pass_status
- Feedback: $ui_feedback_text
"
    fi

    PR_URL=$(gh pr create --title "feat: $ISSUE_TITLE (#$ISSUE_NUMBER)" --body "$(cat <<EOF
## Summary
- Implements #$ISSUE_NUMBER
- Score: $FINAL_SCORE/100
- Iterations: $ITERATION
$subtask_summary$ui_verify_summary
## Test plan
- [x] All tests pass
- [x] Code review completed with score >= $PASSING_SCORE

Closes #$ISSUE_NUMBER
EOF
)" 2>&1)

    if echo "$PR_URL" | grep -q "https://github.com"; then
        PR_NUMBER=$(echo "$PR_URL" | grep -oE '[0-9]+$')
        log_console "✅ PR 已创建: $PR_URL"

        # 合并 PR（不删除本地分支，我们自己处理）
        log_console "合并 PR #$PR_NUMBER..."
        MERGE_OUTPUT=""
        if ! MERGE_OUTPUT=$(gh pr merge "$PR_NUMBER" --merge 2>&1); then
            log_console "⚠️ PR 合并失败，请手动处理"
            log_console "PR URL: $PR_URL"
            log "PR merge failed: $MERGE_OUTPUT"
            cat >> "$WORK_DIR/log.md" << EOF

---

## ⚠️ PR 合并失败

**时间**: $(date '+%Y-%m-%d %H:%M:%S')
**PR**: $PR_URL
**错误输出**:
\`\`\`
$MERGE_OUTPUT
\`\`\`

请手动合并: gh pr merge $PR_NUMBER --merge
EOF
        fi

        # 切换回主分支前，先处理未提交的更改
        cd "$PROJECT_ROOT"
        main_branch=$(git remote show origin | grep 'HEAD branch' | cut -d':' -f2 | tr -d ' ')
        [ -z "$main_branch" ] && main_branch="master"

        # 切换回主分支前，如果有未提交的更改，先 stash
        stashed=0
        if ! git diff --quiet 2>/dev/null || ! git diff --cached --quiet 2>/dev/null; then
            log "检测到未提交的更改，暂存..."
            if git stash push -m "autoresearch-temp-$(date +%s)" -- .autoresearch/ 2>/dev/null; then
                stashed=1
            fi
        fi

        cleanup_merged_branch "$main_branch" "$BRANCH_NAME"

        # 恢复 stash（.autoresearch/ 为临时数据，恢复失败直接 drop）
        if [ $stashed -eq 1 ]; then
            if ! git stash pop 2>/dev/null; then
                log "stash pop 失败（文件冲突），跳过恢复"
                git stash drop 2>/dev/null || true
            fi
        fi

        # 添加评论到 Issue（仅包含总结信息）
        log_console "添加评论到 Issue #$ISSUE_NUMBER..."
        log_summary=""
        if [ -f "$WORK_DIR/log.md" ]; then
            log_summary=$(cat "$WORK_DIR/log.md")
        fi
        gh issue comment "$ISSUE_NUMBER" --body "$(cat <<EOF
## 自动处理完成

- **PR**: $PR_URL (已合并)
- **评分**: $FINAL_SCORE/100
- **迭代次数**: $ITERATION
- **实现方式**: autoresearch 多 agent 迭代 (${AGENT_NAMES[@]})

${log_summary}

该 Issue 已由 autoresearch 自动实现、审核并合并。
EOF
)" 2>/dev/null || log "警告: 添加评论失败"

        # 关闭 Issue
        log_console "关闭 Issue #$ISSUE_NUMBER..."
        gh issue close "$ISSUE_NUMBER" --reason completed 2>/dev/null || log_console "⚠️ 关闭 Issue 失败 (可能已通过 PR 自动关闭)"

        log_console ""
        log_console "  ╔══════════════════════════════════════╗"
        log_console "  ║      全部完成！Issue 已自动处理      ║"
        log_console "  ╚══════════════════════════════════════╝"
        log_console ""
        log_console "✅ PR: $PR_URL"
        log_console "🔗 状态: 已合并并关闭"
    else
        log_console "⚠️ PR 创建失败或已存在"
        log_console "$PR_URL"
    fi

    SCRIPT_COMPLETED_NORMALLY=1
    exit 0
fi

# 达到最大迭代次数
log_console ""
log_console "  ╔══════════════════════════════════════╗"
log_console "  ║  达到最大迭代次数，需要人工介入       ║"
log_console "  ╚══════════════════════════════════════╝"
log_console ""
log_console "⚠️ 最终评分: $FINAL_SCORE/100"
log_console "📂 工作目录: $WORK_DIR"

record_final_result "$ISSUE_NUMBER" "blocked" "$ITERATION" "$FINAL_SCORE"

SCRIPT_COMPLETED_NORMALLY=1
exit 1
