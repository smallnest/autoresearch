#!/bin/bash
# autoresearch/run.sh - 自动化处理 GitHub Issue
#
# 通用版本 - 可处理任意 Git + GitHub 项目
#
# 用法:
#   ./run.sh [-p project_path] [-a agents] [-c] <issue_number> [max_iterations]
#
# 示例:
#   ./run.sh 42                              # 处理当前目录项目的 Issue #42
#   ./run.sh -p /path/to/project 42         # 处理指定项目的 Issue #42
#   ./run.sh -p /path/to/project 42 10      # 最多迭代 10 次
#   ./run.sh -a claude,codex 42              # 只启用 Claude 和 Codex
#   ./run.sh -a claude 42                    # 单 agent 模式
#   ./run.sh -a claude,opencode,codex 42     # 自定义 agent 顺序
#
# 要求:
#   - 项目目录必须是 git 仓库
#   - 项目目录必须有 GitHub remote (origin)
#
# 配置文件 (可选):
#   在项目根目录创建 .autoresearch/ 目录，可以放置:
#   - .autoresearch/agents/codex.md     自定义 Codex 指令
#   - .autoresearch/agents/claude.md    自定义 Claude 指令
#   - .autoresearch/agents/opencode.md  自定义 OpenCode 指令
#   - .autoresearch/program.md          自定义实现规则与约束

set -e
set -o pipefail

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

# 默认项目根目录 = 当前工作目录 (可通过 -p 参数覆盖)
PROJECT_ROOT="$(pwd)"

# ==================== 函数 ====================

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1" >&2
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
        log "硬门禁: 构建检查 ($build_cmd)..."
        echo "命令: $build_cmd" >> "$log_file"
        local build_out build_rc
        build_out=$($build_cmd 2>&1) ; build_rc=$?
        echo "$build_out" >> "$log_file"
        if [ $build_rc -eq 0 ]; then
            echo "结果: 通过" >> "$log_file"
            log "硬门禁: 构建通过"
        else
            echo "结果: 失败 (exit code: $build_rc)" >> "$log_file"
            local build_tail
            build_tail=$(echo "$build_out" | tail -20)
            errors="${errors}## 构建失败 ($build_cmd)\n\n\`\`\`\n${build_tail}\n\`\`\`\n\n"
            failed=1
            log "硬门禁: 构建失败"
        fi
    else
        echo "结果: 跳过 (无构建命令)" >> "$log_file"
        log "硬门禁: 无构建命令，跳过"
    fi
    echo "" >> "$log_file"

    # --- Lint 检查 ---
    local lint_cmd
    lint_cmd=$(get_lint_command)
    echo "--- Lint ---" >> "$log_file"
    if [ -n "$lint_cmd" ]; then
        log "硬门禁: Lint 检查 ($lint_cmd)..."
        echo "命令: $lint_cmd" >> "$log_file"
        local lint_out lint_rc
        lint_out=$($lint_cmd 2>&1) ; lint_rc=$?
        echo "$lint_out" >> "$log_file"
        if [ $lint_rc -eq 0 ]; then
            echo "结果: 通过" >> "$log_file"
            log "硬门禁: Lint 通过"
        else
            echo "结果: 失败 (exit code: $lint_rc)" >> "$log_file"
            local lint_tail
            lint_tail=$(echo "$lint_out" | tail -20)
            errors="${errors}## Lint 失败 ($lint_cmd)\n\n\`\`\`\n${lint_tail}\n\`\`\`\n\n"
            failed=1
            log "硬门禁: Lint 失败"
        fi
    else
        echo "结果: 跳过 (无 lint 命令)" >> "$log_file"
        log "硬门禁: 无 lint 命令，跳过"
    fi
    echo "" >> "$log_file"

    # --- 测试 ---
    local test_cmd
    test_cmd=$(get_test_command)
    echo "--- 测试 ---" >> "$log_file"
    if [ -n "$test_cmd" ]; then
        log "硬门禁: 测试 ($test_cmd)..."
        echo "命令: $test_cmd" >> "$log_file"
        local test_out test_rc
        test_out=$($test_cmd 2>&1) ; test_rc=$?
        echo "$test_out" >> "$log_file"
        if [ $test_rc -eq 0 ]; then
            echo "结果: 通过" >> "$log_file"
            log "硬门禁: 测试通过"
        else
            echo "结果: 失败 (exit code: $test_rc)" >> "$log_file"
            local test_tail
            test_tail=$(echo "$test_out" | tail -20)
            errors="${errors}## 测试失败 ($test_cmd)\n\n\`\`\`\n${test_tail}\n\`\`\`\n\n"
            failed=1
            log "硬门禁: 测试失败"
        fi
    else
        echo "结果: 跳过 (无测试命令)" >> "$log_file"
        log "硬门禁: 无测试命令，跳过"
    fi
    echo "" >> "$log_file"

    # --- 汇总 ---
    echo "=== 汇总 ===" >> "$log_file"
    if [ $failed -eq 0 ]; then
        echo "状态: 全部通过" >> "$log_file"
        log "硬门禁: 全部通过"
    else
        echo "状态: 失败" >> "$log_file"
        log "硬门禁: 未通过"
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
    # 仅匹配行首的错误模式，避免误判代码中讨论 "error handling" 等正常内容
    local pattern='^(Error|ERROR|Fatal|Panic|Exception)[: ]'
    pattern+='|^(timeout|rate.limit|authentication|unauthorized|API.key).*error'
    pattern+='|context.length.exceeded'
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
    grep -qE "$pattern" "$log_file" 2>/dev/null
}

