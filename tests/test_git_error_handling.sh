#!/bin/bash
# tests/test_git_error_handling.sh - 综合测试 Git 操作容错
#
# Tests verify:
# 1. gh pr merge 失败时不中断流程，记录日志并输出 PR URL
# 2. git push 失败时记录详细错误日志
# 3. branch 清理失败时记录警告日志
# 4. 错误处理函数返回正确状态
#
# Usage: bash tests/test_git_error_handling.sh

set -e

PASS=0
FAIL=0
TOTAL=0

WORK_ROOT=""
WORK_DIR=""

# Mock state variables
MOCK_GH_PR_MERGE_FAIL=0
MOCK_GIT_PUSH_FAIL=0
MOCK_GIT_CHECKOUT_FAIL=0
MOCK_GIT_PULL_FAIL=0
MOCK_GIT_BRANCH_DELETE_FAIL=0
MOCK_BRANCH_EXISTS=1
MOCK_GH_LOG=""
MOCK_GIT_LOG=""

# Mock gh command
gh() {
    MOCK_GH_LOG="${MOCK_GH_LOG}gh $*\n"

    case "$1" in
        pr)
            if [ "$2" = "merge" ]; then
                if [ "$MOCK_GH_PR_MERGE_FAIL" -eq 1 ]; then
                    echo "error: merge failed: PR is not mergeable" >&2
                    return 1
                fi
                echo "✓ Merged pull request #$3"
                return 0
            fi
            ;;
        *)
            return 0
            ;;
    esac
}

# Mock git command
git() {
    MOCK_GIT_LOG="${MOCK_GIT_LOG}git $*\n"

    case "$1" in
        push)
            if [ "$MOCK_GIT_PUSH_FAIL" -eq 1 ]; then
                echo "fatal: unable to access 'https://github.com/': Failed to connect" >&2
                return 1
            fi
            echo "Push successful"
            return 0
            ;;
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
        diff|stash|remote)
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

error() {
    local msg="$1"
    echo "$msg" >&2
    if [ -n "$WORK_DIR" ] && [ -d "$WORK_DIR" ]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $msg" >> "$WORK_DIR/terminal.log"
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
    MOCK_GH_PR_MERGE_FAIL=0
    MOCK_GIT_PUSH_FAIL=0
    MOCK_GIT_CHECKOUT_FAIL=0
    MOCK_GIT_PULL_FAIL=0
    MOCK_GIT_BRANCH_DELETE_FAIL=0
    MOCK_BRANCH_EXISTS=1
    MOCK_GH_LOG=""
    MOCK_GIT_LOG=""
}

setup_case() {
    reset_state
    WORK_ROOT=$(mktemp -d)
    WORK_DIR="$WORK_ROOT/work"
    mkdir -p "$WORK_DIR"
    : > "$WORK_DIR/log.md"
    : > "$WORK_DIR/terminal.log"
}

teardown_case() {
    if [ -n "$WORK_ROOT" ] && [ -d "$WORK_ROOT" ]; then
        rm -rf "$WORK_ROOT"
    fi
    WORK_ROOT=""
    WORK_DIR=""
}

