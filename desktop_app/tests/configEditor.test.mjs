import test from 'node:test';
import assert from 'node:assert/strict';
import {
  buildConfigEditorViewModel,
  buildBrowserFallback,
  clearConfigEditorFeedback,
  CONFIG_EDITOR_MESSAGES,
  configFileLabel,
  getConfigEditorMode,
  isConfigEditorInteractionLocked,
  loadConfigEditorFile,
  pendingProjectSwitchMessage,
  reloadConfigEditorFile,
  resetConfigEditorFile,
  resolveConfigEditorLoadPlan,
  resolveConfigEditorProjectPath,
  saveTargetPath,
  saveConfigEditorFile,
  shouldProceedWithPendingAction,
  sourceLabel,
  submitConfigEditorReset,
  submitConfigEditorSave,
  switchConfigEditorFile,
  unsavedChangesMessage,
} from '../src/pages/configEditor.ts';

test('browser fallback exposes default template metadata without pretending project persistence', () => {
  const config = buildBrowserFallback('agents/codex.md');

  assert.deepEqual(config, {
    file_id: 'agents/codex.md',
    relative_path: 'agents/codex.md',
    content: '# codex.md\n\n浏览器模式下仅展示本地占位内容。\n',
    source: 'default',
  });
});

test('config editor mode is read-only in browser fallback and writable with Tauri backend', () => {
  assert.deepEqual(getConfigEditorMode(false), {
    canPersist: false,
    readOnly: true,
    hint: '浏览器模式下仅支持查看占位内容，保存与重置需在桌面应用中进行。',
  });

  assert.deepEqual(getConfigEditorMode(true), {
    canPersist: true,
    readOnly: false,
    hint: '编辑器始终操作固定白名单文件，避免前端拼接任意路径。',
  });
});

test('config editor interactions lock while load/save/reset work is in flight', () => {
  assert.equal(isConfigEditorInteractionLocked(false, false, false), false);
  assert.equal(isConfigEditorInteractionLocked(true, false, false), true);
  assert.equal(isConfigEditorInteractionLocked(false, true, false), true);
  assert.equal(isConfigEditorInteractionLocked(false, false, true), true);
});

test('config editor helper labels source and save target consistently', () => {
  assert.equal(sourceLabel('project'), '项目覆写');
  assert.equal(sourceLabel('default'), '内置默认模板');
  assert.equal(configFileLabel('agents/claude.md'), 'Claude');
  assert.equal(
    saveTargetPath('/tmp/demo', 'agents/claude.md'),
    '/tmp/demo/.autoresearch/agents/claude.md'
  );
  assert.equal(
    saveTargetPath('C:\\demo', 'agents/claude.md'),
    'C:\\demo\\.autoresearch\\agents\\claude.md'
  );
  assert.equal(
    saveTargetPath('C:/demo', 'agents/claude.md'),
    'C:\\demo\\.autoresearch\\agents\\claude.md'
  );
});

test('pending project switch keeps the editor bound to the last loaded project path', () => {
  assert.equal(
    resolveConfigEditorProjectPath({
      projectPath: '/tmp/new-project',
      loadedProjectPath: '/tmp/loaded-project',
      pendingProjectPath: '/tmp/new-project',
    }),
    '/tmp/loaded-project'
  );

  assert.equal(
    resolveConfigEditorProjectPath({
      projectPath: '/tmp/current-project',
      loadedProjectPath: '/tmp/loaded-project',
      pendingProjectPath: null,
    }),
    '/tmp/current-project'
  );

  assert.equal(
    resolveConfigEditorProjectPath({
      projectPath: null,
      loadedProjectPath: '/tmp/loaded-project',
      pendingProjectPath: '/tmp/new-project',
    }),
    '/tmp/loaded-project'
  );
});