# 检测 Agent 输出是否包含 API/网络级别的失败（区分于可恢复的内容错误）
has_api_failure() {
    local log_file="$1"
    # 这些模式表示 API 调用本身失败，而非代码内容问题
    local pattern='status.4[0-9][0-9]'
    pattern+='|status.5[0-9][0-9]'
    pattern+='|HTTP.4[0-9][0-9]'
    pattern+='|HTTP.5[0-9][0-9]'
    pattern+='|curl.*error'
    pattern+='|fetch.failed'
    pattern+='|request.failed'
    pattern+='|response.is.empty'
    pattern+='|no.response.received'
    grep -qE "$pattern" "$log_file" 2>/dev/null
}

# 检测 Agent 输出是否包含上下文溢出信号
detect_context_overflow() {
    local log_file="$1"

    if [ ! -f "$log_file" ]; then
        return 1
    fi

    local pattern='context.length.exceeded'
    pattern+='|context.window.exceeded'
    pattern+='|maximum.context.length'
    pattern+='|maximum.context.window'
    pattern+='|token.limit.exceeded'
    pattern+='|token.limit.reached'
    pattern+='|too.many.tokens'
    pattern+='|exceeds.the.maximum'
    pattern+='|exceeded.the.maximum.number.of.tokens'
    pattern+='|input.is.too.long'

    grep -qiE "$pattern" "$log_file" 2>/dev/null
}

# 处理上下文溢出：保存进度并自动交接
# 返回 0 表示溢出已处理（调用者应 continue），1 表示非溢出
handle_context_overflow() {
    local iteration="$1"
    local agent_name="$2"
    local log_file="$3"

    if ! detect_context_overflow "$log_file"; then
        return 1
    fi

    CONTEXT_RETRIES=$((CONTEXT_RETRIES + 1))

    if [ $CONTEXT_RETRIES -gt $MAX_CONTEXT_RETRIES ]; then
        log "上下文溢出已达最大重试次数 ($MAX_CONTEXT_RETRIES)，计为正常失败"
        return 1
    fi

    log "检测到上下文溢出，自动交接 (第 $CONTEXT_RETRIES/$MAX_CONTEXT_RETRIES 次)"

    # 保存进度到 progress.md
    append_to_progress "$iteration" "$agent_name" "$log_file" "N/A" "上下文溢出交接" ""

    # 设置下一次迭代的反馈
    PREVIOUS_FEEDBACK="上一次迭代因上下文溢出中断。请继续当前子任务的实现，参考 progress.md 中的进度记录。"

    # 不计入连续失败（这不是实现失败，是资源限制）
    CONSECUTIVE_ITERATION_FAILURES=0

    # 记录到日志
    echo "- 上下文溢出: 自动交接 (第 $CONTEXT_RETRIES/$MAX_CONTEXT_RETRIES 次)" >> "$WORK_DIR/log.md"

    CONTEXT_OVERFLOW=1

    return 0
}

run_with_retry() {
    local agent=$1
    local prompt="$2"
    local log_file="$3"
    local retry=0
    local success=0

    while [ $retry -lt $MAX_RETRIES ]; do
        retry=$((retry + 1))

        if [ $retry -gt 1 ]; then
            local delay
            delay=$(annealing_delay $retry)
            log "第 $retry/$MAX_RETRIES 次重试，等待 ${delay} 秒..."
            sleep $delay
        fi

        log "调用 $agent (尝试 $retry/$MAX_RETRIES)..."

        # Truncate log file before each attempt so we only capture this attempt's output
        : > "$log_file"

        local exit_code=1
        if [ "$agent" = "codex" ]; then
            codex exec --full-auto "$prompt" 2>&1 | tee "$log_file" || true
            exit_code=${PIPESTATUS[0]}
        elif [ "$agent" = "opencode" ]; then
            opencode run "$prompt" 2>&1 | tee "$log_file" || true
            exit_code=${PIPESTATUS[0]}
        else
            claude -p "$prompt" --dangerously-skip-permissions 2>&1 | tee "$log_file" || true
            exit_code=${PIPESTATUS[0]}
        fi

        # Check for context overflow first (non-retryable)
        if detect_context_overflow "$log_file"; then
            log "检测到上下文溢出，停止重试"
            break
        fi

        # Check for non-zero exit code from the agent
        if [ $exit_code -ne 0 ]; then
            log "Agent $agent 以非零退出码退出: $exit_code"
            log "$agent 第 $retry 次调用失败"
            continue
        fi

        # Check for fatal errors in output
        if has_fatal_error "$log_file"; then
            log "检测到致命错误，将重试"
            log "$agent 第 $retry 次调用失败"
            continue
        fi

        # Check for API failures in output
        if has_api_failure "$log_file"; then
            log "检测到 API 失败，将重试"
            log "$agent 第 $retry 次调用失败"
            continue
        fi

        # Check output quality: must have meaningful content
        local content_lines
        content_lines=$(grep -vE '^\s*$' "$log_file" | wc -l)
        if [ "$content_lines" -lt 5 ]; then
            log "警告: 输出内容过少 ($content_lines 行)，将重试"
            log "$agent 第 $retry 次调用失败"
            continue
        fi

        success=1
        break
    done

    if [ $success -eq 1 ]; then
        return 0
    else
        error "$agent 调用失败，已重试 $MAX_RETRIES 次"
        return 1
    fi
}

usage() {
    echo "用法: $0 [-p project_path] [-a agents] [-c] <issue_number> [max_iterations]"
    echo ""
    echo "通用自动化 Issue 处理工具，支持任意 Git + GitHub 项目。"
    echo ""
    echo "参数:"
    echo "  -p <path>        项目路径 (默认: 当前目录)"
    echo "  -a <agents>      逗号分隔的 agent 列表 (默认: claude,codex,opencode)"
    echo "                   第一个 agent 用于初始实现，后续 agent 按顺序轮流审核+修复"
    echo "  -c               继续模式，从上次中断的迭代继续"
    echo "  issue_number     GitHub Issue 编号"
    echo "  max_iterations   最大迭代次数 (默认: $DEFAULT_MAX_ITERATIONS)"
    echo ""
    echo "配置 (环境变量):"
    echo "  PASSING_SCORE=85              达标评分线 (百分制)"
    echo "  MAX_CONSECUTIVE_FAILURES=3    连续失败最大次数"
    echo "  MAX_CONTEXT_RETRIES=3         上下文溢出自动交接最大次数"
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
        error "未找到 git remote origin"
        exit 1
    fi

    if ! echo "$remote_url" | grep -qE 'github\.com|github\.baidu\.com'; then
        error "origin 不是 GitHub 仓库: $remote_url"
        exit 1
    fi

    local lang=$(detect_language)
    log "项目目录: $PROJECT_ROOT"
    log "Git remote: $remote_url"
    log "项目语言: $lang"
}

