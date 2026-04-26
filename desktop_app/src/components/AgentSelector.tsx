import {
  DndContext,
  closestCenter,
  KeyboardSensor,
  PointerSensor,
  useSensor,
  useSensors,
  DragEndEvent,
} from '@dnd-kit/core';
import {
  SortableContext,
  sortableKeyboardCoordinates,
  useSortable,
  verticalListSortingStrategy,
} from '@dnd-kit/sortable';
import { CSS } from '@dnd-kit/utilities';
import { useAgentStore, AVAILABLE_AGENTS, AGENT_METADATA, AgentId } from '../stores/agentStore';

interface SortableTagProps {
  id: AgentId;
  name: string;
  installed: boolean;
  onRemove: () => void;
}

function SortableTag({ id, name, installed, onRemove }: SortableTagProps) {
  const {
    attributes,
    listeners,
    setNodeRef,
    transform,
    transition,
    isDragging,
  } = useSortable({ id });

  const style = {
    transform: CSS.Transform.toString(transform),
    transition,
    opacity: isDragging ? 0.5 : installed ? 1 : 0.5,
  };

  return (
    <div
      ref={setNodeRef}
      style={style}
      className={`inline-flex items-center gap-2 px-3 py-1.5 rounded-lg ${
        installed
          ? 'bg-blue-600 cursor-grab active:cursor-grabbing hover:bg-blue-500'
          : 'bg-gray-300 cursor-not-allowed'
      }`}
      {...attributes}
      {...listeners}
    >
      <span className={`text-sm font-medium ${installed ? 'text-white' : 'text-gray-500'}`}>
        {name}
      </span>
      {!installed && (
        <span className="text-xs text-gray-500">未安装</span>
      )}
      <button
        type="button"
        onClick={(e) => {
          e.stopPropagation();
          onRemove();
        }}
        aria-label={`移除 ${name}`}
        className={`w-4 h-4 flex items-center justify-center rounded ${
          installed
            ? 'text-blue-200 hover:text-white hover:bg-blue-700'
            : 'text-gray-400 hover:text-gray-600 hover:bg-gray-400'
        }`}
      >
        ×
      </button>
    </div>
  );
}

interface AgentTagProps {
  name: string;
  isSelected: boolean;
  installed: boolean;
  onClick: () => void;
}

function AgentTag({ name, isSelected, installed, onClick }: AgentTagProps) {
  if (!installed) {
    return (
      <span className="inline-flex items-center gap-1 px-3 py-1.5 rounded-lg text-sm font-medium bg-gray-100 text-gray-400 cursor-not-allowed opacity-50">
        {name}
        <span className="text-xs text-gray-400">未安装</span>
      </span>
    );
  }

  return (
    <button
      type="button"
      onClick={onClick}
      className={`inline-flex items-center gap-1 px-3 py-1.5 rounded-lg text-sm font-medium transition-colors ${
        isSelected
          ? 'bg-blue-600 text-white hover:bg-blue-500'
          : 'bg-gray-100 text-gray-500 hover:bg-gray-200 hover:text-gray-700'
      }`}
    >
      {name}
    </button>
  );
}

function AgentSkeletonTag() {
  return (
    <div className="skeleton-shimmer inline-flex items-center h-8 w-24 rounded-lg bg-gray-100" />
  );
}

export default function AgentSelector() {
  const {
    selectedAgents,
    installedAgents,
    isDetecting,
    toggleAgent,
    reorderAgents,
    selectAll,
    clearAll,
  } = useAgentStore();

  const sensors = useSensors(
    useSensor(PointerSensor, {
      activationConstraint: {
        distance: 5,
      },
    }),
    useSensor(KeyboardSensor, {
      coordinateGetter: sortableKeyboardCoordinates,
    })
  );

  const handleDragEnd = (event: DragEndEvent) => {
    const { active, over } = event;

    if (over && active.id !== over.id) {
      const oldIndex = selectedAgents.indexOf(active.id as AgentId);
      const newIndex = selectedAgents.indexOf(over.id as AgentId);
      reorderAgents(oldIndex, newIndex);
    }
  };

  const selected = selectedAgents;
  const unselected = AVAILABLE_AGENTS.filter((agent) => !selectedAgents.includes(agent));

  const handleToggle = (agentId: AgentId) => {
    // Only allow toggling installed agents
    if (!installedAgents[agentId]?.installed) {
      return;
    }
    toggleAgent(agentId);
  };

  // Loading state: show skeleton tags
  if (isDetecting) {
    return (
      <div className="space-y-6">
        <div>
          <div className="flex items-center justify-between mb-3">
            <h3 className="text-sm font-medium text-gray-600">已选 Agent</h3>
          </div>
          <div className="flex flex-wrap gap-2 p-3 bg-gray-50 rounded-lg border border-gray-200">
            <AgentSkeletonTag />
            <AgentSkeletonTag />
            <AgentSkeletonTag />
          </div>
        </div>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      <div>
        <div className="flex items-center justify-between mb-3">
          <h3 className="text-sm font-medium text-gray-600">已选 Agent</h3>
          <div className="flex gap-2">
            <button
              type="button"
              onClick={selectAll}
              className="px-3 py-1 text-xs font-medium text-gray-600 bg-gray-100 hover:bg-gray-200 rounded"
            >
              全选
            </button>
            <button
              type="button"
              onClick={clearAll}
              className="px-3 py-1 text-xs font-medium text-gray-600 bg-gray-100 hover:bg-gray-200 rounded"
            >
              清空
            </button>
          </div>
        </div>

        {selected.length > 0 ? (
          <DndContext
            sensors={sensors}
            collisionDetection={closestCenter}
            onDragEnd={handleDragEnd}
          >
            <SortableContext items={selected} strategy={verticalListSortingStrategy}>
              <div className="flex flex-wrap gap-2 p-3 bg-gray-50 rounded-lg border border-gray-200">
                {selected.map((agentId) => (
                  <SortableTag
                    key={agentId}
                    id={agentId}
                    name={AGENT_METADATA[agentId].name}
                    installed={installedAgents[agentId]?.installed ?? false}
                    onRemove={() => handleToggle(agentId)}
                  />
                ))}
              </div>
            </SortableContext>
          </DndContext>
        ) : (
          <div className="p-3 bg-gray-50 rounded-lg border border-gray-200 text-gray-400 text-sm">
            暂未选择 Agent，请在下方添加。
          </div>
        )}
      </div>

      {unselected.length > 0 && (
        <div>
          <h3 className="text-sm font-medium text-gray-600 mb-3">可选 Agent</h3>
          <div className="flex flex-wrap gap-2">
            {unselected.map((agentId) => (
              <AgentTag
                key={agentId}
                name={AGENT_METADATA[agentId].name}
                isSelected={false}
                installed={installedAgents[agentId]?.installed ?? false}
                onClick={() => handleToggle(agentId)}
              />
            ))}
          </div>
        </div>
      )}
    </div>
  );
}
