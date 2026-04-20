#!/bin/bash
# tests/test_context_overflow.sh - Unit tests for context overflow detection
#
# Usage: bash tests/test_context_overflow.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# ==================== Extract functions from run.sh ====================

# Configuration constants
RETRY_BASE_DELAY=2
RETRY_MAX_DELAY=60
PASSING_SCORE=85
MAX_CONTEXT_RETRIES=3

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

TMPDIR_TESTS=$(mktemp -d)

# Helper: create temp log file with content
make_log() {
    local name="$1"
    local content="$2"
    local path="$TMPDIR_TESTS/$name"
    echo -e "$content" > "$path"
    echo "$path"
}

# ==================== Tests: detect_context_overflow() ====================

echo "=== detect_context_overflow() Tests ==="
echo ""

echo "--- Context overflow signals (should detect) ---"

assert_true "context length exceeded" \
    "detect_context_overflow $(make_log 'ov1.log' 'Error: context length exceeded, maximum is 200000 tokens')"

assert_true "context_length_exceeded (underscore)" \
    "detect_context_overflow $(make_log 'ov2.log' 'error: context_length_exceeded')"

assert_true "maximum context length" \
    "detect_context_overflow $(make_log 'ov3.log' 'This model maximum context length is 128000 tokens')"

assert_true "token limit exceeded" \
    "detect_context_overflow $(make_log 'ov4.log' 'Error: token limit exceeded')"

assert_true "token_limit_reached" \
    "detect_context_overflow $(make_log 'ov5.log' 'token_limit_reached: input too long')"

assert_true "too many tokens" \
    "detect_context_overflow $(make_log 'ov6.log' 'Error: too many tokens in request')"

assert_true "exceeds the maximum" \
    "detect_context_overflow $(make_log 'ov7.log' 'input exceeds the maximum number of tokens allowed')"

assert_true "exceeded the maximum number of tokens" \
    "detect_context_overflow $(make_log 'ov8.log' 'You exceeded the maximum number of tokens for this model')"

assert_true "input is too long" \
    "detect_context_overflow $(make_log 'ov9.log' 'Error: input is too long, please reduce the prompt size')"

assert_true "context window exceeded" \
    "detect_context_overflow $(make_log 'ov10.log' 'context window exceeded: reduce input size')"

assert_true "maximum context window" \
    "detect_context_overflow $(make_log 'ov11.log' 'Reached maximum context window size')"

assert_true "case insensitive" \
    "detect_context_overflow $(make_log 'ov12.log' 'CONTEXT LENGTH EXCEEDED')"

assert_true "mixed case" \
    "detect_context_overflow $(make_log 'ov13.log' 'Token Limit Exceeded')"

assert_true "in multiline output" \
    "detect_context_overflow $(make_log 'ov14.log' 'Implementing feature...\nDone with step 1\nError: context length exceeded\nRemaining steps not completed')"

echo "--- Normal output (should NOT detect) ---"

assert_false "normal implementation output" \
    "detect_context_overflow $(make_log 'ok1.log' 'Implementation complete\nTests passing\nCode looks good')"

assert_false "empty file" \
    "detect_context_overflow $(make_log 'ok2.log' '')"

assert_false "nonexistent file" \
    "detect_context_overflow /tmp/nonexistent_file_$$_test.log"

assert_false "context discussion" \
    "detect_context_overflow $(make_log 'ok3.log' 'The context object provides request-scoped data\nUse context.WithTimeout for deadlines')"

assert_false "token discussion" \
    "detect_context_overflow $(make_log 'ok4.log' 'JWT token generation\nStore the refresh token securely')"

assert_false "limit discussion" \
    "detect_context_overflow $(make_log 'ok5.log' 'Add rate limiting to prevent abuse\nSet connection limits in the config')"

assert_false "maximum discussion" \
    "detect_context_overflow $(make_log 'ok6.log' 'Maximum retry attempts should be 3\nSet the maximum file size')"

# ==================== Tests: handle_context_overflow() ====================

echo ""
echo "=== handle_context_overflow() Tests ==="
echo ""

# Need to set up WORK_DIR and other state for handle_context_overflow
WORK_DIR="$TMPDIR_TESTS/handle_test_workdir"
mkdir -p "$WORK_DIR"
ISSUE_NUMBER=42

# Reuse progress functions from test_extract_score.sh
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
    if [ ! -f "$log_file" ]; then echo ""; return; fi
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
    if [ ! -f "$progress_file" ]; then init_progress; fi

    local date_str
    date_str=$(date '+%Y-%m-%d')
    local learnings
    learnings=$(extract_learnings_from_log "$log_file")
    local learnings_truncated
    learnings_truncated=$(echo "$learnings" | head -c 1500)

    local entry="
