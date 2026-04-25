import test from 'node:test';
import assert from 'node:assert/strict';
import { createRunStore } from '../src/stores/runStore.ts';

function createInvokeMock(handlers) {
  return async (cmd) => {
    const handler = handlers[cmd];
    if (!handler) {
      throw new Error(`Unhandled command: ${cmd}`);
    }
    return handler();
  };
}

test('startRun clears unknown active issue when backend already has another task', async () => {
  const store = createRunStore({
    isTauri: true,
    invoke: createInvokeMock({
      start_run: () => {
        throw new Error('A run is already in progress.');
      },
      get_run_status: () => 'Running',
    }),
    listen: async () => () => {},
    getSelectedAgents: () => [],
  });

  await store.getState().startRun({
    projectPath: '/tmp/project',
    issueNumber: 28,
  });

  assert.equal(store.getState().status, 'running');
  assert.equal(store.getState().activeIssueNumber, null);
  assert.equal(store.getState().error, 'A run is already in progress.');
});

test('startRun restores previous running issue when stop/start race fails', async () => {
  const store = createRunStore({
    isTauri: true,
    invoke: createInvokeMock({
      start_run: () => {
        throw new Error('A run is already in progress.');
      },
      get_run_status: () => 'Running',
    }),
    listen: async () => () => {},
    getSelectedAgents: () => [],
  });

  store.setState({
    status: 'running',
    activeIssueNumber: 7,
    outputLines: ['existing output'],
    exitCode: null,
    error: null,
  });

  await store.getState().startRun({
    projectPath: '/tmp/project',
    issueNumber: 28,
  });

  assert.equal(store.getState().status, 'running');
  assert.equal(store.getState().activeIssueNumber, 7);
  assert.deepEqual(store.getState().outputLines, ['existing output']);
});

test('initialize wires run events and caps output history', async () => {
  const listeners = new Map();
  const store = createRunStore({
    isTauri: true,
    invoke: createInvokeMock({
      get_run_status: () => 'Idle',
    }),
    listen: async (event, callback) => {
      listeners.set(event, callback);
      return () => {
        listeners.delete(event);
      };
    },
    getSelectedAgents: () => [],
  });

  await store.getState().initialize();

  const outputListener = listeners.get('run-output');
  const exitListener = listeners.get('run-exit');

  assert.ok(outputListener);
  assert.ok(exitListener);

  for (let index = 0; index < 2005; index += 1) {
    outputListener({ payload: `line-${index}` });
  }

  exitListener({ payload: { exit_code: 2, killed: false } });

  assert.equal(store.getState().outputLines.length, 2000);
  assert.equal(store.getState().outputLines[0], 'line-5');
  assert.equal(store.getState().outputLines[store.getState().outputLines.length - 1], 'line-2004');
  assert.equal(store.getState().status, 'error');
  assert.equal(store.getState().exitCode, 2);
  assert.equal(store.getState().error, '运行失败 (exit code 2)');
});
