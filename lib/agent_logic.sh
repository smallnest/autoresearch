#!/bin/bash
# Shared agent list parsing and rotation helpers.

# parse_agent_list parses comma-separated agents into AGENT_NAMES.
# Returns 0 on success, 1 on invalid input.
parse_agent_list() {
    local agent_list="$1"
    local valid_agents="claude codex opencode"
    local parsed=()
    local agent_name=""

    AGENT_NAMES=()
    AGENT_LIST_ERROR=""

    if [ -z "$agent_list" ]; then
        AGENT_NAMES=("claude" "codex" "opencode")
        return 0
    fi

    # Allow common user input like "claude, codex".
    agent_list=$(echo "$agent_list" | tr -d '[:space:]')
    if [ -z "$agent_list" ]; then
        AGENT_NAMES=("claude" "codex" "opencode")
        return 0
    fi

    if [[ "$agent_list" == ,* ]] || [[ "$agent_list" == *, ]] || [[ "$agent_list" == *",,"* ]]; then
        AGENT_LIST_ERROR="agent 列表格式无效: 存在空项"
        return 1
    fi

    IFS=',' read -ra parsed <<< "$agent_list"

    for agent_name in "${parsed[@]}"; do
        if [ -z "$agent_name" ]; then
            AGENT_LIST_ERROR="agent 列表格式无效: 存在空项"
            return 1
        fi
        if ! echo "$valid_agents" | grep -qw "$agent_name"; then
            AGENT_LIST_ERROR="未知的 agent: $agent_name (支持: claude, codex, opencode)"
            return 1
        fi
    done

    AGENT_NAMES=("${parsed[@]}")
    return 0
}

# get_review_agent returns the agent index for a given iteration.
get_review_agent() {
    local iter=$1
    local num_agents=${2:-${#AGENT_NAMES[@]}}
    if [ "$num_agents" -le 0 ]; then
        return 1
    fi
    echo $(( (iter - 1) % num_agents ))
}