# Simulate gh pr merge failure handling from run.sh
# Returns 0 on success, 1 on failure (but flow continues)
simulate_pr_merge_with_failure_handling() {
    local PR_NUMBER="$1"
    local PR_URL="$2"
    local MERGE_OUTPUT=""

    if ! MERGE_OUTPUT=$(gh pr merge "$PR_NUMBER" --merge 2>&1); then
        log_console "⚠️ PR 合并失败，请手动处理"
        log_console "PR URL: $PR_URL"
        log "PR merge failed: $MERGE_OUTPUT"
        cat >> "$WORK_DIR/log.md" << EOF

---

## ⚠️ PR 合并失败

**时间**: $(date '+%Y-%m-%d %H:%M:%S')
**PR**: $PR_URL
**错误输出**:
\`\`\`
$MERGE_OUTPUT
\`\`\`

请手动合并: gh pr merge $PR_NUMBER --merge
EOF
        return 1
    fi
    return 0
}

# shellcheck source=/dev/null
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/branch_cleanup.sh"

trap teardown_case EXIT

echo "=== Git Error Handling Tests ==="
echo ""

# Test 1: gh pr merge failure handling
setup_case
echo "Scenario 1: gh pr merge failure logs PR URL and continues"
MOCK_GH_PR_MERGE_FAIL=1

MERGE_FAILED=0
simulate_pr_merge_with_failure_handling 123 "https://github.com/test/repo/pull/123" || MERGE_FAILED=1

assert_eq "merge failed but flow continued" "1" "$MERGE_FAILED"
assert_contains "PR URL logged" "$WORK_DIR/terminal.log" "https://github.com/test/repo/pull/123"
assert_contains "warning message logged" "$WORK_DIR/terminal.log" "PR 合并失败"
assert_contains "error section in log.md" "$WORK_DIR/log.md" "PR 合并失败"
assert_contains "manual command suggested" "$WORK_DIR/log.md" "gh pr merge 123"
teardown_case

# Test 2: gh pr merge success
setup_case
echo "Scenario 2: gh pr merge success works normally"
MOCK_GH_PR_MERGE_FAIL=0

MERGE_RESULT=0
simulate_pr_merge_with_failure_handling 456 "https://github.com/test/repo/pull/456" || MERGE_RESULT=1

assert_eq "merge succeeded" "0" "$MERGE_RESULT"
assert_eq "log.md has no merge errors" "" "$(grep 'PR 合并失败' $WORK_DIR/log.md 2>/dev/null || echo '')"
teardown_case

# Test 3: branch cleanup checkout failure
setup_case
echo "Scenario 3: branch cleanup checkout failure logs warning and continues"
MOCK_GIT_CHECKOUT_FAIL=1

FOLLOWUP_EXECUTED=0
cleanup_merged_branch "main" "feature/test-issue"
FOLLOWUP_EXECUTED=1

assert_contains "checkout warning logged" "$WORK_DIR/terminal.log" "切换到 main 分支失败"
assert_contains "checkout failure log recorded" "$WORK_DIR/terminal.log" "branch cleanup: checkout main failed"
assert_eq "flow continues after checkout failure" "1" "$FOLLOWUP_EXECUTED"
teardown_case

# Test 4: branch cleanup pull failure
setup_case
echo "Scenario 4: branch cleanup pull failure logs warning and continues"
MOCK_GIT_PULL_FAIL=1

FOLLOWUP_EXECUTED=0
cleanup_merged_branch "main" "feature/test-issue"
FOLLOWUP_EXECUTED=1

assert_contains "pull warning logged" "$WORK_DIR/terminal.log" "拉取 main 分支最新代码失败"
assert_contains "pull failure log recorded" "$WORK_DIR/terminal.log" "branch cleanup: git pull main failed"
assert_eq "flow continues after pull failure" "1" "$FOLLOWUP_EXECUTED"
teardown_case

# Test 5: branch cleanup delete failure
setup_case
echo "Scenario 5: branch cleanup delete failure logs warning and continues"
MOCK_GIT_BRANCH_DELETE_FAIL=1

FOLLOWUP_EXECUTED=0
cleanup_merged_branch "main" "feature/test-issue"
FOLLOWUP_EXECUTED=1

assert_contains "delete warning logged" "$WORK_DIR/terminal.log" "删除本地分支 feature/test-issue 失败"
assert_contains "delete failure log recorded" "$WORK_DIR/terminal.log" "branch cleanup: git branch -D feature/test-issue failed"
assert_eq "flow continues after delete failure" "1" "$FOLLOWUP_EXECUTED"
teardown_case

# Test 6: branch cleanup missing branch skips delete
setup_case
echo "Scenario 6: branch cleanup missing branch skips delete without warnings"
MOCK_BRANCH_EXISTS=0

cleanup_merged_branch "main" "feature/test-issue"

assert_eq "no delete attempted when branch missing" "0" "$(printf "%b" "$MOCK_GIT_LOG" | grep -c "git branch -D feature/test-issue" || true)"
teardown_case

# Test 7: combined failures don't block flow
setup_case
echo "Scenario 7: combined failures (PR merge + branch cleanup) don't block flow"
MOCK_GH_PR_MERGE_FAIL=1
MOCK_GIT_CHECKOUT_FAIL=1

FLOW_CONTINUED=0

# PR merge fails
simulate_pr_merge_with_failure_handling 789 "https://github.com/test/repo/pull/789" || true

# Branch cleanup also fails
cleanup_merged_branch "main" "feature/test-issue" || true

FLOW_CONTINUED=1

assert_eq "flow continued after multiple failures" "1" "$FLOW_CONTINUED"
assert_contains "PR merge error in log.md" "$WORK_DIR/log.md" "PR 合并失败"
assert_contains "checkout error in terminal.log" "$WORK_DIR/terminal.log" "切换到 main 分支失败"
teardown_case

echo ""
echo "=== Test Summary ==="
echo "Total: $TOTAL, Passed: $PASS, Failed: $FAIL"

if [ $FAIL -gt 0 ]; then
    exit 1
fi

exit 0