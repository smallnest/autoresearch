# PRD: Autoresearch Desktop App

## Introduction

为 autoresearch 命令行工具构建一个全功能桌面管理面板。当前 autoresearch 完全通过 CLI (`run.sh`) 操作，用户需要在终端中手动运行命令、查看日志文件来了解处理进度。本 Desktop App 将提供可视化界面，让开发者通过 GUI 完成所有操作：启动/停止 Issue 处理、实时监控进度与日志、管理配置、查看历史记录与评分趋势，以及审核自动创建的 PR。

代码仓库位置：`desktop_app/` 目录（相对于 autoresearch 项目根目录）。
技术栈：Tauri 2 + React（TypeScript），跨平台支持 macOS（优先）、Windows、Linux。

## Goals

- 提供直观的 GUI 替代 CLI 操作，降低使用门槛
- 实时可视化展示 autoresearch 迭代循环的每一步状态
- 统一管理所有配置（agents、program.md、passing score 等）
- 集中展示历史处理结果、评分趋势、迭代日志
- 支持在 GUI 中审核和操作自动创建的 PR

## User Stories

### US-001: 项目目录选择与初始化
**Description:** 作为开发者，我希望能通过 GUI 选择项目目录，App 自动识别该目录下的 `.autoresearch/` 配置，无需手动输入路径。

**Acceptance Criteria:**
- [ ] 提供文件夹选择对话框，选择后显示项目路径
- [ ] 挑选要使用的agent和顺序，可以以标签选择框的方式，以便可以调整选择的agent的顺序
- [ ] 自动检测目录下是否存在 `.autoresearch/`、`program.md`、`agents/` 等配置
- [ ] 如果没有配置，提示用户是否从模板初始化
- [ ] 记住最近打开的项目路径，下次启动自动加载
- [ ] Typecheck/lint passes

### US-002: Issue 列表与选择
**Description:** 作为开发者，我希望能浏览 GitHub Issues 并选择要处理的 Issue，而不是在命令行中手动输入编号。

**Acceptance Criteria:**
- [ ] 从关联的 GitHub 仓库拉取 Open Issues 列表
- [ ] 显示 Issue 编号、标题、标签、创建时间
- [ ] 支持按标签过滤和关键词搜索
- [ ] 已处理过的 Issue 显示状态标记（已合并/进行中/失败）
- [ ] 点击 Issue 显示详情（描述、评论）
- [ ] Typecheck/lint passes

### US-003: 启动/停止 Issue 处理
**Description:** 作为开发者，我希望能通过 GUI 启动 autoresearch 处理指定的 Issue，并能在需要时停止。

**Acceptance Criteria:**
- [ ] 选择 Issue 后，可配置参数（max iterations、agents、passing score）
- [ ] 点击"开始"按钮启动 `run.sh`，支持 `-c` 续跑模式
- [ ] 运行中显示"停止"按钮，点击后优雅终止进程
- [ ] 一次只能运行一个任务（单项目模式）
- [ ] 进程异常退出时显示错误信息
- [ ] Typecheck/lint passes

### US-004: 实时进度与迭代状态
**Description:** 作为开发者，我希望能实时看到当前迭代的进度——处于哪个阶段（planning/implementation/review）、当前 subtask、评分结果。

**Acceptance Criteria:**
- [ ] 展示当前迭代编号和总迭代数（如 `3/16`）
- [ ] 显示当前阶段：Planning / Implementation / Review / Build/Lint/Test
- [ ] 如果有 subtask 系统，显示 subtask 进度条和各 subtask 状态（pending/passing/failing）
- [ ] 实时更新，无需手动刷新
- [ ] Typecheck/lint passes

### US-005: 实时日志查看
**Description:** 作为开发者，我希望能实时查看 agent 的输出日志，了解实现和 review 的详细过程。

**Acceptance Criteria:**
- [ ] 主日志区域实时滚动显示 `run.sh` 的 stdout/stderr
- [ ] 可按迭代查看各 agent 的输出日志（对应 `.autoresearch/workflows/issue-N/` 下的 log 文件）
- [ ] 支持日志搜索和按级别过滤（info/warn/error）
- [ ] 日志支持自动滚动到底部，也可手动暂停滚动
- [ ] Typecheck/lint passes

