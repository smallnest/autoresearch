#!/bin/bash
# tests/test_continue_diverged.sh - Unit tests for continue mode remote branch divergence detection
#
# Tests the divergence detection logic in restore_continue_state():
# - diverged (both ahead and behind)
# - ahead only (local ahead of remote)
# - behind only (local behind remote)
# - no remote tracking branch
#
# Usage: bash tests/test_continue_diverged.sh

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

# ---- extracted function under test ----
# Mirrors the divergence detection logic from restore_continue_state() in run.sh.

check_branch_divergence() {
    local branch="$1"
    local remote_branch="origin/$branch"
    if git show-ref --verify --quiet "refs/remotes/$remote_branch" 2>/dev/null; then
        local rev_count
        rev_count=$(git rev-list --left-right --count "$remote_branch...$branch" 2>/dev/null || echo "0	0")
        local ahead behind
        ahead=$(echo "$rev_count" | awk '{print $2}')
        behind=$(echo "$rev_count" | awk '{print $1}')
        if [ "$ahead" -gt 0 ] && [ "$behind" -gt 0 ]; then
            log_console "⚠️ 本地分支与远程分支已分叉: ahead $ahead, behind $behind"
            log "分支分叉检测: $branch 与 $remote_branch 分叉 (ahead=$ahead, behind=$behind)"
            log_console "建议执行: git rebase $remote_branch 或手动合并后再继续"
        elif [ "$behind" -gt 0 ]; then
            log_console "⚠️ 本地分支落后远程 $behind 个提交"
            log "分支落后检测: $branch 落后 $remote_branch $behind 个提交"
            log_console "建议执行: git pull $remote_branch 后再继续"
        fi
    else
        log "远程分支 $remote_branch 不存在，跳过分叉检测"
    fi
}

# ---- tests ----

echo "=== Continue Mode Branch Divergence Tests ==="
echo ""

# Test 1: No remote tracking branch - skip detection
setup_case
echo "Test 1: no remote tracking branch skips detection"
check_branch_divergence "feature/issue-99"
assert_contains "log mentions skip" "$(cat "$LOG_OUTPUT")" "远程分支 origin/feature/issue-99 不存在，跳过分叉检测"
assert_not_contains "no console warning" "$(cat "$CONSOLE_OUTPUT")" "分叉"
assert_not_contains "no console warning" "$(cat "$CONSOLE_OUTPUT")" "落后"
teardown_case

# Test 2: Behind remote (remote ahead of local)
setup_case
echo "Test 2: local branch behind remote"
# Create a "remote" repo and push the initial branch
REMOTE_ROOT="$WORK_ROOT/remote"
mkdir -p "$REMOTE_ROOT"
cd "$REMOTE_ROOT"
git init -q --bare
cd "$PROJECT_ROOT"
git remote add origin "$REMOTE_ROOT"
git push -q -u origin feature/issue-99
# Add a commit on remote (simulate another user pushing)
git clone -q "$REMOTE_ROOT" "$WORK_ROOT/other"
cd "$WORK_ROOT/other"
git checkout -q feature/issue-99
echo "remote change" > remote.txt
git add remote.txt
git commit -q -m "remote commit"
git push -q origin feature/issue-99
# Back to project, local is now behind
cd "$PROJECT_ROOT"
git fetch -q origin
check_branch_divergence "feature/issue-99"
assert_contains "console warns behind" "$(cat "$CONSOLE_OUTPUT")" "本地分支落后远程"
assert_contains "console suggests pull" "$(cat "$CONSOLE_OUTPUT")" "git pull"
assert_contains "log records behind" "$(cat "$LOG_OUTPUT")" "分支落后检测"
teardown_case

# Test 3: Ahead of remote (local ahead of remote)
setup_case
echo "Test 3: local branch ahead of remote"
REMOTE_ROOT="$WORK_ROOT/remote"
mkdir -p "$REMOTE_ROOT"
cd "$REMOTE_ROOT"
git init -q --bare
cd "$PROJECT_ROOT"
git remote add origin "$REMOTE_ROOT"
git push -q -u origin feature/issue-99
# Add local commit without pushing
echo "local change" > local.txt
git add local.txt
git commit -q -m "local commit"
git fetch -q origin
check_branch_divergence "feature/issue-99"
# ahead > 0, behind == 0  => no warning (only behind triggers warning)
assert_not_contains "no console warning when only ahead" "$(cat "$CONSOLE_OUTPUT")" "分叉"
assert_not_contains "no console warning when only ahead" "$(cat "$CONSOLE_OUTPUT")" "落后"
teardown_case

# Test 4: Diverged (both ahead and behind)
setup_case
echo "Test 4: local and remote diverged"
REMOTE_ROOT="$WORK_ROOT/remote"
mkdir -p "$REMOTE_ROOT"
cd "$REMOTE_ROOT"
git init -q --bare
cd "$PROJECT_ROOT"
git remote add origin "$REMOTE_ROOT"
git push -q -u origin feature/issue-99
# Add remote commit
git clone -q "$REMOTE_ROOT" "$WORK_ROOT/other"
cd "$WORK_ROOT/other"
git checkout -q feature/issue-99
echo "remote change" > remote.txt
git add remote.txt
git commit -q -m "remote commit"
git push -q origin feature/issue-99
# Back to project, add local commit
cd "$PROJECT_ROOT"
git fetch -q origin
echo "local change" > local.txt
git add local.txt
git commit -q -m "local commit"
check_branch_divergence "feature/issue-99"
assert_contains "console warns diverged" "$(cat "$CONSOLE_OUTPUT")" "本地分支与远程分支已分叉"
assert_contains "console shows ahead/behind" "$(cat "$CONSOLE_OUTPUT")" "ahead"
assert_contains "console shows ahead/behind" "$(cat "$CONSOLE_OUTPUT")" "behind"
assert_contains "console suggests rebase" "$(cat "$CONSOLE_OUTPUT")" "git rebase"
assert_contains "log records diverged" "$(cat "$LOG_OUTPUT")" "分支分叉检测"
teardown_case

echo ""
echo "=========================================="
echo "Total: $TOTAL  Passed: $PASS  Failed: $FAIL"
echo "=========================================="

if [ $FAIL -gt 0 ]; then
    exit 1
fi

exit 0
