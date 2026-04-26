import { useEffect, useMemo, useState, useCallback, useRef, type JSX } from 'react';
import { useProjectStore } from '../stores/projectStore';
import Dropdown from '../components/Dropdown';
import {
  useHistoryStore,
  getFilteredAndSortedHistory,
  HistoryEntry,
  RunStatus,
  StatusFilter,
  SortOrder,
} from '../stores/historyStore';
import { useHistoryDetailStore } from '../stores/historyDetailStore';
import HistoryDetailPanel from '../components/HistoryDetailPanel';

// ---------------------------------------------------------------------------
// Status helpers
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

const FILTER_OPTIONS: { value: StatusFilter; label: string }[] = [
  { value: 'all', label: '全部状态' },
  { value: 'success', label: '成功' },
  { value: 'fail', label: '失败' },
  { value: 'interrupt', label: '中断' },
  { value: 'in_progress', label: '进行中' },
];

const SORT_OPTIONS: { value: SortOrder; label: string }[] = [
  { value: 'desc', label: '最新优先' },
  { value: 'asc', label: '最早优先' },
];

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

function ChevronRight({ className }: { className?: string }): JSX.Element {
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
        d="M9 5l7 7-7 7"
      />
    </svg>
  );
}

function HistoryListItem({
  entry,
  isSelected,
  onClick,
}: {
  entry: HistoryEntry;
  isSelected: boolean;
  onClick: () => void;
}): JSX.Element {
  return (
    <button
      type="button"
      onClick={onClick}
      className={`w-full text-left p-4 rounded-lg border transition-all ${
        isSelected
          ? 'bg-blue-50 border-blue-300 ring-1 ring-blue-200'
          : 'bg-white border-gray-200 hover:border-gray-300 hover:bg-gray-50'
      }`}
    >
      <div className="flex items-start justify-between gap-3">
        <div className="flex-1 min-w-0">
          <div className="flex items-center gap-2 mb-1">
            <span className="text-xs text-blue-600 font-mono font-medium">
              #{entry.issue_number}
            </span>
            <StatusBadge status={entry.status} />
          </div>
          <h3 className="text-sm font-medium text-gray-800 truncate">
            {entry.title}
          </h3>
        </div>
        <div className="flex-shrink-0 flex items-center gap-2">
          {entry.final_score != null ? (
            <span className="text-sm font-semibold text-gray-700">
              {entry.final_score}/100
            </span>
          ) : (
            <span className="text-sm text-gray-400">-</span>
          )}
          <ChevronRight className="w-4 h-4 text-gray-300" />
        </div>
      </div>
      <div className="mt-2 flex items-center gap-3 text-xs text-gray-500">
        <span>{formatTime(entry.start_time)}</span>
        {entry.total_iterations != null && (
          <span>{entry.total_iterations} 次迭代</span>
        )}
      </div>
    </button>
  );
}

function SkeletonRow(): JSX.Element {
  return (
    <div className="p-4 rounded-lg border border-gray-100 bg-white">
      <div className="flex items-center gap-3 mb-2">
        <div className="skeleton-shimmer h-4 w-12 rounded bg-gray-100" />
        <div className="skeleton-shimmer h-5 w-16 rounded bg-gray-100" />
      </div>
      <div className="skeleton-shimmer h-4 w-3/4 rounded bg-gray-100 mb-2" />
      <div className="skeleton-shimmer h-3 w-1/3 rounded bg-gray-100" />
    </div>
  );
}

function EmptyState(): JSX.Element {
  return (
    <div className="flex flex-col items-center justify-center py-16 text-gray-400">
      <svg
        className="w-16 h-16 mb-4 opacity-50"
        fill="none"
        stroke="currentColor"
        viewBox="0 0 24 24"
      >
        <path
          strokeLinecap="round"
          strokeLinejoin="round"
          strokeWidth={1.5}
          d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z"
        />
      </svg>
      <p className="text-sm font-medium text-gray-500 mb-1">暂无历史记录</p>
      <p className="text-xs text-gray-400">处理完成的 Issue 将出现在这里</p>
    </div>
  );
}

