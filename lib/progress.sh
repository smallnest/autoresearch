#!/bin/bash
# Progress tracking: init, append, and retrieve iteration experience logs.
#
# Required globals: WORK_DIR, ISSUE_NUMBER
# Required callbacks: log, register_temp_file

init_progress() {
    local progress_file="$WORK_DIR/progress.md"
    cat > "$progress_file" << EOF
# Issue #$ISSUE_NUMBER 经验日志

## Codebase Patterns

> 此区域汇总最重要的可复用经验和模式。Agent 可在实现过程中更新此区域。

EOF
    log "初始化经验日志: $progress_file"
}

# 从 Agent 输出日志中提取 Learnings 部分
# 优先查找 ## Learnings 区块，否则截取前 30 行非空内容作为摘要
extract_learnings_from_log() {
    local log_file="$1"

    if [ ! -f "$log_file" ]; then
        echo ""
        return
    fi

    # 先清理日志中的无效 UTF-8 字符到临时文件
    local cleaned_file
    cleaned_file=$(mktemp)
    register_temp_file "$cleaned_file"
    iconv -f UTF-8 -t UTF-8 -c "$log_file" > "$cleaned_file" 2>/dev/null || cp "$log_file" "$cleaned_file"

    # 优先提取 ## Learnings 区块
    if grep -q "^## Learnings" "$cleaned_file" 2>/dev/null; then
        sed -n '/^## Learnings/,/^## [^L]/{ /^## [^L]/!p; }' "$cleaned_file" 2>/dev/null | head -50
        rm -f "$cleaned_file"
        return
    fi

    # 回退：截取前 30 行非空内容作为摘要
    grep -vE '^\s*$' "$cleaned_file" 2>/dev/null | head -30
    rm -f "$cleaned_file"
}

# 追加迭代经验到 progress.md
append_to_progress() {
    local iteration="$1"
    local agent_name="$2"
    local log_file="$3"
    local score="${4:-N/A}"
    local entry_type="$5"  # "实现" 或 "审核+修复"
    local review_summary="$6"

    local progress_file="$WORK_DIR/progress.md"
    if [ ! -f "$progress_file" ]; then
        init_progress
    fi

    local date_str
    date_str=$(date '+%Y-%m-%d')

    # 从日志中提取 learnings
    local learnings
    learnings=$(extract_learnings_from_log "$log_file")

    # 清理无效 UTF-8 字符
    learnings=$(printf '%s' "$learnings" | iconv -f UTF-8 -t UTF-8 -c 2>/dev/null || echo "$learnings")

    # 限制 learnings 大小（约 1500 字符）
    local learnings_truncated
    learnings_truncated=$(echo "$learnings" | head -c 1500)
    if [ ${#learnings} -gt 1500 ]; then
        learnings_truncated="${learnings_truncated}

... (内容过长，已截断)"
    fi

    # 构建经验条目
    local entry="
## Iteration $iteration - $date_str

- **Agent**: $agent_name
- **类型**: $entry_type
- **评分**: $score/100
"

    # 如果有审核反馈摘要，追加
    if [ -n "$review_summary" ]; then
        # 清理并截取审核反馈的前 800 字符
        local review_brief
        review_brief=$(printf '%s' "$review_summary" | iconv -f UTF-8 -t UTF-8 -c 2>/dev/null | head -c 800 || echo "$review_summary" | head -c 800)
        entry="$entry
- **审核要点**:

${review_brief}
"
    fi

    # 追加 learnings
    if [ -n "$learnings_truncated" ]; then
        entry="$entry
- **经验与发现**:

${learnings_truncated}
"
    fi

    echo "$entry" >> "$progress_file"
    log "已追加迭代 $iteration 经验到 progress.md"
}

# 获取 progress.md 内容用于 prompt 注入
# 返回 ## Codebase Patterns 区 + 最近的迭代记录
# 如果 summaries/ 目录存在，自动使用摘要替代原始日志内容
get_progress_content() {
    local progress_file="$WORK_DIR/progress.md"
    if [ ! -f "$progress_file" ]; then
        echo ""
        return
    fi

    # 先清理文件中的无效 UTF-8 字符
    local cleaned_file
    cleaned_file=$(mktemp)
    register_temp_file "$cleaned_file"
    iconv -f UTF-8 -t UTF-8 -c "$progress_file" > "$cleaned_file" 2>/dev/null || cp "$progress_file" "$cleaned_file"

    local content
    content=$(cat "$cleaned_file")

    # 如果 summaries/ 目录存在，将原始日志引用替换为摘要引用
    local summaries_dir="$WORK_DIR/summaries"
    if [ -d "$summaries_dir" ]; then
        # 替换 progress.md 中的原始日志引用为摘要引用
        # 匹配格式: [iteration-N-agent.log](./iteration-N-agent.log)
        content=$(echo "$content" | sed -E 's/\[iteration-([0-9]+)-([a-z]+)\.log\]\([^)]+\)/[iteration-\1-\2.summary.md](.\/summaries\/iteration-\1-\2.summary.md)/g')
    fi

    # 安全限制：最大 5000 字符，避免过多 token 消耗
    local max_chars=5000
    local content_len
    content_len=$(echo "$content" | wc -c | tr -d ' ')

    if [ "$content_len" -le "$max_chars" ]; then
        rm -f "$cleaned_file"
        echo "$content"
        return
    fi

    # 超长时：保留 ## Codebase Patterns 区 + 最后 3000 字符
    local patterns_section
    patterns_section=$(awk '/^## Codebase Patterns/,/^## [^C]/{ if (/^## [^C]/) next; print }' "$cleaned_file" 2>/dev/null || echo "")

    local recent_entries
    recent_entries=$(tail -c 3000 "$cleaned_file")

    # 同样对截断后的内容应用摘要替换
    if [ -d "$summaries_dir" ]; then
        recent_entries=$(echo "$recent_entries" | sed -E 's/\[iteration-([0-9]+)-([a-z]+)\.log\]\([^)]+\)/[iteration-\1-\2.summary.md](.\/summaries\/iteration-\1-\2.summary.md)/g')
    fi

    rm -f "$cleaned_file"

    echo "$patterns_section

... (中间迭代记录已省略)

$recent_entries"
}

# 获取格式化的经验注入文本（用于 prompt）
get_progress_section() {
    local content
    content=$(get_progress_content)
    if [ -z "$content" ]; then
        echo ""
        return
    fi
    cat << EOF

## 跨迭代经验

以下是之前迭代中积累的经验和发现，请优先参考，避免重复踩坑：

$content
EOF
}
