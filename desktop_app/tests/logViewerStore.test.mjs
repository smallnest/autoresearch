import test from 'node:test';
import assert from 'node:assert/strict';
import {
  buildLogEntries,
  classifyLogLevel,
  createLogViewerStore,
  filterLogEntries,
} from '../src/stores/logViewerStore.ts';

function createInvokeMock(handlers) {
  return async (cmd) => {
    const handler = handlers[cmd];
    if (!handler) {
      throw new Error(`Unhandled command: ${cmd}`);
    }
    return handler();
  };
}

test('classifyLogLevel detects info, warn, and error lines', () => {
  assert.equal(classifyLogLevel('[2026-04-25 09:21:17] 调用 codex'), 'info');
  assert.equal(classifyLogLevel('Warning: retrying request'), 'warn');
  assert.equal(classifyLogLevel('❌ 构建失败'), 'error');
});

test('filterLogEntries applies search query and level filters together', () => {
  const entries = buildLogEntries('start\nWarning: retry\nbuild failed');
  const filtered = filterLogEntries(entries, 'retry', {
    info: true,
    warn: true,
    error: false,
  });

  assert.deepEqual(
    filtered.map((entry) => entry.text),
    ['Warning: retry']
  );
});

test('loadSources prepends live output and prefers terminal log when not running', async () => {
  const store = createLogViewerStore({
    isTauri: true,
    invoke: createInvokeMock({
      list_issue_log_sources: () => [
        {
          id: 'iteration-2-codex-review.log',
          label: 'iteration-2-codex-review.log',
          kind: 'iteration',
          updated_at: '10',
          size_bytes: 10,
        },
        {
          id: 'terminal.log',
          label: '终端日志',
          kind: 'terminal',
          updated_at: '20',
          size_bytes: 20,
        },
      ],
    }),
  });

  await store.getState().loadSources('/tmp/project', 30, { preferLive: false });

  assert.deepEqual(
    store.getState().sources.map((source) => source.id),
    ['live-output', 'iteration-2-codex-review.log', 'terminal.log']
  );
  assert.equal(store.getState().selectedSourceId, 'terminal.log');
});

test('loadSources prefers live output for active issue and refreshSelectedSource caches content', async () => {
  const store = createLogViewerStore({
    isTauri: true,
    invoke: createInvokeMock({
      list_issue_log_sources: () => [
        {
          id: 'terminal.log',
          label: '终端日志',
          kind: 'terminal',
          updated_at: '20',
          size_bytes: 20,
        },
      ],
      read_issue_log_content: () => ({
        source_id: 'terminal.log',
        text: 'line one\nline two',
        updated_at: '30',
      }),
    }),
  });

  await store.getState().loadSources('/tmp/project', 30, { preferLive: true });
  assert.equal(store.getState().selectedSourceId, 'live-output');

  store.getState().selectSource('terminal.log');
  await store.getState().refreshSelectedSource('/tmp/project', 30);

  assert.equal(
    store.getState().sourceContents['terminal.log'].text,
    'line one\nline two'
  );
});

test('loadSources preserves viewer state while refreshing the same issue', async () => {
  const store = createLogViewerStore({
    isTauri: true,
    invoke: createInvokeMock({
      list_issue_log_sources: () => [
        {
          id: 'terminal.log',
          label: '终端日志',
          kind: 'terminal',
          updated_at: '20',
          size_bytes: 20,
        },
        {
          id: 'iteration-2-codex-review.log',
          label: 'iteration-2-codex-review.log',
          kind: 'iteration',
          updated_at: '30',
          size_bytes: 30,
        },
      ],
    }),
  });

  await store.getState().loadSources('/tmp/project', 30, { preferLive: false });
  store.getState().selectSource('iteration-2-codex-review.log');
  store.getState().setSearchQuery('failed');
  store.getState().setAutoScroll(false);
  store.getState().markScrollPending(true);

  await store.getState().loadSources('/tmp/project', 30, { preferLive: false });

  assert.equal(store.getState().selectedSourceId, 'iteration-2-codex-review.log');
  assert.equal(store.getState().searchQuery, 'failed');
  assert.equal(store.getState().autoScroll, false);
  assert.equal(store.getState().hasPendingScroll, true);
});

test('loadSources preserves an explicit live-output selection while refreshing the same issue', async () => {
  const store = createLogViewerStore({
    isTauri: true,
    invoke: createInvokeMock({
      list_issue_log_sources: () => [
        {
          id: 'terminal.log',
          label: '终端日志',
          kind: 'terminal',
          updated_at: '20',
          size_bytes: 20,
        },
      ],
    }),
  });

  await store.getState().loadSources('/tmp/project', 30, { preferLive: false });
  assert.equal(store.getState().selectedSourceId, 'terminal.log');

  store.getState().selectSource('live-output');
  await store.getState().loadSources('/tmp/project', 30, { preferLive: false });

  assert.equal(store.getState().selectedSourceId, 'live-output');
});

