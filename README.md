# Autoresearch for Software Development

> 全自动化软件开发工具，你只需负责喝茶和睡觉。
> 一觉醒来,Features 全自动高质量的实现了。

![宣传视频](docs/autoresearch-promo-cn.gif)

基于 [karpathy/autoresearch](https://github.com/karpathy/autoresearch) 思想实现的通用的基于GitHub Issue管理的全自动化开发工具。

支持任意 Git + GitHub 项目（Go、Node.js、Python、Rust、Java 等）。

使用autoresearch实现本项目Issue#2：
[![asciicast](https://asciinema.org/a/KdHGFHK6pcelUdPg.svg)](https://asciinema.org/a/KdHGFHK6pcelUdPg)

[![asciinema](https://asciinema.org/a/你的录制ID.svg)](https://asciinema.org/a/你的录制ID)



## 架构图

![](docs/architecture.png)

图中展示了 autoresearch 的核心架构:
- **GitHub Issue** → 触发输入
- **run.sh** → 核心运行器
- **.autoresearch/** → 日志记录
- **Claude / Codex / OpenCode** → 三个 Agent 轮转审核
- **Score ≥ 85?** → 评分门控,超过85分代码就合格了
- **PASS** → 自动创建 PR → 合并 → 关闭 Issue
- **FAIL** → 虚线回路，进入下一轮迭代

_底部斜体注释说明了 Agent 轮转公式：(iter − 1) % N。_


## 快速开始

先下载本项目到你的本地文件，可以下载压缩包或者使用`git clone`下载：
```bash
git clone git@github.com:smallnest/autoresearch.git
```

然后就可以使用`autoresearch/run.sh` 执行自动化开发工作了：
```bash
# 处理当前目录项目的 Issue#10
autoresearch/run.sh 10

# 处理指定目录项目的 Issue#10
autoresearch/run.sh -p /path/to/project 10

# 指定最大迭代次数为16次， 处理 Issue#10
autoresearch/run.sh -p /path/to/project 10 16

# 调整达标线为90分，处理 Issue#10
PASSING_SCORE=90 autoresearch/run.sh 10

# 指定启用的 agents 及顺序（首个 agent 做初始实现）
autoresearch/run.sh -a claude,codex 10

# 自定义审核轮转顺序
autoresearch/run.sh -a opencode,claude,codex 10

# 继续处理 Issue#42，默认追加 42 次迭代
autoresearch/run.sh -c 42

# 继续处理 Issue#42，追加 10 次迭代
autoresearch/run.sh -c 42 10
```

## 前置条件

需要安装这些工具。

> 这三个Coding CLI你按需安装，如果你想使用这三个，那么就全部工具。

```bash
gh auth status          # GitHub CLI, https://cli.github.com/
which claude            # Claude Code CLI, https://code.claude.com/docs/en/quickstart
which codex             # OpenAI Codex CLI, https://developers.openai.com/codex/cli
which opencode          # OpenCode CLI, https://opencode.ai/download
```

项目需有对应语言的构建工具（Go/Node/Python/Rust/Java）。

## 推荐工作流：从 PRD 到自动实现

本节介绍一个完整的端到端工作流，从产品需求文档 (PRD) 开始，到自动创建 GitHub Issues，再到使用 autoresearch 逐一实现。

### 步骤概览

```
PRD 生成 → Issue 拆分与创建 → 选择 Issue → autoresearch 实现 → 选择下一个 Issue → ...
```

![](docs/workflow.png)

### Step 1: 生成 PRD

> 首先在你的智能体(claudecode/codex/opencode/openclaw/hermes等)中安装技能`https://github.com/snarktank/ralph/tree/main/skills/prd`。

使用 `/prd` skill 生成交付需求文档：

```
/prd 为本项目创建一个桌面 app
```

Skill 会：
1. 调研项目代码库，理解上下文
2. 提出澄清问题（如：目标用户、技术栈偏好、核心功能）
3. 生成结构化 PRD，保存到 `tasks/prd-[feature-name].md`

PRD 包含：
- **Introduction**: 项目背景、代码位置、技术栈
- **Goals**: 核心目标列表
- **User Stories**: 用户故事（US-001 ~ US-NNN），每个含验收标准
- **Functional Requirements**: 功能需求编号（FR-1 ~ FR-N）
- **Non-Goals**: 明确排除项
- **Technical Considerations**: 架构、依赖、技术选型

### Step 2: 拆分为 GitHub Issues

基于 PRD 中的 User Stories 拆分为细粒度 Issue：

**拆分原则**：
- 每个 Issue 可在单次开发会话中完成
- 有明确的验收标准（checkbox）
- 标注依赖关系
- Issue 标题加统一前缀（如 `[desktop-app]`）

**Issue 结构**：
```markdown
## Description
简要描述该 Issue 要完成的工作。

## Acceptance Criteria
- [ ] 具体可验证的验收标准
- [ ] Typecheck/lint passes
- [ ] Verify in browser（涉及 UI 的 Issue）

## Dependencies
依赖的前置 Issue 编号

## Technical Notes
实现提示和技术选型建议
```

**创建 Issue**：
```bash
# 创建标签
gh label create "desktop-app" --color "#0E8A16"

# 批量创建 Issues
gh issue create --title "[desktop-app] 项目脚手架搭建" \n  --body "$(cat issue-22.md)" \n  --label "desktop-app,enhancement"
```

实际上不必这么复杂，你可以简单的使用智能体去做这个事情，你只需告诉智能体下面的文字：
```text
基于 PRD 中的 User Stories 拆分为细粒度 Issue,并在github上创建这些issue。

**拆分原则**：
- 每个 Issue 可在单次开发会话中完成
- 有明确的验收标准（checkbox）
- 标注依赖关系
```

### Step 3: 选择 Issue 并自动实现

选择一个无依赖或依赖已完成的 Issue：

```bash
# 实现 Issue #22
./run.sh 22

# 或指定项目路径
./run.sh -p /path/to/project 22
```

autoresearch 会：
1. 规划阶段：拆分 subtasks（如需要）
2. 迭代实现：首个 agent 实现 → 轮转审核 → 修复 → 评分
3. 质量门禁：Build/Lint/Test + LLM 评分 ≥ 85
4. 自动收尾：创建 PR → 合并 → 评论 Issue → 关闭 Issue

### Step 4: 继续下一个 Issue

上一个 Issue 完成后，选择下一个：

```bash
# 实现 Issue #23（依赖 #22，现已满足）
./run.sh 23
```

重复直到所有 Issue 完成。

### 完整示例：Desktop App

以本项目的 Desktop App 为例，完整流程如下：

| 阶段 | 操作 | 产出 |
|------|------|------|
| PRD 生成 | `/prd 为本项目创建一个桌面 app` | `tasks/prd-desktop-app.md` |
| Issue 拆分 | 基于 10 个 User Stories 拆分 | 19 个 Issues (#22 ~ #40) |
| 首个 Issue | `./run.sh 22` | 脚手架搭建完成，PR #42 合并 |
| 后续 Issues | `./run.sh 23`, `./run.sh 24`, ... | 逐一实现各功能模块 |

详细过程记录见 [docs/desktop-app-prd-to-issues.md](docs/desktop-app-prd-to-issues.md)。

### 依赖关系图示例

```
#22 (脚手架)
 ├── #23 (布局)
 ├── #24 (目录选择) ── #26 (Issue 列表)
 ├── #25 (Agent 选择器) ── #28 (进程管理)
 └── #39 (系统托盘)
```

按依赖顺序实现：先 `#22`，再并行 `#23/#24/#25/#39`，最后 `#26/#28`。

---

## 单 Issue 工作流程

单个 Issue 的内部处理流程：

```
Issue -> 首个 Agent 实现 -> [按指定顺序轮流审核+修复] -> 自动 PR -> 自动合并 -> 自动关闭 Issue
```

- **默认 agents**: `claude,codex,opencode`
- **迭代 1**: `-a` 列表中的第一个 agent 初始实现
- **迭代 2+**: 所有启用的 agents 按顺序轮流审核并修复
- 评分达标（默认 >= 85）后自动创建 PR、合并、评论并关闭 Issue

## 项目自定义配置

在项目目录下创建 `.autoresearch/`：

```
.autoresearch/
├── agents/
│   ├── codex.md          # 自定义 Codex 指令
│   ├── claude.md         # 自定义 Claude 指令
│   └── opencode.md       # 自定义 OpenCode 指令
├── program.md            # 自定义实现规则与约束
├── workflows/            # 各 Issue 详细记录（自动生成）
└── results.tsv           # 处理结果日志（自动生成）
```

如无自定义文件，使用本目录下的默认配置。

## 按语言裁剪 program.md

`program.md` 的「代码规范」章节包含多种语言的规范模板。使用前应根据目标项目的实际语言进行裁剪，只保留相关规范，删除无关规范，以减少 token 消耗并避免干扰。

### 操作方式

1. 确认项目的编程语言（通过检测文件判断，如 `go.mod` → Go，`package.json` → Node.js，`Cargo.toml` → Rust 等）
2. 保留「通用规范」和与项目语言对应的规范章节
3. 删除其余语言规范章节,节省Token
4. 如果项目是前端项目，保留「前端代码规范」章节

### 示例

假设项目是一个 **Go** 后端项目，`program.md` 中代码规范部分应只保留：

```markdown
## 代码规范

### 通用规范

（保留）

### Go 代码规范

（保留）

（删除 Python / TypeScript/JavaScript / Rust / 前端 等无关章节）
```


## 配置参数

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `-p <path>` | 当前目录 | 项目路径 |
| `-a <agents>` | `claude,codex,opencode` | 指定启用 agents 及顺序（第一个负责初始实现） |
| `-c` | 关闭 | 继续模式，从上次中断的迭代继续 |
| `PASSING_SCORE` | 85 | 达标评分线（百分制） |
| `MAX_CONSECUTIVE_FAILURES` | 3 | 连续失败停止阈值 |
| `MAX_RETRIES` | 5 | 单次 agent 调用重试次数 |

## 文件说明

| 文件 | 用途 |
|------|------|
| `run.sh` | 主脚本 |
| `lib/agent_logic.sh` | agent 列表解析与轮转共享逻辑 |
| `program.md` | 默认实现规则与约束 |
| `agents/*.md` | Agent 提示词模板 |
| `tests/test_agent_logic.sh` | agent 选择与顺序逻辑测试 |


## 类似项目

- [snarktank/ralph](https://github.com/snarktank/ralph)

### autoresearch vs ralph 对比

| 维度 | **autoresearch** | **ralph** |
|------|-----------------|-----------|
| **核心理念** | GitHub Issue → 规划拆子任务 → 多 Agent 轮转审核 → PR/合并/关闭 | PRD → 单 Agent 迭代实现用户故事 → 完成 |
| **输入** | GitHub Issue 编号 | PRD（`prd.json`，结构化用户故事） |
| **任务分解** | 规划阶段自动拆 `tasks.json`（含优先级、验收条件、类型标记），失败回退一次性实现 | PRD 预拆分为多个用户故事，每迭代完成一个 |
| **Agent 模型** | 多 Agent 轮转（Claude/Codex/OpenCode），迭代间换人审核 | 单 Agent 反复启动新实例（Amp 或 Claude Code），每次干净上下文 |
| **硬门禁** | Build → Lint → Test 三重自动化检查，不通过则反馈给 Agent 修复 | 类型检查 + Lint + 测试，必须全部通过才更新状态 |
| **软门禁** | LLM 多维度评分 ≥ 85/100（正确性 35% / 测试 25% / 代码质量 20% / 安全 10% / 性能 10%） | 无 LLM 评分，完全依赖自动化工具链 |
| **审核机制** | 不同 Agent 交叉审核 + 修复（Agent 轮转公式），兼顾 LLM 评分和工具检查 | 无独立审核，靠自动化测试和 lint 守关 |
| **记忆模型** | `progress.md` 跨迭代经验积累 + `tasks.json` 任务状态 + 日志文件 | `progress.txt`（经验日志）+ `prd.json`（故事状态）+ `AGENTS.md`（目录级知识）+ Git 历史 |
| **上下文溢出** | 自动检测 → 保存进度到 `progress.md` → 交接给下一 Agent（最多 3 次） | 右尺寸故事策略预防溢出；Amp 用户实验性 `autoHandoff`（90% 上下文容量时触发） |
| **UI 验证** | 浏览器截图 + LLM 视觉验证（Playwright/Chrome DevTools MCP，最多 3 次重试） | `dev-browser` skill 浏览器验证，作为质量门禁一部分 |
| **PR/合并** | 自动创建 PR → 合并 → 评论 Issue → 关闭 Issue | 完成后发 `COMPLETE` 信号，未内置 PR 创建 |
| **归档机制** | 自动检测并归档旧 workflow 到 `archive/YYYY-MM-DD-issue-N/`，支持后缀去重 | 检测 `prd.json` 分支名变更时自动归档旧文件到日期目录 |
| **Continue 模式** | `-c` 从中断处恢复（迭代数、分数、连续失败数、子任务状态全部恢复） | 无内置继续模式，需手动重启 |
| **配置体系** | 两层覆盖：默认 `program.md` + 项目级 `.autoresearch/`；支持 `-a` 指定 Agent 顺序 | `prompt.md`(Amp) / `CLAUDE.md`(Claude Code) 指导行为 |
| **插件系统** | ClaudeCode/Codex/OpenCode自带的Skills 系统 | Skills 系统（`/prd` 生成 PRD、`/ralph` 转换 JSON），支持本地/全局/市场安装 |
| **实现语言** | Bash 脚本 `run.sh` + `lib/agent_logic.sh` | 单个 Bash 脚本 `ralph.sh` + React 流程图可视化 |
| **重试/容错** | 指数退避重试（5 次）+ 连续失败硬停止（3 次）+ 上下文溢出自动交接 + Continue 模式 | 质量检查不过则不更新状态，下次重试同一故事 |
| **沙箱/安全** | `--dangerously-skip-permissions` / `--full-auto`，无沙箱 | 同样无沙箱，全权委托 |

#### 各自优势

**autoresearch 优势：**
- **双轨质量门禁**：硬门禁（Build/Lint/Test）+ 软门禁（LLM 多维度评分），比单一策略覆盖面更广
- **多 Agent 交叉审核**：不同 Agent 轮转审核，提供真正的"第二双眼睛"视角
- **GitHub 端到端自动化**：Issue → 规划 → 实现 → 审核 → PR → 合并 → 关闭，全自动闭环
- **上下文溢出自动交接**：检测到溢出立即保存进度并交接给下一 Agent，不丢失工作成果
- **Continue 模式**：中断后可恢复全部状态继续执行
- **UI 验证**：浏览器截图 + LLM 视觉校验，前端任务质量更有保障
- **灵活 Agent 编排**：`-a` 参数自由选择启用哪些 Agent 及顺序

**ralph 优势：**
- **PRD 驱动**：从产品需求文档出发，语义更丰富，适合从零开始的功能开发
- **四通道记忆**：`progress.txt` + `AGENTS.md` + `prd.json` + Git 形成完整知识体系，`AGENTS.md` 的目录级知识积累实现自进化
- **确定性质量门禁**：完全基于工具链，不依赖 LLM 输出解析，更稳定可预测
- **Skills 插件系统**：`/prd` 和 `/ralph` 技能辅助 PRD 生成与转换，可扩展
- **流程序可视化**：内置 React 交互式流程图，直观理解工作流
- **故事右尺寸设计**：从源头控制任务粒度，减少上下文溢出风险

#### 关键差异总结

1. **驱动方式**：autoresearch 由 GitHub Issue 驱动，新项目建好 Issue 即可从零开发，现有项目则用于迭代；ralph 由 PRD 驱动，从产品需求文档出发规划功能。
2. **质量门禁哲学**：autoresearch 采用硬门禁（工具链）+ 软门禁（LLM 评分）双轨制，既保证确定性又兼顾灵活性；ralph 纯粹依赖工具链，更稳健但覆盖面窄。
3. **Agent 协作**：autoresearch 多 Agent 轮转交叉审核，ralph 单 Agent 反复迭代——前者获得不同视角，后者上下文更一致。
4. **端到端程度**：autoresearch 真正做到 Issue → 合并的全自动闭环（含 Continue 恢复）；ralph 止步于代码完成，需人工创建 PR。
5. **知识积累**：ralph 的 `AGENTS.md` 目录级知识系统更成熟；autoresearch 的 `progress.md` 提供跨迭代经验传递但粒度较粗。
