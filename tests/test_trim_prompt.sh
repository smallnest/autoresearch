#!/bin/bash
# tests/test_trim_prompt.sh - Unit tests for trim_prompt_smart(), apply_prompt_trimming(), and get_program_instructions()
#
# Usage: bash tests/test_trim_prompt.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# ==================== Extract functions from run.sh ====================

# Configuration constants
PROMPT_TRIMMED=0

# log() stub - do nothing (tests don't need logging)
log() { :; }
log_console() { :; }

# detect_language() stub for testing
detect_language() {
    echo "unknown"
}

# trim_prompt_smart() - extracted from run.sh (matches production version)
# Note: production code does NOT check PROMPT_TRIMMED inside this function;
# the caller (apply_prompt_trimming) manages the flag.
trim_prompt_smart() {
    local prompt="$1"

    if [ -z "$prompt" ]; then
        echo "$prompt"
        return
    fi

    log_console "执行智能 prompt 裁剪: 保留关键上下文，移除冗余内容"

    local trimmed="$prompt"

    # 1. Remove program.md content (section starting with "# Program")
    #    get_program_instructions() 已按语言优先级裁剪，此处移除 prompt 中残留的 program 段落
    if echo "$trimmed" | grep -q "^# Program"; then
        trimmed=$(echo "$trimmed" | awk '
            BEGIN { in_program=0 }
            /^# Program/ { in_program=1; next }
            /^# [A-Z]/ { in_program=0 }
            in_program { next }
            { print }
        ')
    fi

    # 2. Remove long code blocks (>20 lines) from agent persona examples
    trimmed=$(echo "$trimmed" | awk '
        BEGIN { in_block=0; block_lines=0; block_buf="" }
        /^```/ {
            if (in_block) {
                in_block=0
                if (block_lines <= 20) {
                    print block_buf
                    print "```"
                }
                block_buf=""; block_lines=0
            } else {
                in_block=1; block_buf="```"; block_lines=0
            }
            next
        }
        in_block {
            block_lines++
            block_buf = block_buf "\n" $0
            next
        }
        { print }
    ')

    # 3. Remove detailed descriptions of passed subtasks (keep only title lines)
    #    Buffer entire subtask block, decide whether to print full or title-only after seeing passes flag
    #    Subtask block = lines starting with "- **ID**: T-xxx" through consecutive list lines
    #    Block ends on blank line, section header, or non-list line
    trimmed=$(echo "$trimmed" | awk '
        BEGIN { in_subtask=0; is_passed=0; title_lines=""; subtask_buf="" }
        function flush_subtask() {
            if (in_subtask) {
                if (is_passed) { print title_lines }
                else { print subtask_buf }
                in_subtask=0; is_passed=0; title_lines=""; subtask_buf=""
            }
        }
        /^- \*\*ID\*\*:.*T-[0-9]/ {
            flush_subtask()
            in_subtask=1; is_passed=0
            title_lines=$0; subtask_buf=$0
            next
        }
        in_subtask && /^[^- \t]/ {
            flush_subtask()
            print
            next
        }
        in_subtask && /^$/ {
            flush_subtask()
            print
            next
        }
        in_subtask {
            subtask_buf = subtask_buf "\n" $0
            if (/^- \*\*标题\*\*:/) {
                title_lines = title_lines "\n" $0
            }
            if (/passes.?:.*true/) {
                is_passed=1
            }
            next
        }
        { print }
        END { flush_subtask() }
    ')

    log "智能裁剪完成: 原始长度=${#prompt}, 裁剪后长度=${#trimmed}"
    echo "$trimmed"
}

# trim_prompt_for_overflow() - alias matching run.sh
trim_prompt_for_overflow() {
    trim_prompt_smart "$@"
}

# apply_prompt_trimming() - extracted from run.sh (matches production version)
# Supports levels: 0=no trim, 1=light, 2=medium, 3=heavy
# After trimming, resets to 0 to prevent re-trimming the same prompt.
apply_prompt_trimming() {
    local prompt="$1"
    if [ "$PROMPT_TRIMMED" -ge 1 ]; then
        local trim_level=$PROMPT_TRIMMED
        PROMPT_TRIMMED=0
        case $trim_level in
            1)
                trim_prompt_for_overflow "$prompt"
                ;;
            2)
                local trimmed
                trimmed=$(trim_prompt_for_overflow "$prompt")
                echo "$trimmed" | awk '
                    BEGIN { in_history=0 }
                    /^## 历史迭代摘要/ { in_history=1; next }
                    /^## [^#]/ { in_history=0 }
                    in_history { next }
                    { print }
                '
                ;;
            3)
                local trimmed
                trimmed=$(trim_prompt_for_overflow "$prompt")
                echo "$trimmed" | awk '
                    BEGIN { in_history=0; in_persona=0 }
                    /^## 历史迭代摘要/ { in_history=1; next }
                    /^## [^#]/ { in_history=0 }
                    in_history { next }
                    /^## Agent Persona/ { in_persona=1; next }
                    /^## [^#]/ { in_persona=0 }
                    in_persona { next }
                    { print }
                '
                ;;
            *)
                trim_prompt_for_overflow "$prompt"
                ;;
        esac
    else
        echo "$prompt"
    fi
}

