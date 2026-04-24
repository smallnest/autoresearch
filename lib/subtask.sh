#!/bin/bash
# Subtask management: tasks.json CRUD, progress summaries, prompt sections.
#
# Required globals: WORK_DIR
# Required callbacks: log, register_temp_file

# 获取 tasks.json 文件路径
get_tasks_file() {
    echo "$WORK_DIR/tasks.json"
}

# 检查 tasks.json 是否存在且包含子任务
has_subtasks() {
    local tasks_file
    tasks_file=$(get_tasks_file)
    if [ ! -f "$tasks_file" ]; then
        return 1
    fi
    local count
    count=$(jq '.subtasks | length' "$tasks_file" 2>/dev/null)
    [ -n "$count" ] && [ "$count" -gt 0 ]
}

# 获取第一个 passes: false 的子任务信息（JSON 格式）
get_current_subtask() {
    local tasks_file
    tasks_file=$(get_tasks_file)
    if [ ! -f "$tasks_file" ]; then
        echo ""
        return
    fi
    jq '.subtasks | map(select(.passes == false)) | .[0]' "$tasks_file" 2>/dev/null
}

# 获取当前子任务的 ID
get_current_subtask_id() {
    local subtask
    subtask=$(get_current_subtask)
    if [ -z "$subtask" ] || [ "$subtask" = "null" ]; then
        echo ""
        return
    fi
    echo "$subtask" | jq -r '.id' 2>/dev/null
}

# 获取当前子任务的标题
get_current_subtask_title() {
    local subtask
    subtask=$(get_current_subtask)
    if [ -z "$subtask" ] || [ "$subtask" = "null" ]; then
        echo ""
        return
    fi
    echo "$subtask" | jq -r '.title' 2>/dev/null
}

# 校验 tasks.json 的 JSON 有效性
# 返回: 0 = 有效, 1 = 无效或不存在
validate_tasks_json() {
    local tasks_file
    tasks_file=$(get_tasks_file)
    if [ ! -f "$tasks_file" ]; then
        return 1
    fi
    # 空文件视为无效
    if [ ! -s "$tasks_file" ]; then
        return 1
    fi
    jq '.' "$tasks_file" >/dev/null 2>&1
}

# 标记指定子任务为 passes: true（原子写入 + JSON 校验）
mark_subtask_passed() {
    local subtask_id="$1"
    local tasks_file
    tasks_file=$(get_tasks_file)
    if [ ! -f "$tasks_file" ]; then
        return 1
    fi
    # 在 tasks.json 同目录创建临时文件，确保 mv 在同一文件系统上是原子操作
    local tasks_dir
    tasks_dir=$(dirname "$tasks_file")
    local tmp_file
    tmp_file=$(mktemp "${tasks_dir}/tasks.XXXXXX")
    register_temp_file "$tmp_file"

    if ! jq --arg id "$subtask_id" '(.subtasks[] | select(.id == $id)).passes = true' "$tasks_file" > "$tmp_file"; then
        log "❌ 子任务 $subtask_id: jq 处理失败，跳过写入"
        rm -f "$tmp_file"
        return 1
    fi

    # 写入前校验 JSON 有效性
    if ! jq '.' "$tmp_file" >/dev/null 2>&1; then
        log "❌ 子任务 $subtask_id: jq 输出的 JSON 无效，拒绝覆盖 tasks.json"
        rm -f "$tmp_file"
        return 1
    fi

    mv "$tmp_file" "$tasks_file"
    log "子任务 $subtask_id 已标记为通过"
}

# 检查所有子任务是否都已通过
all_subtasks_passed() {
    local tasks_file
    tasks_file=$(get_tasks_file)
    if [ ! -f "$tasks_file" ]; then
        # 无 tasks.json 视为全部通过（兼容旧模式）
        return 0
    fi
    local unfinished
    unfinished=$(jq '[.subtasks[] | select(.passes == false)] | length' "$tasks_file" 2>/dev/null)
    [ "$unfinished" = "0" ]
}

# 检测当前子任务是否为 UI 类型
# 返回: 0 = UI 类型, 1 = 非 UI 类型
is_ui_subtask() {
    local subtask
    subtask=$(get_current_subtask)
    if [ -z "$subtask" ] || [ "$subtask" = "null" ]; then
        return 1
    fi
    local subtask_type
    subtask_type=$(echo "$subtask" | jq -r '.type // "code"' 2>/dev/null)
    [ "$subtask_type" = "ui" ]
}

# 统计 UI 子任务数量
get_ui_subtasks_count() {
    local tasks_file
    tasks_file=$(get_tasks_file)
    if [ ! -f "$tasks_file" ]; then
        echo "0"
        return
    fi
    jq '[.subtasks[] | select(.type == "ui")] | length' "$tasks_file" 2>/dev/null || echo "0"
}

