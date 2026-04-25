import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

function readSource(relativePath) {
  return readFileSync(new URL(relativePath, import.meta.url), 'utf8');
}

test('layout components use Chinese navigation and panel copy', () => {
  const sidebarSource = readSource('../src/components/Sidebar.tsx');
  const rightPanelSource = readSource('../src/components/RightPanel.tsx');

  assert.match(sidebarSource, /label: "概览"/);
  assert.match(sidebarSource, /label: "议题"/);
  assert.match(sidebarSource, /label: "历史"/);
  assert.match(sidebarSource, /label: "设置"/);
  assert.doesNotMatch(sidebarSource, /label: "Dashboard"/);
  assert.doesNotMatch(sidebarSource, /label: "History"/);

  assert.match(rightPanelSource, /信息面板/);
  assert.match(rightPanelSource, /展开面板/);
  assert.match(rightPanelSource, /收起面板/);
  assert.match(rightPanelSource, /选择一项后可在这里查看详情。/);
  assert.doesNotMatch(rightPanelSource, /Info Panel/);
  assert.doesNotMatch(rightPanelSource, /Expand panel/);
});

test('settings, history, and agent selection copy is localized', () => {
  const settingsSource = readSource('../src/pages/SettingsPage.tsx');
  const historySource = readSource('../src/pages/HistoryPage.tsx');
  const dashboardSource = readSource('../src/pages/DashboardPage.tsx');
  const agentSelectorSource = readSource('../src/components/AgentSelector.tsx');
  const runConfigSource = readSource('../src/components/RunConfigPanel.tsx');
  const logViewerSource = readSource('../src/components/LogViewer.tsx');

  assert.match(settingsSource, />设置</);
  assert.match(settingsSource, /配置应用偏好与 Agent 选择顺序。/);
  assert.match(settingsSource, /Agent 配置/);
  assert.doesNotMatch(settingsSource, />Settings</);

  assert.match(historySource, />历史</);
  assert.match(historySource, /查看过去的工作流执行记录与结果。/);
  assert.doesNotMatch(historySource, />History</);

  assert.match(dashboardSource, /欢迎使用 Autoresearch/);
  assert.match(dashboardSource, /查看议题/);
  assert.match(dashboardSource, /aria-label="关闭错误提示"/);
  assert.doesNotMatch(dashboardSource, /查看 Issues/);

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

  assert.match(issuesSource, />议题</);
  assert.match(issuesSource, /GitHub 未关闭议题/);
  assert.match(issuesSource, /正在加载议题/);
  assert.match(issuesSource, /没有匹配的议题/);
  assert.match(issuesSource, /暂无议题/);
  assert.match(issuesSource, /已关闭/);
  assert.match(issuesSource, /搜索议题标题或编号/);
  assert.match(issuesSource, /aria-label="关闭错误提示"/);
  assert.match(issuesSource, /aria-label="清空搜索"/);
  assert.doesNotMatch(issuesSource, />Issues</);
  assert.doesNotMatch(issuesSource, /OPEN Issues/);
  assert.doesNotMatch(issuesSource, /搜索 Issue 标题或编号/);

  assert.match(issueDetailSource, /议题详情/);
  assert.match(issueDetailSource, /选择一个议题/);
  assert.match(issueDetailSource, /从左侧列表中点击议题后/);
  assert.match(issueDetailSource, /进行中/);
  assert.match(issueDetailSource, /已关闭/);
  assert.match(issueDetailSource, /退出码/);
  assert.match(issueDetailSource, /当前正在运行议题/);
  assert.match(issueDetailSource, /该议题暂无描述/);
  assert.match(issueDetailSource, /该议题暂无评论/);
  assert.match(issueDetailSource, /的头像/);
  assert.doesNotMatch(issueDetailSource, /Issue Detail/);
  assert.doesNotMatch(issueDetailSource, /alt=\{`\$\{comment\.author\.login\} avatar`\}/);

  assert.match(issueStoreSource, /浏览器模式不支持获取 GitHub 议题/);
  assert.match(issueStoreSource, /未找到议题 #/);
  assert.match(issueStoreSource, /normalizeIssueListError/);
  assert.match(issueStoreSource, /normalizeIssueDetailError/);
  assert.doesNotMatch(issueStoreSource, /GitHub Issues/);
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
