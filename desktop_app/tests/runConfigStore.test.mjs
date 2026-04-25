import test from 'node:test';
import assert from 'node:assert/strict';
import {
  createRunConfigStore,
  DEFAULT_CONTINUE_MODE,
  DEFAULT_MAX_ITERATIONS,
  DEFAULT_PASSING_SCORE,
  RUN_CONFIG_STORE_KEY,
  sanitizeRunConfig,
} from '../src/stores/runConfigStore.ts';

function createMemoryStorage(initialState = {}) {
  const data = new Map(Object.entries(initialState));

  return {
    getItem: (name) => data.get(name) ?? null,
    setItem: (name, value) => {
      data.set(name, value);
    },
    removeItem: (name) => {
      data.delete(name);
    },
    dump: () => Object.fromEntries(data.entries()),
  };
}

test('runConfigStore exposes required default values', () => {
  const storage = createMemoryStorage();
  const store = createRunConfigStore({ storage });

  assert.equal(store.getState().maxIterations, DEFAULT_MAX_ITERATIONS);
  assert.equal(store.getState().passingScore, DEFAULT_PASSING_SCORE);
  assert.equal(store.getState().continueMode, DEFAULT_CONTINUE_MODE);
});

test('runConfigStore clamps numeric setters to accepted ranges', () => {
  const storage = createMemoryStorage();
  const store = createRunConfigStore({ storage });

  store.getState().setMaxIterations(0);
  store.getState().setPassingScore(101);

  assert.equal(store.getState().maxIterations, 1);
  assert.equal(store.getState().passingScore, 100);

  store.getState().setMaxIterations(99);
  store.getState().setPassingScore(-20);

  assert.equal(store.getState().maxIterations, 50);
  assert.equal(store.getState().passingScore, 1);
});

test('runConfigStore normalizes decimal values to integers before persisting', () => {
  const storage = createMemoryStorage();
  const store = createRunConfigStore({ storage });

  store.getState().setMaxIterations(12.6);
  store.getState().setPassingScore(84.4);

  assert.equal(store.getState().maxIterations, 13);
  assert.equal(store.getState().passingScore, 84);

  const persisted = JSON.parse(storage.dump()[RUN_CONFIG_STORE_KEY]);

  assert.deepEqual(persisted.state, {
    maxIterations: 13,
    passingScore: 84,
    continueMode: DEFAULT_CONTINUE_MODE,
  });
});

test('runConfigStore persists values under the required storage key', () => {
  const storage = createMemoryStorage();
  const store = createRunConfigStore({ storage });

  store.getState().setMaxIterations(24);
  store.getState().setPassingScore(90);
  store.getState().setContinueMode(true);

  const persisted = JSON.parse(storage.dump()[RUN_CONFIG_STORE_KEY]);

  assert.deepEqual(persisted.state, {
    maxIterations: 24,
    passingScore: 90,
    continueMode: true,
  });
});

test('runConfigStore sanitizes persisted numeric values during hydration', async () => {
  const storage = createMemoryStorage({
    [RUN_CONFIG_STORE_KEY]: JSON.stringify({
      state: {
        maxIterations: -10,
        passingScore: 999,
        continueMode: true,
      },
      version: 0,
    }),
  });

  const store = createRunConfigStore({ storage });
  await store.persist.rehydrate();

  assert.equal(store.getState().maxIterations, 1);
  assert.equal(store.getState().passingScore, 100);
  assert.equal(store.getState().continueMode, true);
});

test('runConfigStore rounds persisted decimal values during hydration', async () => {
  const storage = createMemoryStorage({
    [RUN_CONFIG_STORE_KEY]: JSON.stringify({
      state: {
        maxIterations: 8.8,
        passingScore: 90.2,
        continueMode: false,
      },
      version: 0,
    }),
  });

  const store = createRunConfigStore({ storage });
  await store.persist.rehydrate();

  assert.equal(store.getState().maxIterations, 9);
  assert.equal(store.getState().passingScore, 90);
  assert.equal(store.getState().continueMode, false);
});

test('runConfigStore ignores NaN updates and preserves the previous valid values', () => {
  const storage = createMemoryStorage();
  const store = createRunConfigStore({ storage });

  store.getState().setMaxIterations(NaN);
  store.getState().setPassingScore(Number.NaN);
  store.getState().setContinueMode('true');

  assert.equal(store.getState().maxIterations, DEFAULT_MAX_ITERATIONS);
  assert.equal(store.getState().passingScore, DEFAULT_PASSING_SCORE);
  assert.equal(store.getState().continueMode, DEFAULT_CONTINUE_MODE);
});

test('sanitizeRunConfig rejects non-boolean and non-finite persisted values', () => {
  const sanitized = sanitizeRunConfig({
    maxIterations: Number.NaN,
    passingScore: Infinity,
    continueMode: 'false',
  });

  assert.deepEqual(sanitized, {
    maxIterations: DEFAULT_MAX_ITERATIONS,
    passingScore: DEFAULT_PASSING_SCORE,
    continueMode: DEFAULT_CONTINUE_MODE,
  });
});
