#!/bin/bash
# lib/gitea.sh — Gitea API helpers for autoresearch
#
# 环境变量:
#   GITEA_URL    Gitea 实例地址，如 https://gitea.example.com (无尾斜杠)
#   GITEA_TOKEN  Gitea 访问令牌 (Settings → Applications → Access Tokens)
#
# 用法:
#   GITEA_URL=https://gitea.example.com GITEA_TOKEN=xxx \
#     ./run.sh --issue-source=gitea -p /path/to/repo 42

# ──────────────────────────────────────────────
# 内部工具
# ──────────────────────────────────────────────

_gitea_api() {
    local method="$1"; local path="$2"; shift 2
    curl -sf -X "$method" \
        -H "Authorization: token ${GITEA_TOKEN}" \
        -H "Content-Type: application/json" \
        "${GITEA_URL}/api/v1${path}" "$@"
}

# 从 git remote URL 提取 owner/repo
# 支持 https://host/owner/repo.git 和 ssh://git@host/owner/repo.git
_gitea_parse_remote() {
    local remote_url="$1"
    local path
    path=$(echo "$remote_url" \
        | sed -E \
            -e 's|^https?://[^/]+/||' \
            -e 's|^ssh://[^/@]+@?[^/]+/||' \
            -e 's|^git@[^:]+:||' \
            -e 's|\.git$||' \
        | grep -oE '[^/]+/[^/]+$')
    GITEA_OWNER=$(echo "$path" | cut -d'/' -f1)
    GITEA_REPO=$(echo  "$path" | cut -d'/' -f2)
}

# ──────────────────────────────────────────────
# Issue 获取
# ──────────────────────────────────────────────

get_gitea_issue_info() {
    local issue_number="$1"

    if [ -z "$GITEA_TOKEN" ]; then
        error "GITEA_TOKEN 未设置，请先生成 Gitea Access Token"
        exit 1
    fi
    if [ -z "$GITEA_URL" ]; then
        error "GITEA_URL 未设置，请设置 Gitea 实例地址（如 https://gitea.example.com）"
        exit 1
    fi

    local remote_url
    remote_url=$(git -C "$PROJECT_ROOT" remote get-url origin 2>/dev/null || true)
    _gitea_parse_remote "$remote_url"

    log "Gitea: ${GITEA_URL}/${GITEA_OWNER}/${GITEA_REPO} issue #${issue_number}"

    local issue_json
    issue_json=$(_gitea_api GET "/repos/${GITEA_OWNER}/${GITEA_REPO}/issues/${issue_number}" 2>&1)
    if [ $? -ne 0 ] || [ -z "$issue_json" ]; then
        error "无法获取 Gitea Issue #${issue_number}: ${issue_json}"
        exit 1
    fi

    ISSUE_TITLE=$(echo "$issue_json" | jq -r '.title')
    ISSUE_BODY=$(echo  "$issue_json" | jq -r '.body // ""')
    ISSUE_STATE=$(echo "$issue_json" | jq -r '.state')
    ISSUE_LABELS=$(echo "$issue_json" | jq -r '.labels[]?.name // empty' | tr '\n' ',' | sed 's/,$//')
    ISSUE_FILE=""

    if [ "$ISSUE_STATE" != "open" ]; then
        error "Gitea Issue #${issue_number} 状态为 ${ISSUE_STATE}，不是 open"
        exit 1
    fi

    log "Issue 标题: $ISSUE_TITLE"
    log "Issue 标签: ${ISSUE_LABELS:-无}"
}

# ──────────────────────────────────────────────
# PR 创建 + 合并
# ──────────────────────────────────────────────

gitea_create_and_merge_pr() {
    local issue_number="$1"
    local issue_title="$2"
    local branch_name="$3"
    local final_score="$4"
    local iteration="$5"
    local pr_body="$6"

    local main_branch
    main_branch=$(git -C "$PROJECT_ROOT" remote show origin 2>/dev/null \
        | grep 'HEAD branch' | cut -d':' -f2 | tr -d ' ')
    [ -z "$main_branch" ] && main_branch="master"

    log_console "创建 Gitea Pull Request..."

    local pr_json
    pr_json=$(_gitea_api POST \
        "/repos/${GITEA_OWNER}/${GITEA_REPO}/pulls" \
        -d "$(jq -n \
            --arg title "feat: ${issue_title} (#${issue_number})" \
            --arg body  "$pr_body" \
            --arg head  "$branch_name" \
            --arg base  "$main_branch" \
            '{title:$title, body:$body, head:$head, base:$base}')" 2>&1)

    if [ $? -ne 0 ] || [ -z "$pr_json" ]; then
        log_console "⚠️ Gitea PR 创建失败: $pr_json"
        return 1
    fi

    local pr_number pr_url
    pr_number=$(echo "$pr_json" | jq -r '.number')
    pr_url=$(echo     "$pr_json" | jq -r '.html_url')
    log_console "✅ PR 已创建: $pr_url"
    set_phase "create_pr"

    # 合并 PR
    log_console "合并 PR #${pr_number}..."
    local merge_resp
    merge_resp=$(_gitea_api POST \
        "/repos/${GITEA_OWNER}/${GITEA_REPO}/pulls/${pr_number}/merge" \
        -d '{"Do":"merge","merge_message_field":"Auto-merged by autoresearch"}' 2>&1)

    if [ $? -ne 0 ]; then
        log_console "⚠️ PR 合并失败，请手动处理: $pr_url"
        log "PR merge failed: $merge_resp"
    else
        log_console "✅ PR #${pr_number} 已合并"
    fi

    PR_URL="$pr_url"
    PR_NUMBER="$pr_number"
}

# ──────────────────────────────────────────────
# Issue 评论 + 关闭
# ──────────────────────────────────────────────

gitea_comment_issue() {
    local issue_number="$1"
    local body="$2"

    _gitea_api POST \
        "/repos/${GITEA_OWNER}/${GITEA_REPO}/issues/${issue_number}/comments" \
        -d "$(jq -n --arg body "$body" '{body:$body}')" > /dev/null 2>&1 \
        || log "警告: Gitea 添加评论失败"
}

gitea_close_issue() {
    local issue_number="$1"

    _gitea_api PATCH \
        "/repos/${GITEA_OWNER}/${GITEA_REPO}/issues/${issue_number}" \
        -d '{"state":"closed"}' > /dev/null 2>&1 \
        || log_console "⚠️ 关闭 Gitea Issue 失败 (可能已通过 PR 自动关闭)"
}

# ──────────────────────────────────────────────
# 自动检测 remote 是否为 Gitea
# ──────────────────────────────────────────────

is_gitea_remote() {
    local remote_url="$1"
    if [ -z "$GITEA_URL" ]; then
        return 1
    fi
    local gitea_host
    gitea_host=$(echo "$GITEA_URL" | sed -E 's|^https?://||')
    echo "$remote_url" | grep -q "$gitea_host"
}
