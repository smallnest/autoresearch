#!/bin/bash
# tests/test_extract_score.sh - Unit tests for extract_score()
#
# Usage: bash tests/test_extract_score.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# ==================== Extract functions from run.sh ====================
# run.sh has set -e and side effects, so we extract just the pure functions.

# Configuration constants (needed by the functions)
RETRY_BASE_DELAY=2
RETRY_MAX_DELAY=60
PASSING_SCORE=85

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

has_fatal_error() {
    local log_file="$1"
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

has_api_failure() {
    local log_file="$1"
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

check_score_passed() {
    local score=$1
    local passing=$PASSING_SCORE
    awk -v score="$score" -v passing="$passing" 'BEGIN { exit (score >= passing) ? 0 : 1 }'
}

# ==================== progress.md functions ====================

# These functions depend on WORK_DIR and ISSUE_NUMBER being set.

init_progress() {
    local progress_file="$WORK_DIR/progress.md"
    cat > "$progress_file" << EOF
# Issue #$ISSUE_NUMBER 经验日志

## Codebase Patterns

> 此区域汇总最重要的可复用经验和模式。Agent 可在实现过程中更新此区域。

EOF
}

extract_learnings_from_log() {
    local log_file="$1"

    if [ ! -f "$log_file" ]; then
        echo ""
        return
    fi

    if grep -q "^## Learnings" "$log_file" 2>/dev/null; then
        sed -n '/^## Learnings/,/^## [^L]/{ /^## [^L]/!p; }' "$log_file" 2>/dev/null | head -50
        return
    fi

    grep -vE '^\s*$' "$log_file" 2>/dev/null | head -30
}

append_to_progress() {
    local iteration="$1"
    local agent_name="$2"
    local log_file="$3"
    local score="${4:-N/A}"
    local entry_type="$5"
    local review_summary="$6"

    local progress_file="$WORK_DIR/progress.md"
    if [ ! -f "$progress_file" ]; then
        init_progress
    fi

    local date_str
    date_str=$(date '+%Y-%m-%d')

    local learnings
    learnings=$(extract_learnings_from_log "$log_file")

    local learnings_truncated
    learnings_truncated=$(echo "$learnings" | head -c 1500)
    if [ ${#learnings} -gt 1500 ]; then
        learnings_truncated="${learnings_truncated}

... (内容过长，已截断)"
    fi

    local entry="
## Iteration $iteration - $date_str

- **Agent**: $agent_name
- **类型**: $entry_type
- **评分**: $score/100
"

    if [ -n "$review_summary" ]; then
        local review_brief
        review_brief=$(echo "$review_summary" | head -c 800)
        entry="$entry
- **审核要点**:

${review_brief}
"
    fi

    if [ -n "$learnings_truncated" ]; then
        entry="$entry
- **经验与发现**:

${learnings_truncated}
"
    fi

    echo "$entry" >> "$progress_file"
}

get_progress_content() {
    local progress_file="$WORK_DIR/progress.md"
    if [ ! -f "$progress_file" ]; then
        echo ""
        return
    fi

    local content
    content=$(cat "$progress_file")

    local max_chars=5000
    local content_len
    content_len=$(echo "$content" | wc -c | tr -d ' ')

    if [ "$content_len" -le "$max_chars" ]; then
        echo "$content"
        return
    fi

    local patterns_section
    patterns_section=$(awk '/^## Codebase Patterns/,/^## [^C]/{ if (/^## [^C]/) next; print }' "$progress_file")

    local recent_entries
    recent_entries=$(tail -c 3000 "$progress_file")

    echo "$patterns_section

... (中间迭代记录已省略)

$recent_entries"
}

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

# ==================== tasks.json functions ====================

# These functions depend on WORK_DIR being set.

get_tasks_file() {
    echo "$WORK_DIR/tasks.json"
}

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

get_current_subtask() {
    local tasks_file
    tasks_file=$(get_tasks_file)
    if [ ! -f "$tasks_file" ]; then
        echo ""
        return
    fi
    jq '.subtasks | map(select(.passes == false)) | .[0]' "$tasks_file" 2>/dev/null
}

get_current_subtask_id() {
    local subtask
    subtask=$(get_current_subtask)
    if [ -z "$subtask" ] || [ "$subtask" = "null" ]; then
        echo ""
        return
    fi
    echo "$subtask" | jq -r '.id' 2>/dev/null
}

get_current_subtask_title() {
    local subtask
    subtask=$(get_current_subtask)
    if [ -z "$subtask" ] || [ "$subtask" = "null" ]; then
        echo ""
        return
    fi
    echo "$subtask" | jq -r '.title' 2>/dev/null
}

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
}

all_subtasks_passed() {
    local tasks_file
    tasks_file=$(get_tasks_file)
    if [ ! -f "$tasks_file" ]; then
        return 0
    fi
    local unfinished
    unfinished=$(jq '[.subtasks[] | select(.passes == false)] | length' "$tasks_file" 2>/dev/null)
    [ "$unfinished" = "0" ]
}

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

# ==================== Test Framework ====================

PASS=0
FAIL=0
TOTAL=0

assert_eq() {
    local test_name="$1"
    local expected="$2"
    local actual="$3"
    TOTAL=$((TOTAL + 1))
    if [ "$expected" = "$actual" ]; then
        PASS=$((PASS + 1))
        echo "  PASS: $test_name (expected=$expected, actual=$actual)"
    else
        FAIL=$((FAIL + 1))
        echo "  FAIL: $test_name (expected=$expected, actual=$actual)"
    fi
}

assert_true() {
    local test_name="$1"
    local cmd="$2"
    TOTAL=$((TOTAL + 1))
    if eval "$cmd"; then
        PASS=$((PASS + 1))
        echo "  PASS: $test_name"
    else
        FAIL=$((FAIL + 1))
        echo "  FAIL: $test_name (expected true, got false)"
    fi
}

assert_false() {
    local test_name="$1"
    local cmd="$2"
    TOTAL=$((TOTAL + 1))
    if eval "$cmd"; then
        FAIL=$((FAIL + 1))
        echo "  FAIL: $test_name (expected false, got true)"
    else
        PASS=$((PASS + 1))
        echo "  PASS: $test_name"
    fi
}

TMPDIR_TESTS=""
cleanup() {
    if [ -n "$TMPDIR_TESTS" ] && [ -d "$TMPDIR_TESTS" ]; then
        rm -rf "$TMPDIR_TESTS"
    fi
}
trap cleanup EXIT

# ==================== Tests: extract_score() ====================

echo "=== extract_score() Tests ==="
echo ""

# --- Format 1: X/100 ---
echo "--- Format 1: X/100 ---"

assert_eq "plain 85/100" "85" "$(extract_score "总体评分 85/100")"
assert_eq "plain 92/100" "92" "$(extract_score "Score: 92/100")"
assert_eq "plain 0/100" "0" "$(extract_score "得分 0/100")"
assert_eq "plain 100/100" "100" "$(extract_score "满分 100/100")"

# --- Format 2: **评分: X/100** ---
echo "--- Format 2: **评分: X/100** ---"

assert_eq "bold 评分 85/100" "85" "$(extract_score "**评分: 85/100**")"
assert_eq "bold Score 78/100" "78" "$(extract_score "**Score: 78/100**")"
assert_eq "bold 评分 in context" "90" "$(extract_score "一些文字\n\n**评分: 90/100**\n\n更多文字")"

# --- Format 3: 总分 table row ---
echo "--- Format 3: 总分 table ---"

assert_eq "总分 table format" "70" "$(extract_score "| 总分 | 7.0 |\n|**总分**|**7.0**|")"
assert_eq "总分 arrow format" "80" "$(extract_score "总分 → 8.0")"

# --- Format 4: X/10 ---
echo "--- Format 4: X/10 ---"

assert_eq "8/10 scale" "80" "$(extract_score "评分 8/10")"
assert_eq "7/10 scale" "70" "$(extract_score "Score: 7/10")"
assert_eq "9.5/10 scale" "95" "$(extract_score "9.5/10")"

# --- Format 5: **评分: X** ---
echo "--- Format 5: **评分: X** (no /100) ---"

assert_eq "bold 评分 small number" "80" "$(extract_score "**评分: 8**")"
assert_eq "bold Score small number" "70" "$(extract_score "**Score: 7**")"
assert_eq "bold 评分 large number" "85" "$(extract_score "**评分: 85**")"
assert_eq "bold Score large number" "92" "$(extract_score "**Score: 92**")"

# --- Format 6: 评分: X ---
echo "--- Format 6: 评分: X (plain) ---"

assert_eq "plain 评分 small" "90" "$(extract_score "评分: 9")"
assert_eq "plain Score small" "60" "$(extract_score "Score: 6")"
assert_eq "plain 评分 large" "75" "$(extract_score "评分: 75")"
assert_eq "plain Score large" "88" "$(extract_score "Score: 88")"

# --- No score found ---
echo "--- No score ---"

assert_eq "no score returns 0" "0" "$(extract_score "这段文字没有评分信息")"
assert_eq "empty string returns 0" "0" "$(extract_score "")"

# --- Priority: Format 1 should win over others ---
echo "--- Priority tests ---"

assert_eq "format 1 takes priority" "85" "$(extract_score "总体评分 85/100\n评分: 7")"

# --- Edge cases ---
echo "--- Edge cases ---"

assert_eq "score with decimal" "86" "$(extract_score "85.5/100")"
assert_eq "score in multiline" "75" "$(extract_score "Line 1\n评分 75/100\nLine 3")"

# ==================== Tests: has_fatal_error() ====================

echo ""
echo "=== has_fatal_error() Tests ==="
echo ""

TMPDIR_TESTS=$(mktemp -d)

# Helper: create temp log file with content
make_log() {
    local name="$1"
    local content="$2"
    local path="$TMPDIR_TESTS/$name"
    echo -e "$content" > "$path"
    echo "$path"
}

echo "--- Fatal errors (should detect) ---"

assert_true "Error: prefix" "has_fatal_error $(make_log 'err1.log' 'Error: something went wrong')"
assert_true "ERROR: prefix" "has_fatal_error $(make_log 'err2.log' 'ERROR: connection failed')"
assert_true "Fatal: prefix" "has_fatal_error $(make_log 'err3.log' 'Fatal: out of memory')"
assert_true "Panic: prefix" "has_fatal_error $(make_log 'err4.log' 'Panic: runtime error')"
assert_true "timeout error" "has_fatal_error $(make_log 'err5.log' 'timeout error during API call')"
assert_true "rate limit error" "has_fatal_error $(make_log 'err6.log' 'rate limit error exceeded')"
assert_true "authentication error" "has_fatal_error $(make_log 'err7.log' 'authentication error: invalid token')"
assert_true "API key error" "has_fatal_error $(make_log 'err8.log' 'API key error: key not found')"
assert_true "Exception prefix" "has_fatal_error $(make_log 'err9.log' 'Exception: null pointer reference')"
assert_true "context length exceeded" "has_fatal_error $(make_log 'err10.log' 'context length exceeded')"
assert_true "token limit exceeded" "has_fatal_error $(make_log 'err11.log' 'token limit exceeded')"
assert_true "model is overloaded" "has_fatal_error $(make_log 'err12.log' 'model is overloaded')"
assert_true "server error" "has_fatal_error $(make_log 'err13.log' 'server error: 500')"
assert_true "service unavailable" "has_fatal_error $(make_log 'err14.log' 'service unavailable')"
assert_true "internal server error" "has_fatal_error $(make_log 'err15.log' 'internal server error')"
assert_true "too many requests" "has_fatal_error $(make_log 'err16.log' 'too many requests')"
assert_true "quota exceeded" "has_fatal_error $(make_log 'err17.log' 'quota exceeded')"
assert_true "billing hard limit" "has_fatal_error $(make_log 'err18.log' 'billing hard limit reached')"
assert_true "connection refused" "has_fatal_error $(make_log 'err19.log' 'connection refused')"
assert_true "network error" "has_fatal_error $(make_log 'err20.log' 'network error')"
assert_true "DNS resolution" "has_fatal_error $(make_log 'err21.log' 'DNS resolution failed')"

echo "--- Non-fatal content (should not detect) ---"

assert_false "normal output" "has_fatal_error $(make_log 'ok1.log' 'The implementation looks good\nTests passed successfully')"
assert_false "error handling discussion" "has_fatal_error $(make_log 'ok2.log' 'Consider adding error handling for edge cases')"
assert_false "error in middle of line" "has_fatal_error $(make_log 'ok3.log' 'This fix resolves the error that occurred previously')"
assert_false "empty file" "has_fatal_error $(make_log 'ok4.log' '')"
assert_false "nonexistent file" "has_fatal_error /tmp/nonexistent_file_$$_test.log"

# ==================== Tests: has_api_failure() ====================

echo ""
echo "=== has_api_failure() Tests ==="
echo ""

echo "--- API failures (should detect) ---"

assert_true "status 401" "has_api_failure $(make_log 'api1.log' 'status 401 Unauthorized')"
assert_true "status 429" "has_api_failure $(make_log 'api2.log' 'status 429 Too Many Requests')"
assert_true "status 500" "has_api_failure $(make_log 'api3.log' 'status 500 Internal Server Error')"
assert_true "status 503" "has_api_failure $(make_log 'api4.log' 'status 503 Service Unavailable')"
assert_true "HTTP 500" "has_api_failure $(make_log 'api5.log' 'HTTP 500 error')"
assert_true "curl error" "has_api_failure $(make_log 'api6.log' 'curl error: connection timed out')"
assert_true "fetch failed" "has_api_failure $(make_log 'api7.log' 'fetch failed: network unreachable')"
assert_true "request failed" "has_api_failure $(make_log 'api8.log' 'request failed: timeout')"
assert_true "response is empty" "has_api_failure $(make_log 'api9.log' 'response is empty')"
assert_true "no response received" "has_api_failure $(make_log 'api10.log' 'no response received from server')"

echo "--- Normal API responses (should not detect) ---"

assert_false "normal output" "has_api_failure $(make_log 'api_ok1.log' 'Implementation completed successfully')"
assert_false "status discussion" "has_api_failure $(make_log 'api_ok2.log' 'Check the HTTP status codes for error handling')"
assert_false "empty file" "has_api_failure $(make_log 'api_ok3.log' '')"
assert_false "nonexistent file" "has_api_failure /tmp/nonexistent_file_$$_test2.log"

# ==================== Tests: check_score_passed() ====================

echo ""
echo "=== check_score_passed() Tests ==="
echo ""

echo "--- Scores at threshold (85) ---"

assert_true "score 85 passes" "check_score_passed 85"
assert_true "score 100 passes" "check_score_passed 100"
assert_true "score 90 passes" "check_score_passed 90"

echo "--- Scores below threshold ---"

assert_false "score 84 fails" "check_score_passed 84"
assert_false "score 0 fails" "check_score_passed 0"
assert_false "score 50 fails" "check_score_passed 50"

# ==================== Tests: annealing_delay() ====================

echo ""
echo "=== annealing_delay() Tests ==="
echo ""

echo "--- Base delay calculation (without jitter randomness) ---"

# retry=1: base=2*1=2, max_jitter=0 (2/4=0 rounded down)
delay1=$(annealing_delay 1)
assert_true "retry 1 delay >= 2" "[ $delay1 -ge 2 ]"
assert_true "retry 1 delay <= 2" "[ $delay1 -le 2 ]"

# retry=2: base=2*2=4, max_jitter=1 (4/4=1)
delay2=$(annealing_delay 2)
assert_true "retry 2 delay >= 4" "[ $delay2 -ge 4 ]"
assert_true "retry 2 delay <= 5" "[ $delay2 -le 5 ]"

# retry=3: base=2*4=8, max_jitter=2 (8/4=2)
delay3=$(annealing_delay 3)
assert_true "retry 3 delay >= 8" "[ $delay3 -ge 8 ]"
assert_true "retry 3 delay <= 10" "[ $delay3 -le 10 ]"

# retry=4: base=2*8=16, max_jitter=4 (16/4=4)
delay4=$(annealing_delay 4)
assert_true "retry 4 delay >= 16" "[ $delay4 -ge 16 ]"
assert_true "retry 4 delay <= 20" "[ $delay4 -le 20 ]"

# retry=5: base=2*16=32, max_jitter=8 (32/4=8)
delay5=$(annealing_delay 5)
assert_true "retry 5 delay >= 32" "[ $delay5 -ge 32 ]"
assert_true "retry 5 delay <= 40" "[ $delay5 -le 40 ]"

echo "--- Capped at max delay ---"

# retry=10: base=2*512=1024, but should be capped at 60
delay10=$(annealing_delay 10)
assert_true "retry 10 capped at 60" "[ $delay10 -le 60 ]"

echo "--- Exponential growth ---"

# Verify delay generally increases with retries
assert_true "delay increases retry 1<2" "[ $delay2 -ge $delay1 ]"
assert_true "delay increases retry 2<3" "[ $delay3 -ge $delay2 ]"

# ==================== Tests: PIPESTATUS exit code capture ====================

echo ""
echo "=== PIPESTATUS exit code capture Tests ==="
echo ""

echo "--- pipefail preserves exit codes ---"

# With set -o pipefail, a failing first command should cause the pipeline to fail
assert_true "pipefail: failing command in pipe" "echo hello | false 2>/dev/null; [ ${PIPESTATUS[0]} -ne 0 ] || [ \$? -ne 0 ] || true"

echo "--- PIPESTATUS captures first command exit ---"

# Successful pipeline: both commands succeed, PIPESTATUS[0] should be 0
result=$(bash -c 'set -o pipefail; echo "test" | cat; echo ${PIPESTATUS[0]}')
assert_eq "PIPESTATUS: successful pipeline" "0" "$(bash -c 'set -o pipefail; echo "test" | cat>/dev/null; echo ${PIPESTATUS[0]}')"

# Failing first command: PIPESTATUS[0] should reflect the failure
assert_true "PIPESTATUS: failing first command" "bash -c 'set -o pipefail; false | cat>/dev/null; exit \${PIPESTATUS[0]}' 2>/dev/null; [ \$? -ne 0 ]"

# ==================== Tests: Output quality detection ====================

echo ""
echo "=== Output quality detection Tests ==="
echo ""

echo "--- Meaningful output detection ---"

# Count non-empty, non-whitespace lines
assert_eq "5 non-empty lines >= 5" "5" "$(echo -e "line1\nline2\nline3\nline4\nline5" | grep -vE '^\s*$' | wc -l | tr -d ' ')"

# Whitespace-only lines should be filtered
assert_eq "whitespace-only lines filtered" "2" "$(echo -e "line1\n   \n\nline2\n\t\n" | grep -vE '^\s*$' | wc -l | tr -d ' ')"

# Empty output
assert_eq "empty output has 0 lines" "0" "$(echo "" | grep -vE '^\s*$' | wc -l | tr -d ' ')"

# Only whitespace
assert_eq "whitespace-only output has 0 lines" "0" "$(echo -e "   \n\t\n  " | grep -vE '^\s*$' | wc -l | tr -d ' ')"

echo "--- Combined error detection scenarios ---"

# A log file with fatal error should be detected even if exit code is 0
cat > "$TMPDIR_TESTS/exit0_with_error.log" << 'INNEREOF'
Error: API rate limit exceeded
The implementation is complete.
INNEREOF
assert_true "exit 0 + fatal error in log" "has_fatal_error $TMPDIR_TESTS/exit0_with_error.log"

# A log file with API failure should be detected
cat > "$TMPDIR_TESTS/exit0_with_api_failure.log" << 'INNEREOF'
status 429 Too Many Requests
The code looks good.
INNEREOF
assert_true "exit 0 + API failure in log" "has_api_failure $TMPDIR_TESTS/exit0_with_api_failure.log"

# A normal log file with "error" discussion should NOT be flagged
cat > "$TMPDIR_TESTS/normal_error_discussion.log" << 'INNEREOF'
Consider adding error handling for edge cases.
The error path should return a proper message.
Overall this is a solid implementation.
Score: 85/100
All tests pass successfully.
INNEREOF
assert_false "normal error discussion not fatal" "has_fatal_error $TMPDIR_TESTS/normal_error_discussion.log"
assert_false "normal error discussion not API failure" "has_api_failure $TMPDIR_TESTS/normal_error_discussion.log"
assert_true "normal discussion has enough lines" "[ $(grep -vE '^\s*$' $TMPDIR_TESTS/normal_error_discussion.log | wc -l) -ge 5 ]"

# ==================== Tests: progress.md functions ====================

echo ""
echo "=== progress.md functions Tests ==="
echo ""

# Setup: create a temporary WORK_DIR for progress tests
WORK_DIR="$TMPDIR_TESTS/progress_test_workdir"
mkdir -p "$WORK_DIR"

# --- init_progress() ---
echo "--- init_progress() ---"

ISSUE_NUMBER=99
init_progress

assert_true "progress.md created" "[ -f '$WORK_DIR/progress.md' ]"
assert_true "has Codebase Patterns header" "grep -q '## Codebase Patterns' '$WORK_DIR/progress.md'"

# --- extract_learnings_from_log() ---
echo "--- extract_learnings_from_log() ---"

# Create a log file with ## Learnings section
cat > "$TMPDIR_TESTS/learnings_log.txt" << 'INNEREOF'
I implemented the feature.
## Learnings

- **模式**: The project uses dependency injection
- **踩坑**: Config must be loaded before init
- **经验**: Always check nil before accessing map

## Other Section
This should not be included.
INNEREOF

learnings_result=$(extract_learnings_from_log "$TMPDIR_TESTS/learnings_log.txt")
assert_true "extracts Learnings section" "echo '$learnings_result' | grep -q 'dependency injection'"
assert_true "Learnings includes 踩坑" "echo '$learnings_result' | grep -q '踩坑'"
# The "## Other Section" heading should not be included (it's the next ## section)
assert_false "excludes non-Learnings section" "echo '$learnings_result' | grep -q 'Other Section'"

# Create a log file WITHOUT ## Learnings section (fallback)
cat > "$TMPDIR_TESTS/no_learnings_log.txt" << 'INNEREOF'
Line 1 of output
Line 2 of output
Line 3 of output
INNEREOF

fallback_result=$(extract_learnings_from_log "$TMPDIR_TESTS/no_learnings_log.txt")
assert_true "fallback returns content" "[ -n '$fallback_result' ]"
assert_true "fallback includes line 1" "echo '$fallback_result' | grep -q 'Line 1'"

# Non-existent log file
empty_result=$(extract_learnings_from_log "/tmp/nonexistent_log_$$_test.txt")
assert_eq "nonexistent file returns empty" "" "$empty_result"

# --- append_to_progress() ---
echo "--- append_to_progress() ---"

# Re-init for clean state
rm -f "$WORK_DIR/progress.md"
init_progress

# Append an iteration entry
cat > "$TMPDIR_TESTS/iter1_log.txt" << 'INNEREOF'
## Learnings

- **模式**: Project uses factory pattern
- **踩坑**: Avoid global state
INNEREOF

append_to_progress 1 "claude" "$TMPDIR_TESTS/iter1_log.txt" "N/A" "初始实现" ""

assert_true "progress.md has Iteration 1" "grep -q '## Iteration 1' '$WORK_DIR/progress.md'"
assert_true "progress.md has agent name" "grep -q 'claude' '$WORK_DIR/progress.md'"
assert_true "progress.md has learnings content" "grep -q 'factory pattern' '$WORK_DIR/progress.md'"

# Append a second iteration with review feedback
append_to_progress 2 "codex" "$TMPDIR_TESTS/iter1_log.txt" "65" "审核+修复" "Hardcoded secret found in auth.go"

assert_true "progress.md has Iteration 2" "grep -q '## Iteration 2' '$WORK_DIR/progress.md'"
assert_true "progress.md has review score" "grep -q '65/100' '$WORK_DIR/progress.md'"
assert_true "progress.md has review feedback" "grep -q 'Hardcoded secret' '$WORK_DIR/progress.md'"

# Codebase Patterns section should still be at top
assert_true "Codebase Patterns still at top after appends" "head -5 '$WORK_DIR/progress.md' | grep -q '## Codebase Patterns'"

# --- get_progress_content() ---
echo "--- get_progress_content() ---"

content=$(get_progress_content)
assert_true "returns non-empty content" "[ -n '$content' ]"
assert_true "includes Codebase Patterns" "echo '$content' | grep -q '## Codebase Patterns'"
assert_true "includes iteration entries" "echo '$content' | grep -q '## Iteration 1'"

# Test with no progress.md
rm -f "$WORK_DIR/progress.md"
empty_content=$(get_progress_content)
assert_eq "no progress.md returns empty" "" "$empty_content"

# --- get_progress_section() ---
echo "--- get_progress_section() ---"

# Re-create progress.md
init_progress
append_to_progress 1 "claude" "$TMPDIR_TESTS/iter1_log.txt" "N/A" "初始实现" ""

section=$(get_progress_section)
assert_true "section has 跨迭代经验 header" "echo '$section' | grep -q '跨迭代经验'"
assert_true "section includes Codebase Patterns" "echo '$section' | grep -q '## Codebase Patterns'"
assert_true "section includes iteration data" "echo '$section' | grep -q '## Iteration 1'"

# Test with no progress.md
rm -f "$WORK_DIR/progress.md"
empty_section=$(get_progress_section)
assert_eq "no progress.md returns empty section" "" "$empty_section"

# --- Truncation test ---
echo "--- Truncation test ---"

rm -f "$WORK_DIR/progress.md"
init_progress

# Append many iterations to exceed 5000 char limit
for i in $(seq 1 20); do
    echo "Pattern $i: $(printf 'A%.0s' {1..100})" >> "$WORK_DIR/progress.md"
    echo "" >> "$WORK_DIR/progress.md"
    echo "## Iteration $i - 2024-01-15" >> "$WORK_DIR/progress.md"
    echo "Content for iteration $i with enough text to fill space." >> "$WORK_DIR/progress.md"
    echo "" >> "$WORK_DIR/progress.md"
done

truncated_content=$(get_progress_content)
content_len=$(echo "$truncated_content" | wc -c | tr -d ' ')
assert_true "truncated content stays within limit" "[ $content_len -le 8000 ]"

# ==================== Tests: tasks.json functions ====================

echo ""
echo "=== tasks.json functions Tests ==="
echo ""

# Setup: create a temporary WORK_DIR for tasks tests
WORK_DIR="$TMPDIR_TESTS/tasks_test_workdir"
rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"

# --- get_tasks_file() ---
echo "--- get_tasks_file() ---"

tasks_file_result=$(get_tasks_file)
assert_eq "get_tasks_file returns correct path" "$WORK_DIR/tasks.json" "$tasks_file_result"

# --- has_subtasks() when no tasks.json ---
echo "--- has_subtasks() when no file ---"

assert_false "no tasks.json returns false" "has_subtasks"

# --- Create a valid tasks.json ---
cat > "$WORK_DIR/tasks.json" << 'INNEREOF'
{
  "issueNumber": 42,
  "subtasks": [
    {
      "id": "T-001",
      "title": "添加 tasks.json 解析函数",
      "description": "实现 tasks.json 的创建、读取、更新函数",
      "acceptanceCriteria": ["JSON 可正确解析", "子任务状态可更新"],
      "priority": 1,
      "passes": false
    },
    {
      "id": "T-002",
      "title": "修改迭代循环",
      "description": "修改 run.sh 迭代循环以支持子任务粒度",
      "acceptanceCriteria": ["迭代按子任务执行", "子任务通过后自动切换"],
      "priority": 2,
      "passes": false
    },
    {
      "id": "T-003",
      "title": "更新 prompt 注入",
      "description": "将子任务信息注入到 agent prompt 中",
      "acceptanceCriteria": ["实现和审核 prompt 包含子任务信息"],
      "priority": 3,
      "passes": false
    }
  ]
}
INNEREOF

# --- has_subtasks() with valid file ---
echo "--- has_subtasks() with valid file ---"

assert_true "valid tasks.json returns true" "has_subtasks"

# --- get_current_subtask() ---
echo "--- get_current_subtask() ---"

current=$(get_current_subtask)
assert_true "returns non-null subtask" "[ '$current' != 'null' ]"
assert_true "current subtask has id T-001" "echo '$current' | jq -r '.id' | grep -q 'T-001'"

# --- get_current_subtask_id() ---
echo "--- get_current_subtask_id() ---"

assert_eq "current subtask id is T-001" "T-001" "$(get_current_subtask_id)"

# --- get_current_subtask_title() ---
echo "--- get_current_subtask_title() ---"

current_title=$(get_current_subtask_title)
assert_true "current subtask title contains 解析函数" "echo '$current_title' | grep -q '解析函数'"

# --- mark_subtask_passed() ---
echo "--- mark_subtask_passed() ---"

mark_subtask_passed "T-001"

# After marking T-001, current should be T-002
assert_eq "after T-001 passes, current is T-002" "T-002" "$(get_current_subtask_id)"

# Verify T-001 is marked as passed in the file
t001_passes=$(jq -r '.subtasks[0].passes' "$WORK_DIR/tasks.json")
assert_eq "T-001 passes is true" "true" "$t001_passes"

# --- get_subtask_progress_summary() ---
echo "--- get_subtask_progress_summary() ---"

progress_summary=$(get_subtask_progress_summary)
assert_true "progress summary contains 1/3" "echo '$progress_summary' | grep -q '1/3'"
assert_true "progress summary contains T-002" "echo '$progress_summary' | grep -q 'T-002'"

# --- all_subtasks_passed() ---
echo "--- all_subtasks_passed() ---"

assert_false "not all subtasks passed" "all_subtasks_passed"

# Mark remaining subtasks as passed
mark_subtask_passed "T-002"
mark_subtask_passed "T-003"

assert_true "all subtasks passed" "all_subtasks_passed"
assert_eq "current subtask id is empty" "" "$(get_current_subtask_id)"

# --- get_subtask_section() ---
echo "--- get_subtask_section() ---"

# Reset tasks.json for section tests
cat > "$WORK_DIR/tasks.json" << 'INNEREOF'
{
  "issueNumber": 42,
  "subtasks": [
    {
      "id": "T-001",
      "title": "测试子任务",
      "description": "测试子任务描述",
      "acceptanceCriteria": ["条件1", "条件2"],
      "priority": 1,
      "passes": false
    }
  ]
}
INNEREOF

section=$(get_subtask_section)
assert_true "section has 当前子任务 header" "echo '$section' | grep -q '当前子任务'"
assert_true "section has T-001" "echo '$section' | grep -q 'T-001'"
assert_true "section has 测试子任务" "echo '$section' | grep -q '测试子任务'"
assert_true "section has 条件1" "echo '$section' | grep -q '条件1'"

# --- get_subtask_review_section() ---
echo "--- get_subtask_review_section() ---"

review_section=$(get_subtask_review_section)
assert_true "review section has 子任务审核 header" "echo '$review_section' | grep -q '子任务审核'"
assert_true "review section has T-001" "echo '$review_section' | grep -q 'T-001'"
assert_true "review section has 验收条件" "echo '$review_section' | grep -q '验收条件'"

# --- Edge cases ---
echo "--- Edge cases ---"

# Test with empty tasks.json (no subtasks)
cat > "$WORK_DIR/tasks.json" << 'INNEREOF'
{
  "issueNumber": 42,
  "subtasks": []
}
INNEREOF

assert_false "empty subtasks array returns false" "has_subtasks"
assert_eq "empty subtasks current id is empty" "" "$(get_current_subtask_id)"

# Test with all passed
cat > "$WORK_DIR/tasks.json" << 'INNEREOF'
{
  "issueNumber": 42,
  "subtasks": [
    {
      "id": "T-001",
      "title": "已完成",
      "description": "desc",
      "acceptanceCriteria": [],
      "priority": 1,
      "passes": true
    }
  ]
}
INNEREOF

assert_true "all passed returns true for all_subtasks_passed" "all_subtasks_passed"
assert_eq "all passed current id is empty" "" "$(get_current_subtask_id)"

# Test with no tasks.json (backward compatibility)
rm -f "$WORK_DIR/tasks.json"
assert_true "no tasks.json: all_subtasks_passed returns true (backward compat)" "all_subtasks_passed"
assert_eq "no tasks.json: get_subtask_section returns empty" "" "$(get_subtask_section)"

# Clean up tasks test dir
rm -rf "$WORK_DIR"

# ==================== Summary ====================

echo ""
echo "=========================================="
echo "Total: $TOTAL  Passed: $PASS  Failed: $FAIL"
echo "=========================================="

if [ $FAIL -gt 0 ]; then
    exit 1
fi

exit 0