# 获取子任务进度摘要（用于日志和 prompt 注入）
get_subtask_progress_summary() {
    local tasks_file
    tasks_file=$(get_tasks_file)
    if [ ! -f "$tasks_file" ]; then
        echo ""
        return
    fi

    local total passed current_id current_title
    total=$(jq '.subtasks | length' "$tasks_file" 2>/dev/null)
    passed=$(jq '[.subtasks[] | select(.passes == true)] | length' "$tasks_file" 2>/dev/null)
    current_id=$(get_current_subtask_id)
    current_title=$(get_current_subtask_title)

    echo "子任务进度: $passed/$total 已完成 | 当前子任务: $current_id - $current_title"
}

# 获取已压缩的摘要内容（用于子任务 section）
get_summaries_content() {
    local work_dir="$1"
    local summaries_dir="$work_dir/summaries"

    if [ ! -d "$summaries_dir" ]; then
        echo ""
        return
    fi

    local summaries=""
    local summary_files=()
    while IFS= read -r f; do
        summary_files+=("$f")
    done < <(ls -1 "$summaries_dir"/iteration-*-*.summary.md 2>/dev/null | sort -t'-' -k2 -n)

    if [ ${#summary_files[@]} -eq 0 ]; then
        echo ""
        return
    fi

    summaries="

### 历史迭代摘要

以下迭代日志已压缩为摘要：

"
    for summary_file in "${summary_files[@]}"; do
        local basename
        basename=$(basename "$summary_file" .summary.md)
        summaries="${summaries}- [$basename](${summaries_dir#$work_dir/}/$(basename "$summary_file"))
"
    done

    echo "$summaries"
}

# 生成子任务注入文本（用于 prompt）
# 自动包含已压缩的摘要引用
get_subtask_section() {
    local subtask
    subtask=$(get_current_subtask)
    if [ -z "$subtask" ] || [ "$subtask" = "null" ]; then
        echo ""
        return
    fi

    local id title desc criteria subtask_type
    id=$(echo "$subtask" | jq -r '.id')
    title=$(echo "$subtask" | jq -r '.title')
    desc=$(echo "$subtask" | jq -r '.description')
    criteria=$(echo "$subtask" | jq -r '.acceptanceCriteria[]?' 2>/dev/null)
    subtask_type=$(echo "$subtask" | jq -r '.type // "code"' 2>/dev/null)

    local progress
    progress=$(get_subtask_progress_summary)

    # 自动包含摘要引用
    local summaries_section
    summaries_section=$(get_summaries_content "$WORK_DIR")

    local ui_hint=""
    if [ "$subtask_type" = "ui" ]; then
        ui_hint="

⚠️ **UI 类型任务**: 此子任务涉及 UI 变更，实现时请注意：
- 确保页面布局、样式正确渲染
- 确保交互元素（按钮、表单、链接等）功能正常
- 确保无 console 错误或页面崩溃
- 实现完成后将进行浏览器截图验证"
    fi

    cat << EOF

## 当前子任务

$progress

### 子任务详情

- **ID**: $id
- **标题**: $title
- **类型**: $subtask_type
- **描述**: $desc
- **验收条件**:
$(echo "$criteria" | while read -r line; do echo "  - $line"; done)
$ui_hint
请专注于实现此子任务，不要处理其他子任务。完成此子任务后等待审核。
$summaries_section
EOF
}

# 生成规划阶段子任务注入文本（用于审核 prompt，包含所有子任务状态）
get_subtask_review_section() {
    local tasks_file
    tasks_file=$(get_tasks_file)
    if [ ! -f "$tasks_file" ]; then
        echo ""
        return
    fi

    local progress
    progress=$(get_subtask_progress_summary)

    local current_subtask
    current_subtask=$(get_current_subtask)
    if [ -z "$current_subtask" ] || [ "$current_subtask" = "null" ]; then
        echo "

## 子任务审核

$progress

所有子任务已完成审核。"
        return
    fi

    local id title desc criteria subtask_type
    id=$(echo "$current_subtask" | jq -r '.id')
    title=$(echo "$current_subtask" | jq -r '.title')
    desc=$(echo "$current_subtask" | jq -r '.description')
    criteria=$(echo "$current_subtask" | jq -r '.acceptanceCriteria[]?' 2>/dev/null)
    subtask_type=$(echo "$current_subtask" | jq -r '.type // "code"' 2>/dev/null)

    local ui_review_section=""
    if [ "$subtask_type" = "ui" ]; then
        ui_review_section="

### UI 验证标准（此子任务为 UI 类型）

审核时请额外关注以下 UI 验证标准：
- 页面无空白或崩溃：页面能正常加载，无白屏或错误页面
- 关键元素可见：页面标题、内容、导航等关键元素正确渲染
- 交互元素可点击：按钮、链接、表单等可正常交互
- 无 console 错误：浏览器控制台无 JavaScript 错误
- 样式一致性：CSS 样式与设计稿或现有风格一致
- 响应式布局：在不同屏幕尺寸下布局合理（如适用）

此子任务通过代码审核后，将进行浏览器截图验证以确认 UI 渲染正确。"
    fi

    cat << EOF

## 子任务审核

$progress

请审核当前子任务的实现：

- **ID**: $id
- **标题**: $title
- **类型**: $subtask_type
- **描述**: $desc
- **验收条件**:
$(echo "$criteria" | while read -r line; do echo "  - $line"; done)
$ui_review_section

请针对此子任务的验收条件进行审核。
EOF
}
