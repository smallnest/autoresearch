# Autoresearch for Software Development

> 全自动化软件开发工具，你只需负责喝茶和睡觉。
> 一觉醒来，Features 全自动高质量的实现了。

![宣传视频](docs/autoresearch-promo-cn.gif)

基于 [karpathy/autoresearch](https://github.com/karpathy/autoresearch) 思想实现的通用的全自动化开发工具。支持 **GitHub Issue** 和**本地 Issue** 两种模式，适用于任意 Git 项目（Go、Node.js、Python、Rust、Java 等）。

使用 autoresearch 实现本项目 Issue#2：
[![asciicast](https://asciinema.org/a/KdHGFHK6pcelUdPg.svg)](https://asciinema.org/a/KdHGFHK6pcelUdPg)

---

## 目录

- [快速开始](#快速开始)
- [前置条件](#前置条件)
- [项目架构](#项目架构)
- [工作流程](#工作流程)
- [本地 Issue 模式](#本地-issue-模式)
- [工具配置](#工具配置)
- [与 ralph 对比](#与-ralph-对比)

---

## 快速开始

```bash
# 下载项目
git clone git@github.com:smallnest/autoresearch.git

# 处理当前目录项目的 Issue#10
autoresearch/run.sh 10

# 处理指定目录项目的 Issue#10
autoresearch/run.sh -p /path/to/project 10

# 指定最大迭代次数为 16 次
autoresearch/run.sh -p /path/to/project 10 16

# 调整达标线为 90 分
PASSING_SCORE=90 autoresearch/run.sh 10

# 指定启用的 agents 及顺序（首个 agent 做初始实现）
autoresearch/run.sh -a claude,codex 10

# 继续处理 Issue#42，追加 10 次迭代
autoresearch/run.sh -c 42 10

# 处理本地 Issue #8（从 .autoresearch/issues/ 读取）
autoresearch/run.sh --issues-dir=.autoresearch/issues 8
```

## 前置条件

需要安装以下工具（按需安装）：

```bash
gh auth status          # GitHub CLI（仅 GitHub 模式需要）
which claude            # Claude Code CLI
which codex             # OpenAI Codex CLI
which opencode          # OpenCode CLI
```

项目需有对应语言的构建工具（Go/Node/Python/Rust/Java）。

---

## 项目架构

![](docs/architecture.png)

核心流程：

| 组件 | 说明 |
|------|------|
| **GitHub Issue / 本地 Issue** | 触发输入 |
| **run.sh** | 核心运行器 |
| **Claude / Codex / OpenCode** | 三个 Agent 轮转审核 |
| **Score ≥ 85?** | 评分门控 |
| **PASS** | 自动创建 PR → 合并 → 关闭 Issue |
| **FAIL** | 进入下一轮迭代修复 |

Agent 轮转公式：`(iter − 1) % N`

---

## 工作流程

### 单 Issue 流程

```
Issue → 首个 Agent 实现 → 轮转审核+修复 → 自动 PR → 合并 → 关闭 Issue
```

- **迭代 1**: `-a` 列表中的第一个 agent 初始实现
- **迭代 2+**: 所有启用的 agents 按顺序轮流审核并修复
- 评分达标（默认 ≥ 85）后自动创建 PR、合并、评论并关闭 Issue

### 推荐工作流：从 PRD 到自动实现

完整端到端工作流：**PRD 生成 → Issue 拆分 → autoresearch 实现**

```
PRD 生成 → Issue 拆分与创建 → 选择 Issue → autoresearch 实现 → 选择下一个 Issue → ...
```

![](docs/workflow.png)

#### Step 1: 生成 PRD

使用 `/prd` skill 生成交付需求文档：

```
/prd 为本项目创建一个桌面 app
```

#### Step 2: 拆分为 GitHub Issues

让智能体基于 PRD 拆分 Issue：

```text
基于 PRD 中的 User Stories 拆分为细粒度 Issue，并在 GitHub 上创建这些 issue。

拆分原则：
- 每个 Issue 可在单次开发会话中完成
- 有明确的验收标准（checkbox）
- 标注依赖关系
```

#### Step 3: 选择 Issue 并自动实现

```bash
./run.sh 22
```

autoresearch 会：
1. 规划阶段：拆分 subtasks（如需要）
2. 迭代实现：首个 agent 实现 → 轮转审核 → 修复 → 评分
3. 质量门禁：Build/Lint/Test + LLM 评分 ≥ 85
4. 自动收尾：创建 PR → 合并 → 评论 Issue → 关闭 Issue

#### 完整示例

以本项目 Desktop App 为例：19 个 Issues (#22 ~ #40) 从 PRD 到全部实现。

详细过程见 [docs/desktop-app-prd-to-issues.md](docs/desktop-app-prd-to-issues.md)。

---

## 本地 Issue 模式

除了从 GitHub 拉取 Issue，autoresearch 还支持从项目本地目录读取 Issue 文件，无需 GitHub 即可运行。适合本地项目、内网项目或不想创建 GitHub Issue 的场景。

### 快速开始

```bash
# 1. 创建 issues 目录
mkdir -p .autoresearch/issues

# 2. 创建 Issue 文件（命名格式：issue-NNN-描述.md）
cat > .autoresearch/issues/issue-008-add-login.md << 'EOF'
# 添加登录功能

实现用户登录页面，包括：
- 用户名/密码输入框
- 表单验证
- 登录 API 调用
- 错误提示
EOF

# 3. 运行（自动检测本地文件）
./run.sh 8
```

### Issue 文件格式

- **位置**：`$PROJECT_ROOT/.autoresearch/issues/`（默认）或 `--issues-dir` 指定
- **命名**：`issue-NNN-描述.md`，编号补零到 3 位（如 `issue-008-add-login.md`）
- **内容**：第一个 `# 标题` 行作为 Issue 标题，其余内容作为 Issue 正文
- **匹配**：CLI 传入的编号 `8` 会匹配 `issue-008-*.md` 或 `issue-8-*.md`

### 运行结束后

- 代码提交到本地分支（不推送远程、不创建 PR、不合并）
- 处理结果自动追加到 Issue 文件末尾：

```markdown
---

## 自动处理结果

- **评分**: 92/100
- **迭代次数**: 3
- **实现方式**: autoresearch 多 agent 迭代 (claude codex opencode)
- **分支**: feature/issue-8
- **完成时间**: 2026-04-27 15:30:00
- 子任务: 2/2 完成

...日志内容...

该 Issue 已由 autoresearch 自动实现。
```

### 命令行参数

```bash
# 自动检测模式（默认目录下有匹配文件即生效）
./run.sh 8

# 手动指定 issues 目录
./run.sh --issues-dir=.autoresearch/issues 8

# 指定项目路径 + 本地模式
./run.sh -p /path/to/project --issues-dir=.autoresearch/issues 8

# 组合其他参数
./run.sh --issues-dir=.autoresearch/issues 8 10   # 最多迭代10次
```

### 与 GitHub 模式对比

| | GitHub 模式 | 本地模式 |
|---|---|---|
| Issue 来源 | `gh issue view` | 本地 `.md` 文件 |
| 需要 `gh` CLI | 是 | 否 |
| 需要 GitHub remote | 是 | 否 |
| 推送/PR/合并 | 自动执行 | 不执行 |
| 评论/关闭 Issue | 自动执行 | 不执行 |
| 结果记录 | PR 评论 + 关闭 Issue | 追加到文件末尾 |

### 模式自动切换

两种模式完全兼容，互不影响：

- 有匹配的本地 Issue 文件 → 自动进入本地模式
- 没有本地文件 → 走 GitHub 流程（`gh issue view` → push → PR → merge → close）

同一项目可以混合使用：

```bash
./run.sh 8    # .autoresearch/issues/issue-008-*.md 存在 → 本地模式
./run.sh 42   # 没有对应的本地文件 → GitHub 模式
```

---

## 工具配置

### 项目自定义配置

在项目目录下创建 `.autoresearch/`：

```
.autoresearch/
├── agents/
│   ├── codex.md          # 自定义 Codex 指令
│   ├── claude.md         # 自定义 Claude 指令
│   └── opencode.md       # 自定义 OpenCode 指令
├── issues/               # 本地 Issue 文件（issue-NNN-描述.md）
├── program.md            # 自定义实现规则与约束
├── workflows/            # 各 Issue 详细记录（自动生成）
└── results.tsv           # 处理结果日志（自动生成）
```

### 命令行参数

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `-p <path>` | 当前目录 | 项目路径 |
| `-a <agents>` | `claude,codex,opencode` | 指定启用 agents 及顺序 |
| `-c` | 关闭 | 继续模式，从上次中断的迭代继续 |
| `--issues-dir=<path>` | `.autoresearch/issues` | 本地 Issue 目录（启用本地模式） |
| `PASSING_SCORE` | 85 | 达标评分线（百分制） |
| `MAX_CONSECUTIVE_FAILURES` | 3 | 连续失败停止阈值 |
| `MAX_RETRIES` | 5 | 单次 agent 调用重试次数 |

### 裁剪 program.md

`program.md` 包含多种语言的规范模板。使用前应根据目标项目语言裁剪，只保留相关规范以减少 token 消耗。

**示例**：Go 后端项目只需保留「通用规范」和「Go 代码规范」章节，删除 Python/TypeScript/Rust/前端等无关章节。

### 文件说明

| 文件 | 用途 |
|------|------|
| `run.sh` | 主脚本 |
| `lib/agent_logic.sh` | agent 列表解析与轮转共享逻辑 |
| `program.md` | 默认实现规则与约束 |
| `agents/*.md` | Agent 提示词模板 |
| `tests/test_agent_logic.sh` | agent 选择与顺序逻辑测试 |

---

## 与 ralph 对比

[ralph](https://github.com/snarktank/ralph) 是类似的自动化开发工具。

### 核心差异

| 维度 | **autoresearch** | **ralph** |
|------|-----------------|-----------|
| **驱动方式** | GitHub Issue / 本地 Issue | PRD（`prd.json`） |
| **Agent 模型** | 多 Agent 轮转交叉审核 | 单 Agent 反复迭代 |
| **质量门禁** | 硬门禁（Build/Lint/Test）+ 软门禁（LLM 评分） | 纯工具链检查 |
| **审核机制** | 不同 Agent 交叉审核 | 无独立审核 |
| **端到端** | Issue → PR → 合并 → 关闭（全自动闭环） | 止步于代码完成 |
| **Continue 模式** | 支持 `-c` 恢复 | 无 |
| **UI 验证** | 浏览器截图 + LLM 视觉验证 | `dev-browser` skill |

### 各自优势

**autoresearch 优势：**
- 双轨质量门禁覆盖更广
- 多 Agent 交叉审核提供不同视角
- GitHub 端到端自动化闭环，也支持本地项目无 GitHub 运行
- 上下文溢出自动交接
- Continue 模式支持中断恢复

**ralph 优势：**
- PRD 驱动，语义更丰富
- 四通道记忆形成完整知识体系
- 确定性质量门禁更稳定
- Skills 插件系统可扩展
- 内置流程序可视化

---

## 类似项目

- [snarktank/ralph](https://github.com/snarktank/ralph)
- [karpathy/autoresearch](https://github.com/karpathy/autoresearch)（原版思想）
- [达尔文.skill](https://github.com/alchaincyf/darwin-skill): 使用 autoresearch 优化Skill, 花叔出品