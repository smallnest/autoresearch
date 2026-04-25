import test from 'node:test';
import assert from 'node:assert/strict';
import { normalizeIssueDetailError, normalizeIssueListError } from '../src/stores/issueStore.ts';
import { normalizeLogViewerError } from '../src/stores/logViewerStore.ts';
import { normalizeProjectError } from '../src/stores/projectStore.ts';
import {
  normalizeRunStatusError,
  normalizeStartRunError,
  normalizeStopRunError,
} from '../src/stores/runStore.ts';

test('store error normalizers preserve Chinese copy and replace English errors with Chinese fallbacks', () => {
  assert.equal(normalizeProjectError(new Error('Network timeout')), '加载项目失败，请重试。');
  assert.equal(
    normalizeProjectError(new Error('路径格式无效，请输入绝对路径')),
    '路径格式无效，请输入绝对路径'
  );

  assert.equal(normalizeIssueListError(new Error('Request failed')), '加载议题失败，请重试。');
  assert.equal(normalizeIssueDetailError(new Error('Request failed')), '加载议题详情失败，请重试。');
  assert.equal(normalizeLogViewerError(new Error('Permission denied')), '加载日志失败，请重试。');
});

test('run store error normalizers keep user-facing copy fully Chinese', () => {
  assert.equal(normalizeRunStatusError(new Error('Backend unavailable')), '获取运行状态失败，请重试。');
  assert.equal(normalizeStartRunError(new Error('Unknown backend error')), '启动任务失败，请重试。');
  assert.equal(normalizeStopRunError(new Error('Unknown backend error')), '停止任务失败，请重试。');
  assert.equal(normalizeStartRunError(new Error('当前已有任务在运行，请先停止后再启动新任务。')), '当前已有任务在运行，请先停止后再启动新任务。');
});
