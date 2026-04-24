# Issue #54 经验日志

## Codebase Patterns

> 此区域汇总最重要的可复用经验和模式。Agent 可在实现过程中更新此区域。


## Iteration 1 - 2026-04-24

- **Agent**: claude
- **类型**: 初始实现 - 在 check_dependencies 中增加磁盘空间预检
- **评分**: N/A/100

- **经验与发现**:

## 实现总结
### 在 `run.sh:1206-1215` 中做出的修改
在 `check_dependencies()` 中添加了磁盘空间预检逻辑：
- 使用 `df -k .` 检查当前工作目录分区的可用空间
- 默认阈值 **1GB** (1024MB)，可通过 `DISK_MIN_MB` 环境变量配置
- 如果 `df` 失败（例如，分区不可用），则优雅地回退到 0（不阻塞）
- 空间不足时：记录一个 `error` 并设置 `missing=1`，这会导致 `exit 1`
- 总是记录当前可用空间和阈值
### 新文件: `tests/test_disk_space.sh`
11 个测试用例，涵盖：
1. 默认阈值通过（正常情况）
2. 低自定义阈值 (1MB) 通过
3. 极高阈值 (99999999MB) 正确失败
4. 零阈值始终通过
5. 日志格式验证（可用空间和阈值都已记录）
所有测试通过 (11/11)，加上所有现有测试也继续通过 (agent_logic: 52, extract_score: 177, archive: 13)。
## 经验总结
- **模式**：`check_dependencies()` 使用一个 `missing` 标志，该标志在最后检查时设置；新检查遵循相同的模式
- **经验教训**：在 `set -e` 下，使用 `cmd || result=$?` 来捕获预期失败的命令的退出代码，避免 `|| true` 吞噬代码
- **约定**：项目中的 Shell 测试遵循独立测试模式，使用 `assert_*` 辅助函数，不直接获取 `source run.sh`


## Iteration 2 - 2026-04-24

- **Agent**: codex
- **类型**: 审核+修复 - T-002
- **评分**: 90/100

- **审核要点**:

OpenAI Codex v0.120.0 (research preview)
--------
workdir: /Users/smallnest/ai/autoresearch
model: tencent/hy3-preview:free
provider: openrouter
approval: never
sandbox: workspace-write [workdir, /tmp, $TMPDIR, /Users/smallnest/.codex/memories]
reasoning effort: high
reasoning summaries: none
session id: 019dbb16-176d-7220-9d76-dce14219cac0
--------
user
审核 Issue #54 的实现

项目路径: /Users/smallnest/ai/autoresearch
项目语言: unknown
Issue 标题: [hardness engineering] 磁盘空间预检


## 子任务审核

子任务进度: 0/2 已完成 | 当前子任务: T-001 - 在 check_dependencies 中增加磁盘空间预检

请审核当前子任务的实现：

- **ID**: T-001
- **标题**: 在 check_dependencies 中增加磁盘空间预检
- **类型**: code
- **描述**: 在 ch

- **经验与发现**:

## Learnings

- **模式**: [发现的可复用模式]
- **踩坑**: [遇到的问题及解决方式]
- **经验**: [对后续迭代有帮助的经验]
```

如果你在项目中发现了重要的可复用模式，可以建议更新 `progress.md` 的 `## Codebase Patterns` 区域。

### 更新目录级 CLAUDE.md

除了在输出中总结 Learnings，你还必须将可复用的项目知识写入相关目录的 `CLAUDE.md` 文件中。这样后续迭代和 Agent 都能自动获取这些知识。

**操作流程**：
1. 实现完成后，回顾你修改或新增代码所在的目录
2. 如果发现了可复用的模式、约定或陷阱，更新（或创建）该目录的 `CLAUDE.md`
3. 如果 `CLAUDE.md` 已存在，追加新知识，不要删除已有内容
4. 如果 `CLAUDE.md` 不存在，创建新文件，格式参考 `program.md` 中的「目录级知识积累」章节

**示例**：如果你在 `internal/auth/` 目录下发现 "所有中间件必须调用 next() 即使认证失败"，就更新 `internal/auth/CLAUDE.md`：

```markdown
# internal/auth


## Iteration 3 - 2026-04-24

- **Agent**: opencode
- **类型**: 审核+修复
- **评分**: 90/100

- **审核要点**:

[0m
> build · k2p6
[0m
[0m→ [0mRead run.sh[90m [limit=200][0m
[0m✱ [0mGlob "tests/test_disk*.sh"[90m 1 match[0m
[0m✱ [0mGrep "safe_log_append|mark_subtask_passed|tasks\.json|progress\.md"[90m in run.sh · 33 matches[0m
[0m→ [0mRead tests/test_disk_space.sh
[0m→ [0mRead run.sh[90m [offset=1640, limit=120][0m
[0m→ [0mRead run.sh[90m [limit=100, offset=1960][0m
[0m→ [0mRead run.sh[90m [limit=100, offset=2060][0m
[0m→ [0mRead run.sh[90m [limit=150, offset=2160][0m
[0m✱ [0mGrep "echo.*>>.*log\.md|echo.*>.*log\.md|echo.*>>.*progress\.md|echo.*>.*progress\.md|echo.*>.*tasks\.json"[90m in run.sh · 34 matches[0m
[0m→ [0mRead run.sh[90m [limit=100, offset=700][0m
[0m→ [0mRead run.sh[90m [limit=100, offset=1200][0m
[0m✗ [0mgrep f

- **经验与发现**:

## Learnings

- **模式**: T-001 的实现模式（`cmd || result=$?`）可以直接复用到 T-002 的错误处理中
- **踩坑**: 迭代 3 的审核发现 T-002 完全未实现，可能是 agent 误解了任务范围或只完成了 T-001
- **经验**: 在 `set -e` 环境下，所有关键写入操作都需要 `||` 错误处理，否则磁盘满时脚本会无信息中断

