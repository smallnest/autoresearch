# Issue #49 经验日志

## Codebase Patterns

> 此区域汇总最重要的可复用经验和模式。Agent 可在实现过程中更新此区域。


## Iteration 1 - 2026-04-22

- **Agent**: opencode
- **类型**: 初始实现 - 添加全局 trap cleanup 清理机制
- **评分**: N/A/100

- **经验与发现**:

## Learnings

- **模式**: 使用 `trap func EXIT INT TERM` 配合 `$?` 获取退出码可正确处理信号和正常退出两种情况
- **踩坑**: `trap` 中信号参数在 bash 中不是 `$1`，而是 `$?` 来获取退出码；正确做法是不传参数，检查 `$?`
- **经验**: agent 子进程需要用后台运行 + wait 方式才能获取 PID 用于后续清理


## Iteration 2 - 2026-04-22

- **Agent**: opencode
- **类型**: 审核+修复
- **评分**: 85/100

- **审核要点**:

[0m
> build · big-pickle
[0m
我将审核 Issue #49 子任务 T-001 的实现。首先让我查看项目代码中是否已添加全局 trap cleanup 清理机制。
[0m✱ [0mGlob "*.sh"[90m in . · 6 matches[0m
[0m✱ [0mGrep "trap.*cleanup"[90m in . · 34 matches[0m
[0m→ [0mRead run.sh[90m [offset=3120, limit=80][0m
[0m✱ [0mGrep "^cleanup\(\)"[90m in . · 4 matches[0m
[0m→ [0mRead run.sh[90m [offset=2645, limit=60][0m
[0m✱ [0mGrep "stop_spinner"[90m in . · 6 matches[0m
[0m→ [0mRead run.sh[90m [limit=30, offset=410][0m
[0m→ [0mRead run.sh[90m [limit=40, offset=2620][0m
[0m✱ [0mGrep "AGENT_PID"[90m in . · 13 matches[0m
[0m→ [0mRead run.sh[90m [limit=40, offset=450][0m
现在让我检查是否有测试文件覆盖这个功能。
[

- **经验与发现**:

## Learnings

- **模式**: `trap cleanup EXIT INT TERM` 需配合 `$?` 获取退出码，`$1` 不是信号参数
- **踩坑**: AGENT_PID 必须保存后台进程 PID（`$!`），且不能在 wait 后立即清空，否则 cleanup 无法清理
- **经验**: 后台运行 (`&`) + wait 模式获取的 PID 如需清理，应在 wait 之后检查进程是否仍在运行，而不是立即清空变量

