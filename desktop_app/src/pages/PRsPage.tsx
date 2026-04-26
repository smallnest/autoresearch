import { useCallback, useEffect, useMemo, useState } from 'react';
import { useProjectStore } from '../stores/projectStore';
import {
  usePrStore,
  GhPullRequest,
  PrFileChange,
} from '../stores/prStore';
import DiffViewer from '../components/DiffViewer';
import ConfirmModal from '../components/ConfirmModal';
import Toast, { useToast } from '../components/Toast';

// PR Icon
function PRIcon({ className }: { className?: string }): JSX.Element {
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
        d="M8 7h12m0 0l-4-4m4 4l-4 4m0 6H4m0 0l4 4m-4-4l4-4"
      />
    </svg>
  );
}

// Clear Icon
function ClearIcon({ className }: { className?: string }): JSX.Element {
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

// File Icon
function FileIcon({ className }: { className?: string }): JSX.Element {
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
        d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z"
      />
    </svg>
  );
}

// Search Icon
function SearchIcon({ className }: { className?: string }): JSX.Element {
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
        d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z"
      />
    </svg>
  );
}

// Chevron Icon (expand/collapse)
function ChevronIcon({ className, expanded }: { className?: string; expanded: boolean }): JSX.Element {
  return (
    <svg
      className={`${className} transition-transform ${expanded ? 'rotate-90' : ''}`}
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
  );
}

// File change row
function FileChangeRow({ file }: { file: PrFileChange }): JSX.Element {
  return (
    <div className="flex items-center justify-between py-1.5 px-3 text-xs border-b border-gray-100 last:border-b-0">
      <div className="flex items-center gap-2 min-w-0 flex-1">
        <FileIcon className="w-3.5 h-3.5 text-gray-400 flex-shrink-0" />
        <span className="font-mono text-gray-700 truncate">{file.path}</span>
      </div>
      <div className="flex items-center gap-3 flex-shrink-0 ml-2">
        <span className="text-green-600 font-mono">+{file.additions}</span>
        <span className="text-red-500 font-mono">-{file.deletions}</span>
      </div>
    </div>
  );
}

// Collapsible file change list
function FileChangeList({ files }: { files: PrFileChange[] }): JSX.Element {
  const [expanded, setExpanded] = useState(true);

  return (
    <div className="mb-4">
      <button
        type="button"
        onClick={() => setExpanded((v) => !v)}
        className="flex items-center gap-1.5 text-xs text-gray-500 font-medium mb-2 hover:text-gray-700 transition-colors"
      >
        <svg
          className={`w-3.5 h-3.5 transition-transform ${expanded ? '' : '-rotate-90'}`}
          fill="none"
          stroke="currentColor"
          viewBox="0 0 24 24"
        >
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 9l-7 7-7-7" />
        </svg>
        文件变更列表
        <span className="text-gray-400">({files.length})</span>
      </button>
      {expanded && (
        <div className="bg-white rounded-md border border-gray-200 divide-y divide-gray-100">
          {files.map((file) => (
            <FileChangeRow key={file.path} file={file} />
          ))}
        </div>
      )}
    </div>
  );
}

