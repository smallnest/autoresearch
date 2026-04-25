import test from 'node:test';
import assert from 'node:assert/strict';
import {
  idleMessage,
  PHASE_STEPS,
  phaseIndex,
  scoreBadgeClass,
  scoreColorClass,
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

test('scoreColorClass returns correct color classes for score ranges', () => {
  // Red: < 70
  assert.match(scoreColorClass(0), /red/);
  assert.match(scoreColorClass(69), /red/);
  // Yellow: 70-84
  assert.match(scoreColorClass(70), /yellow/);
  assert.match(scoreColorClass(84), /yellow/);
  // Green: >= 85
  assert.match(scoreColorClass(85), /green/);
  assert.match(scoreColorClass(100), /green/);
});

test('scoreBadgeClass returns correct badge classes for score ranges', () => {
  assert.match(scoreBadgeClass(50), /red/);
  assert.match(scoreBadgeClass(75), /yellow/);
  assert.match(scoreBadgeClass(90), /green/);
});
