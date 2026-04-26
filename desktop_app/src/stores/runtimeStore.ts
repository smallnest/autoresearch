import { create } from 'zustand';
import { normalizeUserFacingError } from './uiError.ts';

const isTauri = typeof window !== 'undefined' && '__TAURI_INTERNALS__' in window;

async function tauriInvoke<T>(cmd: string, args?: Record<string, unknown>): Promise<T> {
  const { invoke } = await import('@tauri-apps/api/core');
  return invoke<T>(cmd, args);
}

export type RuntimeStatus = 'idle' | 'initializing' | 'installed' | 'already_exists' | 'updated' | 'error';

interface EnsureRuntimeResult {
  status: 'installed' | 'already_exists' | 'updated';
}

interface RuntimeState {
  status: RuntimeStatus;
  error: string | null;
  initializeRuntime: () => Promise<void>;
}

export const useRuntimeStore = create<RuntimeState>((set, get) => ({
  status: 'idle',
  error: null,

  initializeRuntime: async () => {
    // Prevent double initialization
    if (get().status === 'initializing' || get().status === 'installed' || get().status === 'already_exists' || get().status === 'updated') {
      return;
    }

    if (!isTauri) {
      set({ status: 'already_exists' });
      return;
    }

    set({ status: 'initializing', error: null });

    try {
      const result = await tauriInvoke<EnsureRuntimeResult>('ensure_runtime');
      set({ status: result.status });
    } catch (e) {
      console.error('Runtime initialization failed:', e);
      set({
        status: 'error',
        error: normalizeUserFacingError(e, '运行时初始化失败，请重启应用重试。'),
      });
    }
  },
}));
