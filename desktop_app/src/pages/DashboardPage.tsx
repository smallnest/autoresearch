import { useEffect, useState } from 'react';
import { useProjectStore, ProjectConfig } from '../stores/projectStore';

// Check Icon component
function CheckIcon({ className }: { className?: string }): JSX.Element {
  return (
    <svg
      className={className}
      fill="none"
      stroke="currentColor"
      viewBox="0 0 24 24"
    >
      <path
        strokeLinecap="round"
        strokeLinejoin="round"
        strokeWidth={2}
        d="M5 13l4 4L19 7"
      />
    </svg>
  );
}

// X Icon component
function XIcon({ className }: { className?: string }): JSX.Element {
  return (
    <svg
      className={className}
      fill="none"
      stroke="currentColor"
      viewBox="0 0 24 24"
    >
      <path
        strokeLinecap="round"
        strokeLinejoin="round"
        strokeWidth={2}
        d="M6 18L18 6M6 6l12 12"
      />
    </svg>
  );
}

// Format path for display (truncate if too long)
function formatPath(path: string, maxLength: number = 50): string {
  if (path.length <= maxLength) return path;
  const start = path.slice(0, maxLength / 2);
  const end = path.slice(-maxLength / 2);
  return `${start}...${end}`;
}

// Get directory name from path
function getDirName(path: string): string {
  const parts = path.split(/[/\\]/);
  return parts[parts.length - 1] || path;
}

// Config status badge component
function ConfigBadge({
  label,
  exists,
}: {
  label: string;
  exists: boolean;
}): JSX.Element {
  return (
    <span
      className={`inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium ${
        exists
          ? 'bg-green-900/50 text-green-400 border border-green-700'
          : 'bg-red-900/50 text-red-400 border border-red-700'
      }`}
    >
      {exists ? (
        <CheckIcon className="w-3 h-3 mr-1.5" />
      ) : (
        <XIcon className="w-3 h-3 mr-1.5" />
      )}
      {label}
    </span>
  );
}

