import type { Phase, SubtaskStatus } from '../stores/iterationStore';

export const PHASE_STEPS: { key: Exclude<Phase, 'Idle'>; label: string }[] = [
  { key: 'Planning', label: '规划' },
  { key: 'Implementation', label: '实现' },
  { key: 'Review', label: '审核' },
  { key: 'BuildLintTest', label: '构建·检查·测试' },
];

export function phaseIndex(phase: Phase): number {
  const idx = PHASE_STEPS.findIndex((step) => step.key === phase);
  return idx === -1 ? -1 : idx;
}

export function subtaskBadgeClass(status: SubtaskStatus): string {
  switch (status) {
    case 'passing':
      return 'border-green-200 bg-green-50 text-green-700';
    case 'failing':
      return 'border-red-200 bg-red-50 text-red-700';
    case 'pending':
    default:
      return 'border-gray-200 bg-gray-100 text-gray-500';
  }
}

export function idleMessage(isRunning: boolean, isLoading: boolean): string {
  if (isRunning || isLoading) {
    return '正在加载迭代进度…';
  }
  return '暂无迭代进度，当前为空闲状态。';
}

export function subtaskStatusLabel(status: SubtaskStatus): string {
  switch (status) {
    case 'passing':
      return '通过';
    case 'failing':
      return '失败';
    case 'pending':
    default:
      return '待处理';
  }
}

/**
 * Returns Tailwind CSS classes for score color coding:
 * - Red (< 70): failing
 * - Yellow (70–84): marginal
 * - Green (>= 85): passing
 */
export function scoreColorClass(score: number): string {
  if (score >= 85) {
    return 'text-green-600';
  }
  if (score >= 70) {
    return 'text-yellow-600';
  }
  return 'text-red-600';
}

/**
 * Returns Tailwind CSS classes for score background badge.
 */
export function scoreBadgeClass(score: number): string {
  if (score >= 85) {
    return 'bg-green-50 border-green-200 text-green-700';
  }
  if (score >= 70) {
    return 'bg-yellow-50 border-yellow-200 text-yellow-700';
  }
  return 'bg-red-50 border-red-200 text-red-700';
}
