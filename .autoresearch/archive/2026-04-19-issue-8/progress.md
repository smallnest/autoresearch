# Issue #8 经验日志

## Codebase Patterns

> 此区域汇总最重要的可复用经验和模式。Agent 可在实现过程中更新此区域。


## Iteration 1 - 2026-04-19

- **Agent**: claude
- **类型**: 初始实现
- **评分**: N/A/100

- **经验与发现**:

## Learnings

- **模式**: autoresearch 的配置覆盖机制（项目级 `.autoresearch/` > 默认文件）使得 prompt 模板修改可以同时影响所有项目
- **经验**: CLAUDE.md 目录级知识积累是零代码改动、纯 prompt 调整的典型场景，充分利用了 Claude Code 原生的自动读取行为


## Iteration 2 - 2026-04-19

- **Agent**: codex
- **类型**: 审核+修复
- **评分**: N/A/100

- **审核要点**:

OpenAI Codex v0.121.0 (research preview)
--------
workdir: /Users/chaoyuepan/ai/autoresearch
model: gpt-5.3-codex
provider: openai
approval: never
sandbox: workspace-write [workdir, /tmp, $TMPDIR, /Users/chaoyuepan/.codex/memories]
reasoning effort: medium
reasoning summaries: none
session id: 019da4c2-b9d0-7c13-8912-6a1e9bced25f
--------
user
审核 Issue #8 的实现

项目路径: /Users/chaoyuepan/ai/autoresearch
项目语言: unknown
Issue 标题: feat: CLAUDE.md 目录级知识积累


---
请按照以下指令执行审核。

评分格式要求: 必须在审核报告的总体评价中使用 **评分: X/100** 格式输出分数，其中 X 为 0-100 的整数。

评分维度与权重:
- 正确性 (35%): 功能是否符合需求、边界情况处理、错误处理
- 测试质量 (25%)

- **经验与发现**:

## Learnings

- **模式**: autoresearch 的配置覆盖机制（项目级 `.autoresearch/` > 默认文件）使得 prompt 模板修改可以同时影响所有项目
- **经验**: CLAUDE.md 目录级知识积累是零代码改动、纯 prompt 调整的典型场景，充分利用了 Claude Code 原生的自动读取行为
# Codex Agent

你是一个专业的软件工程师 Agent，既能实现功能，也能审核代码。

---

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
# internal/a


## Iteration 3 - 2026-04-19

- **Agent**: opencode
- **类型**: 审核+修复
- **评分**: 100/100

- **审核要点**:

[94m[1m| [0m[90m Glob     [0m{"pattern":"agents/*.md"}
[96m[1m| [0m[90m Read     [0mprogram.md
I will start by examining the changes made to the agent instructions and the `program.md` file to verify the implementation of directory-level knowledge accumulation.
[96m[1m| [0m[90m Read     [0magents/claude.md
[96m[1m| [0m[90m Read     [0magents/codex.md
[96m[1m| [0m[90m Read     [0magents/opencode.md
I will now read the agent instruction files `agents/claude.md`, `agents/codex.md`, and `agents/opencode.md` to verify that the "Learnings" and `CLAUDE.md` update instructions have been properly integrated into their personas.
[94m[1m| [0m[90m Glob     [0m{"pattern":"**/CLAUDE.md"}
I've confirmed that the agent instruction files and `program.md` have been updated as r

- **经验与发现**:

## Learnings

- **模式**: `autoresearch` 的配置覆盖机制（项目级 `.autoresearch/` > 默认文件）使得 prompt 模板修改可以同时影响所有项目，这种"控制面"的设计非常灵活。
- **模式**: 目录级 `CLAUDE.md` 知识积累利用了 LLM 的自动上下文读取能力，是实现长短期记忆结合的有效手段。
- **经验**: 在 macOS 上进行开发时，必须注意文件名的大小写冲突，特别是 `CLAUDE.md` 与可能存在的 `claude.md` 或 `Claude.md`。
- **模式**: 跨迭代经验（`progress.md`）与持久化知识（`CLAUDE.md`）互补：前者记录单次 Issue 的演进，后者沉淀跨 Issue 的共性模式。

### 更新目录级 CLAUDE.md

我已经更新了以下目录的 `CLAUDE.md` 以积累本次审核中发现的知识：
- `agents/CLAUDE.md`: 定义了 Agent Persona 的设计规范和 Learnings 要求。
- `lib/CLAUDE.md`: 记录了共享逻辑库的约定。
- `tests/CLAUDE.md`: 说明了测试脚本的编写约定。