// Welcome screen when no project selected
function WelcomeScreen(): JSX.Element {
  const {
    recentProjects,
    isLoading,
    error,
    selectProject,
    loadProject,
    clearError,
  } = useProjectStore();

  return (
    <div className="flex flex-col items-center justify-center h-full min-h-[400px] p-6">
      {/* Logo/Icon placeholder */}
      <div className="w-16 h-16 mb-6 rounded-xl bg-gradient-to-br from-blue-500 to-purple-600 flex items-center justify-center shadow-lg shadow-blue-500/20">
        <svg
          className="w-8 h-8 text-white"
          fill="none"
          stroke="currentColor"
          viewBox="0 0 24 24"
        >
          <path
            strokeLinecap="round"
            strokeLinejoin="round"
            strokeWidth={2}
            d="M19.428 15.428a2 2 0 00-1.022-.547l-2.384-.477a6 6 0 00-3.86.517l-.318.158a6 6 0 01-3.86.517L6.05 15.21a2 2 0 00-1.806.547M8 4h8l-1 1v5.172a2 2 0 00.586 1.414l5 5c1.26 1.26.367 3.414-1.415 3.414H4.828c-1.782 0-2.674-2.154-1.414-3.414l5-5A2 2 0 009 10.172V5L8 4z"
          />
        </svg>
      </div>

      <h2 className="text-2xl font-bold mb-2 text-gray-100">
        欢迎使用 Autoresearch
      </h2>
      <p className="text-gray-400 mb-8 text-center max-w-md">
        选择一个项目目录开始使用自动化研发工作流
      </p>

      {/* Error message */}
      {error && (
        <div className="mb-4 p-3 rounded-lg bg-red-900/30 border border-red-700 text-red-300 text-sm max-w-md">
          <div className="flex items-center justify-between">
            <span>{error}</span>
            <button
              onClick={clearError}
              className="ml-2 text-red-400 hover:text-red-300"
            >
              <svg className="w-4 h-4" fill="currentColor" viewBox="0 0 20 20">
                <path
                  fillRule="evenodd"
                  d="M4.293 4.293a1 1 0 011.414 0L10 8.586l4.293-4.293a1 1 0 111.414 1.414L11.414 10l4.293 4.293a1 1 0 01-1.414 1.414L10 11.414l-4.293 4.293a1 1 0 01-1.414-1.414L8.586 10 4.293 5.707a1 1 0 010-1.414z"
                  clipRule="evenodd"
                />
              </svg>
            </button>
          </div>
        </div>
      )}

      {/* Select Project Button */}
      <button
        onClick={selectProject}
        disabled={isLoading}
        className="px-6 py-3 bg-blue-600 hover:bg-blue-700 disabled:bg-gray-700 disabled:cursor-not-allowed text-white rounded-lg font-medium transition-colors flex items-center gap-2 shadow-lg shadow-blue-600/20"
      >
        {isLoading ? (
          <>
            <svg
              className="animate-spin w-4 h-4"
              fill="none"
              viewBox="0 0 24 24"
            >
              <circle
                className="opacity-25"
                cx="12"
                cy="12"
                r="10"
                stroke="currentColor"
                strokeWidth={4}
              />
              <path
                className="opacity-75"
                fill="currentColor"
                d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"
              />
            </svg>
            加载中...
          </>
        ) : (
          <>
            <svg
              className="w-4 h-4"
              fill="none"
              stroke="currentColor"
              viewBox="0 0 24 24"
            >
              <path
                strokeLinecap="round"
                strokeLinejoin="round"
                strokeWidth={2}
                d="M3 7v10a2 2 0 002 2h14a2 2 0 002-2V9a2 2 0 00-2-2h-6l-2-2H5a2 2 0 00-2 2z"
              />
            </svg>
            选择项目目录
          </>
        )}
      </button>

      {/* Recent Projects Section */}
      {recentProjects.length > 0 && (
        <div className="mt-10 w-full max-w-md">
          <h3 className="text-sm font-medium text-gray-500 uppercase tracking-wider mb-3">
            上次打开的项目
          </h3>
          <ul className="space-y-2">
            {recentProjects.map((recentPath) => (
              <li
                key={recentPath}
                className="group flex items-center justify-between p-3 rounded-lg bg-gray-800/50 border border-gray-700 hover:border-gray-600 hover:bg-gray-800 cursor-pointer transition-colors"
                onClick={() => {
                  loadProject(recentPath);
                }}
              >
                <div className="flex items-center gap-3 min-w-0">
                  <div className="w-8 h-8 rounded-lg bg-gray-700 flex items-center justify-center flex-shrink-0">
                    <span className="text-xs font-medium text-gray-400">
                      {getDirName(recentPath).charAt(0).toUpperCase()}
                    </span>
                  </div>
                  <div className="min-w-0">
                    <p className="text-sm font-medium text-gray-200 truncate">
                      {getDirName(recentPath)}
                    </p>
                    <p className="text-xs text-gray-500 truncate">
                      {formatPath(recentPath)}
                    </p>
                  </div>
                </div>
                <svg
                  className="w-4 h-4 text-gray-600 group-hover:text-gray-400 flex-shrink-0 ml-2"
                  fill="none"
                  stroke="currentColor"
                  viewBox="0 0 24 24"
                >
                  <path
                    strokeLinecap="round"
                    strokeLinejoin="round"
                    strokeWidth={2}
                    d="M9 5l7 7-7 7"
                  />
                </svg>
              </li>
            ))}
          </ul>
        </div>
      )}
    </div>
  );
}

