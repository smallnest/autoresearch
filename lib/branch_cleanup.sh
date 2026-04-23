#!/bin/bash
# Shared helpers for non-fatal post-merge branch cleanup.

# cleanup_merged_branch switches back to the main branch, refreshes it, and
# deletes the feature branch. Cleanup failures are logged but never returned as
# fatal so the caller can continue later post-merge steps.
cleanup_merged_branch() {
    local main_branch="$1"
    local branch_name="$2"

    log_console "切换回 $main_branch 分支..."
    if ! git checkout "$main_branch" 2>/dev/null; then
        log_console "⚠️  切换到 $main_branch 分支失败，继续执行..."
        log "branch cleanup: checkout $main_branch failed"
    fi

    if ! git pull origin "$main_branch" 2>/dev/null; then
        log_console "⚠️  拉取 $main_branch 分支最新代码失败，继续执行..."
        log "branch cleanup: git pull $main_branch failed"
    fi

    if git show-ref --verify --quiet "refs/heads/$branch_name"; then
        if ! git branch -D "$branch_name" 2>/dev/null; then
            log_console "⚠️  删除本地分支 $branch_name 失败，可能分支不存在或未合并"
            log "branch cleanup: git branch -D $branch_name failed"
        fi
    fi

    return 0
}
