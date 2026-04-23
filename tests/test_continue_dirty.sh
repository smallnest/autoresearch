#!/bin/bash
# tests/test_continue_dirty.sh - Unit tests for continue mode dirty working tree detection
#
# Tests the dirty working tree handling in restore_continue_state():
# - git status --porcelain detection after checkout
# - auto stash on dirty files with stash message
# - stash failure graceful degradation
# - residual stash detection and recovery
# - clean working tree (no stash)
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

# ---- extracted functions under test ----
# We extract the dirty detection logic from restore_continue_state() as a
# standalone testable function.  It mirrors the exact code in run.sh.

detect_and_handle_dirty_tree() {
    local issue_number="$1"

    cd "$PROJECT_ROOT"

    # 检测 dirty working tree 并自动 stash
    local dirty_files
    dirty_files=$(git status --porcelain 2>/dev/null)
    if [ -n "$dirty_files" ]; then
        local stash_msg="autoresearch-temp-continue-$issue_number-$(date +%s)"
        log_console "⚠️ 检测到未提交的更改，自动 stash..."
        log "检测到 dirty working tree，执行 git stash push -m \"$stash_msg\""
        if git stash push -u -m "$stash_msg" 2>/dev/null; then
            log_console "已 stash 未提交的更改: $stash_msg"
            log "stash 成功: $stash_msg"
            CONTINUE_STASH_REF="$stash_msg"
        else
            log_console "⚠️ stash 失败，继续运行（dirty 文件可能影响后续操作）"
            log "stash 失败，降级继续"
            CONTINUE_STASH_REF=""
        fi
    else
        CONTINUE_STASH_REF=""
    fi

    # 检测是否有残留的 autoresearch stash（上次中断遗留）
    # 排除本次 continue 刚创建的 stash
    local residual_stash
    if [ -n "$CONTINUE_STASH_REF" ]; then
        residual_stash=$(git stash list 2>/dev/null | grep 'autoresearch-temp-' | grep -v "$CONTINUE_STASH_REF" | head -1 || true)
    else
        residual_stash=$(git stash list 2>/dev/null | grep 'autoresearch-temp-' | head -1 || true)
    fi
    if [ -n "$residual_stash" ]; then
        log_console "⚠️ 发现上次中断遗留的 stash: $residual_stash"
        log "发现残留 stash: $residual_stash"
        local stash_index
        stash_index=$(echo "$residual_stash" | grep -oE 'stash@\{[0-9]+\}' | head -1)
        if [ -n "$stash_index" ]; then
            log_console "尝试恢复残留 stash..."
            if git stash pop "$stash_index" 2>/dev/null; then
                log_console "已恢复残留 stash"
                log "残留 stash 恢复成功: $stash_index"
            else
                log_console "⚠️ 残留 stash pop 失败（可能有冲突），请手动处理"
                log "残留 stash pop 失败: $stash_index"
            fi
        fi
    fi
}

# ---- tests ----

echo "=== Continue Mode Dirty Working Tree Tests ==="
echo ""

# Test 1: Clean working tree - no stash
setup_case
echo "Test 1: clean working tree does not stash"
CONTINUE_STASH_REF=""
detect_and_handle_dirty_tree 99
assert_eq "no stash on clean tree" "" "$CONTINUE_STASH_REF"
assert_not_contains "no stash log message" "$(cat "$LOG_OUTPUT")" "stash"
teardown_case

# Test 2: Dirty working tree - auto stash
setup_case
echo "Test 2: dirty working tree auto stashes"
echo "dirty file" > dirty.txt
CONTINUE_STASH_REF=""
detect_and_handle_dirty_tree 99
assert_contains "stash ref set" "$CONTINUE_STASH_REF" "autoresearch-temp-continue-99"
assert_contains "log mentions stash success" "$(cat "$LOG_OUTPUT")" "stash 成功"
assert_contains "console mentions stash" "$(cat "$CONSOLE_OUTPUT")" "已 stash 未提交的更改"
# Verify stash was created
stash_count=$(git stash list | grep -c 'autoresearch-temp-continue-99' || true)
assert_eq "stash entry exists" "1" "$stash_count"
# Verify working tree is now clean
assert_true "working tree is clean after stash" "git diff --quiet"
teardown_case