### US-006: 评分结果展示
**Description:** 作为开发者，我希望能直观看到每次 review 的评分，以及评分趋势。

**Acceptance Criteria:**
- [ ] 每次迭代完成后显示评分（如 `78/100`），用颜色区分（红 < 70、黄 70-84、绿 >= 85）
- [ ] 评分历史折线图，展示从第 1 次到当前迭代的评分变化
- [ ] 显示 review 的关键反馈摘要
- [ ] 达到 passing score 时有明确的通过提示
- [ ] Typecheck/lint passes

### US-007: 配置管理
**Description:** 作为开发者，我希望能通过 GUI 编辑 autoresearch 的配置文件，而不是手动编辑 markdown。

**Acceptance Criteria:**
- [ ] 可查看和编辑 `program.md`（代码规范部分）
- [ ] 可查看和编辑各 agent 配置（`agents/claude.md`、`agents/codex.md` 等）
- [ ] 可配置运行参数：passing score、agent 执行顺序、max iterations
- [ ] 编辑后保存到对应文件，立即生效
- [ ] 提供配置重置为默认值的选项
- [ ] Typecheck/lint passes

### US-008: 处理历史记录
**Description:** 作为开发者，我希望能查看所有历史处理记录，了解每个 Issue 的处理结果。

**Acceptance Criteria:**
- [ ] 列表展示所有处理过的 Issue，包含编号、标题、状态、评分、耗时
- [ ] 状态分为：成功（已合并）、进行中、失败、已中断
- [ ] 点击记录查看详情：所有迭代日志、评分、review 反馈
- [ ] 可导出某次处理的全量日志
- [ ] Typecheck/lint passes

### US-009: PR 审核与操作
**Description:** 作为开发者，我希望能直接在 App 中查看 autoresearch 自动创建的 PR，并进行合并/关闭操作。

**Acceptance Criteria:**
- [ ] PR 创建后自动弹出通知
- [ ] 展示 PR 信息：标题、描述、分支、文件变更统计
- [ ] 可查看 PR 的 diff（文件列表 + 代码差异）
- [ ] 提供"合并"和"关闭"按钮，调用 `gh` CLI 执行
- [ ] 操作前需确认弹窗
- [ ] Typecheck/lint passes

### US-010: 系统托盘与通知
**Description:** 作为开发者，我希望 App 在后台运行时能通过系统通知获知关键事件，无需一直盯着界面。

**Acceptance Criteria:**
- [ ] 最小化到系统托盘，后台持续运行
- [ ] 关键事件发送系统通知：迭代完成、达到 passing score、PR 已创建、处理失败
- [ ] 托盘图标右键菜单：显示主窗口、停止当前任务、退出
- [ ] 点击通知跳转到 App 对应页面
- [ ] Typecheck/lint passes

## Functional Requirements

- FR-1: App 启动时加载上次打开的项目目录，如无则显示项目选择引导页
- FR-2: 通过 GitHub CLI (`gh`) 获取 Issue 列表和 PR 信息，不直接调用 GitHub API
- FR-3: 通过 Tauri sidecar 或 shell command 调用 `run.sh`，捕获 stdout/stderr 用于实时展示
- FR-4: 实时监听 `.autoresearch/workflows/issue-N/` 目录变化，解析 log 文件更新 UI 状态
- FR-5: 解析 `tasks.json` 获取 subtask 结构和状态，渲染进度视图
- FR-6: 解析 `log.md` 和各迭代 log 文件提取评分和 review 反馈
- FR-7: 配置编辑器直接读写文件系统中的 `program.md` 和 `agents/*.md`
- FR-8: 运行参数（passing score、max iterations）通过 `run.sh` 的 CLI 参数或环境变量传递
- FR-8.1: 提供可视化 agent 选择器（标签选择框），支持勾选要使用的 agent 并通过拖拽调整执行顺序，所选 agent 列表作为参数传给 `run.sh`
- FR-9: 停止任务时发送 SIGTERM 给 `run.sh` 进程组，等待优雅退出
- FR-10: 支持 `run.sh -c` 续跑模式，从上次中断处继续
- FR-11: 系统通知通过 Tauri notification API 实现
- FR-12: 所有用户操作（启动、停止、合并 PR 等）需二次确认

