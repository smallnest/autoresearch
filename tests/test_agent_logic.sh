#!/bin/bash
# tests/test_agent_logic.sh - Unit tests for agent list parsing and rotation
#
# Usage: bash tests/test_agent_logic.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# ==================== Load production functions ====================

# Reuse the same implementation as run.sh to avoid test drift.
# shellcheck source=/dev/null
source "$PROJECT_DIR/lib/agent_logic.sh"

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
    if eval "$cmd"; then
        FAIL=$((FAIL + 1))
        echo "  FAIL: $test_name (expected false, got true)"
    else
        PASS=$((PASS + 1))
        echo "  PASS: $test_name"
    fi
}

# ==================== Tests: parse_agent_list() ====================

echo "=== parse_agent_list() Tests ==="
echo ""

echo "--- Default (empty input) ---"

parse_agent_list ""
assert_eq "default agent count" "3" "${#AGENT_NAMES[@]}"
assert_eq "default first agent" "claude" "${AGENT_NAMES[0]}"
assert_eq "default second agent" "codex" "${AGENT_NAMES[1]}"
assert_eq "default third agent" "opencode" "${AGENT_NAMES[2]}"

echo "--- Custom agent list (no spaces) ---"

parse_agent_list "claude,codex"
assert_eq "two agents count" "2" "${#AGENT_NAMES[@]}"
assert_eq "two agents first" "claude" "${AGENT_NAMES[0]}"
assert_eq "two agents second" "codex" "${AGENT_NAMES[1]}"

parse_agent_list "opencode,claude,codex"
assert_eq "three custom count" "3" "${#AGENT_NAMES[@]}"
assert_eq "three custom first" "opencode" "${AGENT_NAMES[0]}"
assert_eq "three custom second" "claude" "${AGENT_NAMES[1]}"
assert_eq "three custom third" "codex" "${AGENT_NAMES[2]}"

echo "--- Single agent ---"

parse_agent_list "claude"
assert_eq "single agent count" "1" "${#AGENT_NAMES[@]}"
assert_eq "single agent name" "claude" "${AGENT_NAMES[0]}"

echo "--- Input with spaces (trimmed) ---"

parse_agent_list "claude, codex"
assert_eq "space after comma: count" "2" "${#AGENT_NAMES[@]}"
assert_eq "space after comma: first" "claude" "${AGENT_NAMES[0]}"
assert_eq "space after comma: second" "codex" "${AGENT_NAMES[1]}"

parse_agent_list "claude , codex , opencode"
assert_eq "spaces both sides: count" "3" "${#AGENT_NAMES[@]}"
assert_eq "spaces both sides: first" "claude" "${AGENT_NAMES[0]}"
assert_eq "spaces both sides: second" "codex" "${AGENT_NAMES[1]}"
assert_eq "spaces both sides: third" "opencode" "${AGENT_NAMES[2]}"

echo "--- Invalid agent name ---"

rc=0; parse_agent_list "claude,invalid_agent" || rc=$?
assert_false "invalid agent rejected" "[ $rc -eq 0 ]"

rc=0; parse_agent_list "unknown" || rc=$?
assert_false "single invalid agent rejected" "[ $rc -eq 0 ]"

echo "--- Invalid list format (empty entry) ---"

rc=0; parse_agent_list ",claude" || rc=$?
assert_false "leading comma rejected" "[ $rc -eq 0 ]"

rc=0; parse_agent_list "claude," || rc=$?
assert_false "trailing comma rejected" "[ $rc -eq 0 ]"

rc=0; parse_agent_list "claude,,codex" || rc=$?
assert_false "double comma rejected" "[ $rc -eq 0 ]"

echo "--- Duplicate agent (accepted, not blocked) ---"

parse_agent_list "claude,claude"
assert_eq "duplicate agents count" "2" "${#AGENT_NAMES[@]}"
assert_eq "duplicate agents first" "claude" "${AGENT_NAMES[0]}"
assert_eq "duplicate agents second" "claude" "${AGENT_NAMES[1]}"

# ==================== Tests: get_review_agent() ====================

echo ""
echo "=== get_review_agent() Tests ==="
echo ""

echo "--- 3 agents (default) ---"

assert_eq "iter 1, 3 agents" "0" "$(get_review_agent 1 3)"
assert_eq "iter 2, 3 agents" "1" "$(get_review_agent 2 3)"
assert_eq "iter 3, 3 agents" "2" "$(get_review_agent 3 3)"
assert_eq "iter 4, 3 agents (wraps)" "0" "$(get_review_agent 4 3)"
assert_eq "iter 5, 3 agents (wraps)" "1" "$(get_review_agent 5 3)"
assert_eq "iter 6, 3 agents (wraps)" "2" "$(get_review_agent 6 3)"
assert_eq "iter 7, 3 agents (wraps)" "0" "$(get_review_agent 7 3)"

echo "--- 2 agents ---"

assert_eq "iter 1, 2 agents" "0" "$(get_review_agent 1 2)"
assert_eq "iter 2, 2 agents" "1" "$(get_review_agent 2 2)"
assert_eq "iter 3, 2 agents (wraps)" "0" "$(get_review_agent 3 2)"
assert_eq "iter 4, 2 agents (wraps)" "1" "$(get_review_agent 4 2)"

echo "--- 1 agent ---"

assert_eq "iter 1, 1 agent" "0" "$(get_review_agent 1 1)"
assert_eq "iter 2, 1 agent" "0" "$(get_review_agent 2 1)"
assert_eq "iter 5, 1 agent" "0" "$(get_review_agent 5 1)"

echo "--- Rotation with agent names ---"

# Simulate full rotation with 3 agents
AGENT_NAMES=("claude" "codex" "opencode")
num_agents=${#AGENT_NAMES[@]}

for iter in 1 2 3 4 5 6; do
    idx=$(get_review_agent $iter $num_agents)
    # iter 1: agent[0]=claude, iter 2: agent[1]=codex, iter 3: agent[2]=opencode
    # iter 4: agent[0]=claude, iter 5: agent[1]=codex, iter 6: agent[2]=opencode
    case $iter in
        1|4) assert_eq "iter $iter rotates to claude" "claude" "${AGENT_NAMES[$idx]}" ;;
        2|5) assert_eq "iter $iter rotates to codex" "codex" "${AGENT_NAMES[$idx]}" ;;
        3|6) assert_eq "iter $iter rotates to opencode" "opencode" "${AGENT_NAMES[$idx]}" ;;
    esac
done

echo "--- Custom order rotation ---"

AGENT_NAMES=("opencode" "claude" "codex")
num_agents=${#AGENT_NAMES[@]}

idx=$(get_review_agent 1 $num_agents)
assert_eq "custom order iter 1" "opencode" "${AGENT_NAMES[$idx]}"
idx=$(get_review_agent 2 $num_agents)
assert_eq "custom order iter 2" "claude" "${AGENT_NAMES[$idx]}"
idx=$(get_review_agent 3 $num_agents)
assert_eq "custom order iter 3" "codex" "${AGENT_NAMES[$idx]}"
idx=$(get_review_agent 4 $num_agents)
assert_eq "custom order iter 4 wraps" "opencode" "${AGENT_NAMES[$idx]}"

# ==================== Summary ====================

echo ""
echo "=========================================="
echo "Total: $TOTAL  Passed: $PASS  Failed: $FAIL"
echo "=========================================="

if [ $FAIL -gt 0 ]; then
    exit 1
fi

exit 0
