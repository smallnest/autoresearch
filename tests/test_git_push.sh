#!/bin/bash
# tests/test_git_push.sh - Unit tests for git push failure handling
#
# Tests verify:
# 1. `git push` first failure doesn't exit due to `set -e`
# 2. Failure info goes to `WORK_DIR/log.md`
# 3. Uncommitted changes trigger stash and retry, retry failure still outputs suggestions
#
# Usage: bash tests/test_git_push.sh

set -e

PASS=0
FAIL=0
TOTAL=0

WORK_ROOT=""
WORK_DIR=""

# Mock git command
MOCK_GIT_PUSH_FAIL=0
MOCK_GIT_PUSH_RETRY_FAIL=0
MOCK_GIT_HAS_UNCOMMITTED=0
MOCK_GIT_LOG=""

git() {
    MOCK_GIT_LOG="${MOCK_GIT_LOG}git $*$'\n'"

    case "$1" in
        push)
            if [ $MOCK_GIT_PUSH_FAIL -eq 1 ]; then
                echo "fatal: unable to access 'https://github.com/': Failed to connect to github.com" >&2
                return 1
            fi
            echo "Push successful"
            return 0
            ;;
        stash)
            if [ "$2" = "push" ]; then
                echo "Saved working directory and index state WIP on feature/test"
                return 0
            elif [ "$2" = "pop" ]; then
                echo "Dropped refs/stash@{0}"
                return 0
            fi
            return 0
            ;;
        diff)
            if [ "$2" = "--quiet" ] || [ "$3" = "--quiet" ]; then
                # Return non-zero if there are uncommitted changes
                if [ $MOCK_GIT_HAS_UNCOMMITTED -eq 1 ]; then
                    return 1
                fi
                return 0
            fi
            return 0
            ;;
        *)
            builtin git "$@"
            ;;
    esac
}

