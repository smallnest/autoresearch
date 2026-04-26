import test from 'node:test';
import assert from 'node:assert/strict';
import { createAgentStore, AVAILABLE_AGENTS } from '../src/stores/agentStore.ts';

// In-memory storage to suppress zustand persist warnings in Node.js
function createInMemoryStorage() {
  const map = new Map();
  return {
    getItem: (name) => map.get(name) ?? null,
    setItem: (name, value) => map.set(name, value),
    removeItem: (name) => map.delete(name),
  };
}

function makeDetectResult({ gh = true, claude = true, codex = false, opencode = false } = {}) {
  return {
    gh: { installed: gh, path: gh ? '/usr/local/bin/gh' : null },
    claude: { installed: claude, path: claude ? '/usr/local/bin/claude' : null },
    codex: { installed: codex, path: codex ? '/usr/local/bin/codex' : null },
    opencode: { installed: opencode, path: opencode ? '/usr/local/bin/opencode' : null },
  };
}

function createInvokeMock(detectResult) {
  return async (cmd) => {
    if (cmd === 'detect_cli_tools') return detectResult;
    throw new Error(`Unhandled command: ${cmd}`);
  };
}

// Helper to create store with a fresh in-memory storage each time
function createStore(overrides = {}) {
  return createAgentStore({ storage: createInMemoryStorage(), ...overrides });
}

test('initializeFromDetection sets ghInstalled to false when gh is missing', async () => {
  const store = createStore({
    isTauri: true,
    invoke: createInvokeMock(makeDetectResult({ gh: false, claude: true, codex: false, opencode: false })),
  });

  await store.getState().initializeFromDetection();

  assert.equal(store.getState().ghInstalled, false);
  assert.equal(store.getState().selectedAgents.length, 1);
  assert.equal(store.getState().selectedAgents[0], 'claude');
  assert.equal(store.getState().detectionDone, true);
});

test('initializeFromDetection selects no agents when none are installed', async () => {
  const store = createStore({
    isTauri: true,
    invoke: createInvokeMock(makeDetectResult({ gh: true, claude: false, codex: false, opencode: false })),
  });

  await store.getState().initializeFromDetection();

  assert.deepEqual(store.getState().selectedAgents, []);
  assert.equal(store.getState().installedAgents.claude.installed, false);
  assert.equal(store.getState().installedAgents.codex.installed, false);
  assert.equal(store.getState().installedAgents.opencode.installed, false);
  assert.equal(store.getState().detectionDone, true);
});

test('initializeFromDetection auto-selects installed agents on first launch', async () => {
  const store = createStore({
    isTauri: true,
    invoke: createInvokeMock(makeDetectResult({ gh: true, claude: true, codex: true, opencode: false })),
  });

  await store.getState().initializeFromDetection();

  assert.deepEqual(store.getState().selectedAgents, ['claude', 'codex']);
  assert.equal(store.getState().ghInstalled, true);
  assert.equal(store.getState().isDetecting, false);
  assert.equal(store.getState().detectionDone, true);
  assert.equal(store.getState().installedAgents.claude.installed, true);
  assert.equal(store.getState().installedAgents.opencode.installed, false);
});

test('initializeFromDetection preserves user selection on non-first launch', async () => {
  const store = createStore({
    isTauri: true,
    invoke: createInvokeMock(makeDetectResult({ gh: true, claude: true, codex: true, opencode: true })),
  });

  // Simulate first launch to populate installedAgents
  await store.getState().initializeFromDetection();
  // Auto-selected all three: ['claude', 'codex', 'opencode']

  // User deselects claude, keeps codex + opencode
  store.getState().toggleAgent('claude'); // remove claude
  assert.deepEqual(store.getState().selectedAgents, ['codex', 'opencode']);

  // Re-detect (e.g. app restart or manual refresh)
  await store.getState().initializeFromDetection();

  // User selection preserved
  assert.deepEqual(store.getState().selectedAgents, ['codex', 'opencode']);
});

test('initializeFromDetection does not corrupt state on detection failure', async () => {
  const store = createStore({
    isTauri: true,
    invoke: async () => { throw new Error('detection failed'); },
  });

  // Set some initial state
  store.setState({ ghInstalled: true, installedAgents: { claude: { installed: true, path: '/bin/claude' } } });

  await store.getState().initializeFromDetection();

  // Existing state preserved, loading stopped
  assert.equal(store.getState().ghInstalled, true);
  assert.equal(store.getState().installedAgents.claude.installed, true);
  assert.equal(store.getState().isDetecting, false);
  assert.equal(store.getState().detectionDone, true);
});

test('initializeFromDetection is no-op in non-Tauri environment', async () => {
  const store = createStore({
    isTauri: false,
    invoke: createInvokeMock(makeDetectResult()),
  });

  await store.getState().initializeFromDetection();

  assert.equal(store.getState().isDetecting, false);
  assert.equal(store.getState().detectionDone, false);
  assert.deepEqual(store.getState().installedAgents, {});
});

