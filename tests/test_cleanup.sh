#!/bin/bash
# tests/test_cleanup.sh - Unit tests for global cleanup logic
#
# Usage: bash tests/test_cleanup.sh

set -e

PASS=0
FAIL=0
TOTAL=0

WORK_ROOT=""
WORK_DIR=""
GLOBAL_TEMP_FILES=""
SPINNER_PID=""
SCRIPT_COMPLETED_NORMALLY=0
CLEANUP_ALREADY_RAN=0
DEV_SERVER_CLEANED=0
USE_MOCK_TREE=0
MOCK_PROCESS_TREE=""
MOCK_ALIVE_PIDS=""
KILL_LOG=""

log() {
    :
}

log_console() {
    :
}

kill() {
    if [ "$USE_MOCK_TREE" -eq 1 ]; then
        local signal=""
        local pid=""

        case "$1" in
            -0|-9)
                signal="$1"
                pid="$2"
                ;;
            *)
                pid="$1"
                ;;
        esac

        if [ -z "$pid" ]; then
            return 1
        fi

        if printf '%s\n' "$MOCK_ALIVE_PIDS" | grep -Fxq "$pid"; then
            if [ "$signal" != "-0" ]; then
                MOCK_ALIVE_PIDS=$(printf '%s\n' "$MOCK_ALIVE_PIDS" | grep -Fxv "$pid" || true)
                KILL_LOG="${KILL_LOG}${signal:-TERM}:$pid"$'\n'
            fi
            return 0
        fi

        return 1
    fi

    builtin kill "$@"
}

start_spinner() {
    (
        while true; do
            sleep 1
        done
    ) &
    SPINNER_PID=$!
}

stop_spinner() {
    if [ -n "$SPINNER_PID" ] && kill -0 "$SPINNER_PID" 2>/dev/null; then
        kill "$SPINNER_PID" 2>/dev/null || true
        wait "$SPINNER_PID" 2>/dev/null || true
    fi
    SPINNER_PID=""
}

cleanup_dev_server() {
    DEV_SERVER_CLEANED=1
}

register_temp_file() {
    local temp_path="$1"
    if [ -n "$temp_path" ]; then
        if [ -z "$GLOBAL_TEMP_FILES" ]; then
            GLOBAL_TEMP_FILES="$temp_path"
        else
            GLOBAL_TEMP_FILES="$GLOBAL_TEMP_FILES"$'\n'"$temp_path"
        fi
    fi
}

list_child_pids() {
    local parent_pid="$1"
    local child_pids=""

    if [ "$USE_MOCK_TREE" -eq 1 ]; then
        child_pids=$(printf '%s\n' "$MOCK_PROCESS_TREE" | awk -v ppid="$parent_pid" '$1 == ppid { print $2 }') || child_pids=""
        if [ -n "$child_pids" ]; then
            printf '%s\n' "$child_pids"
        fi
        return 0
    fi

    if command -v pgrep >/dev/null 2>&1; then
        child_pids=$(pgrep -P "$parent_pid" 2>/dev/null) || child_pids=""
    fi

    if [ -z "$child_pids" ] && command -v ps >/dev/null 2>&1; then
        child_pids=$(ps -eo pid=,ppid= 2>/dev/null | awk -v ppid="$parent_pid" '$2 == ppid { print $1 }') || child_pids=""
    fi

    if [ -n "$child_pids" ]; then
        printf '%s\n' "$child_pids"
    fi
}

collect_descendant_pids() {
    local parent_pid="$1"
    local child_pid

    while IFS= read -r child_pid; do
        [ -z "$child_pid" ] && continue
        collect_descendant_pids "$child_pid"
        echo "$child_pid"
    done < <(list_child_pids "$parent_pid")
}