test('buildConfigEditorViewModel wires file switching, button disabled state, and editor updates', async () => {
  const calls = [];
  const confirmed = [];
  const view = buildConfigEditorViewModel({
    projectPath: '/tmp/demo',
    activeFileId: 'program.md',
    currentFile: {
      file_id: 'program.md',
      relative_path: 'program.md',
      content: 'old\n',
      source: 'project',
    },
    editorContent: 'draft\n',
    editorMode: getConfigEditorMode(true),
    isDirty: true,
    isLoading: false,
    isSaving: false,
    isResetting: false,
    isInteractionLocked: false,
    pendingProjectPath: '/tmp/next',
    clearFeedback: () => calls.push('clearFeedback'),
    clearStatusMessage: () => calls.push('clearStatus'),
    confirmPendingAction: (action) => {
      confirmed.push(action);
      return true;
    },
    setActiveFileId: (fileId) => calls.push(['setActiveFileId', fileId]),
    setEditorContent: (value) => calls.push(['setEditorContent', value]),
    onReload: () => {
      calls.push('reload');
      return true;
    },
    onSave: async () => {
      calls.push('save');
    },
    onReset: async () => {
      calls.push('reset');
    },
    onLoadPendingProject: () => calls.push('loadPendingProject'),
  });

  assert.equal(view.activeDefinition.label, 'program.md');
  assert.equal(view.currentSourceLabel, '项目覆写');
  assert.equal(view.savePath, '/tmp/demo/.autoresearch/program.md');
  assert.equal(view.saveDisabled, false);
  assert.equal(view.resetDisabled, false);
  assert.equal(view.reloadDisabled, false);
  assert.equal(view.editorDisabled, false);
  assert.equal(view.editorReadOnly, false);
  assert.equal(view.helperText, '编辑器始终操作固定白名单文件，避免前端拼接任意路径。');
  assert.equal(view.pendingProjectCallout?.message, pendingProjectSwitchMessage('/tmp/next'));
  assert.equal(
    view.pendingProjectCallout?.actionLabel,
    '放弃当前修改并加载新项目配置'
  );

  const codexTab = view.fileTabs.find((tab) => tab.id === 'agents/codex.md');
  assert.ok(codexTab);
  assert.equal(codexTab.selected, false);
  assert.equal(codexTab.disabled, false);
  codexTab.onSelect();
  view.onEditorChange('updated\n');
  view.pendingProjectCallout?.onConfirmDiscard();
  assert.equal(view.onReload(), true);
  await view.onSave();
  await view.onReset();

  assert.deepEqual(confirmed, [{ type: 'switch-file', nextFileId: 'agents/codex.md' }]);
  assert.deepEqual(calls, [
    ['setActiveFileId', 'agents/codex.md'],
    'clearFeedback',
    ['setEditorContent', 'updated\n'],
    'clearStatus',
    'loadPendingProject',
    'reload',
    'save',
    'reset',
  ]);
});

test('buildConfigEditorViewModel keeps controls locked while async work is in flight', () => {
  const calls = [];
  const view = buildConfigEditorViewModel({
    projectPath: '/tmp/demo',
    activeFileId: 'agents/claude.md',
    currentFile: null,
    editorContent: '',
    editorMode: getConfigEditorMode(false),
    isDirty: false,
    isLoading: true,
    isSaving: false,
    isResetting: false,
    isInteractionLocked: true,
    pendingProjectPath: null,
    clearFeedback: () => calls.push('clearFeedback'),
    clearStatusMessage: () => calls.push('clearStatus'),
    confirmPendingAction: () => {
      throw new Error('should not confirm while locked');
    },
    setActiveFileId: (fileId) => calls.push(['setActiveFileId', fileId]),
    setEditorContent: (value) => calls.push(['setEditorContent', value]),
    onReload: () => {
      calls.push('reload');
      return false;
    },
    onSave: async () => {
      calls.push('save');
    },
    onReset: async () => {
      calls.push('reset');
    },
    onLoadPendingProject: () => calls.push('loadPendingProject'),
  });

  assert.equal(view.currentSourceLabel, '加载中');
  assert.equal(
    view.savePath,
    '/tmp/demo/.autoresearch/agents/claude.md'
  );
  assert.equal(view.saveDisabled, true);
  assert.equal(view.resetDisabled, true);
  assert.equal(view.reloadDisabled, true);
  assert.equal(view.editorDisabled, true);
  assert.equal(view.editorReadOnly, true);
  assert.equal(view.helperText, '正在加载配置文件内容...');
  assert.equal(view.pendingProjectCallout, null);
  assert.ok(view.fileTabs.every((tab) => tab.disabled));

  view.fileTabs[2].onSelect();
  assert.deepEqual(calls, []);
});

