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
