import { create } from 'zustand';
import { normalizeUserFacingError } from './uiError.ts';

// Detect if running inside Tauri (has native backend) or plain browser (vite dev only)
const isTauri = typeof window !== 'undefined' && '__TAURI_INTERNALS__' in window;

// Lazy import to avoid crash when Tauri is not available
async function tauriInvoke<T>(cmd: string, args?: Record<string, unknown>): Promise<T> {
  const { invoke } = await import('@tauri-apps/api/core');
  return invoke<T>(cmd, args);
}

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
  isInitializing: boolean;
  error: string | null;
  selectProject: () => Promise<void>;
  loadProject: (_path: string) => Promise<void>;
  loadRecentProjects: () => Promise<void>;
  refreshConfig: (_projectPath?: string) => Promise<void>;
  clearError: () => void;
  retryInitialize: () => Promise<void>;
}

// Browser fallback: use localStorage and show/pickFolder API
function isProjectPath(path: string): boolean {
  return path.startsWith('/') || !!path.match(/^[A-Z]:\\/);
}

function detectConfigBrowser(projectPath: string): ProjectConfig {
  // Best-effort: in browser mode we can't check the filesystem,
  // so return a demo config for known project names
  const name = projectPath.split(/[/\\]/).pop() || '';
  const isAutoresearch = name === 'autoresearch' || projectPath.includes('autoresearch');
  return {
    has_autoresearch_dir: isAutoresearch,
    has_program_md: isAutoresearch,
    has_agents_dir: isAutoresearch,
  };
}

function loadRecentFromStorage(): string | null {
  try {
    return localStorage.getItem('autoresearch_recent_project');
  } catch {
    return null;
  }
}

function saveRecentToStorage(path: string) {
  try {
    localStorage.setItem('autoresearch_recent_project', path);
  } catch {
    // ignore
  }
}

export function isConfigIncomplete(config: ProjectConfig | null): boolean {
  if (!config) return true;
  return !config.has_autoresearch_dir || !config.has_program_md || !config.has_agents_dir;
}

async function ensureConfigInitialized(
  path: string,
  config: ProjectConfig,
  set: (partial: Partial<ProjectState> | ((state: ProjectState) => Partial<ProjectState>)) => void,
): Promise<ProjectConfig> {
  if (!isConfigIncomplete(config)) return config;
  set({ isInitializing: true });
  try {
    return await tauriInvoke<ProjectConfig>('init_project_config', { projectPath: path });
  } catch (initError) {
    // Set error so UI can display failure feedback, but don't block the user
    console.warn('Auto-init project config failed:', initError);
    set({ error: normalizeProjectError(initError) });
    return config;
  } finally {
    set({ isInitializing: false });
  }
}

export function normalizeProjectError(error: unknown): string {
  return normalizeUserFacingError(error, '加载项目失败，请重试。');
}

