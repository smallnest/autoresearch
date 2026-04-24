import { useEffect, useMemo, useState } from 'react';
import { useProjectStore } from '../stores/projectStore';
import IssueDetailPanel from '../components/IssueDetailPanel';
import {
  useIssueStore,
  GhIssue,
  GhLabel,
  formatDate,
} from '../stores/issueStore';

// Search Icon component
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

// Issue Icon component
function IssueIcon({ className }: { className?: string }): JSX.Element {
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
        d="M12 8v4m0 4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"
      />
    </svg>
  );
}

// Processed Icon component
function ProcessedIcon({ className }: { className?: string }): JSX.Element {
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
        d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z"
      />
    </svg>
  );
}

// Clear Icon component
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

// Label badge component
function LabelBadge({
  label,
  isSelected,
  onClick,
}: {
  label: GhLabel;
  isSelected: boolean;
  onClick: () => void;
}): JSX.Element {
  // Convert hex color to readable text color (white or black)
  const getTextColor = (hexColor: string): string => {
    const r = parseInt(hexColor.slice(0, 2), 16);
    const g = parseInt(hexColor.slice(2, 4), 16);
    const b = parseInt(hexColor.slice(4, 6), 16);
    const brightness = (r * 299 + g * 587 + b * 114) / 1000;
    return brightness > 128 ? '#1a1a1a' : '#ffffff';
  };

  const textColor = getTextColor(label.color);

  return (
    <button
      onClick={onClick}
      className={`inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium transition-all ${
        isSelected
          ? 'ring-2 ring-offset-1 ring-offset-white ring-blue-500 scale-105'
          : 'hover:opacity-80'
      }`}
      style={{
        backgroundColor: `#${label.color}`,
        color: textColor,
      }}
    >
      {label.name}
    </button>
  );
}

// Issue list item component
function IssueListItem({
  issue,
  isProcessed,
  isSelected,
  onClick,
}: {
  issue: GhIssue;
  isProcessed: boolean;
  isSelected: boolean;
  onClick: () => void;
}): JSX.Element {
  return (
    <div
      onClick={onClick}
      className={`p-4 rounded-lg border cursor-pointer transition-all ${
        isSelected
          ? 'bg-blue-50 border-blue-300 shadow-sm'
          : 'bg-white border-gray-200 hover:border-gray-300 hover:bg-gray-50'
      }`}
    >
      <div className="flex items-start gap-3">
        {/* Issue icon and number */}
        <div className="flex-shrink-0 mt-0.5">
          <div
            className={`w-6 h-6 rounded-full flex items-center justify-center ${
              issue.state === 'OPEN'
                ? 'bg-green-100 text-green-600'
                : 'bg-purple-100 text-purple-600'
            }`}
          >
            {issue.state === 'OPEN' ? (
              <IssueIcon className="w-3.5 h-3.5" />
            ) : (
              <CheckIcon className="w-3.5 h-3.5" />
            )}
          </div>
        </div>

        {/* Issue content */}
        <div className="flex-1 min-w-0">
          <div className="flex items-center gap-2 mb-1">
            <span className="text-xs text-gray-500 font-mono">
              #{issue.number}
            </span>
            {issue.state !== 'OPEN' && (
              <span className="inline-flex items-center px-1.5 py-0.5 rounded text-xs font-medium bg-purple-50 text-purple-700 border border-purple-200">
                closed
              </span>
            )}
            {isProcessed && (
              <span className="inline-flex items-center px-1.5 py-0.5 rounded text-xs font-medium bg-green-50 text-green-700 border border-green-200">
                <ProcessedIcon className="w-3 h-3 mr-1" />
                已处理
              </span>
            )}
          </div>

          <h3 className="text-sm font-medium text-gray-800 mb-2 truncate">
            {issue.title}
          </h3>

          {/* Labels */}
          {issue.labels.length > 0 && (
            <div className="flex flex-wrap gap-1.5 mb-2">
              {issue.labels.map((label) => (
                <span
                  key={label.name}
                  className="inline-flex items-center px-1.5 py-0.5 rounded text-xs font-medium"
                  style={{
                    backgroundColor: `#${label.color}33`,
                    color: `#${label.color}`,
                    border: `1px solid #${label.color}66`,
                  }}
                >
                  {label.name}
                </span>
              ))}
            </div>
          )}

          {/* Created date */}
          <p className="text-xs text-gray-500">
            创建于 {formatDate(issue.createdAt)}
          </p>
        </div>

        {/* Selection indicator */}
        {isSelected && (
          <div className="flex-shrink-0 self-center">
            <CheckIcon className="w-5 h-5 text-blue-400" />
          </div>
        )}
      </div>
    </div>
  );
}

