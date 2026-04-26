import { create } from 'zustand';
import { useAgentStore } from './agentStore.ts';
import { normalizeUserFacingError } from './uiError.ts';

const isTauri =
  typeof window !== 'undefined' && '__TAURI_INTERNALS__' in window;

const MAX_OUTPUT_LINES = 5000;

type RunLifecycleStatus = 'idle' | 'running' | 'stopping' | 'finished' | 'error';
type BackendRunStatus = 'Idle' | 'Running';

interface RunExitEvent {
  exit_code: number | null;
  killed: boolean;
}

interface StartRunRequest {
  projectPath: string;
  issueNumber: number;
  agents?: string;
  maxIter?: number;
  passingScore?: number;
  continueMode?: boolean;
}

type UnlistenFn = () => void;
type RunEventName = 'run-output' | 'run-exit' | 'tray-stop-task';
type RunEventCallback<TPayload> = (event: { payload: TPayload }) => void;

interface RunStoreDeps {
  isTauri: boolean;
  invoke: <T>(cmd: string, args?: Record<string, unknown>) => Promise<T>;
  listen: <TPayload>(
    event: RunEventName,
    callback: RunEventCallback<TPayload>
  ) => Promise<UnlistenFn>;
  getSelectedAgents: () => string[];
}

interface RunStateSnapshot {
  status: RunLifecycleStatus;
  activeIssueNumber: number | null;
  outputLines: string[];
  exitCode: number | null;
}

async function tauriInvoke<T>(
  cmd: string,
  args?: Record<string, unknown>
): Promise<T> {
  const { invoke } = await import('@tauri-apps/api/core');
  return invoke<T>(cmd, args);
}

export function normalizeRunStatusError(error: unknown): string {
  return normalizeUserFacingError(error, '获取运行状态失败，请重试。');
}

export function normalizeStartRunError(error: unknown): string {
  return normalizeUserFacingError(error, '启动任务失败，请重试。');
}

export function normalizeStopRunError(error: unknown): string {
  return normalizeUserFacingError(error, '停止任务失败，请重试。');
}

function mapBackendStatus(status: BackendRunStatus): RunLifecycleStatus {
  return status === 'Running' ? 'running' : 'idle';
}

function appendLine(lines: string[], line: string): string[] {
  const nextLines = [...lines, line];
  if (nextLines.length <= MAX_OUTPUT_LINES) {
    return nextLines;
  }
  return nextLines.slice(nextLines.length - MAX_OUTPUT_LINES);
}

function snapshotState(state: RunState): RunStateSnapshot {
  return {
    status: state.status,
    activeIssueNumber: state.activeIssueNumber,
    outputLines: state.outputLines,
    exitCode: state.exitCode,
  };
}

function restoreKnownIssue(snapshot: RunStateSnapshot): number | null {
  return snapshot.status === 'running' || snapshot.status === 'stopping'
    ? snapshot.activeIssueNumber
    : null;
}

interface RunState {
  status: RunLifecycleStatus;
  activeIssueNumber: number | null;
  outputLines: string[];
  exitCode: number | null;
  error: string | null;
  isSupported: boolean;
  subscriptionsReady: boolean;
  initialize: () => Promise<void>;
  refreshStatus: () => Promise<void>;
  startRun: (_request: StartRunRequest) => Promise<void>;
  stopRun: () => Promise<void>;
  clearOutput: () => void;
  clearError: () => void;
  isIssueRunning: (_issueNumber: number | null) => boolean;
}

async function tauriListen<TPayload>(
  event: RunEventName,
  callback: RunEventCallback<TPayload>
): Promise<UnlistenFn> {
  const { listen } = await import('@tauri-apps/api/event');
  return listen(event, callback);
}

function createRunStoreDeps(overrides: Partial<RunStoreDeps> = {}): RunStoreDeps {
  return {
    isTauri,
    invoke: tauriInvoke,
    listen: tauriListen,
    getSelectedAgents: () => [...useAgentStore.getState().selectedAgents],
    ...overrides,
  };
}

