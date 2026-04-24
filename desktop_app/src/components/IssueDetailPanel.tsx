import type { JSX } from 'react';
import ReactMarkdown from 'react-markdown';
import { formatDateTime, GhIssue, IssueDetail } from '../stores/issueStore';

interface IssueDetailPanelProps {
  issue: GhIssue | null;
  detail: IssueDetail | null;
  isLoading: boolean;
  error: string | null;
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

function DetailSkeleton(): JSX.Element {
  return (
    <div className="space-y-6">
      <div className="rounded-2xl border border-gray-700 bg-gray-900/80 p-5">
        <div className="skeleton-shimmer mb-4 h-6 w-1/3 rounded bg-gray-800" />
        <div className="skeleton-shimmer mb-3 h-4 w-full rounded bg-gray-800" />
        <div className="skeleton-shimmer mb-3 h-4 w-11/12 rounded bg-gray-800" />
        <div className="skeleton-shimmer h-28 w-full rounded-2xl bg-gray-950" />
      </div>
      <div className="rounded-2xl border border-gray-700 bg-gray-900/80 p-5">
        <div className="skeleton-shimmer mb-4 h-5 w-24 rounded bg-gray-800" />
        <div className="space-y-4">
          <div className="rounded-xl border border-gray-800 bg-gray-950/70 p-4">
            <div className="mb-3 flex items-center gap-3">
              <div className="skeleton-shimmer h-10 w-10 rounded-full bg-gray-800" />
              <div className="flex-1 space-y-2">
                <div className="skeleton-shimmer h-4 w-32 rounded bg-gray-800" />
                <div className="skeleton-shimmer h-3 w-24 rounded bg-gray-800" />
              </div>
            </div>
            <div className="skeleton-shimmer mb-2 h-4 w-full rounded bg-gray-800" />
            <div className="skeleton-shimmer h-4 w-4/5 rounded bg-gray-800" />
          </div>
        </div>
      </div>
    </div>
  );
}

function EmptySelectionState(): JSX.Element {
  return (
    <div className="flex h-full min-h-[420px] items-center justify-center rounded-3xl border border-dashed border-gray-700 bg-gray-900/40 p-8 text-center">
      <div>
        <CommentIcon className="mx-auto mb-4 h-12 w-12 text-gray-600" />
        <h2 className="mb-2 text-lg font-semibold text-gray-200">选择一个 Issue</h2>
        <p className="max-w-sm text-sm leading-6 text-gray-500">
          从左侧列表中点击 Issue 后，这里会展示描述、评论和最新状态。
        </p>
      </div>
    </div>
  );
}

function EmptyContentState({ title }: { title: string }): JSX.Element {
  return (
    <div className="rounded-2xl border border-dashed border-gray-700 bg-gray-950/50 p-4 text-sm text-gray-500">
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
    <div className="rounded-2xl border border-red-700/60 bg-red-950/30 p-5">
      <h3 className="mb-2 text-sm font-semibold text-red-200">详情加载失败</h3>
      <p className="mb-4 text-sm leading-6 text-red-300">{message}</p>
      <button
        onClick={onRetry}
        className="rounded-lg border border-red-600 px-3 py-2 text-sm font-medium text-red-200 transition-colors hover:bg-red-900/40"
      >
        重试
      </button>
    </div>
  );
}

function avatarUrl(login: string): string {
  return `https://github.com/${encodeURIComponent(login)}.png?size=80`;
}

function IssueDetailPanel({
  issue,
  detail,
  isLoading,
  error,
  onClose,
  onRetry,
}: IssueDetailPanelProps): JSX.Element {
  if (!issue) {
    return <EmptySelectionState />;
  }

  return (
    <aside className="rounded-3xl border border-gray-700 bg-gray-800/50 shadow-2xl shadow-black/20">
      <div className="sticky top-0 z-10 flex items-start justify-between gap-4 rounded-t-3xl border-b border-gray-700 bg-gray-800/95 px-5 py-4 backdrop-blur">
        <div className="min-w-0">
          <p className="mb-1 text-xs font-medium uppercase tracking-[0.2em] text-blue-300">
            Issue Detail
          </p>
          <h2 className="truncate text-lg font-semibold text-gray-100">
            #{issue.number} {issue.title}
          </h2>
          <p className="mt-1 text-sm text-gray-500">
            {issue.state === 'open' ? 'Open' : 'Closed'} · 创建于{' '}
            {formatDateTime(issue.createdAt)}
          </p>
        </div>
        <button
          onClick={onClose}
          className="rounded-lg p-2 text-gray-400 transition-colors hover:bg-gray-700 hover:text-gray-200 lg:hidden"
          aria-label="关闭 Issue 详情"
        >
          <CloseIcon className="h-5 w-5" />
        </button>
      </div>

      <div className="space-y-6 p-5">
        {isLoading ? (
          <DetailSkeleton />
        ) : error ? (
          <ErrorState message={error} onRetry={onRetry} />
        ) : (
          <>
            <section className="rounded-2xl border border-gray-700 bg-gray-900/80 p-5">
              <div className="mb-4 flex items-center justify-between gap-3">
                <h3 className="text-sm font-semibold uppercase tracking-[0.18em] text-gray-400">
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

            <section className="rounded-2xl border border-gray-700 bg-gray-900/80 p-5">
              <div className="mb-4 flex items-center gap-2">
                <CommentIcon className="h-4 w-4 text-gray-400" />
                <h3 className="text-sm font-semibold uppercase tracking-[0.18em] text-gray-400">
                  评论
                </h3>
                <span className="rounded-full bg-gray-800 px-2 py-0.5 text-xs text-gray-400">
                  {detail?.comments.length ?? 0}
                </span>
              </div>

              {detail && detail.comments.length > 0 ? (
                <div className="space-y-4">
                  {detail.comments.map((comment) => (
                    <article
                      key={comment.id}
                      className="rounded-2xl border border-gray-700 bg-gray-950/70 p-4"
                    >
                      <div className="mb-4 flex items-center gap-3">
                        <img
                          src={avatarUrl(comment.author.login)}
                          alt={`${comment.author.login} avatar`}
                          className="h-10 w-10 rounded-full border border-gray-700 bg-gray-800 object-cover"
                        />
                        <div>
                          <p className="text-sm font-semibold text-gray-200">
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
