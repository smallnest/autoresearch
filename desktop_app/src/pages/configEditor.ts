export type ConfigFileId =
  | 'program.md'
  | 'agents/claude.md'
  | 'agents/codex.md'
  | 'agents/opencode.md';

export interface ConfigFileContent {
  file_id: ConfigFileId;
  relative_path: string;
  content: string;
  source: 'default' | 'project' | string;
}

export interface ConfigFileDefinition {
  id: ConfigFileId;
  label: string;
  description: string;
}

export interface ConfigEditorMode {
  canPersist: boolean;
  readOnly: boolean;
  hint: string;
}

export interface ConfigEditorMessages {
  loadError: string;
  saveError: string;
  resetError: string;
  saveSuccess: string;
  resetSuccess: string;
}

export interface ConfigEditorFileTab {
  id: ConfigFileId;
  label: string;
  description: string;
  selected: boolean;
  disabled: boolean;
  onSelect: () => void;
}

export interface ConfigEditorPendingProjectCallout {
  nextProjectPath: string;
  message: string;
  actionLabel: string;
  onConfirmDiscard: () => void;
}

export interface ConfigEditorViewModel {
  activeDefinition: ConfigFileDefinition;
  fileTabs: ConfigEditorFileTab[];
  currentSourceLabel: string;
  savePath: string;
  saveDisabled: boolean;
  resetDisabled: boolean;
  reloadDisabled: boolean;
  editorDisabled: boolean;
  editorReadOnly: boolean;
  editorValue: string;
  helperText: string;
  pendingProjectCallout: ConfigEditorPendingProjectCallout | null;
  onReload: () => boolean;
  onSave: () => Promise<void>;
  onReset: () => Promise<void>;
  onEditorChange: (value: string) => void;
}

const CONFIG_EDITOR_LOAD_FAILURE_HINT =
  '配置文件尚未加载成功，可重新加载或重置为默认值。';

export interface LoadConfigFileOptions {
  fileId: ConfigFileId;
  hasTauriBackend: boolean;
  readConfigFile: (_fileId: ConfigFileId) => Promise<ConfigFileContent>;
}

export interface PersistConfigFileOptions {
  fileId: ConfigFileId;
  editorMode: ConfigEditorMode;
  refreshConfig: () => Promise<void>;
}

export interface SaveConfigFileOptions extends PersistConfigFileOptions {
  content: string;
  writeConfigFile: (
    _fileId: ConfigFileId,
    _content: string
  ) => Promise<ConfigFileContent>;
}

export interface ResetConfigFileOptions extends PersistConfigFileOptions {
  resetConfigFile: (_fileId: ConfigFileId) => Promise<ConfigFileContent>;
}

export interface PersistConfigFileResult {
  config: ConfigFileContent;
  statusMessage: string;
}

export interface ConfigEditorFeedbackHandlers {
  setError: (value: string | null) => void;
  setStatusMessage: (value: string | null) => void;
}

export type ConfigEditorPendingAction =
  | { type: 'reload' }
  | { type: 'reset' }
  | { type: 'switch-file'; nextFileId: ConfigFileId }
  | { type: 'switch-project'; nextProjectPath: string };

export type ConfigEditorLoadPlan =
  | { type: 'clear' }
  | { type: 'load'; projectPath: string }
  | {
      type: 'block-project-switch';
      nextProjectPath: string;
      statusMessage: string;
    };

export interface SwitchConfigEditorFileOptions {
  activeFileId: ConfigFileId;
  nextFileId: ConfigFileId;
  isInteractionLocked: boolean;
  confirmPendingAction: (action: ConfigEditorPendingAction) => boolean;
  clearFeedback: () => void;
  setActiveFileId: (fileId: ConfigFileId) => void;
}

export interface ReloadConfigEditorFileOptions {
  projectPath: string | null;
  isInteractionLocked: boolean;
  confirmPendingAction: (action: ConfigEditorPendingAction) => boolean;
  clearFeedback: () => void;
  bumpReloadKey: () => void;
}

export interface SubmitConfigEditorSaveOptions extends SaveConfigFileOptions {
  projectPath: string | null;
  currentFile: ConfigFileContent | null;
  setIsSaving: (value: boolean) => void;
  setCurrentFile: (value: ConfigFileContent) => void;
  setEditorContent: (value: string) => void;
  normalizeError: (error: unknown, fallbackMessage: string) => string;
  feedback: ConfigEditorFeedbackHandlers;
}

