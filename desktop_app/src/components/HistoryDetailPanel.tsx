import { useEffect, type JSX } from 'react';
import { useProjectStore } from '../stores/projectStore';
import {
  useHistoryDetailStore,
} from '../stores/historyDetailStore';
import type {
  RunStatus,
  IterationSummary,
  SubtaskStatusEntry,
} from '../stores/historyStore';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const STATUS_LABEL: Record<RunStatus, string> = {
  Success: '成功',
  Fail: '失败',
  Interrupt: '中断',
  InProgress: '进行中',
};

const STATUS_BADGE_CLASS: Record<RunStatus, string> = {
  Success: 'bg-green-50 text-green-700 border-green-200',
  Fail: 'bg-red-50 text-red-700 border-red-200',
  Interrupt: 'bg-amber-50 text-amber-700 border-amber-200',
  InProgress: 'bg-blue-50 text-blue-700 border-blue-200',
};

const STATUS_DOT_CLASS: Record<RunStatus, string> = {
  Success: 'bg-green-500',
  Fail: 'bg-red-500',
  Interrupt: 'bg-amber-500',
  InProgress: 'bg-blue-500',
};

const SUBTASK_BADGE: Record<string, string> = {
  Passing: 'bg-green-50 text-green-700 border-green-200',
  Failing: 'bg-red-50 text-red-700 border-red-200',
  Pending: 'bg-gray-50 text-gray-500 border-gray-200',
};

const SUBTASK_LABEL: Record<string, string> = {
  Passing: '已通过',
  Failing: '未通过',
  Pending: '待处理',
};

const SUBTASK_DOT: Record<string, string> = {
  Passing: 'bg-green-500',
  Failing: 'bg-red-500',
  Pending: 'bg-gray-300',
};