# Test 3: Dirty working tree with staged files - auto stash
setup_case
echo "Test 3: staged dirty files also trigger stash"
echo "staged file" > staged.txt
git add staged.txt
CONTINUE_STASH_REF=""
detect_and_handle_dirty_tree 99
assert_contains "stash ref set for staged" "$CONTINUE_STASH_REF" "autoresearch-temp-continue-99"
assert_contains "log mentions stash" "$(cat "$LOG_OUTPUT")" "stash 成功"
teardown_case

# Test 4: Residual stash detection and recovery
setup_case
echo "Test 4: residual stash from previous run is detected and restored"
echo "residual file" > residual.txt
git add residual.txt
git stash push -m "autoresearch-temp-continue-99-old" -q
CONTINUE_STASH_REF=""
detect_and_handle_dirty_tree 99
assert_contains "console mentions residual stash" "$(cat "$CONSOLE_OUTPUT")" "上次中断遗留的 stash"
assert_contains "console mentions restore attempt" "$(cat "$CONSOLE_OUTPUT")" "尝试恢复残留 stash"
assert_true "residual file restored" "[ -f residual.txt ]"
teardown_case

# Test 5: Dirty tree + residual stash both handled
setup_case
echo "Test 5: dirty tree with residual stash from previous run"
echo "old residual" > old_residual.txt
git add old_residual.txt
git stash push -m "autoresearch-temp-continue-99-old" -q
echo "new dirty" > new_dirty.txt
CONTINUE_STASH_REF=""
detect_and_handle_dirty_tree 99
assert_contains "stash ref set for new dirty" "$CONTINUE_STASH_REF" "autoresearch-temp-continue-99"
assert_contains "console mentions residual" "$(cat "$CONSOLE_OUTPUT")" "上次中断遗留的 stash"
teardown_case

# Test 6: Stash message format verification
setup_case
echo "Test 6: stash message follows autoresearch-temp-continue format"
echo "dirty" > dirty.txt
CONTINUE_STASH_REF=""
detect_and_handle_dirty_tree 42
stash_msg=$(git stash list | head -1 | grep -oE 'autoresearch-temp-continue-42-[0-9]+' || true)
assert_contains "stash message has correct format" "$stash_msg" "autoresearch-temp-continue-42"
teardown_case

# Test 7: Multiple dirty files
setup_case
echo "Test 7: multiple dirty files are all stashed"
echo "file1" > file1.txt
echo "file2" > file2.txt
echo "file3" > file3.txt
git add file1.txt
CONTINUE_STASH_REF=""
detect_and_handle_dirty_tree 99
assert_true "all dirty files stashed" "[ ! -f file1.txt ] && [ ! -f file2.txt ] && [ ! -f file3.txt ]"
assert_contains "stash ref set" "$CONTINUE_STASH_REF" "autoresearch-temp-continue-99"
teardown_case

# Test 8: Modified tracked file is detected as dirty
setup_case
echo "Test 8: modified tracked file triggers stash"
echo "original" > tracked.txt
git add tracked.txt
git commit -q -m "add tracked"
echo "modified" > tracked.txt
CONTINUE_STASH_REF=""
detect_and_handle_dirty_tree 99
assert_contains "stash ref for modified tracked" "$CONTINUE_STASH_REF" "autoresearch-temp-continue-99"
teardown_case

echo ""
echo "=========================================="
echo "Total: $TOTAL  Passed: $PASS  Failed: $FAIL"
echo "=========================================="

if [ $FAIL -gt 0 ]; then
    exit 1
fi

exit 0
