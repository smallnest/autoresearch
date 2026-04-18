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

# ==================== Summary ====================

echo ""
echo "=========================================="
echo "Total: $TOTAL  Passed: $PASS  Failed: $FAIL"
echo "=========================================="

if [ $FAIL -gt 0 ]; then
    exit 1
fi

exit 0