// Empty state component
function EmptyState({ message }: { message: string }): JSX.Element {
  return (
    <div className="flex flex-col items-center justify-center py-12 text-gray-500">
      <IssueIcon className="w-12 h-12 mb-3 opacity-50" />
      <p className="text-sm">{message}</p>
    </div>
  );
}

// Main Issues Page Component
function IssuesPage(): JSX.Element {
  const { projectPath } = useProjectStore();
  const {
    issues,
    processedNumbers,
    searchQuery,
    selectedLabel,
    selectedIssueNumber,
    isLoading,
    detailLoading,
    error,
    detailError,
    issueDetail,
    loadIssues,
    loadIssueDetail,
    setSearchQuery,
    toggleLabelFilter,
    selectIssue,
    clearIssueDetail,
    clearError,
    clearDetailError,
  } = useIssueStore();

  // Load issues on mount and when project changes
  useEffect(() => {
    if (projectPath) {
      loadIssues(projectPath);
    }
  }, [projectPath, loadIssues]);

  useEffect(() => {
    if (projectPath && selectedIssueNumber !== null) {
      loadIssueDetail(projectPath, selectedIssueNumber);
    }
  }, [projectPath, selectedIssueNumber, loadIssueDetail]);

  // Get all unique labels from issues
  const allLabels = useMemo(() => {
    const labelMap = new Map<string, GhLabel>();
    issues.forEach((issue) => {
      issue.labels.forEach((label) => {
        if (!labelMap.has(label.name)) {
          labelMap.set(label.name, label);
        }
      });
    });
    return Array.from(labelMap.values()).sort((a, b) =>
      a.name.localeCompare(b.name)
    );
  }, [issues]);

  // Filter issues based on search query and selected label
  const filteredIssues = useMemo(() => {
    return issues.filter((issue) => {
      // Search filter (case-insensitive)
      const matchesSearch =
        !searchQuery ||
        issue.title.toLowerCase().includes(searchQuery.toLowerCase()) ||
        issue.number.toString().includes(searchQuery);

      // Label filter
      const matchesLabel =
        !selectedLabel ||
        issue.labels.some((label) => label.name === selectedLabel);

      return matchesSearch && matchesLabel;
    });
  }, [issues, searchQuery, selectedLabel]);

  // Pagination
  const PAGE_SIZE = 10;
  const [currentPage, setCurrentPage] = useState(1);

  // Reset to page 1 when filters change
  useEffect(() => {
    setCurrentPage(1);
  }, [searchQuery, selectedLabel]);

  const totalPages = Math.max(1, Math.ceil(filteredIssues.length / PAGE_SIZE));
  const pagedIssues = useMemo(() => {
    const start = (currentPage - 1) * PAGE_SIZE;
    return filteredIssues.slice(start, start + PAGE_SIZE);
  }, [filteredIssues, currentPage]);

  // Check if an issue is processed
  const isProcessed = (issueNumber: number): boolean => {
    return processedNumbers.includes(issueNumber);
  };

  const selectedIssue = useMemo(
    () => issues.find((issue) => issue.number === selectedIssueNumber) ?? null,
    [issues, selectedIssueNumber]
  );

  // Handle search input change
  const handleSearchChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    setSearchQuery(e.target.value);
  };

  // Clear search
  const handleClearSearch = () => {
    setSearchQuery('');
  };

  // Handle issue click
  const handleIssueClick = (issueNumber: number) => {
    if (selectedIssueNumber === issueNumber) {
      clearIssueDetail();
      return;
    }

    selectIssue(issueNumber);
  };

  if (!projectPath) {
    return (
      <div className="p-6">
        <div className="flex flex-col items-center justify-center h-full min-h-[400px]">
          <IssueIcon className="w-16 h-16 mb-4 text-gray-300" />
          <h2 className="text-xl font-bold text-gray-700 mb-2">
            请先选择项目
          </h2>
          <p className="text-gray-500 text-center max-w-md">
            在 Dashboard 页面选择一个项目目录后，即可查看和管理 GitHub Issues
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
          <h1 className="text-2xl font-bold text-gray-900 mb-1">Issues</h1>
          <p className="text-sm text-gray-500">
            管理和追踪 GitHub OPEN Issues ({filteredIssues.length} / {issues.length})
          </p>
        </div>

        {/* Refresh button */}
        <button
          onClick={() => projectPath && loadIssues(projectPath)}
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
              className="ml-2 text-red-400 hover:text-red-600"
            >
              <ClearIcon className="w-4 h-4" />
            </button>
          </div>
        </div>
      )}

      <div className="grid gap-6 xl:grid-cols-[minmax(0,1fr)_24rem]">
        <section className="min-w-0">
          {/* Search bar */}
          <div className="mb-4">
            <div className="relative">
              <SearchIcon className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-gray-500" />
              <input
                type="text"
                placeholder="搜索 Issue 标题或编号..."
                value={searchQuery}
                onChange={handleSearchChange}
                className="w-full pl-10 pr-10 py-2.5 bg-white border border-gray-200 rounded-lg text-sm text-gray-900 placeholder-gray-400 focus:outline-none focus:border-blue-500 focus:ring-1 focus:ring-blue-500 transition-colors"
              />
              {searchQuery && (
                <button
                  onClick={handleClearSearch}
                  className="absolute right-3 top-1/2 -translate-y-1/2 text-gray-500 hover:text-gray-300"
                >
                  <ClearIcon className="w-4 h-4" />
                </button>
              )}
            </div>
          </div>

          {/* Label filters */}
          {allLabels.length > 0 && (
            <div className="mb-4">
              <p className="text-xs text-gray-500 mb-2">标签过滤:</p>
              <div className="flex flex-wrap gap-2">
                {allLabels.map((label) => (
                  <LabelBadge
                    key={label.name}
                    label={label}
                    isSelected={selectedLabel === label.name}
                    onClick={() => toggleLabelFilter(label.name)}
                  />
                ))}
              </div>
            </div>
          )}

          {/* Issues list */}
          <div className="space-y-3">
            {isLoading && issues.length === 0 ? (
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
                <p className="text-sm text-gray-500">加载 Issues 中...</p>
              </div>
            ) : pagedIssues.length > 0 ? (
              pagedIssues.map((issue) => (
                <IssueListItem
                  key={issue.number}
                  issue={issue}
                  isProcessed={isProcessed(issue.number)}
                  isSelected={selectedIssueNumber === issue.number}
                  onClick={() => handleIssueClick(issue.number)}
                />
              ))
            ) : (
              <EmptyState
                message={
                  searchQuery || selectedLabel
                    ? '没有匹配的 Issues'
                    : '暂无 Issues'
                }
              />
            )}
          </div>

          {/* Pagination */}
          {totalPages > 1 && (
            <div className="mt-4 flex items-center justify-between">
              <p className="text-xs text-gray-500">
                第 {(currentPage - 1) * PAGE_SIZE + 1}-{Math.min(currentPage * PAGE_SIZE, filteredIssues.length)} 条，共 {filteredIssues.length} 条
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
        </section>

        <section
          className={`min-w-0 ${selectedIssue ? 'block' : 'hidden xl:block'}`}
        >
          <IssueDetailPanel
            issue={selectedIssue}
            detail={issueDetail}
            isLoading={detailLoading}
            error={detailError}
            onClose={clearIssueDetail}
            onRetry={() => {
              clearDetailError();
              if (projectPath && selectedIssueNumber !== null) {
                loadIssueDetail(projectPath, selectedIssueNumber);
              }
            }}
          />
        </section>
      </div>
    </div>
  );
}

export default IssuesPage;
