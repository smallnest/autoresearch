import { create, type StateCreator } from 'zustand';
import {
  createJSONStorage,
  persist,
  type PersistOptions,
  type StateStorage,
} from 'zustand/middleware';

export const RUN_CONFIG_STORE_KEY = 'autoresearch-run-config';

export const MIN_MAX_ITERATIONS = 1;
export const MAX_MAX_ITERATIONS = 50;
export const DEFAULT_MAX_ITERATIONS = 16;

export const MIN_PASSING_SCORE = 1;
export const MAX_PASSING_SCORE = 100;
export const DEFAULT_PASSING_SCORE = 85;

export const DEFAULT_CONTINUE_MODE = false;

interface RunConfigValues {
  maxIterations: number;
  passingScore: number;
  continueMode: boolean;
}

export interface RunConfigState extends RunConfigValues {
  setMaxIterations: (value: number) => void;
  setPassingScore: (value: number) => void;
  setContinueMode: (value: boolean) => void;
  reset: () => void;
}

interface RunConfigStoreDeps {
  storage?: StateStorage;
}

const DEFAULT_CONFIG: RunConfigValues = {
  maxIterations: DEFAULT_MAX_ITERATIONS,
  passingScore: DEFAULT_PASSING_SCORE,
  continueMode: DEFAULT_CONTINUE_MODE,
};

const noopStorage: StateStorage = {
  getItem: () => null,
  setItem: () => {},
  removeItem: () => {},
};

function clamp(value: number, min: number, max: number): number {
  return Math.min(Math.max(value, min), max);
}

function normalizeInteger(value: number): number {
  return Math.round(value);
}

function sanitizeNumber(value: unknown, fallback: number, min: number, max: number): number {
  if (typeof value !== 'number' || !Number.isFinite(value)) {
    return fallback;
  }

  return clamp(normalizeInteger(value), min, max);
}

function sanitizeBoolean(value: unknown, fallback: boolean): boolean {
  return typeof value === 'boolean' ? value : fallback;
}

export function sanitizeRunConfig(values: Partial<RunConfigValues>): RunConfigValues {
  return {
    maxIterations: sanitizeNumber(
      values.maxIterations,
      DEFAULT_MAX_ITERATIONS,
      MIN_MAX_ITERATIONS,
      MAX_MAX_ITERATIONS
    ),
    passingScore: sanitizeNumber(
      values.passingScore,
      DEFAULT_PASSING_SCORE,
      MIN_PASSING_SCORE,
      MAX_PASSING_SCORE
    ),
    continueMode: sanitizeBoolean(values.continueMode, DEFAULT_CONTINUE_MODE),
  };
}

function createRunConfigState(
  set: Parameters<StateCreator<RunConfigState>>[0]
): RunConfigState {
  return {
    ...DEFAULT_CONFIG,
    setMaxIterations: (value) => {
      set((state) => ({
        maxIterations: sanitizeNumber(
          value,
          state.maxIterations,
          MIN_MAX_ITERATIONS,
          MAX_MAX_ITERATIONS
        ),
      }));
    },
    setPassingScore: (value) => {
      set((state) => ({
        passingScore: sanitizeNumber(
          value,
          state.passingScore,
          MIN_PASSING_SCORE,
          MAX_PASSING_SCORE
        ),
      }));
    },
    setContinueMode: (value) => {
      set((state) => ({
        continueMode: sanitizeBoolean(value, state.continueMode),
      }));
    },
    reset: () => {
      set({ ...DEFAULT_CONFIG });
    },
  };
}

function createPersistOptions(
  deps: RunConfigStoreDeps
): PersistOptions<RunConfigState, RunConfigValues> {
  return {
    name: RUN_CONFIG_STORE_KEY,
    storage: createJSONStorage(() =>
      deps.storage ?? (typeof localStorage === 'undefined' ? noopStorage : localStorage)
    ),
    partialize: (state) => ({
      maxIterations: state.maxIterations,
      passingScore: state.passingScore,
      continueMode: state.continueMode,
    }),
    merge: (persistedState, currentState) => ({
      ...currentState,
      ...sanitizeRunConfig((persistedState as Partial<RunConfigValues>) ?? {}),
    }),
  };
}

export function createRunConfigStore(deps: RunConfigStoreDeps = {}) {
  return create<RunConfigState>()(
    persist((set) => createRunConfigState(set), createPersistOptions(deps))
  );
}

export const useRunConfigStore = createRunConfigStore();
