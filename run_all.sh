#!/bin/bash
# autoresearch/run_all.sh - 批量处理所有未关闭的 Issues
#
# 根据 --issue-source 参数决定 Issue 来源，支持三种模式：
#   github  — 拉取项目中所有 open 状态的 GitHub Issues (默认)
#   local   — 扫描本地 .autoresearch/issues/ 目录下的 issue-NNN-*.md 文件
#   baidu   — 拉取百度 iCafe 空间中未关闭的卡片
#
# 用法:
#   ./run_all.sh                                              # 默认 GitHub 模式，处理所有 open issue
#   ./run_all.sh -p /path/to/project                         # 指定项目路径
#   ./run_all.sh --issue-source=local                        # 本地模式：处理 .autoresearch/issues/ 下的所有文件
#   ./run_all.sh --issue-source=local --issues-dir=/path     # 本地模式：指定 issue 目录
#   ./run_all.sh --issue-source=baidu --space=cloud-iCafe    # 百度模式：处理 iCafe 空间中所有未关闭卡片
#   ./run_all.sh -a claude,codex                             # 指定 agents
#   ./run_all.sh --no-archive --no-ui-verify                 # 跳过归档和 UI 验证
#
# 注意: 对每个 issue 默认使用 -c (continue) 模式调用 run.sh。
#       首次运行的 issue 会正常从头开始，中断后重跑会自动续跑。
#
# 环境变量:
#   RUN_ALL_LABEL:      只处理带有此 label 的 issues (可选，仅 GitHub 模式)
#   RUN_ALL_DRY_RUN:    设为 yes 则只列出 issues 不执行 (可选)
#   ICAFE_SPACE:        iCafe 空间前缀代码 (baidu 模式，也可用 --space)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUN_SH="$SCRIPT_DIR/run.sh"

if [ ! -f "$RUN_SH" ]; then
    echo "ERROR: 找不到 run.sh: $RUN_SH" >&2
    exit 1
fi

# ==================== 解析参数 ====================
RUN_ARGS=("$@")
ISSUE_SOURCE="github"
ICAFE_SPACE="${ICAFE_SPACE:-}"
ISSUES_DIR=""
TARGET_BRANCH=""

# 从 RUN_ARGS 中提取 --issue-source / --space / --issues-dir / --target-branch
for arg in "${RUN_ARGS[@]+"${RUN_ARGS[@]}"}"; do
    case "$arg" in
        --issue-source=*)
            ISSUE_SOURCE="${arg#--issue-source=}"
            ;;
        --space=*)
            ICAFE_SPACE="${arg#--space=}"
            ;;
        --issues-dir=*)
            ISSUES_DIR="${arg#--issues-dir=}"
            ;;
        --target-branch=*)
            TARGET_BRANCH="${arg#--target-branch=}"
            ;;
    esac
done