function formatTime(iso: string | null): string {
  if (!iso) return '-';
  try {
    const d = new Date(iso);
    const pad = (n: number) => String(n).padStart(2, '0');
    return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())} ${pad(d.getHours())}:${pad(d.getMinutes())}`;
  } catch {
    return '-';
  }
}

// ---------------------------------------------------------------------------
// Sub-components
// ---------------------------------------------------------------------------

function CloseIcon({ className }: { className?: string }): JSX.Element {
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
        d="M6 18L18 6M6 6l12 12"
      />
    </svg>
  );
}

function BackIcon({ className }: { className?: string }): JSX.Element {
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
        d="M15 19l-7-7 7-7"
      />
    </svg>
  );
}

function StatusBadge({ status }: { status: RunStatus }): JSX.Element {
  return (
    <span
      className={`inline-flex items-center gap-1 px-2 py-0.5 rounded text-xs font-medium border ${STATUS_BADGE_CLASS[status]}`}
    >
      <span className={`w-1.5 h-1.5 rounded-full ${STATUS_DOT_CLASS[status]}`} />
      {STATUS_LABEL[status]}
    </span>
  );
}

// ---------------------------------------------------------------------------
// SubtaskProgressView
// ---------------------------------------------------------------------------

function SubtaskProgressView({
  subtasks,
}: {
  subtasks: SubtaskStatusEntry[];
}): JSX.Element {
  if (subtasks.length === 0) {
    return <p className="text-xs text-gray-400">暂无子任务信息。</p>;
  }

  const passed = subtasks.filter((s) => s.status === 'Passing').length;
  const total = subtasks.length;
  const pct = total > 0 ? Math.round((passed / total) * 100) : 0;

  return (
    <div className="space-y-3">
      <div className="flex items-center justify-between text-xs">
        <span className="font-medium text-gray-600">
          已通过 {passed}/{total} 个子任务
        </span>
        <span className="text-gray-400">{pct}%</span>
      </div>
      <div className="h-2 overflow-hidden rounded-full bg-gray-200">
        <div
          className="h-full rounded-full bg-blue-500 transition-all"
          style={{ width: `${pct}%` }}
        />
      </div>
      <ul className="space-y-1.5">
        {subtasks.map((subtask) => (
          <li
            key={subtask.id}
            className="flex items-center justify-between rounded-lg border border-gray-100 bg-white px-3 py-2 text-sm"
          >
            <span className="min-w-0 truncate text-gray-700">
              <span className="mr-1.5 font-mono text-xs text-gray-400">
                {subtask.id}
              </span>
              {subtask.title}
            </span>
            <span
              className={`ml-2 inline-flex items-center gap-1 shrink-0 rounded-full border px-2 py-0.5 text-xs font-medium ${SUBTASK_BADGE[subtask.status] ?? SUBTASK_BADGE.Pending}`}
            >
              <span
                className={`w-1.5 h-1.5 rounded-full ${SUBTASK_DOT[subtask.status] ?? SUBTASK_DOT.Pending}`}
              />
              {SUBTASK_LABEL[subtask.status] ?? subtask.status}
            </span>
          </li>
        ))}
      </ul>
    </div>
  );
}

// ---------------------------------------------------------------------------
// IterationTabView
// ---------------------------------------------------------------------------

function IterationTabView({
  iterations,
  selectedIteration,
  onSelect,
}: {
  iterations: IterationSummary[];
  selectedIteration: number;
  onSelect: (iteration: number) => void;
}): JSX.Element {
  if (iterations.length === 0) {
    return <p className="text-xs text-gray-400">暂无迭代记录。</p>;
  }

  return (
    <div>
      <div className="flex flex-wrap gap-1 border-b border-gray-200 mb-3">
        {iterations.map((iter) => {
          const isActive = iter.iteration === selectedIteration;
          return (
            <button
              key={iter.iteration}
              type="button"
              onClick={() => onSelect(iter.iteration)}
              className={`px-3 py-1.5 text-xs font-medium rounded-t-lg transition-colors ${
                isActive
                  ? 'bg-blue-50 text-blue-700 border border-b-0 border-blue-200'
                  : 'text-gray-500 hover:text-gray-700 hover:bg-gray-50'
              }`}
            >
              迭代 {iter.iteration}
              {iter.score != null && (
                <span className="ml-1 text-gray-400">({iter.score})</span>
              )}
            </button>
          );
        })}
      </div>
    </div>
  );
}

function IterationLogContent({
  log,
  isLoading,
}: {
  log: string | undefined;
  isLoading: boolean;
}): JSX.Element {
  if (isLoading) {
    return (
      <div className="text-xs text-blue-500 animate-pulse py-3">
        加载日志中...
      </div>
    );
  }

  if (!log) {
    return (
      <div className="text-xs text-gray-400 py-3">该迭代暂无日志。</div>
    );
  }

  return (
    <div className="font-mono text-xs text-gray-700 whitespace-pre-wrap break-words bg-gray-50 rounded-lg p-3 max-h-[24rem] overflow-y-auto leading-relaxed">
      {log}
    </div>
  );
}

function IterationSummaryCard({
  iteration,
}: {
  iteration: IterationSummary | undefined;
}): JSX.Element | null {
  if (!iteration) {
    return null;
  }

  return (
    <div className="flex items-center gap-3 rounded-lg border border-gray-100 bg-white px-3 py-2 text-sm mb-3">
      <span className="text-gray-500">Agent:</span>
      <span className="font-medium text-gray-700">{iteration.agent}</span>
      {iteration.score != null ? (
        <>
          <span className="text-gray-400">|</span>
          <span className="text-gray-500">评分:</span>
          <span
            className={`font-semibold ${
              iteration.score >= 85
                ? 'text-green-600'
                : iteration.score >= 60
                  ? 'text-amber-600'
                  : 'text-red-600'
            }`}
          >
            {iteration.score}/100
          </span>
        </>
      ) : (
        <>
          <span className="text-gray-400">|</span>
          <span className="text-gray-400">未评分</span>
        </>
      )}
      {iteration.review_summary && (
        <>
          <span className="text-gray-400">|</span>
          <span className="text-gray-600 truncate flex-1 min-w-0">
            {iteration.review_summary}
          </span>
        </>
      )}
    </div>
  );
}

// ---------------------------------------------------------------------------
// Main DetailPanel
// ---------------------------------------------------------------------------

interface HistoryDetailPanelProps {
  issueNumber: number;
  onClose: () => void;
}

export default function HistoryDetailPanel({
  issueNumber,
  onClose,
}: HistoryDetailPanelProps): JSX.Element {
  const { projectPath } = useProjectStore();
  const {
    detail,
    subtasks,
    iterationLogs,
    selectedIteration,
    isLoadingDetail,
    isLoadingLog,
    isExporting,
    exportError,
    error,
    loadDetail,
    loadIterationLog,
    exportLog,
    clearError,
  } = useHistoryDetailStore();

  useEffect(() => {
    if (projectPath) {
      void loadDetail(projectPath, issueNumber);
    }
  }, [projectPath, issueNumber, loadDetail]);

  const handleTabSelect = (iteration: number) => {
    if (projectPath) {
      void loadIterationLog(projectPath, issueNumber, iteration);
    }
  };

  const currentIteration = detail?.iterations.find(
    (i) => i.iteration === selectedIteration,
  );

  if (isLoadingDetail) {
    return (
      <div className="flex flex-col h-full">
        <div className="flex items-center justify-between px-4 py-3 border-b border-gray-200">
          <h2 className="text-lg font-bold text-gray-900">加载中...</h2>
          <button
            type="button"
            onClick={onClose}
            className="p-1 rounded-md hover:bg-gray-100 text-gray-400 hover:text-gray-600"
            aria-label="关闭详情面板"
          >
            <CloseIcon className="w-5 h-5" />
          </button>
        </div>
        <div className="flex-1 p-4">
          <div className="skeleton-shimmer h-6 w-48 rounded bg-gray-100 mb-3" />
          <div className="skeleton-shimmer h-4 w-32 rounded bg-gray-100 mb-6" />
          <div className="skeleton-shimmer h-4 w-full rounded bg-gray-100 mb-2" />
          <div className="skeleton-shimmer h-4 w-3/4 rounded bg-gray-100" />
        </div>
      </div>
    );
  }

  if (!detail) {
    return (
      <div className="flex flex-col h-full">
        <div className="flex items-center justify-between px-4 py-3 border-b border-gray-200">
          <h2 className="text-lg font-bold text-gray-900">详情</h2>
          <button
            type="button"
            onClick={onClose}
            className="p-1 rounded-md hover:bg-gray-100 text-gray-400 hover:text-gray-600"
            aria-label="关闭详情面板"
          >
            <CloseIcon className="w-5 h-5" />
          </button>
        </div>
        <div className="flex-1 flex items-center justify-center">
          {error ? (
            <div className="text-center space-y-3">
              <p className="text-sm text-red-500">{error}</p>
              <button
                type="button"
                onClick={() => {
                  clearError();
                  if (projectPath) void loadDetail(projectPath, issueNumber);
                }}
                className="text-xs text-blue-500 hover:text-blue-700 underline"
              >
                重试
              </button>
            </div>
          ) : (
            <p className="text-sm text-gray-400">未找到详情数据。</p>
          )}
        </div>
      </div>
    );
  }

  return (
    <div className="flex flex-col h-full">
      {/* Header */}
      <div className="flex items-center justify-between px-4 py-3 border-b border-gray-200 bg-white sticky top-0 z-10">
        <div className="flex items-center gap-2 min-w-0">
          <button
            type="button"
            onClick={onClose}
            className="p-1 rounded-md hover:bg-gray-100 text-gray-400 hover:text-gray-600 shrink-0"
            aria-label="返回历史列表"
          >
            <BackIcon className="w-5 h-5" />
          </button>
          <h2 className="text-lg font-bold text-gray-900 truncate">
            #{detail.issue_number}
          </h2>
          <StatusBadge status={detail.status} />
        </div>
        <div className="flex items-center gap-2 shrink-0">
          <button
            type="button"
            onClick={() => {
              if (projectPath) void exportLog(projectPath, issueNumber);
            }}
            disabled={isExporting}
            className={`inline-flex items-center gap-1 px-2.5 py-1 rounded-md text-xs font-medium border ${
              isExporting
                ? 'bg-gray-100 text-gray-400 border-gray-200 cursor-not-allowed'
                : 'bg-blue-50 text-blue-700 border-blue-200 hover:bg-blue-100'
            }`}
            aria-label="导出日志"
          >
            <svg
              className="w-3.5 h-3.5"
              fill="none"
              stroke="currentColor"
              viewBox="0 0 24 24"
              aria-hidden="true"
            >
              <path
                strokeLinecap="round"
                strokeLinejoin="round"
                strokeWidth={2}
                d="M12 10v6m0 0l-3-3m3 3l3-3m2 8H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z"
              />
            </svg>
            {isExporting ? '导出中...' : '导出日志'}
          </button>
          <button
            type="button"
            onClick={onClose}
            className="p-1 rounded-md hover:bg-gray-100 text-gray-400 hover:text-gray-600"
            aria-label="关闭详情面板"
          >
            <CloseIcon className="w-5 h-5" />
          </button>
        </div>
      </div>

      {/* Scrollable content */}
      <div className="flex-1 overflow-y-auto p-4 space-y-5">
        {/* Issue info */}
        <div>
          <h3 className="text-base font-semibold text-gray-800 mb-2">
            {detail.title}
          </h3>
          <div className="flex flex-wrap items-center gap-3 text-xs text-gray-500">
            {detail.final_score != null && (
              <span className="font-semibold text-gray-700">
                最终评分: {detail.final_score}/100
              </span>
            )}
            {detail.total_iterations != null && (
              <span>{detail.total_iterations} 次迭代</span>
            )}
            <span>开始: {formatTime(detail.start_time)}</span>
            {detail.end_time && (
              <span>结束: {formatTime(detail.end_time)}</span>
            )}
          </div>
        </div>

        {/* Subtask progress */}
        <div>
          <h4 className="text-sm font-semibold text-gray-700 mb-2">子任务进度</h4>
          <SubtaskProgressView subtasks={subtasks} />
        </div>

        {/* Iteration tabs + log */}
        <div>
          <h4 className="text-sm font-semibold text-gray-700 mb-2">迭代日志</h4>
          <IterationTabView
            iterations={detail.iterations}
            selectedIteration={selectedIteration}
            onSelect={handleTabSelect}
          />
          <IterationSummaryCard iteration={currentIteration} />
          <IterationLogContent
            log={iterationLogs[selectedIteration]}
            isLoading={isLoadingLog}
          />
        </div>

        {/* Export error feedback */}
        {exportError && (
          <div className="rounded-lg border border-red-200 bg-red-50 px-3 py-2 text-xs text-red-600">
            {exportError}
          </div>
        )}
      </div>
    </div>
  );
}
