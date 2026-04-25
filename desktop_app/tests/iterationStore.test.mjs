import test from 'node:test';
import assert from 'node:assert/strict';
import { createIterationStore, IDLE_PROGRESS } from '../src/stores/iterationStore.ts';

function createDeferred() {
  let resolve;
  let reject;
  const promise = new Promise((res, rej) => {
    resolve = res;
    reject = rej;
  });
  return { promise, resolve, reject };
}

function createInvokeMock(handlers) {
  return async (cmd, args) => {
    const handler = handlers[cmd];
    if (!handler) {
      throw new Error(`Unhandled command: ${cmd}`);
    }
    return handler(args);
  };
}

const SAMPLE_PROGRESS = {
  current_iteration: 3,
  total_iterations: 16,
  phase: 'Review',
  subtasks: [
    { id: 'T-001', title: 'Backend data model', status: 'passing' },
    { id: 'T-002', title: 'File watcher', status: 'passing' },
    { id: 'T-003', title: 'Frontend UI', status: 'failing' },
  ],
  passed_count: 2,
  total_count: 3,
  last_score: 78,
  passing_score: 85,
  review_summary: 'Code quality needs improvement',
};

test('watchIssue stores iteration data from backend', async () => {
  const store = createIterationStore({
    isTauri: true,
    invoke: createInvokeMock({
      get_iteration_progress: () => SAMPLE_PROGRESS,
    }),
    listen: async () => () => {},
  });

  await store.getState().watchIssue('/tmp/project', 31);

  const state = store.getState();
  assert.equal(state.progress.current_iteration, 3);
  assert.equal(state.progress.total_iterations, 16);
  assert.equal(state.progress.phase, 'Review');
  assert.equal(state.progress.subtasks.length, 3);
  assert.equal(state.progress.subtasks[2].status, 'failing');
  assert.equal(state.isLoading, false);
  assert.equal(state.error, null);
});

test('initialize wires iteration-progress event and applies matching payload', async () => {
  let eventListener = null;
  const store = createIterationStore({
    isTauri: true,
    invoke: createInvokeMock({
      get_iteration_progress: () => SAMPLE_PROGRESS,
    }),
    listen: async (_event, callback) => {
      eventListener = callback;
      return () => {};
    },
  });

  await store.getState().initialize();
  await store.getState().watchIssue('/tmp/project', 31);

  eventListener({
    payload: {
      issue_number: 31,
      progress: {
        ...SAMPLE_PROGRESS,
        current_iteration: 4,
        phase: 'BuildLintTest',
      },
    },
  });

  const state = store.getState();
  assert.equal(state.progress.current_iteration, 4);
  assert.equal(state.progress.phase, 'BuildLintTest');
  assert.equal(state.error, null);
});

test('iteration-progress event ignores other issues', async () => {
  let eventListener = null;
  const store = createIterationStore({
    isTauri: true,
    invoke: createInvokeMock({
      get_iteration_progress: () => SAMPLE_PROGRESS,
    }),
    listen: async (_event, callback) => {
      eventListener = callback;
      return () => {};
    },
  });

  await store.getState().initialize();
  await store.getState().watchIssue('/tmp/project', 31);

  eventListener({
    payload: {
      issue_number: 99,
      progress: {
        ...SAMPLE_PROGRESS,
        current_iteration: 10,
      },
    },
  });

  assert.equal(store.getState().progress.current_iteration, 3);
});

test('watchIssue ignores stale responses after switching issues', async () => {
  const first = createDeferred();
  const second = createDeferred();
  const store = createIterationStore({
    isTauri: true,
    invoke: async (_cmd, args) => {
      if (args.issueNumber === 31) {
        return first.promise;
      }
      return second.promise;
    },
    listen: async () => () => {},
  });

  const firstPromise = store.getState().watchIssue('/tmp/project', 31);
  const secondPromise = store.getState().watchIssue('/tmp/project', 32);

  second.resolve({
    ...SAMPLE_PROGRESS,
    current_iteration: 9,
  });
  await secondPromise;

  first.resolve({
    ...SAMPLE_PROGRESS,
    current_iteration: 1,
  });
  await firstPromise;

  const state = store.getState();
  assert.equal(state.currentIssueNumber, 32);
  assert.equal(state.progress.current_iteration, 9);
});

test('watchIssue sets error on backend failure', async () => {
  const store = createIterationStore({
    isTauri: true,
    invoke: createInvokeMock({
      get_iteration_progress: () => {
        throw new Error('Workflow dir not found');
      },
    }),
    listen: async () => () => {},
  });

  await store.getState().watchIssue('/tmp/project', 99);

  const state = store.getState();
  assert.equal(state.error, 'Workflow dir not found');
  assert.equal(state.isLoading, false);
  assert.deepEqual(state.progress, IDLE_PROGRESS);
});

test('watchIssue is a no-op when isTauri is false', async () => {
  const invoked = [];
  const store = createIterationStore({
    isTauri: false,
    invoke: async (cmd) => {
      invoked.push(cmd);
      return {};
    },
    listen: async () => () => {},
  });

  await store.getState().watchIssue('/tmp/project', 31);

  assert.equal(invoked.length, 0);
  assert.equal(store.getState().progress.phase, 'Idle');
});

test('reset restores idle state and invalidates in-flight requests', async () => {
  const deferred = createDeferred();
  const store = createIterationStore({
    isTauri: true,
    invoke: async () => deferred.promise,
    listen: async () => () => {},
  });

  const pending = store.getState().watchIssue('/tmp/project', 31);
  store.getState().reset();
  deferred.resolve(SAMPLE_PROGRESS);
  await pending;

  const state = store.getState();
  assert.equal(state.currentIssueNumber, null);
  assert.deepEqual(state.progress, IDLE_PROGRESS);
  assert.equal(state.error, null);
});