// PR list item with expandable detail
function PRListItem({
  pr,
  isSelected,
  onClick,
  detail,
  detailLoading,
  diffText,
  diffLoading,
  actionLoading,
  onMerge,
  onClose,
}: {
  pr: GhPullRequest;
  isSelected: boolean;
  onClick: () => void;
  detail: { files: PrFileChange[]; additions: number; deletions: number; changedFiles: number } | null;
  detailLoading: boolean;
  diffText: string;
  diffLoading: boolean;
  actionLoading: boolean;
  onMerge: () => void;
  onClose: () => void;
}): JSX.Element {
  return (
    <div
      className={`rounded-lg border transition-all ${
        isSelected
          ? 'bg-blue-50 border-blue-300 shadow-sm'
          : 'bg-white border-gray-200 hover:border-gray-300 hover:bg-gray-50'
      }`}
    >
      <div
        onClick={onClick}
        className="p-4 cursor-pointer"
      >
        <div className="flex items-start gap-3">
          <div className="flex-shrink-0 mt-0.5">
            <div className="w-6 h-6 rounded-full flex items-center justify-center bg-blue-100 text-blue-600">
              <PRIcon className="w-3.5 h-3.5" />
            </div>
          </div>

          <div className="flex-1 min-w-0">
            <div className="flex items-center gap-2 mb-1">
              <span className="text-xs text-gray-500 font-mono">
                #{pr.number}
              </span>
              <span className={`inline-flex items-center px-1.5 py-0.5 rounded text-xs font-medium border ${
                pr.state === 'OPEN'
                  ? 'bg-green-50 text-green-700 border-green-200'
                  : 'bg-purple-50 text-purple-700 border-purple-200'
              }`}>
                {pr.state === 'OPEN' ? '开启' : '已关闭'}
              </span>
              <span className="inline-flex items-center px-1.5 py-0.5 rounded text-xs font-medium bg-gray-100 text-gray-600 border border-gray-200">
                {pr.headRefName}
              </span>
            </div>

            <h3 className="text-sm font-medium text-gray-800 mb-1 truncate">
              {pr.title}
            </h3>

            {detail && (
              <div className="flex items-center gap-3 text-xs text-gray-500 mt-1">
                <span>{detail.changedFiles} 个文件变更</span>
                <span className="text-green-600">+{detail.additions}</span>
                <span className="text-red-500">-{detail.deletions}</span>
              </div>
            )}
          </div>

          <div className="flex-shrink-0 flex items-center gap-1 self-center">
            <ChevronIcon className="w-4 h-4 text-gray-400" expanded={isSelected} />
          </div>
        </div>
      </div>

      {/* Expanded file list and diff */}
      {isSelected && (
        <div className="border-t border-gray-200 bg-gray-50/50 px-4 py-3">
          {/* Action buttons — only for open PRs */}
          {pr.state === 'OPEN' && (
          <div className="flex items-center gap-2 mb-3">
            <button
              onClick={(e) => { e.stopPropagation(); onMerge(); }}
              disabled={actionLoading}
              className="inline-flex items-center gap-1.5 px-3 py-1.5 text-xs font-medium rounded-md bg-green-600 text-white hover:bg-green-700 disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
            >
              {actionLoading ? (
                <svg className="animate-spin w-3.5 h-3.5" fill="none" viewBox="0 0 24 24">
                  <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth={4} />
                  <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z" />
                </svg>
              ) : (
                <svg className="w-3.5 h-3.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M5 13l4 4L19 7" />
                </svg>
              )}
              合并
            </button>
            <button
              onClick={(e) => { e.stopPropagation(); onClose(); }}
              disabled={actionLoading}
              className="inline-flex items-center gap-1.5 px-3 py-1.5 text-xs font-medium rounded-md bg-red-600 text-white hover:bg-red-700 disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
            >
              {actionLoading ? (
                <svg className="animate-spin w-3.5 h-3.5" fill="none" viewBox="0 0 24 24">
                  <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth={4} />
                  <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z" />
                </svg>
              ) : (
                <svg className="w-3.5 h-3.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
                </svg>
              )}
              关闭
            </button>
          </div>
          )}

          {detailLoading || diffLoading ? (
            <div className="flex items-center justify-center py-4">
              <svg
                className="animate-spin w-5 h-5 text-gray-400 mr-2"
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
              <span className="text-xs text-gray-500">
                {detailLoading ? '加载文件变更...' : '加载 Diff...'}
              </span>
            </div>
          ) : (
            <>
              {/* File change summary */}
              {detail && detail.files.length > 0 && (
                <FileChangeList files={detail.files} />
              )}

              {/* Diff viewer */}
              {diffText && (
                <div>
                  <p className="text-xs text-gray-500 mb-2 font-medium">代码差异</p>
                  <DiffViewer diffText={diffText} />
                </div>
              )}
            </>
          )}
        </div>
      )}
    </div>
  );
}

// Empty state
function EmptyState({ message }: { message: string }): JSX.Element {
  return (
    <div className="flex flex-col items-center justify-center py-12 text-gray-500">
      <PRIcon className="w-12 h-12 mb-3 opacity-50" />
      <p className="text-sm">{message}</p>
    </div>
  );
}

