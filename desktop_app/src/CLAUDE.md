# desktop_app/src

## Architecture

- **Router**: react-router-dom v7 with BrowserRouter wrapping in main.tsx, Routes/Route in App.tsx
- **Layout**: AppShell component (three-column: Sidebar 240px | main flex-1 | RightPanel 300px collapsible)
- **Pages**: Dashboard, Issues, History, Settings — each in src/pages/
- **Components**: Shared layout components in src/components/ (Sidebar, RightPanel, AppShell)
- **Styling**: Tailwind CSS v4 via @tailwindcss/vite plugin (no tailwind.config.js)
- **Theme**: Light theme (bg-white, text-gray-900, gray-50 for panels, gray-200 borders)

## Conventions

- Functional components with default exports
- SVG icons inline in components (no icon library dependency)
- NavLink for active route highlighting in navigation
- Outlet pattern: AppShell renders `<Outlet />` for nested route content
- Panel collapse state is local (useState), not global store

## Dependencies

- react-router-dom: routing (BrowserRouter, Routes, Route, NavLink, Outlet)
- Tailwind CSS v4: utility-first styling via @tailwindcss/vite
- zustand: global state management, stores in `src/stores/`

## Testing

- Store-heavy logic should be written so it can be instantiated with injected dependencies instead of hard-wiring Tauri imports; this repo uses `createRunStore(overrides)` for that pattern.
- Persisted Zustand stores should also expose a factory (for example `createRunConfigStore`) so tests can inject in-memory storage and explicitly exercise hydration behavior.
- `node --test --experimental-strip-types` works in this project for lightweight TypeScript store tests without adding Vitest/Jest.
- When a desktop store mirrors backend process state, do not assume the frontend knows the active resource after a failed `invoke`; prefer clearing unknown identifiers instead of showing a wrong Issue number.

## State Management (Zustand)

- Stores are in `src/stores/` directory
- Use `create<State>()` from zustand to define stores
- Import store hooks with destructuring: `const { field, action } = useProjectStore()`
- Async actions should handle loading and error states
- Store pattern: state + actions + getters in one `create()` call
- Persisted UI preference stores should expose shared default/min/max constants and clamp numeric values both in setters and during persist rehydration, so stale localStorage data cannot bypass UI constraints.
- When persisted form fields represent CLI or backend integer parameters, normalize them to integers in the store layer as well, not just in the HTML input, so rehydrated localStorage and programmatic updates cannot send decimals downstream.
- For persisted form state, treat `NaN`, `Infinity`, and wrong primitive types as invalid input; setters should preserve the last valid value, while rehydration should fall back to defaults.
- For store tests, prefer exported factory functions with injected dependencies (for example custom storage) so `node --test --experimental-strip-types` can cover Zustand logic without a browser runtime.
- When a React component mainly assembles command payloads, extract that mapping into a small non-JSX helper so `node --test --experimental-strip-types` can cover the integration contract without a browser test runner.
- For persisted stores with value bounds, validate both setter input and persisted hydration (`merge`/`migrate`), otherwise invalid `localStorage` data can bypass runtime constraints.

## Tauri Integration

- Import `invoke` from `@tauri-apps/api/core` to call Rust commands
- Commands return `Promise<T>` and can throw errors
- Pattern: `await invoke<ReturnType>('command_name', { args })`
- Tauri event subscriptions should be centralized in a store when multiple UI components need the same lifecycle state; `run-output` / `run-exit` are handled in `src/stores/runStore.ts`

## Pitfalls

- Backend `get_recent_project` stores only a single path (not a list). Frontend `recentProjects` is kept as an array for future extensibility but currently holds at most one item.
- When adding store actions that load a specific project by path, always call `detect_project_config` + `save_recent_project` + update state in one action — don't split across multiple calls.
- In `.map()` callbacks, avoid naming variables the same as component props (e.g. `projectPath`) to prevent shadowing. Use descriptive names like `recentPath`.
- `loadRecentProjects` auto-loads the last project on app startup. If the project directory was deleted/moved, `detect_project_config` will fail. Consider adding a "back to welcome" escape hatch or error recovery in the UI.
- Use unique identifiers (e.g. path strings) as React keys in `.map()`, not array indices.

## IssuesPage 约定

### 组件结构

