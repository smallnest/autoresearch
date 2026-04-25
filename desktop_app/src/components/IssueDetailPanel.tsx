import { useEffect, useRef, type JSX } from 'react';
import ReactMarkdown from 'react-markdown';
import { formatDateTime, GhIssue, IssueDetail } from '../stores/issueStore';
import { useRunStore } from '../stores/runStore';
import {
  DEFAULT_CONTINUE_MODE,
  DEFAULT_MAX_ITERATIONS,
  DEFAULT_PASSING_SCORE,
  useRunConfigStore,
} from '../stores/runConfigStore';
import RunConfigPanel from './RunConfigPanel';
import AgentSelector from './AgentSelector';
import { buildIssueRunRequest } from './issueRunRequest';

interface IssueDetailPanelProps {
  issue: GhIssue | null;
  detail: IssueDetail | null;
  isLoading: boolean;
  error: string | null;
  projectPath: string | null;
  onClose: () => void;
  onRetry: () => void;
}

function CloseIcon({ className }: { className?: string }): JSX.Element {
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

function CommentIcon({ className }: { className?: string }): JSX.Element {
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
        d="M8 10h.01M12 10h.01M16 10h.01M9 16H5a2 2 0 01-2-2V6a2 2 0 012-2h14a2 2 0 012 2v8a2 2 0 01-2 2h-5l-4 4v-4z"
      />
    </svg>
  );
}

function PlayIcon({ className }: { className?: string }): JSX.Element {
  return (
    <svg
      className={className}
      fill="currentColor"
      viewBox="0 0 24 24"
      aria-hidden="true"
    >
      <path d="M8 5.14v13.72a1 1 0 001.5.86l10.29-6.86a1 1 0 000-1.72L9.5 4.28A1 1 0 008 5.14z" />
    </svg>
  );
}

function StopIcon({ className }: { className?: string }): JSX.Element {
  return (
    <svg
      className={className}
      fill="currentColor"
      viewBox="0 0 24 24"
      aria-hidden="true"
    >
      <rect x="6" y="6" width="12" height="12" rx="2" />
    </svg>
  );
}

function TerminalIcon({ className }: { className?: string }): JSX.Element {
  return (
    <svg
      className={className}
      fill="none"
      stroke="currentColor"
      viewBox="0 0 24 24"
      aria-hidden="true"
    >
      <path
        strokeLinecap="round"
        strokeLinejoin="round"
        strokeWidth={2}
        d="M8 9l3 3-3 3m5 0h3M5 19h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v10a2 2 0 002 2z"
      />
    </svg>
  );
}

function DetailSkeleton(): JSX.Element {
  return (
    <div className="space-y-6">
      <div className="rounded-2xl border border-gray-200 bg-white p-5">
        <div className="skeleton-shimmer mb-4 h-6 w-1/3 rounded bg-gray-100" />
        <div className="skeleton-shimmer mb-3 h-4 w-full rounded bg-gray-100" />
        <div className="skeleton-shimmer mb-3 h-4 w-11/12 rounded bg-gray-100" />
        <div className="skeleton-shimmer h-28 w-full rounded-2xl bg-gray-50" />
      </div>
      <div className="rounded-2xl border border-gray-200 bg-white p-5">
        <div className="skeleton-shimmer mb-4 h-5 w-24 rounded bg-gray-100" />
        <div className="space-y-4">
          <div className="rounded-xl border border-gray-100 bg-gray-50 p-4">
            <div className="mb-3 flex items-center gap-3">
              <div className="skeleton-shimmer h-10 w-10 rounded-full bg-gray-200" />
              <div className="flex-1 space-y-2">
                <div className="skeleton-shimmer h-4 w-32 rounded bg-gray-100" />
                <div className="skeleton-shimmer h-3 w-24 rounded bg-gray-100" />
              </div>
            </div>
            <div className="skeleton-shimmer mb-2 h-4 w-full rounded bg-gray-100" />
            <div className="skeleton-shimmer h-4 w-4/5 rounded bg-gray-100" />
          </div>
        </div>
      </div>
    </div>
  );
}

