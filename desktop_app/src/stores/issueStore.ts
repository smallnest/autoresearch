import { create } from 'zustand';

const isTauri =
  typeof window !== 'undefined' && '__TAURI_INTERNALS__' in window;

async function tauriInvoke<T>(
  cmd: string,
  args?: Record<string, unknown>
): Promise<T> {
  const { invoke } = await import('@tauri-apps/api/core');
  return invoke<T>(cmd, args);
}

export interface GhLabel {
  name: string;
  color: string;
}

export interface GhIssue {
  number: number;
  title: string;
  labels: GhLabel[];
  createdAt: string;
  state: string;
}

export interface GhCommentAuthor {
  login: string;
}

export interface GhComment {
  id: string;
  author: GhCommentAuthor;
  body: string;
  createdAt: string;
}

export interface IssueDetail {
  body: string;
  comments: GhComment[];
}

export interface IssuesResult {
  issues: GhIssue[];
  processed_numbers: number[];
}

interface IssueState {
  issues: GhIssue[];
  processedNumbers: number[];
  searchQuery: string;
  selectedLabel: string | null;
  selectedIssueNumber: number | null;
  issueDetail: IssueDetail | null;
  isLoading: boolean;
  detailLoading: boolean;
  detailRequestKey: number;
  error: string | null;
  detailError: string | null;
  loadIssues: (_projectPath: string) => Promise<void>;
  loadIssueDetail: (_projectPath: string, _issueNumber: number) => Promise<void>;
  setSearchQuery: (_query: string) => void;
  toggleLabelFilter: (_label: string) => void;
  selectIssue: (_number: number | null) => void;
  clearIssueDetail: () => void;
  clearError: () => void;
  clearDetailError: () => void;
}

const mockIssues: GhIssue[] = [];

const mockProcessedNumbers: number[] = [];

const mockIssueDetails: Record<number, IssueDetail> = {};

function formatDate(dateString: string): string {
  const date = new Date(dateString);
  return date.toLocaleDateString('zh-CN', {
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  });
}

function formatDateTime(dateString: string): string {
  const date = new Date(dateString);
  return date.toLocaleString('zh-CN', {
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
  });
}

export const useIssueStore = create<IssueState>((set, get) => ({
  issues: [],
  processedNumbers: [],
  searchQuery: '',
  selectedLabel: null,
  selectedIssueNumber: null,
  issueDetail: null,
  isLoading: false,
  detailLoading: false,
  detailRequestKey: 0,
  error: null,
  detailError: null,

  loadIssues: async (_projectPath: string) => {
    set({ isLoading: true, error: null });
    try {
      if (isTauri) {
        const result = await tauriInvoke<IssuesResult>('list_issues', {
          projectPath: _projectPath,
        });
        set({
          issues: result.issues,
          processedNumbers: result.processed_numbers,
        });
      } else {
        set({
          issues: mockIssues,
          processedNumbers: mockProcessedNumbers,
          error: '浏览器模式不支持获取 GitHub Issues，请通过 tauri dev 运行',
        });
      }

      const { selectedIssueNumber, issues } = get();
      if (selectedIssueNumber && !issues.some((issue) => issue.number === selectedIssueNumber)) {
        set({
          selectedIssueNumber: null,
          issueDetail: null,
          detailError: null,
          detailLoading: false,
          detailRequestKey: 0,
        });
      }
    } catch (e) {
      set({ error: String(e) });
    } finally {
      set({ isLoading: false });
    }
  },

  loadIssueDetail: async (_projectPath: string, _issueNumber: number) => {
    const nextRequestKey = get().detailRequestKey + 1;
    set({
      detailLoading: true,
      detailRequestKey: nextRequestKey,
      detailError: null,
      issueDetail: null,
      selectedIssueNumber: _issueNumber,
    });

    try {
      const detail = isTauri
        ? await tauriInvoke<IssueDetail>('get_issue_detail', {
            projectPath: _projectPath,
            issueNumber: _issueNumber,
          })
        : await new Promise<IssueDetail>((resolve, reject) => {
            window.setTimeout(() => {
              const mockDetail = mockIssueDetails[_issueNumber];
              if (mockDetail) {
                resolve(mockDetail);
                return;
              }
              reject(new Error(`Issue #${_issueNumber} not found`));
            }, 250);
          });

      const { selectedIssueNumber, detailRequestKey } = get();
      if (
        selectedIssueNumber !== _issueNumber ||
        detailRequestKey !== nextRequestKey
      ) {
        return;
      }

      set((state) => {
        if (state.selectedIssueNumber !== _issueNumber) {
          return state;
        }
        return {
          issueDetail: detail,
          detailLoading: false,
          detailError: null,
        };
      });
    } catch (e) {
      const { selectedIssueNumber, detailRequestKey } = get();
      if (
        selectedIssueNumber !== _issueNumber ||
        detailRequestKey !== nextRequestKey
      ) {
        return;
      }

      set({
        detailLoading: false,
        detailError: String(e),
      });
    }
  },

  setSearchQuery: (_query: string) => {
    set({ searchQuery: _query });
  },

  toggleLabelFilter: (_label: string) => {
    set((state) => ({
      selectedLabel: state.selectedLabel === _label ? null : _label,
    }));
  },

  selectIssue: (_number: number | null) => {
    set({ selectedIssueNumber: _number });
  },

  clearIssueDetail: () => {
    set({
      selectedIssueNumber: null,
      issueDetail: null,
      detailError: null,
      detailLoading: false,
      detailRequestKey: 0,
    });
  },

  clearError: () => set({ error: null }),
  clearDetailError: () => set({ detailError: null }),
}));

export { formatDate, formatDateTime, isTauri };
