#!/bin/bash
# tests/test_output_validation.sh - Unit tests for output file validation
#
# Usage: bash tests/test_output_validation.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

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

assert_file_contains() {
    local test_name="$1"
    local file="$2"
    local pattern="$3"
    TOTAL=$((TOTAL + 1))
    if grep -q "$pattern" "$file" 2>/dev/null; then
        PASS=$((PASS + 1))
        echo "  PASS: $test_name"
    else
        FAIL=$((FAIL + 1))
        echo "  FAIL: $test_name (file does not contain '$pattern')"
    fi
}

# ==================== Setup ====================

TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

# Mock log function to capture messages
LOG_FILE="$TEST_DIR/captured_logs.txt"
log() {
    echo "$1" >> "$LOG_FILE"
}

log_console() {
    echo "$1"
}

# ==================== Test 1: Empty file ====================

echo "=== Test 1: Empty file handling ==="

EMPTY_FILE="$TEST_DIR/empty.log"
touch "$EMPTY_FILE"

# Simulate review function behavior with empty file
review_result=""
score=0
if [ ! -f "$EMPTY_FILE" ] || [ ! -s "$EMPTY_FILE" ]; then
    log "警告: 审核输出文件不存在或为空，默认评分 50"
    review_result=""
    score=50
else
    review_result=$(cat "$EMPTY_FILE")
fi

assert_eq "empty file score" "50" "$score"
assert_file_contains "empty file warning logged" "$LOG_FILE" "警告: 审核输出文件不存在或为空"

# Reset log
> "$LOG_FILE"

# ==================== Test 2: Non-existent file ====================

echo "=== Test 2: Non-existent file handling ==="

MISSING_FILE="$TEST_DIR/nonexistent.log"

# Simulate review function behavior with missing file
review_result=""
score=0
if [ ! -f "$MISSING_FILE" ] || [ ! -s "$MISSING_FILE" ]; then
    log "警告: 审核输出文件不存在或为空，默认评分 50"
    review_result=""
    score=50
else
    review_result=$(cat "$MISSING_FILE")
fi

assert_eq "missing file score" "50" "$score"
assert_file_contains "missing file warning logged" "$LOG_FILE" "警告: 审核输出文件不存在或为空"

# Reset log
> "$LOG_FILE"

# ==================== Test 3: Normal file with content ====================

echo "=== Test 3: Normal file with content ==="

NORMAL_FILE="$TEST_DIR/normal.log"
echo "This is a normal review output with score 85/100" > "$NORMAL_FILE"

# Simulate review function behavior with normal file
review_result=""
score=0
if [ ! -f "$NORMAL_FILE" ] || [ ! -s "$NORMAL_FILE" ]; then
    log "警告: 审核输出文件不存在或为空，默认评分 50"
    review_result=""
    score=50
else
    review_result=$(cat "$NORMAL_FILE")
    # Simulate score extraction
    score=$(echo "$review_result" | grep -oE '[0-9]+' | head -1)
fi

assert_eq "normal file score" "85" "$score"
assert_eq "normal file content" "This is a normal review output with score 85/100" "$review_result"

# Verify no warning was logged for normal file
if grep -q "警告: 审核输出文件不存在或为空" "$LOG_FILE" 2>/dev/null; then
    TOTAL=$((TOTAL + 1))
    FAIL=$((FAIL + 1))
    echo "  FAIL: normal file should not log warning"
else
    TOTAL=$((TOTAL + 1))
    PASS=$((PASS + 1))
    echo "  PASS: normal file should not log warning"
fi

# Reset log
> "$LOG_FILE"

# ==================== Test 4: Planning phase - empty file ====================

echo "=== Test 4: Planning phase empty file handling ==="

PLAN_EMPTY="$TEST_DIR/plan_empty.log"
touch "$PLAN_EMPTY"

# Simulate planning phase behavior with empty file
planning_failed=0
if [ ! -f "$PLAN_EMPTY" ] || [ ! -s "$PLAN_EMPTY" ]; then
    log "警告: 规划阶段输出文件不存在或为空，回退到原有模式"
    planning_failed=1
fi

assert_eq "planning empty file fallback" "1" "$planning_failed"
assert_file_contains "planning empty file warning" "$LOG_FILE" "警告: 规划阶段输出文件不存在或为空"

# Reset log
> "$LOG_FILE"

# ==================== Test 5: Planning phase - non-existent file ====================

echo "=== Test 5: Planning phase non-existent file handling ==="

PLAN_MISSING="$TEST_DIR/plan_missing.log"

# Simulate planning phase behavior with missing file
planning_failed=0
if [ ! -f "$PLAN_MISSING" ] || [ ! -s "$PLAN_MISSING" ]; then
    log "警告: 规划阶段输出文件不存在或为空，回退到原有模式"
    planning_failed=1
fi

assert_eq "planning missing file fallback" "1" "$planning_failed"
assert_file_contains "planning missing file warning" "$LOG_FILE" "警告: 规划阶段输出文件不存在或为空"

# Reset log
> "$LOG_FILE"

# ==================== Test 6: Planning phase - normal file ====================

echo "=== Test 6: Planning phase normal file handling ==="

PLAN_NORMAL="$TEST_DIR/plan_normal.log"
cat > "$PLAN_NORMAL" << 'EOF'
```json
{
  "subtasks": [
    {"id": "T-001", "title": "Test task"}
  ]
}
```
EOF

# Simulate planning phase behavior with normal file
planning_failed=0
if [ ! -f "$PLAN_NORMAL" ] || [ ! -s "$PLAN_NORMAL" ]; then
    log "警告: 规划阶段输出文件不存在或为空，回退到原有模式"
    planning_failed=1
else
    # Simulate JSON extraction
    json_content=$(sed -n '/^```json$/,/^```$/{ /^```json$/d; /^```$/d; p; }' "$PLAN_NORMAL" | head -200)
    if [ -z "$json_content" ]; then
        planning_failed=1
    fi
fi

assert_eq "planning normal file success" "0" "$planning_failed"

# Verify no warning was logged for normal planning file
if grep -q "警告: 规划阶段输出文件不存在或为空" "$LOG_FILE" 2>/dev/null; then
    TOTAL=$((TOTAL + 1))
    FAIL=$((FAIL + 1))
    echo "  FAIL: planning normal file should not log warning"
else
    TOTAL=$((TOTAL + 1))
    PASS=$((PASS + 1))
    echo "  PASS: planning normal file should not log warning"
fi

# ==================== Summary ====================

echo ""
echo "=========================================="
echo "Total: $TOTAL  Passed: $PASS  Failed: $FAIL"
echo "=========================================="

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