function EmptySelectionState(): JSX.Element {
  return (
    <div className="flex h-full min-h-[420px] items-center justify-center rounded-3xl border border-dashed border-gray-300 bg-gray-50/50 p-8 text-center">
      <div>
        <CommentIcon className="mx-auto mb-4 h-12 w-12 text-gray-300" />
        <h2 className="mb-2 text-lg font-semibold text-gray-700">选择一个 Issue</h2>
        <p className="max-w-sm text-sm leading-6 text-gray-500">
          从左侧列表中点击 Issue 后，这里会展示描述、评论和最新状态。
        </p>
      </div>
    </div>
  );
}

function EmptyContentState({ title }: { title: string }): JSX.Element {
  return (
    <div className="rounded-2xl border border-dashed border-gray-300 bg-gray-50 p-4 text-sm text-gray-400">
      {title}
    </div>
  );
}

function ErrorState({
  message,
  onRetry,
}: {
  message: string;
  onRetry: () => void;
}): JSX.Element {
  return (
    <div className="rounded-2xl border border-red-200 bg-red-50 p-5">
      <h3 className="mb-2 text-sm font-semibold text-red-700">详情加载失败</h3>
      <p className="mb-4 text-sm leading-6 text-red-600">{message}</p>
      <button
        onClick={onRetry}
        className="rounded-lg border border-red-300 px-3 py-2 text-sm font-medium text-red-700 transition-colors hover:bg-red-100"
      >
        重试
      </button>
    </div>
  );
}

function avatarUrl(login: string): string {
  return `https://github.com/${encodeURIComponent(login)}.png?size=80`;
}

function getRunStatusLabel(status: ReturnType<typeof useRunStore.getState>['status']): string {
  switch (status) {
    case 'running':
      return '运行中';
    case 'stopping':
      return '停止中';
    case 'finished':
      return '已结束';
    case 'error':
      return '错误';
    case 'idle':
    default:
      return '空闲';
  }
}

function getRunStatusClass(status: ReturnType<typeof useRunStore.getState>['status']): string {
  switch (status) {
    case 'running':
      return 'border-emerald-200 bg-emerald-50 text-emerald-700';
    case 'stopping':
      return 'border-amber-200 bg-amber-50 text-amber-700';
    case 'finished':
      return 'border-slate-200 bg-slate-100 text-slate-700';
    case 'error':
      return 'border-red-200 bg-red-50 text-red-700';
    case 'idle':
    default:
      return 'border-gray-200 bg-gray-100 text-gray-600';
  }
}

