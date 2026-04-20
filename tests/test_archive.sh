#!/bin/bash
# tests/test_archive.sh - Unit tests for archive mechanism
#
# Usage: bash tests/test_archive.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# ==================== Mock Functions & Constants ====================

log() {
    echo "[LOG] $1"
}

# ==================== Extract archive_old_workflows from run.sh ====================

# We extract the function logic to test it in isolation
# Instead of sourcing run.sh which has side effects
archive_old_workflows() {
    local current_issue=$1
    local workflows_dir="$TEST_PROJECT_ROOT/.autoresearch/workflows"
    local archive_dir="$TEST_PROJECT_ROOT/.autoresearch/archive"

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

# ==================== Test Framework ====================

PASS=0
FAIL=0
TOTAL=0

assert_true() {
    local test_name="$1"
    local cmd="$2"
    TOTAL=$((TOTAL + 1))
    if eval "$cmd"; then
        PASS=$((PASS + 1))
        echo "  PASS: $test_name"
    else
        FAIL=$((FAIL + 1))
        echo "  FAIL: $test_name"
    fi
}

assert_exists() {
    local test_name="$1"
    local path="$2"
    assert_true "$test_name" "[ -d \"$path\" ] || [ -f \"$path\" ]"
}

assert_not_exists() {
    local test_name="$1"
    local path="$2"
    assert_true "$test_name" "[ ! -d \"$path\" ] && [ ! -f \"$path\" ]"
}

# ==================== Setup/Teardown ====================

TEST_PROJECT_ROOT=""

setup() {
    TEST_PROJECT_ROOT=$(mktemp -d)
    mkdir -p "$TEST_PROJECT_ROOT/.autoresearch/workflows"
    mkdir -p "$TEST_PROJECT_ROOT/.autoresearch/archive"
}

cleanup() {
    if [ -n "$TEST_PROJECT_ROOT" ] && [ -d "$TEST_PROJECT_ROOT" ]; then
        rm -rf "$TEST_PROJECT_ROOT"
    fi
}

# ==================== Tests ====================

echo "=== archive_old_workflows() Tests ==="
echo ""

# 1. 测试归档多个旧 Issue
setup
echo "Scenario 1: Archive multiple old issues"
mkdir -p "$TEST_PROJECT_ROOT/.autoresearch/workflows/issue-1"
mkdir -p "$TEST_PROJECT_ROOT/.autoresearch/workflows/issue-2"
mkdir -p "$TEST_PROJECT_ROOT/.autoresearch/workflows/issue-3"

archive_old_workflows "3"

current_date=$(date '+%Y-%m-%d')
assert_exists "Issue 1 archived" "$TEST_PROJECT_ROOT/.autoresearch/archive/${current_date}-issue-1"
assert_exists "Issue 2 archived" "$TEST_PROJECT_ROOT/.autoresearch/archive/${current_date}-issue-2"
assert_exists "Issue 3 NOT archived (current)" "$TEST_PROJECT_ROOT/.autoresearch/workflows/issue-3"
assert_not_exists "Issue 1 removed from workflows" "$TEST_PROJECT_ROOT/.autoresearch/workflows/issue-1"
cleanup

# 2. 只有当前 Issue 时不归档
setup
echo "Scenario 2: Only current issue"
mkdir -p "$TEST_PROJECT_ROOT/.autoresearch/workflows/issue-5"
archive_old_workflows "5"
assert_exists "Issue 5 still in workflows" "$TEST_PROJECT_ROOT/.autoresearch/workflows/issue-5"
count=$(ls "$TEST_PROJECT_ROOT/.autoresearch/archive" | wc -l)
assert_true "Archive is empty" "[ $count -eq 0 ]"
cleanup

# 3. workflows 为空时不报错
setup
echo "Scenario 3: Empty workflows"
archive_old_workflows "10"
assert_true "Function exited normally" "true"
cleanup

# 4. 目标目录已存在时追加后缀
setup
echo "Scenario 4: Target exists, add suffix"
mkdir -p "$TEST_PROJECT_ROOT/.autoresearch/workflows/issue-1"
current_date=$(date '+%Y-%m-%d')
mkdir -p "$TEST_PROJECT_ROOT/.autoresearch/archive/${current_date}-issue-1"
touch "$TEST_PROJECT_ROOT/.autoresearch/archive/${current_date}-issue-1/old.txt"

archive_old_workflows "2"

assert_exists "Issue 1 archived with suffix" "$TEST_PROJECT_ROOT/.autoresearch/archive/${current_date}-issue-1-1"
assert_exists "Original archive still exists" "$TEST_PROJECT_ROOT/.autoresearch/archive/${current_date}-issue-1/old.txt"
cleanup

# 5. 测试 --no-archive 标志逻辑 (在 run.sh 中的使用逻辑)
echo "Scenario 5: --no-archive logic check"
# 模拟 run.sh 中的逻辑
check_no_archive() {
    local CONTINUE_MODE=$1
    local NO_ARCHIVE=$2
    local archived=0
    if [ $CONTINUE_MODE -eq 0 ] && [ $NO_ARCHIVE -eq 0 ]; then
        archived=1
    fi
    echo $archived
}

assert_true "Archives when both are 0" "[ $(check_no_archive 0 0) -eq 1 ]"
assert_true "No archive when CONTINUE_MODE=1" "[ $(check_no_archive 1 0) -eq 0 ]"
assert_true "No archive when NO_ARCHIVE=1" "[ $(check_no_archive 0 1) -eq 0 ]"
assert_true "No archive when both are 1" "[ $(check_no_archive 1 1) -eq 0 ]"

# ==================== Summary ====================

echo ""
echo "=========================================="
echo "Total: $TOTAL  Passed: $PASS  Failed: $FAIL"
echo "=========================================="

if [ $FAIL -gt 0 ]; then
    exit 1
fi

exit 0
