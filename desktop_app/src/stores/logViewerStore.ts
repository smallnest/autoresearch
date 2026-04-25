import { create } from 'zustand';
import { isTauri as issueStoreIsTauri } from './issueStore.ts';

export type LogLevel = 'info' | 'warn' | 'error';
export type LogSourceKind = 'live' | 'terminal' | 'summary' | 'iteration' | 'file';

export interface IssueLogSource {
  id: string;
  label: string;
  kind: Exclude<LogSourceKind, 'live'>;
  updated_at: string | null;
  size_bytes: number;
}

export interface IssueLogContent {
  source_id: string;
  text: string;
  updated_at: string | null;
}

export interface LogSourceOption {
  id: string;
  label: string;
  kind: LogSourceKind;
  updatedAt: string | null;
  sizeBytes: number | null;
}

export interface LogEntry {
  lineNumber: number;
  text: string;
  level: LogLevel;
}

type InvokeFn = <T>(cmd: string, args?: Record<string, unknown>) => Promise<T>;

interface LogViewerDeps {
  isTauri: boolean;
  invoke: InvokeFn;
}

interface LoadSourcesOptions {
  preferLive: boolean;
}

interface LogViewerState {
  currentIssueNumber: number | null;
  sourcesRequestKey: number;
  contentRequestKey: number;
  sources: LogSourceOption[];
  selectedSourceId: string;
  searchQuery: string;
  levelFilters: Record<LogLevel, boolean>;
  autoScroll: boolean;
  hasPendingScroll: boolean;
  sourceContents: Record<string, IssueLogContent>;
  isLoadingSources: boolean;
  isLoadingContent: boolean;
  error: string | null;
  loadSources: (
    _projectPath: string,
    _issueNumber: number,
    _options?: Partial<LoadSourcesOptions>
  ) => Promise<void>;
  refreshSelectedSource: (_projectPath: string, _issueNumber: number) => Promise<void>;
  selectSource: (_sourceId: string) => void;
  setSearchQuery: (_query: string) => void;
  toggleLevel: (_level: LogLevel) => void;
  setAutoScroll: (_enabled: boolean) => void;
  markScrollPending: (_pending: boolean) => void;
  clearError: () => void;
  clearIssue: () => void;
}

const DEFAULT_SELECTED_SOURCE_ID = 'live-output';

async function tauriInvoke<T>(
  cmd: string,
  args?: Record<string, unknown>
): Promise<T> {
  const { invoke } = await import('@tauri-apps/api/core');
  return invoke<T>(cmd, args);
}

function normalizeError(error: unknown): string {
  if (error instanceof Error) {
    return error.message;
  }
  return String(error);
}

function createLiveSource(): LogSourceOption {
  return {
    id: DEFAULT_SELECTED_SOURCE_ID,
    label: '当前运行输出',
    kind: 'live',
    updatedAt: null,
    sizeBytes: null,
  };
}

export function classifyLogLevel(line: string): LogLevel {
  const normalized = line.toLowerCase();
  if (
    normalized.includes('error') ||
    normalized.includes('failed') ||
    normalized.includes('failure') ||
    normalized.includes('fatal') ||
    normalized.includes('❌') ||
    normalized.includes('错误') ||
    normalized.includes('失败')
  ) {
    return 'error';
  }

  if (
    normalized.includes('warn') ||
    normalized.includes('warning') ||
    normalized.includes('⚠️') ||
    normalized.includes('警告')
  ) {
    return 'warn';
  }

  return 'info';
}

const MAX_LOG_LINES = 5000;

export function buildLogEntries(text: string): LogEntry[] {
  if (!text) {
    return [];
  }

  const lines = text.split(/\r?\n/);
  const start = Math.max(0, lines.length - MAX_LOG_LINES);
  return lines.slice(start).map((line, index) => ({
    lineNumber: start + index + 1,
    text: line,
    level: classifyLogLevel(line),
  }));
}