function IssueDetailPanel({
  issue,
  detail,
  isLoading,
  error,
  projectPath,
  onClose,
  onRetry,
}: IssueDetailPanelProps): JSX.Element {
  const outputContainerRef = useRef<HTMLDivElement | null>(null);
  const {
    status: runStatus,
    activeIssueNumber,
    outputLines,
    exitCode,
    error: runError,
    isSupported,
    startRun,
    stopRun,
    clearOutput,
    clearError: clearRunError,
  } = useRunStore();

  const {
    maxIterations,
    passingScore,
    continueMode,
  } = useRunConfigStore();

  useEffect(() => {
    const container = outputContainerRef.current;
    if (!container) {
      return;
    }
    container.scrollTop = container.scrollHeight;
  }, [outputLines, runStatus]);

  if (!issue) {
    return <EmptySelectionState />;
  }

  const isRunActive = runStatus === 'running' || runStatus === 'stopping';
  const isCurrentIssueRunning = activeIssueNumber === issue.number && isRunActive;
  const canStart =
    Boolean(projectPath) && isSupported && !isRunActive;
  const canStop = isSupported && isRunActive;
  const outputText =
    outputLines.length > 0 ? outputLines.join('\n') : '等待运行输出...';
  const showRunMeta =
    activeIssueNumber !== null &&
    (isRunActive || runStatus === 'finished' || runStatus === 'error');

  return (
    <aside className="rounded-3xl border border-gray-200 bg-white shadow-sm">
      <div className="sticky top-0 z-10 flex items-start justify-between gap-4 rounded-t-3xl border-b border-gray-200 bg-white/95 px-5 py-4 backdrop-blur">
        <div className="min-w-0">
          <p className="mb-1 text-xs font-medium uppercase tracking-[0.2em] text-blue-600">
            Issue Detail
          </p>
          <h2 className="truncate text-lg font-semibold text-gray-900">
            #{issue.number} {issue.title}
          </h2>
          <p className="mt-1 text-sm text-gray-500">
            {issue.state === 'OPEN' ? 'Open' : 'Closed'} · 创建于{' '}
            {formatDateTime(issue.createdAt)}
          </p>
        </div>
        <button
          onClick={onClose}
          className="rounded-lg p-2 text-gray-400 transition-colors hover:bg-gray-100 hover:text-gray-700 lg:hidden"
          aria-label="关闭 Issue 详情"
        >
          <CloseIcon className="h-5 w-5" />
        </button>
      </div>

      <div className="space-y-6 p-5">
        <section className="rounded-2xl border border-gray-200 bg-gray-50 p-5">
          <div className="mb-4 flex flex-col gap-3 md:flex-row md:items-start md:justify-between">
            <div>
              <div className="mb-2 flex flex-wrap items-center gap-2">
                <span
                  className={`inline-flex items-center gap-2 rounded-full border px-3 py-1 text-xs font-semibold ${getRunStatusClass(runStatus)}`}
                >
                  {(runStatus === 'running' || runStatus === 'stopping') && (
                    <span className="h-2 w-2 animate-pulse rounded-full bg-current" />
                  )}
                  {getRunStatusLabel(runStatus)}
                </span>
                {showRunMeta && (
                  <span className="text-xs text-gray-500">
                    当前任务 #{activeIssueNumber}
                    {exitCode !== null ? ` · exit code ${exitCode}` : ''}
                  </span>
                )}
              </div>
              <h3 className="text-sm font-semibold uppercase tracking-[0.18em] text-gray-500">
                运行控制
              </h3>
              <p className="mt-2 text-sm leading-6 text-gray-500">
                选择当前 Issue 后可直接启动 `run.sh`，输出会实时显示在下方。
              </p>
            </div>

            <div className="flex flex-wrap gap-2">
              <button
                type="button"
                onClick={() => {
                  clearRunError();
                  if (projectPath) {
                    void startRun(
                      buildIssueRunRequest(projectPath, issue.number, {
                        maxIterations,
                        passingScore,
                        continueMode,
                      })
                    );
                  }
                }}
                disabled={!canStart}
                className="inline-flex items-center gap-2 rounded-lg bg-blue-600 px-4 py-2 text-sm font-medium text-white transition-colors hover:bg-blue-500 disabled:cursor-not-allowed disabled:bg-gray-300"
              >
                <PlayIcon className="h-4 w-4" />
                启动
              </button>
              <button
                type="button"
                onClick={() => {
                  clearRunError();
                  void stopRun();
                }}
                disabled={!canStop}
                className="inline-flex items-center gap-2 rounded-lg border border-gray-300 bg-white px-4 py-2 text-sm font-medium text-gray-700 transition-colors hover:bg-gray-100 disabled:cursor-not-allowed disabled:border-gray-200 disabled:bg-gray-100 disabled:text-gray-400"
              >
                <StopIcon className="h-4 w-4" />
                停止
              </button>
            </div>
          </div>

          <div className="space-y-4">
            <RunConfigPanel
              defaultConfig={{
                maxIterations: DEFAULT_MAX_ITERATIONS,
                passingScore: DEFAULT_PASSING_SCORE,
                continueMode: DEFAULT_CONTINUE_MODE,
              }}
            />
            <div className="rounded-xl border border-gray-200 bg-white p-4">
              <AgentSelector />
            </div>
          </div>

          {!isSupported && (
            <div className="rounded-xl border border-amber-200 bg-amber-50 px-4 py-3 text-sm text-amber-800">
              浏览器模式不支持启动任务，请通过 `pnpm tauri dev` 运行桌面应用。
            </div>
          )}

          {isSupported && !isCurrentIssueRunning && isRunActive && activeIssueNumber !== null && (
            <div className="rounded-xl border border-blue-200 bg-blue-50 px-4 py-3 text-sm text-blue-700">
              当前正在运行 Issue #{activeIssueNumber}，一次只能处理一个任务。
            </div>
          )}

          {runError && (
            <div className="mt-3 rounded-xl border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-700">
              {runError}
            </div>
          )}

          <div className="mt-4 overflow-hidden rounded-2xl border border-gray-200 bg-gray-950 text-gray-100">
            <div className="flex items-center justify-between border-b border-gray-800 px-4 py-3">
              <div className="flex items-center gap-2 text-sm font-medium text-gray-200">
                <TerminalIcon className="h-4 w-4" />
                实时输出
              </div>
              <button
                type="button"
                onClick={clearOutput}
                disabled={outputLines.length === 0}
                className="rounded-md border border-gray-700 px-2.5 py-1 text-xs text-gray-300 transition-colors hover:bg-gray-800 disabled:cursor-not-allowed disabled:opacity-40"
              >
                清空
              </button>
            </div>
            <div
              ref={outputContainerRef}
              className="max-h-72 overflow-y-auto px-4 py-3"
            >
              <pre className="whitespace-pre-wrap break-words font-mono text-xs leading-6 text-gray-100">
                {outputText}
              </pre>
            </div>
          </div>
        </section>

        {isLoading ? (
          <DetailSkeleton />
        ) : error ? (
          <ErrorState message={error} onRetry={onRetry} />
        ) : (
          <>
            <section className="rounded-2xl border border-gray-200 bg-gray-50 p-5">
              <div className="mb-4 flex items-center justify-between gap-3">
                <h3 className="text-sm font-semibold uppercase tracking-[0.18em] text-gray-500">
                  描述
                </h3>
              </div>
              {detail?.body.trim() ? (
                <ReactMarkdown className="markdown-body">
                  {detail.body}
                </ReactMarkdown>
              ) : (
                <EmptyContentState title="该 Issue 暂无描述。" />
              )}
            </section>

            <section className="rounded-2xl border border-gray-200 bg-gray-50 p-5">
              <div className="mb-4 flex items-center gap-2">
                <CommentIcon className="h-4 w-4 text-gray-400" />
                <h3 className="text-sm font-semibold uppercase tracking-[0.18em] text-gray-500">
                  评论
                </h3>
                <span className="rounded-full bg-gray-200 px-2 py-0.5 text-xs text-gray-500">
                  {detail?.comments.length ?? 0}
                </span>
              </div>

              {detail && detail.comments.length > 0 ? (
                <div className="space-y-4">
                  {detail.comments.map((comment) => (
                    <article
                      key={comment.id}
                      className="rounded-2xl border border-gray-200 bg-white p-4"
                    >
                      <div className="mb-4 flex items-center gap-3">
                        <img
                          src={avatarUrl(comment.author.login)}
                          alt={`${comment.author.login} avatar`}
                          className="h-10 w-10 rounded-full border border-gray-200 bg-gray-100 object-cover"
                        />
                        <div>
                          <p className="text-sm font-semibold text-gray-800">
                            {comment.author.login}
                          </p>
                          <p className="text-xs text-gray-500">
                            {formatDateTime(comment.createdAt)}
                          </p>
                        </div>
                      </div>
                      <ReactMarkdown className="markdown-body markdown-comment">
                        {comment.body}
                      </ReactMarkdown>
                    </article>
                  ))}
                </div>
              ) : (
                <EmptyContentState title="该 Issue 暂无评论。" />
              )}
            </section>
          </>
        )}
      </div>
    </aside>
  );
}

export default IssueDetailPanel;
