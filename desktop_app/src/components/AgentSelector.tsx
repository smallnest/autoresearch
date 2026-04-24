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
  onRemove: () => void;
}

function SortableTag({ id, name, onRemove }: SortableTagProps) {
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
    opacity: isDragging ? 0.5 : 1,
  };

  return (
    <div
      ref={setNodeRef}
      style={style}
      className="inline-flex items-center gap-2 px-3 py-1.5 bg-blue-600 rounded-lg cursor-grab active:cursor-grabbing hover:bg-blue-500"
      {...attributes}
      {...listeners}
    >
      <span className="text-sm font-medium text-white">{name}</span>
      <button
        type="button"
        onClick={(e) => {
          e.stopPropagation();
          onRemove();
        }}
        className="w-4 h-4 flex items-center justify-center text-blue-200 hover:text-white hover:bg-blue-700 rounded"
      >
        ×
      </button>
    </div>
  );
}

interface AgentTagProps {
  name: string;
  isSelected: boolean;
  onClick: () => void;
}

function AgentTag({ name, isSelected, onClick }: AgentTagProps) {
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

export default function AgentSelector() {
  const { selectedAgents, toggleAgent, reorderAgents, selectAll, clearAll } = useAgentStore();

  const sensors = useSensors(
    useSensor(PointerSensor, {
      activationConstraint: {
        distance: 5, // 需要 5px 移动才触发拖拽，避免误触
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
    toggleAgent(agentId);
  };

  return (
    <div className="space-y-6">
      <div>
        <div className="flex items-center justify-between mb-3">
          <h3 className="text-sm font-medium text-gray-600">Selected Agents</h3>
          <div className="flex gap-2">
            <button
              type="button"
              onClick={selectAll}
              className="px-3 py-1 text-xs font-medium text-gray-600 bg-gray-100 hover:bg-gray-200 rounded"
            >
              Select All
            </button>
            <button
              type="button"
              onClick={clearAll}
              className="px-3 py-1 text-xs font-medium text-gray-600 bg-gray-100 hover:bg-gray-200 rounded"
            >
              Clear All
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
                    onRemove={() => handleToggle(agentId)}
                  />
                ))}
              </div>
            </SortableContext>
          </DndContext>
        ) : (
          <div className="p-3 bg-gray-50 rounded-lg border border-gray-200 text-gray-400 text-sm">
            No agents selected. Click below to select.
          </div>
        )}
      </div>

      {unselected.length > 0 && (
        <div>
          <h3 className="text-sm font-medium text-gray-600 mb-3">Available Agents</h3>
          <div className="flex flex-wrap gap-2">
            {unselected.map((agentId) => (
              <AgentTag
                key={agentId}
                name={AGENT_METADATA[agentId].name}
                isSelected={false}
                onClick={() => handleToggle(agentId)}
              />
            ))}
          </div>
        </div>
      )}
    </div>
  );
}
