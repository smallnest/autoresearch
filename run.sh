#!/bin/bash
# autoresearch/run.sh - 自动化处理 GitHub Issue
#
# 通用版本 - 可处理任意 Git + GitHub 项目
#
# 用法:
#   ./run.sh [-p project_path] <issue_number> [max_iterations]
#
# 示例:
#   ./run.sh 42                              # 处理当前目录项目的 Issue #42
#   ./run.sh -p /path/to/project 42         # 处理指定项目的 Issue #42
#   ./run.sh -p /path/to/project 42 10      # 最多迭代 10 次
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

# 脚本所在目录（用于查找默认 agents 配置和 program.md）
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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
    echo "用法: $0 [-p project_path] [-c] <issue_number> [max_iterations]"
    echo ""
    echo "通用自动化 Issue 处理工具，支持任意 Git + GitHub 项目。"
    echo ""
    echo "参数:"
    echo "  -p <path>        项目路径 (默认: 当前目录)"
    echo "  -c               继续模式，从上次中断的迭代继续"
    echo "  issue_number     GitHub Issue 编号"
    echo "  max_iterations   最大迭代次数 (默认: $DEFAULT_MAX_ITERATIONS)"
    echo ""
    echo "配置 (环境变量):"
    echo "  PASSING_SCORE=85              达标评分线 (百分制)"
    echo "  MAX_CONSECUTIVE_FAILURES=3    连续失败最大次数"
    echo ""
    echo "自定义配置文件 (放在项目目录 .autoresearch/ 下):"
    echo "  agents/codex.md              Codex 指令"
    echo "  agents/claude.md             Claude 指令"
    echo "  agents/opencode.md           OpenCode 指令"
    echo "  program.md                   实现规则与约束"
    echo ""
    echo "示例:"
    echo "  $0 42                                  # 处理当前项目的 Issue #42"
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

    if ! command -v claude &> /dev/null; then
        error "claude (Claude Code CLI) 未安装"
        missing=1
    fi

    if ! command -v codex &> /dev/null; then
        error "codex (OpenAI Codex CLI) 未安装"
        missing=1
    fi

    if ! command -v opencode &> /dev/null; then
        error "opencode CLI 未安装"
        missing=1
    fi

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
        error "Issue #$issue_number 状态为 $ISSUE_STATE，不是 OPEN"
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

    local prompt
    if [ -z "$previous_feedback" ]; then
        prompt="实现 GitHub Issue #$issue_number

项目路径: $PROJECT_ROOT
项目语言: $(detect_language)
Issue 标题: $ISSUE_TITLE
Issue 内容: $ISSUE_BODY

迭代次数: $iteration

---
请按以下步骤执行:

## 第一步：制定计划
分析 Issue 需求，制定实现计划，拆解为具体的 tasks/todos，输出任务清单。

## 第二步：逐步实现
按照任务清单逐步实现，每完成一个任务标记为已完成。

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

---
请按以下步骤执行:

## 第一步：制定计划
分析审核反馈，制定修复计划，拆解为具体的 tasks/todos，输出任务清单。

## 第二步：逐步实现
按照任务清单逐步修复，每完成一个任务标记为已完成。

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

    local prompt
    if [ -z "$previous_feedback" ]; then
        prompt="实现 GitHub Issue #$issue_number

项目路径: $PROJECT_ROOT
项目语言: $(detect_language)
Issue 标题: $ISSUE_TITLE
Issue 内容: $ISSUE_BODY

迭代次数: $iteration

---
请按以下步骤执行:

## 第一步：制定计划
分析 Issue 需求，制定实现计划，拆解为具体的 tasks/todos，输出任务清单。

## 第二步：逐步实现
按照任务清单逐步实现，每完成一个任务标记为已完成。

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

---
请按以下步骤执行:

## 第一步：制定计划
分析审核反馈，制定修复计划，拆解为具体的 tasks/todos，输出任务清单。

## 第二步：逐步实现
按照任务清单逐步修复，每完成一个任务标记为已完成。

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

    local prompt
    if [ -z "$previous_feedback" ]; then
        prompt="实现 GitHub Issue #$issue_number

项目路径: $PROJECT_ROOT
项目语言: $(detect_language)
Issue 标题: $ISSUE_TITLE
Issue 内容: $ISSUE_BODY

迭代次数: $iteration

---
请按以下步骤执行:

## 第一步：制定计划
分析 Issue 需求，制定实现计划，拆解为具体的 tasks/todos，输出任务清单。

## 第二步：逐步实现
按照任务清单逐步实现，每完成一个任务标记为已完成。

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

---
请按以下步骤执行:

## 第一步：制定计划
分析审核反馈，制定修复计划，拆解为具体的 tasks/todos，输出任务清单。

## 第二步：逐步实现
按照任务清单逐步修复，每完成一个任务标记为已完成。

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

    local prompt="审核 Issue #$issue_number 的实现

项目路径: $PROJECT_ROOT
项目语言: $(detect_language)
Issue 标题: $ISSUE_TITLE

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

    local prompt="审核 Issue #$issue_number 的实现

项目路径: $PROJECT_ROOT
项目语言: $(detect_language)
Issue 标题: $ISSUE_TITLE

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

    local prompt="审核 Issue #$issue_number 的实现