export const useProjectStore = create<ProjectState>((set, get) => ({
  projectPath: null,
  config: null,
  recentProjects: [],
  isLoading: false,
  isInitializing: false,
  error: null,

  selectProject: async () => {
    set({ isLoading: true, error: null });
    try {
      if (isTauri) {
        const path = await tauriInvoke<string | null>('select_project_dir');
        if (path) {
          const detected = await tauriInvoke<ProjectConfig>('detect_project_config', {
            projectPath: path,
          });
          const config = await ensureConfigInitialized(path, detected, set);
          await tauriInvoke('save_recent_project', { path });
          set((state) => ({
            projectPath: path,
            config,
            recentProjects: [path, ...state.recentProjects.filter((p) => p !== path)].slice(0, 5),
          }));
        }
      } else {
        // Browser fallback: use the File System Access API if available
        if ('showDirectoryPicker' in window) {
          const dirHandle = await (window as unknown as { showDirectoryPicker: () => Promise<FileSystemDirectoryHandle> }).showDirectoryPicker();
          const path = dirHandle.name;
          // We don't get the full path in browser, use the name as identifier
          const fakePath = `/home/user/${path}`;
          const config = detectConfigBrowser(fakePath);
          saveRecentToStorage(fakePath);
          set((state) => ({
            projectPath: fakePath,
            config,
            recentProjects: [fakePath, ...state.recentProjects.filter((p) => p !== fakePath)].slice(0, 5),
          }));
        } else {
          // Last resort: prompt user to type a path
          const path = prompt('请输入项目目录路径（例如: /Users/smallnest/ai/autoresearch）:');
          if (path && isProjectPath(path)) {
            const config = detectConfigBrowser(path);
            saveRecentToStorage(path);
            set((state) => ({
              projectPath: path,
              config,
              recentProjects: [path, ...state.recentProjects.filter((p) => p !== path)].slice(0, 5),
            }));
          } else if (path) {
            set({ error: '路径格式无效，请输入绝对路径' });
          }
        }
      }
    } catch (e) {
      set({ error: normalizeProjectError(e) });
    } finally {
      set({ isLoading: false });
    }
  },

  loadProject: async (path: string) => {
    set({ isLoading: true, error: null });
    try {
      if (isTauri) {
        const detected = await tauriInvoke<ProjectConfig>('detect_project_config', {
          projectPath: path,
        });
        const config = await ensureConfigInitialized(path, detected, set);
        await tauriInvoke('save_recent_project', { path });
        set((state) => ({
          projectPath: path,
          config,
          recentProjects: [path, ...state.recentProjects.filter((p) => p !== path)].slice(0, 5),
        }));
      } else {
        const config = detectConfigBrowser(path);
        saveRecentToStorage(path);
        set((state) => ({
          projectPath: path,
          config,
          recentProjects: [path, ...state.recentProjects.filter((p) => p !== path)].slice(0, 5),
        }));
      }
    } catch (e) {
      set({ error: normalizeProjectError(e) });
    } finally {
      set({ isLoading: false });
    }
  },

  loadRecentProjects: async () => {
    try {
      if (isTauri) {
        const path = await tauriInvoke<string | null>('get_recent_project');
        if (path) {
          set({ recentProjects: [path] });
          if (!get().projectPath) {
            const config = await tauriInvoke<ProjectConfig>('detect_project_config', {
              projectPath: path,
            });
            set({ projectPath: path, config });
          }
        }
      } else {
        // Browser fallback: read from localStorage
        const path = loadRecentFromStorage();
        if (path) {
          const config = detectConfigBrowser(path);
          set({
            recentProjects: [path],
            projectPath: path,
            config,
          });
        }
      }
    } catch (e) {
      console.error('Failed to load recent projects:', e);
    }
  },

  refreshConfig: async (targetProjectPath?: string) => {
    const projectPath = targetProjectPath ?? get().projectPath;
    if (!projectPath) {
      return;
    }

    try {
      if (isTauri) {
        const config = await tauriInvoke<ProjectConfig>('detect_project_config', {
          projectPath,
        });
        if (get().projectPath === projectPath) {
          set({ config });
        }
      } else {
        if (get().projectPath === projectPath) {
          set({ config: detectConfigBrowser(projectPath) });
        }
      }
    } catch (e) {
      if (get().projectPath === projectPath) {
        set({ error: normalizeProjectError(e) });
      }
    }
  },

  clearError: () => set({ error: null }),

  retryInitialize: async () => {
    const { projectPath } = get();
    if (!projectPath) return;

    set({ isInitializing: true, error: null });
    try {
      if (isTauri) {
        const config = await tauriInvoke<ProjectConfig>('init_project_config', {
          projectPath,
        });
        set({ config });
      } else {
        set({ config: detectConfigBrowser(projectPath) });
      }
    } catch (e) {
      set({ error: normalizeProjectError(e) });
    } finally {
      set({ isInitializing: false });
    }
  },
}));
