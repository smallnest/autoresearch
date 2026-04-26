import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

function readSource(relativePath) {
  return readFileSync(new URL(relativePath, import.meta.url), 'utf8');
}

test('layout components use Chinese navigation and panel copy', () => {
  const sidebarSource = readSource('../src/components/Sidebar.tsx');

  assert.match(sidebarSource, /label: "概览"/);
  assert.match(sidebarSource, /label: "Issues"/);
  assert.match(sidebarSource, /label: "历史"/);
  assert.match(sidebarSource, /label: "设置"/);
  assert.doesNotMatch(sidebarSource, /label: "Dashboard"/);
  assert.doesNotMatch(sidebarSource, /label: "History"/);
});

test('settings, history, and agent selection copy is localized', () => {
  const settingsSource = readSource('../src/pages/SettingsPage.tsx');
  const historySource = readSource('../src/pages/HistoryPage.tsx');
  const dashboardSource = readSource('../src/pages/DashboardPage.tsx');
  const configEditorSource = readSource('../src/pages/configEditor.ts');
  const agentSelectorSource = readSource('../src/components/AgentSelector.tsx');
  const runConfigSource = readSource('../src/components/RunConfigPanel.tsx');
  const logViewerSource = readSource('../src/components/LogViewer.tsx');

  assert.match(settingsSource, />设置</);
  assert.match(settingsSource, /配置应用偏好与 Agent 选择顺序。/);
  assert.match(settingsSource, /配置文件编辑器/);
  assert.match(settingsSource, /保存配置/);
  assert.match(settingsSource, /重置为默认值/);
  assert.match(settingsSource, /请先在概览页选择项目目录/);
  assert.match(configEditorSource, /放弃当前修改并加载新项目配置/);
  assert.match(configEditorSource, /pendingProjectSwitchMessage/);
  assert.match(settingsSource, /运行参数/);
  assert.match(settingsSource, /passing score、最大迭代次数与继续模式/);
  assert.match(settingsSource, /<RunConfigPanel/);
  assert.match(settingsSource, /disabled=\{configEditorView\?\.editorDisabled\}/);
  assert.match(settingsSource, /readOnly=\{configEditorView\?\.editorReadOnly\}/);
  assert.match(settingsSource, /projectPath: effectiveProjectPath/);
  assert.match(settingsSource, /refreshConfig\(effectiveProjectPath \?\? undefined\)/);
  assert.match(configEditorSource, /浏览器模式下仅支持查看占位内容，保存与重置需在桌面应用中进行。/);
  assert.match(configEditorSource, /isConfigEditorInteractionLocked/);
  assert.match(configEditorSource, /buildConfigEditorViewModel/);
  assert.match(configEditorSource, /resolveConfigEditorProjectPath/);
  assert.match(settingsSource, /Agent 配置/);
  assert.doesNotMatch(settingsSource, />Settings</);

  assert.match(historySource, />历史记录</);
  assert.match(historySource, /暂无历史记录/);
  assert.match(historySource, /按状态过滤/);
  assert.match(historySource, /aria-label="关闭错误提示"/);
  assert.doesNotMatch(historySource, />History</);

  assert.match(dashboardSource, /欢迎使用 Autoresearch/);
  assert.match(dashboardSource, /查看 Issues/);
  assert.match(dashboardSource, /aria-label="关闭错误提示"/);
  assert.doesNotMatch(dashboardSource, /查看议题/);

  assert.match(agentSelectorSource, /已选 Agent/);
  assert.match(agentSelectorSource, /全选/);
  assert.match(agentSelectorSource, /清空/);
  assert.match(agentSelectorSource, /暂未选择 Agent，请在下方添加。/);
  assert.match(agentSelectorSource, /可选 Agent/);
  assert.match(agentSelectorSource, /aria-label=\{`移除 \$\{name\}`\}/);
  assert.doesNotMatch(agentSelectorSource, /Selected Agents/);
  assert.doesNotMatch(agentSelectorSource, /Available Agents/);

  assert.match(runConfigSource, /运行参数配置/);
  assert.match(runConfigSource, /最大迭代次数/);
  assert.match(runConfigSource, /通过分数/);
  assert.match(runConfigSource, /继续模式/);

  assert.match(logViewerSource, /日志查看器/);
  assert.match(logViewerSource, /搜索日志内容/);
  assert.match(logViewerSource, /等待新的运行输出/);
  assert.match(logViewerSource, /跳到最新/);
  assert.match(logViewerSource, /info: '信息'/);
  assert.match(logViewerSource, /warn: '警告'/);
  assert.match(logViewerSource, /error: '错误'/);
  assert.doesNotMatch(logViewerSource, /level\.toUpperCase\(\)/);
});