// Main PRs Page Component
function PRsPage(): JSX.Element {
  const { projectPath } = useProjectStore();
  const {
    prs,
    selectedPrNumber,
    prDetail,
    prDiff,
    isLoading,
    detailLoading,
    diffLoading,
    actionLoading,
    error,
    detailError,
    loadPrs,
    loadPrDetail,
    loadPrDiff,
    mergePr,
    closePr,
    clearPrDetail,
    clearError,
    clearDetailError,
  } = usePrStore();

  const { toasts, addToast, removeToast } = useToast();

  // Confirmation modal state
  const [confirmAction, setConfirmAction] = useState<'merge' | 'close' | null>(null);
  const [confirmPr, setConfirmPr] = useState<GhPullRequest | null>(null);

  const [searchQuery, setSearchQuery] = useState('');

  // Load PRs when project changes
  useEffect(() => {
    if (projectPath) {
      loadPrs(projectPath);
    }
  }, [projectPath, loadPrs]);

  // Load detail when selected PR changes
  useEffect(() => {
    if (projectPath && selectedPrNumber !== null) {
      loadPrDetail(projectPath, selectedPrNumber);
    }
  }, [projectPath, selectedPrNumber, loadPrDetail]);

  // Load diff when selected PR changes
  useEffect(() => {
    if (projectPath && selectedPrNumber !== null) {
      loadPrDiff(projectPath, selectedPrNumber);
    }
  }, [projectPath, selectedPrNumber, loadPrDiff]);

  // Filter PRs by search query
  const filteredPrs = useMemo(() => {
    if (!searchQuery) return prs;
    const q = searchQuery.toLowerCase();
    return prs.filter(
      (pr) =>
        pr.title.toLowerCase().includes(q) ||
        pr.number.toString().includes(q) ||
        pr.headRefName.toLowerCase().includes(q)
    );
  }, [prs, searchQuery]);

  // Pagination
  const PAGE_SIZE = 10;
  const [currentPage, setCurrentPage] = useState(1);

  useEffect(() => {
    setCurrentPage(1);
  }, [searchQuery]);

  const totalPages = Math.max(1, Math.ceil(filteredPrs.length / PAGE_SIZE));
  const pagedPrs = useMemo(() => {
    const start = (currentPage - 1) * PAGE_SIZE;
    return filteredPrs.slice(start, start + PAGE_SIZE);
  }, [filteredPrs, currentPage]);

  const handlePrClick = (prNumber: number) => {
    if (selectedPrNumber === prNumber) {
      clearPrDetail();
      return;
    }
    usePrStore.getState().selectPr(prNumber);
  };

  const openConfirm = useCallback((action: 'merge' | 'close', pr: GhPullRequest) => {
    setConfirmAction(action);
    setConfirmPr(pr);
  }, []);

  const cancelConfirm = useCallback(() => {
    setConfirmAction(null);
    setConfirmPr(null);
  }, []);

  const executeAction = useCallback(async () => {
    if (!confirmAction || !confirmPr || !projectPath) return;
    const action = confirmAction;
    const pr = confirmPr;
    setConfirmAction(null);
    setConfirmPr(null);

    const result =
      action === 'merge'
        ? await mergePr(projectPath, pr.number)
        : await closePr(projectPath, pr.number);

    if (result.success) {
      addToast(result.message || `${action === 'merge' ? '合并' : '关闭'} PR #${pr.number} 成功`, 'success');
      loadPrs(projectPath);
    } else {
      addToast(result.message, 'error');
    }
  }, [confirmAction, confirmPr, projectPath, mergePr, closePr, addToast, loadPrs]);

  if (!projectPath) {
    return (
      <div className="p-6">
        <div className="flex flex-col items-center justify-center h-full min-h-[400px]">
          <PRIcon className="w-16 h-16 mb-4 text-gray-300" />
          <h2 className="text-xl font-bold text-gray-700 mb-2">
            请先选择项目
          </h2>
          <p className="text-gray-500 text-center max-w-md">
            在"概览"页面选择一个项目目录后，即可查看 GitHub Pull Request
          </p>
        </div>
      </div>
    );
  }

  return (
    <div className="p-6">
      {/* Header */}
      <div className="flex items-center justify-between mb-6">
        <div>
          <h1 className="text-2xl font-bold text-gray-900 mb-1">Pull Requests</h1>
          <p className="text-sm text-gray-500">
            查看项目的 Pull Request 列表和文件变更（{filteredPrs.length} / {prs.length}）
          </p>
        </div>

        <button
          onClick={() => projectPath && loadPrs(projectPath)}
          disabled={isLoading}
          className="px-4 py-2 bg-white hover:bg-gray-50 disabled:bg-gray-100 disabled:cursor-not-allowed text-gray-700 rounded-lg text-sm font-medium transition-colors flex items-center gap-2 border border-gray-200"
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
                  d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15"
                />
              </svg>
              刷新
            </>
          )}
        </button>
      </div>

      {/* Error message */}
      {error && (
        <div className="mb-4 p-3 rounded-lg bg-red-50 border border-red-200 text-red-700 text-sm">
          <div className="flex items-center justify-between">
            <span>{error}</span>
            <button
              onClick={clearError}
              aria-label="关闭错误提示"
              className="ml-2 text-red-400 hover:text-red-600"
            >
              <ClearIcon className="w-4 h-4" />
            </button>
          </div>
        </div>
      )}

      {/* Detail error */}
      {detailError && (
        <div className="mb-4 p-3 rounded-lg bg-red-50 border border-red-200 text-red-700 text-sm">
          <div className="flex items-center justify-between">
            <span>{detailError}</span>
            <button
              onClick={() => {
                clearDetailError();
                if (projectPath && selectedPrNumber !== null) {
                  loadPrDetail(projectPath, selectedPrNumber);
                }
              }}
              aria-label="关闭详情错误"
              className="ml-2 text-red-400 hover:text-red-600"
            >
              <ClearIcon className="w-4 h-4" />
            </button>
          </div>
        </div>
      )}

      {/* Search bar */}
      <div className="mb-4">
        <div className="relative">
          <SearchIcon className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-gray-500" />
          <input
            type="text"
            placeholder="搜索 PR 标题、编号或分支名..."
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            className="w-full pl-10 pr-10 py-2.5 bg-white border border-gray-200 rounded-lg text-sm text-gray-900 placeholder-gray-400 focus:outline-none focus:border-blue-500 focus:ring-1 focus:ring-blue-500 transition-colors"
          />
          {searchQuery && (
            <button
              onClick={() => setSearchQuery('')}
              aria-label="清空搜索"
              className="absolute right-3 top-1/2 -translate-y-1/2 text-gray-500 hover:text-gray-300"
            >
              <ClearIcon className="w-4 h-4" />
            </button>
          )}
        </div>
      </div>

      {/* PR list */}
      <div className="space-y-3">
        {isLoading && prs.length === 0 ? (
          <div className="flex flex-col items-center justify-center py-12">
            <svg
              className="animate-spin w-8 h-8 text-gray-500 mb-3"
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
            <p className="text-sm text-gray-500">正在加载 PR 列表...</p>
          </div>
        ) : pagedPrs.length > 0 ? (
          pagedPrs.map((pr) => (
            <PRListItem
              key={pr.number}
              pr={pr}
              isSelected={selectedPrNumber === pr.number}
              onClick={() => handlePrClick(pr.number)}
              detail={selectedPrNumber === pr.number ? prDetail : null}
              detailLoading={selectedPrNumber === pr.number && detailLoading}
              diffText={selectedPrNumber === pr.number ? (prDiff?.diff ?? '') : ''}
              diffLoading={selectedPrNumber === pr.number && diffLoading}
              actionLoading={selectedPrNumber === pr.number && actionLoading}
              onMerge={() => openConfirm('merge', pr)}
              onClose={() => openConfirm('close', pr)}
            />
          ))
        ) : (
          <EmptyState
            message={searchQuery ? '没有匹配的 PR' : '暂无 Pull Request'}
          />
        )}
      </div>

      {/* Pagination */}
      {totalPages > 1 && (
        <div className="mt-4 flex items-center justify-between">
          <p className="text-xs text-gray-500">
            第 {(currentPage - 1) * PAGE_SIZE + 1}-{Math.min(currentPage * PAGE_SIZE, filteredPrs.length)} 条，共 {filteredPrs.length} 条
          </p>
          <div className="flex items-center gap-1">
            <button
              onClick={() => setCurrentPage(1)}
              disabled={currentPage === 1}
              className="px-2 py-1 text-xs rounded border border-gray-200 text-gray-600 hover:bg-gray-50 disabled:opacity-40 disabled:cursor-not-allowed"
            >
              首页
            </button>
            <button
              onClick={() => setCurrentPage((p) => Math.max(1, p - 1))}
              disabled={currentPage === 1}
              className="px-2 py-1 text-xs rounded border border-gray-200 text-gray-600 hover:bg-gray-50 disabled:opacity-40 disabled:cursor-not-allowed"
            >
              上一页
            </button>
            <span className="px-3 py-1 text-xs text-gray-700 font-medium">
              {currentPage} / {totalPages}
            </span>
            <button
              onClick={() => setCurrentPage((p) => Math.min(totalPages, p + 1))}
              disabled={currentPage === totalPages}
              className="px-2 py-1 text-xs rounded border border-gray-200 text-gray-600 hover:bg-gray-50 disabled:opacity-40 disabled:cursor-not-allowed"
            >
              下一页
            </button>
            <button
              onClick={() => setCurrentPage(totalPages)}
              disabled={currentPage === totalPages}
              className="px-2 py-1 text-xs rounded border border-gray-200 text-gray-600 hover:bg-gray-50 disabled:opacity-40 disabled:cursor-not-allowed"
            >
              末页
            </button>
          </div>
        </div>
      )}

      {/* Confirmation modal */}
      <ConfirmModal
        open={confirmAction !== null && confirmPr !== null}
        title={confirmAction === 'merge' ? '确认合并 PR' : '确认关闭 PR'}
        message={
          confirmPr
            ? `${confirmAction === 'merge' ? '合并' : '关闭'} PR #${confirmPr.number}：${confirmPr.title}`
            : ''
        }
        confirmLabel={confirmAction === 'merge' ? '合并' : '关闭'}
        confirmClass={
          confirmAction === 'merge'
            ? 'bg-green-600 hover:bg-green-700 text-white'
            : 'bg-red-600 hover:bg-red-700 text-white'
        }
        loading={actionLoading}
        onConfirm={executeAction}
        onCancel={cancelConfirm}
      />

      {/* Toast notifications */}
      <Toast toasts={toasts} onRemove={removeToast} />
    </div>
  );
}

export default PRsPage;
