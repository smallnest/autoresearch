import test from 'node:test';
import assert from 'node:assert/strict';
import { normalizeUserFacingError } from '../src/stores/uiError.ts';
import { normalizeIssueDetailError, normalizeIssueListError } from '../src/stores/issueStore.ts';
import { normalizeLogViewerError } from '../src/stores/logViewerStore.ts';
import { normalizeProjectError } from '../src/stores/projectStore.ts';
import {
  normalizeRunStatusError,
  normalizeStartRunError,
  normalizeStopRunError,
} from '../src/stores/runStore.ts';

test('normalizeUserFacingError preserves Chinese messages as-is', () => {
  assert.equal(
    normalizeUserFacingError(new Error('项目路径无效'), '默认错误'),
    '项目路径无效'
  );
});

test('normalizeUserFacingError appends English details to Chinese fallback', () => {
  assert.equal(
    normalizeUserFacingError(new Error('run.sh not found at: /foo/bar'), '启动任务失败，请重试'),
    '启动任务失败，请重试：run.sh not found at: /foo/bar'
  );
  assert.equal(
    normalizeUserFacingError(new Error('Project path is not a directory: /tmp'), '加载失败'),
    '加载失败：Project path is not a directory: /tmp'
  );
});

test('normalizeUserFacingError returns pure fallback for empty errors', () => {
  assert.equal(normalizeUserFacingError(new Error(''), '默认错误'), '默认错误');
  assert.equal(normalizeUserFacingError('', '默认错误'), '默认错误');
});

test('store error normalizers preserve Chinese copy and append English errors to Chinese fallbacks', () => {
  assert.equal(normalizeProjectError(new Error('Network timeout')), '加载项目失败，请重试。：Network timeout');
  assert.equal(
    normalizeProjectError(new Error('路径格式无效，请输入绝对路径')),
    '路径格式无效，请输入绝对路径'
  );

  assert.equal(normalizeIssueListError(new Error('Request failed')), '加载议题失败，请重试。：Request failed');
  assert.equal(normalizeIssueDetailError(new Error('Request failed')), '加载议题详情失败，请重试。：Request failed');
  assert.equal(normalizeLogViewerError(new Error('Permission denied')), '加载日志失败，请重试。：Permission denied');
});

test('run store error normalizers append English details to Chinese fallbacks', () => {
  assert.equal(normalizeRunStatusError(new Error('Backend unavailable')), '获取运行状态失败，请重试。：Backend unavailable');
  assert.equal(normalizeStartRunError(new Error('Unknown backend error')), '启动任务失败，请重试。：Unknown backend error');
  assert.equal(normalizeStopRunError(new Error('Unknown backend error')), '停止任务失败，请重试。：Unknown backend error');
  assert.equal(normalizeStartRunError(new Error('当前已有任务在运行，请先停止后再启动新任务。')), '当前已有任务在运行，请先停止后再启动新任务。');
});