test('buildConfigEditorViewModel keeps editor read-only after a load failure', () => {
  const calls = [];
  const view = buildConfigEditorViewModel({
    projectPath: '/tmp/demo',
    activeFileId: 'program.md',
    currentFile: null,
    editorContent: '',
    editorMode: getConfigEditorMode(true),
    isDirty: false,
    isLoading: false,
    isSaving: false,
    isResetting: false,
    isInteractionLocked: false,
    pendingProjectPath: null,
    clearFeedback: () => calls.push('clearFeedback'),
    clearStatusMessage: () => calls.push('clearStatus'),
    confirmPendingAction: () => true,
    setActiveFileId: (fileId) => calls.push(['setActiveFileId', fileId]),
    setEditorContent: (value) => calls.push(['setEditorContent', value]),
    onReload: () => {
      calls.push('reload');
      return true;
    },
    onSave: async () => {
      calls.push('save');
    },
    onReset: async () => {
      calls.push('reset');
    },
    onLoadPendingProject: () => calls.push('loadPendingProject'),
  });

  assert.equal(view.currentSourceLabel, '加载失败');
  assert.equal(view.saveDisabled, true);
  assert.equal(view.resetDisabled, false);
  assert.equal(view.reloadDisabled, false);
  assert.equal(view.editorDisabled, true);
  assert.equal(view.editorReadOnly, true);
  assert.equal(view.helperText, '配置文件尚未加载成功，可重新加载或重置为默认值。');
  assert.ok(view.fileTabs.every((tab) => tab.disabled === false));
});

test('unsaved changes warnings describe the pending action clearly', () => {
  assert.equal(
    unsavedChangesMessage({ type: 'reload' }),
    '当前文件有未保存修改，重新加载会丢失这些内容。要继续吗？'
  );
  assert.equal(
    unsavedChangesMessage({ type: 'reset' }),
    '当前文件有未保存修改，重置为默认值会丢失这些内容。要继续吗？'
  );
  assert.equal(
    unsavedChangesMessage({ type: 'switch-file', nextFileId: 'agents/codex.md' }),
    '当前文件有未保存修改，切换到 Codex 会丢失这些内容。要继续吗？'
  );
});

test('dirty-state guard bypasses confirm when clean and defers to confirm when dirty', () => {
  const prompts = [];
  const confirmDiscard = (message) => {
    prompts.push(message);
    return false;
  };

  assert.equal(
    shouldProceedWithPendingAction(false, { type: 'reload' }, confirmDiscard),
    true
  );
  assert.deepEqual(prompts, []);

  assert.equal(
    shouldProceedWithPendingAction(
      true,
      { type: 'switch-file', nextFileId: 'program.md' },
      confirmDiscard
    ),
    false
  );
  assert.deepEqual(prompts, [
    '当前文件有未保存修改，切换到 program.md 会丢失这些内容。要继续吗？',
  ]);

  assert.equal(
    shouldProceedWithPendingAction(true, { type: 'reload' }, () => true),
    true
  );
  assert.equal(
    shouldProceedWithPendingAction(true, { type: 'reset' }, confirmDiscard),
    false
  );
  assert.deepEqual(prompts, [
    '当前文件有未保存修改，切换到 program.md 会丢失这些内容。要继续吗？',
    '当前文件有未保存修改，重置为默认值会丢失这些内容。要继续吗？',
  ]);
});

test('clearConfigEditorFeedback resets both error and status message', () => {
  const updates = [];

  clearConfigEditorFeedback({
    setError: (value) => updates.push(['error', value]),
    setStatusMessage: (value) => updates.push(['status', value]),
  });

  assert.deepEqual(updates, [
    ['error', null],
    ['status', null],
  ]);
});

