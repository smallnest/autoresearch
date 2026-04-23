#!/bin/bash
# Shared git push recovery helpers.

# push_branch_with_recovery pushes BRANCH_NAME to origin and handles failures.
# Required globals: PROJECT_ROOT, BRANCH_NAME, WORK_DIR.
# Required callbacks: log_console, error.
push_branch_with_recovery() {
    local push_output=""
    local push_exit_code=0
    local retry_output=""
    local retry_exit_code=0
    local stash_output=""
    local stash_msg=""
    local stash_before=0
    local stash_after=0
    local stash_created=0

    log_console "推送分支 $BRANCH_NAME..."

    push_output=$(git push -u origin "$BRANCH_NAME" 2>&1) || {
        push_exit_code=$?

        error "git push 失败 (exit code: $push_exit_code)"
        log_console ""
        log_console "❌ git push 失败！"
        log_console ""
        log_console "错误输出:"
        log_console "$push_output"
        log_console ""

        cat >> "$WORK_DIR/log.md" << EOF

---

## ❌ Git Push 失败

**时间**: $(date '+%Y-%m-%d %H:%M:%S')
**分支**: $BRANCH_NAME
**错误码**: $push_exit_code

**错误输出**:
\`\`\`
$push_output
\`\`\`

EOF

        if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
            log_console "检测到未提交的更改，尝试 stash 后重试..."
            stash_msg="autoresearch-push-retry-$(date +%s)"
            stash_before=$(git stash list 2>/dev/null | wc -l | tr -d ' ')
            stash_output=$(git stash push --include-untracked -m "$stash_msg" 2>&1) || true
            stash_after=$(git stash list 2>/dev/null | wc -l | tr -d ' ')

            if [ "$stash_after" -gt "$stash_before" ] 2>/dev/null; then
                stash_created=1
            fi

            if [ $stash_created -eq 1 ]; then
                log_console "重试 git push..."
                retry_output=$(git push -u origin "$BRANCH_NAME" 2>&1) || {
                    retry_exit_code=$?
                }

                if [ $retry_exit_code -eq 0 ]; then
                    log_console "✅ Stash 后重试成功！"
                    git stash pop >/dev/null 2>&1 || true
                    return 0
                fi

                git stash pop >/dev/null 2>&1 || true
                log_console "❌ 重试仍然失败"
                log_console ""

                cat >> "$WORK_DIR/log.md" << EOF

**重试结果**: 失败 (exit code: $retry_exit_code)

**重试输出**:
\`\`\`
$retry_output
\`\`\`

EOF
            else
                log_console "未能创建 stash，跳过重试。"

                cat >> "$WORK_DIR/log.md" << EOF

**Stash 结果**: 未创建 stash，跳过重试

**Stash 输出**:
\`\`\`
$stash_output
\`\`\`

EOF
            fi
        fi

        log_console ""
        log_console "═══════════════════════════════════════════════════════════"
        log_console "📋 恢复建议："
        log_console "═══════════════════════════════════════════════════════════"
        log_console ""
        log_console "1. 检查网络连接和 GitHub 访问"
        log_console "   - 确认可以访问 github.com"
        log_console "   - 检查是否需要 VPN 或代理"
        log_console ""
        log_console "2. 检查认证状态"
        log_console "   - 运行: gh auth status"
        log_console "   - 如需重新登录: gh auth login"
        log_console ""
        log_console "3. 检查分支状态"
        log_console "   - 当前分支: $BRANCH_NAME"
        log_console "   - 运行: git status"
        log_console "   - 运行: git log --oneline -5"
        log_console ""
        log_console "4. 手动推送命令"
        log_console "   cd $PROJECT_ROOT"
        log_console "   git push -u origin $BRANCH_NAME"
        log_console ""
        log_console "5. 如果推送成功，继续后续流程："
        log_console "   gh pr create --title '<issue-title> (#<issue-number>)'"
        log_console ""
        log_console "6. 如果 stash 未自动恢复，运行:"
        log_console "   git stash list"
        log_console "   git stash pop"
        log_console "═══════════════════════════════════════════════════════════"
        log_console ""
        log_console "📂 工作目录: $WORK_DIR"
        log_console "📄 详细日志: $WORK_DIR/log.md"
        log_console ""

        return 1
    }

    return 0
}
