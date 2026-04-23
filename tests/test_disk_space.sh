#!/bin/bash
# tests/test_disk_space.sh - Unit tests for disk space pre-check in check_dependencies
#
# Usage: bash tests/test_disk_space.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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
    if ! eval "$cmd"; then
        PASS=$((PASS + 1))
        echo "  PASS: $test_name"
    else
        FAIL=$((FAIL + 1))
        echo "  FAIL: $test_name (expected false, got true)"
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

# Mock log and error functions that write to a test log file
TEST_LOG="$TEST_DIR/test.log"

log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    echo "$msg" >> "$TEST_LOG"
}

error() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1"
    echo "$msg" >> "$TEST_LOG"
}

# ==================== Disk Space Check Logic ====================
# Extract the disk check portion from run.sh for isolated testing.
# This mirrors the exact logic in check_dependencies().

check_disk_space() {
    local disk_min_mb="${DISK_MIN_MB:-1024}"
    local available_kb
    available_kb=$(df -k . 2>/dev/null | awk 'NR==2 {print $4}') || available_kb=0
    local available_mb=$((available_kb / 1024))
    log "磁盘空间检查: 可用 ${available_mb}MB, 阈值 ${disk_min_mb}MB"
    if [ "$available_kb" -gt 0 ] && [ "$available_mb" -lt "$disk_min_mb" ]; then
        error "磁盘空间不足: 可用 ${available_mb}MB, 最低要求 ${disk_min_mb}MB"
        return 1
    fi
    return 0
}

# ==================== Tests ====================

echo ""
echo "=== Disk Space Pre-check Tests ==="
echo ""

# Test 1: Normal case - disk space sufficient with default threshold
test_disk_space_sufficient() {
    echo "--- test_disk_space_sufficient ---"
    : > "$TEST_LOG"
    unset DISK_MIN_MB

    # Default threshold is 1024MB; most systems have more than that
    check_disk_space
    local result=$?

    assert_eq "default threshold returns 0 (pass)" "0" "$result"
    assert_file_contains "log records disk check" "$TEST_LOG" "磁盘空间检查"
    assert_file_contains "log records available space" "$TEST_LOG" "MB"
}

test_disk_space_sufficient

# Test 2: Custom threshold via DISK_MIN_MB
test_custom_threshold_low() {
    echo "--- test_custom_threshold_low ---"
    : > "$TEST_LOG"
    # Set a very low threshold (1MB) - should always pass
    DISK_MIN_MB=1 check_disk_space
    local result=$?

    assert_eq "low custom threshold returns 0 (pass)" "0" "$result"
    assert_file_contains "log shows custom threshold" "$TEST_LOG" "1MB"
}

test_custom_threshold_low

# Test 3: Custom threshold too high - should fail
test_custom_threshold_too_high() {
    echo "--- test_custom_threshold_too_high ---"
    : > "$TEST_LOG"
    # Set an impossibly high threshold (99999999 MB ≈ 95 PB)
    local result=0
    DISK_MIN_MB=99999999 check_disk_space || result=$?

    assert_eq "impossibly high threshold returns 1 (fail)" "1" "$result"
    assert_file_contains "error message recorded" "$TEST_LOG" "磁盘空间不足"
    assert_file_contains "error includes threshold" "$TEST_LOG" "99999999MB"
}

test_custom_threshold_too_high

# Test 4: Threshold of 0 should always pass
test_threshold_zero() {
    echo "--- test_threshold_zero ---"
    : > "$TEST_LOG"
    DISK_MIN_MB=0 check_disk_space
    local result=$?

    assert_eq "threshold 0 returns 0 (always pass)" "0" "$result"
}

test_threshold_zero

# Test 5: Log contains both available and threshold values
test_log_format() {
    echo "--- test_log_format ---"
    : > "$TEST_LOG"
    DISK_MIN_MB=512 check_disk_space

    assert_file_contains "log contains threshold value" "$TEST_LOG" "阈值 512MB"
    assert_file_contains "log contains available value" "$TEST_LOG" "可用"
}

test_log_format

# ==================== Summary ====================

echo ""
echo "==============================="
echo "Total: $TOTAL  Pass: $PASS  Fail: $FAIL"
echo "==============================="

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
