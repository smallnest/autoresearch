#!/bin/bash
# tests/test_continue_dirty.sh - Unit tests for continue mode dirty working tree handling
#
# Tests the dirty working tree handling in restore_continue_state():
# - clean working tree (no stash, no action)
# - dirty working tree files are preserved (NOT stashed)
# - residual stash detection warns about old stashes
# - multiple dirty files are preserved
# - modified tracked files are preserved
#
# Usage: bash tests/test_continue_dirty.sh

set -e

PASS=0
FAIL=0
TOTAL=0

# ---- test infrastructure ----

WORK_ROOT=""

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
        echo "  FAIL: $test_name (expected='$expected', actual='$actual')"
    fi
}

assert_contains() {
    local test_name="$1"
    local haystack="$2"
    local needle="$3"
    TOTAL=$((TOTAL + 1))
    if echo "$haystack" | grep -q "$needle"; then
        PASS=$((PASS + 1))
        echo "  PASS: $test_name"
    else
        FAIL=$((FAIL + 1))
        echo "  FAIL: $test_name (expected to contain '$needle')"
    fi
}

assert_not_contains() {
    local test_name="$1"
    local haystack="$2"
    local needle="$3"
    TOTAL=$((TOTAL + 1))
    if echo "$haystack" | grep -q "$needle"; then
        FAIL=$((FAIL + 1))
        echo "  FAIL: $test_name (expected NOT to contain '$needle')"
    else
        PASS=$((PASS + 1))
        echo "  PASS: $test_name"
    fi
}

setup_case() {
    WORK_ROOT=$(mktemp -d)
    PROJECT_ROOT="$WORK_ROOT/project"
    mkdir -p "$PROJECT_ROOT"
    cd "$PROJECT_ROOT"
    git init -q
    git config user.email "test@test.com"
    git config user.name "Test"
    echo "initial" > README.md
    git add .
    git commit -q -m "initial"

    # Create feature branch
    git checkout -q -b feature/issue-99

    # Mock log functions
    LOG_OUTPUT="$WORK_ROOT/log_output.txt"
    : > "$LOG_OUTPUT"
    CONSOLE_OUTPUT="$WORK_ROOT/console_output.txt"
    : > "$CONSOLE_OUTPUT"
}

teardown_case() {
    cd /
    if [ -n "$WORK_ROOT" ] && [ -d "$WORK_ROOT" ]; then
        rm -rf "$WORK_ROOT"
    fi
    WORK_ROOT=""
}

log() {
    echo "$1" >> "$LOG_OUTPUT"
}

log_console() {
    echo "$1" >> "$CONSOLE_OUTPUT"
}

error() {
    echo "ERROR: $1" >> "$CONSOLE_OUTPUT"
}

# ---- extracted function under test ----
# This mirrors the current behavior of restore_continue_state():
# dirty files are preserved (NOT stashed), residual stashes are warned about.

handle_dirty_tree_and_residual_stashes() {
    local issue_number="$1"

    cd "$PROJECT_ROOT"

    # 检测是否有残留的 autoresearch stash（上次中断遗留）
    # 只警告，不自动 pop，避免冲突导致脚本中断
    local residual_stash
    residual_stash=$(git stash list 2>/dev/null | grep 'autoresearch-temp-' | head -1 || true)
    if [ -n "$residual_stash" ]; then
        local stash_index
        stash_index=$(echo "$residual_stash" | grep -oE 'stash@\{[0-9]+\}' | head -1)
        log_console "⚠️ 发现上次中断遗留的 stash: $residual_stash"
        log_console "   如需恢复，请手动执行: git stash pop $stash_index"
        log "发现残留 stash: $residual_stash"
    fi
}

# ---- tests ----

echo "=== Continue Mode Dirty Working Tree Tests ==="
echo ""

