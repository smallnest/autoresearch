#!/bin/bash
# Prompt assembly helpers: program instructions, smart trimming, overflow trimming.
#
# Required globals: PROJECT_ROOT, SCRIPT_DIR, PROMPT_TRIMMED
# Required callbacks: detect_language, log, log_console

get_program_instructions() {
    local project_program="$PROJECT_ROOT/.autoresearch/program.md"
    local default_program="$SCRIPT_DIR/program.md"
    local program_file=""

    if [ -f "$project_program" ]; then
        program_file="$project_program"
    elif [ -f "$default_program" ]; then
        program_file="$default_program"
    else
        echo ""
        return
    fi

    if [ "${PROMPT_TRIMMED:-0}" -eq 0 ]; then
        cat "$program_file"
        return
    fi

    # PROMPT_TRIMMED=1: 按优先级裁剪 program.md
    # 保留：当前项目语言相关的代码规范、通用规则
    # 移除：与当前项目语言无关的部分（如 Go/Python/TypeScript/Rust 中非当前语言的章节）
    local current_lang
    current_lang=$(detect_language)
    local trimmed
    trimmed=$(grep -v -i -E "^[#]+ .*(Go|Python|TypeScript|Rust|Frontend|Java|C\+\+|Ruby|PHP)" "$program_file" 2>/dev/null || cat "$program_file")

    # 如果裁剪后内容仍然过长，只保留通用规则（不含语言特定规则的行）
    local trimmed_len=${#trimmed}
    if [ "$trimmed_len" -gt 5000 ]; then
        # 进一步裁剪：只保留不以 # 开头的行和通用规则标题
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

# 智能裁剪 prompt：保留关键信息，移除冗余内容
# 注意：此函数不检查 PROMPT_TRIMMED 标志，由调用者控制何时裁剪
# 裁剪策略（按优先级）：
#   1. 保留：当前子任务描述、未完成子任务列表、最近 review 反馈、progress.md 经验日志
#   2. 移除：program.md 内容（get_program_instructions 已按语言裁剪）、长代码块（>20行）
#   3. 移除：已通过子任务的详细描述（只保留标题行）
# 这是需求中要求的函数名 trim_prompt_for_overflow() 的别名
trim_prompt_for_overflow() {
    trim_prompt_smart "$@"
}

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

# 如果 PROMPT_TRIMMED=1（来自上一次溢出），对 prompt 应用智能裁剪
# 用法: prompt=$(apply_prompt_trimming "$prompt")
# PROMPT_TRIMMED 标志在 trim 后设为 1，防止同一 prompt 被重复裁剪
# 在迭代成功完成时（非溢出退出）重置为 0
apply_prompt_trimming() {
    local prompt="$1"
    if [ "${PROMPT_TRIMMED:-0}" -ge 1 ]; then
        local trim_level=${PROMPT_TRIMMED:-0}
        PROMPT_TRIMMED=0  # 标记已执行裁剪，防止同一 prompt 重复裁剪
        # 根据裁剪级别调整裁剪策略
        case $trim_level in
            1)
                # 轻度裁剪：只移除 program.md 和长代码块
                trim_prompt_for_overflow "$prompt"
                ;;
            2)
                # 中度裁剪：额外移除已通过子任务的详细描述
                local trimmed
                trimmed=$(trim_prompt_for_overflow "$prompt")
                # 进一步裁剪：移除更多历史迭代摘要
                echo "$trimmed" | awk '
                    BEGIN { in_history=0 }
                    /^## 历史迭代摘要/ { in_history=1; next }
                    /^## [^#]/ { in_history=0 }
                    in_history { next }
                    { print }
                '
                ;;
            3)
                # 重度裁剪：保留核心信息，移除大部分辅助内容
                local trimmed
                trimmed=$(trim_prompt_for_overflow "$prompt")
                # 移除历史迭代摘要和 agent persona 示例
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