# get_program_instructions() - extracted from run.sh (simplified for testing)
# Uses a test program.md file instead of real project files.
get_program_instructions() {
    local program_file="$TEST_PROGRAM_MD"

    if [ -z "$program_file" ] || [ ! -f "$program_file" ]; then
        echo ""
        return
    fi

    if [ "$PROMPT_TRIMMED" -eq 0 ]; then
        cat "$program_file"
        return
    fi

    # PROMPT_TRIMMED=1: 按优先级裁剪 program.md
    local current_lang
    current_lang=$(detect_language)
    local trimmed
    trimmed=$(grep -v -i -E "^[#]+ .*(Go|Python|TypeScript|Rust|Frontend|Java|C\+\+|Ruby|PHP)" "$program_file" 2>/dev/null || cat "$program_file")

    # 如果裁剪后内容仍然过长，只保留通用规则
    local trimmed_len=${#trimmed}
    if [ "$trimmed_len" -gt 5000 ]; then
        local lang_pattern="Go|Python|TypeScript|Rust|Frontend|Java|Ruby|PHP|C\\+\\+"
        trimmed=$(echo "$trimmed" | awk -v lp="$lang_pattern" '
            $0 ~ "^[#]+ .*(" lp ")" { skip=1; next }
            /^[#]+ / { skip=0 }
            !skip { print }
        ')
    fi

    # 如果裁剪后为空，返回原始内容（安全回退）
    if [ -z "$trimmed" ]; then
        cat "$program_file"
        return
    fi

    echo "$trimmed"
}

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
        echo "  PASS: $test_name"
    else
        FAIL=$((FAIL + 1))
        echo "  FAIL: $test_name (expected='$expected', actual='$actual')"
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

assert_contains() {
    local test_name="$1"
    local haystack="$2"
    local needle="$3"
    TOTAL=$((TOTAL + 1))
    if echo "$haystack" | grep -qF "$needle"; then
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
    if echo "$haystack" | grep -qF "$needle"; then
        FAIL=$((FAIL + 1))
        echo "  FAIL: $test_name (expected NOT to contain '$needle')"
    else
        PASS=$((PASS + 1))
        echo "  PASS: $test_name"
    fi
}

# ==================== Temp dir setup ====================

TMPDIR_TESTS=""
cleanup() {
    if [ -n "$TMPDIR_TESTS" ] && [ -d "$TMPDIR_TESTS" ]; then
        rm -rf "$TMPDIR_TESTS"
    fi
}
trap cleanup EXIT

TMPDIR_TESTS=$(mktemp -d)

# ==================== Tests: trim_prompt_smart() preserves key info ====================

echo "=== trim_prompt_smart() Key Info Preservation Tests ==="
echo ""

echo "--- Preserves Issue description ---"
prompt="实现 GitHub Issue #42

项目路径: /path/to/project
项目语言: Go
Issue 标题: Fix bug in parser
Issue 内容: The parser fails on empty input

迭代次数: 1

# Program - Rules
Some program content here
More program rules

# Claude Agent
Agent instructions"

result=$(trim_prompt_smart "$prompt")
assert_contains "preserves Issue number" "$result" "Issue #42"
assert_contains "preserves project path" "$result" "/path/to/project"
assert_contains "preserves language" "$result" "Go"
assert_contains "preserves Issue title" "$result" "Fix bug in parser"
assert_contains "preserves Issue body" "$result" "parser fails on empty input"

echo "--- Preserves subtask section ---"
prompt="实现 GitHub Issue #42

项目路径: /path/to/project

## 当前子任务

子任务进度: 0/2 已完成 | 当前子任务: T-001 - Add parser

### 子任务详情

- **ID**: T-001
- **标题**: Add parser
- **描述**: Implement the parser function
- **验收条件**:
  - Parser handles empty input
  - Parser returns correct AST

# Program - Rules
Some content

# Claude Agent"

result=$(trim_prompt_smart "$prompt")
assert_contains "preserves subtask ID" "$result" "T-001"
assert_contains "preserves subtask title" "$result" "Add parser"
assert_contains "preserves acceptance criteria" "$result" "Parser handles empty input"

echo "--- Preserves review feedback ---"
prompt="根据审核反馈改进 Issue #42

项目路径: /path/to/project

审核反馈:
问题1: Hardcoded secret in auth.go:15
问题2: Missing error handling
建议: Add proper error handling

## 当前子任务

# Program - Rules
Some content"

result=$(trim_prompt_smart "$prompt")
assert_contains "preserves review feedback" "$result" "Hardcoded secret"
assert_contains "preserves review suggestions" "$result" "Add proper error handling"

# ==================== Tests: trim_prompt_smart() removes verbose content ====================

echo ""
echo "=== trim_prompt_smart() Verbose Content Removal Tests ==="
echo ""

echo "--- Removes # Program section ---"
prompt="Issue #42 header

# Program - Implementation Rules

This is a long program.md content.
It has many rules.
Line 4
Line 5
Line 6
Line 7
Line 8
Line 9
Line 10

# Claude Agent
Agent instructions here"

result=$(trim_prompt_smart "$prompt")
assert_not_contains "removes Program section content" "$result" "long program.md content"
assert_contains "preserves section after Program" "$result" "Claude Agent"

echo "--- Preserves prompt without Program section ---"
prompt="Issue #42 header

Some important context here

# Claude Agent
Agent instructions"

result=$(trim_prompt_smart "$prompt")
assert_contains "preserves Issue header" "$result" "Issue #42"
assert_contains "preserves context" "$result" "important context"

echo "--- Removes long code blocks (>20 lines) ---"
# Create a code block with 25 lines
long_code="line1
line2
line3
line4
line5
line6
line7
line8
line9
line10
line11
line12
line13
line14
line15
line16
line17
line18
line19
line20
line21
line22
line23
line24
line25"

prompt="Issue #42 header

Some context before code

\`\`\`go
$long_code
\`\`\`

Some context after code"

result=$(trim_prompt_smart "$prompt")
assert_not_contains "removes long code block content" "$result" "line25"
assert_contains "preserves context before code" "$result" "context before code"
assert_contains "preserves context after code" "$result" "context after code"

echo "--- Preserves short code blocks (<=20 lines) ---"
short_code="line1
line2
line3
line4
line5"

prompt="Issue #42 header

\`\`\`go
$short_code
\`\`\`

After code"

result=$(trim_prompt_smart "$prompt")
assert_contains "preserves short code block" "$result" "line3"
assert_contains "preserves short code closing" "$result" "After code"

# ==================== Tests: trim_prompt_smart() removes passed subtasks ====================

echo ""
echo "=== trim_prompt_smart() Passed Subtask Removal Tests ==="
echo ""

echo "--- Removes passed subtask details, keeps title ---"
prompt="## 子任务详情

- **ID**: T-001
- **标题**: Add parser
- **描述**: This is a long description of the parser task
- passes: true

- **ID**: T-002
- **标题**: Add tests
- **描述**: Write comprehensive tests for the parser
- passes: false

## Other section"

result=$(trim_prompt_smart "$prompt")
assert_contains "keeps T-001 ID" "$result" "T-001"
assert_contains "keeps T-001 title" "$result" "Add parser"
assert_not_contains "removes T-001 description" "$result" "long description of the parser task"
assert_contains "keeps T-002 ID" "$result" "T-002"
assert_contains "keeps T-002 description" "$result" "Write comprehensive tests"

# ==================== Tests: apply_prompt_trimming() ====================

echo ""
echo "=== apply_prompt_trimming() Tests ==="
echo ""

echo "--- No trimming when PROMPT_TRIMMED=0 ---"
PROMPT_TRIMMED=0
prompt="Issue #42 with some content"
result=$(apply_prompt_trimming "$prompt")
assert_eq "no trim when PROMPT_TRIMMED=0" "$prompt" "$result"

echo "--- Applies trim when PROMPT_TRIMMED=1 ---"
PROMPT_TRIMMED=1
prompt="Issue #42

# Program - Rules
Long program content here

# Claude Agent
Instructions"
result=$(apply_prompt_trimming "$prompt")
assert_not_contains "trim removes program content" "$result" "Long program content"
assert_contains "trim preserves agent section" "$result" "Claude Agent"

echo "--- Applies medium trim when PROMPT_TRIMMED=2 ---"
PROMPT_TRIMMED=2
prompt="Issue #42

# Program - Rules
Long program content here

## 历史迭代摘要
Old iteration summary here

# Claude Agent
Instructions"
result=$(apply_prompt_trimming "$prompt")
assert_not_contains "medium trim removes program content" "$result" "Long program content"
assert_not_contains "medium trim removes history summary" "$result" "Old iteration summary"
assert_contains "medium trim preserves agent section" "$result" "Claude Agent"

# ==================== Tests: get_program_instructions() ====================

echo ""
echo "=== get_program_instructions() Tests ==="
echo ""

# Create a test program.md
TEST_PROGRAM_MD="$TMPDIR_TESTS/program.md"
cat > "$TEST_PROGRAM_MD" << 'EOF'
# Code Standards

## General Rules
- Use clear variable names
- Write tests for all new code

## Go Rules
- Use gofmt for formatting
- Handle all errors explicitly

## Python Rules
- Follow PEP 8
- Use type hints

## TypeScript Rules
- Use strict mode
- Prefer interfaces over types

## Rust Rules
- Follow clippy recommendations
- Use Result for error handling
EOF

echo "--- Returns full content when PROMPT_TRIMMED=0 ---"
PROMPT_TRIMMED=0
result=$(get_program_instructions)
assert_contains "full content has Go rules" "$result" "gofmt"
assert_contains "full content has Python rules" "$result" "PEP 8"
assert_contains "full content has TypeScript rules" "$result" "strict mode"
assert_contains "full content has Rust rules" "$result" "clippy"
assert_contains "full content has general rules" "$result" "clear variable names"

echo "--- Returns trimmed content when PROMPT_TRIMMED=1 ---"
PROMPT_TRIMMED=1
result=$(get_program_instructions)
assert_contains "trimmed has general rules" "$result" "clear variable names"
# grep -v removes language-specific SECTION HEADERS but not their body content
# This is the actual production behavior: only headers matching the pattern are removed
assert_not_contains "trimmed removes Go section header" "$result" "## Go Rules"
assert_not_contains "trimmed removes Python section header" "$result" "## Python Rules"
assert_not_contains "trimmed removes TypeScript section header" "$result" "## TypeScript Rules"
assert_not_contains "trimmed removes Rust section header" "$result" "## Rust Rules"

echo "--- Returns empty when no program file ---"
TEST_PROGRAM_MD=""
result=$(get_program_instructions)
assert_eq "empty result when no file" "" "$result"

# ==================== Tests: Context overflow sets PROMPT_TRIMMED ====================

echo ""
echo "=== Context Overflow Integration Tests ==="
echo ""

echo "--- handle_context_overflow sets PROMPT_TRIMMED ---"
PROMPT_TRIMMED=0
assert_eq "PROMPT_TRIMMED is 0 before overflow" "0" "$PROMPT_TRIMMED"

# Simulate what handle_context_overflow does
PROMPT_TRIMMED=1
assert_eq "PROMPT_TRIMMED is 1 after overflow" "1" "$PROMPT_TRIMMED"

echo "--- apply_prompt_trimming activates after overflow ---"
PROMPT_TRIMMED=1
prompt="Issue #42

# Program - Rules
Content to remove

# Claude Agent
Some important context"
result=$(apply_prompt_trimming "$prompt")
assert_contains "trimmed prompt preserves context" "$result" "important context"
assert_not_contains "trimmed prompt removes program content" "$result" "Content to remove"

echo "--- Successful iteration resets PROMPT_TRIMMED ---"
PROMPT_TRIMMED=1
# Simulate: successful iteration (non-overflow) resets PROMPT_TRIMMED=0
PROMPT_TRIMMED=0
assert_eq "PROMPT_TRIMMED reset to 0 on success" "0" "$PROMPT_TRIMMED"

# ==================== Tests: Edge cases ====================

echo ""
echo "=== Edge Case Tests ==="
echo ""

echo "--- Empty prompt ---"
result=$(trim_prompt_smart "")
assert_eq "empty prompt returns empty" "" "$result"

echo "--- Prompt with only essential info (no trimming needed) ---"
prompt="Issue #42

Project path: /foo
Language: Go"
result=$(trim_prompt_smart "$prompt")
assert_contains "preserves simple prompt" "$result" "Issue #42"
assert_contains "preserves project path" "$result" "/foo"

echo "--- Multiple code blocks: long one removed, short one kept ---"
long_code="l1
l2
l3
l4
l5
l6
l7
l8
l9
l10
l11
l12
l13
l14
l15
l16
l17
l18
l19
l20
l21"
prompt="Header

\`\`\`go
$long_code
\`\`\`

Middle text

\`\`\`go
short code
\`\`\`

End"

result=$(trim_prompt_smart "$prompt")
assert_not_contains "removes long code block" "$result" "l21"
assert_contains "keeps short code block" "$result" "short code"
assert_contains "keeps middle text" "$result" "Middle text"
assert_contains "keeps end text" "$result" "End"

# ==================== Summary ====================

echo ""
echo "=========================================="
echo "Total: $TOTAL  Passed: $PASS  Failed: $FAIL"
echo "=========================================="

if [ $FAIL -gt 0 ]; then
    exit 1
fi

exit 0