# Test 1: Clean working tree - no stash
setup_case
echo "Test 1: clean working tree remains clean"
handle_dirty_tree_and_residual_stashes 99
assert_true "working tree still clean" "git diff --quiet"
assert_not_contains "no stash log message" "$(cat "$LOG_OUTPUT")" "stash"
teardown_case

# Test 2: Dirty working tree - files are NOT stashed, preserved in place
setup_case
echo "Test 2: dirty working tree files are preserved (not stashed)"
echo "dirty file" > dirty.txt
handle_dirty_tree_and_residual_stashes 99
assert_true "dirty file still exists" "[ -f dirty.txt ]"
assert_eq "dirty file content preserved" "dirty file" "$(cat dirty.txt)"
assert_not_contains "no stash was performed" "$(cat "$LOG_OUTPUT")" "stash 成功"
# Verify stash was NOT created
stash_count=$(git stash list | grep -c 'autoresearch-temp-continue-99' || true)
assert_eq "no stash entry was created" "0" "$stash_count"
teardown_case

# Test 3: Staged dirty files are also preserved
setup_case
echo "Test 3: staged dirty files are preserved"
echo "staged file" > staged.txt
git add staged.txt
handle_dirty_tree_and_residual_stashes 99
assert_true "staged file still exists" "[ -f staged.txt ]"
assert_eq "staged file content preserved" "staged file" "$(cat staged.txt)"
teardown_case

# Test 4: Residual stash detection warms about old stashes
setup_case
echo "Test 4: residual stash from previous run is detected with warning"
echo "residual file" > residual.txt
git add residual.txt
git stash push -m "autoresearch-temp-continue-99-old" -q
handle_dirty_tree_and_residual_stashes 99
assert_contains "console warns about residual stash" "$(cat "$CONSOLE_OUTPUT")" "上次中断遗留的 stash"
assert_contains "console shows restore command" "$(cat "$CONSOLE_OUTPUT")" "git stash pop"
assert_not_contains "residual stash not auto-popped" "$(cat "$CONSOLE_OUTPUT")" "已恢复残留 stash"
teardown_case

# Test 5: Dirty tree with residual stash from previous run
setup_case
echo "Test 5: dirty tree files persist while residual stash warning is shown"
echo "old residual" > old_residual.txt
git add old_residual.txt
git stash push -m "autoresearch-temp-continue-99-old" -q
echo "new dirty" > new_dirty.txt
handle_dirty_tree_and_residual_stashes 99
assert_true "new dirty file preserved" "[ -f new_dirty.txt ]"
assert_contains "console warns about residual" "$(cat "$CONSOLE_OUTPUT")" "上次中断遗留的 stash"
teardown_case

# Test 6: Multiple dirty files are all preserved
setup_case
echo "Test 6: multiple dirty files are all preserved"
echo "file1" > file1.txt
echo "file2" > file2.txt
echo "file3" > file3.txt
git add file1.txt
handle_dirty_tree_and_residual_stashes 99
assert_true "all dirty files preserved" "[ -f file1.txt ] && [ -f file2.txt ] && [ -f file3.txt ]"
assert_eq "file1 content" "file1" "$(cat file1.txt)"
assert_eq "file2 content" "file2" "$(cat file2.txt)"
assert_eq "file3 content" "file3" "$(cat file3.txt)"
teardown_case

# Test 7: Modified tracked file is preserved
setup_case
echo "Test 7: modified tracked file is preserved"
echo "original" > tracked.txt
git add tracked.txt
git commit -q -m "add tracked"
echo "modified" > tracked.txt
handle_dirty_tree_and_residual_stashes 99
assert_true "tracked file preserved" "[ -f tracked.txt ]"
assert_eq "modified content preserved" "modified" "$(cat tracked.txt)"
teardown_case

echo ""
echo "=========================================="
echo "Total: $TOTAL  Passed: $PASS  Failed: $FAIL"
echo "=========================================="

if [ $FAIL -gt 0 ]; then
    exit 1
fi

exit 0