test('switchConfigEditorFile only updates selection after dirty-state confirmation passes', () => {
  const actions = [];
  const confirmed = [];

  assert.equal(
    switchConfigEditorFile({
      activeFileId: 'program.md',
      nextFileId: 'agents/codex.md',
      isInteractionLocked: true,
      confirmPendingAction: () => {
        throw new Error('should not confirm while locked');
      },
      clearFeedback: () => actions.push('clear'),
      setActiveFileId: (fileId) => actions.push(['set', fileId]),
    }),
    false
  );

  assert.equal(
    switchConfigEditorFile({
      activeFileId: 'program.md',
      nextFileId: 'program.md',
      isInteractionLocked: false,
      confirmPendingAction: () => {
        throw new Error('should not confirm current file');
      },
      clearFeedback: () => actions.push('clear'),
      setActiveFileId: (fileId) => actions.push(['set', fileId]),
    }),
    false
  );

  assert.equal(
    switchConfigEditorFile({
      activeFileId: 'program.md',
      nextFileId: 'agents/codex.md',
      isInteractionLocked: false,
      confirmPendingAction: (action) => {
        confirmed.push(action);
        return false;
      },
      clearFeedback: () => actions.push('clear'),
      setActiveFileId: (fileId) => actions.push(['set', fileId]),
    }),
    false
  );

  assert.equal(
    switchConfigEditorFile({
      activeFileId: 'program.md',
      nextFileId: 'agents/codex.md',
      isInteractionLocked: false,
      confirmPendingAction: (action) => {
        confirmed.push(action);
        return true;
      },
      clearFeedback: () => actions.push('clear'),
      setActiveFileId: (fileId) => actions.push(['set', fileId]),
    }),
    true
  );

  assert.deepEqual(confirmed, [
    { type: 'switch-file', nextFileId: 'agents/codex.md' },
    { type: 'switch-file', nextFileId: 'agents/codex.md' },
  ]);
  assert.deepEqual(actions, [['set', 'agents/codex.md'], 'clear']);
});

test('reloadConfigEditorFile respects project selection and dirty-state confirmation', () => {
  const actions = [];
  const confirmed = [];

  assert.equal(
    reloadConfigEditorFile({
      projectPath: '/tmp/demo',
      isInteractionLocked: true,
      confirmPendingAction: () => {
        throw new Error('should not confirm while locked');
      },
      clearFeedback: () => actions.push('clear'),
      bumpReloadKey: () => actions.push('reload'),
    }),
    false
  );

  assert.equal(
    reloadConfigEditorFile({
      projectPath: null,
      isInteractionLocked: false,
      confirmPendingAction: () => {
        throw new Error('should not confirm without project');
      },
      clearFeedback: () => actions.push('clear'),
      bumpReloadKey: () => actions.push('reload'),
    }),
    false
  );

  assert.equal(
    reloadConfigEditorFile({
      projectPath: '/tmp/demo',
      isInteractionLocked: false,
      confirmPendingAction: (action) => {
        confirmed.push(action);
        return false;
      },
      clearFeedback: () => actions.push('clear'),
      bumpReloadKey: () => actions.push('reload'),
    }),
    false
  );

  assert.equal(
    reloadConfigEditorFile({
      projectPath: '/tmp/demo',
      isInteractionLocked: false,
      confirmPendingAction: (action) => {
        confirmed.push(action);
        return true;
      },
      clearFeedback: () => actions.push('clear'),
      bumpReloadKey: () => actions.push('reload'),
    }),
    true
  );

  assert.deepEqual(confirmed, [{ type: 'reload' }, { type: 'reload' }]);
  assert.deepEqual(actions, ['reload', 'clear']);
});

test('resolveConfigEditorLoadPlan blocks dirty project switches until discard is confirmed', () => {
  const prompts = [];

  assert.deepEqual(
    resolveConfigEditorLoadPlan({
      projectPath: null,
      loadedProjectPath: '/tmp/old',
      isDirty: true,
      confirmDiscard: () => {
        throw new Error('should not confirm when project is cleared');
      },
    }),
    { type: 'clear' }
  );

  assert.deepEqual(
    resolveConfigEditorLoadPlan({
      projectPath: '/tmp/new',
      loadedProjectPath: '/tmp/old',
      isDirty: false,
      confirmDiscard: () => {
        throw new Error('clean switch should not confirm');
      },
    }),
    { type: 'load', projectPath: '/tmp/new' }
  );

  assert.deepEqual(
    resolveConfigEditorLoadPlan({
      projectPath: '/tmp/new',
      loadedProjectPath: '/tmp/old',
      isDirty: true,
      confirmDiscard: (message) => {
        prompts.push(message);
        return false;
      },
    }),
    {
      type: 'block-project-switch',
      nextProjectPath: '/tmp/new',
      statusMessage: pendingProjectSwitchMessage('/tmp/new'),
    }
  );

  assert.deepEqual(prompts, [
    '当前文件有未保存修改，切换到项目 /tmp/new 会丢失这些内容。要继续吗？',
  ]);

  assert.deepEqual(
    resolveConfigEditorLoadPlan({
      projectPath: '/tmp/new',
      loadedProjectPath: '/tmp/old',
      isDirty: true,
      confirmDiscard: () => true,
    }),
    { type: 'load', projectPath: '/tmp/new' }
  );
});

