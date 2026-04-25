import { create } from 'zustand';
import { normalizeUserFacingError } from './uiError.ts';

const isTauri =
  typeof window !== 'undefined' && '__TAURI_INTERNALS__' in window;

async function tauriInvoke<T>(
  cmd: string,
  args?: Record<string, unknown>
): Promise<T> {
  const { invoke } = await import('@tauri-apps/api/core');
  return invoke<T>(cmd, args);
}

export interface GhPullRequest {
  number: number;
  title: string;
  headRefName: string;
  body: string;
}

export interface PrFileChange {
  path: string;
  additions: number;
  deletions: number;
}

export interface PrDetail {
  files: PrFileChange[];
  additions: number;
  deletions: number;
  changedFiles: number;
}

export interface PrDiff {
  diff: string;
}

interface PrState {
  prs: GhPullRequest[];
  selectedPrNumber: number | null;
  prDetail: PrDetail | null;
  prDiff: PrDiff | null;
  isLoading: boolean;
  detailLoading: boolean;
  diffLoading: boolean;
  detailRequestKey: number;
  error: string | null;
  detailError: string | null;
  loadPrs: (_projectPath: string) => Promise<void>;
  loadPrDetail: (_projectPath: string, _prNumber: number) => Promise<void>;
  loadPrDiff: (_projectPath: string, _prNumber: number) => Promise<void>;
  selectPr: (_number: number | null) => void;
  clearPrDetail: () => void;
  clearError: () => void;
  clearDetailError: () => void;
}

const mockPrs: GhPullRequest[] = [];

export function normalizePrListError(error: unknown): string {
  return normalizeUserFacingError(error, '加载 PR 列表失败，请重试。');
}

export function normalizePrDetailError(error: unknown): string {
  return normalizeUserFacingError(error, '加载 PR 详情失败，请重试。');
}

export const usePrStore = create<PrState>((set, get) => ({
  prs: [],
  selectedPrNumber: null,
  prDetail: null,
  prDiff: null,
  isLoading: false,
  detailLoading: false,
  diffLoading: false,
  detailRequestKey: 0,
  error: null,
  detailError: null,

  loadPrs: async (_projectPath: string) => {
    set({ isLoading: true, error: null });
    try {
      if (isTauri) {
        const result = await tauriInvoke<GhPullRequest[]>('list_prs', {
          projectPath: _projectPath,
        });
        set({ prs: result });
      } else {
        set({
          prs: mockPrs,
          error: '浏览器模式不支持获取 GitHub PR，请通过 tauri dev 运行',
        });
      }

      const { selectedPrNumber, prs } = get();
      if (selectedPrNumber && !prs.some((pr) => pr.number === selectedPrNumber)) {
        set({
          selectedPrNumber: null,
          prDetail: null,
          prDiff: null,
          detailError: null,
          detailLoading: false,
          diffLoading: false,
          detailRequestKey: 0,
        });
      }
    } catch (e) {
      set({ error: normalizePrListError(e) });
    } finally {
      set({ isLoading: false });
    }
  },

  loadPrDetail: async (_projectPath: string, _prNumber: number) => {
    const nextRequestKey = get().detailRequestKey + 1;
    set({
      detailLoading: true,
      detailRequestKey: nextRequestKey,
      detailError: null,
      prDetail: null,
      selectedPrNumber: _prNumber,
    });

    try {
      const detail = isTauri
        ? await tauriInvoke<PrDetail>('get_pr_detail', {
            projectPath: _projectPath,
            prNumber: _prNumber,
          })
        : await new Promise<PrDetail>((_resolve, reject) => {
            window.setTimeout(() => {
              reject(new Error(`未找到 PR #${_prNumber}`));
            }, 250);
          });

      const { selectedPrNumber, detailRequestKey } = get();
      if (
        selectedPrNumber !== _prNumber ||
        detailRequestKey !== nextRequestKey
      ) {
        return;
      }

      set((state) => {
        if (state.selectedPrNumber !== _prNumber) {
          return state;
        }
        return {
          prDetail: detail,
          detailLoading: false,
          detailError: null,
        };
      });
    } catch (e) {
      const { selectedPrNumber, detailRequestKey } = get();
      if (
        selectedPrNumber !== _prNumber ||
        detailRequestKey !== nextRequestKey
      ) {
        return;
      }

      set({
        detailLoading: false,
        detailError: normalizePrDetailError(e),
      });
    }
  },

  loadPrDiff: async (_projectPath: string, _prNumber: number) => {
    set({ diffLoading: true });
    try {
      const diffResult = isTauri
        ? await tauriInvoke<PrDiff>('get_pr_diff', {
            projectPath: _projectPath,
            prNumber: _prNumber,
          })
        : await new Promise<PrDiff>((_resolve, reject) => {
            window.setTimeout(() => {
              reject(new Error(`未找到 PR #${_prNumber} 的 Diff`));
            }, 250);
          });

      const { selectedPrNumber } = get();
      if (selectedPrNumber !== _prNumber) {
        return;
      }

      set({ prDiff: diffResult, diffLoading: false });
    } catch {
      const { selectedPrNumber } = get();
      if (selectedPrNumber !== _prNumber) {
        return;
      }
      set({ prDiff: null, diffLoading: false });
    }
  },

  selectPr: (_number: number | null) => {
    set({ selectedPrNumber: _number });
  },

  clearPrDetail: () => {
    set({
      selectedPrNumber: null,
      prDetail: null,
      prDiff: null,
      detailError: null,
      detailLoading: false,
      diffLoading: false,
      detailRequestKey: 0,
    });
  },

  clearError: () => set({ error: null }),
  clearDetailError: () => set({ detailError: null }),
}));
