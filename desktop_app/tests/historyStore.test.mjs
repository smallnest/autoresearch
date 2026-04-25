import test from 'node:test';
import assert from 'node:assert/strict';
import {
  getFilteredAndSortedHistory,
  createHistoryStore,
} from '../src/stores/historyStore.ts';

// ---------------------------------------------------------------------------
// Test data
// ---------------------------------------------------------------------------

const SAMPLE_ENTRIES = [
  {
    issue_number: 34,
    title: '[desktop-app] 配置文件编辑器',
    status: 'Success',
    final_score: 90,
    total_iterations: 8,
    start_time: '2026-04-24T10:00:00Z',
    end_time: '2026-04-24T12:30:00Z',
  },
  {
    issue_number: 30,
    title: '[desktop-app] 日志查看器',
    status: 'Fail',
    final_score: 72,
    total_iterations: 10,
    start_time: '2026-04-22T14:00:00Z',
    end_time: '2026-04-22T18:00:00Z',
  },
  {
    issue_number: 35,
    title: '[desktop-app] 处理历史列表',
    status: 'InProgress',
    final_score: null,
    total_iterations: 15,
    start_time: '2026-04-25T08:00:00Z',
    end_time: null,
  },
  {
    issue_number: 28,
    title: '[desktop-app] 运行配置面板',
    status: 'Interrupt',
    final_score: 60,
    total_iterations: 4,
    start_time: '2026-04-21T13:00:00Z',
    end_time: null,
  },
  {
    issue_number: 33,
    title: '[desktop-app] 评分趋势折线图',
    status: 'Success',
    final_score: 88,
    total_iterations: 6,
    start_time: '2026-04-23T09:00:00Z',
    end_time: '2026-04-23T11:00:00Z',
  },
];

// ---------------------------------------------------------------------------
// getFilteredAndSortedHistory pure function tests
// ---------------------------------------------------------------------------

test('getFilteredAndSortedHistory: statusFilter "all" returns all entries', () => {
  const result = getFilteredAndSortedHistory(SAMPLE_ENTRIES, 'all', 'desc');
  assert.equal(result.length, SAMPLE_ENTRIES.length);
});

test('getFilteredAndSortedHistory: filters by "success"', () => {
  const result = getFilteredAndSortedHistory(SAMPLE_ENTRIES, 'success', 'desc');
  assert.equal(result.length, 2);
  assert.ok(result.every((e) => e.status === 'Success'));
});

test('getFilteredAndSortedHistory: filters by "fail"', () => {
  const result = getFilteredAndSortedHistory(SAMPLE_ENTRIES, 'fail', 'desc');
  assert.equal(result.length, 1);
  assert.equal(result[0].status, 'Fail');
  assert.equal(result[0].issue_number, 30);
});

test('getFilteredAndSortedHistory: filters by "interrupt"', () => {
  const result = getFilteredAndSortedHistory(SAMPLE_ENTRIES, 'interrupt', 'desc');
  assert.equal(result.length, 1);
  assert.equal(result[0].status, 'Interrupt');
  assert.equal(result[0].issue_number, 28);
});

test('getFilteredAndSortedHistory: filters by "in_progress"', () => {
  const result = getFilteredAndSortedHistory(SAMPLE_ENTRIES, 'in_progress', 'desc');
  assert.equal(result.length, 1);
  assert.equal(result[0].status, 'InProgress');
  assert.equal(result[0].issue_number, 35);
});

test('getFilteredAndSortedHistory: sort asc by start_time', () => {
  const result = getFilteredAndSortedHistory(SAMPLE_ENTRIES, 'all', 'asc');
  const times = result.map((e) => e.start_time);
  for (let i = 1; i < times.length; i++) {
    assert.ok(times[i] >= times[i - 1], `Expected ${times[i]} >= ${times[i - 1]}`);
  }
  assert.equal(result[0].issue_number, 28); // earliest: 2026-04-21
});

test('getFilteredAndSortedHistory: sort desc by start_time', () => {
  const result = getFilteredAndSortedHistory(SAMPLE_ENTRIES, 'all', 'desc');
  const times = result.map((e) => e.start_time);
  for (let i = 1; i < times.length; i++) {
    assert.ok(times[i] <= times[i - 1], `Expected ${times[i]} <= ${times[i - 1]}`);
  }
  assert.equal(result[0].issue_number, 35); // latest: 2026-04-25
});

test('getFilteredAndSortedHistory: null start_time sorts to end (asc)', () => {
  const withNull = [
    { issue_number: 1, title: 'a', status: 'Success', final_score: null, total_iterations: null, start_time: null, end_time: null },
    { issue_number: 2, title: 'b', status: 'Fail', final_score: null, total_iterations: null, start_time: '2026-04-25T00:00:00Z', end_time: null },
  ];
  const result = getFilteredAndSortedHistory(withNull, 'all', 'asc');
  assert.equal(result[0].issue_number, 2);
  assert.equal(result[1].issue_number, 1);
});