test('loadConfigEditorFile reads from tauri backend when available and falls back in browser mode', async () => {
  const readCalls = [];

  const tauriConfig = await loadConfigEditorFile({
    fileId: 'program.md',
    hasTauriBackend: true,
    readConfigFile: async (fileId) => {
      readCalls.push(fileId);
      return {
        file_id: fileId,
        relative_path: fileId,
        content: 'project content\n',
        source: 'project',
      };
    },
  });

  assert.equal(tauriConfig.content, 'project content\n');
  assert.deepEqual(readCalls, ['program.md']);

  const browserConfig = await loadConfigEditorFile({
    fileId: 'agents/opencode.md',
    hasTauriBackend: false,
    readConfigFile: async () => {
      throw new Error('should not be called');
    },
  });

  assert.deepEqual(browserConfig, {
    file_id: 'agents/opencode.md',
    relative_path: 'agents/opencode.md',
    content: '# opencode.md\n\n浏览器模式下仅展示本地占位内容。\n',
    source: 'default',
  });
});

test('saveConfigEditorFile persists through injected writer and refreshes project config', async () => {
  const calls = [];
  const editorMode = getConfigEditorMode(true);

  const result = await saveConfigEditorFile({
    fileId: 'agents/claude.md',
    content: 'updated claude\n',
    editorMode,
    writeConfigFile: async (fileId, content) => {
      calls.push(['write', fileId, content]);
      return {
        file_id: fileId,
        relative_path: fileId,
        content,
        source: 'project',
      };
    },
    refreshConfig: async () => {
      calls.push(['refresh']);
    },
  });

  assert.deepEqual(calls, [
    ['write', 'agents/claude.md', 'updated claude\n'],
    ['refresh'],
  ]);
  assert.equal(result.statusMessage, CONFIG_EDITOR_MESSAGES.saveSuccess);
  assert.equal(result.config.source, 'project');
});

test('submitConfigEditorSave drives saving state, persistence, and success feedback', async () => {
  const calls = [];
  const editorMode = getConfigEditorMode(true);

  const succeeded = await submitConfigEditorSave({
    projectPath: '/tmp/demo',
    currentFile: {
      file_id: 'agents/claude.md',
      relative_path: 'agents/claude.md',
      content: 'old\n',
      source: 'project',
    },
    fileId: 'agents/claude.md',
    content: 'new\n',
    editorMode,
    writeConfigFile: async (fileId, content) => {
      calls.push(['write', fileId, content]);
      return {
        file_id: fileId,
        relative_path: fileId,
        content,
        source: 'project',
      };
    },
    refreshConfig: async () => {
      calls.push(['refresh']);
    },
    setIsSaving: (value) => calls.push(['saving', value]),
    setCurrentFile: (value) => calls.push(['current', value.content]),
    setEditorContent: (value) => calls.push(['editor', value]),
    normalizeError: () => 'unexpected',
    feedback: {
      setError: (value) => calls.push(['error', value]),
      setStatusMessage: (value) => calls.push(['status', value]),
    },
  });

  assert.equal(succeeded, true);
  assert.deepEqual(calls, [
    ['saving', true],
    ['error', null],
    ['status', null],
    ['write', 'agents/claude.md', 'new\n'],
    ['refresh'],
    ['current', 'new\n'],
    ['editor', 'new\n'],
    ['status', CONFIG_EDITOR_MESSAGES.saveSuccess],
    ['saving', false],
  ]);
});

test('submitConfigEditorSave surfaces normalized errors from the SettingsPage save flow', async () => {
  const calls = [];
  const editorMode = getConfigEditorMode(true);

  const succeeded = await submitConfigEditorSave({
    projectPath: '/tmp/demo',
    currentFile: buildBrowserFallback('program.md'),
    fileId: 'program.md',
    content: 'new\n',
    editorMode,
    writeConfigFile: async () => {
      throw new Error('disk full');
    },
    refreshConfig: async () => {
      calls.push(['refresh']);
    },
    setIsSaving: (value) => calls.push(['saving', value]),
    setCurrentFile: (value) => calls.push(['current', value.content]),
    setEditorContent: (value) => calls.push(['editor', value]),
    normalizeError: (error, fallback) => `${fallback}:${error.message}`,
    feedback: {
      setError: (value) => calls.push(['error', value]),
      setStatusMessage: (value) => calls.push(['status', value]),
    },
  });

  assert.equal(succeeded, false);
  assert.deepEqual(calls, [
    ['saving', true],
    ['error', null],
    ['status', null],
    ['error', '保存配置失败，请重试。:disk full'],
    ['saving', false],
  ]);
});