test('issues page and issue detail copy is localized', () => {
  const issuesSource = readSource('../src/pages/IssuesPage.tsx');
  const issueDetailSource = readSource('../src/components/IssueDetailPanel.tsx');
  const issueStoreSource = readSource('../src/stores/issueStore.ts');
  const projectStoreSource = readSource('../src/stores/projectStore.ts');
  const logViewerStoreSource = readSource('../src/stores/logViewerStore.ts');
  const runStoreSource = readSource('../src/stores/runStore.ts');

  assert.match(issuesSource, />Issues</);
  assert.match(issuesSource, /GitHub 未关闭 Issues/);
  assert.match(issuesSource, /正在加载 Issues/);
  assert.match(issuesSource, /没有匹配的 Issues/);
  assert.match(issuesSource, /暂无 Issues/);
  assert.match(issuesSource, /已关闭/);
  assert.match(issuesSource, /搜索 Issues 标题或编号/);
  assert.match(issuesSource, /aria-label="关闭错误提示"/);
  assert.match(issuesSource, /aria-label="清空搜索"/);
  assert.doesNotMatch(issuesSource, />议题</);
  assert.doesNotMatch(issuesSource, /OPEN Issues/);
  assert.doesNotMatch(issuesSource, /搜索议题标题或编号/);

  assert.match(issueDetailSource, /Issues 详情/);
  assert.match(issueDetailSource, /选择一个 Issue/);
  assert.match(issueDetailSource, /从左侧列表中点击 Issue 后/);
  assert.match(issueDetailSource, /进行中/);
  assert.match(issueDetailSource, /已关闭/);
  assert.match(issueDetailSource, /退出码/);
  assert.match(issueDetailSource, /当前正在运行 Issue/);
  assert.match(issueDetailSource, /该 Issue 暂无描述/);
  assert.match(issueDetailSource, /该 Issue 暂无评论/);
  assert.match(issueDetailSource, /的头像/);
  assert.doesNotMatch(issueDetailSource, /议题详情/);
  assert.doesNotMatch(issueDetailSource, /alt=\{`\$\{comment\.author\.login\} avatar`\}/);

  assert.match(issueStoreSource, /浏览器模式不支持获取 GitHub Issues/);
  assert.match(issueStoreSource, /未找到 Issue #/);
  assert.match(issueStoreSource, /normalizeIssueListError/);
  assert.match(issueStoreSource, /normalizeIssueDetailError/);
  assert.doesNotMatch(issueStoreSource, /GitHub 议题/);
  assert.doesNotMatch(issueStoreSource, /Issue #\$\{_issueNumber\} not found/);
  assert.doesNotMatch(issueStoreSource, /String\(e\)/);

  assert.match(projectStoreSource, /normalizeProjectError/);
  assert.doesNotMatch(projectStoreSource, /String\(e\)/);

  assert.match(logViewerStoreSource, /normalizeLogViewerError/);
  assert.doesNotMatch(logViewerStoreSource, /error\.message/);

  assert.match(runStoreSource, /退出码/);
  assert.match(runStoreSource, /const MAX_OUTPUT_LINES = 5000/);
  assert.doesNotMatch(runStoreSource, /exit code/);
});

test('iteration progress copy is localized', () => {
  const iterationProgressViewSource = readSource('../src/components/iterationProgressView.ts');
  const iterationProgressPanelSource = readSource('../src/components/IterationProgressPanel.tsx');

  assert.match(iterationProgressViewSource, /label: '规划'/);
  assert.match(iterationProgressViewSource, /label: '实现'/);
  assert.match(iterationProgressViewSource, /label: '审核'/);
  assert.match(iterationProgressViewSource, /label: '构建·检查·测试'/);
  assert.match(iterationProgressViewSource, /当前为空闲状态/);
  assert.match(iterationProgressViewSource, /待处理/);
  assert.match(iterationProgressViewSource, /通过/);
  assert.match(iterationProgressViewSource, /失败/);
  assert.doesNotMatch(iterationProgressViewSource, /label: 'Planning'/);
  assert.doesNotMatch(iterationProgressViewSource, /idle 状态/);

  assert.match(iterationProgressPanelSource, /暂无子任务信息/);
  assert.match(iterationProgressPanelSource, /已通过 \{passed\}\/\{total\} 个子任务/);
  assert.doesNotMatch(iterationProgressPanelSource, /暂无 subtask 信息/);
  assert.doesNotMatch(iterationProgressPanelSource, /subtasks passed/);
});
