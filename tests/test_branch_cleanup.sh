#!/bin/bash
# tests/test_branch_cleanup.sh - Unit tests for post-merge branch cleanup
#
# Usage: bash tests/test_branch_cleanup.sh

set -e

PASS=0
FAIL=0
TOTAL=0

WORK_ROOT=""
WORK_DIR=""

MOCK_GIT_CHECKOUT_FAIL=0
MOCK_GIT_PULL_FAIL=0
MOCK_GIT_BRANCH_DELETE_FAIL=0
MOCK_BRANCH_EXISTS=1
MOCK_GIT_LOG=""

git() {
    MOCK_GIT_LOG="${MOCK_GIT_LOG}git $*\n"

    case "$1" in
        checkout)
            [ "$MOCK_GIT_CHECKOUT_FAIL" -eq 1 ] && return 1
            return 0
            ;;
        pull)
            [ "$MOCK_GIT_PULL_FAIL" -eq 1 ] && return 1
            return 0
            ;;
        show-ref)
            [ "$MOCK_BRANCH_EXISTS" -eq 1 ] && return 0
            return 1
            ;;
        branch)
            if [ "$2" = "-D" ]; then
                [ "$MOCK_GIT_BRANCH_DELETE_FAIL" -eq 1 ] && return 1
                return 0
            fi
            return 0
            ;;
        *)
            return 0
            ;;
    esac
}

log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    if [ -n "$WORK_DIR" ] && [ -d "$WORK_DIR" ]; then
        echo "$msg" >> "$WORK_DIR/terminal.log"
    fi
}

log_console() {
    local msg="$1"
    if [ -n "$WORK_DIR" ] && [ -d "$WORK_DIR" ]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] $msg" >> "$WORK_DIR/terminal.log"
    fi
}

assert_eq() {
    local test_name="$1"
    local expected="$2"
    local actual="$3"
    TOTAL=$((TOTAL + 1))
    if [ "$expected" = "$actual" ]; then
        PASS=$((PASS + 1))
        echo "  PASS: $test_name"
    else
        FAIL=$((FAIL + 1))
        echo "  FAIL: $test_name (expected=$expected, actual=$actual)"
    fi
}

assert_contains() {
    local test_name="$1"
    local file="$2"
    local pattern="$3"
    TOTAL=$((TOTAL + 1))
    if grep -q "$pattern" "$file" 2>/dev/null; then
        PASS=$((PASS + 1))
        echo "  PASS: $test_name"
    else
        FAIL=$((FAIL + 1))
        echo "  FAIL: $test_name (pattern '$pattern' not found in $file)"
    fi
}

reset_state() {
    MOCK_GIT_CHECKOUT_FAIL=0
    MOCK_GIT_PULL_FAIL=0
    MOCK_GIT_BRANCH_DELETE_FAIL=0
    MOCK_BRANCH_EXISTS=1
    MOCK_GIT_LOG=""
}

setup_case() {
    reset_state
    WORK_ROOT=$(mktemp -d)
    WORK_DIR="$WORK_ROOT/work"
    mkdir -p "$WORK_DIR"
    : > "$WORK_DIR/terminal.log"
}

teardown_case() {
    if [ -n "$WORK_ROOT" ] && [ -d "$WORK_ROOT" ]; then
        rm -rf "$WORK_ROOT"
    fi
    WORK_ROOT=""
    WORK_DIR=""
}

# shellcheck source=/dev/null
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/branch_cleanup.sh"

trap teardown_case EXIT

echo "=== Branch Cleanup Tests ==="
echo ""

setup_case
echo "Scenario 1: checkout failure logs warning and main flow continues"
MOCK_GIT_CHECKOUT_FAIL=1
FOLLOWUP_EXECUTED=0
cleanup_merged_branch "main" "feature/test-issue"
FOLLOWUP_EXECUTED=1
assert_contains "checkout warning logged" "$WORK_DIR/terminal.log" "切换到 main 分支失败"
assert_contains "checkout failure log recorded" "$WORK_DIR/terminal.log" "branch cleanup: checkout main failed"
assert_eq "flow continues after checkout failure" "1" "$FOLLOWUP_EXECUTED"
teardown_case

setup_case
echo "Scenario 2: pull failure logs warning and main flow continues"
MOCK_GIT_PULL_FAIL=1
FOLLOWUP_EXECUTED=0
cleanup_merged_branch "main" "feature/test-issue"
FOLLOWUP_EXECUTED=1
assert_contains "pull warning logged" "$WORK_DIR/terminal.log" "拉取 main 分支最新代码失败"
assert_contains "pull failure log recorded" "$WORK_DIR/terminal.log" "branch cleanup: git pull main failed"
assert_eq "flow continues after pull failure" "1" "$FOLLOWUP_EXECUTED"
teardown_case

setup_case
echo "Scenario 3: branch delete failure logs warning and main flow continues"
MOCK_GIT_BRANCH_DELETE_FAIL=1
FOLLOWUP_EXECUTED=0
cleanup_merged_branch "main" "feature/test-issue"
FOLLOWUP_EXECUTED=1
assert_contains "delete warning logged" "$WORK_DIR/terminal.log" "删除本地分支 feature/test-issue 失败"
assert_contains "delete failure log recorded" "$WORK_DIR/terminal.log" "branch cleanup: git branch -D feature/test-issue failed"
assert_eq "flow continues after delete failure" "1" "$FOLLOWUP_EXECUTED"
teardown_case

setup_case
echo "Scenario 4: missing branch skips delete without warnings"
MOCK_BRANCH_EXISTS=0
cleanup_merged_branch "main" "feature/test-issue"
assert_eq "no delete attempted when branch missing" "0" "$(printf "%b" "$MOCK_GIT_LOG" | grep -c "git branch -D feature/test-issue" || true)"
teardown_case

echo ""
echo "=== Test Summary ==="
echo "Total: $TOTAL, Passed: $PASS, Failed: $FAIL"

if [ $FAIL -gt 0 ]; then
    exit 1
fi

exit 0
