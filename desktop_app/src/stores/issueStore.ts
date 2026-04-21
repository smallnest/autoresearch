import { create } from 'zustand';

// Detect if running inside Tauri (has native backend) or plain browser (vite dev only)
const isTauri = typeof window !== 'undefined' && '__TAURI_INTERNALS__' in window;

// Lazy import to avoid crash when Tauri is not available
async function tauriInvoke<T>(cmd: string, args?: Record<string, unknown>): Promise<T> {
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
  isLoading: boolean;
  error: string | null;
  loadIssues: (projectPath: string) => Promise<void>;
  setSearchQuery: (query: string) => void;
  toggleLabelFilter: (label: string) => void;
  selectIssue: (number: number | null) => void;
  clearError: () => void;
}

// Browser fallback: mock data for development
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
    labels: [
      { name: 'documentation', color: '0075ca' },
    ],
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

function formatDate(dateString: string): string {
  const date = new Date(dateString);
  return date.toLocaleDateString('zh-CN', {
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  });
}

export const useIssueStore = create<IssueState>((set) => ({
  issues: [],
  processedNumbers: [],
  searchQuery: '',
  selectedLabel: null,
  selectedIssueNumber: null,
  isLoading: false,
  error: null,

  loadIssues: async (projectPath: string) => {
    set({ isLoading: true, error: null });
    try {
      if (isTauri) {
        const result = await tauriInvoke<IssuesResult>('list_issues', {
          project_path: projectPath,
        });
        set({
          issues: result.issues,
          processedNumbers: result.processed_numbers,
        });
      } else {
        // Browser fallback: use mock data
        set({
          issues: mockIssues,
          processedNumbers: mockProcessedNumbers,
        });
      }
    } catch (e) {
      set({ error: String(e) });
    } finally {
      set({ isLoading: false });
    }
  },

  setSearchQuery: (query: string) => {
    set({ searchQuery: query });
  },

  toggleLabelFilter: (label: string) => {
    set((state) => ({
      selectedLabel: state.selectedLabel === label ? null : label,
    }));
  },

  selectIssue: (number: number | null) => {
    set({ selectedIssueNumber: number });
  },

  clearError: () => set({ error: null }),
}));

// Export helper functions
export { formatDate, isTauri };
