import { create } from 'zustand';
import { normalizeUserFacingError } from './uiError.ts';

// ---------------------------------------------------------------------------
// Types – aligned with Rust `HistoryEntry` / `HistoryRunStatus` (snake_case,
// PascalCase enum variants).
// ---------------------------------------------------------------------------

/** Mirrors Rust `HistoryRunStatus` – serde serialises as PascalCase. */
export type RunStatus = 'Success' | 'Fail' | 'Interrupt' | 'InProgress';

/** UI filter values (lowercase) used by StatusFilter dropdown. */
export type StatusFilter = 'all' | 'success' | 'fail' | 'interrupt' | 'in_progress';

/** Sort direction for the history list. */
export type SortOrder = 'asc' | 'desc';

/** Mirrors Rust `HistoryEntry` – all fields snake_case. */
export interface HistoryEntry {
  issue_number: number;
  title: string;
  status: RunStatus;
  final_score: number | null;
  total_iterations: number | null;
  start_time: string | null;
  end_time: string | null;
}

/** Mirrors Rust `IterationSummary`. */
export interface IterationSummary {
  iteration: number;
  agent: string;
  score: number | null;
  review_summary: string | null;
}

/** Mirrors Rust `HistoryDetail`. */
export interface HistoryDetail {
  issue_number: number;
  title: string;
  status: RunStatus;
  final_score: number | null;
  total_iterations: number | null;
  start_time: string | null;
  end_time: string | null;
  iterations: IterationSummary[];
}

/** Mirrors Rust `SubtaskStatus` enum variants. */
export type SubtaskStatus = 'Pending' | 'Passing' | 'Failing';

/** Mirrors Rust `SubtaskStatusEntry`. */
export interface SubtaskStatusEntry {
  id: string;
  title: string;
  status: SubtaskStatus;
}

// ---------------------------------------------------------------------------
// Pure helpers
// ---------------------------------------------------------------------------

const RUN_STATUS_TO_FILTER: Record<RunStatus, StatusFilter> = {
  Success: 'success',
  Fail: 'fail',
  Interrupt: 'interrupt',
  InProgress: 'in_progress',
};

/**
 * Filter and sort a history list. Kept as a pure function so it can be
 * unit-tested without any store dependency.
 */
export function getFilteredAndSortedHistory(
  entries: HistoryEntry[],
  statusFilter: StatusFilter,
  sortOrder: SortOrder,
): HistoryEntry[] {
  const filtered =
    statusFilter === 'all'
      ? entries
      : entries.filter(
          (e) => RUN_STATUS_TO_FILTER[e.status] === statusFilter,
        );

  return [...filtered].sort((a, b) => {
    // Null start_time always sorts to the end regardless of direction
    if (a.start_time == null && b.start_time == null) return 0;
    if (a.start_time == null) return 1;
    if (b.start_time == null) return -1;
    const cmp = a.start_time.localeCompare(b.start_time);
    return sortOrder === 'desc' ? -cmp : cmp;
  });
}

// ---------------------------------------------------------------------------
// Error normalisation
// ---------------------------------------------------------------------------

export function normalizeHistoryError(error: unknown): string {
  return normalizeUserFacingError(error, '加载历史记录失败，请重试。');
}

// ---------------------------------------------------------------------------
// Mock data (browser mode fallback)
// ---------------------------------------------------------------------------

const mockHistory: HistoryEntry[] = [
  {
    issue_number: 34,
    title: '[desktop-app] 配置文件编辑器',
    status: 'Success',
    final_score: 90,
    total_iterations: 8,
    start_time: '2026-04-24T10:00:00Z',
    end_time: '2026-04-24T12:30:00Z',
  },
  {
    issue_number: 33,
    title: '[desktop-app] 评分趋势折线图',
    status: 'Success',
    final_score: 88,
    total_iterations: 6,
    start_time: '2026-04-23T09:00:00Z',
    end_time: '2026-04-23T11:00:00Z',
  },
  {
    issue_number: 30,
    title: '[desktop-app] 日志查看器',
    status: 'Fail',
    final_score: 72,
    total_iterations: 10,
    start_time: '2026-04-22T14:00:00Z',
    end_time: '2026-04-22T18:00:00Z',
  },
  {
    issue_number: 35,
    title: '[desktop-app] 处理历史列表',
    status: 'InProgress',
    final_score: null,
    total_iterations: 15,
    start_time: '2026-04-25T08:00:00Z',
    end_time: null,
  },
  {
    issue_number: 28,
    title: '[desktop-app] 运行配置面板',
    status: 'Interrupt',
    final_score: 60,
    total_iterations: 4,
    start_time: '2026-04-21T13:00:00Z',
    end_time: null,
  },
];

// ---------------------------------------------------------------------------
// Store
// ---------------------------------------------------------------------------

interface HistoryState {
  entries: HistoryEntry[];
  statusFilter: StatusFilter;
  sortOrder: SortOrder;
  isLoading: boolean;
  error: string | null;

  loadHistory: (projectPath: string) => Promise<void>;
  setStatusFilter: (filter: StatusFilter) => void;
  setSortOrder: (order: SortOrder) => void;
  clearError: () => void;
}

interface HistoryStoreDeps {
  isTauri: boolean;
  invoke: <T>(cmd: string, args?: Record<string, unknown>) => Promise<T>;
}

const isTauri =
  typeof window !== 'undefined' && '__TAURI_INTERNALS__' in window;

async function tauriInvoke<T>(
  cmd: string,
  args?: Record<string, unknown>,
): Promise<T> {
  const { invoke } = await import('@tauri-apps/api/core');
  return invoke<T>(cmd, args);
}

function createHistoryStoreDeps(
  overrides: Partial<HistoryStoreDeps> = {},
): HistoryStoreDeps {
  return {
    isTauri,
    invoke: tauriInvoke,
    ...overrides,
  };
}

export function createHistoryStore(overrides: Partial<HistoryStoreDeps> = {}) {
  const deps = createHistoryStoreDeps(overrides);

  return create<HistoryState>((set) => ({
    entries: [],
    statusFilter: 'all',
    sortOrder: 'desc',
    isLoading: false,
    error: null,

    loadHistory: async (projectPath: string) => {
      set({ isLoading: true, error: null });
      try {
        if (deps.isTauri) {
          const data = await deps.invoke<HistoryEntry[]>('list_history', {
            projectPath,
          });
          set({ entries: data });
        } else {
          set({ entries: mockHistory });
        }
      } catch (e) {
        set({ error: normalizeHistoryError(e) });
      } finally {
        set({ isLoading: false });
      }
    },

    setStatusFilter: (filter: StatusFilter) => {
      set({ statusFilter: filter });
    },

    setSortOrder: (order: SortOrder) => {
      set({ sortOrder: order });
    },

    clearError: () => set({ error: null }),
  }));
}

export const useHistoryStore = createHistoryStore();