## Iteration $iteration - $date_str

- **Agent**: $agent_name
- **类型**: $entry_type
- **评分**: $score/100
"
    if [ -n "$learnings_truncated" ]; then
        entry="$entry
- **经验与发现**:

${learnings_truncated}
"
    fi
    echo "$entry" >> "$progress_file"
}

handle_context_overflow() {
    local iteration="$1"
    local agent_name="$2"
    local log_file="$3"

    if ! detect_context_overflow "$log_file"; then
        return 1
    fi

    CONTEXT_RETRIES=$((CONTEXT_RETRIES + 1))

    if [ $CONTEXT_RETRIES -gt $MAX_CONTEXT_RETRIES ]; then
        return 1
    fi

    PREVIOUS_FEEDBACK="上一次迭代因上下文溢出中断。请继续当前子任务的实现，参考 progress.md 中的进度记录。"
    CONSECUTIVE_ITERATION_FAILURES=0
    CONTEXT_OVERFLOW=1

    append_to_progress "$iteration" "$agent_name" "$log_file" "N/A" "上下文溢出交接" ""
    echo "- 上下文溢出: 自动交接 (第 $CONTEXT_RETRIES/$MAX_CONTEXT_RETRIES 次)" >> "$WORK_DIR/log.md"

    return 0
}

echo "--- Overflow detected and handled ---"

# Setup
init_progress
cat > "$WORK_DIR/log.md" << 'EOF'
# Issue #42 实现日志
EOF

CONTEXT_RETRIES=0
CONSECUTIVE_ITERATION_FAILURES=1
CONTEXT_OVERFLOW=0
PREVIOUS_FEEDBACK=""

overflow_log=$(make_log 'overflow_test.log' 'Error: context length exceeded')

assert_true "handle returns 0 for overflow" \
    "handle_context_overflow 1 'claude' '$overflow_log'"

assert_eq "CONTEXT_RETRIES incremented" "1" "$CONTEXT_RETRIES"
assert_eq "CONTEXT_OVERFLOW set to 1" "1" "$CONTEXT_OVERFLOW"
assert_eq "CONSECUTIVE_FAILURES reset to 0" "0" "$CONSECUTIVE_ITERATION_FAILURES"
assert_true "PREVIOUS_FEEDBACK mentions overflow" \
    "echo '$PREVIOUS_FEEDBACK' | grep -q '上下文溢出'"
assert_true "progress.md has overflow entry" \
    "grep -q '上下文溢出交接' '$WORK_DIR/progress.md'"
assert_true "log.md has overflow note" \
    "grep -q '上下文溢出.*自动交接' '$WORK_DIR/log.md'"

echo "--- Non-overflow not handled ---"

CONTEXT_RETRIES=0
CONTEXT_OVERFLOW=0
normal_log=$(make_log 'normal_test.log' 'Implementation complete, tests pass')

assert_false "handle returns 1 for normal output" \
    "handle_context_overflow 1 'claude' '$normal_log'"

assert_eq "CONTEXT_RETRIES stays 0 for normal" "0" "$CONTEXT_RETRIES"

echo "--- Max retries reached ---"

CONTEXT_RETRIES=$MAX_CONTEXT_RETRIES
CONTEXT_OVERFLOW=0
CONSECUTIVE_ITERATION_FAILURES=0

assert_false "handle returns 1 when max retries reached" \
    "handle_context_overflow 1 'claude' '$overflow_log'"

assert_eq "CONTEXT_RETRIES at max+1" "$((MAX_CONTEXT_RETRIES + 1))" "$CONTEXT_RETRIES"

echo "--- Multiple retries increment counter ---"

CONTEXT_RETRIES=0
CONTEXT_OVERFLOW=0

handle_context_overflow 1 "claude" "$overflow_log"
assert_eq "first retry: counter=1" "1" "$CONTEXT_RETRIES"

handle_context_overflow 2 "codex" "$overflow_log"
assert_eq "second retry: counter=2" "2" "$CONTEXT_RETRIES"

handle_context_overflow 3 "opencode" "$overflow_log"
assert_eq "third retry: counter=3" "3" "$CONTEXT_RETRIES"

# Fourth should fail
CONTEXT_OVERFLOW=0
result=0
handle_context_overflow 4 "claude" "$overflow_log" || result=$?
assert_true "fourth retry exceeds max" "[ $result -ne 0 ]"

# ==================== Summary ====================

echo ""
echo "=========================================="
echo "Total: $TOTAL  Passed: $PASS  Failed: $FAIL"
echo "=========================================="

if [ $FAIL -gt 0 ]; then
    exit 1
fi

exit 0
