# desktop_app/src

## Architecture

- **Router**: react-router-dom v7 with BrowserRouter wrapping in main.tsx, Routes/Route in App.tsx
- **Layout**: AppShell component (three-column: Sidebar 240px | main flex-1 | RightPanel 300px collapsible)
- **Pages**: Dashboard, Issues, History, Settings — each in src/pages/
- **Components**: Shared layout components in src/components/ (Sidebar, RightPanel, AppShell)
- **Styling**: Tailwind CSS v4 via @tailwindcss/vite plugin (no tailwind.config.js)
- **Theme**: Dark theme by default (bg-gray-900, text-gray-100, gray-800 for panels)

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

## State Management (Zustand)

- Stores are in `src/stores/` directory
- Use `create<State>()` from zustand to define stores
- Import store hooks with destructuring: `const { field, action } = useProjectStore()`
- Async actions should handle loading and error states
- Store pattern: state + actions + getters in one `create()` call

## Tauri Integration

- Import `invoke` from `@tauri-apps/api/core` to call Rust commands
- Commands return `Promise<T>` and can throw errors
- Pattern: `await invoke<ReturnType>('command_name', { args })`

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
- **搜索过滤**: 实时按标题和编号过滤（case-insensitive）
- **标签过滤**: 点击标签切换过滤状态，使用 `toggleLabelFilter(label.name)`
- **选中高亮**: 点击 Issue 项切换选中状态，使用 `selectIssue(number)`
- **已处理标记**: 通过 `processedNumbers.includes(issue.number)` 判断，显示绿色"已处理"徽章
- **浏览器 fallback**: 非 Tauri 环境使用 mock issue 列表和 mock issue 详情，保证浏览器模式也能验证详情面板
- **详情加载流**: `selectIssue` 会先清空旧的详情/错误态，再由页面 effect 触发详情加载，避免切换 Issue 时闪现旧数据
- **请求竞态保护**: `useIssueStore` 使用递增的 `detailRequestKey` 防止快速切换 Issue 时旧请求覆盖新详情

### 样式约定

- Issue 列表项: `bg-gray-800/50 border-gray-700`，选中时 `bg-blue-900/30 border-blue-600`
- 标签徽章: 使用 GitHub label 的 `color` 字段作为背景色，自动计算文字颜色（黑白）
- 已处理标记: 绿色主题（`bg-green-900/50 text-green-400`）
- 搜索框: `bg-gray-800 border-gray-700`，focus 时 `border-blue-600 ring-blue-600`
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

- 配置存在：绿色主题（`bg-green-900/50`, `text-green-400`, `border-green-700`）
- 配置缺失：红色主题（`bg-red-900/50`, `text-red-400`, `border-red-700`）
- 初始化提示：黄色主题（`bg-yellow-900/30`, `text-yellow-200`）
- 配置卡片边框：缺失配置时边框变为黄色（`border-yellow-700/50`）