check_dependencies() {
    log "检查依赖..."

    local missing=0

    if ! command -v gh &> /dev/null; then
        error "gh (GitHub CLI) 未安装"
        missing=1
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
    local required=$(get_required_tools)
    if [ -n "$required" ] && ! command -v "$required" &> /dev/null; then
        error "$required 未安装 (项目语言: $(detect_language))"
        missing=1
    fi

    if [ $missing -eq 1 ]; then
        exit 1
    fi

    log "依赖检查通过"
}

get_issue_info() {
    local issue_number=$1

    log "获取 Issue #$issue_number 信息..."

    ISSUE_INFO=$(gh issue view $issue_number --json number,title,body,state,labels 2>&1)

    if [ $? -ne 0 ]; then
        error "无法获取 Issue #$issue_number: $ISSUE_INFO"
        exit 1
    fi

    ISSUE_TITLE=$(echo "$ISSUE_INFO" | jq -r '.title')
    ISSUE_BODY=$(echo "$ISSUE_INFO" | jq -r '.body')
    ISSUE_STATE=$(echo "$ISSUE_INFO" | jq -r '.state')
    ISSUE_LABELS=$(echo "$ISSUE_INFO" | jq -r '.labels[].name' | tr '\n' ',' | sed 's/,$//')

    if [ "$ISSUE_STATE" != "OPEN" ]; then
        error "Issue #$issue_number 状态为 ${ISSUE_STATE}，不是 OPEN"
        exit 1
    fi

    log "Issue 标题: $ISSUE_TITLE"
    log "Issue 标签: $ISSUE_LABELS"
}