# ==================== 检测项目路径 ====================
PROJECT_ROOT="$(pwd)"
for (( i=0; i<${#RUN_ARGS[@]}; i++ )); do
    if [ "${RUN_ARGS[$i]}" = "-p" ] && (( i+1 < ${#RUN_ARGS[@]} )); then
        PROJECT_ROOT="${RUN_ARGS[$((i+1))]}"
        break
    fi
done

# ==================== 自动检测 issue source ====================
# 如果显式指定了 local 或 baidu，尊重用户选择
# 否则尝试自动检测

if [ "$ISSUE_SOURCE" = "github" ]; then
    # 如果指定了 --issues-dir，切换到 local 模式
    if [ -n "$ISSUES_DIR" ]; then
        ISSUE_SOURCE="local"
    fi
fi

if [ "$ISSUE_SOURCE" = "github" ] && [ -n "$ICAFE_SPACE" ]; then
    # 检查 git remote 是否包含 icode.baidu.com
    REMOTE_URL="$(git -C "$PROJECT_ROOT" remote get-url origin 2>/dev/null || true)"
    if echo "$REMOTE_URL" | grep -q 'icode\.baidu\.com'; then
        ISSUE_SOURCE="baidu"
    fi
fi

# ==================== Issue 列表获取 ====================
ISSUES_JSON=""   # JSON 数组: [{"number": N, "title": "..."}, ...]

fetch_github_issues() {
    # 检查 gh CLI
    if ! command -v gh &>/dev/null; then
        echo "ERROR: 需要安装 GitHub CLI (gh)。请运行: brew install gh" >&2
        exit 1
    fi
    if ! gh auth status &>/dev/null; then
        echo "ERROR: gh 未登录。请运行: gh auth login" >&2
        exit 1
    fi

    # 获取 repo slug
    local repo_slug=""
    if [ -d "$PROJECT_ROOT/.git" ]; then
        repo_slug="$(cd "$PROJECT_ROOT" && git remote get-url origin 2>/dev/null | sed -E 's#.*github.com[/:]##;s/\.git$//' || true)"
    fi
    if [ -z "$repo_slug" ]; then
        echo "ERROR: 无法从 $PROJECT_ROOT 检测到 GitHub remote (origin)。确保项目目录是 git 仓库且关联了 GitHub。" >&2
        exit 1
    fi

    local gh_args=(issue list --repo "$repo_slug" --state open --limit 1000 --json number,title,labels)
    local json
    json="$(gh "${gh_args[@]}" 2>/dev/null)" || {
        echo "ERROR: 拉取 issues 失败。请检查仓库权限和网络。" >&2
        exit 1
    }

    # 可选：按 label 过滤
    if [ -n "${RUN_ALL_LABEL:-}" ]; then
        json="$(echo "$json" | jq -c "[.[] | select(.labels[].name == \"$RUN_ALL_LABEL\")]")"
    fi

    # 标准化为 {number, title} 数组
    ISSUES_JSON="$(echo "$json" | jq -c '[.[] | {number: .number, title: .title}]')"
}

fetch_local_issues() {
    local dir="$ISSUES_DIR"
    if [ -z "$dir" ]; then
        dir="$PROJECT_ROOT/.autoresearch/issues"
    fi

    # 相对路径转绝对路径
    if [[ "$dir" != /* ]]; then
        dir="$PROJECT_ROOT/$dir"
    fi

    if [ ! -d "$dir" ]; then
        echo "ERROR: 本地 issue 目录不存在: $dir" >&2
        echo "提示: 创建目录并放入 issue-NNN-*.md 文件，或使用 --issues-dir 指定路径" >&2
        exit 1
    fi

    # 扫描 issue-NNN-*.md 文件
    local entries=()
    for f in "$dir"/issue-*-*.md; do
        [ -f "$f" ] || continue
        local basename
        basename="$(basename "$f")"
        # 从 issue-008-feature-request.md 提取编号和标题
        local number title
        number="$(echo "$basename" | sed -E 's/^issue-0*([0-9]+)-.*/\1/')"
        title="$(echo "$basename" | sed -E 's/^issue-[0-9]+-(.*)\.md$/\1/' | tr '-' ' ')"
        entries+=("{\"number\": $number, \"title\": $(printf '%s' "$title" | jq -Rs 'rtrimstr("\n")')}")
    done

    if [ ${#entries[@]} -eq 0 ]; then
        ISSUES_JSON="[]"
        return
    fi

    # 组装 JSON 数组
    ISSUES_JSON="$(printf '%s\n' "${entries[@]}" | jq -s '.')"
}

fetch_baidu_issues() {
    if ! command -v icafe-cli &>/dev/null; then
        echo "ERROR: icafe-cli 未安装。请参考 https://icode.baidu.com/articles/help/icafe-cli" >&2
        exit 1
    fi
    if ! icafe-cli login status &>/dev/null 2>&1; then
        echo "ERROR: icafe-cli 未登录，请先运行 icafe-cli login" >&2
        exit 1
    fi
    if [ -z "$ICAFE_SPACE" ]; then
        echo "ERROR: baidu 模式需要指定 --space=<prefixCode> 或设置 ICAFE_SPACE 环境变量" >&2
        exit 1
    fi

    # 使用 icafe-cli card query 获取未关闭的卡片
    local json
    json="$(icafe-cli card query --space "$ICAFE_SPACE" --max-records 100 --brief 2>&1)" || {
        echo "ERROR: 拉取 iCafe 卡片失败: $json" >&2
        echo "提示: 请检查空间名称 ($ICAFE_SPACE) 和网络连接" >&2
        exit 1
    }

    # 解析返回的 JSON，过滤掉已关闭/已完成的卡片
    ISSUES_JSON="$(echo "$json" | jq -c '
        [(.cards // . // [])[]
        | select(
            (.status // "" | test("已完成|已关闭|closed"; "i")) | not
          )
        | {number: .sequence, title: .title}
        ]
    ')"
}

# ==================== 执行获取 ====================
echo "========================================"
echo " autoresearch run_all"
echo " 来源: $ISSUE_SOURCE"
echo " 项目: $PROJECT_ROOT"
if [ "$ISSUE_SOURCE" = "baidu" ]; then
    echo " iCafe 空间: $ICAFE_SPACE"
fi
echo "========================================"

case "$ISSUE_SOURCE" in
    github) fetch_github_issues ;;
    local)  fetch_local_issues ;;
    baidu)  fetch_baidu_issues ;;
    *)
        echo "ERROR: 未知 issue-source: $ISSUE_SOURCE (支持: github, local, baidu)" >&2
        exit 1
        ;;
esac

ISSUE_COUNT="$(echo "$ISSUES_JSON" | jq 'length')"

if [ "$ISSUE_COUNT" -eq 0 ]; then
    echo "没有找到待处理的 issues ($ISSUE_SOURCE 模式)。"
    exit 0
fi

echo ""
echo "找到 $ISSUE_COUNT 个待处理 issues ($ISSUE_SOURCE 模式):"
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
echo "  来源: $ISSUE_SOURCE"
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
