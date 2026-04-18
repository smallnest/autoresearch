#!/bin/bash
# tests/test_extract_score.sh - Unit tests for extract_score()
#
# Usage: bash tests/test_extract_score.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source extract_score by extracting just that function from run.sh
# (run.sh has set -e and side effects, so we can't source it directly)
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

# ==================== Tests ====================

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

# ==================== Summary ====================

echo ""
echo "=========================================="
echo "Total: $TOTAL  Passed: $PASS  Failed: $FAIL"
echo "=========================================="

if [ $FAIL -gt 0 ]; then
    exit 1
fi

exit 0