export function createRunStore(overrides: Partial<RunStoreDeps> = {}) {
  const deps = createRunStoreDeps(overrides);

  return create<RunState>((set, get) => ({
    status: 'idle',
    activeIssueNumber: null,
    outputLines: [],
    exitCode: null,
    error: null,
    isSupported: deps.isTauri,
    subscriptionsReady: false,

    initialize: async () => {
      if (!deps.isTauri) {
        set({ subscriptionsReady: true });
        return;
      }

      if (get().subscriptionsReady) {
        return;
      }

      await Promise.all<UnlistenFn>([
        deps.listen<string>('run-output', (event) => {
          set((state) => ({
            outputLines: appendLine(state.outputLines, event.payload),
          }));
        }),
        deps.listen<RunExitEvent>('run-exit', (event) => {
          const { exit_code: exitCode, killed } = event.payload;
          set((state) => ({
            status: killed || exitCode === 0 ? 'finished' : 'error',
            exitCode,
            activeIssueNumber: state.activeIssueNumber,
            error:
              killed || exitCode === 0
                ? null
                : `运行失败${exitCode === null ? '' : `（退出码 ${exitCode}）`}`,
          }));
        }),
        deps.listen('tray-stop-task', () => {
          get().stopRun();
        }),
      ]);

      set({ subscriptionsReady: true });
      await get().refreshStatus();
    },

    refreshStatus: async () => {
      if (!deps.isTauri) {
        set({ status: 'idle' });
        return;
      }

      try {
        const backendStatus = await deps.invoke<BackendRunStatus>('get_run_status');
        set((state) => {
          const nextStatus = mapBackendStatus(backendStatus);
          if (nextStatus === 'running') {
            return {
              status: nextStatus,
              error: null,
            };
          }

          if (state.status === 'running' || state.status === 'stopping') {
            return {
              status: 'idle',
              activeIssueNumber: null,
            };
          }

          return {
            status: state.status === 'idle' ? 'idle' : state.status,
          };
        });
      } catch (error) {
        set({
          status: 'error',
          error: normalizeRunStatusError(error),
        });
      }
    },

    startRun: async (_request: StartRunRequest) => {
      if (!deps.isTauri) {
        set({
          status: 'error',
          error: '浏览器模式不支持运行任务，请通过 tauri dev 启动桌面应用。',
        });
        return;
      }

      const currentStatus = get().status;
      if (currentStatus === 'running' || currentStatus === 'stopping') {
        set({ error: '当前已有任务在运行，请先停止后再启动新任务。' });
        return;
      }

      const previousState = snapshotState(get());
      const selectedAgents = deps.getSelectedAgents();
      const agents =
        _request.agents ?? (selectedAgents.length > 0 ? selectedAgents.join(',') : undefined);

      set({
        status: 'running',
        activeIssueNumber: _request.issueNumber,
        outputLines: [],
        exitCode: null,
        error: null,
      });

      try {
        await deps.invoke('start_run', {
          request: {
            project_path: _request.projectPath,
            issue_number: _request.issueNumber,
            agents,
            max_iter: _request.maxIter,
            passing_score: _request.passingScore,
            continue_mode: _request.continueMode,
          },
        });
      } catch (error) {
        await get().refreshStatus();
        set((state) => {
          const backendStillRunning = state.status === 'running';
          return {
            status: backendStillRunning ? 'running' : 'error',
            activeIssueNumber: backendStillRunning
              ? restoreKnownIssue(previousState)
              : previousState.activeIssueNumber,
            outputLines: previousState.outputLines,
            exitCode: previousState.exitCode,
            error: backendStillRunning
              ? '当前已有任务在运行，请先停止后再启动新任务。'
              : normalizeStartRunError(error),
          };
        });
      }
    },

    stopRun: async () => {
      if (!deps.isTauri) {
        return;
      }

      const previousIssueNumber = get().activeIssueNumber;
      set({
        status: 'stopping',
        error: null,
        activeIssueNumber: previousIssueNumber,
      });

      try {
        await deps.invoke('stop_run');
      } catch (error) {
        await get().refreshStatus();
        set((state) => ({
          status: state.status === 'running' ? 'running' : 'error',
          error: normalizeStopRunError(error),
        }));
      }
    },

    clearOutput: () => {
      set({ outputLines: [] });
    },

    clearError: () => {
      set({ error: null });
    },

    isIssueRunning: (_issueNumber: number | null) => {
      if (_issueNumber === null) {
        return false;
      }
      return get().status === 'running' && get().activeIssueNumber === _issueNumber;
    },
  }));
}

export const useRunStore = createRunStore();