setup_work_directory() {
    local issue_number=$1

    WORK_DIR="$PROJECT_ROOT/.autoresearch/workflows/issue-$issue_number"
    mkdir -p "$WORK_DIR"

    log "工作目录: $WORK_DIR"

    if [ $CONTINUE_MODE -eq 1 ]; then
        if [ ! -f "$WORK_DIR/log.md" ]; then
            error "未找到 Issue #$issue_number 的工作日志，无法继续"
            exit 1
        fi
        log "继续模式: 追加到已有日志"
        return
    fi

    cat > "$WORK_DIR/log.md" << EOF
# Issue #$issue_number 实现日志

## 基本信息
- Issue: #$issue_number - $ISSUE_TITLE
- 项目: $PROJECT_ROOT
- 语言: $(detect_language)
- 开始时间: $(date '+%Y-%m-%d %H:%M:%S')
- 标签: $ISSUE_LABELS

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
get_program_instructions() {
    local project_program="$PROJECT_ROOT/.autoresearch/program.md"
    if [ -f "$project_program" ]; then
        cat "$project_program"
        return
    fi

    local default_program="$SCRIPT_DIR/program.md"
    if [ -f "$default_program" ]; then
        cat "$default_program"
        return
    fi

    echo ""
}

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

# ==================== 子任务 (tasks.json) 相关函数 ====================

# 获取 tasks.json 文件路径
get_tasks_file() {
    echo "$WORK_DIR/tasks.json"
}

# 检查 tasks.json 是否存在且包含子任务
has_subtasks() {
    local tasks_file
    tasks_file=$(get_tasks_file)
    if [ ! -f "$tasks_file" ]; then
        return 1
    fi
    local count
    count=$(jq '.subtasks | length' "$tasks_file" 2>/dev/null)
    [ -n "$count" ] && [ "$count" -gt 0 ]
}

# 获取第一个 passes: false 的子任务信息（JSON 格式）
get_current_subtask() {
    local tasks_file
    tasks_file=$(get_tasks_file)
    if [ ! -f "$tasks_file" ]; then
        echo ""
        return
    fi
    jq '.subtasks | map(select(.passes == false)) | .[0]' "$tasks_file" 2>/dev/null
}

# 获取当前子任务的 ID
get_current_subtask_id() {
    local subtask
    subtask=$(get_current_subtask)
    if [ -z "$subtask" ] || [ "$subtask" = "null" ]; then
        echo ""
        return
    fi
    echo "$subtask" | jq -r '.id' 2>/dev/null
}

# 获取当前子任务的标题
get_current_subtask_title() {
    local subtask
    subtask=$(get_current_subtask)
    if [ -z "$subtask" ] || [ "$subtask" = "null" ]; then
        echo ""
        return
    fi
    echo "$subtask" | jq -r '.title' 2>/dev/null
}

# 标记指定子任务为 passes: true
mark_subtask_passed() {
    local subtask_id="$1"
    local tasks_file
    tasks_file=$(get_tasks_file)
    if [ ! -f "$tasks_file" ]; then
        return 1
    fi
    local tmp_file
    tmp_file=$(mktemp)
    jq --arg id "$subtask_id" '(.subtasks[] | select(.id == $id)).passes = true' "$tasks_file" > "$tmp_file" && mv "$tmp_file" "$tasks_file"
    log "子任务 $subtask_id 已标记为通过"
}

# 检查所有子任务是否都已通过
all_subtasks_passed() {
    local tasks_file
    tasks_file=$(get_tasks_file)
    if [ ! -f "$tasks_file" ]; then
        # 无 tasks.json 视为全部通过（兼容旧模式）
        return 0
    fi
    local unfinished
    unfinished=$(jq '[.subtasks[] | select(.passes == false)] | length' "$tasks_file" 2>/dev/null)
    [ "$unfinished" = "0" ]
}

# 获取子任务进度摘要（用于日志和 prompt 注入）
get_subtask_progress_summary() {
    local tasks_file
    tasks_file=$(get_tasks_file)
    if [ ! -f "$tasks_file" ]; then
        echo ""
        return
    fi

    local total passed current_id current_title
    total=$(jq '.subtasks | length' "$tasks_file" 2>/dev/null)
    passed=$(jq '[.subtasks[] | select(.passes == true)] | length' "$tasks_file" 2>/dev/null)
    current_id=$(get_current_subtask_id)
    current_title=$(get_current_subtask_title)

    echo "子任务进度: $passed/$total 已完成 | 当前子任务: $current_id - $current_title"
}

# 生成子任务注入文本（用于 prompt）
get_subtask_section() {
    local subtask
    subtask=$(get_current_subtask)
    if [ -z "$subtask" ] || [ "$subtask" = "null" ]; then
        echo ""
        return
    fi

    local id title desc criteria
    id=$(echo "$subtask" | jq -r '.id')
    title=$(echo "$subtask" | jq -r '.title')
    desc=$(echo "$subtask" | jq -r '.description')
    criteria=$(echo "$subtask" | jq -r '.acceptanceCriteria[]?' 2>/dev/null)

    local progress
    progress=$(get_subtask_progress_summary)

    cat << EOF

## 当前子任务

$progress

### 子任务详情

- **ID**: $id
- **标题**: $title
- **描述**: $desc
- **验收条件**:
$(echo "$criteria" | while read -r line; do echo "  - $line"; done)

请专注于实现此子任务，不要处理其他子任务。完成此子任务后等待审核。
EOF
}

# 生成规划阶段子任务注入文本（用于审核 prompt，包含所有子任务状态）
get_subtask_review_section() {
    local tasks_file
    tasks_file=$(get_tasks_file)
    if [ ! -f "$tasks_file" ]; then
        echo ""
        return
    fi

    local progress
    progress=$(get_subtask_progress_summary)

    local current_subtask
    current_subtask=$(get_current_subtask)
    if [ -z "$current_subtask" ] || [ "$current_subtask" = "null" ]; then
        echo "

## 子任务审核

$progress

所有子任务已完成审核。"
        return
    fi

    local id title desc criteria
    id=$(echo "$current_subtask" | jq -r '.id')
    title=$(echo "$current_subtask" | jq -r '.title')
    desc=$(echo "$current_subtask" | jq -r '.description')
    criteria=$(echo "$current_subtask" | jq -r '.acceptanceCriteria[]?' 2>/dev/null)

    cat << EOF

## 子任务审核

$progress

请审核当前子任务的实现：

- **ID**: $id
- **标题**: $title
- **描述**: $desc
- **验收条件**:
$(echo "$criteria" | while read -r line; do echo "  - $line"; done)

请针对此子任务的验收条件进行审核。
EOF
}

# ==================== 跨迭代经验日志 (progress.md) ====================

# 初始化 progress.md
init_progress() {
    local progress_file="$WORK_DIR/progress.md"
    cat > "$progress_file" << EOF
# Issue #$ISSUE_NUMBER 经验日志

## Codebase Patterns

> 此区域汇总最重要的可复用经验和模式。Agent 可在实现过程中更新此区域。

EOF
    log "初始化经验日志: $progress_file"
}

# 从 Agent 输出日志中提取 Learnings 部分
# 优先查找 ## Learnings 区块，否则截取前 30 行非空内容作为摘要
extract_learnings_from_log() {
    local log_file="$1"

    if [ ! -f "$log_file" ]; then
        echo ""
        return
    fi

    # 优先提取 ## Learnings 区块
    if grep -q "^## Learnings" "$log_file" 2>/dev/null; then
        sed -n '/^## Learnings/,/^## [^L]/{ /^## [^L]/!p; }' "$log_file" 2>/dev/null | head -50
        return
    fi

    # 回退：截取前 30 行非空内容作为摘要
    grep -vE '^\s*$' "$log_file" 2>/dev/null | head -30
}

# 追加迭代经验到 progress.md
append_to_progress() {
    local iteration="$1"
    local agent_name="$2"
    local log_file="$3"
    local score="${4:-N/A}"
    local entry_type="$5"  # "实现" 或 "审核+修复"
    local review_summary="$6"

    local progress_file="$WORK_DIR/progress.md"
    if [ ! -f "$progress_file" ]; then
        init_progress
    fi

    local date_str
    date_str=$(date '+%Y-%m-%d')

    # 从日志中提取 learnings
    local learnings
    learnings=$(extract_learnings_from_log "$log_file")

    # 限制 learnings 大小（约 1500 字符）
    local learnings_truncated
    learnings_truncated=$(echo "$learnings" | head -c 1500)
    if [ ${#learnings} -gt 1500 ]; then
        learnings_truncated="${learnings_truncated}

... (内容过长，已截断)"
    fi

    # 构建经验条目
    local entry="
## Iteration $iteration - $date_str

- **Agent**: $agent_name
- **类型**: $entry_type
- **评分**: $score/100
"

    # 如果有审核反馈摘要，追加
    if [ -n "$review_summary" ]; then
        # 截取审核反馈的前 800 字符
        local review_brief
        review_brief=$(echo "$review_summary" | head -c 800)
        entry="$entry
- **审核要点**:

${review_brief}
"
    fi

    # 追加 learnings
    if [ -n "$learnings_truncated" ]; then
        entry="$entry
- **经验与发现**:

${learnings_truncated}
"
    fi

    echo "$entry" >> "$progress_file"
    log "已追加迭代 $iteration 经验到 progress.md"
}

# 获取 progress.md 内容用于 prompt 注入
# 返回 ## Codebase Patterns 区 + 最近的迭代记录
get_progress_content() {
    local progress_file="$WORK_DIR/progress.md"
    if [ ! -f "$progress_file" ]; then
        echo ""
        return
    fi

    local content
    content=$(cat "$progress_file")

    # 安全限制：最大 5000 字符，避免过多 token 消耗
    local max_chars=5000
    local content_len
    content_len=$(echo "$content" | wc -c | tr -d ' ')

    if [ "$content_len" -le "$max_chars" ]; then
        echo "$content"
        return
    fi

    # 超长时：保留 ## Codebase Patterns 区 + 最后 3000 字符
    local patterns_section
    patterns_section=$(awk '/^## Codebase Patterns/,/^## [^C]/{ if (/^## [^C]/) next; print }' "$progress_file")

    local recent_entries
    recent_entries=$(tail -c 3000 "$progress_file")

    echo "$patterns_section

... (中间迭代记录已省略)

$recent_entries"
}

# 获取格式化的经验注入文本（用于 prompt）
get_progress_section() {
    local content
    content=$(get_progress_content)
    if [ -z "$content" ]; then
        echo ""
        return
    fi
    cat << EOF

## 跨迭代经验

以下是之前迭代中积累的经验和发现，请优先参考，避免重复踩坑：

$content
EOF
}

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

    local prompt="规划 GitHub Issue #$issue_number 的子任务拆分

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

---
$program_instructions

$agent_instructions
"

    local log_file="$WORK_DIR/planning.log"

    cd "$PROJECT_ROOT"
    if ! run_with_retry "$first_agent" "$prompt" "$log_file"; then
        log "规划阶段失败，将不拆分子任务（回退到原有模式）"
        return 1
    fi

    # 从 agent 输出中提取 tasks.json
    local tasks_file
    tasks_file=$(get_tasks_file)

    # 尝试提取 ```json ... ``` 代码块
    local json_content
    json_content=$(sed -n '/^```json$/,/^```$/{ /^```json$/d; /^```$/d; p; }' "$log_file" | head -200)

    if [ -n "$json_content" ]; then
        echo "$json_content" > "$tasks_file"

        # 验证 JSON 格式
        if jq '.' "$tasks_file" > /dev/null 2>&1; then
            local count
            count=$(jq '.subtasks | length' "$tasks_file")
            log "成功拆分为 $count 个子任务"

            # 记录到日志
            echo "" >> "$WORK_DIR/log.md"
            echo "### 规划阶段" >> "$WORK_DIR/log.md"
            echo "" >> "$WORK_DIR/log.md"
            echo "已拆分为 $count 个子任务，详见: [tasks.json](./tasks.json)" >> "$WORK_DIR/log.md"

            # 打印子任务列表
            log "子任务列表:"
            jq -r '.subtasks[] | "  \(.id): \(.title) (priority: \(.priority))"' "$tasks_file" | while read -r line; do
                log "$line"
            done

            return 0
        else
            log "提取的 JSON 格式无效，回退到原有模式"
            rm -f "$tasks_file"
            return 1
        fi
    fi

    log "未能从规划输出中提取 tasks.json，回退到原有模式"
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
        prompt="实现 GitHub Issue #$issue_number

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

    cd "$PROJECT_ROOT"
    if ! run_with_retry codex "$prompt" "$log_file"; then
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
        prompt="实现 GitHub Issue #$issue_number

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

    cd "$PROJECT_ROOT"
    if ! run_with_retry claude "$prompt" "$log_file"; then
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
        prompt="实现 GitHub Issue #$issue_number

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

    cd "$PROJECT_ROOT"
    if ! run_with_retry opencode "$prompt" "$log_file"; then
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

    cd "$PROJECT_ROOT"
    if ! run_with_retry opencode "$prompt" "$log_file"; then
        echo "0" > "$WORK_DIR/.last_score"
        return 1
    fi

    local score=0
    local review_result
    review_result=$(cat "$log_file")

    score=$(extract_score "$review_result")

    if [ -z "$score" ] || [ "$score" = "0" ]; then
        log "警告: 无法从审核结果中提取评分，默认为 50"
        score=50
    fi

    echo "- 审核评分 (OpenCode): $score/100" >> "$WORK_DIR/log.md"

    log "审核评分: $score/100"

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
        log "测试命令: $test_cmd"
        if $test_cmd 2>&1 | tee "$log_file"; then
            log "测试通过"
            echo "- 测试: ✅ 通过" >> "$WORK_DIR/log.md"
            return 0
        else
            log "测试失败"
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

    cd "$PROJECT_ROOT"
    if ! run_with_retry claude "$prompt" "$log_file"; then
        echo "0" > "$WORK_DIR/.last_score"
        return 1
    fi

    local score=0
    local review_result
    review_result=$(cat "$log_file")

    score=$(extract_score "$review_result")

    if [ -z "$score" ] || [ "$score" = "0" ]; then
        log "警告: 无法从审核结果中提取评分，默认为 50"
        score=50
    fi

    echo "- 审核评分 (Claude): $score/100" >> "$WORK_DIR/log.md"

    log "审核评分: $score/100"

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

    cd "$PROJECT_ROOT"
    if ! run_with_retry codex "$prompt" "$log_file"; then
        echo "0" > "$WORK_DIR/.last_score"
        return 1
    fi

    local score=0
    local review_result
    review_result=$(cat "$log_file")

    score=$(extract_score "$review_result")

    if [ -z "$score" ] || [ "$score" = "0" ]; then
        log "警告: 无法从审核结果中提取评分，默认为 50"
        score=50
    fi

    echo "- 审核评分 (Codex): $score/100" >> "$WORK_DIR/log.md"

    log "审核评分: $score/100"

    echo "$review_result"
    echo "$score" > "$WORK_DIR/.last_score"
    return 0
}

# ==================== 评分相关 ====================

extract_score() {
    local review_result="$1"
    local score=0
    local score_line

    # 格式1: 明确的百分制 X/100
    score_line=$(echo "$review_result" | grep -Eo '[0-9]+\.?[0-9]*(\s*/\s*100)' | head -1)
    if [ -n "$score_line" ]; then
        score=$(echo "$score_line" | grep -oE '[0-9]+\.?[0-9]*' | head -1)
        score=$(awk -v s="$score" 'BEGIN { printf "%.0f", s }')
        echo "$score"
        return
    fi

    # 格式2: **评分: X/100** 或 **Score: X/100**
    score_line=$(echo "$review_result" | grep -E '\*\*(评分|Score)[^*]*100' | head -1)
    if [ -n "$score_line" ]; then
        score=$(echo "$score_line" | grep -oE '[0-9]+\.?[0-9]*' | head -1)
        score=$(awk -v s="$score" 'BEGIN { printf "%.0f", s }')
        echo "$score"
        return
    fi

    # 格式3: 总分行
    score_line=$(echo "$review_result" | grep -E '(\*\*)?总分(\*\*)?\s*\|.*\*\*[0-9]' | head -1)
    if [ -z "$score_line" ]; then
        score_line=$(echo "$review_result" | grep -E '总分.*→' | head -1)
    fi
    if [ -n "$score_line" ]; then
        score=$(echo "$score_line" | grep -oE '[0-9]+\.?[0-9]*' | tail -1)
        if [ -n "$score" ]; then
            score=$(awk -v s="$score" 'BEGIN { printf "%.0f", s * 10 }')
            echo "$score"
            return
        fi
    fi

    # 格式4: X/10
    score_line=$(echo "$review_result" | grep -Eo '[0-9]+\.?[0-9]*(\s*/\s*10)' | head -1)
    if [ -n "$score_line" ]; then
        score=$(echo "$score_line" | grep -oE '[0-9]+\.?[0-9]*' | head -1)
        if [ -n "$score" ]; then
            score=$(awk -v s="$score" 'BEGIN { printf "%.0f", s * 10 }')
            echo "$score"
            return
        fi
    fi

    # 格式5: **评分: X** 或 **Score: X**
    score_line=$(echo "$review_result" | grep -E '\*\*(评分|Score)' | head -1)
    if [ -n "$score_line" ]; then
        score=$(echo "$score_line" | grep -oE '[0-9]+\.?[0-9]*' | head -1)
        if [ -n "$score" ]; then
            if awk -v s="$score" 'BEGIN { exit (s <= 10) ? 0 : 1 }'; then
                score=$(awk -v s="$score" 'BEGIN { printf "%.0f", s * 10 }')
            fi
            echo "$score"
            return
        fi
    fi

    # 格式6: "评分: X" 或 "Score: X"
    score_line=$(echo "$review_result" | grep -E '(评分|Score)\s*:' | grep -v '各维度\|维度' | head -1)
    if [ -n "$score_line" ]; then
        score=$(echo "$score_line" | grep -oE '[0-9]+\.?[0-9]*' | head -1)
        if [ -n "$score" ]; then
            if awk -v s="$score" 'BEGIN { exit (s <= 10) ? 0 : 1 }'; then
                score=$(awk -v s="$score" 'BEGIN { printf "%.0f", s * 10 }')
            fi
            echo "$score"
            return
        fi
    fi

    echo "0"
}

check_score_passed() {
    local score=$1
    local passing=$PASSING_SCORE
    awk -v score="$score" -v passing="$passing" 'BEGIN { exit (score >= passing) ? 0 : 1 }'
}

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
        error "未找到任何迭代记录，无法继续 (last_iter='$last_iter')"
        exit 1
    fi

    log "上次运行到迭代 ${last_iter}，从迭代 $((last_iter + 1)) 继续"

    # 恢复迭代计数
    ITERATION=$last_iter

    # 恢复最终评分
    if [ -f "$WORK_DIR/.last_score" ]; then
        FINAL_SCORE=$(cat "$WORK_DIR/.last_score" | tr -cd '0-9')
        [ -z "$FINAL_SCORE" ] && FINAL_SCORE=0
        log "上次评分: $FINAL_SCORE/100"
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
        log "已切换到分支: $branch"
    else
        error "未找到分支 ${branch}，无法继续"
        exit 1
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
        log "$progress"
    fi

    echo "" >> "$WORK_DIR/log.md"
}

# ==================== 参数解析 ====================

CONTINUE_MODE=0
AGENT_LIST=""

while getopts "p:a:c" opt; do
    case $opt in
        p) PROJECT_ROOT="$(cd "$OPTARG" && pwd)" ;;
        a) AGENT_LIST="$OPTARG" ;;
        c) CONTINUE_MODE=1 ;;
        *) usage ;;
    esac