test('saveConfigEditorFile refuses browser fallback persistence without invoking side effects', async () => {
  const editorMode = getConfigEditorMode(false);
  const calls = [];

  await assert.rejects(
    saveConfigEditorFile({
      fileId: 'program.md',
      content: 'value',
      editorMode,
      writeConfigFile: async () => {
        calls.push('write');
        return buildBrowserFallback('program.md');
      },
      refreshConfig: async () => {
        calls.push('refresh');
      },
    }),
    /浏览器模式下仅支持查看占位内容，保存与重置需在桌面应用中进行。/
  );

  assert.deepEqual(calls, []);
});

test('resetConfigEditorFile persists default content and refreshes project config', async () => {
  const calls = [];
  const editorMode = getConfigEditorMode(true);

  const result = await resetConfigEditorFile({
    fileId: 'agents/codex.md',
    editorMode,
    resetConfigFile: async (fileId) => {
      calls.push(['reset', fileId]);
      return {
        file_id: fileId,
        relative_path: fileId,
        content: 'default codex\n',
        source: 'project',
      };
    },
    refreshConfig: async () => {
      calls.push(['refresh']);
    },
  });

  assert.deepEqual(calls, [
    ['reset', 'agents/codex.md'],
    ['refresh'],
  ]);
  assert.equal(result.statusMessage, CONFIG_EDITOR_MESSAGES.resetSuccess);
  assert.equal(result.config.content, 'default codex\n');
});

test('submitConfigEditorReset drives confirm, reset, refresh, and feedback sequencing', async () => {
  const calls = [];
  const editorMode = getConfigEditorMode(true);
  const confirmed = [];

  const succeeded = await submitConfigEditorReset({
    projectPath: '/tmp/demo',
    confirmPendingAction: (action) => {
      confirmed.push(action);
      return true;
    },
    fileId: 'agents/codex.md',
    editorMode,
    resetConfigFile: async (fileId) => {
      calls.push(['reset', fileId]);
      return {
        file_id: fileId,
        relative_path: fileId,
        content: 'default codex\n',
        source: 'project',
      };
    },
    refreshConfig: async () => {
      calls.push(['refresh']);
    },
    setIsResetting: (value) => calls.push(['resetting', value]),
    setCurrentFile: (value) => calls.push(['current', value.content]),
    setEditorContent: (value) => calls.push(['editor', value]),
    normalizeError: () => 'unexpected',
    feedback: {
      setError: (value) => calls.push(['error', value]),
      setStatusMessage: (value) => calls.push(['status', value]),
    },
  });

  assert.equal(succeeded, true);
  assert.deepEqual(confirmed, [{ type: 'reset' }]);
  assert.deepEqual(calls, [
    ['resetting', true],
    ['error', null],
    ['status', null],
    ['reset', 'agents/codex.md'],
    ['refresh'],
    ['current', 'default codex\n'],
    ['editor', 'default codex\n'],
    ['status', CONFIG_EDITOR_MESSAGES.resetSuccess],
    ['resetting', false],
  ]);
});

test('submitConfigEditorReset stops before side effects when destructive action is cancelled', async () => {
  const calls = [];

  const succeeded = await submitConfigEditorReset({
    projectPath: '/tmp/demo',
    confirmPendingAction: (action) => {
      calls.push(['confirm', action]);
      return false;
    },
    fileId: 'agents/codex.md',
    editorMode: getConfigEditorMode(true),
    resetConfigFile: async () => {
      calls.push(['reset']);
      return buildBrowserFallback('agents/codex.md');
    },
    refreshConfig: async () => {
      calls.push(['refresh']);
    },
    setIsResetting: (value) => calls.push(['resetting', value]),
    setCurrentFile: (value) => calls.push(['current', value.content]),
    setEditorContent: (value) => calls.push(['editor', value]),
    normalizeError: () => 'unexpected',
    feedback: {
      setError: (value) => calls.push(['error', value]),
      setStatusMessage: (value) => calls.push(['status', value]),
    },
  });

  assert.equal(succeeded, false);
  assert.deepEqual(calls, [['confirm', { type: 'reset' }]]);
});