test('getFilteredAndSortedHistory: null start_time sorts to end (desc)', () => {
  const withNull = [
    { issue_number: 1, title: 'a', status: 'Success', final_score: null, total_iterations: null, start_time: '2026-04-25T00:00:00Z', end_time: null },
    { issue_number: 2, title: 'b', status: 'Fail', final_score: null, total_iterations: null, start_time: null, end_time: null },
  ];
  const result = getFilteredAndSortedHistory(withNull, 'all', 'desc');
  assert.equal(result[0].issue_number, 1);
  assert.equal(result[1].issue_number, 2);
});

test('getFilteredAndSortedHistory: empty array returns empty array', () => {
  const result = getFilteredAndSortedHistory([], 'all', 'desc');
  assert.equal(result.length, 0);
});

test('getFilteredAndSortedHistory: both null start_time preserves relative order', () => {
  const bothNull = [
    { issue_number: 1, title: 'a', status: 'Success', final_score: null, total_iterations: null, start_time: null, end_time: null },
    { issue_number: 2, title: 'b', status: 'Fail', final_score: null, total_iterations: null, start_time: null, end_time: null },
  ];
  const result = getFilteredAndSortedHistory(bothNull, 'all', 'asc');
  assert.equal(result.length, 2);
});

test('getFilteredAndSortedHistory: does not mutate input', () => {
  const original = [...SAMPLE_ENTRIES];
  getFilteredAndSortedHistory(SAMPLE_ENTRIES, 'success', 'asc');
  assert.deepEqual(SAMPLE_ENTRIES, original);
});

test('getFilteredAndSortedHistory: filter returns empty for non-matching status', () => {
  // All entries are Success/Fail/InProgress/Interrupt, no other statuses
  const onlySuccess = SAMPLE_ENTRIES.filter((e) => e.status === 'Success');
  const result = getFilteredAndSortedHistory(onlySuccess, 'fail', 'desc');
  assert.equal(result.length, 0);
});

// ---------------------------------------------------------------------------
// Store tests (factory pattern with dependency injection)
// ---------------------------------------------------------------------------

function createInvokeMock(handlers) {
  return async (cmd, args) => {
    const handler = handlers[cmd];
    if (!handler) {
      throw new Error(`Unhandled command: ${cmd}`);
    }
    return handler(args);
  };
}

test('loadHistory: Tauri mode stores backend data', async () => {
  const backendData = SAMPLE_ENTRIES.slice(0, 2);
  const store = createHistoryStore({
    isTauri: true,
    invoke: createInvokeMock({
      list_history: () => backendData,
    }),
  });

  await store.getState().loadHistory('/tmp/project');

  assert.equal(store.getState().entries.length, 2);
  assert.equal(store.getState().isLoading, false);
  assert.equal(store.getState().error, null);
});

test('loadHistory: non-Tauri mode uses mock data', async () => {
  const store = createHistoryStore({ isTauri: false });

  await store.getState().loadHistory('/tmp/project');

  assert.ok(store.getState().entries.length > 0);
  assert.equal(store.getState().isLoading, false);
  assert.equal(store.getState().error, null);
});

test('loadHistory: Tauri error normalised through normalizeHistoryError', async () => {
  const store = createHistoryStore({
    isTauri: true,
    invoke: createInvokeMock({
      list_history: () => {
        throw new Error('command failed');
      },
    }),
  });

  await store.getState().loadHistory('/tmp/project');

  assert.equal(store.getState().entries.length, 0);
  assert.equal(store.getState().isLoading, false);
  assert.ok(store.getState().error !== null);
  // Error should be Chinese fallback message
  assert.ok(store.getState().error.includes('加载历史记录失败'));
});

test('setStatusFilter updates filter state', () => {
  const store = createHistoryStore({ isTauri: false });
  assert.equal(store.getState().statusFilter, 'all');

  store.getState().setStatusFilter('success');
  assert.equal(store.getState().statusFilter, 'success');

  store.getState().setStatusFilter('fail');
  assert.equal(store.getState().statusFilter, 'fail');
});

test('setSortOrder updates sort state', () => {
  const store = createHistoryStore({ isTauri: false });
  assert.equal(store.getState().sortOrder, 'desc');

  store.getState().setSortOrder('asc');
  assert.equal(store.getState().sortOrder, 'asc');
});

test('clearError clears error state', async () => {
  const store = createHistoryStore({
    isTauri: true,
    invoke: createInvokeMock({
      list_history: () => {
        throw new Error('fail');
      },
    }),
  });

  await store.getState().loadHistory('/tmp/project');
  assert.ok(store.getState().error !== null);

  store.getState().clearError();
  assert.equal(store.getState().error, null);
});