- `IssueListItem`: 单个 Issue 列表项，显示编号、标题、标签、创建时间、处理状态
- `LabelBadge`: 可点击的标签徽章，支持选中高亮状态
- `SearchIcon`/`CheckIcon`/`IssueIcon`/`ProcessedIcon`/`ClearIcon`: 内联 SVG 图标组件
- `EmptyState`: 空状态提示组件

### 功能实现

- **数据获取**: 通过 `useIssueStore.loadIssues(projectPath)` 调用 Tauri `list_issues` 命令
- **详情数据**: 选中 Issue 后先用 `selectIssue(number)` 切换选中态，再由页面 effect 通过 `useIssueStore.loadIssueDetail(projectPath, issueNumber)` 调用 Tauri `get_issue_detail`
- **运行控制**: `useRunStore.initialize()` 在 `IssuesPage` 挂载时订阅 `run-output` / `run-exit` 事件；启动/停止操作放在 `IssueDetailPanel`
- **单任务限制**: 前端用 `runStore.status` 禁用启动按钮，后端再通过 `start_run` 的互斥检查做第二层保护
- **运行参数配置**: `RunConfigPanel` 默认折叠，使用 `useRunConfigStore` 持久化 `maxIterations`、`passingScore`、`continueMode`；数值输入必须保持整数语义，并在 store 层统一校验
- **搜索过滤**: 实时按标题和编号过滤（case-insensitive）
- **标签过滤**: 点击标签切换过滤状态，使用 `toggleLabelFilter(label.name)`
- **选中高亮**: 点击 Issue 项切换选中状态，使用 `selectIssue(number)`
- **已处理标记**: 通过 `processedNumbers.includes(issue.number)` 判断，显示绿色"已处理"徽章
- **浏览器 fallback**: 非 Tauri 环境使用 mock issue 列表和 mock issue 详情，保证浏览器模式也能验证详情面板
- **运行 fallback**: 非 Tauri 环境禁用启动/停止按钮，并明确提示“浏览器模式不支持运行任务”
- **详情加载流**: `selectIssue` 会先清空旧的详情/错误态，再由页面 effect 触发详情加载，避免切换 Issue 时闪现旧数据
- **请求竞态保护**: `useIssueStore` 使用递增的 `detailRequestKey` 防止快速切换 Issue 时旧请求覆盖新详情
- **输出区域**: 实时输出保存在 `runStore.outputLines`，UI 层只负责渲染和滚动到底部；输出上限 2000 行，避免长任务无限增长
- **日志查看器**: 历史日志不要直接塞进 `runStore.outputLines`；单独用 `useLogViewerStore` 管理日志源、搜索词、级别过滤和自动滚动状态，实时输出只作为其中一个 source (`live-output`)
- **日志来源**: 日志源列表统一由 Tauri `list_issue_log_sources` 返回，前端只拿 `source.id` 调 `read_issue_log_content`，不要自己拼 `.autoresearch/workflows/issue-N/...` 路径
- **日志轮询**: `LogViewer` 需要同时轮询“日志源列表”和“当前选中文件内容”；否则运行中新增的 iteration 日志文件不会出现在下拉列表里
- **刷新保态**: 同一 Issue 的日志源轮询不能重置 `searchQuery`、`selectedSourceId`、`autoScroll` 或 `hasPendingScroll`，这些都是用户当前阅读状态

### 样式约定

- Issue 列表项: `bg-white border-gray-200`，选中时 `bg-blue-50 border-blue-300`
- 标签徽章: 使用 GitHub label 的 `color` 字段作为背景色，自动计算文字颜色（黑白）
- 已处理标记: 绿色主题（`bg-green-50 text-green-700`）
- 搜索框: `bg-white border-gray-200`，focus 时 `border-blue-500 ring-blue-500`
- 空状态: 居中显示，灰色图标和文字
- 详情面板: 使用页面内右侧 sticky 卡片，而不是复用全局 `RightPanel`
- Markdown 样式: 统一挂在 `.markdown-body`，代码块高亮 token 使用 `.md-token-*` 类名
- Markdown 渲染: `react-markdown` 通过 Vite/TS alias 指向本地兼容实现 `src/vendor/react-markdown.tsx`，保证离线环境可构建；链接只允许 `http/https/mailto`
- 骨架屏: 使用 `.skeleton-shimmer` 伪元素实现统一 shimmer 动效，避免在组件内重复写动画

## DashboardPage 约定

### 配置状态显示

