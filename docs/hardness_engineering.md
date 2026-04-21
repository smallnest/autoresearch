# Hardness Engineering 特性清单

本文档记录 autoresearch 项目中 "hardness engineering" 相关的特性规划和实现状态（Issue #48 ~ #57）。这些特性旨在增强脚本的健壮性，防止 agent 调用异常导致整个流程卡死或失败。

## 总览

| # | Issue | 特性 | 优先级 | 状态 |
|---|-------|------|:------:|:----:|
| 1 | [#48 Agent 调用超时机制](https://github.com/smallnest/autoresearch/issues/48) | `timeout_wrapper` 包裹 agent 调用，超时自动重试 | 高 | 已实现 |
| 2 | [#49 全局 trap 清理机制](https://github.com/smallnest/autoresearch/issues/49) | `trap cleanup EXIT` 防止孤儿进程 | 高 | 未实现 |
| 3 | [#50 Git 操作容错](https://github.com/smallnest/autoresearch/issues/50) | push/merge 失败时清理和友好提示 | 高 | 未实现 |
| 4 | [#51 Continue 模式 git 状态校验](https://github.com/smallnest/autoresearch/issues/51) | 检测 dirty 文件、分支分叉、tasks.json 有效性 | 中 | 未实现 |
| 5 | [#52 tasks.json 原子写入](https://github.com/smallnest/autoresearch/issues/52) | mktemp + 校验，防写入中断损坏 | 中 | 未实现 |
| 6 | [#53 Agent 输出文件校验](https://github.com/smallnest/autoresearch/issues/53) | 成功退出前检查文件非空，空文件触发重试 | 中 | 未实现 |
| 7 | [#54 磁盘空间预检](https://github.com/smallnest/autoresearch/issues/54) | 启动时 `df` 检查，低于阈值 warn/abort | 低 | 未实现 |
| 8 | [#55 API 限速全局感知](https://github.com/smallnest/autoresearch/issues/55) | 全局冷却 + 跨 agent 共享限速状态 | 低 | 未实现 |
| 9 | [#56 Agent 子进程资源限制](https://github.com/smallnest/autoresearch/issues/56) | ulimit/prlimit/cgroup 限制内存和 CPU | 低 | 未实现 |
| 10 | [#57 Prompt 裁剪策略导致关键信息丢失](https://github.com/smallnest/autoresearch/issues/57) | 结构化裁剪保留关键上下文，限制裁剪次数 | 高 | 未实现 |

---

## 优先级：高

### 1. Agent 调用超时机制 (Issue #48)

**状态：已实现**

**问题：** agent (codex/claude/opencode) 调用没有超时限制，如果 agent 进程挂死（无限循环、等待用户输入等），整个 `run.sh` 会永远卡住。这是最严重的缺口，直接导致脚本卡死。

**实现方案：**
- **`AGENT_TIMEOUT` 环境变量**（默认 600 秒），可通过环境变量覆盖
- **`timeout_wrapper` 函数**：优先使用 GNU `timeout`/`gtimeout`，回退到 shell 原生后台进程 + sleep + kill 方案，确保 macOS/Linux 兼容
- **超时退出码 124** 在 `run_with_retry` 中被识别为可重试错误，触发重试而非直接失败
- codex/opencode/claude 三个 agent 调用均被 timeout 机制包裹

**关键代码位置：**
- 变量定义：`run.sh:19` (注释)、`run.sh:55` (默认值)
- `timeout_wrapper` 函数：`run.sh:338-367`
- agent 调用包裹：`run.sh:514`、`run.sh:517`、`run.sh:520`
- 超时重试逻辑：`run.sh:539-541`

---

### 2. 全局 trap 清理机制 (Issue #49)

**状态：未实现**

**问题：** 脚本没有全局的 `trap cleanup EXIT`，中断时 spinner 进程、agent 子进程都会变成孤儿进程。

**方案：**
- 在脚本入口添加 `trap cleanup EXIT INT TERM`
- cleanup 函数负责：杀掉 spinner 进程、杀掉残留 agent 子进程、清理临时文件、记录中断位置到 log.md
- 复用已有的 `stop_spinner` 和 `cleanup_dev_server` 逻辑

---

### 3. Git 操作容错 (Issue #50)

**状态：未实现**

**问题：** `git push` 和 `gh pr merge` 在 `set -e` 下失败会直接 abort，没有任何清理和友好提示。失败后状态不一致，用户无法恢复。

**方案：**
- `git push -u origin` 和 `gh pr merge` 加 `|| { error handling; return 1 }` 保护
- push 失败后应记录日志、尝试 stash/restore、给出可操作的建议
- PR 创建成功但 merge 失败时，应记录 PR URL 供用户手动处理
- 合并后的 branch 清理（checkout main、pull、branch -D）失败不应影响主流程

---

### 10. Prompt 裁剪策略导致关键信息丢失 (Issue #57)

**状态：未实现**

**问题：** `trim_prompt_for_codex_retry()` 在处理 agent 失败时暴力裁剪 prompt，存在以下严重问题：
- **丢失关键上下文**：`"${prompt: -4000}"` 只保留最后 4000 字符，把 Issue 描述、项目路径、语言、子任务要求、验收标准等头部关键信息全部丢弃
- **禁止所有 tool call**：裁剪后添加 `"Do NOT use any tool/function calls"` 前缀，让 agent 无法读取文件、编辑代码
- **裁剪是永久性的**：直接覆盖原始 prompt 变量，后续重试中继续使用裁剪后的版本，越裁越短
- **输出无意义**：裁剪后的 agent 既不知道任务上下文，又不能用工具，输出内容会被误判为正常输出

**方案：**
- **保留结构化裁剪**：保留头部关键信息（Issue 描述、项目路径、子任务详情）+ 尾部（最新 review 反馈），去掉 `program.md` 等冗长但非必要内容
- **限制裁剪行为**：只触发一次（设置标志位防止逐次缩短）；只在 `has_invalid_tool_call` 场景触发，其他错误场景不裁剪
- **可选：分段式 prompt**：将 prompt 分为必要段（Issue + 子任务）和可选段（program.md + 示例），裁剪时只去掉可选段

---

## 优先级：中

### 4. Continue 模式 git 状态校验 (Issue #51)

**状态：未实现**

**问题：** `restore_continue_state()` 只检查分支是否存在，不检查 working tree 是否有未提交的 dirty 文件、本地分支与 remote tracking branch 是否分叉、上次中断留下的未完成状态。存在数据一致性风险。

**方案：**
- continue 时检测 `git status --porcelain`，如有 dirty 文件提示用户或自动 stash
- 检测与 remote 的分叉，提示是否 rebase
- 校验 tasks.json 的 JSON 有效性

---

### 5. tasks.json 原子写入 (Issue #52)

**状态：未实现**

**问题：** `mark_subtask_passed()` 先 `jq > tmpfile` 再 `mv`，如果中途被 kill，文件可能损坏（空文件或截断的 JSON）。存在数据一致性风险。

**方案：**
- 使用 `mktemp` 在同一文件系统创建临时文件（确保 `mv` 是原子操作）
- 写入前校验 jq 输出的 JSON 有效性
- continue 启动时校验 tasks.json 完整性，损坏则回退到原始模式

---

### 6. Agent 输出文件校验 (Issue #53)

**状态：未实现**

**问题：** `run_with_retry` 返回成功后，调用方直接 `cat "$log_file"`，没有检查文件是否存在且非空。文件系统错误或竞态条件可能导致空读。

**方案：**
- 在 `run_with_retry` 成功退出前，增加文件存在性和非空检查
- 调用方在读取前也加防御性检查
- 空文件情况触发重试而非返回空内容

---

## 优先级：低

### 7. 磁盘空间预检 (Issue #54)

**状态：未实现**

**问题：** 脚本运行前没有检查磁盘空间，中途磁盘满会导致日志写入失败、`set -e` abort、mktemp 失败、tasks.json 损坏，且没有有用的错误信息。

**方案：**
- 在 `check_dependencies` 阶段增加磁盘空间检查（`df`）
- 预留阈值（如 1GB），不足则 warn 或 abort
- 运行中关键写入操作（tasks.json、log.md）加入错误检查

---

### 8. API 限速全局感知 (Issue #55)

**状态：未实现**

**问题：** 当前每个 agent 独立重试 5 次，同一次 API 限速故障可能烧掉 15 次重试（3 agent × 5），浪费时间和配额。

**方案：**
- 检测到 rate limit 错误后，全局冷却（如 sleep 60s）而非逐个重试
- 跨 agent 共享限速状态（写文件标记到 $WORK_DIR）
- 区分 transient 429（可重试）和 quota exceeded（应立即停止）

---

### 9. Agent 子进程资源限制 (Issue #56)

**状态：未实现**

**问题：** agent 子进程没有资源限制，一个失控的 agent 可能吃光系统内存或 CPU。

**方案：**
- 用 `ulimit -v` 限制 agent 子进程内存
- 或用 `prlimit` / cgroup 进一步控制
- 考虑在超时机制的基础上加 CPU 时间限制
