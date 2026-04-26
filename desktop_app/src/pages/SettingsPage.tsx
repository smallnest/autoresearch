import { useEffect, useRef, useState } from 'react';
import AgentSelector from '../components/AgentSelector';
import RunConfigPanel from '../components/RunConfigPanel';
import { useProjectStore } from '../stores/projectStore';
import { useRunConfigStore } from '../stores/runConfigStore';
import { normalizeUserFacingError } from '../stores/uiError';
import {
  buildConfigEditorViewModel,
  clearConfigEditorFeedback,
  CONFIG_EDITOR_MESSAGES,
  type ConfigEditorPendingAction,
  type ConfigFileContent,
  type ConfigFileId,
  getConfigEditorMode,
  isConfigEditorInteractionLocked,
  loadConfigEditorFile,
  reloadConfigEditorFile,
  resolveConfigEditorLoadPlan,
  resolveConfigEditorProjectPath,
  submitConfigEditorReset,
  submitConfigEditorSave,
  shouldProceedWithPendingAction,
} from './configEditor';

const isTauri = typeof window !== 'undefined' && '__TAURI_INTERNALS__' in window;

async function tauriInvoke<T>(cmd: string, args?: Record<string, unknown>): Promise<T> {
  const { invoke } = await import('@tauri-apps/api/core');
  return invoke<T>(cmd, args);
}