- 使用 `ConfigBadge` 组件显示 `.autoresearch/`、`program.md`、`agents/` 状态
- `ConfigBadge` 使用勾/叉图标（`CheckIcon`/`XIcon`）替代圆点，符合验收条件要求
- 配置完整时显示"配置完整"成功提示（绿色背景卡片）
- 配置缺失时显示"是否从模板初始化"提示 UI（黄色背景卡片，仅 UI，不实际初始化）
- 提示 UI 包含"稍后"和"了解"两个操作按钮

### 组件结构

- `WelcomeScreen`: 未选择项目时显示的欢迎页面
- `ProjectInfoScreen`: 已选择项目时显示的项目信息页面
- `ConfigBadge`: 配置状态徽章（用于显示单个配置项）
- `InitTemplatePrompt`: 初始化模板提示（配置缺失时显示）
- `ConfigCompleteNotification`: 配置完整提示（配置齐全时显示）
- `CheckIcon`/`XIcon`: 状态图标组件

### 样式约定

- 配置存在：绿色主题（`bg-green-50`, `text-green-700`, `border-green-200`）
- 配置缺失：红色主题（`bg-red-50`, `text-red-700`, `border-red-200`）
- 初始化提示：琥珀色主题（`bg-amber-50`, `text-amber-800`）
- 配置卡片边框：缺失配置时边框变为琥珀色（`border-amber-300`）

## LogViewer 约定

### 性能

- `buildLogEntries` 结果必须通过 `useMemo` 缓存（`totalEntries`），然后 `filterLogEntries` 基于缓存结果再 memo；footer 中显示总行数用 `totalEntries.length`，不要重新调用 `buildLogEntries`
- `buildLogEntries` 内置 `MAX_LOG_LINES = 5000` 截断保护，只保留最近 5000 行，`lineNumber` 从实际起始行号开始计数（不是从 1）

### 状态正确性

- 同一 Issue 的日志源刷新必须保留用户当前选择的 source，包括用户主动切到 `live-output` 的情况；不要在后台轮询时自动切回 `terminal.log`
- `loadSources` / `refreshSelectedSource` 这类异步动作在切换 Issue 时需要请求隔离（例如 request key / issue number guard），否则旧 Issue 的迟到响应会污染新 Issue 的 `sources` 或 `sourceContents`

### 搜索高亮

- 搜索关键词高亮通过 `HighlightedText` 组件实现，使用 `<mark>` 标签包裹匹配文本
- `escapeRegExp` 用于安全转义用户输入中的正则特殊字符
- 搜索过滤（filter）和搜索高亮（highlight）是两个独立功能，不要混淆

### React Key

- 日志行的 React key 使用 `entry.lineNumber`（同一文件中唯一），不要拼接 `entry.text`（日志中常有重复行）

## IterationProgressPanel 约定

### 数据来源

- `iterationStore.ts` 通过 `invoke('get_iteration_progress', { projectPath, issueNumber })` 从 Rust 后端拉取
- Rust 后端 `IterationProgress` 使用 snake_case 序列化：`current_iteration`, `total_iterations`, `phase`, `subtasks`, `passed_count`, `total_count`
- 前端 TypeScript 接口必须匹配 snake_case 字段名（不是 camelCase）
- 后端 `Phase` 枚举值为：`Planning`, `Implementation`, `Review`, `BuildLintTest`, `Idle`
- 评分展示链路也走同一个 `IterationProgress` payload：新增字段时要同时更新 Rust struct、Tauri command 返回值、`iterationStore.ts` 接口和 `IDLE_PROGRESS` 默认值
- 当前评分相关字段为 `last_score`, `passing_score`, `review_summary`；前端不自行提取评分，只消费后端结果
- 评分趋势图使用同一条 `IterationProgress` 链路里的 `score_history` 数组；该字段元素保持 snake_case（`iteration`, `score`, `review_summary`），不要在 store 层改成 camelCase
- 如果验收要求是“无 score 时不显示评分区域”，前端组件要以 `last_score` 为评分区块的唯一显隐条件，`review_summary` 不能单独触发渲染
- 趋势图这类可视化组件优先做成独立可嵌入组件（如 `ScoreTrendChart`），由面板决定是否显示；这样同一组件可复用到 Dashboard 或右侧详情区

### 更新策略

