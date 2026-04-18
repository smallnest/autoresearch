# Autoresearch for Software Development

> 全自动化软件开发工具，你只需负责喝茶和睡觉。
> 一觉醒来,Features 全自动高质量的实现了。

基于 [karpathy/autoresearch](https://github.com/karpathy/autoresearch) 思想实现的通用的基于GitHub Issue管理的全自动化开发工具。

支持任意 Git + GitHub 项目（Go、Node.js、Python、Rust、Java 等）。

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

```bash
gh auth status          # GitHub CLI
which claude            # Claude Code CLI
which codex             # OpenAI Codex CLI
which opencode          # OpenCode CLI
```

项目需有对应语言的构建工具（Go/Node/Python/Rust/Java）。

## 工作流程

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