项目路径: $PROJECT_ROOT
项目语言: $(detect_language)
Issue 标题: $ISSUE_TITLE

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

    log "上次运行到迭代 $last_iter，从迭代 $((last_iter + 1)) 继续"

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
    local last_review_log=""
    for agent_name in "${AGENT_NAMES[@]}"; do
        local f="$WORK_DIR/iteration-${last_iter}-${agent_name}-review.log"
        if [ -f "$f" ]; then
            last_review_log="$f"
        fi
    done

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
        error "未找到分支 $branch，无法继续"
        exit 1
    fi

    # 追加继续标记到日志
    echo "" >> "$WORK_DIR/log.md"
    echo "---" >> "$WORK_DIR/log.md"
    echo "" >> "$WORK_DIR/log.md"
    echo "## 继续运行 (从迭代 $((last_iter + 1)) 继续)" >> "$WORK_DIR/log.md"
    echo "- 继续时间: $(date '+%Y-%m-%d %H:%M:%S')" >> "$WORK_DIR/log.md"
    echo "- 上次评分: $FINAL_SCORE/100" >> "$WORK_DIR/log.md"
    echo "" >> "$WORK_DIR/log.md"
}

# ==================== 参数解析 ====================

CONTINUE_MODE=0

while getopts "p:c" opt; do
    case $opt in
        p) PROJECT_ROOT="$(cd "$OPTARG" && pwd)" ;;
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

AGENT_NAMES=("claude" "codex" "opencode")
ITERATION=0
PREVIOUS_FEEDBACK=""
FINAL_SCORE=0
CONSECUTIVE_ITERATION_FAILURES=0

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
        local remaining=$((MAX_ITERATIONS - ITERATION))
        log "继续运行: 已完成 $ITERATION 轮，再跑 $remaining 轮 (总计 $MAX_ITERATIONS)"
    else
        MAX_ITERATIONS=$((ITERATION + $2))
        log "继续运行: 已完成 $ITERATION 轮，再跑 $2 轮 (总计 $MAX_ITERATIONS)"
    fi
fi

# ==================== 迭代循环 ====================

# Agent 列表: 0=claude, 1=codex, 2=opencode
# 迭代 1:  Claude 初始实现
# 迭代 2+: 三 agent 轮流审核 + 修复

get_review_agent() {
    local iter=$1
    echo $(( (iter - 1) % 3 ))  # iter=2 → 1=codex, iter=3 → 2=opencode, iter=4 → 0=claude
}

run_review_and_fix() {
    local agent_idx=$1
    local agent_name="${AGENT_NAMES[$agent_idx]}"
    local review_func="run_${agent_name}_review"
    local impl_func="run_${agent_name}"

    # 审核
    if ! $review_func "$ISSUE_NUMBER" "$ITERATION"; then
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
        return
    fi

    log "评分未达标 ($SCORE/$PASSING_SCORE)，$agent_name 根据反馈修复..."

    REVIEW_FEEDBACK=$(cat "$REVIEW_LOG_FILE")
    if ! $impl_func "$ISSUE_NUMBER" "$ITERATION" "$REVIEW_FEEDBACK"; then
        log "$agent_name 修复失败，跳到下一次迭代"
        PREVIOUS_FEEDBACK="$REVIEW_FEEDBACK"
        ITERATION_FAILED=1
        return
    fi

    if ! run_tests "$ITERATION"; then
        PREVIOUS_FEEDBACK="测试失败，请检查测试输出并修复问题。"
    else
        PREVIOUS_FEEDBACK=""
    fi
}

while [ $ITERATION -lt $MAX_ITERATIONS ]; do
    ITERATION=$((ITERATION + 1))
    PASSED=0
    ITERATION_FAILED=0

    log ""
    log "=========================================="
    log "迭代 $ITERATION/$MAX_ITERATIONS"
    if [ $ITERATION -eq 1 ]; then
        log "本轮: Claude 初始实现"
    else
        agent_idx=$(get_review_agent $ITERATION)
        log "本轮: ${AGENT_NAMES[$agent_idx]} 审核 + 修复"
    fi
    log "=========================================="

    # ---- 迭代 1: Claude 初始实现 ----
    if [ $ITERATION -eq 1 ]; then
        if ! run_claude "$ISSUE_NUMBER" "$ITERATION" ""; then
            log "Claude 初始实现失败，跳到下一次迭代"
            ITERATION_FAILED=1
        else
            if ! run_tests "$ITERATION"; then
                log "初始实现测试失败，继续下一轮审核修复"
                PREVIOUS_FEEDBACK="测试失败，请检查测试输出并修复问题。"
            fi
            PREVIOUS_FEEDBACK="初始实现完成，请审核代码质量并给出评分。如果有问题请直接修复。"
        fi

        if [ $ITERATION_FAILED -eq 1 ]; then
            CONSECUTIVE_ITERATION_FAILURES=$((CONSECUTIVE_ITERATION_FAILURES + 1))
        else
            CONSECUTIVE_ITERATION_FAILURES=0
        fi
        continue
    fi

    # ---- 迭代 >=2: 三 agent 轮流审核 + 修复 ----
    agent_idx=$(get_review_agent $ITERATION)
    run_review_and_fix $agent_idx

    if [ $PASSED -eq 1 ]; then
        break
    fi

    if [ $ITERATION_FAILED -eq 1 ]; then
        CONSECUTIVE_ITERATION_FAILURES=$((CONSECUTIVE_ITERATION_FAILURES + 1))
    else
        CONSECUTIVE_ITERATION_FAILURES=0
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
    PR_URL=$(gh pr create --title "feat: $ISSUE_TITLE (#$ISSUE_NUMBER)" --body "$(cat <<EOF
## Summary
- Implements #$ISSUE_NUMBER
- Score: $FINAL_SCORE/100
- Iterations: $ITERATION

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