export interface SubmitConfigEditorResetOptions extends ResetConfigFileOptions {
  projectPath: string | null;
  confirmPendingAction: (action: ConfigEditorPendingAction) => boolean;
  setIsResetting: (value: boolean) => void;
  setCurrentFile: (value: ConfigFileContent) => void;
  setEditorContent: (value: string) => void;
  normalizeError: (error: unknown, fallbackMessage: string) => string;
  feedback: ConfigEditorFeedbackHandlers;
}

export interface BuildConfigEditorViewModelOptions {
  projectPath: string;
  activeFileId: ConfigFileId;
  currentFile: ConfigFileContent | null;
  editorContent: string;
  editorMode: ConfigEditorMode;
  isDirty: boolean;
  isLoading: boolean;
  isSaving: boolean;
  isResetting: boolean;
  isInteractionLocked: boolean;
  pendingProjectPath: string | null;
  clearFeedback: () => void;
  clearStatusMessage: () => void;
  confirmPendingAction: (action: ConfigEditorPendingAction) => boolean;
  setActiveFileId: (fileId: ConfigFileId) => void;
  setEditorContent: (value: string) => void;
  onReload: () => boolean;
  onSave: () => Promise<void>;
  onReset: () => Promise<void>;
  onLoadPendingProject: () => void;
}

export function resolveConfigEditorProjectPath({
  projectPath,
  loadedProjectPath,
  pendingProjectPath,
}: {
  projectPath: string | null;
  loadedProjectPath: string | null;
  pendingProjectPath: string | null;
}): string | null {
  if (pendingProjectPath && loadedProjectPath) {
    return loadedProjectPath;
  }

  return projectPath;
}

export const CONFIG_FILES: ConfigFileDefinition[] = [
  {
    id: 'program.md',
    label: 'program.md',
    description: '实现规范与通用约束',
  },
  {
    id: 'agents/claude.md',
    label: 'Claude',
    description: 'Claude agent 指令',
  },
  {
    id: 'agents/codex.md',
    label: 'Codex',
    description: 'Codex agent 指令',
  },
  {
    id: 'agents/opencode.md',
    label: 'OpenCode',
    description: 'OpenCode agent 指令',
  },
];

const BROWSER_FALLBACK_CONTENT: Record<ConfigFileId, string> = {
  'program.md': '# program.md\n\n浏览器模式下无法读取本地项目配置。\n',
  'agents/claude.md': '# claude.md\n\n浏览器模式下仅展示本地占位内容。\n',
  'agents/codex.md': '# codex.md\n\n浏览器模式下仅展示本地占位内容。\n',
  'agents/opencode.md': '# opencode.md\n\n浏览器模式下仅展示本地占位内容。\n',
};

export const CONFIG_EDITOR_MESSAGES: ConfigEditorMessages = {
  loadError: '加载配置文件失败，请重试。',
  saveError: '保存配置失败，请重试。',
  resetError: '重置配置失败，请重试。',
  saveSuccess: '配置已保存，后续运行将使用新的项目覆写文件。',
  resetSuccess: '配置已重置为默认模板。',
};

export function buildBrowserFallback(fileId: ConfigFileId): ConfigFileContent {
  return {
    file_id: fileId,
    relative_path: fileId,
    content: BROWSER_FALLBACK_CONTENT[fileId],
    source: 'default',
  };
}

export function sourceLabel(source: string): string {
  return source === 'project' ? '项目覆写' : '内置默认模板';
}

export function saveTargetPath(projectPath: string, relativePath: string): string {
  const separator =
    projectPath.includes('\\') || /^[A-Za-z]:/.test(projectPath) ? '\\' : '/';
  const trimmedProjectPath = projectPath.replace(/[\\/]+$/, '');
  const normalizedProjectPath = trimmedProjectPath.replace(/[\\/]+/g, separator);
  const normalizedRelativePath = relativePath.replace(/[\\/]+/g, separator);
  return `${normalizedProjectPath}${separator}.autoresearch${separator}${normalizedRelativePath}`;
}

export function configFileLabel(fileId: ConfigFileId): string {
  return CONFIG_FILES.find((file) => file.id === fileId)?.label ?? fileId;
}

export function unsavedChangesMessage(action: ConfigEditorPendingAction): string {
  if (action.type === 'reload') {
    return '当前文件有未保存修改，重新加载会丢失这些内容。要继续吗？';
  }

  if (action.type === 'reset') {
    return '当前文件有未保存修改，重置为默认值会丢失这些内容。要继续吗？';
  }

  if (action.type === 'switch-project') {
    return `当前文件有未保存修改，切换到项目 ${action.nextProjectPath} 会丢失这些内容。要继续吗？`;
  }

  return `当前文件有未保存修改，切换到 ${configFileLabel(
    action.nextFileId
  )} 会丢失这些内容。要继续吗？`;
}

