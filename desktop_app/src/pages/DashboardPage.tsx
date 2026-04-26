import React, { useEffect, useState } from 'react';
import { useProjectStore, ProjectConfig, isConfigIncomplete } from '../stores/projectStore';
import { useRuntimeStore, RuntimeStatus } from '../stores/runtimeStore';

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
          ? 'bg-green-50 text-green-700 border border-green-200'
          : 'bg-red-50 text-red-700 border border-red-200'
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
      <div className="w-16 h-16 mb-6 rounded-xl bg-gradient-to-br from-blue-500 to-purple-600 flex items-center justify-center shadow-lg shadow-blue-500/10">
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

      <h2 className="text-2xl font-bold mb-2 text-gray-900">
        欢迎使用 Autoresearch
      </h2>
      <p className="text-gray-500 mb-8 text-center max-w-md">
        选择一个项目目录开始使用自动化研发工作流
      </p>

      {/* Error message */}
      {error && (
        <div className="mb-4 p-3 rounded-lg bg-red-50 border border-red-200 text-red-700 text-sm max-w-md">
          <div className="flex items-center justify-between">
            <span>{error}</span>
            <button
              onClick={clearError}
              aria-label="关闭错误提示"
              className="ml-2 text-red-400 hover:text-red-600"
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
        className="px-6 py-3 bg-blue-600 hover:bg-blue-700 disabled:bg-gray-300 disabled:cursor-not-allowed text-white rounded-lg font-medium transition-colors flex items-center gap-2 shadow-lg shadow-blue-600/10"
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
                className="group flex items-center justify-between p-3 rounded-lg bg-gray-50 border border-gray-200 hover:border-gray-300 hover:bg-gray-100 cursor-pointer transition-colors"
                onClick={() => {
                  loadProject(recentPath);
                }}
              >
                <div className="flex items-center gap-3 min-w-0">
                  <div className="w-8 h-8 rounded-lg bg-gray-200 flex items-center justify-center flex-shrink-0">
                    <span className="text-xs font-medium text-gray-500">
                      {getDirName(recentPath).charAt(0).toUpperCase()}
                    </span>
                  </div>
                  <div className="min-w-0">
                    <p className="text-sm font-medium text-gray-800 truncate">
                      {getDirName(recentPath)}
                    </p>
                    <p className="text-xs text-gray-400 truncate">
                      {formatPath(recentPath)}
                    </p>
                  </div>
                </div>
                <svg
                  className="w-4 h-4 text-gray-300 group-hover:text-gray-500 flex-shrink-0 ml-2"
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

// Init from template prompt component — shows initialization status
function InitTemplatePrompt(): JSX.Element {
  const { isInitializing, error, retryInitialize, config } = useProjectStore();
  const [showSuccess, setShowSuccess] = useState(false);
  const [dismissed, setDismissed] = useState(false);
  const prevInitializing = React.useRef(isInitializing);

  useEffect(() => {
    // Detect transition from initializing → done
    if (prevInitializing.current && !isInitializing) {
      if (!error && config && !isConfigIncomplete(config)) {
        setShowSuccess(true);
        const timer = setTimeout(() => setShowSuccess(false), 3000);
        return () => clearTimeout(timer);
      }
    }
    prevInitializing.current = isInitializing;
  }, [isInitializing, error, config]);

  if (dismissed && !isInitializing) {
    return <></>;
  }

  // Success feedback
  if (showSuccess) {
    return (
      <div className="p-4 rounded-lg bg-green-50 border border-green-200 mb-6">
        <div className="flex items-center gap-3">
          <div className="flex-shrink-0 w-8 h-8 rounded-full bg-green-100 flex items-center justify-center">
            <CheckIcon className="w-4 h-4 text-green-600" />
          </div>
          <div>
            <h4 className="text-sm font-medium text-green-800">
              初始化成功
            </h4>
            <p className="text-sm text-green-600">
              .autoresearch 配置已自动创建完成
            </p>
          </div>
        </div>
      </div>
    );
  }

  // Loading state
  if (isInitializing) {
    return (
      <div className="p-4 rounded-lg bg-blue-50 border border-blue-200 mb-6">
        <div className="flex items-center gap-3">
          <div className="flex-shrink-0 w-8 h-8 rounded-full bg-blue-100 flex items-center justify-center">
            <svg
              className="animate-spin w-4 h-4 text-blue-600"
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
          </div>
          <div>
            <h4 className="text-sm font-medium text-blue-800">
              正在初始化配置...
            </h4>
            <p className="text-sm text-blue-600">
              正在创建 .autoresearch/ 目录、program.md 和 agents/ 目录
            </p>
          </div>
        </div>
      </div>
    );
  }

  // Error state with retry
  if (error) {
    return (
      <div className="p-4 rounded-lg bg-red-50 border border-red-200 mb-6">
        <div className="flex items-start gap-3">
          <div className="flex-shrink-0 w-8 h-8 rounded-full bg-red-100 flex items-center justify-center">
            <XIcon className="w-4 h-4 text-red-600" />
          </div>
          <div className="flex-1">
            <h4 className="text-sm font-medium text-red-800 mb-1">
              初始化失败
            </h4>
            <p className="text-sm text-red-700 mb-3">{error}</p>
            <div className="flex gap-2">
              <button
                onClick={() => retryInitialize()}
                className="px-3 py-1.5 text-sm font-medium text-white bg-red-500 hover:bg-red-600 rounded transition-colors"
              >
                重试
              </button>
              <button
                onClick={() => setDismissed(true)}
                className="px-3 py-1.5 text-sm font-medium text-red-700 hover:text-red-900 bg-red-100 hover:bg-red-200 border border-red-300 rounded transition-colors"
              >
                关闭
              </button>
            </div>
          </div>
        </div>
      </div>
    );
  }

  // Default: config still incomplete (e.g. user dismissed and came back)
  return (
    <div className="p-4 rounded-lg bg-amber-50 border border-amber-200 mb-6">
      <div className="flex items-start gap-3">
        <div className="flex-shrink-0 w-8 h-8 rounded-full bg-amber-100 flex items-center justify-center">
          <svg
            className="w-4 h-4 text-amber-600"
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
          <h4 className="text-sm font-medium text-amber-800 mb-1">
            项目配置不完整
          </h4>
          <p className="text-sm text-amber-700 mb-3">
            缺少 .autoresearch 配置文件。点击初始化按钮自动创建。
          </p>
          <div className="flex gap-2">
            <button
              onClick={() => retryInitialize()}
              className="px-3 py-1.5 text-sm font-medium text-white bg-amber-500 hover:bg-amber-600 rounded transition-colors"
            >
              初始化
            </button>
            <button
              onClick={() => setDismissed(true)}
              className="px-3 py-1.5 text-sm font-medium text-amber-700 hover:text-amber-900 bg-amber-100 hover:bg-amber-200 border border-amber-300 rounded transition-colors"
            >
              稍后
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
    <div className="p-4 rounded-lg bg-green-50 border border-green-200 mb-6">
      <div className="flex items-center gap-3">
        <div className="flex-shrink-0 w-8 h-8 rounded-full bg-green-100 flex items-center justify-center">
          <CheckIcon className="w-4 h-4 text-green-600" />
        </div>
        <div>
          <h4 className="text-sm font-medium text-green-800">
            配置完整
          </h4>
          <p className="text-sm text-green-600">
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

  return (
    <div className="p-6">
      {/* Header */}
      <div className="flex items-center justify-between mb-6">
        <div>
          <h1 className="text-2xl font-bold text-gray-900 mb-1">
            {getDirName(projectPath)}
          </h1>
          <p className="text-sm text-gray-500">{projectPath}</p>
        </div>
        <button
          onClick={selectProject}
          className="px-4 py-2 bg-white hover:bg-gray-50 text-gray-700 rounded-lg text-sm font-medium transition-colors flex items-center gap-2 border border-gray-200"
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
      {hasMissingConfig && (
        <InitTemplatePrompt />
      )}

      {/* Config Status Cards */}
      {config && (
        <div className="grid grid-cols-1 md:grid-cols-3 gap-4 mb-6">
          <div
            className={`p-4 rounded-lg bg-white border ${
              hasMissingConfig ? 'border-amber-300' : 'border-gray-200'
            }`}
          >
            <h3 className="text-sm font-medium text-gray-500 mb-3">
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

          <div className="p-4 rounded-lg bg-white border border-gray-200">
            <h3 className="text-sm font-medium text-gray-500 mb-3">
              项目状态
            </h3>
            <div className="flex items-center gap-2">
              {config.has_autoresearch_dir ? (
                <span className="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-green-50 text-green-700 border border-green-200">
                  <CheckIcon className="w-3 h-3 mr-1.5" />
                  已配置
                </span>
              ) : (
                <span className="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-amber-50 text-amber-700 border border-amber-200">
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

          <div className="p-4 rounded-lg bg-white border border-gray-200">
            <h3 className="text-sm font-medium text-gray-500 mb-3">
              快捷操作
            </h3>
            <div className="space-y-2">
              <button className="w-full text-left px-3 py-2 rounded bg-gray-50 hover:bg-gray-100 text-sm text-gray-700 transition-colors flex items-center gap-2">
                <svg
                  className="w-4 h-4 text-gray-400"
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
              <button className="w-full text-left px-3 py-2 rounded bg-gray-50 hover:bg-gray-100 text-sm text-gray-700 transition-colors flex items-center gap-2">
                <svg
                  className="w-4 h-4 text-gray-400"
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
      <div className="p-4 rounded-lg bg-gray-50 border border-gray-200">
        <h3 className="text-sm font-medium text-gray-500 mb-2">活动概览</h3>
        <p className="text-gray-400 text-sm">
          项目活动数据将在后续版本中提供...
        </p>
      </div>
    </div>
  );
}

// Runtime initialization status banner (non-blocking)
function RuntimeInitBanner(): JSX.Element {
  const { status, error, initializeRuntime } = useRuntimeStore();
  const [dismissed, setDismissed] = useState(false);

  // Auto-dismiss success after 3 seconds
  const [showSuccess, setShowSuccess] = useState(false);
  const prevStatus = React.useRef<RuntimeStatus>(status);

  useEffect(() => {
    if (prevStatus.current === 'initializing' && (status === 'installed' || status === 'updated')) {
      setShowSuccess(true);
      const timer = setTimeout(() => setShowSuccess(false), 3000);
      return () => clearTimeout(timer);
    }
    prevStatus.current = status;
  }, [status]);

  if (dismissed) return <></>;

  // Success feedback (after install or update)
  if (showSuccess) {
    return (
      <div className="p-4 rounded-lg bg-green-50 border border-green-200 mb-6">
        <div className="flex items-center gap-3">
          <div className="flex-shrink-0 w-8 h-8 rounded-full bg-green-100 flex items-center justify-center">
            <CheckIcon className="w-4 h-4 text-green-600" />
          </div>
          <div>
            <h4 className="text-sm font-medium text-green-800">
              运行时安装成功
            </h4>
            <p className="text-sm text-green-600">
              Autoresearch 运行时已就绪，可以开始处理 Issue
            </p>
          </div>
        </div>
      </div>
    );
  }

  // Loading state
  if (status === 'initializing') {
    return (
      <div className="p-4 rounded-lg bg-blue-50 border border-blue-200 mb-6">
        <div className="flex items-center gap-3">
          <div className="flex-shrink-0 w-8 h-8 rounded-full bg-blue-100 flex items-center justify-center">
            <svg
              className="animate-spin w-4 h-4 text-blue-600"
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
          </div>
          <div>
            <h4 className="text-sm font-medium text-blue-800">
              正在初始化运行时...
            </h4>
            <p className="text-sm text-blue-600">
              正在安装 run.sh 及依赖库到 ~/.autoresearch/runtime/
            </p>
          </div>
        </div>
      </div>
    );
  }

  // Error state (non-blocking: user can dismiss)
  if (status === 'error' && error) {
    return (
      <div className="p-4 rounded-lg bg-red-50 border border-red-200 mb-6">
        <div className="flex items-start gap-3">
          <div className="flex-shrink-0 w-8 h-8 rounded-full bg-red-100 flex items-center justify-center">
            <XIcon className="w-4 h-4 text-red-600" />
          </div>
          <div className="flex-1">
            <h4 className="text-sm font-medium text-red-800 mb-1">
              运行时初始化失败
            </h4>
            <p className="text-sm text-red-700 mb-3">{error}</p>
            <div className="flex gap-2">
              <button
                onClick={() => initializeRuntime()}
                className="px-3 py-1.5 text-sm font-medium text-white bg-red-500 hover:bg-red-600 rounded transition-colors"
              >
                重试
              </button>
              <button
                onClick={() => setDismissed(true)}
                className="px-3 py-1.5 text-sm font-medium text-red-700 hover:text-red-900 bg-red-100 hover:bg-red-200 border border-red-300 rounded transition-colors"
              >
                关闭
              </button>
            </div>
          </div>
        </div>
      </div>
    );
  }

  return <></>;
}

// Main Dashboard Page Component
function DashboardPage(): JSX.Element {
  const { projectPath, config, loadRecentProjects } = useProjectStore();
  const { initializeRuntime } = useRuntimeStore();

  useEffect(() => {
    loadRecentProjects();
    initializeRuntime();
  }, [loadRecentProjects, initializeRuntime]);

  if (!projectPath) {
    return (
      <>
        <RuntimeInitBanner />
        <WelcomeScreen />
      </>
    );
  }

  return (
    <>
      <RuntimeInitBanner />
      <ProjectInfoScreen projectPath={projectPath} config={config} />
    </>
  );
}

export default DashboardPage;
