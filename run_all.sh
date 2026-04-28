#!/bin/bash
# autoresearch/run_all.sh - 批量处理所有未关闭的 GitHub Issues
#
# 拉取项目中所有 open 状态的 GitHub Issues，逐个调用 run.sh 处理。
#
# 用法:
#   ./run_all.sh [run.sh 的所有参数（不含 issue 编号）]
#
# 示例:
#   ./run_all.sh                                    # 处理当前项目所有 open issue（自动 continue）
#   ./run_all.sh -p /path/to/project               # 处理指定项目的所有 open issue
#   ./run_all.sh -a claude,codex                    # 指定 agents
#   ./run_all.sh -p /path/to/project -a claude 16   # 指定 agents + 最大迭代数
#   ./run_all.sh --no-archive --no-ui-verify        # 跳过归档和 UI 验证
#
# 注意: 对每个 issue 默认使用 -c (continue) 模式调用 run.sh。
#       首次运行的 issue 会正常从头开始，中断后重跑会自动续跑。
#
# 环境变量:
#   RUN_ALL_LABEL:    只处理带有此 label 的 issues (可选)
#   RUN_ALL_DRY_RUN:  设为 yes 则只列出 issues 不执行 (可选)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUN_SH="$SCRIPT_DIR/run.sh"

if [ ! -f "$RUN_SH" ]; then
    echo "ERROR: 找不到 run.sh: $RUN_SH" >&2
    exit 1
fi

# ==================== 解析参数 ====================
# 将所有参数收集起来，留给 run.sh；不在此脚本中消费 issue 编号
RUN_ARGS=("$@")

# ==================== 检测项目路径 ====================
# 如果参数中有 -p，使用其值；否则默认当前目录
PROJECT_ROOT="$(pwd)"
for (( i=0; i<${#RUN_ARGS[@]}; i++ )); do
    if [ "${RUN_ARGS[$i]}" = "-p" ] && (( i+1 < ${#RUN_ARGS[@]} )); then
        PROJECT_ROOT="${RUN_ARGS[$((i+1))]}"
        break
    fi
done

# ==================== 检查 gh CLI ====================
if ! command -v gh &>/dev/null; then
    echo "ERROR: 需要安装 GitHub CLI (gh)。请运行: brew install gh" >&2
    exit 1
fi

if ! gh auth status &>/dev/null; then
    echo "ERROR: gh 未登录。请运行: gh auth login" >&2
    exit 1
fi

# ==================== 获取项目 repo ====================
REPO_SLUG=""
if [ -d "$PROJECT_ROOT/.git" ]; then
    REPO_SLUG="$(cd "$PROJECT_ROOT" && git remote get-url origin 2>/dev/null | sed -E 's#.*github.com[/:]##;s/\.git$//' || true)"
fi

if [ -z "$REPO_SLUG" ]; then
    echo "ERROR: 无法从 $PROJECT_ROOT 检测到 GitHub remote (origin)。确保项目目录是 git 仓库且关联了 GitHub。" >&2
    exit 1
fi

# ==================== 拉取 open issues ====================
echo "========================================"
echo " autoresearch run_all"
echo " Repo: $REPO_SLUG"
echo "========================================"

GH_ARGS=(issue list --repo "$REPO_SLUG" --state open --limit 1000 --json number,title,labels)

ISSUES_JSON="$(gh "${GH_ARGS[@]}" 2>/dev/null)" || {
    echo "ERROR: 拉取 issues 失败。请检查仓库权限和网络。" >&2
    exit 1
}

# 可选：按 label 过滤
if [ -n "${RUN_ALL_LABEL:-}" ]; then
    ISSUES_JSON="$(echo "$ISSUES_JSON" | jq -c "[.[] | select(.labels[].name == \"$RUN_ALL_LABEL\")]")"
fi

ISSUE_COUNT="$(echo "$ISSUES_JSON" | jq 'length')"

if [ "$ISSUE_COUNT" -eq 0 ]; then
    echo "没有找到 open 状态的 issues。"
    exit 0
fi

echo ""
echo "找到 $ISSUE_COUNT 个 open issues:"
echo "$ISSUES_JSON" | jq -r '.[] | "  #\(.number) - \(.title)"'
echo ""

# ==================== DRY RUN 模式 ====================
if [ "${RUN_ALL_DRY_RUN:-}" = "yes" ]; then
    echo "[DRY RUN] 以上 issues 将被处理。设置 RUN_ALL_DRY_RUN 不为 yes 以实际执行。"
    exit 0
fi

# ==================== 逐个处理 ====================
SUCCESS=0
FAILED=0
SKIPPED=0
FAILED_ISSUES=()

echo "----------------------------------------"
echo "开始逐个处理 issues..."
echo "----------------------------------------"

ISSUE_NUMBERS=($(echo "$ISSUES_JSON" | jq -r '.[].number' | sort -n))

for ISSUE_NUM in "${ISSUE_NUMBERS[@]}"; do
    ISSUE_TITLE="$(echo "$ISSUES_JSON" | jq -r ".[] | select(.number == $ISSUE_NUM) | .title")"
    echo ""
    echo "========================================"
    echo " 处理 Issue #$ISSUE_NUM: $ISSUE_TITLE"
    echo "========================================"

    if bash "$RUN_SH" -c "${RUN_ARGS[@]}" "$ISSUE_NUM"; then
        echo "✓ Issue #$ISSUE_NUM 处理完成"
        ((SUCCESS++)) || true
    else
        EXIT_CODE=$?
        echo "✗ Issue #$ISSUE_NUM 处理失败 (exit code: $EXIT_CODE)"
        ((FAILED++)) || true
        FAILED_ISSUES+=("$ISSUE_NUM")
        # 继续处理下一个 issue，不终止
    fi
done

# ==================== 汇总报告 ====================
echo ""
echo "========================================"
echo " 批量处理完成"
echo "========================================"
echo "  成功: $SUCCESS"
echo "  失败: $FAILED"
echo "  总计: $ISSUE_COUNT"

if [ ${#FAILED_ISSUES[@]} -gt 0 ]; then
    echo ""
    echo "失败的 issues:"
    for NUM in "${FAILED_ISSUES[@]}"; do
        echo "  #$NUM"
    done
    echo ""
    echo "可以手动重试失败的 issues:"
    echo "  ./run.sh ${RUN_ARGS[*]} <issue_number>"
fi

echo ""

if [ "$FAILED" -gt 0 ]; then
    exit 1
fi

exit 0