log() {
    :
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
    MOCK_GIT_PUSH_FAIL=0
    MOCK_GIT_PUSH_RETRY_FAIL=0
    MOCK_GIT_HAS_UNCOMMITTED=0
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

# Simulate the git push failure handling logic from run.sh
# Returns 0 on success, 1 on failure
simulate_push_with_failure_handling() {
    local BRANCH_NAME="feature/test-issue"
    local PUSH_OUTPUT
    local PUSH_EXIT_CODE

    # Capture push output (command substitution doesn't trigger set -e exit)
    PUSH_OUTPUT=$(git push -u origin "$BRANCH_NAME" 2>&1) || PUSH_EXIT_CODE=$?

    if [ "${PUSH_EXIT_CODE:-0}" -ne 0 ]; then
        error "git push 失败 (exit code: ${PUSH_EXIT_CODE:-unknown})"
        log_console ""
        log_console "❌ git push 失败！"
        log_console ""
        log_console "错误输出:"
        log_console "$PUSH_OUTPUT"
        log_console ""

        # Record error to log.md
        cat >> "$WORK_DIR/log.md" << EOF

---

## ❌ Git Push 失败

**时间**: $(date '+%Y-%m-%d %H:%M:%S')
**分支**: $BRANCH_NAME
**错误码**: ${PUSH_EXIT_CODE:-unknown}

**错误输出**:
\`\`\`
$PUSH_OUTPUT
\`\`\`

EOF

        # Check for uncommitted changes and retry
        if ! git diff --quiet 2>/dev/null || ! git diff --cached --quiet 2>/dev/null; then
            log_console "检测到未提交的更改，尝试 stash 后重试..."
            STASH_MSG="autoresearch-push-retry-$(date +%s)"
            git stash push -m "$STASH_MSG" 2>/dev/null

            log_console "重试 git push..."
            local RETRY_OUTPUT
            local RETRY_EXIT_CODE
            RETRY_OUTPUT=$(git push -u origin "$BRANCH_NAME" 2>&1) || RETRY_EXIT_CODE=$?

            if [ "${RETRY_EXIT_CODE:-0}" -eq 0 ]; then
                log_console "✅ Stash 后重试成功！"
                git stash pop 2>/dev/null || true
                return 0
            else
                # Retry still failed, restore stash and output suggestions
                git stash pop 2>/dev/null || true

                log_console "❌ 重试仍然失败"
                log_console ""

                # Append retry failure info to log.md
                cat >> "$WORK_DIR/log.md" << EOF

**重试结果**: 失败 (exit code: ${RETRY_EXIT_CODE:-unknown})

**重试输出**:
\`\`\`
$RETRY_OUTPUT
\`\`\`

EOF
            fi
        fi

        # Output recovery suggestions
        log_console ""
        log_console "═══════════════════════════════════════════════════════════"
        log_console "📋 恢复建议："
        log_console "═══════════════════════════════════════════════════════════"
        log_console ""
        log_console "1. 检查网络连接和 GitHub 访问"
        log_console "2. 检查认证状态: gh auth status"
        log_console "3. 手动推送: git push -u origin $BRANCH_NAME"
        log_console "═══════════════════════════════════════════════════════════"

        return 1
    fi

    return 0
}

trap teardown_case EXIT

echo "=== Git Push Failure Handling Tests ==="
echo ""

# Test 1: First failure doesn't exit due to set -e
setup_case
echo "Scenario 1: git push failure doesn't exit script (set -e compatible)"
MOCK_GIT_PUSH_FAIL=1

# This should not exit the script even with set -e
PUSH_FAILED=0
simulate_push_with_failure_handling || PUSH_FAILED=1

assert_eq "script continued after push failure" "1" "$PUSH_FAILED"
assert_contains "error logged to log.md" "$WORK_DIR/log.md" "Git Push 失败"
assert_contains "error details in log.md" "$WORK_DIR/log.md" "Failed to connect"
teardown_case

# Test 2: Failure info goes to WORK_DIR/log.md
setup_case
echo "Scenario 2: failure info is written to log.md"
MOCK_GIT_PUSH_FAIL=1

simulate_push_with_failure_handling || true

assert_contains "has section header" "$WORK_DIR/log.md" "❌ Git Push 失败"
assert_contains "has timestamp" "$WORK_DIR/log.md" "\*\*时间\*\*"
assert_contains "has branch name" "$WORK_DIR/log.md" "feature/test-issue"
assert_contains "has error code" "$WORK_DIR/log.md" "\*\*错误码\*\*"
assert_contains "has error output" "$WORK_DIR/log.md" "Failed to connect"
teardown_case

# Test 3: Uncommitted changes trigger stash and retry
setup_case
echo "Scenario 3: uncommitted changes trigger stash and retry"
MOCK_GIT_PUSH_FAIL=1
MOCK_GIT_HAS_UNCOMMITTED=1

simulate_push_with_failure_handling || true

assert_contains "stash attempt logged" "$WORK_DIR/terminal.log" "stash"
assert_contains "retry attempt logged" "$WORK_DIR/terminal.log" "重试"
teardown_case

# Test 4: Retry failure still outputs suggestions
setup_case
echo "Scenario 4: retry failure still outputs recovery suggestions"
MOCK_GIT_PUSH_FAIL=1
MOCK_GIT_HAS_UNCOMMITTED=1

simulate_push_with_failure_handling || true

assert_contains "suggestions in terminal.log" "$WORK_DIR/terminal.log" "恢复建议"
assert_contains "manual push command suggested" "$WORK_DIR/terminal.log" "git push -u origin"
assert_contains "retry failure in log.md" "$WORK_DIR/log.md" "重试结果"
teardown_case

# Test 5: Successful push works normally
setup_case
echo "Scenario 5: successful push works normally"
MOCK_GIT_PUSH_FAIL=0

PUSH_RESULT=0
simulate_push_with_failure_handling || PUSH_RESULT=1

assert_eq "push succeeded" "0" "$PUSH_RESULT"
# log.md should be empty (no error logged)
assert_eq "log.md has no errors" "" "$(grep 'Git Push 失败' $WORK_DIR/log.md 2>/dev/null || echo '')"
teardown_case

echo ""
echo "=== Test Summary ==="
echo "Total: $TOTAL, Passed: $PASS, Failed: $FAIL"

if [ $FAIL -gt 0 ]; then
    exit 1
fi

exit 0
