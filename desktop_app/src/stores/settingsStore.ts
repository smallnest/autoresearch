import { create } from 'zustand';
import { persist } from 'zustand/middleware';

export interface RunConfig {
  maxIterations: number;
  passingScore: number;
}

interface SettingsState {
  config: RunConfig;
  setMaxIterations: (value: number) => void;
  setPassingScore: (value: number) => void;
  resetToDefaults: () => void;
}

const DEFAULT_CONFIG: RunConfig = {
  maxIterations: 42,
  passingScore: 85,
};

export const useSettingsStore = create<SettingsState>()(
  persist(
    (set) => ({
      config: DEFAULT_CONFIG,

      setMaxIterations: (_value: number) => {
        set((state) => ({
          config: { ...state.config, maxIterations: Math.max(1, Math.min(100, _value)) },
        }));
      },

      setPassingScore: (_value: number) => {
        set((state) => ({
          config: { ...state.config, passingScore: Math.max(0, Math.min(100, _value)) },
        }));
      },

      resetToDefaults: () => {
        set({ config: DEFAULT_CONFIG });
      },
    }),
    {
      name: 'autoresearch-settings',
    }
  )
);