export function pendingProjectSwitchMessage(nextProjectPath: string): string {
  return `已保留当前未保存内容。确认放弃后，再加载项目 ${nextProjectPath} 的配置。`;
}

export function shouldProceedWithPendingAction(
  isDirty: boolean,
  action: ConfigEditorPendingAction,
  confirmDiscard: (message: string) => boolean
): boolean {
  if (!isDirty) {
    return true;
  }

  return confirmDiscard(unsavedChangesMessage(action));
}

export function clearConfigEditorFeedback({
  setError,
  setStatusMessage,
}: ConfigEditorFeedbackHandlers): void {
  setError(null);
  setStatusMessage(null);
}

export function isConfigEditorInteractionLocked(
  isLoading: boolean,
  isSaving: boolean,
  isResetting: boolean
): boolean {
  return isLoading || isSaving || isResetting;
}

export function switchConfigEditorFile({
  activeFileId,
  nextFileId,
  isInteractionLocked,
  confirmPendingAction,
  clearFeedback,
  setActiveFileId,
}: SwitchConfigEditorFileOptions): boolean {
  if (activeFileId === nextFileId || isInteractionLocked) {
    return false;
  }

  if (
    !confirmPendingAction({
      type: 'switch-file',
      nextFileId,
    })
  ) {
    return false;
  }

  setActiveFileId(nextFileId);
  clearFeedback();
  return true;
}

export function reloadConfigEditorFile({
  projectPath,
  isInteractionLocked,
  confirmPendingAction,
  clearFeedback,
  bumpReloadKey,
}: ReloadConfigEditorFileOptions): boolean {
  if (!projectPath || isInteractionLocked) {
    return false;
  }

  if (!confirmPendingAction({ type: 'reload' })) {
    return false;
  }

  bumpReloadKey();
  clearFeedback();
  return true;
}

export function resolveConfigEditorLoadPlan({
  projectPath,
  loadedProjectPath,
  isDirty,
  confirmDiscard,
}: {
  projectPath: string | null;
  loadedProjectPath: string | null;
  isDirty: boolean;
  confirmDiscard: (message: string) => boolean;
}): ConfigEditorLoadPlan {
  if (!projectPath) {
    return { type: 'clear' };
  }

  if (
    loadedProjectPath &&
    projectPath !== loadedProjectPath &&
    !shouldProceedWithPendingAction(
      isDirty,
      { type: 'switch-project', nextProjectPath: projectPath },
      confirmDiscard
    )
  ) {
    return {
      type: 'block-project-switch',
      nextProjectPath: projectPath,
      statusMessage: pendingProjectSwitchMessage(projectPath),
    };
  }

  return {
    type: 'load',
    projectPath,
  };
}

export function getConfigEditorMode(hasTauriBackend: boolean): ConfigEditorMode {
  if (hasTauriBackend) {
    return {
      canPersist: true,
      readOnly: false,
      hint: '编辑器始终操作固定白名单文件，避免前端拼接任意路径。',
    };
  }

  return {
    canPersist: false,
    readOnly: true,
    hint: '浏览器模式下仅支持查看占位内容，保存与重置需在桌面应用中进行。',
  };
}

export async function loadConfigEditorFile({
  fileId,
  hasTauriBackend,
  readConfigFile,
}: LoadConfigFileOptions): Promise<ConfigFileContent> {
  if (!hasTauriBackend) {
    return buildBrowserFallback(fileId);
  }

  return readConfigFile(fileId);
}

export async function saveConfigEditorFile({
  fileId,
  content,
  editorMode,
  writeConfigFile,
  refreshConfig,
}: SaveConfigFileOptions): Promise<PersistConfigFileResult> {
  if (!editorMode.canPersist) {
    throw new Error(editorMode.hint);
  }

  const config = await writeConfigFile(fileId, content);
  await refreshConfig();
  return {
    config,
    statusMessage: CONFIG_EDITOR_MESSAGES.saveSuccess,
  };
}

