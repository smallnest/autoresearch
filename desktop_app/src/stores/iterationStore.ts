import { create } from 'zustand';

const isTauri =
  typeof window !== 'undefined' && '__TAURI_INTERNALS__' in window;

export type Phase = 'Planning' | 'Implementation' | 'Review' | 'BuildLintTest' | 'Idle';
export type SubtaskStatus = 'pending' | 'passing' | 'failing';

export interface SubtaskInfo {
  id: string;
  title: string;
  status: SubtaskStatus;
}

export interface IterationProgress {
  current_iteration: number;
  total_iterations: number;
  phase: Phase;
  subtasks: SubtaskInfo[];
  passed_count: number;
  total_count: number;
  last_score: number | null;
  passing_score: number;
  review_summary: string | null;
}

export interface IterationProgressEvent {
  issue_number: number;
  progress: IterationProgress;
}

type UnlistenFn = () => void;
type IterationEventName = 'iteration-progress';
type IterationEventCallback<TPayload> = (event: { payload: TPayload }) => void;

interface IterationStoreDeps {
  isTauri: boolean;
  invoke: <T>(cmd: string, args?: Record<string, unknown>) => Promise<T>;
  listen: <TPayload>(
    event: IterationEventName,
    callback: IterationEventCallback<TPayload>,
  ) => Promise<UnlistenFn>;
}

async function tauriInvoke<T>(
  cmd: string,
  args?: Record<string, unknown>,
): Promise<T> {
  const { invoke } = await import('@tauri-apps/api/core');
  return invoke<T>(cmd, args);
}

async function tauriListen<TPayload>(
  event: IterationEventName,
  callback: IterationEventCallback<TPayload>,
): Promise<UnlistenFn> {
  const { listen } = await import('@tauri-apps/api/event');
  return listen(event, callback);
}

function createIterationStoreDeps(
  overrides: Partial<IterationStoreDeps> = {},
): IterationStoreDeps {
  return {
    isTauri,
    invoke: tauriInvoke,
    listen: tauriListen,
    ...overrides,
  };
}

export const IDLE_PROGRESS: IterationProgress = {
  current_iteration: 0,
  total_iterations: 0,
  phase: 'Idle',
  subtasks: [],
  passed_count: 0,
  total_count: 0,
  last_score: null,
  passing_score: 85,
  review_summary: null,
};

export interface IterationState {
  currentIssueNumber: number | null;
  requestKey: number;
  subscriptionsReady: boolean;
  progress: IterationProgress;
  isLoading: boolean;
  error: string | null;
  initialize: () => Promise<void>;
  watchIssue: (projectPath: string, issueNumber: number) => Promise<void>;
  reset: () => void;
}

export function createIterationStore(overrides: Partial<IterationStoreDeps> = {}) {
  const deps = createIterationStoreDeps(overrides);

  return create<IterationState>((set, get) => ({
    currentIssueNumber: null,
    requestKey: 0,
    subscriptionsReady: false,
    progress: IDLE_PROGRESS,
    isLoading: false,
    error: null,

    initialize: async () => {
      if (!deps.isTauri) {
        set({ subscriptionsReady: true });
        return;
      }

      if (get().subscriptionsReady) {
        return;
      }

      await deps.listen<IterationProgressEvent>('iteration-progress', (event) => {
        set((state) => {
          if (state.currentIssueNumber !== event.payload.issue_number) {
            return state;
          }

          return {
            progress: event.payload.progress,
            isLoading: false,
            error: null,
          };
        });
      });

      set({ subscriptionsReady: true });
    },

    watchIssue: async (projectPath: string, issueNumber: number) => {
      const nextRequestKey = get().requestKey + 1;
      set({
        currentIssueNumber: issueNumber,
        requestKey: nextRequestKey,
        progress: IDLE_PROGRESS,
        isLoading: true,
        error: null,
      });

      if (!deps.isTauri) {
        set({ isLoading: false });
        return;
      }

      try {
        const data = await deps.invoke<IterationProgress>(
          'get_iteration_progress',
          { projectPath, issueNumber },
        );

        const { currentIssueNumber, requestKey } = get();
        if (currentIssueNumber !== issueNumber || requestKey !== nextRequestKey) {
          return;
        }

        set({
          progress: data,
          isLoading: false,
          error: null,
        });
      } catch (err) {
        const { currentIssueNumber, requestKey } = get();
        if (currentIssueNumber !== issueNumber || requestKey !== nextRequestKey) {
          return;
        }

        const message = err instanceof Error ? err.message : String(err);
        set({
          progress: IDLE_PROGRESS,
          isLoading: false,
          error: message,
        });
      }
    },

    reset: () => {
      set((state) => ({
        currentIssueNumber: null,
        requestKey: state.requestKey + 1,
        progress: IDLE_PROGRESS,
        isLoading: false,
        error: null,
      }));
    },
  }));
}

export const useIterationStore = createIterationStore();