function SettingsPage() {
  const { projectPath, refreshConfig } = useProjectStore();
  const { notificationsEnabled, setNotificationsEnabled } = useRunConfigStore();
  const [activeFileId, setActiveFileId] = useState<ConfigFileId>('program.md');
  const [currentFile, setCurrentFile] = useState<ConfigFileContent | null>(null);
  const [editorContent, setEditorContent] = useState('');
  const [isLoading, setIsLoading] = useState(false);
  const [isSaving, setIsSaving] = useState(false);
  const [isResetting, setIsResetting] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [statusMessage, setStatusMessage] = useState<string | null>(null);
  const [reloadKey, setReloadKey] = useState(0);
  const [runConfigCollapsed, setRunConfigCollapsed] = useState(false);
  const [pendingProjectPath, setPendingProjectPath] = useState<string | null>(null);
  const loadedProjectPathRef = useRef<string | null>(null);
  const isDirtyRef = useRef(false);

  const isDirty = currentFile !== null && editorContent !== currentFile.content;
  const editorMode = getConfigEditorMode(isTauri);
  const isProjectSwitchPending = pendingProjectPath !== null;
  const effectiveProjectPath = resolveConfigEditorProjectPath({
    projectPath,
    loadedProjectPath: loadedProjectPathRef.current,
    pendingProjectPath,
  });
  const isInteractionLocked =
    isProjectSwitchPending ||
    isConfigEditorInteractionLocked(isLoading, isSaving, isResetting);

  const confirmPendingAction = (action: ConfigEditorPendingAction) =>
    shouldProceedWithPendingAction(isDirty, action, (message) => window.confirm(message));
  const feedback = { setError, setStatusMessage };
  const clearFeedback = () => clearConfigEditorFeedback(feedback);

  useEffect(() => {
    isDirtyRef.current = isDirty;
  }, [isDirty]);

  useEffect(() => {
    let cancelled = false;

    async function loadConfigFile() {
      const loadPlan = resolveConfigEditorLoadPlan({
        projectPath,
        loadedProjectPath: loadedProjectPathRef.current,
        isDirty: isDirtyRef.current,
        confirmDiscard: (message) => window.confirm(message),
      });

      if (loadPlan.type === 'clear') {
        loadedProjectPathRef.current = null;
        setPendingProjectPath(null);
        setCurrentFile(null);
        setEditorContent('');
        setError(null);
        setStatusMessage(null);
        return;
      }

      if (loadPlan.type === 'block-project-switch') {
        setPendingProjectPath(loadPlan.nextProjectPath);
        setError(null);
        setStatusMessage(loadPlan.statusMessage);
        return;
      }

      setPendingProjectPath(null);
      setIsLoading(true);
      setError(null);
      setStatusMessage(null);

      try {
        const config = await loadConfigEditorFile({
          fileId: activeFileId,
          hasTauriBackend: isTauri,
          readConfigFile: (fileId) =>
            tauriInvoke<ConfigFileContent>('read_config_file', {
              projectPath: loadPlan.projectPath,
              fileId,
            }),
        });

        if (!cancelled) {
          loadedProjectPathRef.current = loadPlan.projectPath;
          setCurrentFile(config);
          setEditorContent(config.content);
        }
      } catch (loadError) {
        if (!cancelled) {
          setCurrentFile(null);
          setEditorContent('');
          setError(normalizeUserFacingError(loadError, CONFIG_EDITOR_MESSAGES.loadError));
        }
      } finally {
        if (!cancelled) {
          setIsLoading(false);
        }
      }
    }

    void loadConfigFile();

    return () => {
      cancelled = true;
    };
  }, [activeFileId, projectPath, reloadKey]);

  const handleSave = async () => {
    await submitConfigEditorSave({
      projectPath: effectiveProjectPath,
      currentFile,
      fileId: activeFileId,
      content: editorContent,
      editorMode,
      writeConfigFile: (fileId, content) =>
        tauriInvoke<ConfigFileContent>('write_config_file', {
          projectPath: effectiveProjectPath,
          fileId,
          content,
        }),
      refreshConfig: () => refreshConfig(effectiveProjectPath ?? undefined),
      setIsSaving,
      setCurrentFile,
      setEditorContent,
      normalizeError: normalizeUserFacingError,
      feedback,
    });
  };

  const handleReset = async () => {
    await submitConfigEditorReset({
      projectPath: effectiveProjectPath,
      confirmPendingAction,
      fileId: activeFileId,
      editorMode,
      resetConfigFile: (fileId) =>
        tauriInvoke<ConfigFileContent>('reset_config_file', {
          projectPath: effectiveProjectPath,
          fileId,
        }),
      refreshConfig: () => refreshConfig(effectiveProjectPath ?? undefined),
      setIsResetting,
      setCurrentFile,
      setEditorContent,
      normalizeError: normalizeUserFacingError,
      feedback,
    });
  };

  const handleReload = () =>
    reloadConfigEditorFile({
      projectPath: effectiveProjectPath,
      isInteractionLocked,
      confirmPendingAction,
      clearFeedback,
      bumpReloadKey: () => setReloadKey((value) => value + 1),
    });

  const handleLoadPendingProject = () => {
    if (!pendingProjectPath) {
      return;
    }

    loadedProjectPathRef.current = pendingProjectPath;
    setPendingProjectPath(null);
    setCurrentFile(null);
    setEditorContent('');
    setError(null);
    setStatusMessage(null);
    setReloadKey((value) => value + 1);
  };

  const configEditorView = effectiveProjectPath
    ? buildConfigEditorViewModel({
        projectPath: effectiveProjectPath,
        activeFileId,
        currentFile,
        editorContent,
        editorMode,
        isDirty,
        isLoading,
        isSaving,
        isResetting,
        isInteractionLocked,
        pendingProjectPath,
        clearFeedback,
        clearStatusMessage: () => setStatusMessage(null),
        confirmPendingAction,
        setActiveFileId,
        setEditorContent,
        onReload: handleReload,
        onSave: handleSave,
        onReset: handleReset,
        onLoadPendingProject: handleLoadPendingProject,
      })
    : null;

  return (
    <div className="p-6 space-y-8">
      <div>
        <h1 className="text-2xl font-bold mb-4">设置</h1>
        <p className="text-gray-500 mb-6">配置应用偏好与 Agent 选择顺序。</p>
      </div>

      <section className="bg-white border border-gray-200 rounded-xl shadow-sm">
        <div className="p-6 border-b border-gray-200">
          <h2 className="text-lg font-semibold mb-2">配置文件编辑器</h2>
          <p className="text-sm text-gray-500">
            编辑 `program.md` 与各 Agent 指令文件。保存后会写入当前项目的
            `.autoresearch/` 目录，并在覆盖前自动创建 `.bak` 备份。
          </p>
        </div>

        {!projectPath ? (
          <div className="p-6 text-sm text-amber-800 bg-amber-50 rounded-b-xl">
            请先在概览页选择项目目录，然后再编辑配置文件。
          </div>
        ) : (
          <div className="p-6 space-y-4">
            <div className="flex flex-wrap gap-3">
              {configEditorView?.fileTabs.map((file) => (
                <button
                  key={file.id}
                  type="button"
                  onClick={file.onSelect}
                  disabled={file.disabled}
                  className={`px-4 py-2 rounded-lg border text-left transition-colors ${
                    file.selected
                      ? 'bg-blue-50 border-blue-300 text-blue-700'
                      : 'bg-gray-50 border-gray-200 text-gray-600 hover:bg-gray-100'
                  } disabled:opacity-60 disabled:cursor-not-allowed`}
                >
                  <div className="text-sm font-medium">{file.label}</div>
                  <div className="text-xs opacity-80">{file.description}</div>
                </button>
              ))}
            </div>

            <div className="grid gap-3 md:grid-cols-2">
              <div className="rounded-lg bg-gray-50 border border-gray-200 px-4 py-3">
                <div className="text-xs uppercase tracking-wide text-gray-400 mb-1">
                  当前来源
                </div>
                <div className="text-sm text-gray-700">
                  {configEditorView?.currentSourceLabel}
                </div>
              </div>
              <div className="rounded-lg bg-gray-50 border border-gray-200 px-4 py-3">
                <div className="text-xs uppercase tracking-wide text-gray-400 mb-1">
                  写入位置
                </div>
                <div className="text-sm text-gray-700 break-all">
                  {configEditorView?.savePath}
                </div>
              </div>
            </div>

            {error && (
              <div className="rounded-lg border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-700">
                {error}
              </div>
            )}

            {statusMessage && (
              <div className="rounded-lg border border-green-200 bg-green-50 px-4 py-3 text-sm text-green-700">
                {statusMessage}
              </div>
            )}

            {configEditorView?.pendingProjectCallout && (
              <div className="rounded-lg border border-amber-200 bg-amber-50 px-4 py-3 text-sm text-amber-900 space-y-3">
                <p>{configEditorView.pendingProjectCallout.message}</p>
                <button
                  type="button"
                  onClick={configEditorView.pendingProjectCallout.onConfirmDiscard}
                  className="px-4 py-2 rounded-lg border border-amber-300 bg-white text-amber-900 hover:bg-amber-100"
                >
                  {configEditorView.pendingProjectCallout.actionLabel}
                </button>
              </div>
            )}

            {!editorMode.canPersist && (
              <div className="rounded-lg border border-amber-200 bg-amber-50 px-4 py-3 text-sm text-amber-800">
                {editorMode.hint}
              </div>
            )}

            <div className="flex flex-wrap gap-3">
                <button
                  type="button"
                  onClick={configEditorView?.onReload}
                  disabled={configEditorView?.reloadDisabled}
                  className="px-4 py-2 rounded-lg border border-gray-200 bg-white text-gray-700 hover:bg-gray-50 disabled:opacity-60"
                >
                  重新加载
                </button>
              <button
                type="button"
                onClick={configEditorView?.onSave}
                disabled={configEditorView?.saveDisabled}
                className="px-4 py-2 rounded-lg bg-blue-600 text-white hover:bg-blue-500 disabled:bg-gray-300 disabled:cursor-not-allowed"
              >
                {isSaving ? '保存中...' : '保存配置'}
              </button>
              <button
                type="button"
                onClick={configEditorView?.onReset}
                disabled={configEditorView?.resetDisabled}
                className="px-4 py-2 rounded-lg border border-gray-200 bg-white text-gray-700 hover:bg-gray-50 disabled:opacity-60"
              >
                {isResetting ? '重置中...' : '重置为默认值'}
              </button>
            </div>

            <label className="block">
              <span className="block text-sm font-medium text-gray-700 mb-2">
                {configEditorView?.activeDefinition.label}
              </span>
              <textarea
                value={configEditorView?.editorValue}
                onChange={(event) => {
                  configEditorView?.onEditorChange(event.target.value);
                }}
                spellCheck={false}
                disabled={configEditorView?.editorDisabled}
                readOnly={configEditorView?.editorReadOnly}
                className="w-full min-h-[420px] rounded-xl border border-gray-200 bg-gray-950 text-gray-100 font-mono text-sm leading-6 p-4 focus:outline-none focus:ring-2 focus:ring-blue-500 disabled:opacity-60"
              />
            </label>

            <p className="text-xs text-gray-500">
              {configEditorView?.helperText}
            </p>
          </div>
        )}
      </section>

      <section className="max-w-3xl bg-white border border-gray-200 rounded-xl shadow-sm">
        <div className="p-6 border-b border-gray-200">
          <h2 className="text-lg font-semibold mb-2">运行参数</h2>
          <p className="text-sm text-gray-500">
            在设置页集中调整 passing score、最大迭代次数与继续模式。
          </p>
        </div>
        <div className="p-6">
          <RunConfigPanel
            collapsed={runConfigCollapsed}
            onCollapsedChange={setRunConfigCollapsed}
          />
        </div>
      </section>

      <section className="max-w-3xl bg-white border border-gray-200 rounded-xl shadow-sm">
        <div className="p-6 border-b border-gray-200">
          <h2 className="text-lg font-semibold mb-2">通知设置</h2>
          <p className="text-sm text-gray-500">
            控制是否在任务完成、质量通过或失败时发送系统通知。
          </p>
        </div>
        <div className="p-6">
          <div className="flex items-center justify-between">
            <div>
              <label
                htmlFor="notificationsEnabled"
                className="text-sm font-medium text-gray-700"
              >
                系统通知
              </label>
              <p className="text-xs text-gray-500">
                {notificationsEnabled ? '通知已开启' : '通知已关闭'}
              </p>
            </div>
            <button
              type="button"
              id="notificationsEnabled"
              role="switch"
              aria-checked={notificationsEnabled}
              onClick={() => setNotificationsEnabled(!notificationsEnabled)}
              className={`relative inline-flex h-6 w-11 flex-shrink-0 cursor-pointer rounded-full border-2 border-transparent transition-colors duration-200 ease-in-out focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-offset-2 ${
                notificationsEnabled ? 'bg-blue-600' : 'bg-gray-200'
              }`}
            >
              <span
                className={`pointer-events-none inline-block h-5 w-5 transform rounded-full bg-white shadow ring-0 transition duration-200 ease-in-out ${
                  notificationsEnabled ? 'translate-x-5' : 'translate-x-0'
                }`}
              />
            </button>
          </div>
        </div>
      </section>

      <section className="max-w-3xl bg-white border border-gray-200 rounded-xl shadow-sm">
        <div className="p-6 border-b border-gray-200">
          <h2 className="text-lg font-semibold mb-2">Agent 配置</h2>
          <p className="text-sm text-gray-500">
            调整默认 Agent 选择顺序，运行参数面板会复用这里的排列结果。
          </p>
        </div>
        <div className="p-6">
          <AgentSelector />
        </div>
      </section>
    </div>
  );
}

export default SettingsPage;