done
shift $((OPTIND - 1))

if [ -z "$1" ]; then
    usage
fi

ISSUE_NUMBER=$1
MAX_ITERATIONS=${2:-$DEFAULT_MAX_ITERATIONS}

log "=========================================="
log "autoresearch - 自动化 Issue 处理"
log "=========================================="
log "Issue: #$ISSUE_NUMBER"
log "项目: $PROJECT_ROOT"
if [ $CONTINUE_MODE -eq 1 ]; then
    log "模式: 继续上次运行"
else
    log "模式: 全新运行"
fi
log "最大迭代次数: $MAX_ITERATIONS"

# 构建 AGENT_NAMES 数组（必须在 check_dependencies 和日志输出之前）
if ! parse_agent_list "$AGENT_LIST"; then
    error "$AGENT_LIST_ERROR"
    exit 1
fi

log "Agent 列表: ${AGENT_NAMES[*]} (初始实现: ${AGENT_NAMES[0]})"

# 检查项目环境
check_project

# 检查依赖
check_dependencies

# 获取 Issue 信息
get_issue_info "$ISSUE_NUMBER"

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

    # 防御：确保 ITERATION 是有效数字
    if [ -z "$ITERATION" ] || ! [ "$ITERATION" -gt 0 ] 2>/dev/null; then
        error "无法恢复迭代状态，ITERATION=$ITERATION"
        exit 1
    fi

    # 不指定轮数时，总迭代数=默认值；指定时，总迭代数=已有+指定轮数
    if [ -z "$2" ]; then
        MAX_ITERATIONS=$DEFAULT_MAX_ITERATIONS
        remaining=$((MAX_ITERATIONS - ITERATION))
        log "继续运行: 已完成 $ITERATION 轮，再跑 $remaining 轮 (总计 $MAX_ITERATIONS)"
    else
        MAX_ITERATIONS=$((ITERATION + $2))
        log "继续运行: 已完成 $ITERATION 轮，再跑 $2 轮 (总计 $MAX_ITERATIONS)"
    fi
