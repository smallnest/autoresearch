import { useEffect, useMemo, useRef, type JSX } from 'react';
import Dropdown from './Dropdown';
import { useRunStore } from '../stores/runStore';
import {
  buildLogEntries,
  DEFAULT_SELECTED_SOURCE_ID,
  filterLogEntries,
  type LogLevel,
  useLogViewerStore,
} from '../stores/logViewerStore';

interface LogViewerProps {
  issueNumber: number;
  projectPath: string | null;
}

function SearchIcon({ className }: { className?: string }): JSX.Element {
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
        d="M21 21l-4.35-4.35m1.85-5.15a7 7 0 11-14 0a7 7 0 0114 0z"
      />
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

function PauseIcon({ className }: { className?: string }): JSX.Element {
  return (
    <svg
      className={className}
      fill="currentColor"
      viewBox="0 0 24 24"
      aria-hidden="true"
    >
      <path d="M7 5h3v14H7zm7 0h3v14h-3z" />
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

function LevelBadge({
  level,
  isActive,
  onClick,
}: {
  level: LogLevel;
  isActive: boolean;
  onClick: () => void;
}): JSX.Element {
  const styleMap: Record<LogLevel, string> = {
    info: isActive
      ? 'border-slate-700 bg-slate-700 text-white'
      : 'border-slate-600 text-slate-300',
    warn: isActive
      ? 'border-amber-400 bg-amber-400 text-slate-950'
      : 'border-amber-500/60 text-amber-300',
    error: isActive
      ? 'border-rose-500 bg-rose-500 text-white'
      : 'border-rose-500/60 text-rose-300',
  };
  const labelMap: Record<LogLevel, string> = {
    info: '信息',
    warn: '警告',
    error: '错误',
  };

  return (
    <button
      type="button"
      onClick={onClick}
      className={`rounded-md border px-2.5 py-1 text-xs font-medium transition-colors ${styleMap[level]}`}
    >
      {labelMap[level]}
    </button>
  );
}

function sourceDescription(kind: string): string {
  switch (kind) {
    case 'live':
      return '来自当前 run.sh 进程的 stdout/stderr';
    case 'terminal':
      return '`.autoresearch/workflows/issue-N/terminal.log`';
    case 'summary':
      return '工作流摘要与评分记录';
    case 'iteration':
      return '单轮 agent 日志';
    default:
      return '工作流文件';
  }
}

function formatUpdatedAt(value: string | null): string {
  if (!value) {
    return '未记录';
  }

  const timestamp = Number(value) * 1000;
  if (Number.isNaN(timestamp)) {
    return value;
  }

  return new Date(timestamp).toLocaleString('zh-CN', {
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
  });
}

function lineClassName(level: LogLevel): string {
  switch (level) {
    case 'warn':
      return 'text-amber-200';
    case 'error':
      return 'text-rose-200';
    case 'info':
    default:
      return 'text-slate-100';
  }
}

function escapeRegExp(s: string): string {
  return s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

function HighlightedText({ text, query }: { text: string; query: string }): JSX.Element {
  if (!query.trim()) return <>{text || ' '}</>;
  const parts = text.split(new RegExp(`(${escapeRegExp(query)})`, 'gi'));
  return (
    <>
      {parts.map((part, i) =>
        part.toLowerCase() === query.toLowerCase() ? (
          <mark key={i} className="bg-yellow-400/40 text-inherit">{part}</mark>
        ) : (
          part
        )
      )}
    </>
  );
}

function isNearBottom(element: HTMLDivElement): boolean {
  return element.scrollHeight - element.scrollTop - element.clientHeight < 24;
}

export default function LogViewer({
  issueNumber,
  projectPath,
}: LogViewerProps): JSX.Element {
  const outputContainerRef = useRef<HTMLDivElement | null>(null);
  const sourceRefreshTimerRef = useRef<number | null>(null);
  const refreshTimerRef = useRef<number | null>(null);
  const {
    status: runStatus,
    activeIssueNumber,
    outputLines,
  } = useRunStore();
  const {
    sources,
    selectedSourceId,
    searchQuery,
    levelFilters,
    autoScroll,
    hasPendingScroll,
    sourceContents,
    isLoadingSources,
    isLoadingContent,
    error,
    loadSources,
    refreshSelectedSource,
    selectSource,
    setSearchQuery,
    toggleLevel,
    setAutoScroll,
    markScrollPending,
    clearError,
    clearIssue,
  } = useLogViewerStore();

  const isCurrentIssueRunning =
    activeIssueNumber === issueNumber &&
    (runStatus === 'running' || runStatus === 'stopping');
  const selectedSource =
    sources.find((source) => source.id === selectedSourceId) ?? sources[0];

  const rawText =
    selectedSourceId === DEFAULT_SELECTED_SOURCE_ID
      ? outputLines.join('\n')
      : (sourceContents[selectedSourceId]?.text ?? '');
  const totalEntries = useMemo(
    () => buildLogEntries(rawText),
    [rawText]
  );
  const visibleEntries = useMemo(
    () => filterLogEntries(totalEntries, searchQuery, levelFilters),
    [totalEntries, searchQuery, levelFilters]
  );

  useEffect(() => {
    if (!projectPath) {
      if (sourceRefreshTimerRef.current !== null) {
        window.clearInterval(sourceRefreshTimerRef.current);
        sourceRefreshTimerRef.current = null;
      }
      clearIssue();
      return;
    }

    void loadSources(projectPath, issueNumber, {
      preferLive: isCurrentIssueRunning,
    });

    if (sourceRefreshTimerRef.current !== null) {
      window.clearInterval(sourceRefreshTimerRef.current);
    }

    sourceRefreshTimerRef.current = window.setInterval(() => {
      void loadSources(projectPath, issueNumber, {
        preferLive: isCurrentIssueRunning,
      });
    }, 1500);

    return () => {
      if (sourceRefreshTimerRef.current !== null) {
        window.clearInterval(sourceRefreshTimerRef.current);
        sourceRefreshTimerRef.current = null;
      }
    };
  }, [clearIssue, isCurrentIssueRunning, issueNumber, loadSources, projectPath]);

  useEffect(() => {
    if (!projectPath || selectedSourceId === DEFAULT_SELECTED_SOURCE_ID) {
      return;
    }

    void refreshSelectedSource(projectPath, issueNumber);

    if (refreshTimerRef.current !== null) {
      window.clearInterval(refreshTimerRef.current);
    }

    refreshTimerRef.current = window.setInterval(() => {
      void refreshSelectedSource(projectPath, issueNumber);
    }, 1500);

    return () => {
      if (refreshTimerRef.current !== null) {
        window.clearInterval(refreshTimerRef.current);
        refreshTimerRef.current = null;
      }
    };
  }, [issueNumber, projectPath, refreshSelectedSource, selectedSourceId]);

  useEffect(() => {
    const element = outputContainerRef.current;
    if (!element) {
      return;
    }

    if (autoScroll) {
      element.scrollTop = element.scrollHeight;
      markScrollPending(false);
      return;
    }

    if (!isNearBottom(element)) {
      markScrollPending(true);
    }
  }, [autoScroll, markScrollPending, selectedSourceId, visibleEntries]);

  const headerMeta = selectedSource
    ? `${sourceDescription(selectedSource.kind)} · 更新于 ${formatUpdatedAt(selectedSource.updatedAt)}`
    : '选择一个日志源开始查看';

  return (
    <div className="mt-4 overflow-hidden rounded-2xl border border-gray-200 bg-gray-950 text-slate-100">
      <div className="border-b border-gray-800 px-4 py-3">
        <div className="flex flex-col gap-3 lg:flex-row lg:items-center lg:justify-between">
          <div className="flex min-w-0 items-center gap-2 text-sm font-medium text-gray-200">
            <TerminalIcon className="h-4 w-4" />
            日志查看器
          </div>
          <div className="flex flex-wrap items-center gap-2">
            <Dropdown
              value={selectedSourceId ?? ''}
              options={sources.map((s) => ({ value: s.id, label: s.label }))}
              onChange={(v) => {
                clearError();
                selectSource(v);
              }}
              ariaLabel="选择日志源"
              variant="dark"
            />
            <button
              type="button"
              onClick={() => {
                const nextAutoScroll = !autoScroll;
                setAutoScroll(nextAutoScroll);
                if (nextAutoScroll && outputContainerRef.current) {
                  outputContainerRef.current.scrollTop =
                    outputContainerRef.current.scrollHeight;
                }
              }}
              className={`inline-flex items-center gap-1 rounded-md border px-2.5 py-1 text-xs font-medium transition-colors ${
                autoScroll
                  ? 'border-emerald-500/60 bg-emerald-500/10 text-emerald-200'
                  : 'border-gray-700 text-gray-300 hover:bg-gray-900'
              }`}
            >
              {autoScroll ? (
                <PauseIcon className="h-3.5 w-3.5" />
              ) : (
                <PlayIcon className="h-3.5 w-3.5" />
              )}
              {autoScroll ? '自动滚动中' : '已暂停滚动'}
            </button>
          </div>
        </div>

        <p className="mt-2 text-xs text-gray-400">{headerMeta}</p>

        <div className="mt-3 flex flex-col gap-3 lg:flex-row lg:items-center lg:justify-between">
          <div className="relative max-w-md flex-1">
            <SearchIcon className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-gray-500" />
            <input
              type="text"
              value={searchQuery}
              onChange={(event) => setSearchQuery(event.target.value)}
              placeholder="搜索日志内容..."
              className="w-full rounded-md border border-gray-700 bg-gray-900 py-2 pl-9 pr-3 text-sm text-gray-100 placeholder:text-gray-500 focus:border-blue-400 focus:outline-none"
            />
          </div>

          <div className="flex flex-wrap items-center gap-2">
            <LevelBadge
              level="info"
              isActive={levelFilters.info}
              onClick={() => toggleLevel('info')}
            />
            <LevelBadge
              level="warn"
              isActive={levelFilters.warn}
              onClick={() => toggleLevel('warn')}
            />
            <LevelBadge
              level="error"
              isActive={levelFilters.error}
              onClick={() => toggleLevel('error')}
            />
          </div>
        </div>

        {error && (
          <div className="mt-3 rounded-lg border border-rose-500/40 bg-rose-500/10 px-3 py-2 text-xs text-rose-200">
            {error}
          </div>
        )}
      </div>

      <div
        ref={outputContainerRef}
        onScroll={(event) => {
          const element = event.currentTarget;
          if (isNearBottom(element)) {
            markScrollPending(false);
            return;
          }

          if (autoScroll) {
            setAutoScroll(false);
          }
        }}
        className="relative max-h-[28rem] overflow-y-auto px-4 py-3"
      >
        {(isLoadingSources || isLoadingContent) && (
          <div className="mb-3 text-xs text-blue-200">日志加载中...</div>
        )}

        {visibleEntries.length > 0 ? (
          <div className="space-y-1 font-mono text-xs leading-6">
            {visibleEntries.map((entry) => (
              <div
                key={entry.lineNumber}
                className="grid grid-cols-[3rem_minmax(0,1fr)] gap-3"
              >
                <span className="select-none text-right text-gray-500">
                  {entry.lineNumber}
                </span>
                <span className={`whitespace-pre-wrap break-words ${lineClassName(entry.level)}`}>
                  <HighlightedText text={entry.text || ' '} query={searchQuery} />
                </span>
              </div>
            ))}
          </div>
        ) : (
          <div className="rounded-xl border border-dashed border-gray-800 bg-gray-950/80 px-4 py-6 text-sm text-gray-400">
            {rawText
              ? '当前过滤条件下没有匹配的日志。'
              : selectedSourceId === DEFAULT_SELECTED_SOURCE_ID
                ? isCurrentIssueRunning
                  ? '等待新的运行输出...'
                  : '当前没有运行中的实时输出，可切换到历史日志文件。'
                : '该日志文件当前为空。'}
          </div>
        )}
      </div>

      <div className="flex flex-wrap items-center justify-between gap-3 border-t border-gray-800 px-4 py-3 text-xs text-gray-400">
        <span>
          显示 {visibleEntries.length} / {totalEntries.length} 行
        </span>
        {hasPendingScroll && (
          <button
            type="button"
            onClick={() => {
              setAutoScroll(true);
              if (outputContainerRef.current) {
                outputContainerRef.current.scrollTop =
                  outputContainerRef.current.scrollHeight;
              }
            }}
            className="rounded-md border border-blue-400/40 px-2.5 py-1 text-blue-200 transition-colors hover:bg-blue-500/10"
          >
            跳到最新
          </button>
        )}
      </div>
    </div>
  );
}