cleanup() {
    local exit_signal="${1:-EXIT}"

    if [ "$CLEANUP_ALREADY_RAN" -eq 1 ]; then
        return 0
    fi
    CLEANUP_ALREADY_RAN=1

    stop_spinner
    cleanup_dev_server

    local descendant_pids
    descendant_pids=$(collect_descendant_pids "$$")
    if [ -n "$descendant_pids" ]; then
        for pid in $descendant_pids; do
            if kill -0 "$pid" 2>/dev/null; then
                kill "$pid" 2>/dev/null || true
            fi
        done
        sleep 1
        for pid in $descendant_pids; do
            if kill -0 "$pid" 2>/dev/null; then
                kill -9 "$pid" 2>/dev/null || true
            fi
        done
    fi

    if [ -n "$GLOBAL_TEMP_FILES" ]; then
        while IFS= read -r temp_path; do
            [ -z "$temp_path" ] && continue
            if [ -d "$temp_path" ]; then
                rm -rf "$temp_path" 2>/dev/null || true
            elif [ -f "$temp_path" ]; then
                rm -f "$temp_path" 2>/dev/null || true
            fi
        done <<< "$GLOBAL_TEMP_FILES"
    fi

    if [ -n "$WORK_DIR" ] && [ -d "$WORK_DIR" ] && [ "$SCRIPT_COMPLETED_NORMALLY" -eq 0 ]; then
        local log_file="$WORK_DIR/log.md"
        {
            echo ""
            echo "---"
            echo ""
            echo "## ⚠️ 脚本被中断"
            echo ""
            echo "- **中断信号**: $exit_signal"
        } >> "$log_file"
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

reset_state() {
    GLOBAL_TEMP_FILES=""
    SPINNER_PID=""
    SCRIPT_COMPLETED_NORMALLY=0
    CLEANUP_ALREADY_RAN=0
    DEV_SERVER_CLEANED=0
    USE_MOCK_TREE=0
    MOCK_PROCESS_TREE=""
    MOCK_ALIVE_PIDS=""
    KILL_LOG=""
}

setup_case() {
    reset_state
    WORK_ROOT=$(mktemp -d)
    WORK_DIR="$WORK_ROOT/work"
    mkdir -p "$WORK_DIR"
    : > "$WORK_DIR/log.md"
}

teardown_case() {
    if [ -n "$WORK_ROOT" ] && [ -d "$WORK_ROOT" ]; then
        rm -rf "$WORK_ROOT"
    fi
    WORK_ROOT=""
    WORK_DIR=""
}

wait_for_pid() {
    local parent_pid="$1"
    local attempts=0
    local child_pid=""

    while [ $attempts -lt 50 ]; do
        child_pid=$(list_child_pids "$parent_pid" | head -n 1 || true)
        if [ -n "$child_pid" ]; then
            echo "$child_pid"
            return 0
        fi
        attempts=$((attempts + 1))
        sleep 0.1
    done
    return 1
}

trap teardown_case EXIT

echo "=== cleanup() Tests ==="
echo ""

setup_case
echo "Scenario 1: abnormal cleanup removes temp paths and logs once"
temp_file="$WORK_ROOT/temp.txt"
temp_dir="$WORK_ROOT/tempdir"
mkdir -p "$temp_dir"
echo "temp" > "$temp_file"
register_temp_file "$temp_file"
register_temp_file "$temp_dir"
cleanup INT
interrupt_count=$(grep -c '^## ⚠️ 脚本被中断' "$WORK_DIR/log.md" || true)
assert_true "temp file removed" "[ ! -f \"$temp_file\" ]"
assert_true "temp dir removed" "[ ! -d \"$temp_dir\" ]"
assert_eq "interrupt log written once" "1" "$interrupt_count"
assert_eq "cleanup_dev_server invoked" "1" "$DEV_SERVER_CLEANED"
teardown_case

setup_case
echo "Scenario 2: normal completion does not write interrupt log"
SCRIPT_COMPLETED_NORMALLY=1
cleanup EXIT
interrupt_count=$(grep -c '^## ⚠️ 脚本被中断' "$WORK_DIR/log.md" || true)
assert_eq "no interrupt log on normal exit" "0" "$interrupt_count"
teardown_case

setup_case
echo "Scenario 3: cleanup is idempotent"
cleanup TERM
cleanup EXIT
interrupt_count=$(grep -c '^## ⚠️ 脚本被中断' "$WORK_DIR/log.md" || true)
assert_eq "duplicate cleanup does not duplicate log" "1" "$interrupt_count"
teardown_case

setup_case
echo "Scenario 4: cleanup stops spinner process"
start_spinner
spinner_pid="$SPINNER_PID"
assert_true "spinner started" "kill -0 \"$spinner_pid\" 2>/dev/null"
cleanup EXIT
assert_true "spinner stopped" "! kill -0 \"$spinner_pid\" 2>/dev/null"
teardown_case

setup_case
echo "Scenario 5: cleanup kills descendant process tree"
USE_MOCK_TREE=1
MOCK_PROCESS_TREE="$$ 61001"$'\n'"61001 61002"$'\n'"61002 61003"
MOCK_ALIVE_PIDS="61001"$'\n'"61002"$'\n'"61003"
cleanup EXIT
assert_true "direct child stopped" "! kill -0 61001 2>/dev/null"
assert_true "grandchild stopped" "! kill -0 61002 2>/dev/null"
assert_true "great-grandchild stopped" "! kill -0 61003 2>/dev/null"
assert_true "descendants killed before parent" "printf '%s' \"$KILL_LOG\" | grep -q 'TERM:61003'"
teardown_case

echo ""
echo "=========================================="
echo "Total: $TOTAL  Passed: $PASS  Failed: $FAIL"
echo "=========================================="

if [ $FAIL -gt 0 ]; then
    exit 1
fi

exit 0