export function filterLogEntries(
  entries: LogEntry[],
  searchQuery: string,
  levelFilters: Record<LogLevel, boolean>
): LogEntry[] {
  const normalizedQuery = searchQuery.trim().toLowerCase();
  return entries.filter((entry) => {
    if (!levelFilters[entry.level]) {
      return false;
    }
    if (!normalizedQuery) {
      return true;
    }
    return entry.text.toLowerCase().includes(normalizedQuery);
  });
}

function mapBackendSource(source: IssueLogSource): LogSourceOption {
  return {
    id: source.id,
    label: source.label,
    kind: source.kind,
    updatedAt: source.updated_at,
    sizeBytes: source.size_bytes,
  };
}

function nextSelectedSourceId(
  availableSources: LogSourceOption[],
  currentSelectedSourceId: string,
  preferLive: boolean
): string {
  if (availableSources.some((source) => source.id === currentSelectedSourceId)) {
    return currentSelectedSourceId;
  }

  if (preferLive) {
    return DEFAULT_SELECTED_SOURCE_ID;
  }

  const terminalSource = availableSources.find((source) => source.kind === 'terminal');
  if (terminalSource) {
    return terminalSource.id;
  }

  return availableSources[0]?.id ?? DEFAULT_SELECTED_SOURCE_ID;
}

function createLogViewerDeps(
  overrides: Partial<LogViewerDeps> = {}
): LogViewerDeps {
  return {
    isTauri: issueStoreIsTauri,
    invoke: tauriInvoke,
    ...overrides,
  };
}

