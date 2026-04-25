import { useEffect, type JSX } from 'react';
import {
  type Phase,
  type SubtaskInfo,
  useIterationStore,
} from '../stores/iterationStore';
import {
  idleMessage,
  PHASE_STEPS,
  phaseIndex,
  subtaskBadgeClass,
} from './iterationProgressView';

interface IterationProgressPanelProps {
  issueNumber: number;
  projectPath: string | null;
  isRunning: boolean;
}

function PhaseSteps({ currentPhase }: { currentPhase: Phase }): JSX.Element {
  const activeIdx = phaseIndex(currentPhase);

  return (
    <div className="flex items-center gap-1">
      {PHASE_STEPS.map((step, idx) => {
        const isActive = idx === activeIdx;
        const isPast = activeIdx > idx;

        let pillClass =
          'rounded-full px-2.5 py-1 text-xs font-medium transition-colors';
        if (isActive) {
          pillClass += ' bg-blue-600 text-white';
        } else if (isPast) {
          pillClass += ' bg-blue-100 text-blue-700';
        } else {
          pillClass += ' bg-gray-100 text-gray-400';
        }

        return (
          <span key={step.key}>
            {idx > 0 && (
              <span
                className={`mx-1 inline-block text-xs ${
                  isPast || isActive ? 'text-blue-400' : 'text-gray-300'
                }`}
              >
                →
              </span>
            )}
            <span className={pillClass}>{step.label}</span>
          </span>
        );
      })}
    </div>
  );
}

function SubtaskList({
  subtasks,
}: {
  subtasks: SubtaskInfo[];
}): JSX.Element {
  if (subtasks.length === 0) {
    return (
      <p className="text-xs text-gray-400">暂无 subtask 信息。</p>
    );
  }

  return (
    <ul className="space-y-1.5">
      {subtasks.map((subtask) => (
        <li
          key={subtask.id}
          className="flex items-center justify-between rounded-lg border border-gray-100 bg-white px-3 py-2 text-sm"
        >
          <span className="min-w-0 truncate text-gray-700">
            <span className="mr-1.5 font-mono text-xs text-gray-400">{subtask.id}</span>
            {subtask.title}
          </span>
          <span
            className={`ml-2 shrink-0 rounded-full border px-2 py-0.5 text-xs font-medium ${subtaskBadgeClass(subtask.status)}`}
          >
            {subtask.status}
          </span>
        </li>
      ))}
    </ul>
  );
}

function ProgressBar({
  passed,
  total,
}: {
  passed: number;
  total: number;
}): JSX.Element {
  const pct = total > 0 ? Math.round((passed / total) * 100) : 0;

  return (
    <div>
      <div className="mb-1 flex items-center justify-between text-xs">
        <span className="font-medium text-gray-600">
          {passed}/{total} subtasks passed
        </span>
        <span className="text-gray-400">{pct}%</span>
      </div>
      <div className="h-2 overflow-hidden rounded-full bg-gray-200">
        <div
          className="h-full rounded-full bg-blue-500 transition-all"
          style={{ width: `${pct}%` }}
        />
      </div>
    </div>
  );
}

export default function IterationProgressPanel({
  issueNumber,
  projectPath,
  isRunning,
}: IterationProgressPanelProps): JSX.Element {
  const { progress, error, isLoading, initialize, watchIssue, reset } = useIterationStore();

  useEffect(() => {
    if (!projectPath) {
      reset();
      return;
    }

    void initialize().then(() => watchIssue(projectPath, issueNumber));

    return () => {
      reset();
    };
  }, [projectPath, issueNumber, initialize, watchIssue, reset]);

  const isIdle = progress.phase === 'Idle' && progress.current_iteration === 0;

  if (isIdle) {
    return (
      <div className="mt-4 rounded-xl border border-dashed border-gray-300 bg-gray-50 px-4 py-5 text-center text-sm text-gray-400">
        {idleMessage(isRunning, isLoading)}
        {error && (
          <p className="mt-2 text-xs text-red-400">{error}</p>
        )}
      </div>
    );
  }

  return (
    <div className="mt-4 space-y-4 rounded-xl border border-gray-200 bg-white p-4">
      <div className="flex items-center justify-between">
        <h4 className="text-sm font-semibold text-gray-700">迭代进度</h4>
        <span className="rounded-full bg-gray-100 px-3 py-1 text-sm font-mono font-medium text-gray-700">
          {progress.current_iteration} / {progress.total_iterations}
        </span>
      </div>

      <PhaseSteps currentPhase={progress.phase} />
      <ProgressBar passed={progress.passed_count} total={progress.total_count} />
      <SubtaskList subtasks={progress.subtasks} />

      {error && (
        <p className="text-xs text-red-500">{error}</p>
      )}
    </div>
  );
}