test('selectAll only selects installed agents', async () => {
  const store = createStore({
    isTauri: true,
    invoke: createInvokeMock(makeDetectResult({ gh: true, claude: true, codex: false, opencode: true })),
  });

  await store.getState().initializeFromDetection();

  // Clear selection, then selectAll
  store.getState().clearAll();
  assert.deepEqual(store.getState().selectedAgents, []);

  store.getState().selectAll();
  assert.deepEqual(store.getState().selectedAgents, ['claude', 'opencode']);
});

test('toggleAgent does not allow adding uninstalled agent', async () => {
  const store = createStore({
    isTauri: true,
    invoke: createInvokeMock(makeDetectResult({ gh: true, claude: true, codex: false, opencode: false })),
  });

  await store.getState().initializeFromDetection();

  // codex is not installed, toggle should be rejected
  store.getState().toggleAgent('codex');
  assert.deepEqual(store.getState().selectedAgents, ['claude']);

  // opencode is not installed, toggle should be rejected
  store.getState().toggleAgent('opencode');
  assert.deepEqual(store.getState().selectedAgents, ['claude']);
});

test('toggleAgent allows removing an installed selected agent', async () => {
  const store = createStore({
    isTauri: true,
    invoke: createInvokeMock(makeDetectResult({ gh: true, claude: true, codex: true, opencode: false })),
  });

  await store.getState().initializeFromDetection();
  assert.deepEqual(store.getState().selectedAgents, ['claude', 'codex']);

  // Remove claude (installed and selected)
  store.getState().toggleAgent('claude');
  assert.deepEqual(store.getState().selectedAgents, ['codex']);
});

test('toggleAgent allows adding an installed unselected agent', async () => {
  const store = createStore({
    isTauri: true,
    invoke: createInvokeMock(makeDetectResult({ gh: true, claude: true, codex: true, opencode: false })),
  });

  await store.getState().initializeFromDetection();

  // Remove claude first, then add it back
  store.getState().toggleAgent('claude');
  assert.deepEqual(store.getState().selectedAgents, ['codex']);

  store.getState().toggleAgent('claude');
  assert.deepEqual(store.getState().selectedAgents, ['codex', 'claude']);
});

test('reorderAgents moves agent from one position to another', async () => {
  const store = createStore({
    isTauri: true,
    invoke: createInvokeMock(makeDetectResult({ gh: true, claude: true, codex: true, opencode: true })),
  });

  await store.getState().initializeFromDetection();
  assert.deepEqual(store.getState().selectedAgents, ['claude', 'codex', 'opencode']);

  // Move opencode (index 2) to index 0
  store.getState().reorderAgents(2, 0);
  assert.deepEqual(store.getState().selectedAgents, ['opencode', 'claude', 'codex']);
});

test('reorderAgents ignores invalid indices', async () => {
  const store = createStore({
    isTauri: true,
    invoke: createInvokeMock(makeDetectResult({ gh: true, claude: true, codex: true, opencode: true })),
  });

  await store.getState().initializeFromDetection();
  const before = [...store.getState().selectedAgents];

  store.getState().reorderAgents(-1, 0);
  assert.deepEqual(store.getState().selectedAgents, before);

  store.getState().reorderAgents(0, 99);
  assert.deepEqual(store.getState().selectedAgents, before);
});

test('isSelected returns correct boolean', async () => {
  const store = createStore({
    isTauri: true,
    invoke: createInvokeMock(makeDetectResult({ gh: true, claude: true, codex: false, opencode: false })),
  });

  await store.getState().initializeFromDetection();

  assert.equal(store.getState().isSelected('claude'), true);
  assert.equal(store.getState().isSelected('codex'), false);
});

test('getSelectedAgentsInfo returns metadata for selected agents', async () => {
  const store = createStore({
    isTauri: true,
    invoke: createInvokeMock(makeDetectResult({ gh: true, claude: true, codex: true, opencode: false })),
  });

  await store.getState().initializeFromDetection();

  const info = store.getState().getSelectedAgentsInfo();
  assert.equal(info.length, 2);
  assert.equal(info[0].id, 'claude');
  assert.equal(info[1].id, 'codex');
});

test('initializeFromDetection sets isDetecting during detection', async () => {
  let resolveDetection;
  const invoke = async (cmd) => {
    if (cmd === 'detect_cli_tools') {
      return new Promise((resolve) => {
        resolveDetection = () => resolve(makeDetectResult({ gh: true, claude: true }));
      });
    }
    throw new Error(`Unhandled command: ${cmd}`);
  };

  const store = createStore({ isTauri: true, invoke });

  const detectionPromise = store.getState().initializeFromDetection();
  assert.equal(store.getState().isDetecting, true);

  resolveDetection();
  await detectionPromise;

  assert.equal(store.getState().isDetecting, false);
  assert.equal(store.getState().detectionDone, true);
});

test('AVAILABLE_AGENTS lists exactly three agents', () => {
  assert.deepEqual([...AVAILABLE_AGENTS], ['claude', 'codex', 'opencode']);
});
