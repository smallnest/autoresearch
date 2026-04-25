# desktop_app/tests

## Learnings

- **模式**: 前端中文化可用 `node --test --experimental-strip-types` 直接做源码字符串断言，不必引入浏览器测试框架。
- **模式**: 如果组件文件是 `.tsx` 且 Node 测试入口不能直接加载，优先把可测试的数据转换或 tooltip 文案 helper 提到邻近的 `.ts` 文件，再对 `.tsx` 做源码级护栏断言。
- **模式**: 对设置页这类依赖 Tauri 环境分支的组件，优先把“浏览器 fallback / 桌面可写态”的模式判断提成纯函数，再用 Node 单测锁住只读语义和提示文案。
- **模式**: 如果设置页交互依赖异步 `invoke + refresh` 链路，但仓库没有 DOM 测试基建，优先把“加载/保存/重置”动作封装成可注入依赖的 async helper，然后用 stub 断言调用顺序和成功文案，避免测试只停留在静态字符串层。
- **模式**: 配置编辑器除了 helper 单测，还要覆盖“dirty 状态下切换文件/重新加载不会静默丢失输入”的交互约束；否则文案和纯函数都通过，真实编辑流程仍可能丢数据。
- **模式**: dirty-state 测试不要只覆盖 switch/reload；`reset` 这类会用默认内容覆盖编辑器的动作同样属于 destructive action，必须走同一套确认分支。
- **模式**: 如果设置页会随着 `projectPath` 变化从 effect 中重载内容，测试必须覆盖“dirty 状态下切换项目不会静默覆盖编辑器”这条分支；否则文件切换都受保护，项目切换仍然会丢稿。
- **模式**: 如果项目没有浏览器测试基建，可先把“切换/重载是否允许继续”的状态机提成纯函数，再用 `node --test --experimental-strip-types` 覆盖 clean/dirty、确认/取消两条分支。
- **模式**: 路径展示 helper 如果服务于跨平台 UI，要在纯单测里同时锁住 POSIX 和 Windows 两种输出，避免只在 macOS 开发时漏掉反斜杠路径回归。
- **模式**: 对设置页这类聚合配置入口，除了测 helper，还要加源码级护栏断言关键子组件确实被挂到目标页面；否则 `RunConfigPanel` 一类功能可能只留在别处页面，验收仍会漏项。
- **模式**: 对 `SettingsPage` 这类自己持有 `useState` + 事件处理器的页面，helper 测试只能证明规则正确，不能证明按钮 wiring 正确；只要仓库允许，仍应补一层组件交互验证或浏览器验收来覆盖实际点击后的状态切换。
- **模式**: 如果暂时没有组件交互测试基建，至少要同时做两层护栏：纯 helper 单测锁住 `busy => 不允许切换/重载`，再加源码断言确认 `SettingsPage` 真的把 `disabled/readOnly` 接到对应控件上。
- **模式**: 对 `SettingsPage` 这类 hook 很重但又缺少 DOM 测试基建的页面，可以把控件接线提成纯 view-model helper；测试直接调用返回的 `onSelect` / `onEditorChange` / `onConfirmDiscard`，就能覆盖真实 wiring，而不必只停在源码字符串断言。
- **模式**: 配置编辑器的错误态也要锁住 view-model 行为；加载失败时 textarea 应保持只读，避免出现“空白可编辑但无法保存”的假交互。
- **模式**: 如果设置页在 dirty 状态下允许“挂起项目切换”，测试必须同时锁住两件事：pure helper 返回旧的已加载项目路径，以及 `SettingsPage` 源码确实把 save/reset/refresh 接到了这个有效路径，而不是直接使用最新 store `projectPath`。
- **经验**: 配置编辑器验收要同时跑 `npm --prefix desktop_app test` 和 Rust 侧 `cargo test config_file` / `cargo clippy -- -D warnings`；前端测试能证明交互规则，但白名单路径、`.bak` 备份和 `.autoresearch` 物化语义仍依赖 Tauri 后端校验。
- **经验**: 对 `SettingsPage` 这类聚合式前端改动，验收不要停在 `test + typecheck + lint`；还要补跑 `npm --prefix desktop_app run build`，否则 Vite 打包层面的 TS/模块问题会漏掉。
- **经验**: 审核配置编辑器时要把“前端状态机”和“Rust 文件命令”视为同一个验收面；如果只验证 helper 交互而不验证后端白名单/备份规则，或反过来只看 Rust 测试不看 `SettingsPage` wiring，都会留下真实回归缺口。
- **模式**: 中文化回归测试除了页面组件，还要直接检查 `src/stores` 里的错误文案；store 抛出的字符串同样会进入 UI。
- **模式**: “全面中文化”测试要把 `IterationProgressPanel` / `iterationProgressView` 这类状态面板也纳入覆盖，它们常含阶段名、状态标签和进度摘要，容易遗漏残留英文。
- **模式**: 如果组件展示的是后端英文枚举，测试要同时检查“映射后的中文文案存在”以及“原始英文枚举不再直接出现在展示常量里”，这样才能防止把内部 key 泄漏到 UI。
- **模式**: 中文化回归不要只盯页面标题；`LogViewer` 的级别筛选标签、`AgentSelector` 这类图标按钮的 `aria-label` 也要单独断言，否则很容易留下肉眼不明显的英文或无障碍缺口。
- **模式**: 图标按钮的无障碍检查不能只覆盖一个组件；像 `DashboardPage` 的错误关闭按钮、`IssuesPage` 的清空搜索/清除错误按钮这类没有可见文本的控件，也要逐一断言中文 `aria-label`。
- **模式**: 中文化 Issue 的测试要加“无关行为不变”的护栏；若 diff 同时改了输出上限、轮询间隔等运行参数，应有独立测试或直接拒绝夹带。
- **模式**: 对 store 错误中文化，优先把“英文异常转中文 fallback”的逻辑提成纯函数并直接单测；这样比只做源码字符串断言更能覆盖真实错误路径。
- **踩坑**: 负向断言不要写得过宽，例如直接匹配 `/ avatar/` 会误伤 `avatarUrl` 这类实现符号；应尽量锚定具体 JSX 片段或属性值。
- **踩坑**: 仅断言硬编码的中文字符串不足以证明“全面中文化”完成；`catch (e) => String(e)` 这类通用错误路径仍可能把英文异常直接暴露给 UI。
- **踩坑**: 同一功能链路若有多个容量常量（例如 `runStore` 与 `logViewerStore` 的日志行数上限），中文化回归也要顺手断言它们未被意外改动，否则容易混入需求外行为变化。
- **经验**: 中文化测试要覆盖页面文案、placeholder、空状态、`aria-label`、图片 `alt`，否则测试全绿也可能遗漏真实 UI 文案。