// Init from template prompt component
function InitTemplatePrompt({
  onLater,
  onLearnMore,
}: {
  onLater: () => void;
  onLearnMore: () => void;
}): JSX.Element {
  return (
    <div className="p-4 rounded-lg bg-yellow-900/30 border border-yellow-700/50 mb-6">
      <div className="flex items-start gap-3">
        <div className="flex-shrink-0 w-8 h-8 rounded-full bg-yellow-900/50 flex items-center justify-center">
          <svg
            className="w-4 h-4 text-yellow-400"
            fill="none"
            stroke="currentColor"
            viewBox="0 0 24 24"
          >
            <path
              strokeLinecap="round"
              strokeLinejoin="round"
              strokeWidth={2}
              d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"
            />
          </svg>
        </div>
        <div className="flex-1">
          <h4 className="text-sm font-medium text-yellow-200 mb-1">
            项目配置不完整
          </h4>
          <p className="text-sm text-yellow-400/80 mb-3">
            是否从模板初始化？这将创建 .autoresearch/ 目录、program.md 和 agents/ 目录。
          </p>
          <div className="flex gap-2">
            <button
              onClick={onLater}
              className="px-3 py-1.5 text-sm font-medium text-yellow-300 hover:text-yellow-200 bg-yellow-900/30 hover:bg-yellow-900/50 border border-yellow-700/50 rounded transition-colors"
            >
              稍后
            </button>
            <button
              onClick={onLearnMore}
              className="px-3 py-1.5 text-sm font-medium text-gray-900 bg-yellow-500 hover:bg-yellow-400 rounded transition-colors"
            >
              了解
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}

// Config complete success notification
function ConfigCompleteNotification(): JSX.Element {
  return (
    <div className="p-4 rounded-lg bg-green-900/30 border border-green-700/50 mb-6">
      <div className="flex items-center gap-3">
        <div className="flex-shrink-0 w-8 h-8 rounded-full bg-green-900/50 flex items-center justify-center">
          <CheckIcon className="w-4 h-4 text-green-400" />
        </div>
        <div>
          <h4 className="text-sm font-medium text-green-200">
            配置完整
          </h4>
          <p className="text-sm text-green-400/80">
            所有配置项已就绪，可以开始使用 Autoresearch
          </p>
        </div>
      </div>
    </div>
  );
}

// Project Info screen when project is selected
function ProjectInfoScreen({
  projectPath,
  config,
}: {
  projectPath: string;
  config: ProjectConfig | null;
}): JSX.Element {
  const { selectProject } = useProjectStore();
  const [showInitPrompt, setShowInitPrompt] = useState(true);

  // Check if any config is missing
  const hasMissingConfig = config
    ? !config.has_autoresearch_dir ||
      !config.has_program_md ||
      !config.has_agents_dir
    : false;

  // Check if all configs are present
  const isConfigComplete = config
    ? config.has_autoresearch_dir &&
      config.has_program_md &&
      config.has_agents_dir
    : false;

  const handleLater = () => {
    setShowInitPrompt(false);
  };

  const handleLearnMore = () => {
    // Just a placeholder - opens documentation or shows more info
    alert('了解更多功能将在后续版本中实现');
    setShowInitPrompt(false);
  };

  return (
    <div className="p-6">
      {/* Header */}
      <div className="flex items-center justify-between mb-6">
        <div>
          <h1 className="text-2xl font-bold text-gray-100 mb-1">
            {getDirName(projectPath)}
          </h1>
          <p className="text-sm text-gray-500">{projectPath}</p>
        </div>
        <button
          onClick={selectProject}
          className="px-4 py-2 bg-gray-800 hover:bg-gray-700 text-gray-300 rounded-lg text-sm font-medium transition-colors flex items-center gap-2 border border-gray-700"
        >
          <svg
            className="w-4 h-4"
            fill="none"
            stroke="currentColor"
            viewBox="0 0 24 24"
          >
            <path
              strokeLinecap="round"
              strokeLinejoin="round"
              strokeWidth={2}
              d="M3 7v10a2 2 0 002 2h14a2 2 0 002-2V9a2 2 0 00-2-2h-6l-2-2H5a2 2 0 00-2 2z"
            />
          </svg>
          切换项目
        </button>
      </div>

      {/* Config Complete Success Notification */}
      {isConfigComplete && <ConfigCompleteNotification />}

      {/* Init Template Prompt */}
      {hasMissingConfig && showInitPrompt && (
        <InitTemplatePrompt onLater={handleLater} onLearnMore={handleLearnMore} />
      )}

      {/* Config Status Cards */}
      {config && (
        <div className="grid grid-cols-1 md:grid-cols-3 gap-4 mb-6">
          <div
            className={`p-4 rounded-lg bg-gray-800/50 border ${
              hasMissingConfig ? 'border-yellow-700/50' : 'border-gray-700'
            }`}
          >
            <h3 className="text-sm font-medium text-gray-400 mb-3">
              配置检测
            </h3>
            <div className="space-y-2">
              <ConfigBadge
                label=".autoresearch/"
                exists={config.has_autoresearch_dir}
              />
              <ConfigBadge
                label="program.md"
                exists={config.has_program_md}
              />
              <ConfigBadge
                label="agents/"
                exists={config.has_agents_dir}
              />
            </div>
          </div>

          <div className="p-4 rounded-lg bg-gray-800/50 border border-gray-700">
            <h3 className="text-sm font-medium text-gray-400 mb-3">
              项目状态
            </h3>
            <div className="flex items-center gap-2">
              {config.has_autoresearch_dir ? (
                <span className="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-green-900/50 text-green-400 border border-green-700">
                  <CheckIcon className="w-3 h-3 mr-1.5" />
                  已配置
                </span>
              ) : (
                <span className="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-yellow-900/50 text-yellow-400 border border-yellow-700">
                  <XIcon className="w-3 h-3 mr-1.5" />
                  未配置
                </span>
              )}
            </div>
            <p className="mt-2 text-xs text-gray-500">
              {config.has_autoresearch_dir
                ? '项目已初始化 autoresearch 配置'
                : '运行 autoresearch init 初始化项目'}
            </p>
          </div>

          <div className="p-4 rounded-lg bg-gray-800/50 border border-gray-700">
            <h3 className="text-sm font-medium text-gray-400 mb-3">
              快捷操作
            </h3>
            <div className="space-y-2">
              <button className="w-full text-left px-3 py-2 rounded bg-gray-700/50 hover:bg-gray-700 text-sm text-gray-300 transition-colors flex items-center gap-2">
                <svg
                  className="w-4 h-4 text-gray-500"
                  fill="none"
                  stroke="currentColor"
                  viewBox="0 0 24 24"
                >
                  <path
                    strokeLinecap="round"
                    strokeLinejoin="round"
                    strokeWidth={2}
                    d="M13 10V3L4 14h7v7l9-11h-7z"
                  />
                </svg>
                新建工作流
              </button>
              <button className="w-full text-left px-3 py-2 rounded bg-gray-700/50 hover:bg-gray-700 text-sm text-gray-300 transition-colors flex items-center gap-2">
                <svg
                  className="w-4 h-4 text-gray-500"
                  fill="none"
                  stroke="currentColor"
                  viewBox="0 0 24 24"
                >
                  <path
                    strokeLinecap="round"
                    strokeLinejoin="round"
                    strokeWidth={2}
                    d="M9 5H7a2 2 0 00-2 2v12a2 2 0 002 2h10a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2"
                  />
                </svg>
                查看 Issues
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Quick Stats Placeholder */}
      <div className="p-4 rounded-lg bg-gray-800/30 border border-gray-700/50">
        <h3 className="text-sm font-medium text-gray-400 mb-2">活动概览</h3>
        <p className="text-gray-500 text-sm">
          项目活动数据将在后续版本中提供...
        </p>
      </div>
    </div>
  );
}

// Main Dashboard Page Component
function DashboardPage(): JSX.Element {
  const { projectPath, config, loadRecentProjects } = useProjectStore();

  useEffect(() => {
    loadRecentProjects();
  }, [loadRecentProjects]);

  if (!projectPath) {
    return <WelcomeScreen />;
  }

  return <ProjectInfoScreen projectPath={projectPath} config={config} />;
}

export default DashboardPage;
