import test from 'node:test';
import assert from 'node:assert/strict';
import {
  idleMessage,
  PHASE_STEPS,
  phaseIndex,
  subtaskBadgeClass,
} from '../src/components/iterationProgressView.ts';

test('phaseIndex and PHASE_STEPS expose the expected iteration pipeline labels', () => {
  assert.deepEqual(
    PHASE_STEPS.map((step) => step.label),
    ['Planning', 'Implementation', 'Review', 'Build·Lint·Test'],
  );
  assert.equal(phaseIndex('Planning'), 0);
  assert.equal(phaseIndex('Review'), 2);
  assert.equal(phaseIndex('Idle'), -1);
});

test('subtaskBadgeClass maps all three statuses to distinct styles', () => {
  assert.match(subtaskBadgeClass('pending'), /gray/);
  assert.match(subtaskBadgeClass('passing'), /green/);
  assert.match(subtaskBadgeClass('failing'), /red/);
});

test('idleMessage distinguishes loading from idle copy', () => {
  assert.equal(idleMessage(true, false), '正在加载迭代进度…');
  assert.equal(idleMessage(false, true), '正在加载迭代进度…');
  assert.equal(idleMessage(false, false), '暂无迭代进度，当前为 idle 状态。');
});