## Non-Goals

- 不支持多项目管理（一次只绑定一个项目目录）
- 不支持团队协作功能（多用户、权限管理）
- 不内置 AI agent（仍然依赖外部 CLI 工具如 claude、codex、opencode）
- 不修改 `run.sh` 的核心逻辑，仅作为 GUI 前端调用它
- 不实现自动定时调度（如 cron 式定时处理 Issue）
- 不支持自定义主题/插件系统
- 不内置代码编辑器（PR diff 查看仅只读）

## Design Considerations

- 整体布局采用三栏结构：左侧导航栏（Issue 列表/历史/配置）、中间主内容区（进度/日志/PR 详情）、右侧信息面板（评分/状态摘要）
- 使用暗色主题为默认，契合开发者习惯
- 关键状态用颜色编码：绿色=成功/通过、黄色=进行中/警告、红色=失败/错误
- 日志区域使用等宽字体，支持语法高亮
- 图表使用轻量库（如 Recharts）展示评分趋势
- 遵循各平台的原生窗口管理习惯

## Technical Considerations

### 架构

```
desktop_app/                  # 桌面 App 代码目录（位于 autoresearch 项目根目录下）
├── src-tauri/           # Rust 后端
│   ├── src/
│   │   ├── main.rs      # Tauri 入口
│   │   ├── commands/     # Tauri commands（IPC handlers）
│   │   │   ├── project.rs    # 项目目录管理
│   │   │   ├── runner.rs     # run.sh 进程管理
│   │   │   ├── config.rs     # 配置文件读写
│   │   │   ├── issues.rs     # Issue/PR 查询（via gh）
│   │   │   └── watcher.rs    # 文件系统监听
│   │   └── utils/
│   └── Cargo.toml
├── src/                 # React 前端
│   ├── components/
│   ├── pages/
│   ├── hooks/
│   └── stores/
└── package.json
```

### 关键技术点

- **进程管理**：Tauri sidecar 或 `std::process::Command` 运行 `run.sh`，通过 async channel 实时推送 stdout/stderr 到前端
- **文件监听**：Rust 侧使用 `notify` crate 监听 `.autoresearch/workflows/` 目录变化，前端通过 Tauri events 接收更新
- **日志解析**：Rust 侧解析 log 文件提取评分、阶段、subtask 状态，结构化数据传给前端
- **GitHub 交互**：通过 `gh` CLI 而非直接 API 调用，保持与 `run.sh` 一致的认证方式
- **数据持久化**：App 自身配置（最近项目、窗口位置等）使用 Tauri 的 store 插件

### 依赖

- Tauri 2.x
- React 18+ / TypeScript
- Tailwind CSS
- Recharts（图表）
- VS Code Monaco Editor 的只读模式或 highlight.js（日志/代码展示）
- Zustand 或 Jotai（前端状态管理）
- `notify` crate（Rust 文件监听）
- `tokio`（Rust 异步运行时）

## Success Metrics

- 开发者能在 3 次点击内启动一个 Issue 的处理
- 实时日志延迟 < 500ms（从 run.sh 输出到 UI 展示）
- 所有 CLI 能完成的操作都能在 GUI 中完成
- App 启动时间 < 3 秒
- 安装包 < 30MB（Tauri 优势）

## Open Questions

- 是否需要支持 `run.sh` 的所有参数（如 `-p` 指定路径），还是只支持当前项目目录？
- PR diff 查看是否需要完整的 diff 语法高亮，还是简单的文件列表 + 行数统计即可？
- 是否需要在 App 中展示 `program.md` 中定义的代码规范摘要，帮助用户了解当前配置？
- 续跑模式 (`-c`) 是否应该在 App 崩溃/重启后自动检测并提示？