fi

# ==================== 规划阶段 ====================

# 非继续模式时执行规划阶段
if [ $CONTINUE_MODE -eq 0 ]; then
    log ""
    log "=========================================="
    log "规划阶段: 拆分子任务"
    log "=========================================="

    if ! run_planning_phase "$ISSUE_NUMBER"; then
        log "规划阶段未生成子任务，将使用原有模式（一次性实现整个 Issue）"
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
    if ! $review_func "$ISSUE_NUMBER" "$ITERATION"; then
        local review_log="$WORK_DIR/iteration-$ITERATION-${agent_name}-review.log"
        if handle_context_overflow "$ITERATION" "$agent_name" "$review_log"; then
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
        log "审核通过！评分: $SCORE/100 (达标线: $PASSING_SCORE)"
        CONSECUTIVE_ITERATION_FAILURES=0
        PASSED=1
        FINAL_REVIEW_REPORT=$(cat "$REVIEW_LOG_FILE" 2>/dev/null || echo "")

        # 如果有子任务，标记当前子任务为通过
        if has_subtasks; then
            local current_subtask_id
            current_subtask_id=$(get_current_subtask_id)
            if [ -n "$current_subtask_id" ]; then
                mark_subtask_passed "$current_subtask_id"
                log "子任务 $current_subtask_id 审核通过"

                # 检查是否还有未通过的子任务
                if all_subtasks_passed; then
                    log "所有子任务已通过！"
                    ALL_SUBTASKS_DONE=1
                else
                    # 还有子任务，重置状态准备下一个
                    local progress
                    progress=$(get_subtask_progress_summary)
                    log "$progress"
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

    log "评分未达标 ($SCORE/$PASSING_SCORE)，$agent_name 根据反馈修复..."

    REVIEW_FEEDBACK=$(cat "$REVIEW_LOG_FILE")
    if ! $impl_func "$ISSUE_NUMBER" "$ITERATION" "$REVIEW_FEEDBACK"; then
        local impl_log="$WORK_DIR/iteration-$ITERATION-${agent_name}.log"
        if handle_context_overflow "$ITERATION" "$agent_name" "$impl_log"; then
            return
        fi
        log "$agent_name 修复失败，跳到下一次迭代"
        PREVIOUS_FEEDBACK="$REVIEW_FEEDBACK"
        ITERATION_FAILED=1
        return
    fi

    # 硬门禁检查：修复后先跑 build → lint → test
    if ! run_hard_gate_checks "$ITERATION"; then
        log "硬门禁检查未通过，跳过本轮审核"
        HARD_GATE_FAILED=1
        local gate_log="$WORK_DIR/hard-gate-$ITERATION.log"
        PREVIOUS_FEEDBACK="硬门禁检查未通过，请根据以下错误修复代码：\n\n$(cat "$gate_log" 2>/dev/null || echo "详见 hard-gate-$ITERATION.log")"
        ITERATION_FAILED=1
        return
    fi
    log "硬门禁检查通过"
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

    log ""
    log "=========================================="
    log "迭代 $ITERATION/$MAX_ITERATIONS"
    if has_subtasks; then
        subtask_progress=$(get_subtask_progress_summary)
        log "$subtask_progress"
    fi
    if [ $ITERATION -eq 1 ] && ! has_subtasks; then
        log "本轮: ${AGENT_NAMES[0]} 初始实现"
    else
        agent_idx=$(get_review_agent $ITERATION)
        log "本轮: ${AGENT_NAMES[$agent_idx]} 审核 + 修复"
    fi
    log "=========================================="

    # ---- 无子任务模式：迭代 1 第一个 agent 初始实现 ----
    if [ $ITERATION -eq 1 ] && ! has_subtasks; then
        HARD_GATE_FAILED=0
        first_agent="${AGENT_NAMES[0]}"
        first_impl_func="run_${first_agent}"
        if ! $first_impl_func "$ISSUE_NUMBER" "$ITERATION" ""; then
            impl_log="$WORK_DIR/iteration-$ITERATION-${first_agent}.log"
            if handle_context_overflow "$ITERATION" "$first_agent" "$impl_log"; then
                : # 上下文溢出已自动交接
            else
                log "$first_agent 初始实现失败，跳到下一次迭代"
                ITERATION_FAILED=1
            fi
        else
            # 硬门禁检查：build → lint → test
            if ! run_hard_gate_checks "$ITERATION"; then
                log "硬门禁检查未通过，跳过本轮审核"
                HARD_GATE_FAILED=1
                local gate_log="$WORK_DIR/hard-gate-$ITERATION.log"
                PREVIOUS_FEEDBACK="硬门禁检查未通过，请根据以下错误修复代码：\n\n$(cat "$gate_log" 2>/dev/null || echo "详见 hard-gate-$ITERATION.log")"
                ITERATION_FAILED=1
            else
                log "硬门禁检查通过"
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
        if ! $first_impl_func "$ISSUE_NUMBER" "$ITERATION" ""; then
            impl_log="$WORK_DIR/iteration-$ITERATION-${first_agent}.log"
            if handle_context_overflow "$ITERATION" "$first_agent" "$impl_log"; then
                : # 上下文溢出已自动交接
            else
                log "$first_agent 初始实现失败，跳到下一次迭代"
                ITERATION_FAILED=1
            fi
        else
            # 硬门禁检查：build → lint → test
            if ! run_hard_gate_checks "$ITERATION"; then
                log "硬门禁检查未通过，跳过本轮审核"
                HARD_GATE_FAILED=1
                local gate_log="$WORK_DIR/hard-gate-$ITERATION.log"
                PREVIOUS_FEEDBACK="硬门禁检查未通过，请根据以下错误修复代码：\n\n$(cat "$gate_log" 2>/dev/null || echo "详见 hard-gate-$ITERATION.log")"
                ITERATION_FAILED=1
            else
                log "硬门禁检查通过"
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

    # 上下文溢出时跳过正常处理（进度已由 handle_context_overflow 保存）
    if [ $CONTEXT_OVERFLOW -eq 1 ]; then
        continue
    fi

    # 追加经验到 progress.md
    review_log="$WORK_DIR/iteration-$ITERATION-${agent_name}-review.log"
    review_feedback_brief=""
    if [ -f "$review_log" ]; then
        review_feedback_brief=$(cat "$review_log" | head -c 800)
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

    if [ $CONTEXT_OVERFLOW -eq 0 ]; then
        if [ $ITERATION_FAILED -eq 1 ] && [ $HARD_GATE_FAILED -eq 0 ]; then
            CONSECUTIVE_ITERATION_FAILURES=$((CONSECUTIVE_ITERATION_FAILURES + 1))
        elif [ $HARD_GATE_FAILED -eq 0 ]; then
            CONSECUTIVE_ITERATION_FAILURES=0
        fi
    fi

    if [ $CONSECUTIVE_ITERATION_FAILURES -ge $MAX_CONSECUTIVE_FAILURES ]; then
        error "连续 $CONSECUTIVE_ITERATION_FAILURES 次迭代失败，停止运行"
        record_final_result "$ISSUE_NUMBER" "agent_failed" "$ITERATION" "$FINAL_SCORE"
        exit 1
    fi
