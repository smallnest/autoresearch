#!/bin/bash
# lib/linear.sh — Linear API helpers for autoresearch
#
# 环境变量:
#   LINEAR_API_KEY  Linear Personal API Key (Settings → API → Personal API keys)
#
# Linear identifier 格式: TEAM-NUMBER (如 OMC-57, XAR-407)
# 全局变量 (由 get_linear_issue_info 设置):
#   LINEAR_ISSUE_ID   Linear 内部 UUID（用于后续 mutation）
#   LINEAR_TEAM_KEY   从 identifier 提取的 team key（如 OMC）

LINEAR_ISSUE_ID=""
LINEAR_TEAM_KEY=""

# ──────────────────────────────────────────────
# 内部工具
# ──────────────────────────────────────────────

_linear_gql() {
    local query="$1"
    local variables="${2:-{\}}"
    curl -sf \
        -H "Authorization: ${LINEAR_API_KEY}" \
        -H "Content-Type: application/json" \
        -d "$(jq -n --arg q "$query" --argjson v "$variables" '{query:$q,variables:$v}')" \
        "https://api.linear.app/graphql"
}

# ──────────────────────────────────────────────
# Issue 获取
# ──────────────────────────────────────────────

get_linear_issue_info() {
    local identifier="$1"

    if [ -z "$LINEAR_API_KEY" ]; then
        error "LINEAR_API_KEY 未设置，请先生成 Linear Personal API Key"
        exit 1
    fi

    # 提取 team key（OMC-57 → OMC）
    LINEAR_TEAM_KEY=$(echo "$identifier" | cut -d'-' -f1)

    log "Linear: 获取 Issue ${identifier}..."

    local query='query GetIssue($id: String!) {
  issues(filter: { identifier: { eq: $id } }) {
    nodes {
      id identifier title description
      state { name type }
      labels { nodes { name } }
    }
  }
}'
    local vars
    vars=$(jq -n --arg id "$identifier" '{id: $id}')

    local resp
    resp=$(_linear_gql "$query" "$vars" 2>&1)
    if [ $? -ne 0 ] || [ -z "$resp" ]; then
        error "无法连接 Linear API: $resp"
        exit 1
    fi

    local node
    node=$(echo "$resp" | jq -r '.data.issues.nodes[0] // empty')
    if [ -z "$node" ]; then
        error "找不到 Linear Issue: $identifier"
        exit 1
    fi

    LINEAR_ISSUE_ID=$(echo "$node" | jq -r '.id')
    ISSUE_TITLE=$(echo "$node" | jq -r '.title')
    ISSUE_BODY=$(echo "$node" | jq -r '.description // ""')
    ISSUE_STATE=$(echo "$node" | jq -r '.state.type')   # backlog/unstarted/started/completed/cancelled
    ISSUE_LABELS=$(echo "$node" | jq -r '.labels.nodes[].name' | tr '\n' ',' | sed 's/,$//')
    ISSUE_FILE=""

    if [ "$ISSUE_STATE" = "completed" ] || [ "$ISSUE_STATE" = "cancelled" ]; then
        error "Linear Issue ${identifier} 状态为 ${ISSUE_STATE}，跳过"
        exit 1
    fi

    log "Issue 标题: $ISSUE_TITLE"
    log "Issue 标签: ${ISSUE_LABELS:-无}"
}

# ──────────────────────────────────────────────
# 添加评论
# ──────────────────────────────────────────────

linear_comment_issue() {
    local issue_id="$1"
    local body="$2"

    local mutation='mutation AddComment($issueId: String!, $body: String!) {
  commentCreate(input: { issueId: $issueId, body: $body }) { success }
}'
    local vars
    vars=$(jq -n --arg issueId "$issue_id" --arg body "$body" \
        '{issueId: $issueId, body: $body}')

    _linear_gql "$mutation" "$vars" > /dev/null 2>&1 \
        || log "警告: Linear 添加评论失败"
}

# ──────────────────────────────────────────────
# 更新 Issue 状态
# 查找 team 下名为 $state_name 的 WorkflowState，然后执行 issueUpdate
# ──────────────────────────────────────────────

linear_update_state() {
    local issue_id="$1"
    local team_key="$2"
    local state_name="$3"

    # 查 stateId
    local sq='query States($key: String!) {
  teams(filter: { key: { eq: $key } }) {
    nodes { states { nodes { id name } } }
  }
}'
    local sv
    sv=$(jq -n --arg key "$team_key" '{key: $key}')
    local state_resp
    state_resp=$(_linear_gql "$sq" "$sv" 2>/dev/null)

    local state_id
    state_id=$(echo "$state_resp" | jq -r \
        --arg name "$state_name" \
        '.data.teams.nodes[0].states.nodes[]? | select(.name==$name) | .id' \
        2>/dev/null | head -1)

    if [ -z "$state_id" ] || [ "$state_id" = "null" ]; then
        log "警告: 找不到 Linear 状态 '${state_name}'（team: ${team_key}），跳过状态更新"
        return 0
    fi

    local mutation='mutation UpdateIssue($id: String!, $stateId: String!) {
  issueUpdate(id: $id, input: { stateId: $stateId }) { success }
}'
    local vars
    vars=$(jq -n --arg id "$issue_id" --arg stateId "$state_id" \
        '{id: $id, stateId: $stateId}')

    _linear_gql "$mutation" "$vars" > /dev/null 2>&1 \
        || log "警告: Linear 更新状态失败"
}
