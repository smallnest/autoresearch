import { useState, type JSX } from 'react';
import {
  useRunConfigStore,
  DEFAULT_CONTINUE_MODE,
  DEFAULT_MAX_ITERATIONS,
  DEFAULT_PASSING_SCORE,
  MIN_MAX_ITERATIONS,
  MAX_MAX_ITERATIONS,
  MIN_PASSING_SCORE,
  MAX_PASSING_SCORE,
} from '../stores/runConfigStore';

function ChevronDownIcon({ className }: { className?: string }): JSX.Element {
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
        d="M19 9l-7 7-7-7"
      />
    </svg>
  );
}

function SettingsIcon({ className }: { className?: string }): JSX.Element {
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
        d="M10.325 4.317c.426-1.756 2.924-1.756 3.35 0a1.724 1.724 0 002.573 1.066c1.543-.94 3.31.826 2.37 2.37a1.724 1.724 0 001.065 2.572c1.756.426 1.756 2.924 0 3.35a1.724 1.724 0 00-1.066 2.573c.94 1.543-.826 3.31-2.37 2.37a1.724 1.724 0 00-2.572 1.065c-.426 1.756-2.924 1.756-3.35 0a1.724 1.724 0 00-2.573-1.066c-1.543.94-3.31-.826-2.37-2.37a1.724 1.724 0 00-1.065-2.572c-1.756-.426-1.756-2.924 0-3.35a1.724 1.724 0 001.066-2.573c-.94-1.543.826-3.31 2.37-2.37.996.608 2.296.07 2.572-1.065z"
      />
      <path
        strokeLinecap="round"
        strokeLinejoin="round"
        strokeWidth={2}
        d="M15 12a3 3 0 11-6 0 3 3 0 016 0z"
      />
    </svg>
  );
}

function ResetIcon({ className }: { className?: string }): JSX.Element {
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
        d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15"
      />
    </svg>
  );
}

interface RunConfigPanelProps {
  collapsed?: boolean;
  onCollapsedChange?: (collapsed: boolean) => void;
  defaultConfig?: {
    maxIterations: number;
    passingScore: number;
    continueMode: boolean;
  };
}

