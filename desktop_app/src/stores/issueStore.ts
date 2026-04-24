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

const mockIssues: GhIssue[] = [
  {
    number: 1,
    title: 'Fix login authentication bug',
    labels: [
      { name: 'bug', color: 'd73a4a' },
      { name: 'high-priority', color: 'b60205' },
    ],
    createdAt: '2024-01-15T10:30:00Z',
    state: 'open',
  },
  {
    number: 2,
    title: 'Add user profile page',
    labels: [
      { name: 'feature', color: 'a2eeef' },
      { name: 'frontend', color: '7057ff' },
    ],
    createdAt: '2024-01-16T14:20:00Z',
    state: 'open',
  },
  {
    number: 3,
    title: 'Update API documentation',
    labels: [{ name: 'documentation', color: '0075ca' }],
    createdAt: '2024-01-17T09:00:00Z',
    state: 'closed',
  },
  {
    number: 4,
    title: 'Optimize database queries',
    labels: [
      { name: 'performance', color: 'ff7619' },
      { name: 'backend', color: '0366d6' },
    ],
    createdAt: '2024-01-18T16:45:00Z',
    state: 'open',
  },
  {
    number: 5,
    title: 'Implement dark mode toggle',
    labels: [
      { name: 'feature', color: 'a2eeef' },
      { name: 'ui', color: '6f42c1' },
    ],
    createdAt: '2024-01-19T11:10:00Z',
    state: 'open',
  },
];

const mockProcessedNumbers: number[] = [1, 3];

const mockIssueDetails: Record<number, IssueDetail> = {
  1: {
    body: [
      '# Login flow regression',
      '',
      'Users cannot sign in after the last auth refactor.',
      '',
      '## Steps',
      '',
      '1. Open `/login`',
      '2. Submit valid credentials',
      '3. Observe `401` response',
      '',
      '```ts',
      "await api.post('/login', credentials);",
      '```',
    ].join('\n'),
    comments: [
      {
        id: 'mock-comment-1',
        author: { login: 'alice' },
        body: 'I can reproduce this on the latest main branch.',
        createdAt: '2024-01-15T12:30:00Z',
      },
      {
        id: 'mock-comment-2',
        author: { login: 'bob' },
        body: 'Looks related to [the session middleware](https://example.com).',
        createdAt: '2024-01-15T13:45:00Z',
      },
    ],
  },
  2: {
    body: [
      'Build the new profile page with:',
      '',
      '- avatar',
      '- activity summary',
      '- editable bio',
    ].join('\n'),
    comments: [],
  },
  3: {
    body: '',
    comments: [
      {
        id: 'mock-comment-3',
        author: { login: 'docs-bot' },
        body: 'Documentation has been updated in a follow-up PR.',
        createdAt: '2024-01-17T10:00:00Z',
      },
    ],
  },
  4: {
    body: 'Investigate slow queries in the reporting pipeline.',
    comments: [],
  },
  5: {
    body: 'Add a theme switch in settings and persist the preference.',
    comments: [
      {
        id: 'mock-comment-4',
        author: { login: 'designer' },
        body: '> Keep the toggle visible in both desktop and mobile layouts.',
        createdAt: '2024-01-19T15:00:00Z',
      },
    ],
  },
};

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
          project_path: _projectPath,
        });
        set({
          issues: result.issues,
          processedNumbers: result.processed_numbers,
        });
      } else {
        set({
          issues: mockIssues,
          processedNumbers: mockProcessedNumbers,
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
            project_path: _projectPath,
            issue_number: _issueNumber,
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