function NoProjectState(): JSX.Element {
  return (
    <div className="flex flex-col items-center justify-center h-full min-h-[400px] text-gray-400">
      <svg
        className="w-16 h-16 mb-4 opacity-50"
        fill="none"
        stroke="currentColor"
        viewBox="0 0 24 24"
      >
        <path
          strokeLinecap="round"
          strokeLinejoin="round"
          strokeWidth={1.5}
          d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z"
        />
      </svg>
      <h2 className="text-xl font-bold text-gray-600 mb-2">请先选择项目</h2>
      <p className="text-sm text-gray-500 text-center max-w-md">
        在"概览"页面选择一个项目目录后，即可查看处理历史记录
      </p>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Main page
// ---------------------------------------------------------------------------

function HistoryPage(): JSX.Element {
  const { projectPath } = useProjectStore();
  const {
    entries,
    statusFilter,
    sortOrder,
    isLoading,
    error,
    loadHistory,
    setStatusFilter,
    setSortOrder,
    clearError,
  } = useHistoryStore();
  const { clearDetail } = useHistoryDetailStore();

  const [selectedIssue, setSelectedIssue] = useState<number | null>(null);

  // Load history when projectPath changes
  useEffect(() => {
    if (projectPath) {
      void loadHistory(projectPath);
    }
  }, [projectPath, loadHistory]);

  const filtered = useMemo(
    () => getFilteredAndSortedHistory(entries, statusFilter, sortOrder),
    [entries, statusFilter, sortOrder],
  );

  const handleSelectIssue = useCallback((issueNumber: number) => {
    setSelectedIssue(issueNumber);
  }, []);

  const handleCloseDetail = useCallback(() => {
    setSelectedIssue(null);
    clearDetail();
  }, [clearDetail]);

  // --- Detail panel resize handle ---
  const MIN_DETAIL_WIDTH = 400;
  const MAX_DETAIL_WIDTH = 1080;
  const containerRef = useRef<HTMLDivElement>(null);
  const [detailWidth, setDetailWidth] = useState(0);
  const dragRef = useRef({ isDragging: false, startX: 0, startWidth: 0 });

  // Initialize detailWidth to 50% of container on first layout
  useEffect(() => {
    const el = containerRef.current;
    if (!el || detailWidth > 0) return;
    const observer = new ResizeObserver(([entry]) => {
      const half = Math.round(entry.contentRect.width * 2 / 3);
      setDetailWidth((prev) => prev === 0 ? Math.min(MAX_DETAIL_WIDTH, Math.max(MIN_DETAIL_WIDTH, half)) : prev);
    });
    observer.observe(el);
    return () => observer.disconnect();
  }, [detailWidth]);

  const handleResizeMouseDown = useCallback((e: React.MouseEvent) => {
    e.preventDefault();
    dragRef.current = { isDragging: true, startX: e.clientX, startWidth: detailWidth };
    document.body.style.cursor = 'col-resize';
    document.body.style.userSelect = 'none';
  }, [detailWidth]);

  useEffect(() => {
    const onMouseMove = (e: MouseEvent) => {
      if (!dragRef.current.isDragging) return;
      const delta = dragRef.current.startX - e.clientX;
      const next = Math.min(MAX_DETAIL_WIDTH, Math.max(MIN_DETAIL_WIDTH, dragRef.current.startWidth + delta));
      setDetailWidth(next);
    };
    const onMouseUp = () => {
      if (!dragRef.current.isDragging) return;
      dragRef.current.isDragging = false;
      document.body.style.cursor = '';
      document.body.style.userSelect = '';
    };
    window.addEventListener('mousemove', onMouseMove);
    window.addEventListener('mouseup', onMouseUp);
    return () => {
      window.removeEventListener('mousemove', onMouseMove);
      window.removeEventListener('mouseup', onMouseUp);
    };
  }, []);

  if (!projectPath) {
    return (
      <div className="p-6">
        <NoProjectState />
      </div>
    );
  }

  return (
    <div ref={containerRef} className="flex h-full">
      {/* Left: List */}
      <div className={`p-6 ${selectedIssue != null ? 'flex-1' : 'w-full'} overflow-y-auto`}>
        {/* Header */}
        <div className="flex items-center justify-between mb-6">
          <div>
            <h1 className="text-2xl font-bold text-gray-900 mb-1">历史记录</h1>
            <p className="text-sm text-gray-500">
              共 {entries.length} 条记录
              {statusFilter !== 'all' && `，已筛选 ${filtered.length} 条`}
            </p>
          </div>
        </div>

        {/* Error message */}
        {error && (
          <div className="mb-4 p-3 rounded-lg bg-red-50 border border-red-200 text-red-700 text-sm">
            <div className="flex items-center justify-between">
              <span>{error}</span>
              <div className="flex items-center gap-2">
                <button
                  onClick={() => {
                    clearError();
                    if (projectPath) void loadHistory(projectPath);
                  }}
                  className="text-red-500 hover:text-red-700 text-xs font-medium underline"
                >
                  重试
                </button>
                <button
                  onClick={clearError}
                  aria-label="关闭错误提示"
                  className="text-red-400 hover:text-red-600"
                >
                  <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
                  </svg>
                </button>
              </div>
            </div>
          </div>
        )}

        {/* Toolbar */}
        <div className="mb-4 flex items-center gap-3">
          <Dropdown
            value={statusFilter}
            options={FILTER_OPTIONS}
            onChange={(v) => setStatusFilter(v as StatusFilter)}
            ariaLabel="按状态过滤"
          />

          <Dropdown
            value={sortOrder}
            options={SORT_OPTIONS}
            onChange={(v) => setSortOrder(v as SortOrder)}
            ariaLabel="时间排序"
          />
        </div>

        {/* Content */}
        {isLoading ? (
          <div className="space-y-3">
            <SkeletonRow />
            <SkeletonRow />
            <SkeletonRow />
            <SkeletonRow />
          </div>
        ) : filtered.length > 0 ? (
          <div className="space-y-3">
            {filtered.map((entry) => (
              <HistoryListItem
                key={entry.issue_number}
                entry={entry}
                isSelected={selectedIssue === entry.issue_number}
                onClick={() => handleSelectIssue(entry.issue_number)}
              />
            ))}
          </div>
        ) : (
          <EmptyState />
        )}
      </div>

      {/* Resize handle */}
      {selectedIssue != null && (
        <div
          className="flex flex-col items-center justify-between cursor-col-resize group flex-shrink-0 py-4"
          onMouseDown={handleResizeMouseDown}
          role="separator"
          aria-orientation="vertical"
          aria-label="拖拽调整详情面板宽度"
          title="拖拽调整宽度"
        >
          <svg width="4" height="10" viewBox="0 0 4 10" className="text-gray-300 group-hover:text-blue-400 transition-colors">
            <circle cx="1" cy="1" r="1" fill="currentColor" />
            <circle cx="3" cy="1" r="1" fill="currentColor" />
            <circle cx="1" cy="4.5" r="1" fill="currentColor" />
            <circle cx="3" cy="4.5" r="1" fill="currentColor" />
            <circle cx="1" cy="8" r="1" fill="currentColor" />
            <circle cx="3" cy="8" r="1" fill="currentColor" />
          </svg>
          <svg width="4" height="10" viewBox="0 0 4 10" className="my-1 text-gray-300 group-hover:text-blue-400 transition-colors">
            <circle cx="1" cy="1" r="1" fill="currentColor" />
            <circle cx="3" cy="1" r="1" fill="currentColor" />
            <circle cx="1" cy="4.5" r="1" fill="currentColor" />
            <circle cx="3" cy="4.5" r="1" fill="currentColor" />
            <circle cx="1" cy="8" r="1" fill="currentColor" />
            <circle cx="3" cy="8" r="1" fill="currentColor" />
          </svg>
          <svg width="4" height="10" viewBox="0 0 4 10" className="text-gray-300 group-hover:text-blue-400 transition-colors">
            <circle cx="1" cy="1" r="1" fill="currentColor" />
            <circle cx="3" cy="1" r="1" fill="currentColor" />
            <circle cx="1" cy="4.5" r="1" fill="currentColor" />
            <circle cx="3" cy="4.5" r="1" fill="currentColor" />
            <circle cx="1" cy="8" r="1" fill="currentColor" />
            <circle cx="3" cy="8" r="1" fill="currentColor" />
          </svg>
        </div>
      )}

      {/* Right: Detail panel */}
      {selectedIssue != null && (
        <div className="shrink-0 overflow-y-auto bg-gray-50" style={{ width: detailWidth }}>
          <HistoryDetailPanel
            issueNumber={selectedIssue}
            onClose={handleCloseDetail}
          />
        </div>
      )}
    </div>
  );
}

export default HistoryPage;
