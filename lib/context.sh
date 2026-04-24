#!/bin/bash
# Context overflow detection, compression, and prompt trimming integration.
#
# Required globals: WORK_DIR, CONTEXT_KEEP_RECENT, CONTEXT_COMPRESS_THRESHOLD,
#                   CONTEXT_RETRIES, MAX_CONTEXT_RETRIES, PROMPT_TRIMMED,
#                   CONTEXT_OVERFLOW, CONSECUTIVE_ITERATION_FAILURES, PREVIOUS_FEEDBACK
# Required callbacks: log_console, append_to_progress

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

# 估算 prompt 的 token 数
# 英文约 4 字符/token，中文约 2 字符/token，取混合系数 3 字符/token
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
# 提取维度：完成的工作、修改的文件、关键决策、失败的尝试、Learnings
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

# 压缩上下文：对历史迭代日志生成摘要，保留近期完整日志
# 通过删除/归档旧日志来减小 prompt 组装时的上下文大小
compress_context() {
    local work_dir="$1"

    if [ ! -d "$work_dir" ]; then
        return 1
    fi

    local summaries_dir="$work_dir/summaries"
    mkdir -p "$summaries_dir"

    # 获取所有实现日志并按迭代号排序
    local log_files=()
    while IFS= read -r f; do
        log_files+=("$f")
    done < <(ls -1 "$work_dir"/iteration-*-*.log 2>/dev/null | sort -t'-' -k2 -n)

    local total_logs=${#log_files[@]}
    if [ "$total_logs" -le "$CONTEXT_KEEP_RECENT" ]; then
        log_console "上下文压缩: 日志数量 ($total_logs) <= 保留数量 ($CONTEXT_KEEP_RECENT)，无需压缩"
        return 0
    fi

    # 需要压缩的日志数量 = 总数 - 保留的近期数量
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

# 检查 prompt 大小并在需要时触发预防性压缩
# 返回 0 表示压缩成功或无需压缩，1 表示压缩后仍超限
check_and_compress_prompt() {
    local prompt="$1"
    local work_dir="$2"

    local estimated_tokens
    estimated_tokens=$(estimate_prompt_tokens "$prompt")

    if [ "$estimated_tokens" -lt "$CONTEXT_COMPRESS_THRESHOLD" ]; then
        return 0
    fi

    log_console "⚠️ Prompt 估算 token 数 ($estimated_tokens) 超过阈值 ($CONTEXT_COMPRESS_THRESHOLD)，触发预防性压缩"

    # 渐进式压缩：如果压缩后仍超限，继续压缩更早期的内容
    local compress_round=0
    local max_compress_rounds=3
    local original_keep=$CONTEXT_KEEP_RECENT
    while [ "$estimated_tokens" -ge "$CONTEXT_COMPRESS_THRESHOLD" ] && [ $compress_round -lt $max_compress_rounds ]; do
        compress_round=$((compress_round + 1))
        log_console "📦 预防性压缩第 $compress_round 轮 (CONTEXT_KEEP_RECENT=$CONTEXT_KEEP_RECENT)..."

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
        log_console "⚠️ 预防性压缩后仍超限 ($estimated_tokens >= $CONTEXT_COMPRESS_THRESHOLD)，触发智能 prompt 裁剪"
        # 压缩后仍超限，设置 PROMPT_TRIMMED 标志，让 apply_prompt_trimming() 裁剪后续 prompt
        PROMPT_TRIMMED=1
        return 1
    fi

    return 0
}

# 处理上下文溢出：压缩上下文并保存进度
# 返回 0 表示溢出已处理（调用者应 continue），1 表示非溢出
handle_context_overflow() {
    local iteration="$1"
    local agent_name="$2"
    local log_file="$3"

    if ! detect_context_overflow "$log_file"; then
        return 1
    fi

    CONTEXT_RETRIES=$((CONTEXT_RETRIES + 1))

    if [ $CONTEXT_RETRIES -gt $MAX_CONTEXT_RETRIES ]; then
        log_console "上下文溢出已达最大重试次数 ($MAX_CONTEXT_RETRIES)，计为正常失败"
        return 1
    fi

    log_console "⚠️ 上下文溢出，触发压缩并交接 (第 $CONTEXT_RETRIES/$MAX_CONTEXT_RETRIES 次)"

    # 第一次溢出就充分压缩，确保后续还有 2 次重试空间
    local original_keep=$CONTEXT_KEEP_RECENT
    local compress_round=0
    local max_compress_rounds=5
    while [ $compress_round -lt $max_compress_rounds ]; do
        compress_round=$((compress_round + 1))
        log_console "📦 溢出压缩第 $compress_round 轮 (CONTEXT_KEEP_RECENT=$CONTEXT_KEEP_RECENT)..."
        compress_context "$WORK_DIR"

        # 基于剩余日志实际大小估算是否仍在阈值以上
        local remaining_size=0
        while IFS= read -r f; do
            remaining_size=$(( remaining_size + $(wc -c < "$f" 2>/dev/null || echo 0) ))
        done < <(ls -1 "$WORK_DIR"/iteration-*-*.log 2>/dev/null | sort -t'-' -k2 -n)
        local remaining_tokens=$(( remaining_size / 3 ))

        if [ "$remaining_tokens" -lt "$CONTEXT_COMPRESS_THRESHOLD" ]; then
            log_console "📦 溢出压缩后剩余估算 $remaining_tokens tokens < $CONTEXT_COMPRESS_THRESHOLD，压缩充足"
            break
        fi

        # 仍在阈值以上：加大压缩力度
        CONTEXT_KEEP_RECENT=$((CONTEXT_KEEP_RECENT - 1))
        if [ "$CONTEXT_KEEP_RECENT" -lt 1 ]; then
            CONTEXT_KEEP_RECENT=1
            # 保留数已到最小但仍然超限，截断剩余摘要以进一步缩减
            for sf in "$WORK_DIR"/summaries/*.summary.md; do
                [ -f "$sf" ] && head -c 2000 "$sf" > "$sf.tmp" && mv "$sf.tmp" "$sf"
            done
            # 再做一轮检查
            remaining_size=0
            while IFS= read -r f; do
                remaining_size=$(( remaining_size + $(wc -c < "$f" 2>/dev/null || echo 0) ))
            done < <(ls -1 "$WORK_DIR"/iteration-*-*.log 2>/dev/null | sort -t'-' -k2 -n)
            remaining_tokens=$(( remaining_size / 3 ))
            if [ "$remaining_tokens" -lt "$CONTEXT_COMPRESS_THRESHOLD" ]; then
                log_console "📦 摘要截断后剩余估算 $remaining_tokens tokens < $CONTEXT_COMPRESS_THRESHOLD"
                break
            fi
            log_console "⚠️ 溢出压缩后仍超限 ($remaining_tokens >= $CONTEXT_COMPRESS_THRESHOLD)，依赖 prompt 裁剪兜底"
            break
        fi
    done
    CONTEXT_KEEP_RECENT=$original_keep

    # 保存进度到 progress.md
    append_to_progress "$iteration" "$agent_name" "$log_file" "N/A" "上下文溢出交接" ""

    # 设置下一次迭代的反馈
    PREVIOUS_FEEDBACK="上一次迭代因上下文溢出中断。请继续当前子任务的实现，参考 progress.md 中的进度记录。"

    # 不计入连续失败（这不是实现失败，是资源限制）
    CONSECUTIVE_ITERATION_FAILURES=0

    # 记录到日志
    echo "- 上下文溢出: 压缩并交接 (第 $CONTEXT_RETRIES/$MAX_CONTEXT_RETRIES 次)" >> "$WORK_DIR/log.md"

    CONTEXT_OVERFLOW=1
    # 设置多级裁剪策略：根据溢出次数调整裁剪力度
    if [ $CONTEXT_RETRIES -eq 1 ]; then
        PROMPT_TRIMMED=1  # 轻度裁剪
    elif [ $CONTEXT_RETRIES -eq 2 ]; then
        PROMPT_TRIMMED=2  # 中度裁剪
    else
        PROMPT_TRIMMED=3  # 重度裁剪
    fi

    return 0
}
