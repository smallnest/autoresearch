import { create } from 'zustand';
import { invoke } from '@tauri-apps/api/core';

export interface ProjectConfig {
  has_autoresearch_dir: boolean;
  has_program_md: boolean;
  has_agents_dir: boolean;
}

interface ProjectState {
  projectPath: string | null;
  config: ProjectConfig | null;
  recentProjects: string[];
  isLoading: boolean;
  error: string | null;
  selectProject: () => Promise<void>;
  loadProject: (path: string) => Promise<void>;
  loadRecentProjects: () => Promise<void>;
  clearError: () => void;
}

export const useProjectStore = create<ProjectState>((set, get) => ({
  projectPath: null,
  config: null,
  recentProjects: [],
  isLoading: false,
  error: null,

  selectProject: async () => {
    set({ isLoading: true, error: null });
    try {
      const path = await invoke<string | null>('select_project_dir');
      if (path) {
        const config = await invoke<ProjectConfig>('detect_project_config', {
          projectPath: path,
        });
        // Save to Tauri store
        await invoke('save_recent_project', { path });
        set((state) => ({
          projectPath: path,
          config,
          recentProjects: [path, ...state.recentProjects.filter((p) => p !== path)].slice(0, 5),
        }));
      }
    } catch (e) {
      set({ error: String(e) });
    } finally {
      set({ isLoading: false });
    }
  },

  loadProject: async (path: string) => {
    set({ isLoading: true, error: null });
    try {
      const config = await invoke<ProjectConfig>('detect_project_config', {
        projectPath: path,
      });
      await invoke('save_recent_project', { path });
      set((state) => ({
        projectPath: path,
        config,
        recentProjects: [path, ...state.recentProjects.filter((p) => p !== path)].slice(0, 5),
      }));
    } catch (e) {
      set({ error: String(e) });
    } finally {
      set({ isLoading: false });
    }
  },

  loadRecentProjects: async () => {
    try {
      const path = await invoke<string | null>('get_recent_project');
      if (path) {
        set({ recentProjects: [path] });
        // If no current project, auto-load the recent one
        if (!get().projectPath) {
          const config = await invoke<ProjectConfig>('detect_project_config', {
            projectPath: path,
          });
          set({ projectPath: path, config });
        }
      }
    } catch (e) {
      console.error('Failed to load recent projects:', e);
    }
  },

  clearError: () => set({ error: null }),
}));
