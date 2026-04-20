# Desktop App: 从 PRD 到 GitHub Issue 创建全过程

## 1. 用户需求

用户输入 `/prd 为本项目创建一个桌面app`，触发 PRD 生成技能。

## 2. 项目调研

通过 Explore Agent 调研 autoresearch 项目，了解：

- **项目定位**：全自动化软件开发工具，输入 GitHub Issue 编号，通过多 Agent 迭代 review 实现功能，自动创建 PR、合并、关闭 Issue
- **运行方式**：单一 Bash 脚本 (`run.sh`)，纯 CLI 操作
- **核心架构**：Planning → Implementation → Review (>=85分通过) → Auto PR/Merge/Close
- **当前状态**：无任何 GUI 或 Web 界面

## 3. 需求澄清

向用户提出 4 个关键问题：

### Q1: 桌面 App 的主要目标是什么？
| 选项 | 描述 |
|------|------|
| A. 可视化监控与操作 | 替代命令行，GUI 启动/停止、查看实时进度、日志、评分 |
| B. **全功能管理面板** | 除监控外，还包括配置管理、Issue 选择、PR 审核、历史记录 |
| C. 结果展示仪表盘 | 聚焦展示处理结果、统计数据、趋势分析 |
| D. 完整 IDE 体验 | 集成代码编辑、文件浏览、终端 |

### Q2: 目标用户是谁？
| 选项 | 描述 |
|------|------|
| A. **开发者个人使用** | 熟悉 autoresearch 的开发者，自己管理多个项目的 Issue 自动化 |
| B. 团队协作使用 | 多人共享，需要任务分配、权限管理 |
| C. 开源社区用户 | 面向不熟悉 CLI 的开源贡献者 |

### Q3: 桌面 App 的技术栈偏好？
| 选项 | 描述 |
|------|------|
| A. Electron + React/Vue | 成熟生态，体积较大 |
| B. **Tauri + React/Vue** | Rust 后端 + Web 前端，轻量高性能 |
| C. 原生应用 (Swift/Kotlin) | 平台原生体验，需分别开发 |
| D. 无偏好，你来推荐 | - |

### Q4: 是否需要同时管理多个项目？
| 选项 | 描述 |
|------|------|
| A. **单项目即可** | 一次只处理一个项目，通过切换目录切换 |
| B. 多项目并行 | 同时监控和管理多个项目 |
| C. 多项目但串行 | 可配置多个项目，但一次只运行一个任务队列 |

**用户选择**：Q1-B、Q2-A、Q3-B、Q4-A

## 4. PRD 生成

基于用户回答生成完整 PRD，保存到 `tasks/prd-desktop-app.md`，包含：

- **Introduction**：项目背景、代码位置（`desktop_app/`）、技术栈（Tauri 2 + React + TypeScript）
- **Goals**：5 条核心目标
- **User Stories**：10 个用户故事（US-001 ~ US-010），每个含验收标准
- **Functional Requirements**：12 条功能需求（FR-1 ~ FR-12）
- **Non-Goals**：7 条明确排除项
- **Design Considerations**：三栏布局、暗色主题、颜色编码
- **Technical Considerations**：架构目录、关键技术点、依赖清单
- **Success Metrics**：5 条成功指标
- **Open Questions**：4 个待确认问题

### 用户反馈与 PRD 迭代

1. **代码目录**：用户要求指定代码保存到 `desktop_app/` 目录 → 更新 Introduction 和架构目录
2. **Agent 选择器**：用户在 US-001 中新增验收标准"挑选要使用的 agent 和顺序，可以以标签选择框的方式" → 同步新增 FR-8.1

## 5. Issue 拆分策略

### 拆分原则

- 每个 Issue 可在单次开发会话中完成
- 有明确的验收标准（checkbox）
- 标注依赖关系，可并行开发无依赖的 Issue
- Issue 标题统一加 `[desktop-app]` 前缀
- 统一打 `desktop-app` 和 `enhancement` 标签

### 拆分结果

将 10 个 User Stories 拆分为 19 个细粒度 Issue，按阶段组织：

```
P1 基础 (2)
├── #22 项目脚手架搭建
└── #23 App 壳布局与导航

P2 项目设置 (2)
├── #24 项目目录选择与配置检测
└── #25 Agent 选择器（拖拽排序）

P3 GitHub 集成 (2)
├── #26 GitHub Issue 列表展示
└── #27 Issue 详情查看

P4 进程控制 (2)
├── #28 run.sh 进程管理（启动/停止）
└── #29 运行参数配置 UI

P5 实时监控 (4)
├── #30 实时日志查看器
├── #31 迭代进度与阶段展示
├── #32 评分提取与展示
└── #33 评分趋势折线图

P6 配置 (1)
└── #34 配置文件编辑器

P7 历史 (2)
├── #35 处理历史列表
└── #36 历史详情查看与日志导出

P8 PR (2)
├── #37 PR 信息查看与 Diff 展示
└── #38 PR 操作（合并/关闭）

P9 系统集成 (2)
├── #39 系统托盘集成
└── #40 桌面通知系统
```

### 依赖关系图

```
#22 (脚手架)
 ├── #23 (布局)
 ├── #24 (目录选择) ── #26 (Issue 列表) ── #27 (Issue 详情)
 │                 ── #34 (配置编辑器)
 │                 ── #35 (历史列表) ── #36 (历史详情)
 │                 ── #37 (PR 查看) ── #38 (PR 操作)
 ├── #25 (Agent 选择器) ── #29 (参数 UI) ── #28 (进程管理)
 │                                              ├── #30 (日志查看器)
 │                                              ├── #31 (迭代进度) ── #32 (评分) ── #33 (趋势图)
 │                                              │                 ── #40 (通知)
 │                                              └── ...
 └── #39 (系统托盘)
```

### 每个 Issue 的统一结构

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

## 6. 执行的操作清单

1. 创建 GitHub Label: `desktop-app` (#0E8A16)
2. 创建 19 个 GitHub Issue (#22 ~ #40)
3. 每个 Issue 包含：Description、Acceptance Criteria、Dependencies、Technical Notes
4. 所有 Issue 使用 `gh issue create` 命令创建，自动打上标签

## 7. 文件清单

| 文件 | 说明 |
|------|------|
| `tasks/prd-desktop-app.md` | 完整 PRD 文档 |
| `docs/desktop-app-prd-to-issues.md` | 本文档（过程记录） |
| `desktop_app/` | 桌面 App 代码目录（待 Issue #22 创建） |
