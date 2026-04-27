import { create } from 'zustand';
import { persist } from 'zustand/middleware';

// Hardcoded list of available agents
export const AVAILABLE_AGENTS = ['claude', 'codex', 'opencode'] as const;

export type AgentId = (typeof AVAILABLE_AGENTS)[number];

export interface AgentInfo {
  id: AgentId;
  name: string;
  description: string;
}

// Agent metadata for display purposes
export const AGENT_METADATA: Record<AgentId, AgentInfo> = {
  claude: {
    id: 'claude',
    name: 'Claude',
    description: 'Anthropic Claude AI Assistant',
  },
  codex: {
    id: 'codex',
    name: 'Codex',
    description: 'OpenAI Codex Agent',
  },
  opencode: {
    id: 'opencode',
    name: 'OpenCode',
    description: 'OpenCode Agent',
  },
};

// Types mirroring Rust CliToolStatus and CliToolsResult
export interface CliToolStatus {
  installed: boolean;
  path: string | null;
}

export interface CliToolsResult {
  gh: CliToolStatus;
  claude: CliToolStatus;
  codex: CliToolStatus;
  opencode: CliToolStatus;
}

export interface AgentInstallStatus {
  installed: boolean;
  path: string | null;
}

interface AgentState {
  // Ordered array of selected agent IDs
  selectedAgents: AgentId[];
  // Install status for each agent, populated by detect_cli_tools
  installedAgents: Record<AgentId, AgentInstallStatus>;
  // Whether gh CLI is installed
  ghInstalled: boolean;
  // Whether detection is in progress
  isDetecting: boolean;
  // Whether detection has completed at least once (including failure)
  detectionDone: boolean;
  // Toggle agent selection (add if not selected, remove if selected)
  toggleAgent: (agentId: AgentId) => void;
  // Reorder agents by moving from one index to another
  reorderAgents: (fromIndex: number, toIndex: number) => void;
  // Select all available agents
  selectAll: () => void;
  // Clear all selected agents
  clearAll: () => void;
  // Check if an agent is selected
  isSelected: (agentId: AgentId) => boolean;
  // Get ordered list of selected agents with metadata
  getSelectedAgentsInfo: () => AgentInfo[];
  // Detect CLI tools and initialize store accordingly
  initializeFromDetection: () => Promise<void>;
}

interface AgentStoreDeps {
  isTauri: boolean;
  invoke: <T>(cmd: string, args?: Record<string, unknown>) => Promise<T>;
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  storage?: any;
}

const isTauri =
  typeof window !== 'undefined' && '__TAURI_INTERNALS__' in window;

async function tauriInvoke<T>(
  cmd: string,
  args?: Record<string, unknown>
): Promise<T> {
  const { invoke } = await import('@tauri-apps/api/core');
  return invoke<T>(cmd, args);
}

function createAgentStoreDeps(overrides: Partial<AgentStoreDeps> = {}): AgentStoreDeps {
  return {
    isTauri,
    invoke: tauriInvoke,
    ...overrides,
  };
}

export function createAgentStore(overrides: Partial<AgentStoreDeps> = {}) {
  const deps = createAgentStoreDeps(overrides);

  return create<AgentState>()(
    persist(
      (set, get) => ({
        selectedAgents: [],
        installedAgents: {} as Record<AgentId, AgentInstallStatus>,
        ghInstalled: false,
        isDetecting: false,
        detectionDone: false,

        isSelected: (_agentId: AgentId) => {
          return get().selectedAgents.includes(_agentId);
        },

        getSelectedAgentsInfo: () => {
          return get().selectedAgents.map((id) => AGENT_METADATA[id]);
        },

        reorderAgents: (_fromIndex: number, _toIndex: number) => {
          set((state) => {
            const agents = [...state.selectedAgents];
            if (
              _fromIndex < 0 ||
              _fromIndex >= agents.length ||
              _toIndex < 0 ||
              _toIndex >= agents.length
            ) {
              return state;
            }

            const [movedAgent] = agents.splice(_fromIndex, 1);
            agents.splice(_toIndex, 0, movedAgent);

            return { selectedAgents: agents };
          });
        },

        selectAll: () => {
          const installed = AVAILABLE_AGENTS.filter(
            (id) => get().installedAgents[id]?.installed
          );
          set({ selectedAgents: installed });
        },

        clearAll: () => {
          set({ selectedAgents: [] });
        },

        toggleAgent: (_agentId: AgentId) => {
          set((state) => {
            const isSelected = state.selectedAgents.includes(_agentId);
            if (isSelected) {
              // Remove agent
              return {
                selectedAgents: state.selectedAgents.filter((id) => id !== _agentId),
              };
            } else {
              // Only allow selecting installed agents
              if (!state.installedAgents[_agentId]?.installed) return state;
              return {
                selectedAgents: [...state.selectedAgents, _agentId],
              };
            }
          });
        },

        initializeFromDetection: async () => {
          if (!deps.isTauri) {
            return;
          }

          set({ isDetecting: true });

          try {
            const result = await deps.invoke<CliToolsResult>('detect_cli_tools');

            // Map detection results to installedAgents
            const installedAgents: Record<AgentId, AgentInstallStatus> = {
              claude: { installed: result.claude.installed, path: result.claude.path },
              codex: { installed: result.codex.installed, path: result.codex.path },
              opencode: { installed: result.opencode.installed, path: result.opencode.path },
            };

            const ghInstalled = result.gh.installed;

            set((state) => {
              // If selectedAgents is empty (first launch), auto-select installed agents
              // in priority order: claude > codex > opencode
              if (state.selectedAgents.length === 0) {
                const autoSelected: AgentId[] = [];
                for (const agentId of AVAILABLE_AGENTS) {
                  if (installedAgents[agentId]?.installed) {
                    autoSelected.push(agentId);
                  }
                }
                return { installedAgents, ghInstalled, isDetecting: false, detectionDone: true, selectedAgents: autoSelected };
              }

              // Non-first launch: keep user selection, just update install status
              return { installedAgents, ghInstalled, isDetecting: false, detectionDone: true };
            });
          } catch {
            // Detection failed — preserve existing detection state, just stop loading
            set({ isDetecting: false, detectionDone: true });
          }
        },
      }),
      {
        name: 'autoresearch-agents',
        // Only persist selectedAgents; detection results are re-computed on each launch
        partialize: (state) => ({ selectedAgents: state.selectedAgents } as AgentState),
        ...(deps.storage ? { storage: deps.storage } : {}),
      }
    )
  );
}

export const useAgentStore = createAgentStore();
