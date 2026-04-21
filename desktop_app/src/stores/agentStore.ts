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

interface AgentState {
  // Ordered array of selected agent IDs
  selectedAgents: AgentId[];
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
}

export const useAgentStore = create<AgentState>()(
  persist(
    (set, get) => ({
      selectedAgents: [],

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
        set({ selectedAgents: [...AVAILABLE_AGENTS] });
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
            // Add agent to the end
            return {
              selectedAgents: [...state.selectedAgents, _agentId],
            };
          }
        });
      },
    }),
    {
      name: 'autoresearch-agents',
    }
  )
);