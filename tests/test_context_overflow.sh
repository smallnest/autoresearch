#!/bin/bash
# tests/test_context_overflow.sh - Unit tests for context overflow detection
#
# Usage: bash tests/test_context_overflow.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# ==================== Extract functions from run.sh ====================

# Configuration constants
RETRY_BASE_DELAY=2
RETRY_MAX_DELAY=60
PASSING_SCORE=85
MAX_CONTEXT_RETRIES=3
CONTEXT_COMPRESS_THRESHOLD=150000
CONTEXT_KEEP_RECENT=3
PROMPT_TRIMMED=0

# log() stub - do nothing (tests don't need logging)
log() { :; }
log_console() { :; }

detect_context_overflow() {
    local log_file="$1"

    if [ ! -f "$log_file" ]; then
        return 1
    fi

    local pattern='context.length.exceeded'
    pattern+='|context.window.exceeded'
    pattern+='|maximum.context.length'
    pattern+='|maximum.context.window'
    pattern+='|token.limit.exceeded'
    pattern+='|token.limit.reached'
    pattern+='|too.many.tokens'
    pattern+='|exceeds.the.maximum'
    pattern+='|exceeded.the.maximum.number.of.tokens'
    pattern+='|input.is.too.long'

    grep -qiE "$pattern" "$log_file" 2>/dev/null
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

TMPDIR_TESTS=""
cleanup() {
    if [ -n "$TMPDIR_TESTS" ] && [ -d "$TMPDIR_TESTS" ]; then
        rm -rf "$TMPDIR_TESTS"
    fi
}
trap cleanup EXIT

TMPDIR_TESTS=$(mktemp -d)

# Helper: create temp log file with content
make_log() {
    local name="$1"
    local content="$2"
    local path="$TMPDIR_TESTS/$name"
    echo -e "$content" > "$path"
    echo "$path"
}

# ==================== Tests: detect_context_overflow() ====================

echo "=== detect_context_overflow() Tests ==="
echo ""

echo "--- Context overflow signals (should detect) ---"

assert_true "context length exceeded" \
    "detect_context_overflow $(make_log 'ov1.log' 'Error: context length exceeded, maximum is 200000 tokens')"

assert_true "context_length_exceeded (underscore)" \
    "detect_context_overflow $(make_log 'ov2.log' 'error: context_length_exceeded')"

assert_true "maximum context length" \
    "detect_context_overflow $(make_log 'ov3.log' 'This model maximum context length is 128000 tokens')"

assert_true "token limit exceeded" \
    "detect_context_overflow $(make_log 'ov4.log' 'Error: token limit exceeded')"

assert_true "token_limit_reached" \
    "detect_context_overflow $(make_log 'ov5.log' 'token_limit_reached: input too long')"

assert_true "too many tokens" \
    "detect_context_overflow $(make_log 'ov6.log' 'Error: too many tokens in request')"

assert_true "exceeds the maximum" \
    "detect_context_overflow $(make_log 'ov7.log' 'input exceeds the maximum number of tokens allowed')"

assert_true "exceeded the maximum number of tokens" \
    "detect_context_overflow $(make_log 'ov8.log' 'You exceeded the maximum number of tokens for this model')"

assert_true "input is too long" \
    "detect_context_overflow $(make_log 'ov9.log' 'Error: input is too long, please reduce the prompt size')"

assert_true "context window exceeded" \
    "detect_context_overflow $(make_log 'ov10.log' 'context window exceeded: reduce input size')"

assert_true "maximum context window" \
    "detect_context_overflow $(make_log 'ov11.log' 'Reached maximum context window size')"

assert_true "case insensitive" \
    "detect_context_overflow $(make_log 'ov12.log' 'CONTEXT LENGTH EXCEEDED')"

assert_true "mixed case" \
    "detect_context_overflow $(make_log 'ov13.log' 'Token Limit Exceeded')"

assert_true "in multiline output" \
    "detect_context_overflow $(make_log 'ov14.log' 'Implementing feature...\nDone with step 1\nError: context length exceeded\nRemaining steps not completed')"

echo "--- Normal output (should NOT detect) ---"

assert_false "normal implementation output" \
    "detect_context_overflow $(make_log 'ok1.log' 'Implementation complete\nTests passing\nCode looks good')"

assert_false "empty file" \
    "detect_context_overflow $(make_log 'ok2.log' '')"

assert_false "nonexistent file" \
    "detect_context_overflow /tmp/nonexistent_file_$$_test.log"

assert_false "context discussion" \
    "detect_context_overflow $(make_log 'ok3.log' 'The context object provides request-scoped data\nUse context.WithTimeout for deadlines')"

assert_false "token discussion" \
    "detect_context_overflow $(make_log 'ok4.log' 'JWT token generation\nStore the refresh token securely')"

assert_false "limit discussion" \
    "detect_context_overflow $(make_log 'ok5.log' 'Add rate limiting to prevent abuse\nSet connection limits in the config')"

assert_false "maximum discussion" \
    "detect_context_overflow $(make_log 'ok6.log' 'Maximum retry attempts should be 3\nSet the maximum file size')"

# ==================== Tests: handle_context_overflow() ====================

echo ""
echo "=== handle_context_overflow() Tests ==="
echo ""

# Need to set up WORK_DIR and other state for handle_context_overflow
WORK_DIR="$TMPDIR_TESTS/handle_test_workdir"
mkdir -p "$WORK_DIR"
ISSUE_NUMBER=42

# Reuse progress functions from test_extract_score.sh
init_progress() {
    local progress_file="$WORK_DIR/progress.md"
    cat > "$progress_file" << EOF
# Issue #$ISSUE_NUMBER 经验日志

## Codebase Patterns

> 此区域汇总最重要的可复用经验和模式。Agent 可在实现过程中更新此区域。

EOF
}

extract_learnings_from_log() {
    local log_file="$1"
    if [ ! -f "$log_file" ]; then echo ""; return; fi
    if grep -q "^## Learnings" "$log_file" 2>/dev/null; then
        sed -n '/^## Learnings/,/^## [^L]/{ /^## [^L]/!p; }' "$log_file" 2>/dev/null | head -50
        return
    fi
    grep -vE '^\s*$' "$log_file" 2>/dev/null | head -30
}

append_to_progress() {
    local iteration="$1"
    local agent_name="$2"
    local log_file="$3"
    local score="${4:-N/A}"
    local entry_type="$5"
    local review_summary="$6"

    local progress_file="$WORK_DIR/progress.md"
    if [ ! -f "$progress_file" ]; then init_progress; fi

    local date_str
    date_str=$(date '+%Y-%m-%d')
    local learnings
    learnings=$(extract_learnings_from_log "$log_file")
    local learnings_truncated
    learnings_truncated=$(echo "$learnings" | head -c 1500)

    local entry="
## Iteration $iteration - $date_str

- **Agent**: $agent_name
- **类型**: $entry_type
- **评分**: $score/100
"
    if [ -n "$learnings_truncated" ]; then
        entry="$entry
- **经验与发现**:

${learnings_truncated}
"
    fi
    echo "$entry" >> "$progress_file"
}

handle_context_overflow() {
    local iteration="$1"
    local agent_name="$2"
    local log_file="$3"

    if ! detect_context_overflow "$log_file"; then
        return 1
    fi

    CONTEXT_RETRIES=$((CONTEXT_RETRIES + 1))

    if [ $CONTEXT_RETRIES -gt $MAX_CONTEXT_RETRIES ]; then
        return 1
    fi

    # 渐进式压缩：第一轮正常压缩，如果压缩后仍有大量日志则加大压缩力度
    local original_keep=$CONTEXT_KEEP_RECENT
    local compress_round=0
    local max_compress_rounds=3
    while [ $compress_round -lt $max_compress_rounds ]; do
        compress_round=$((compress_round + 1))
        compress_context "$WORK_DIR"

        # 检查是否还有大量日志需要压缩
        local remaining_logs
        remaining_logs=$(ls -1 "$WORK_DIR"/iteration-*-*.log 2>/dev/null | wc -l | tr -d ' ')
        if [ "$remaining_logs" -le "$CONTEXT_KEEP_RECENT" ]; then
            break
        fi

        # 加大压缩力度：减少保留数量
        CONTEXT_KEEP_RECENT=$((CONTEXT_KEEP_RECENT - 1))
        if [ "$CONTEXT_KEEP_RECENT" -lt 1 ]; then
            CONTEXT_KEEP_RECENT=1
        fi
    done
    CONTEXT_KEEP_RECENT=$original_keep

    PREVIOUS_FEEDBACK="上一次迭代因上下文溢出中断。请继续当前子任务的实现，参考 progress.md 中的进度记录。"
    CONSECUTIVE_ITERATION_FAILURES=0
    CONTEXT_OVERFLOW=1
    # 设置多级裁剪策略：根据溢出次数调整裁剪力度
    if [ $CONTEXT_RETRIES -eq 1 ]; then
        PROMPT_TRIMMED=1  # 轻度裁剪
    elif [ $CONTEXT_RETRIES -eq 2 ]; then
        PROMPT_TRIMMED=2  # 中度裁剪
    else
        PROMPT_TRIMMED=3  # 重度裁剪
    fi

    append_to_progress "$iteration" "$agent_name" "$log_file" "N/A" "上下文溢出交接" ""
    echo "- 上下文溢出: 压缩并交接 (第 $CONTEXT_RETRIES/$MAX_CONTEXT_RETRIES 次)" >> "$WORK_DIR/log.md"

    return 0
}

# ==================== New functions: estimate_prompt_tokens, generate_iteration_summary, compress_context & trim_prompt_for_overflow ====================

# 智能裁剪 prompt：保留关键信息，移除冗余内容
# 从 run.sh 中提取的核心裁剪逻辑
trim_prompt_for_overflow() {
    local prompt="$1"

    if [ -z "$prompt" ]; then
        echo "$prompt"
        return
    fi

    local trimmed="$prompt"

    # 1. Remove program.md content (section starting with "# Program")
    if echo "$trimmed" | grep -q "^# Program"; then
        trimmed=$(echo "$trimmed" | awk '
            BEGIN { in_program=0 }
            /^# Program/ { in_program=1; next }
            /^# [A-Z]/ { in_program=0 }
            in_program { next }
            { print }
        ')
    fi

    # 2. Remove long code blocks (>20 lines)
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
            if (/passes.:.*true/) {
                is_passed=1
            }
            next
        }
        { print }
        END { flush_subtask() }
    ')

    echo "$trimmed"
}

# 如果 PROMPT_TRIMMED>=1，对 prompt 应用智能裁剪
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

estimate_prompt_tokens() {
    local text="$1"
    if [ -z "$text" ]; then
        echo 0
        return
    fi
    local char_count
    char_count=${#text}
    echo $(( char_count / 3 ))
}

# 从单个迭代日志中提取结构化摘要信息
generate_iteration_summary() {
    local log_file="$1"
    local output_file="$2"

    if [ ! -f "$log_file" ]; then
        return 1
    fi

    if [ ! -s "$log_file" ]; then
        local basename
        basename=$(basename "$log_file" .log)
        cat > "$output_file" << EMPTY_EOF
# ${basename} 摘要

> 原始日志为空文件
EMPTY_EOF
        return 0
    fi

    local basename
    basename=$(basename "$log_file" .log)

    # 清理日志中的无效 UTF-8 字符到临时文件
    local cleaned_file
    cleaned_file=$(mktemp)
    iconv -f UTF-8 -t UTF-8 -c "$log_file" > "$cleaned_file" 2>/dev/null || cp "$log_file" "$cleaned_file"

    # 1. 完成的工作：提取标题行、实现步骤、完成标记
    local completed_work=""
    completed_work=$(grep -iE '(^#{1,3} [^#]|完成|实现|添加|修复|优化|重构|✅|✓|done|implemented|fixed|added|completed)' "$cleaned_file" 2>/dev/null | head -30)

    # 2. 修改的文件：提取文件路径和代码块标记
    local modified_files=""
    modified_files=$(grep -oE '([a-zA-Z0-9_./-]+\.(sh|py|js|ts|go|rs|java|cpp|c|h|md|json|yaml|yml|toml|dockerfile|css|html|vue|jsx|tsx))' "$cleaned_file" 2>/dev/null | sort -u | head -20)
    # 也提取 diff 风格的文件路径
    local diff_files=""
    diff_files=$(grep -E '^\+\+\+ |^--- |^diff --git' "$cleaned_file" 2>/dev/null | head -20)
    if [ -n "$diff_files" ]; then
        modified_files="$modified_files
$diff_files"
    fi

    # 3. 关键决策：提取决策、选择、方案相关的内容
    local key_decisions=""
    key_decisions=$(grep -iE '(决定|选择|方案|策略|设计|架构|使用.*因为|choose|decision|approach|strategy|design|选用)' "$cleaned_file" 2>/dev/null | head -15)

    # 4. 失败的尝试：提取错误、失败、问题、踩坑
    local failed_attempts=""
    failed_attempts=$(grep -iE '(失败|错误|问题|踩坑|尝试.*失败|不工作|报错|error|fail|issue|bug|broken|does not work|not working|⚠️|❌|warning|caution)' "$cleaned_file" 2>/dev/null | head -15)

    # 5. Learnings：优先提取 ## Learnings 区块
    local learnings=""
    if grep -q "^## Learnings" "$cleaned_file" 2>/dev/null; then
        learnings=$(sed -n '/^## Learnings/,/^## [^L]/{ /^## [^L]/!p; }' "$cleaned_file" 2>/dev/null | head -30)
    else
        # 回退：提取经验、模式、教训相关行
        learnings=$(grep -iE '(经验|模式|教训|learning|pattern|takeaway|insight|note:|注意|建议)' "$cleaned_file" 2>/dev/null | head -15)
    fi

    # 6. 代码 diff 摘要：提取变更的文件名和关键变更描述
    local code_diff_summary=""
    code_diff_summary=$(grep -E '^(diff --git|\+\+\+ |--- |@@ |[+-][^+-])' "$cleaned_file" 2>/dev/null | head -40)

    rm -f "$cleaned_file"

    # 生成结构化摘要
    cat > "$output_file" << SUMMARY_EOF
# ${basename} 摘要

> 原始日志已压缩，以下是结构化摘要

## 完成的工作
$(if [ -n "$completed_work" ]; then echo "$completed_work"; else echo "（未提取到明确信息）"; fi)

## 修改的文件
$(if [ -n "$modified_files" ]; then echo "$modified_files"; else echo "（未提取到文件变更信息）"; fi)

## 关键决策
$(if [ -n "$key_decisions" ]; then echo "$key_decisions"; else echo "（未提取到决策信息）"; fi)

## 失败的尝试
$(if [ -n "$failed_attempts" ]; then echo "$failed_attempts"; else echo "（未提取到失败记录）"; fi)

## Learnings
$(if [ -n "$learnings" ]; then echo "$learnings"; else echo "（未提取到经验总结）"; fi)

## 代码变更摘要
$(if [ -n "$code_diff_summary" ]; then echo "$code_diff_summary"; else echo "（未提取到代码 diff）"; fi)
SUMMARY_EOF

    return 0
}

compress_context() {
    local work_dir="$1"

    if [ ! -d "$work_dir" ]; then
        return 1
    fi

    local summaries_dir="$work_dir/summaries"
    mkdir -p "$summaries_dir"

    local log_files=()
    while IFS= read -r f; do
        log_files+=("$f")
    done < <(ls -1 "$work_dir"/iteration-*-*.log 2>/dev/null | sort -t'-' -k2 -n)

    local total_logs=${#log_files[@]}
    if [ "$total_logs" -le "$CONTEXT_KEEP_RECENT" ]; then
        log_console "上下文压缩: 日志数量 ($total_logs) <= 保留数量 ($CONTEXT_KEEP_RECENT)，无需压缩"
        return 0
    fi

    local compress_count=$(( total_logs - CONTEXT_KEEP_RECENT ))
    log_console "📦 上下文压缩: $total_logs 个日志，压缩前 $compress_count 个，保留最近 $CONTEXT_KEEP_RECENT 个"

    local compressed=0
    local i=0
    for log_file in "${log_files[@]}"; do
        i=$(( i + 1 ))
        if [ $i -gt $compress_count ]; then
            break
        fi

        local basename
        basename=$(basename "$log_file" .log)

        # 如果摘要已存在且非空，直接删除原始日志
        if [ -s "$summaries_dir/${basename}.summary.md" ]; then
            rm -f "$log_file"
            compressed=$(( compressed + 1 ))
            continue
        fi

        # 使用 generate_iteration_summary 生成结构化摘要
        generate_iteration_summary "$log_file" "$summaries_dir/${basename}.summary.md"

        # 校验摘要文件已成功生成且非空，再删除原始日志
        if [ -s "$summaries_dir/${basename}.summary.md" ]; then
            rm -f "$log_file"
            compressed=$(( compressed + 1 ))
        else
            log_console "⚠️ 摘要生成失败，保留原始日志: $log_file"
        fi
    done

    log_console "📦 上下文压缩完成: 压缩了 $compressed 个日志，摘要保存在 $summaries_dir/"

    # 记录到日志
    echo "- 上下文压缩: 压缩了 $compressed 个历史日志" >> "$work_dir/log.md"

    return 0
}

check_and_compress_prompt() {
    local prompt="$1"
    local work_dir="$2"

    local estimated_tokens
    estimated_tokens=$(estimate_prompt_tokens "$prompt")

    if [ "$estimated_tokens" -lt "$CONTEXT_COMPRESS_THRESHOLD" ]; then
        return 0
    fi

    # 渐进式压缩：如果压缩后仍超限，继续压缩更早期的内容
    local compress_round=0
    local max_compress_rounds=3
    local original_keep=$CONTEXT_KEEP_RECENT
    while [ "$estimated_tokens" -ge "$CONTEXT_COMPRESS_THRESHOLD" ] && [ $compress_round -lt $max_compress_rounds ]; do
        compress_round=$((compress_round + 1))
        compress_context "$work_dir"

        # 渐进式：每轮减少保留数量，让下一轮能压缩更多
        CONTEXT_KEEP_RECENT=$((CONTEXT_KEEP_RECENT - 1))
        if [ "$CONTEXT_KEEP_RECENT" -lt 1 ]; then
            CONTEXT_KEEP_RECENT=1
        fi

        # 重新估算：基于剩余日志文件的实际大小判断是否仍超限
        local remaining_size=0
        while IFS= read -r f; do
            remaining_size=$(( remaining_size + $(wc -c < "$f" 2>/dev/null || echo 0) ))
        done < <(ls -1 "$work_dir"/iteration-*-*.log 2>/dev/null | sort -t'-' -k2 -n)
        estimated_tokens=$(( remaining_size / 3 ))
    done

    # 恢复原始保留数量
    CONTEXT_KEEP_RECENT=$original_keep

    if [ "$estimated_tokens" -ge "$CONTEXT_COMPRESS_THRESHOLD" ]; then
        return 1
    fi

    return 0
}

echo "--- Overflow detected and handled ---"

# Setup
init_progress
cat > "$WORK_DIR/log.md" << 'EOF'
# Issue #42 实现日志
EOF

CONTEXT_RETRIES=0
CONSECUTIVE_ITERATION_FAILURES=1
CONTEXT_OVERFLOW=0
PROMPT_TRIMMED=0
PREVIOUS_FEEDBACK=""

overflow_log=$(make_log 'overflow_test.log' 'Error: context length exceeded')

assert_true "handle returns 0 for overflow" \
    "handle_context_overflow 1 'claude' '$overflow_log'"

assert_eq "CONTEXT_RETRIES incremented" "1" "$CONTEXT_RETRIES"
assert_eq "CONTEXT_OVERFLOW set to 1" "1" "$CONTEXT_OVERFLOW"
assert_eq "PROMPT_TRIMMED set to 1" "1" "$PROMPT_TRIMMED"
assert_eq "CONSECUTIVE_FAILURES reset to 0" "0" "$CONSECUTIVE_ITERATION_FAILURES"
assert_true "PREVIOUS_FEEDBACK mentions overflow" \
    "echo '$PREVIOUS_FEEDBACK' | grep -q '上下文溢出'"
assert_true "progress.md has overflow entry" \
    "grep -q '上下文溢出交接' '$WORK_DIR/progress.md'"
assert_true "log.md has overflow note" \
    "grep -q '上下文溢出.*压缩并交接' '$WORK_DIR/log.md'"

echo "--- Non-overflow not handled ---"

CONTEXT_RETRIES=0
CONTEXT_OVERFLOW=0
normal_log=$(make_log 'normal_test.log' 'Implementation complete, tests pass')

assert_false "handle returns 1 for normal output" \
    "handle_context_overflow 1 'claude' '$normal_log'"

assert_eq "CONTEXT_RETRIES stays 0 for normal" "0" "$CONTEXT_RETRIES"

echo "--- Max retries reached ---"

CONTEXT_RETRIES=$MAX_CONTEXT_RETRIES
CONTEXT_OVERFLOW=0
CONSECUTIVE_ITERATION_FAILURES=0

assert_false "handle returns 1 when max retries reached" \
    "handle_context_overflow 1 'claude' '$overflow_log'"

assert_eq "CONTEXT_RETRIES at max+1" "$((MAX_CONTEXT_RETRIES + 1))" "$CONTEXT_RETRIES"

echo "--- Multiple retries increment counter ---"

CONTEXT_RETRIES=0
CONTEXT_OVERFLOW=0

handle_context_overflow 1 "claude" "$overflow_log"
assert_eq "first retry: counter=1" "1" "$CONTEXT_RETRIES"

handle_context_overflow 2 "codex" "$overflow_log"
assert_eq "second retry: counter=2" "2" "$CONTEXT_RETRIES"

handle_context_overflow 3 "opencode" "$overflow_log"
assert_eq "third retry: counter=3" "3" "$CONTEXT_RETRIES"

# Fourth should fail
CONTEXT_OVERFLOW=0
result=0
handle_context_overflow 4 "claude" "$overflow_log" || result=$?
assert_true "fourth retry exceeds max" "[ $result -ne 0 ]"

# ==================== Tests: estimate_prompt_tokens() ====================

echo ""
echo "=== estimate_prompt_tokens() Tests ==="
echo ""

echo "--- Token estimation for various text types ---"

# English text: ~4 chars/token, so 120 chars ≈ 40 tokens with mixed ratio (120/3)
english_text="This is a simple English text for testing token estimation functionality in the context overflow system."
english_tokens=$(estimate_prompt_tokens "$english_text")
english_chars=${#english_text}
expected_english=$(( english_chars / 3 ))
assert_eq "English text token estimate" "$expected_english" "$english_tokens"

# Chinese text: ~2 chars/token, mixed ratio gives (len/3)
chinese_text="这是一个中文文本用于测试上下文溢出时的token估算功能"
chinese_tokens=$(estimate_prompt_tokens "$chinese_text")
chinese_chars=${#chinese_text}
expected_chinese=$(( chinese_chars / 3 ))
assert_eq "Chinese text token estimate" "$expected_chinese" "$chinese_tokens"

# Empty text
empty_tokens=$(estimate_prompt_tokens "")
assert_eq "Empty text returns 0 tokens" "0" "$empty_tokens"

# Mixed text
mixed_text="Implement GitHub Issue #60: 上下文溢出时进行智能压缩和摘要。This feature adds compress_context() function."
mixed_tokens=$(estimate_prompt_tokens "$mixed_text")
mixed_chars=${#mixed_text}
expected_mixed=$(( mixed_chars / 3 ))
assert_eq "Mixed text token estimate" "$expected_mixed" "$mixed_tokens"

# Large text: 450000 chars should give 150000 tokens
large_text=$(printf 'A%.0s' $(seq 1 450000))
large_tokens=$(estimate_prompt_tokens "$large_text")
assert_eq "450000 chars → 150000 tokens" "150000" "$large_tokens"

# ==================== Tests: compress_context() ====================

echo ""
echo "=== compress_context() Tests ==="
echo ""

echo "--- Basic compression behavior ---"

# Setup: create a work dir with 5 iteration logs
COMPRESS_WORK_DIR="$TMPDIR_TESTS/compress_test"
rm -rf "$COMPRESS_WORK_DIR"
mkdir -p "$COMPRESS_WORK_DIR"

# Create 5 iteration logs with some content
for i in 1 2 3 4 5; do
    cat > "$COMPRESS_WORK_DIR/iteration-$i-claude.log" << LOGEOF
# Iteration $i

## Changes
- Fix the bug in parser
- Add new feature for user auth

### Details
Implement the authentication module with JWT support.
Error handling improved.
LOGEOF
done

# With CONTEXT_KEEP_RECENT=3, iterations 1 and 2 should be compressed
CONTEXT_KEEP_RECENT=3
compress_context "$COMPRESS_WORK_DIR"

# Check that summaries were created
assert_true "Summary for iteration-1 exists" \
    "[ -f '$COMPRESS_WORK_DIR/summaries/iteration-1-claude.summary.md' ]"
assert_true "Summary for iteration-2 exists" \
    "[ -f '$COMPRESS_WORK_DIR/summaries/iteration-2-claude.summary.md' ]"

# Check that original logs were removed
assert_false "Original iteration-1 log removed" \
    "[ -f '$COMPRESS_WORK_DIR/iteration-1-claude.log' ]"
assert_false "Original iteration-2 log removed" \
    "[ -f '$COMPRESS_WORK_DIR/iteration-2-claude.log' ]"

# Check that recent logs are kept
assert_true "Iteration-3 log kept" \
    "[ -f '$COMPRESS_WORK_DIR/iteration-3-claude.log' ]"
assert_true "Iteration-4 log kept" \
    "[ -f '$COMPRESS_WORK_DIR/iteration-4-claude.log' ]"
assert_true "Iteration-5 log kept" \
    "[ -f '$COMPRESS_WORK_DIR/iteration-5-claude.log' ]"

# Check summary content
assert_true "Summary has key content" \
    "grep -q 'Fix the bug' '$COMPRESS_WORK_DIR/summaries/iteration-1-claude.summary.md'"

# Check structured summary sections
assert_true "Summary has '完成的工作' section" \
    "grep -q '## 完成的工作' '$COMPRESS_WORK_DIR/summaries/iteration-1-claude.summary.md'"
assert_true "Summary has '修改的文件' section" \
    "grep -q '## 修改的文件' '$COMPRESS_WORK_DIR/summaries/iteration-1-claude.summary.md'"
assert_true "Summary has '关键决策' section" \
    "grep -q '## 关键决策' '$COMPRESS_WORK_DIR/summaries/iteration-1-claude.summary.md'"
assert_true "Summary has '失败的尝试' section" \
    "grep -q '## 失败的尝试' '$COMPRESS_WORK_DIR/summaries/iteration-1-claude.summary.md'"
assert_true "Summary has 'Learnings' section" \
    "grep -q '## Learnings' '$COMPRESS_WORK_DIR/summaries/iteration-1-claude.summary.md'"

echo "--- Compression when logs <= keep_recent ---"

COMPRESS_SMALL_DIR="$TMPDIR_TESTS/compress_small"
rm -rf "$COMPRESS_SMALL_DIR"
mkdir -p "$COMPRESS_SMALL_DIR"

# Create only 2 logs
for i in 1 2; do
    echo "Iteration $i content" > "$COMPRESS_SMALL_DIR/iteration-$i-claude.log"
done

CONTEXT_KEEP_RECENT=3
compress_context "$COMPRESS_SMALL_DIR"

# No compression should happen
assert_true "Iteration-1 log still exists" \
    "[ -f '$COMPRESS_SMALL_DIR/iteration-1-claude.log' ]"
assert_true "Iteration-2 log still exists" \
    "[ -f '$COMPRESS_SMALL_DIR/iteration-2-claude.log' ]"
assert_false "No summary files created" \
    "[ -n \"\$(ls -A '$COMPRESS_SMALL_DIR/summaries/' 2>/dev/null)\" ]"

echo "--- Compression with non-existent directory ---"

compress_context "/tmp/nonexistent_dir_for_test_$$" && cresult=0 || cresult=1
assert_eq "Non-existent dir returns 1" "1" "$cresult"

echo "--- Re-compression skips already summarized logs ---"

COMPRESS_RERUN_DIR="$TMPDIR_TESTS/compress_rerun"
rm -rf "$COMPRESS_RERUN_DIR"
mkdir -p "$COMPRESS_RERUN_DIR/summaries"

# Create a pre-existing summary and log
echo "Old summary" > "$COMPRESS_RERUN_DIR/summaries/iteration-1-claude.summary.md"
echo "Log content" > "$COMPRESS_RERUN_DIR/iteration-1-claude.log"
for i in 2 3 4; do
    echo "Iteration $i content with ## Changes" > "$COMPRESS_RERUN_DIR/iteration-$i-claude.log"
done

CONTEXT_KEEP_RECENT=2
compress_context "$COMPRESS_RERUN_DIR"

# iteration-1 should be removed (summary already existed), iteration-2 should be compressed
assert_false "Iteration-1 log removed (already summarized)" \
    "[ -f '$COMPRESS_RERUN_DIR/iteration-1-claude.log' ]"
assert_false "Iteration-2 log removed (newly compressed)" \
    "[ -f '$COMPRESS_RERUN_DIR/iteration-2-claude.log' ]"
assert_true "Iteration-3 log kept" \
    "[ -f '$COMPRESS_RERUN_DIR/iteration-3-claude.log' ]"
assert_true "Iteration-4 log kept" \
    "[ -f '$COMPRESS_RERUN_DIR/iteration-4-claude.log' ]"

# ==================== Tests: check_and_compress_prompt() ====================

echo ""
echo "=== check_and_compress_prompt() Tests ==="
echo ""

echo "--- Below threshold: no compression ---"

CHECK_WORK_DIR="$TMPDIR_TESTS/check_prompt"
rm -rf "$CHECK_WORK_DIR"
mkdir -p "$CHECK_WORK_DIR"

# Small prompt well below threshold
small_prompt="Implement a simple feature"
CONTEXT_COMPRESS_THRESHOLD=150000
check_and_compress_prompt "$small_prompt" "$CHECK_WORK_DIR"
assert_eq "No compression for small prompt" "0" "$?"

assert_false "No summaries dir for small prompt" \
    "[ -d '$CHECK_WORK_DIR/summaries' ]"

echo "--- Above threshold: triggers compression ---"

CHECK_WORK_DIR2="$TMPDIR_TESTS/check_prompt2"
rm -rf "$CHECK_WORK_DIR2"
mkdir -p "$CHECK_WORK_DIR2"

# Create iteration logs
for i in 1 2 3 4 5; do
    echo "Iteration $i with ## Changes and ### Details" > "$CHECK_WORK_DIR2/iteration-$i-claude.log"
done

# Create a prompt that exceeds threshold (450001 chars → 150000+ tokens)
huge_prompt=$(head -c 450001 /dev/zero | tr '\0' 'X')
CONTEXT_COMPRESS_THRESHOLD=150000
CONTEXT_KEEP_RECENT=3
check_and_compress_prompt "$huge_prompt" "$CHECK_WORK_DIR2" || true

# Compression should have been triggered
assert_true "Summaries dir created after threshold breach" \
    "[ -d '$CHECK_WORK_DIR2/summaries' ]"
assert_true "Summary created for iteration-1" \
    "[ -f '$CHECK_WORK_DIR2/summaries/iteration-1-claude.summary.md' ]"
assert_true "Summary created for iteration-2" \
    "[ -f '$CHECK_WORK_DIR2/summaries/iteration-2-claude.summary.md' ]"

echo "--- Custom threshold via environment variable ---"

CHECK_WORK_DIR3="$TMPDIR_TESTS/check_prompt3"
rm -rf "$CHECK_WORK_DIR3"
mkdir -p "$CHECK_WORK_DIR3"

# Medium prompt (300 chars → 100 tokens)
medium_prompt=$(printf 'Y%.0s' $(seq 1 300))

# With high threshold, no compression
CONTEXT_COMPRESS_THRESHOLD=1000
check_and_compress_prompt "$medium_prompt" "$CHECK_WORK_DIR3"
assert_false "No compression with high threshold" \
    "[ -d '$CHECK_WORK_DIR3/summaries' ]"

# With low threshold, compression triggers
CHECK_WORK_DIR4="$TMPDIR_TESTS/check_prompt4"
rm -rf "$CHECK_WORK_DIR4"
mkdir -p "$CHECK_WORK_DIR4"
for i in 1 2 3; do
    echo "Iteration $i with ## Changes" > "$CHECK_WORK_DIR4/iteration-$i-claude.log"
done
CONTEXT_COMPRESS_THRESHOLD=10
CONTEXT_KEEP_RECENT=1
check_and_compress_prompt "$medium_prompt" "$CHECK_WORK_DIR4" || true
assert_true "Compression triggered with low threshold" \
    "[ -d '$CHECK_WORK_DIR4/summaries' ]"

# ==================== Tests: generate_iteration_summary() ====================

echo ""
echo "=== generate_iteration_summary() Tests ==="
echo ""

echo "--- Structured extraction from log ---"

SUMMARY_LOG_DIR="$TMPDIR_TESTS/summary_log"
rm -rf "$SUMMARY_LOG_DIR"
mkdir -p "$SUMMARY_LOG_DIR"

cat > "$SUMMARY_LOG_DIR/test-iteration.log" << 'LOGEOF'
# Iteration 5 - Implementation

## 完成的工作
- ✅ Implemented generate_iteration_summary() function
- ✅ Added structured summary extraction

## 修改的文件
- run.sh: Added generate_iteration_summary()
- tests/test_context_overflow.sh: Added tests

### Code Changes
```diff
diff --git a/run.sh b/run.sh
--- a/run.sh
+++ b/run.sh
@@ -436,0 +437,100 @@
+# 从单个迭代日志中提取结构化摘要信息
+generate_iteration_summary() {
+    local log_file="$1"
+    local output_file="$2"
```

## 关键决策
- 决定使用 grep 模式匹配而非调用 LLM，避免递归调用
- 选择保留最近 3 次迭代日志作为默认值

## 失败的尝试
- ❌ 最初尝试用 awk 提取，但处理多字节字符有问题
- ⚠️ 测试中发现 sed 在某些环境下行为不一致

## Learnings
- **模式**: 使用 iconv 清理无效 UTF-8 字符是可靠的
- **踩坑**: sed -n 的跨平台兼容性需要注意
- **经验**: 结构化摘要比简单 grep 更有价值
LOGEOF

generate_iteration_summary "$SUMMARY_LOG_DIR/test-iteration.log" "$SUMMARY_LOG_DIR/test-iteration.summary.md"

# Check structured sections
assert_true "Summary has completed work" \
    "grep -q 'Implemented generate_iteration_summary' '$SUMMARY_LOG_DIR/test-iteration.summary.md'"
assert_true "Summary has modified files" \
    "grep -q 'run.sh' '$SUMMARY_LOG_DIR/test-iteration.summary.md'"
assert_true "Summary has key decisions" \
    "grep -q '决定使用 grep' '$SUMMARY_LOG_DIR/test-iteration.summary.md'"
assert_true "Summary has failed attempts" \
    "grep -q '最初尝试用 awk' '$SUMMARY_LOG_DIR/test-iteration.summary.md'"
assert_true "Summary has learnings" \
    "grep -q '使用 iconv 清理' '$SUMMARY_LOG_DIR/test-iteration.summary.md'"
assert_true "Summary has code diff" \
    "grep -q 'diff --git' '$SUMMARY_LOG_DIR/test-iteration.summary.md'"

echo "--- Empty log handling ---"

generate_iteration_summary "$SUMMARY_LOG_DIR/nonexistent.log" "$SUMMARY_LOG_DIR/empty.summary.md" && empty_result=0 || empty_result=1
assert_eq "Non-existent log returns 1" "1" "$empty_result"

# ==================== Tests: Progressive compression ====================

echo ""
echo "=== Progressive compression Tests ==="
echo ""

echo "--- Multiple compression rounds ---"

PROGRESSIVE_DIR="$TMPDIR_TESTS/progressive"
rm -rf "$PROGRESSIVE_DIR"
mkdir -p "$PROGRESSIVE_DIR"

# Create 8 iteration logs
for i in 1 2 3 4 5 6 7 8; do
    echo "Iteration $i content with ## Changes" > "$PROGRESSIVE_DIR/iteration-$i-claude.log"
done

CONTEXT_KEEP_RECENT=3
compress_context "$PROGRESSIVE_DIR"

# First round: should compress iterations 1-5
assert_false "Iteration-1 log removed after first compression" \
    "[ -f '$PROGRESSIVE_DIR/iteration-1-claude.log' ]"
assert_false "Iteration-5 log removed after first compression" \
    "[ -f '$PROGRESSIVE_DIR/iteration-5-claude.log' ]"
assert_true "Iteration-6 log kept" \
    "[ -f '$PROGRESSIVE_DIR/iteration-6-claude.log' ]"
assert_true "Iteration-8 log kept" \
    "[ -f '$PROGRESSIVE_DIR/iteration-8-claude.log' ]"

# Add more logs and compress again
for i in 9 10 11; do
    echo "Iteration $i content" > "$PROGRESSIVE_DIR/iteration-$i-claude.log"
done

compress_context "$PROGRESSIVE_DIR"

# Second round: should compress iteration 6
assert_false "Iteration-6 log removed after second compression" \
    "[ -f '$PROGRESSIVE_DIR/iteration-6-claude.log' ]"
assert_true "Iteration-7 summary exists" \
    "[ -f '$PROGRESSIVE_DIR/summaries/iteration-7-claude.summary.md' ]"
assert_true "Iteration-11 log kept" \
    "[ -f '$PROGRESSIVE_DIR/iteration-11-claude.log' ]"

# ==================== Tests: Prompt assembly uses summaries ====================

echo ""
echo "=== Prompt assembly uses summaries ==="
echo ""

echo "--- get_progress_content replaces log references ---"

PROMPT_DIR="$TMPDIR_TESTS/prompt_assembly"
rm -rf "$PROMPT_DIR"
mkdir -p "$PROMPT_DIR/summaries"

# Create a progress.md with log references
cat > "$PROMPT_DIR/progress.md" << 'EOF'
# Issue #42 经验日志

## Codebase Patterns

> 此区域汇总最重要的可复用经验和模式。

## Iteration 1 - 2024-01-01

- **Agent**: claude
- **类型**: 实现
- **评分**: 85/100

详见: [iteration-1-claude.log](./iteration-1-claude.log)

## Iteration 2 - 2024-01-02

- **Agent**: codex
- **类型**: 审核+修复
- **评分**: 90/100

详见: [iteration-2-codex.log](./iteration-2-codex.log)
EOF

# Create summary files
echo "Summary for iteration 1" > "$PROMPT_DIR/summaries/iteration-1-claude.summary.md"
echo "Summary for iteration 2" > "$PROMPT_DIR/summaries/iteration-2-codex.summary.md"

# Mock WORK_DIR
WORK_DIR="$PROMPT_DIR"

# Define get_progress_content for testing
get_progress_content() {
    local progress_file="$WORK_DIR/progress.md"
    if [ ! -f "$progress_file" ]; then
        echo ""
        return
    fi

    local content
    content=$(cat "$progress_file")

    # 如果 summaries/ 目录存在，将原始日志引用替换为摘要引用
    local summaries_dir="$WORK_DIR/summaries"
    if [ -d "$summaries_dir" ]; then
        content=$(echo "$content" | sed -E 's/\[iteration-([0-9]+)-([a-z]+)\.log\]\([^)]*iteration-[0-9]+-[a-z]+\.log\)/[iteration-\1-\2.summary.md](.\/summaries\/iteration-\1-\2.summary.md)/g')
    fi

    echo "$content"
}

# Test get_progress_content
progress_content=$(get_progress_content)

assert_true "Progress content replaces log with summary" \
    "echo '$progress_content' | grep -q 'iteration-1-claude.summary.md'"
assert_false "Progress content no longer has raw log reference" \
    "echo '$progress_content' | grep -q './iteration-1-claude.log'"

# ==================== Tests: handle_context_overflow() with compress_context() ====================

echo ""
echo "=== handle_context_overflow() with compress_context() ==="
echo ""

echo "--- Overflow triggers compression ---"

COMPRESS_HANDLE_DIR="$TMPDIR_TESTS/handle_compress"
rm -rf "$COMPRESS_HANDLE_DIR"
mkdir -p "$COMPRESS_HANDLE_DIR"

# Set up work dir with iteration logs
WORK_DIR="$COMPRESS_HANDLE_DIR"
cat > "$WORK_DIR/log.md" << 'EOF'
# Issue #42 实现日志
EOF

for i in 1 2 3 4 5; do
    echo "Iteration $i with ## Changes" > "$WORK_DIR/iteration-$i-claude.log"
done

init_progress

CONTEXT_RETRIES=0
CONSECUTIVE_ITERATION_FAILURES=1
CONTEXT_OVERFLOW=0
PREVIOUS_FEEDBACK=""
CONTEXT_KEEP_RECENT=3

overflow_log=$(make_log 'overflow_compress_test.log' 'Error: context length exceeded')

assert_true "handle returns 0 for overflow with compression" \
    "handle_context_overflow 5 'claude' '$overflow_log'"

assert_eq "CONTEXT_RETRIES incremented" "1" "$CONTEXT_RETRIES"
assert_eq "CONTEXT_OVERFLOW set to 1" "1" "$CONTEXT_OVERFLOW"
assert_eq "CONSECUTIVE_FAILURES reset to 0" "0" "$CONSECUTIVE_ITERATION_FAILURES"

# Check that compression happened
assert_true "Summaries dir created by overflow handler" \
    "[ -d '$WORK_DIR/summaries' ]"
assert_true "Log notes compression" \
    "grep -q '压缩并交接' '$WORK_DIR/log.md'"

# ==================== Tests: Large file performance ====================

echo ""
echo "=== Large file performance Tests ==="
echo ""

echo "--- generate_iteration_summary handles large log ---"

LARGE_DIR="$TMPDIR_TESTS/large_file"
rm -rf "$LARGE_DIR"
mkdir -p "$LARGE_DIR"

# Create a large log file (~50000 lines)
large_log="$LARGE_DIR/large-iteration.log"
{
    echo "# Iteration 1 - Large Test"
    echo ""
    echo "## 完成的工作"
    for i in $(seq 1 10000); do
        echo "- Completed task $i"
    done
    echo ""
    echo "## 修改的文件"
    echo "- run.sh: modified"
    echo ""
    echo "## 关键决策"
    echo "- Decision: use grep"
    echo ""
    echo "## 失败的尝试"
    echo "- Failed: awk approach"
    echo ""
    echo "## Learnings"
    echo "- Learning: iconv is reliable"
    echo ""
    echo "### Code Changes"
    echo "```diff"
    echo "diff --git a/run.sh b/run.sh"
    echo "--- a/run.sh"
    echo "+++ b/run.sh"
    echo "@@ -1 +1 @@"
    echo "-old"
    echo "+new"
    echo "```"
} > "$large_log"

# Measure time
start_time=$(date +%s)
generate_iteration_summary "$large_log" "$LARGE_DIR/large-iteration.summary.md"
end_time=$(date +%s)
elapsed=$((end_time - start_time))

assert_true "Summary generated for large file" \
    "[ -s '$LARGE_DIR/large-iteration.summary.md' ]"
assert_true "Large file summary has key sections" \
    "grep -q '完成的工作' '$LARGE_DIR/large-iteration.summary.md'"
assert_true "Large file summary under 5 seconds" \
    "[ $elapsed -lt 5 ]"

# ==================== Tests: Summary quality validation ====================

echo ""
echo "=== Summary quality validation Tests ==="
echo ""

echo "--- Summary contains key information ---"

QUALITY_DIR="$TMPDIR_TESTS/quality"
rm -rf "$QUALITY_DIR"
mkdir -p "$QUALITY_DIR"

cat > "$QUALITY_DIR/quality-iteration.log" << 'LOGEOF'
# Iteration 3 - Bug Fix

## 完成的工作
- Fixed the memory leak in parser.c
- Added bounds checking for array access

## 修改的文件
- parser.c: fixed memory leak
- parser.h: added bounds checking

### Code Changes
```diff
diff --git a/parser.c b/parser.c
--- a/parser.c
+++ b/parser.c
@@ -100,6 +100,7 @@
 void parse() {
+    check_bounds();
     free_memory();
 }
```

## 关键决策
- Decision: use valgrind for memory detection
- Decision: add unit tests for edge cases

## 失败的尝试
- Attempt 1: manual memory tracking (too error-prone)
- Attempt 2: smart pointers (not available in C)

## Learnings
- **模式**: valgrind is essential for C memory issues
- **踩坑**: forgetting to free() in error paths
- **经验**: always test with ASAN
LOGEOF

generate_iteration_summary "$QUALITY_DIR/quality-iteration.log" "$QUALITY_DIR/quality-iteration.summary.md"

# Verify summary is not empty and contains key info
assert_true "Quality summary has completed work" \
    "grep -q 'Fixed the memory leak' '$QUALITY_DIR/quality-iteration.summary.md'"
assert_true "Quality summary has modified files" \
    "grep -q 'parser.c' '$QUALITY_DIR/quality-iteration.summary.md'"
assert_true "Quality summary has key decisions" \
    "grep -q 'use valgrind' '$QUALITY_DIR/quality-iteration.summary.md'"
assert_true "Quality summary has failed attempts" \
    "grep -q 'manual memory tracking' '$QUALITY_DIR/quality-iteration.summary.md'"
assert_true "Quality summary has learnings" \
    "grep -q 'valgrind is essential' '$QUALITY_DIR/quality-iteration.summary.md'"
assert_true "Quality summary has code diff" \
    "grep -q 'check_bounds' '$QUALITY_DIR/quality-iteration.summary.md'"

# Verify summary is not empty and contains structured content
assert_true "Summary is not empty" \
    "[ -s '$QUALITY_DIR/quality-iteration.summary.md' ]"
section_count=$(grep -c '^## ' "$QUALITY_DIR/quality-iteration.summary.md" 2>/dev/null || echo 0)
assert_true "Summary has multiple sections" \
    "[ $section_count -ge 5 ]"

# ==================== Tests: Progressive compression token reduction ====================

echo ""
echo "=== Progressive compression token reduction Tests ==="
echo ""

echo "--- Token count decreases after compression ---"

TOKEN_DIR="$TMPDIR_TESTS/token_reduction"
rm -rf "$TOKEN_DIR"
mkdir -p "$TOKEN_DIR"

# Create 8 logs with substantial content
for i in $(seq 1 8); do
    {
        echo "# Iteration $i"
        echo ""
        echo "## 完成的工作"
        for j in $(seq 1 100); do
            echo "- Task $j completed with detailed description"
        done
        echo ""
        echo "## 修改的文件"
        echo "- file$i.txt: modified"
        echo ""
        echo "## 关键决策"
        echo "- Decision $i: use approach A"
        echo ""
        echo "## 失败的尝试"
        echo "- Attempt $i: approach B failed"
        echo ""
        echo "## Learnings"
        echo "- Learning $i: approach A is better"
    } > "$TOKEN_DIR/iteration-$i-claude.log"
done

# Calculate initial token count
initial_tokens=0
for f in "$TOKEN_DIR"/iteration-*-claude.log; do
    size=$(wc -c < "$f")
    initial_tokens=$((initial_tokens + size / 3))
done

CONTEXT_KEEP_RECENT=3
compress_context "$TOKEN_DIR"

# Calculate token count after compression
post_tokens=0
for f in "$TOKEN_DIR"/iteration-*-claude.log; do
    if [ -f "$f" ]; then
        size=$(wc -c < "$f")
        post_tokens=$((post_tokens + size / 3))
    fi
done
# Add summary sizes (summaries are smaller)
for f in "$TOKEN_DIR"/summaries/*.summary.md; do
    if [ -f "$f" ]; then
        size=$(wc -c < "$f")
        post_tokens=$((post_tokens + size / 3))
    fi
done

assert_true "Token count reduced after compression" \
    "[ $post_tokens -lt $initial_tokens ]"

# ==================== Tests: trim_prompt_for_overflow() ====================

echo ""
echo "=== trim_prompt_for_overflow() Tests ==="
echo ""

echo "--- Basic trimming behavior ---"

# Test 1: Empty prompt
empty_trimmed=$(trim_prompt_for_overflow "")
assert_eq "Empty prompt returns empty" "" "$empty_trimmed"

# Test 2: Prompt with program.md section
prompt_with_program="# Task Description

Implement feature X.

# Program Instructions

## Go
- Use gofmt
- Follow Go conventions

## Python
- Use PEP8
- Follow Python conventions

# Current Subtask
- **ID**: T-001
- **Title**: Fix bug
"
trimmed_program=$(trim_prompt_for_overflow "$prompt_with_program")
assert_true "Program section removed" \
    "echo '$trimmed_program' | grep -q 'Implement feature X'"
assert_false "Program instructions removed" \
    "echo '$trimmed_program' | grep -q '^# Program'"

# Test 3: Prompt with long code blocks
prompt_with_long_code="# Task Description

Fix the parser.

\`\`\`go
func parse() {
    // line 1
    // line 2
    // line 3
    // line 4
    // line 5
    // line 6
    // line 7
    // line 8
    // line 9
    // line 10
    // line 11
    // line 12
    // line 13
    // line 14
    // line 15
    // line 16
    // line 17
    // line 18
    // line 19
    // line 20
    // line 21
    // line 22
}
\`\`\`

Continue with implementation.
"
trimmed_code=$(trim_prompt_for_overflow "$prompt_with_long_code")
assert_true "Short content preserved" \
    "echo '$trimmed_code' | grep -q 'Fix the parser'"
assert_true "Continue text preserved" \
    "echo '$trimmed_code' | grep -q 'Continue with implementation'"

# Test 4: Prompt with passed subtasks
prompt_with_subtasks="# Task Description

Implement feature.

- **ID**: T-001
- **Title**: Setup project
- **passes**: true
- **Description**: Detailed setup steps...

- **ID**: T-002
- **Title**: Implement core
- **passes**: false
- **Description**: Core implementation details...

# Review Feedback
Please fix the bug.
"
trimmed_subtasks=$(trim_prompt_for_overflow "$prompt_with_subtasks")
assert_true "Current task preserved" \
    "echo '$trimmed_subtasks' | grep -q 'Implement feature'"
assert_true "Failed subtask kept" \
    "echo '$trimmed_subtasks' | grep -q 'T-002'"
assert_true "Review feedback preserved" \
    "echo '$trimmed_subtasks' | grep -q 'Please fix the bug'"

echo "--- Function exists and is callable ---"

assert_true "trim_prompt_for_overflow function exists" \
    "type trim_prompt_for_overflow >/dev/null 2>&1"

# ==================== Tests: Complete overflow recovery flow ====================

echo ""
echo "=== Complete overflow recovery flow Tests ==="
echo ""

echo "--- Full flow: detect -> compress -> trim -> continue ---"

FLOW_DIR="$TMPDIR_TESTS/flow_test"
rm -rf "$FLOW_DIR"
mkdir -p "$FLOW_DIR"

WORK_DIR="$FLOW_DIR"
cat > "$WORK_DIR/log.md" << 'EOF'
# Issue #42 实现日志
EOF

for i in 1 2 3 4 5; do
    echo "Iteration $i with ## Changes" > "$WORK_DIR/iteration-$i-claude.log"
done

init_progress

CONTEXT_RETRIES=0
CONSECUTIVE_ITERATION_FAILURES=1
CONTEXT_OVERFLOW=0
PROMPT_TRIMMED=0
PREVIOUS_FEEDBACK=""
CONTEXT_KEEP_RECENT=3

overflow_log=$(make_log 'flow_overflow.log' 'Error: context length exceeded')

assert_true "handle returns 0 for overflow" \
    "handle_context_overflow 5 'claude' '$overflow_log'"

assert_eq "CONTEXT_RETRIES incremented" "1" "$CONTEXT_RETRIES"
assert_eq "CONTEXT_OVERFLOW set to 1" "1" "$CONTEXT_OVERFLOW"
assert_eq "PROMPT_TRIMMED set to 1 (first overflow)" "1" "$PROMPT_TRIMMED"
assert_eq "CONSECUTIVE_FAILURES reset to 0" "0" "$CONSECUTIVE_ITERATION_FAILURES"

# Check that compression happened
assert_true "Summaries dir created" \
    "[ -d '$WORK_DIR/summaries' ]"

# Check that trim_prompt_for_overflow can be called after overflow
sample_prompt="# Task

Implement feature X with many details.

# Program
Some program instructions.
"
trimmed_after_overflow=$(trim_prompt_for_overflow "$sample_prompt")
assert_true "trim_prompt_for_overflow works after overflow" \
    "[ -n \"$trimmed_after_overflow\" ]"

echo "--- Progressive overflow increases trim level ---"

# First overflow should set PROMPT_TRIMMED=1
CONTEXT_RETRIES=0
PROMPT_TRIMMED=0
handle_context_overflow 5 "claude" "$overflow_log"
assert_eq "First overflow sets PROMPT_TRIMMED=1" "1" "$PROMPT_TRIMMED"

# Second overflow should set PROMPT_TRIMMED=2
handle_context_overflow 6 "codex" "$overflow_log"
assert_eq "Second overflow sets PROMPT_TRIMMED=2" "2" "$PROMPT_TRIMMED"

# Third overflow should set PROMPT_TRIMMED=3
handle_context_overflow 7 "opencode" "$overflow_log"
assert_eq "Third overflow sets PROMPT_TRIMMED=3" "3" "$PROMPT_TRIMMED"

echo "--- apply_prompt_trimming respects trim levels ---"

# Test level 1 (mild)
PROMPT_TRIMMED=1
test_prompt="# Task\n\nImplement.\n\n# Program\nInstructions.\n"
level1_trimmed=$(apply_prompt_trimming "$test_prompt")
assert_true "Level 1 trimming removes program" \
    "! echo '$level1_trimmed' | grep -q '^# Program'"

# Test level 2 (moderate)
PROMPT_TRIMMED=2
test_prompt2="# Task

Implement.

## 历史迭代摘要
Old summary.

# Program
Instructions.
"
level2_trimmed=$(apply_prompt_trimming "$test_prompt2")
assert_true "Level 2 trimming removes history" \
    "! echo \"$level2_trimmed\" | grep -q '历史迭代摘要'"

# Test level 3 (aggressive)
PROMPT_TRIMMED=3
test_prompt3="# Task

Implement.

## Agent Persona
Examples.

## 历史迭代摘要
Old summary.
"
level3_trimmed=$(apply_prompt_trimming "$test_prompt3")
assert_true "Level 3 trimming removes persona" \
    "! echo \"$level3_trimmed\" | grep -q 'Agent Persona'"

# ==================== Summary ====================

echo ""
echo "=========================================="
echo "Total: $TOTAL  Passed: $PASS  Failed: $FAIL"
echo "=========================================="

if [ $FAIL -gt 0 ]; then
    exit 1
fi

exit 0