export function createLogViewerStore(
  overrides: Partial<LogViewerDeps> = {}
) {
  const deps = createLogViewerDeps(overrides);

  return create<LogViewerState>((set, get) => ({
    currentIssueNumber: null,
    sourcesRequestKey: 0,
    contentRequestKey: 0,
    sources: [createLiveSource()],
    selectedSourceId: DEFAULT_SELECTED_SOURCE_ID,
    searchQuery: '',
    levelFilters: {
      info: true,
      warn: true,
      error: true,
    },
    autoScroll: true,
    hasPendingScroll: false,
    sourceContents: {},
    isLoadingSources: false,
    isLoadingContent: false,
    error: null,

    loadSources: async (
      _projectPath: string,
      _issueNumber: number,
      _options: Partial<LoadSourcesOptions> = {}
    ) => {
      const preferLive = _options.preferLive ?? false;
      const previousState = get();
      const issueChanged = previousState.currentIssueNumber !== _issueNumber;
      const requestKey = previousState.sourcesRequestKey + 1;
      const currentSelectedSourceId = issueChanged
        ? ''
        : previousState.selectedSourceId;

      set((state) => ({
        currentIssueNumber: _issueNumber,
        sourcesRequestKey: requestKey,
        isLoadingSources: true,
        error: null,
        autoScroll: issueChanged ? true : state.autoScroll,
        hasPendingScroll: issueChanged ? false : state.hasPendingScroll,
        selectedSourceId: issueChanged
          ? DEFAULT_SELECTED_SOURCE_ID
          : state.selectedSourceId,
        sourceContents: issueChanged ? {} : state.sourceContents,
        searchQuery: issueChanged ? '' : state.searchQuery,
      }));

      if (!deps.isTauri) {
        set({
          sources: [createLiveSource()],
          selectedSourceId: DEFAULT_SELECTED_SOURCE_ID,
          isLoadingSources: false,
          isLoadingContent: false,
        });
        return;
      }

      try {
        const backendSources = await deps.invoke<IssueLogSource[]>(
          'list_issue_log_sources',
          {
            projectPath: _projectPath,
            issueNumber: _issueNumber,
          }
        );
        const sources = [createLiveSource(), ...backendSources.map(mapBackendSource)];
        const selectedSourceId = nextSelectedSourceId(
          sources,
          currentSelectedSourceId,
          preferLive
        );

        if (
          get().currentIssueNumber !== _issueNumber ||
          get().sourcesRequestKey !== requestKey
        ) {
          return;
        }

        set((state) => {
          const nextSourceContents =
            selectedSourceId === state.selectedSourceId ||
            selectedSourceId === DEFAULT_SELECTED_SOURCE_ID
              ? state.sourceContents
              : Object.fromEntries(
                  Object.entries(state.sourceContents).filter(([sourceId]) =>
                    sources.some((source) => source.id === sourceId)
                  )
                );

          return {
            sources,
            selectedSourceId,
            sourceContents: nextSourceContents,
            isLoadingSources: false,
          };
        });
      } catch (error) {
        if (
          get().currentIssueNumber !== _issueNumber ||
          get().sourcesRequestKey !== requestKey
        ) {
          return;
        }

        set({
          sources: [createLiveSource()],
          selectedSourceId: DEFAULT_SELECTED_SOURCE_ID,
          isLoadingSources: false,
          error: normalizeError(error),
        });
      }
    },

    refreshSelectedSource: async (_projectPath: string, _issueNumber: number) => {
      if (!deps.isTauri) {
        return;
      }

      const { selectedSourceId, currentIssueNumber, contentRequestKey } = get();
      if (selectedSourceId === DEFAULT_SELECTED_SOURCE_ID) {
        return;
      }

      const requestKey = contentRequestKey + 1;

      set({
        currentIssueNumber: currentIssueNumber ?? _issueNumber,
        contentRequestKey: requestKey,
        isLoadingContent: true,
        error: null,
      });

      try {
        const content = await deps.invoke<IssueLogContent>('read_issue_log_content', {
          projectPath: _projectPath,
          issueNumber: _issueNumber,
          sourceId: selectedSourceId,
        });

        if (
          get().currentIssueNumber !== _issueNumber ||
          get().contentRequestKey !== requestKey
        ) {
          return;
        }

        set((state) => ({
          sourceContents: {
            ...state.sourceContents,
            [content.source_id]: content,
          },
          isLoadingContent: false,
        }));
      } catch (error) {
        if (
          get().currentIssueNumber !== _issueNumber ||
          get().contentRequestKey !== requestKey
        ) {
          return;
        }

        set({
          isLoadingContent: false,
          error: normalizeError(error),
        });
      }
    },

    selectSource: (_sourceId: string) => {
      set({
        selectedSourceId: _sourceId,
        error: null,
        hasPendingScroll: false,
      });
    },

    setSearchQuery: (_query: string) => {
      set({ searchQuery: _query });
    },

    toggleLevel: (_level: LogLevel) => {
      set((state) => {
        const nextLevelFilters = {
          ...state.levelFilters,
          [_level]: !state.levelFilters[_level],
        };
        if (Object.values(nextLevelFilters).some(Boolean)) {
          return { levelFilters: nextLevelFilters };
        }
        return state;
      });
    },

    setAutoScroll: (_enabled: boolean) => {
      set({
        autoScroll: _enabled,
        hasPendingScroll: _enabled ? false : get().hasPendingScroll,
      });
    },

    markScrollPending: (_pending: boolean) => {
      set({ hasPendingScroll: _pending });
    },

    clearError: () => set({ error: null }),

    clearIssue: () => {
      set({
        currentIssueNumber: null,
        sourcesRequestKey: 0,
        contentRequestKey: 0,
        sources: [createLiveSource()],
        selectedSourceId: DEFAULT_SELECTED_SOURCE_ID,
        searchQuery: '',
        levelFilters: {
          info: true,
          warn: true,
          error: true,
        },
        autoScroll: true,
        hasPendingScroll: false,
        sourceContents: {},
        isLoadingSources: false,
        isLoadingContent: false,
        error: null,
      });
    },
  }));
}

export const useLogViewerStore = createLogViewerStore();

export { DEFAULT_SELECTED_SOURCE_ID };