export async function submitConfigEditorSave({
  projectPath,
  currentFile,
  fileId,
  content,
  editorMode,
  writeConfigFile,
  refreshConfig,
  setIsSaving,
  setCurrentFile,
  setEditorContent,
  normalizeError,
  feedback,
}: SubmitConfigEditorSaveOptions): Promise<boolean> {
  if (!projectPath || !currentFile) {
    return false;
  }

  if (!editorMode.canPersist) {
    feedback.setError(editorMode.hint);
    feedback.setStatusMessage(null);
    return false;
  }

  setIsSaving(true);
  clearConfigEditorFeedback(feedback);

  try {
    const { config, statusMessage } = await saveConfigEditorFile({
      fileId,
      content,
      editorMode,
      writeConfigFile,
      refreshConfig,
    });

    setCurrentFile(config);
    setEditorContent(config.content);
    feedback.setStatusMessage(statusMessage);
    return true;
  } catch (saveError) {
    feedback.setError(normalizeError(saveError, CONFIG_EDITOR_MESSAGES.saveError));
    return false;
  } finally {
    setIsSaving(false);
  }
}

export async function resetConfigEditorFile({
  fileId,
  editorMode,
  resetConfigFile,
  refreshConfig,
}: ResetConfigFileOptions): Promise<PersistConfigFileResult> {
  if (!editorMode.canPersist) {
    throw new Error(editorMode.hint);
  }

  const config = await resetConfigFile(fileId);
  await refreshConfig();
  return {
    config,
    statusMessage: CONFIG_EDITOR_MESSAGES.resetSuccess,
  };
}

export async function submitConfigEditorReset({
  projectPath,
  confirmPendingAction,
  fileId,
  editorMode,
  resetConfigFile,
  refreshConfig,
  setIsResetting,
  setCurrentFile,
  setEditorContent,
  normalizeError,
  feedback,
}: SubmitConfigEditorResetOptions): Promise<boolean> {
  if (!projectPath) {
    return false;
  }

  if (!confirmPendingAction({ type: 'reset' })) {
    return false;
  }

  if (!editorMode.canPersist) {
    feedback.setError(editorMode.hint);
    feedback.setStatusMessage(null);
    return false;
  }

  setIsResetting(true);
  clearConfigEditorFeedback(feedback);

  try {
    const { config, statusMessage } = await resetConfigEditorFile({
      fileId,
      editorMode,
      resetConfigFile,
      refreshConfig,
    });

    setCurrentFile(config);
    setEditorContent(config.content);
    feedback.setStatusMessage(statusMessage);
    return true;
  } catch (resetError) {
    feedback.setError(normalizeError(resetError, CONFIG_EDITOR_MESSAGES.resetError));
    return false;
  } finally {
    setIsResetting(false);
  }
}

export function buildConfigEditorViewModel({
  projectPath,
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
  clearStatusMessage,
  confirmPendingAction,
  setActiveFileId,
  setEditorContent,
  onReload,
  onSave,
  onReset,
  onLoadPendingProject,
}: BuildConfigEditorViewModelOptions): ConfigEditorViewModel {
  const activeDefinition =
    CONFIG_FILES.find((file) => file.id === activeFileId) ?? CONFIG_FILES[0];
  const hasLoadedFile = currentFile !== null;
  const currentSourceLabel = isLoading
    ? '加载中'
    : hasLoadedFile
      ? sourceLabel(currentFile.source)
      : '加载失败';
  const helperText = isLoading
    ? '正在加载配置文件内容...'
    : hasLoadedFile
      ? editorMode.hint
      : CONFIG_EDITOR_LOAD_FAILURE_HINT;

  return {
    activeDefinition,
    fileTabs: CONFIG_FILES.map((file) => ({
      ...file,
      selected: file.id === activeFileId,
      disabled: isInteractionLocked,
      onSelect: () => {
        switchConfigEditorFile({
          activeFileId,
          nextFileId: file.id,
          isInteractionLocked,
          confirmPendingAction,
          clearFeedback,
          setActiveFileId,
        });
      },
    })),
    currentSourceLabel,
    savePath: saveTargetPath(
      projectPath,
      currentFile ? currentFile.relative_path : activeDefinition.id
    ),
    saveDisabled: isLoading || isSaving || isResetting || !isDirty || !editorMode.canPersist,
    resetDisabled: isLoading || isSaving || isResetting || !editorMode.canPersist,
    reloadDisabled: isInteractionLocked,
    editorDisabled: isInteractionLocked || !hasLoadedFile,
    editorReadOnly: !hasLoadedFile || editorMode.readOnly || isSaving || isResetting,
    editorValue: editorContent,
    helperText,
    pendingProjectCallout: pendingProjectPath
      ? {
          nextProjectPath: pendingProjectPath,
          message: pendingProjectSwitchMessage(pendingProjectPath),
          actionLabel: '放弃当前修改并加载新项目配置',
          onConfirmDiscard: onLoadPendingProject,
        }
      : null,
    onReload,
    onSave,
    onReset,
    onEditorChange: (value: string) => {
      setEditorContent(value);
      clearStatusMessage();
    },
  };
}