done

# ==================== 最终处理 ====================

if check_score_passed "$FINAL_SCORE"; then
    record_final_result "$ISSUE_NUMBER" "completed" "$ITERATION" "$FINAL_SCORE"

    echo ""
    log "=========================================="
    log "处理完成！"
    log "=========================================="
    log "分支: $BRANCH_NAME"
    log "评分: $FINAL_SCORE/100"
    log "迭代次数: $ITERATION"

    # 自动提交 PR 并合并
    log ""
    log "=========================================="
    log "自动提交 PR 并合并..."
    log "=========================================="

    cd "$PROJECT_ROOT"

    # 提交所有更改
    log "提交更改..."
    git add -A

    # 构建 commit message：包含审核报告
    COMMIT_MSG="feat: implement issue #$ISSUE_NUMBER - $ISSUE_TITLE

$FINAL_REVIEW_REPORT

Closes #$ISSUE_NUMBER"

    git commit -m "$COMMIT_MSG" 2>/dev/null || log "没有需要提交的更改"

    # 推送分支
    log "推送分支 $BRANCH_NAME..."
    git push -u origin "$BRANCH_NAME"

    # 创建 PR
    log "创建 Pull Request..."

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

    PR_URL=$(gh pr create --title "feat: $ISSUE_TITLE (#$ISSUE_NUMBER)" --body "$(cat <<EOF
## Summary
- Implements #$ISSUE_NUMBER
- Score: $FINAL_SCORE/100
- Iterations: $ITERATION
$subtask_summary
## Test plan
- [x] All tests pass
- [x] Code review completed with score >= $PASSING_SCORE

Closes #$ISSUE_NUMBER
EOF
)" 2>&1)

    if echo "$PR_URL" | grep -q "https://github.com"; then
        PR_NUMBER=$(echo "$PR_URL" | grep -oE '[0-9]+$')
        log "PR 已创建: $PR_URL"

        # 合并 PR
        log "合并 PR #$PR_NUMBER..."
        gh pr merge "$PR_NUMBER" --merge --delete-branch

        # 添加评论到 Issue（包含最终审核报告）
        log "添加评论到 Issue #$ISSUE_NUMBER..."
        FINAL_REVIEW_SECTION=""
        if [ -n "$FINAL_REVIEW_REPORT" ]; then
            FINAL_REVIEW_SECTION="