- `iteration-progress` 事件由后端主动推送，前端 `iterationStore.ts` 负责集中订阅并按 `issue_number` 过滤
- 组件切换 Issue 时先调用 `watchIssue(projectPath, issueNumber)` 主动拉取一次，再等待事件增量更新；不要再在组件里用 `setInterval` 轮询
- 切换 Issue 或关闭详情时调用 `reset()`，清空当前 issue 绑定并使旧请求失效

### Store 模式

- 遵循 `createRunStore(overrides)` 工厂模式，注入 `isTauri`/`invoke` 依赖
- 迭代进度 store 还需要注入 `listen`，测试使用 `createIterationStore({ isTauri: true, invoke: mockFn, listen: mockListen })` 隔离事件
- `isTauri: false` 时 `watchIssue` 为 no-op，确保浏览器模式不报错
- 迭代进度如果按 Issue 维度放在全局 store，必须做请求隔离（request key / issue guard）；切换 Issue 时旧请求的迟到响应不能覆盖当前 Issue 的进度
- subtask 三态由后端提供 `status: pending | passing | failing`；前端只负责渲染，不要再用 `passes: boolean` 自行推导 `failing`
- 评分 UI 的颜色映射约定放在 `iterationProgressView.ts` 这类纯函数里，用 `node --test --experimental-strip-types` 直接测阈值边界，比把颜色逻辑写死在 JSX 里更稳
- 对这类小型 React UI，优先把关键显示区块提成纯组件，再用 `react-dom/server` 的 `renderToStaticMarkup` 做静态渲染测试；这样无需引入浏览器测试框架，也能覆盖文案、图标和显隐逻辑

## 文案与中文化约定

- “UI 全面中文化”类需求默认覆盖所有用户可见文案：页面标题、导航、按钮、空状态、提示语、状态标签、ARIA label 和占位符；不能只改局部组件
- 中文化审核要覆盖未触碰的页面和可访问性文案，尤其是 `DashboardPage`、详情区图片 `alt`、搜索框 placeholder 这类容易漏掉的字符串
- 做文案类改动时，必须同步更新受影响的字符串断言测试或静态渲染测试；如果常量语义变了（例如输出上限），对应测试里的边界值也要一起改
- 审核此类需求时先看 `master...HEAD` 的实际 diff；如果 diff 与需求标题明显不符，优先按“需求未实现”处理，而不是假设代码落在别处
- 纯文案 / 中文化需求不应顺手修改运行逻辑或容量阈值；如果确实需要顺带调整行为，必须在说明和测试里明确交代原因
- `runStore` 的输出保留上限当前约定为 2000 行；若要调整属于独立行为/性能变更，不能夹带在 UI 文案类 Issue 里
- 文案回归测试除了标题和正文，还要显式覆盖 placeholder、空状态、`aria-label`、图片 `alt`；这些字符串最容易漏。
- 对前端 store 返回给 UI 的错误消息也要做中文化检查；这些字符串虽然不在 JSX 里，但会直接显示给用户，审核时不能漏掉
- store 里的通用异常不要直接 `String(error)` / `error.message` 回传到 UI；统一通过 `src/stores/uiError.ts` 这类 helper 做“保留中文、英文回退到中文 fallback”的归一化
- `iterationStore` 也属于直接面向用户的状态源；拉取迭代进度失败时不能直接透传后端异常原文，否则会在“迭代进度”面板泄漏英文报错
- 后端枚举值如 `Phase`、`SubtaskStatus` 允许继续使用英文 key，但前端展示层必须通过单独映射输出中文，不能直接把 `Planning`、`pending` 之类的内部值渲染给用户
- `LogViewer` 这类状态面板里的筛选标签同样属于用户可见文案，`info/warn/error` 不能直接 `toUpperCase()` 暴露给 UI，必须单独做展示映射
- 中文化审核不能只看前端静态 JSX；像日志源下拉框这类由后端返回 `label` 的动态文案也必须检查，`iteration-*.log` 这种原始英文文件名如果直接展示给用户，同样算未完成中文化
- 图标型按钮也属于中文化范围；像 Agent 标签的移除按钮这类仅显示 “×” 的控件，需要补充中文 `aria-label`，否则视觉上看似完成中文化但读屏仍缺失可理解文案
- 中文化需求不得夹带运行行为改动；像 `runStore` / `logViewerStore` 的日志保留行数这种容量常量要保持一致，若要调整必须作为独立行为变更处理