export default function RunConfigPanel({
  collapsed: controlledCollapsed,
  onCollapsedChange,
  defaultConfig = {
    maxIterations: DEFAULT_MAX_ITERATIONS,
    passingScore: DEFAULT_PASSING_SCORE,
    continueMode: DEFAULT_CONTINUE_MODE,
  },
}: RunConfigPanelProps): JSX.Element {
  const [internalCollapsed, setInternalCollapsed] = useState(true);
  const contentId = 'run-config-panel-content';

  const isControlled = controlledCollapsed !== undefined;
  const collapsed = isControlled ? controlledCollapsed : internalCollapsed;

  const toggleCollapse = () => {
    const nextCollapsed = !collapsed;
    if (isControlled && onCollapsedChange) {
      onCollapsedChange(nextCollapsed);
    } else {
      setInternalCollapsed(nextCollapsed);
    }
  };

  const {
    maxIterations,
    passingScore,
    continueMode,
    setMaxIterations,
    setPassingScore,
    setContinueMode,
    reset,
  } = useRunConfigStore();

  const isDefault =
    maxIterations === defaultConfig.maxIterations &&
    passingScore === defaultConfig.passingScore &&
    continueMode === defaultConfig.continueMode;

  return (
    <div className="rounded-xl border border-gray-200 bg-white overflow-hidden">
      <button
        type="button"
        onClick={toggleCollapse}
        aria-expanded={!collapsed}
        aria-controls={contentId}
        className="w-full flex items-center justify-between px-4 py-3 text-left hover:bg-gray-50 transition-colors"
      >
        <div className="flex items-center gap-2">
          <SettingsIcon className="h-4 w-4 text-gray-500" />
          <span className="text-sm font-medium text-gray-700">运行参数配置</span>
          {!isDefault && (
            <span className="inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium bg-blue-100 text-blue-700">
              已修改
            </span>
          )}
        </div>
        <ChevronDownIcon
          className={`h-4 w-4 text-gray-400 transition-transform duration-200 ${
            collapsed ? '' : 'rotate-180'
          }`}
        />
      </button>

      {!collapsed && (
        <div
          id={contentId}
          className="px-4 pb-4 space-y-4 border-t border-gray-100"
        >
          <div className="pt-4">
            <div className="flex items-center justify-between mb-2">
              <label
                htmlFor="maxIterations"
                className="text-sm font-medium text-gray-700"
              >
                最大迭代次数
              </label>
              <span className="text-xs text-gray-500">
                {MIN_MAX_ITERATIONS}-{MAX_MAX_ITERATIONS}
              </span>
            </div>
            <div className="flex items-center gap-3">
              <input
                type="range"
                id="maxIterations"
                min={MIN_MAX_ITERATIONS}
                max={MAX_MAX_ITERATIONS}
                step={1}
                value={maxIterations}
                onChange={(e) => setMaxIterations(Number(e.target.value))}
                className="flex-1 h-2 bg-gray-200 rounded-lg appearance-none cursor-pointer accent-blue-600"
              />
              <input
                type="number"
                min={MIN_MAX_ITERATIONS}
                max={MAX_MAX_ITERATIONS}
                step={1}
                inputMode="numeric"
                value={maxIterations}
                onChange={(e) => setMaxIterations(Number(e.target.value))}
                className="w-16 px-2 py-1 text-sm text-center border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-blue-500"
              />
            </div>
            <p className="mt-1 text-xs text-gray-500">
              每个任务最多执行的迭代次数（默认 {DEFAULT_MAX_ITERATIONS}）
            </p>
          </div>

          <div>
            <div className="flex items-center justify-between mb-2">
              <label
                htmlFor="passingScore"
                className="text-sm font-medium text-gray-700"
              >
                通过分数
              </label>
              <span className="text-xs text-gray-500">
                {MIN_PASSING_SCORE}-{MAX_PASSING_SCORE}
              </span>
            </div>
            <div className="flex items-center gap-3">
              <input
                type="range"
                id="passingScore"
                min={MIN_PASSING_SCORE}
                max={MAX_PASSING_SCORE}
                step={1}
                value={passingScore}
                onChange={(e) => setPassingScore(Number(e.target.value))}
                className="flex-1 h-2 bg-gray-200 rounded-lg appearance-none cursor-pointer accent-blue-600"
              />
              <input
                type="number"
                min={MIN_PASSING_SCORE}
                max={MAX_PASSING_SCORE}
                step={1}
                inputMode="numeric"
                value={passingScore}
                onChange={(e) => setPassingScore(Number(e.target.value))}
                className="w-16 px-2 py-1 text-sm text-center border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-blue-500"
              />
            </div>
            <p className="mt-1 text-xs text-gray-500">
              审核评分达到此分数才算通过（默认 {DEFAULT_PASSING_SCORE}）
            </p>
          </div>

          <div>
            <div className="flex items-center justify-between">
              <div>
                <label
                  htmlFor="continueMode"
                  className="text-sm font-medium text-gray-700"
                >
                  继续模式
                </label>
                <p className="text-xs text-gray-500">
                  从上次中断的地方继续执行
                </p>
              </div>
              <button
                type="button"
                id="continueMode"
                role="switch"
                aria-checked={continueMode}
                onClick={() => setContinueMode(!continueMode)}
                className={`relative inline-flex h-6 w-11 flex-shrink-0 cursor-pointer rounded-full border-2 border-transparent transition-colors duration-200 ease-in-out focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-offset-2 ${
                  continueMode ? 'bg-blue-600' : 'bg-gray-200'
                }`}
              >
                <span
                  className={`pointer-events-none inline-block h-5 w-5 transform rounded-full bg-white shadow ring-0 transition duration-200 ease-in-out ${
                    continueMode ? 'translate-x-5' : 'translate-x-0'
                  }`}
                />
              </button>
            </div>
          </div>

          <div className="pt-2 border-t border-gray-100">
            <button
              type="button"
              onClick={reset}
              disabled={isDefault}
              className="inline-flex items-center gap-1.5 px-3 py-1.5 text-sm font-medium text-gray-600 bg-gray-100 rounded-lg hover:bg-gray-200 disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
            >
              <ResetIcon className="h-4 w-4" />
              重置为默认值
            </button>
          </div>
        </div>
      )}
    </div>
  );
}