---

$FINAL_REVIEW_REPORT
"
        fi
        gh issue comment "$ISSUE_NUMBER" --body "$(cat <<EOF
## 自动处理完成

- **PR**: $PR_URL (已合并)
- **评分**: $FINAL_SCORE/100
- **迭代次数**: $ITERATION
- **实现方式**: autoresearch 多 agent 迭代 (${AGENT_NAMES[@]})
${FINAL_REVIEW_SECTION}
该 Issue 已由 autoresearch 自动实现、审核并合并。
EOF
)" 2>/dev/null || log "警告: 添加评论失败"

        # 关闭 Issue
        log "关闭 Issue #$ISSUE_NUMBER..."
        gh issue close "$ISSUE_NUMBER" --reason completed 2>/dev/null || log "警告: 关闭 Issue 失败 (可能已通过 PR 自动关闭)"

        log ""
        log "=========================================="
        log "完成！Issue #$ISSUE_NUMBER 已自动处理"
        log "=========================================="
        log "PR: $PR_URL"
        log "状态: 已合并并关闭"
    else
        log "警告: PR 创建失败或已存在"
        log "$PR_URL"
    fi

    exit 0
fi

# 达到最大迭代次数
log ""
log "=========================================="
log "达到最大迭代次数，仍未通过审核"
log "=========================================="
log "最终评分: $FINAL_SCORE/100"
log "请人工介入处理"

record_final_result "$ISSUE_NUMBER" "blocked" "$ITERATION" "$FINAL_SCORE"

exit 1