test('loadSources ignores a stale response from a previous issue', async () => {
  let resolveIssue30;
  const issue30Promise = new Promise((resolve) => {
    resolveIssue30 = resolve;
  });

  const store = createLogViewerStore({
    isTauri: true,
    invoke: async (cmd, args) => {
      assert.equal(cmd, 'list_issue_log_sources');

      if (args.issueNumber === 30) {
        return issue30Promise;
      }

      if (args.issueNumber === 31) {
        return [
          {
            id: 'iteration-31-codex.log',
            label: 'iteration-31-codex.log',
            kind: 'iteration',
            updated_at: '31',
            size_bytes: 31,
          },
        ];
      }

      throw new Error(`Unexpected issue number: ${args.issueNumber}`);
    },
  });

  const firstLoad = store.getState().loadSources('/tmp/project', 30, {
    preferLive: false,
  });
  await store.getState().loadSources('/tmp/project', 31, {
    preferLive: false,
  });

  resolveIssue30([
    {
      id: 'iteration-30-codex.log',
      label: 'iteration-30-codex.log',
      kind: 'iteration',
      updated_at: '30',
      size_bytes: 30,
    },
  ]);
  await firstLoad;

  assert.equal(store.getState().currentIssueNumber, 31);
  assert.deepEqual(
    store.getState().sources.map((source) => source.id),
    ['live-output', 'iteration-31-codex.log']
  );
});

test('refreshSelectedSource ignores a stale response from a previous issue', async () => {
  let resolveIssue30;
  const issue30Promise = new Promise((resolve) => {
    resolveIssue30 = resolve;
  });

  const store = createLogViewerStore({
    isTauri: true,
    invoke: async (cmd, args) => {
      if (cmd === 'list_issue_log_sources') {
        return [
          {
            id: 'terminal.log',
            label: '终端日志',
            kind: 'terminal',
            updated_at: String(args.issueNumber),
            size_bytes: 20,
          },
        ];
      }

      assert.equal(cmd, 'read_issue_log_content');
      if (args.issueNumber === 30) {
        return issue30Promise;
      }

      if (args.issueNumber === 31) {
        return {
          source_id: 'terminal.log',
          text: 'issue 31 line',
          updated_at: '31',
        };
      }

      throw new Error(`Unexpected issue number: ${args.issueNumber}`);
    },
  });

  await store.getState().loadSources('/tmp/project', 30, { preferLive: false });
  store.getState().selectSource('terminal.log');
  const issue30Refresh = store.getState().refreshSelectedSource('/tmp/project', 30);

  await store.getState().loadSources('/tmp/project', 31, { preferLive: false });
  store.getState().selectSource('terminal.log');
  await store.getState().refreshSelectedSource('/tmp/project', 31);

  resolveIssue30({
    source_id: 'terminal.log',
    text: 'issue 30 line',
    updated_at: '30',
  });
  await issue30Refresh;

  assert.equal(store.getState().currentIssueNumber, 31);
  assert.equal(store.getState().sourceContents['terminal.log'].text, 'issue 31 line');
});

test('toggleLevel keeps at least one log level enabled', () => {
  const store = createLogViewerStore({
    isTauri: false,
    invoke: async () => {
      throw new Error('invoke should not be called');
    },
  });

  store.getState().toggleLevel('info');
  store.getState().toggleLevel('warn');
  store.getState().toggleLevel('error');

  assert.deepEqual(store.getState().levelFilters, {
    info: false,
    warn: false,
    error: true,
  });
});

test('buildLogEntries truncates to last 5000 lines for large input', () => {
  const lineCount = 6000;
  const lines = Array.from({ length: lineCount }, (_, i) => `line ${i + 1}`);
  const text = lines.join('\n');
  const entries = buildLogEntries(text);

  assert.equal(entries.length, 5000);
  assert.equal(entries[0].lineNumber, 1001);
  assert.equal(entries[0].text, 'line 1001');
  assert.equal(entries[entries.length - 1].lineNumber, 6000);
  assert.equal(entries[entries.length - 1].text, 'line 6000');
});

test('buildLogEntries keeps all lines when under 5000', () => {
  const entries = buildLogEntries('a\nb\nc');
  assert.equal(entries.length, 3);
  assert.equal(entries[0].lineNumber, 1);
  assert.equal(entries[2].lineNumber, 3);
});
