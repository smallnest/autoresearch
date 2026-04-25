import { create } from 'zustand';
import { normalizeUserFacingError } from './uiError.ts';
import type {
  HistoryDetail,
  SubtaskStatusEntry,
} from './historyStore.ts';

// ---------------------------------------------------------------------------
// Error normalisation
// ---------------------------------------------------------------------------

export function normalizeDetailError(error: unknown): string {
  return normalizeUserFacingError(error, '加载历史详情失败，请重试。');
}

// ---------------------------------------------------------------------------
// Mock data (browser mode fallback)
// ---------------------------------------------------------------------------

const mockDetail: HistoryDetail = {
  issue_number: 34,
  title: '[desktop-app] 配置文件编辑器',
  status: 'Success',
  final_score: 90,
  total_iterations: 8,
  start_time: '2026-04-24T10:00:00Z',
  end_time: '2026-04-24T12:30:00Z',
  iterations: [
    {
      iteration: 1,
      agent: 'claude',
      score: 60,
      review_summary: '初始实现完成，缺少错误处理和测试覆盖。',
    },
    {
      iteration: 2,
      agent: 'codex',
      score: 78,
      review_summary: '错误处理已改进，测试覆盖率不足。',
    },
    {
      iteration: 3,
      agent: 'claude',
      score: 90,
      review_summary: '实现完整，测试通过，代码质量良好。',
    },
  ],
};

const mockSubtasks: SubtaskStatusEntry[] = [
  { id: 'T-001', title: '配置文件读取接口', status: 'Passing' },
  { id: 'T-002', title: '编辑器 UI 组件', status: 'Passing' },
  { id: 'T-003', title: '保存与重置功能', status: 'Passing' },
];

const mockIterationLogs: Record<number, string> = {
  1: `## 迭代 1 - 初始实现\n\nAgent: claude\n评分: 60/100\n\n### 审核报告\n\n初始实现完成基本功能，但存在以下问题：\n- 缺少错误处理\n- 测试覆盖率不足\n- 代码风格需要改进`,
  2: `## 迭代 2 - 错误处理改进\n\nAgent: codex\n评分: 78/100\n\n### 审核报告\n\n错误处理已改进，主要问题：\n- 测试覆盖率仍需提高\n- 部分边界条件未处理`,
  3: `## 迭代 3 - 最终修复\n\nAgent: claude\n评分: 90/100\n\n### 审核报告\n\n实现完整，所有验收标准已满足。`,
};

// ---------------------------------------------------------------------------
// Store
// ---------------------------------------------------------------------------

interface HistoryDetailState {
  detail: HistoryDetail | null;
  subtasks: SubtaskStatusEntry[];
  iterationLogs: Record<number, string>;
  selectedIteration: number;
  isLoadingDetail: boolean;
  isLoadingLog: boolean;
  isExporting: boolean;
  exportError: string | null;
  error: string | null;

  loadDetail: (projectPath: string, issueNumber: number) => Promise<void>;
  loadIterationLog: (
    projectPath: string,
    issueNumber: number,
    iteration: number,
  ) => Promise<void>;
  exportLog: (projectPath: string, issueNumber: number) => Promise<boolean>;
  selectIteration: (iteration: number) => void;
  clearDetail: () => void;
  clearError: () => void;
}

interface HistoryDetailStoreDeps {
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

function createHistoryDetailStoreDeps(
  overrides: Partial<HistoryDetailStoreDeps> = {},
): HistoryDetailStoreDeps {
  return {
    isTauri,
    invoke: tauriInvoke,
    ...overrides,
  };
}

export function createHistoryDetailStore(
  overrides: Partial<HistoryDetailStoreDeps> = {},
) {
  const deps = createHistoryDetailStoreDeps(overrides);

  return create<HistoryDetailState>((set, get) => ({
    detail: null,
    subtasks: [],
    iterationLogs: {},
    selectedIteration: 1,
    isLoadingDetail: false,
    isLoadingLog: false,
    isExporting: false,
    exportError: null,
    error: null,

    loadDetail: async (projectPath: string, issueNumber: number) => {
      set({ isLoadingDetail: true, error: null });
      try {
        if (deps.isTauri) {
          const [detail, subtasks] = await Promise.all([
            deps.invoke<HistoryDetail>('get_history_detail', {
              projectPath,
              issueNumber,
            }),
            deps.invoke<SubtaskStatusEntry[]>('get_subtask_status', {
              projectPath,
              issueNumber,
            }),
          ]);

          const firstIteration =
            detail.iterations.length > 0 ? detail.iterations[0].iteration : 1;

          set({
            detail,
            subtasks,
            selectedIteration: firstIteration,
            iterationLogs: {},
          });

          // Auto-load the first iteration log
          await get().loadIterationLog(
            projectPath,
            issueNumber,
            firstIteration,
          );
        } else {
          set({
            detail: { ...mockDetail, issue_number: issueNumber },
            subtasks: mockSubtasks,
            selectedIteration: 1,
            iterationLogs: { 1: mockIterationLogs[1] },
          });
        }
      } catch (e) {
        set({ error: normalizeDetailError(e) });
      } finally {
        set({ isLoadingDetail: false });
      }
    },

    loadIterationLog: async (
      projectPath: string,
      issueNumber: number,
      iteration: number,
    ) => {
      // Skip if already loaded
      if (get().iterationLogs[iteration]) {
        set({ selectedIteration: iteration });
        return;
      }

      set({ isLoadingLog: true, selectedIteration: iteration });
      try {
        if (deps.isTauri) {
          const log = await deps.invoke<string>('get_iteration_log', {
            projectPath,
            issueNumber,
            iteration,
          });
          set((state) => ({
            iterationLogs: { ...state.iterationLogs, [iteration]: log },
          }));
        } else {
          const log =
            mockIterationLogs[iteration] ?? `迭代 ${iteration} 暂无日志。`;
          set((state) => ({
            iterationLogs: { ...state.iterationLogs, [iteration]: log },
          }));
        }
      } catch (e) {
        set({ error: normalizeDetailError(e) });
      } finally {
        set({ isLoadingLog: false });
      }
    },

    selectIteration: (iteration: number) => {
      set({ selectedIteration: iteration });
    },

    exportLog: async (projectPath: string, issueNumber: number) => {
      set({ isExporting: true, exportError: null });
      try {
        if (deps.isTauri) {
          await deps.invoke('export_history_log', {
            projectPath,
            issueNumber,
          });
          return true;
        } else {
          // Browser mode: export is not supported
          set({ exportError: '浏览器模式不支持导出日志。' });
          return false;
        }
      } catch (e) {
        set({ exportError: normalizeDetailError(e) });
        return false;
      } finally {
        set({ isExporting: false });
      }
    },

    clearDetail: () => {
      set({
        detail: null,
        subtasks: [],
        iterationLogs: {},
        selectedIteration: 1,
        isLoadingDetail: false,
        isLoadingLog: false,
        isExporting: false,
        exportError: null,
        error: null,
      });
    },

    clearError: () => set({ error: null }),
  }));
}

export const useHistoryDetailStore = createHistoryDetailStore();
