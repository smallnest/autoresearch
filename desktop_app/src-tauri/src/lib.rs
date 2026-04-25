use std::fs;
use std::path::Path;
use std::process::Command;
use std::process::Stdio as StdStdio;
use std::sync::Arc;
use std::time::UNIX_EPOCH;

use tauri::Emitter;
use tokio::sync::Mutex;

#[cfg(unix)]
use std::sync::atomic::{AtomicBool, Ordering};
#[cfg(unix)]
use tokio::io::{AsyncBufReadExt, BufReader as TokioBufReader};
#[cfg(unix)]
use tokio::process::Command as TokioCommand;

/// Process state for a running run.sh instance.
#[cfg(unix)]
struct RunProcess {
    pid: u32,
    project_path: String,
    issue_number: i64,
    last_progress: Option<IterationProgress>,
}

/// Global state for run.sh process management.
#[cfg(unix)]
#[derive(Default)]
struct RunProcessState {
    process: Option<RunProcess>,
}

/// Global process state wrapped in Arc<Mutex>.
#[cfg(unix)]
static RUN_STATE: std::sync::OnceLock<Arc<Mutex<RunProcessState>>> = std::sync::OnceLock::new();

/// Flag to track if the process was killed by stop_run (for the spawned task).
#[cfg(unix)]
static WAS_KILLED: std::sync::OnceLock<AtomicBool> = std::sync::OnceLock::new();

#[cfg(unix)]
fn get_run_state() -> Arc<Mutex<RunProcessState>> {
    RUN_STATE
        .get_or_init(|| Arc::new(Mutex::new(RunProcessState::default())))
        .clone()
}

#[cfg(unix)]
fn get_was_killed() -> &'static AtomicBool {
    WAS_KILLED.get_or_init(|| AtomicBool::new(false))
}

/// Configuration detection result for a project directory.
#[derive(serde::Serialize)]
struct ProjectConfig {
    has_autoresearch_dir: bool,
    has_program_md: bool,
    has_agents_dir: bool,
}

/// A label attached to a GitHub Issue.
#[derive(serde::Serialize, serde::Deserialize, Debug, Clone)]
struct GhLabel {
    name: String,
    color: String,
}

/// A GitHub Issue returned by `gh issue list`.
#[derive(serde::Serialize, serde::Deserialize, Debug, Clone)]
struct GhIssue {
    number: i64,
    title: String,
    labels: Vec<GhLabel>,
    #[serde(rename = "createdAt")]
    created_at: String,
    state: String,
}

/// Author information for a GitHub comment.
#[derive(serde::Serialize, serde::Deserialize, Debug, Clone, PartialEq, Eq)]
struct GhCommentAuthor {
    login: String,
}

/// A comment on a GitHub Issue.
#[derive(serde::Serialize, serde::Deserialize, Debug, Clone, PartialEq, Eq)]
struct GhComment {
    id: String,
    author: GhCommentAuthor,
    body: String,
    #[serde(rename = "createdAt")]
    created_at: String,
}

/// Detailed information about a GitHub Issue.
#[derive(serde::Serialize, serde::Deserialize, Debug, PartialEq, Eq)]
struct IssueDetail {
    body: String,
    comments: Vec<GhComment>,
}

/// Metadata for a workflow log source under `.autoresearch/workflows/issue-N/`.
#[derive(serde::Serialize, Debug, Clone, PartialEq, Eq)]
struct IssueLogSource {
    id: String,
    label: String,
    kind: String,
    updated_at: Option<String>,
    size_bytes: u64,
}

/// The full text content for a single workflow log source.
#[derive(serde::Serialize, Debug, Clone, PartialEq, Eq)]
struct IssueLogContent {
    source_id: String,
    text: String,
    updated_at: Option<String>,
}

/// Result for the list_issues command, including processed status info.
#[derive(serde::Serialize)]
struct IssuesResult {
    issues: Vec<GhIssue>,
    processed_numbers: Vec<i64>,
}

/// Event payload for frontend iteration-progress subscriptions.
#[derive(serde::Serialize, Debug, Clone, PartialEq)]
struct IterationProgressEvent {
    issue_number: i64,
    progress: IterationProgress,
}

// ========================================
// Iteration progress types
// ========================================

/// Current phase of the autoresearch workflow.
#[derive(serde::Serialize, Debug, Clone, Copy, PartialEq, Eq)]
enum Phase {
    /// Planning phase — subtask breakdown.
    Planning,
    /// Agent is implementing code.
    Implementation,
    /// Agent is reviewing code.
    Review,
    /// Build/lint/test hard gate checks.
    BuildLintTest,
/// No active run or unknown state.
    Idle,
}

/// Frontend-facing status of a subtask.
#[derive(serde::Serialize, serde::Deserialize, Debug, Clone, Copy, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
enum SubtaskStatus {
    Pending,
    Passing,
    Failing,
}

/// Information about a single subtask from tasks.json.
#[derive(serde::Serialize, serde::Deserialize, Debug, Clone, PartialEq, Eq)]
struct SubtaskInfo {
    id: String,
    title: String,
    status: SubtaskStatus,
}

/// Overall iteration progress data sent to the frontend.
#[derive(serde::Serialize, Debug, Clone, PartialEq)]
struct IterationProgress {
    /// Current iteration number (1-based), 0 if not started.
    current_iteration: i32,
    /// Total iterations configured (e.g. 42).
    total_iterations: i32,
    /// Current workflow phase.
    phase: Phase,
    /// List of subtasks with pass/fail status.
    subtasks: Vec<SubtaskInfo>,
    /// Number of subtasks that have passed.
    passed_count: usize,
    /// Total number of subtasks.
    total_count: usize,
}

/// Raw tasks.json structure for deserialization.
#[derive(serde::Deserialize, Debug)]
#[serde(rename_all = "camelCase")]
struct TasksFile {
    #[allow(dead_code)]
    issue_number: Option<i64>,
    subtasks: Vec<TasksFileSubtask>,
}

/// A subtask entry in tasks.json.
#[derive(serde::Deserialize, Debug)]
#[serde(rename_all = "camelCase")]
struct TasksFileSubtask {
    id: String,
    title: String,
    passes: bool,
}

// ========================================
// Iteration progress helpers
// ========================================

/// Parses tasks.json and returns a list of SubtaskInfo.
fn parse_tasks_json(workflow_dir: &Path) -> Vec<TasksFileSubtask> {
    let tasks_path = workflow_dir.join("tasks.json");
    let bytes = match fs::read(&tasks_path) {
        Ok(b) => b,
        Err(_) => return Vec::new(),
    };
    let tasks_file: TasksFile = match serde_json::from_slice(&bytes) {
        Ok(t) => t,
        Err(_) => return Vec::new(),
    };
    tasks_file.subtasks
}

fn read_last_score(workflow_dir: &Path) -> Option<i32> {
    let content = fs::read_to_string(workflow_dir.join(".last_score")).ok()?;
    content.trim().parse::<i32>().ok()
}

fn current_iteration_has_review_or_hard_gate(workflow_dir: &Path, current_iteration: i32) -> bool {
    if current_iteration <= 0 {
        return false;
    }

    let review_prefix = format!("iteration-{current_iteration}-");
    if let Ok(entries) = fs::read_dir(workflow_dir) {
        for entry in entries.flatten() {
            let name = entry.file_name();
            let name = name.to_string_lossy();
            if name.starts_with(&review_prefix) && name.ends_with("-review.log") {
                return true;
            }
        }
    }

    workflow_dir
        .join(format!("hard-gate-{current_iteration}.log"))
        .is_file()
}

fn build_subtask_infos(workflow_dir: &Path) -> Vec<SubtaskInfo> {
    let raw_subtasks = parse_tasks_json(workflow_dir);
    let current_iteration = extract_iteration_numbers(workflow_dir).0;
    let last_score = read_last_score(workflow_dir);
    let current_failed = current_iteration_has_review_or_hard_gate(workflow_dir, current_iteration)
        || last_score.is_some_and(|score| score < 85);
    let current_index = raw_subtasks.iter().position(|subtask| !subtask.passes);

    raw_subtasks
        .into_iter()
        .enumerate()
        .map(|(index, subtask)| {
            let status = if subtask.passes {
                SubtaskStatus::Passing
            } else if Some(index) == current_index && current_failed {
                SubtaskStatus::Failing
            } else {
                SubtaskStatus::Pending
            };

            SubtaskInfo {
                id: subtask.id,
                title: subtask.title,
                status,
            }
        })
        .collect()
}

/// Infers the current phase by examining files in the workflow directory.
///
/// Logic:
/// 1. Find the highest iteration number N from `iteration-N-*.log` files.
/// 2. If no iteration logs exist but `planning.log` exists → Planning.
/// 3. If no iteration logs and no planning.log → Idle.
/// 4. If `hard-gate-N.log` exists → BuildLintTest.
/// 5. If `iteration-N-*-review.log` exists → Review.
/// 6. Otherwise → Implementation.
fn infer_phase(workflow_dir: &Path) -> Phase {
    let entries = match fs::read_dir(workflow_dir) {
        Ok(e) => e,
        Err(_) => return Phase::Idle,
    };

    let mut max_iteration: i32 = 0;
    let mut has_planning = false;
    let mut review_iterations = std::collections::HashSet::new();
    let mut hard_gate_iterations = std::collections::HashSet::new();

    for entry in entries.flatten() {
        let name = entry.file_name().to_string_lossy().to_string();
        if name == "planning.log" {
            has_planning = true;
            continue;
        }
        if let Some(n) = iteration_number(&name) {
            if n > max_iteration {
                max_iteration = n;
            }
            if name.contains("-review.log") {
                review_iterations.insert(n);
            }
        }
        if name.starts_with("hard-gate-") && name.ends_with(".log") {
            if let Some(n) = name
                .strip_prefix("hard-gate-")
                .and_then(|s| s.strip_suffix(".log"))
                .and_then(|s| s.parse::<i32>().ok())
            {
                hard_gate_iterations.insert(n);
            }
        }
    }

    if max_iteration == 0 {
        return if has_planning { Phase::Planning } else { Phase::Idle };
    }

    if hard_gate_iterations.contains(&max_iteration) {
        return Phase::BuildLintTest;
    }
    if review_iterations.contains(&max_iteration) {
        return Phase::Review;
    }
    Phase::Implementation
}

/// Extracts the current iteration and total iterations from terminal.log.
///
/// Looks for the pattern `🔄 迭代 N/M` in terminal.log lines (last match wins).
/// Falls back to parsing log.md if terminal.log is missing or has no match.
fn extract_iteration_numbers(workflow_dir: &Path) -> (i32, i32) {
    // Try terminal.log first (most reliable for iteration markers)
    let terminal_path = workflow_dir.join("terminal.log");
    if let Ok(content) = fs::read_to_string(&terminal_path) {
        if let Some((current, total)) = parse_iteration_from_terminal(&content) {
            return (current, total);
        }
    }

    let log_md_path = workflow_dir.join("log.md");
    if let Ok(content) = fs::read_to_string(&log_md_path) {
        if let Some((current, total)) = parse_iteration_from_log_md(&content) {
            return (current, total);
        }
    }

    (0, 0)
}

/// Parses "迭代 N/M" from terminal.log content. Returns the last match.
fn parse_iteration_from_terminal(content: &str) -> Option<(i32, i32)> {
    let mut result = None;
    for line in content.lines() {
        // Look for "迭代 N/M" pattern
        if let Some(pos) = line.find("迭代 ") {
            let rest = &line[pos + "迭代 ".len()..];
            if let Some(slash_pos) = rest.find('/') {
                let current_str = rest[..slash_pos].trim();
                let total_rest = &rest[slash_pos + 1..];
                // Total might be followed by other characters or end of line
                let total_str: String = total_rest.chars().take_while(|c| c.is_ascii_digit()).collect();
                if let (Ok(current), Ok(total)) = (current_str.parse::<i32>(), total_str.parse::<i32>()) {
                    result = Some((current, total));
                }
            }
        }
    }
    result
}

/// Parses iteration progress from log.md content.
///
/// Current iteration is inferred from the last `### 迭代 N - ...` heading.
/// Total iterations is inferred from the last `总迭代次数: N` entry.
/// If only one value is present, the other defaults to 0.
fn parse_iteration_from_log_md(content: &str) -> Option<(i32, i32)> {
    let mut current_iteration = 0;
    let mut total_iterations = 0;

    for line in content.lines() {
        if let Some(rest) = line.strip_prefix("### 迭代 ") {
            let iteration_str: String = rest
                .chars()
                .take_while(|c| c.is_ascii_digit())
                .collect();
            if let Ok(iteration) = iteration_str.parse::<i32>() {
                current_iteration = iteration;
            }
        }

        if let Some(pos) = line.find("总迭代次数:") {
            let total_str: String = line[pos + "总迭代次数:".len()..]
                .chars()
                .skip_while(|c| c.is_whitespace())
                .take_while(|c| c.is_ascii_digit())
                .collect();
            if let Ok(total) = total_str.parse::<i32>() {
                total_iterations = total;
            }
        }
    }

    if current_iteration == 0 && total_iterations == 0 {
        None
    } else {
        Some((current_iteration, total_iterations))
    }
}

/// Builds a complete IterationProgress for a given workflow directory.
fn build_iteration_progress(workflow_dir: &Path) -> IterationProgress {
    let subtasks = build_subtask_infos(workflow_dir);
    let passed_count = subtasks
        .iter()
        .filter(|s| s.status == SubtaskStatus::Passing)
        .count();
    let total_count = subtasks.len();
    let phase = infer_phase(workflow_dir);
    let (current_iteration, total_iterations) = extract_iteration_numbers(workflow_dir);

    IterationProgress {
        current_iteration,
        total_iterations,
        phase,
        subtasks,
        passed_count,
        total_count,
    }
}

/// Returns the iteration progress for a given issue's workflow.
fn get_iteration_progress_sync(
    project_path: &str,
    issue_number: i64,
) -> Result<IterationProgress, String> {
    let base = Path::new(project_path);
    if !base.is_dir() {
        return Err(format!("Path is not a directory: {project_path}"));
    }

    let workflow_dir = base
        .join(".autoresearch")
        .join("workflows")
        .join(format!("issue-{issue_number}"));

    if !workflow_dir.is_dir() {
        // Return idle progress with empty data
        return Ok(IterationProgress {
            current_iteration: 0,
            total_iterations: 0,
            phase: Phase::Idle,
            subtasks: Vec::new(),
            passed_count: 0,
            total_count: 0,
        });
    }

    Ok(build_iteration_progress(&workflow_dir))
}

/// Returns the current iteration progress for a specific issue.
#[tauri::command]
async fn get_iteration_progress(
    project_path: String,
    issue_number: i64,
) -> Result<IterationProgress, String> {
    tokio::task::spawn_blocking(move || get_iteration_progress_sync(&project_path, issue_number))
        .await
        .map_err(|e| format!("Task join error: {e}"))?
}

#[cfg(unix)]
async fn emit_iteration_progress(app: &tauri::AppHandle) {
    let (project_path, issue_number) = {
        let state = get_run_state();
        let state_guard = state.lock().await;
        let Some(process) = state_guard.process.as_ref() else {
            return;
        };
        (process.project_path.clone(), process.issue_number)
    };

    let progress = match tokio::task::spawn_blocking(move || {
        get_iteration_progress_sync(&project_path, issue_number)
    })
    .await
    {
        Ok(Ok(progress)) => progress,
        _ => return,
    };

    let should_emit = {
        let state = get_run_state();
        let mut state_guard = state.lock().await;
        let Some(process) = state_guard.process.as_mut() else {
            return;
        };
        if process.issue_number != issue_number {
            return;
        }
        if process.last_progress.as_ref() == Some(&progress) {
            false
        } else {
            process.last_progress = Some(progress.clone());
            true
        }
    };

    if should_emit {
        let _ = app.emit(
            "iteration-progress",
            &IterationProgressEvent {
                issue_number,
                progress,
            },
        );
    }
}

/// Opens a native folder selection dialog and returns the selected path.
#[tauri::command]
async fn select_project_dir(app: tauri::AppHandle) -> Result<Option<String>, String> {
    let dir = tauri_plugin_dialog::DialogExt::dialog(&app)
        .file()
        .set_title("Select Project Directory")
        .blocking_pick_folder();
    Ok(dir.map(|p| p.to_string()))
}

/// Detects whether the given project directory contains autoresearch configuration files.
#[tauri::command]
async fn detect_project_config(project_path: String) -> Result<ProjectConfig, String> {
    tokio::task::spawn_blocking(move || {
        let base = Path::new(&project_path);
        if !base.is_dir() {
            return Err(format!("Path is not a directory: {project_path}"));
        }
        let ar = base.join(".autoresearch");
        Ok(ProjectConfig {
            has_autoresearch_dir: ar.is_dir(),
            has_program_md: ar.join("program.md").is_file() || base.join("program.md").is_file(),
            has_agents_dir: ar.join("agents").is_dir() || base.join("agents").is_dir(),
        })
    })
    .await
    .map_err(|e| format!("Task join error: {e}"))?
}

/// Retrieves the most recently opened project path from the Tauri store.
#[tauri::command]
async fn get_recent_project(app: tauri::AppHandle) -> Result<Option<String>, String> {
    let store = tauri_plugin_store::StoreExt::store(&app, "app.json")
        .map_err(|e| format!("Failed to open store: {e}"))?;
    let value = store
        .get("recent_project")
        .and_then(|v| v.as_str().map(String::from));
    Ok(value)
}

/// Saves the project path to the Tauri store as the most recent project.
#[tauri::command]
async fn save_recent_project(app: tauri::AppHandle, path: String) -> Result<(), String> {
    let store = tauri_plugin_store::StoreExt::store(&app, "app.json")
        .map_err(|e| format!("Failed to open store: {e}"))?;
    store.set("recent_project", path);
    store.save().map_err(|e| e.to_string())
}

/// Scans `.autoresearch/workflows/issue-*` directories and returns Issue numbers that have been processed.
fn get_processed_issue_numbers(project_path: &Path) -> Result<Vec<i64>, String> {
    let workflows_dir = project_path.join(".autoresearch").join("workflows");
    if !workflows_dir.is_dir() {
        return Ok(Vec::new());
    }
    let mut numbers = Vec::new();
    let entries = fs::read_dir(&workflows_dir)
        .map_err(|e| format!("Failed to read workflows dir: {e}"))?;
    for entry in entries.flatten() {
        let name = entry.file_name();
        let name_str = name.to_string_lossy();
        if let Some(suffix) = name_str.strip_prefix("issue-") {
            if let Ok(num) = suffix.parse::<i64>() {
                numbers.push(num);
            }
        }
    }
    numbers.sort();
    Ok(numbers)
}

/// Lists GitHub Issues for the repository at `project_path` using `gh issue list`.
/// Also returns which Issue numbers have already been processed (have workflow directories).
#[tauri::command]
async fn list_issues(project_path: String) -> Result<IssuesResult, String> {
    tokio::task::spawn_blocking(move || {
        list_issues_sync(&project_path)
    })
    .await
    .map_err(|e| format!("Task join error: {e}"))?
}

fn list_issues_sync(project_path: &str) -> Result<IssuesResult, String> {
    let base = Path::new(project_path);
    if !base.is_dir() {
        return Err(format!("Path is not a directory: {project_path}"));
    }

    // Execute gh issue list
    let output = Command::new("gh")
        .args([
            "issue", "list",
            "--json", "number,title,labels,createdAt,state",
            "--limit", "100",
        ])
        .current_dir(base)
        .output()
        .map_err(|e| format!("Failed to execute gh: {e}"))?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        return Err(format!("gh issue list failed: {}", stderr.trim()));
    }

    let stdout = String::from_utf8_lossy(&output.stdout);
    let issues: Vec<GhIssue> = serde_json::from_str(&stdout)
        .map_err(|e| format!("Failed to parse gh output: {e}. Output: {stdout}"))?;

    let processed_numbers = get_processed_issue_numbers(base)?;

    Ok(IssuesResult {
        issues,
        processed_numbers,
    })
}

/// Returns a list of Issue numbers that have already been processed by autoresearch.
#[tauri::command]
async fn check_processed_issues(project_path: String) -> Result<Vec<i64>, String> {
    tokio::task::spawn_blocking(move || {
        let base = Path::new(&project_path);
        if !base.is_dir() {
            return Err(format!("Path is not a directory: {project_path}"));
        }
        get_processed_issue_numbers(base)
    })
    .await
    .map_err(|e| format!("Task join error: {e}"))?
}

fn parse_issue_detail(stdout: &str) -> Result<IssueDetail, String> {
    serde_json::from_str(stdout).map_err(|e| format!("Failed to parse gh output: {e}. Output: {stdout}"))
}

fn map_issue_detail_command_error(issue_number: i64, stderr: &str) -> String {
    if stderr.contains("not found") || stderr.contains("Could not resolve") {
        return format!("Issue #{issue_number} not found");
    }

    format!("gh issue view failed: {}", stderr.trim())
}

fn workflow_issue_dir(project_path: &str, issue_number: i64) -> Result<std::path::PathBuf, String> {
    let base = Path::new(project_path);
    if !base.is_dir() {
        return Err(format!("Path is not a directory: {project_path}"));
    }

    let issue_dir = base
        .join(".autoresearch")
        .join("workflows")
        .join(format!("issue-{issue_number}"));

    if !issue_dir.is_dir() {
        return Err(format!("Workflow logs for Issue #{issue_number} not found"));
    }

    Ok(issue_dir)
}

fn classify_log_source(filename: &str) -> (&'static str, String) {
    match filename {
        "terminal.log" => ("terminal", "终端日志".to_string()),
        "log.md" => ("summary", "工作流摘要".to_string()),
        _ if filename.starts_with("iteration-") => ("iteration", filename.to_string()),
        _ => ("file", filename.to_string()),
    }
}

fn iteration_number(filename: &str) -> Option<i32> {
    filename
        .strip_prefix("iteration-")
        .and_then(|rest| rest.split('-').next())
        .and_then(|value| value.parse::<i32>().ok())
}

fn sort_log_sources(left: &IssueLogSource, right: &IssueLogSource) -> std::cmp::Ordering {
    fn rank(kind: &str) -> i32 {
        match kind {
            "terminal" => 0,
            "summary" => 1,
            "iteration" => 2,
            _ => 3,
        }
    }

    rank(&left.kind)
        .cmp(&rank(&right.kind))
        .then_with(|| match (left.kind.as_str(), right.kind.as_str()) {
            ("iteration", "iteration") => iteration_number(&left.id)
                .cmp(&iteration_number(&right.id))
                .then_with(|| left.label.cmp(&right.label)),
            _ => std::cmp::Ordering::Equal,
        })
        .then_with(|| left.label.cmp(&right.label))
}

fn file_timestamp(metadata: &fs::Metadata) -> Option<String> {
    metadata
        .modified()
        .ok()
        .and_then(|time| time.duration_since(UNIX_EPOCH).ok())
        .map(|duration| duration.as_secs().to_string())
}

fn list_issue_log_sources_sync(project_path: &str, issue_number: i64) -> Result<Vec<IssueLogSource>, String> {
    let issue_dir = workflow_issue_dir(project_path, issue_number)?;
    let entries = fs::read_dir(&issue_dir)
        .map_err(|e| format!("Failed to read workflow dir: {e}"))?;

    let mut sources = Vec::new();
    for entry in entries {
        let entry = entry.map_err(|e| format!("Failed to read workflow entry: {e}"))?;
        let path = entry.path();
        if !path.is_file() {
            continue;
        }

        let filename = entry.file_name().to_string_lossy().to_string();
        let metadata = entry
            .metadata()
            .map_err(|e| format!("Failed to read metadata for {filename}: {e}"))?;
        let (kind, label) = classify_log_source(&filename);

        sources.push(IssueLogSource {
            id: filename,
            label,
            kind: kind.to_string(),
            updated_at: file_timestamp(&metadata),
            size_bytes: metadata.len(),
        });
    }

    sources.sort_by(sort_log_sources);
    Ok(sources)
}

fn resolve_issue_log_source_path(
    project_path: &str,
    issue_number: i64,
    source_id: &str,
) -> Result<std::path::PathBuf, String> {
    if source_id.is_empty()
        || source_id.contains('/')
        || source_id.contains('\\')
        || source_id == "."
        || source_id == ".."
    {
        return Err(format!("Invalid log source id: {source_id}"));
    }

    let issue_dir = workflow_issue_dir(project_path, issue_number)?;
    let path = issue_dir.join(source_id);
    if !path.is_file() {
        return Err(format!("Log source not found: {source_id}"));
    }

    Ok(path)
}

fn read_issue_log_content_sync(
    project_path: &str,
    issue_number: i64,
    source_id: &str,
) -> Result<IssueLogContent, String> {
    let source_path = resolve_issue_log_source_path(project_path, issue_number, source_id)?;
    let metadata = fs::metadata(&source_path)
        .map_err(|e| format!("Failed to read metadata for {source_id}: {e}"))?;
    let bytes = fs::read(&source_path)
        .map_err(|e| format!("Failed to read log source {source_id}: {e}"))?;

    Ok(IssueLogContent {
        source_id: source_id.to_string(),
        text: String::from_utf8_lossy(&bytes).into_owned(),
        updated_at: file_timestamp(&metadata),
    })
}

/// Retrieves detailed information about a specific GitHub Issue using `gh issue view`.
#[tauri::command]
async fn get_issue_detail(project_path: String, issue_number: i64) -> Result<IssueDetail, String> {
    tokio::task::spawn_blocking(move || {
        get_issue_detail_sync(&project_path, issue_number)
    })
    .await
    .map_err(|e| format!("Task join error: {e}"))?
}

fn get_issue_detail_sync(project_path: &str, issue_number: i64) -> Result<IssueDetail, String> {
    let base = Path::new(project_path);
    if !base.is_dir() {
        return Err(format!("Path is not a directory: {project_path}"));
    }

    // Execute gh issue view
    let output = Command::new("gh")
        .args([
            "issue", "view",
            &issue_number.to_string(),
            "--json", "body,comments",
        ])
        .current_dir(base)
        .output()
        .map_err(|e| format!("Failed to execute gh: {e}"))?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        return Err(map_issue_detail_command_error(issue_number, &stderr));
    }

    let stdout = String::from_utf8_lossy(&output.stdout);
    parse_issue_detail(&stdout)
}

/// Lists available workflow log sources for a processed Issue.
#[tauri::command]
async fn list_issue_log_sources(
    project_path: String,
    issue_number: i64,
) -> Result<Vec<IssueLogSource>, String> {
    tokio::task::spawn_blocking(move || list_issue_log_sources_sync(&project_path, issue_number))
        .await
        .map_err(|e| format!("Task join error: {e}"))?
}

/// Reads the content of a workflow log source under `.autoresearch/workflows/issue-N/`.
#[tauri::command]
async fn read_issue_log_content(
    project_path: String,
    issue_number: i64,
    source_id: String,
) -> Result<IssueLogContent, String> {
    tokio::task::spawn_blocking(move || {
        read_issue_log_content_sync(&project_path, issue_number, &source_id)
    })
    .await
    .map_err(|e| format!("Task join error: {e}"))?
}

/// Request parameters for starting a run.sh process.
#[derive(serde::Deserialize, Debug)]
struct StartRunRequest {
    /// Project directory path where run.sh will execute.
    project_path: String,
    /// GitHub Issue number to process.
    issue_number: i64,
    /// Maximum number of iterations (optional, defaults to 42).
    max_iter: Option<i32>,
    /// Comma-separated list of agents (optional).
    agents: Option<String>,
    /// Passing score threshold (optional, defaults to 85).
    passing_score: Option<i32>,
    /// Continue from last interrupted run (optional).
    continue_mode: Option<bool>,
}

/// Builds command-line arguments for run.sh from the request parameters.
/// This is a pure function extracted for testability.
fn build_run_args(request: &StartRunRequest) -> Vec<String> {
    let mut args = vec![
        "-p".to_string(),
        request.project_path.clone(),
    ];

    if let Some(ref agents) = request.agents {
        if !agents.is_empty() {
            args.push("-a".to_string());
            args.push(agents.clone());
        }
    }

    if request.continue_mode.unwrap_or(false) {
        args.push("-c".to_string());
    }

    args.push(request.issue_number.to_string());

    if let Some(max_iter) = request.max_iter {
        args.push(max_iter.to_string());
    }

    args
}

/// Builds environment variables for run.sh from the request parameters.
/// Returns a vector of (key, value) pairs.
/// This is a pure function extracted for testability.
fn build_run_env_vars(request: &StartRunRequest) -> Vec<(&'static str, String)> {
    let mut env_vars = vec![];
    if let Some(passing_score) = request.passing_score {
        env_vars.push(("PASSING_SCORE", passing_score.to_string()));
    }
    env_vars
}

/// Result returned when run.sh process exits.
#[derive(serde::Serialize, Debug, Clone)]
struct RunExitEvent {
    /// Exit code of the process.
    exit_code: Option<i32>,
    /// Whether the process was killed by stop_run.
    killed: bool,
}

/// Starts a run.sh process to process a GitHub Issue.
///
/// Parameters are mapped to run.sh CLI arguments:
/// - `issue_number` -> positional argument
/// - `max_iter` -> positional argument (after issue_number)
/// - `agents` -> `-a` option
/// - `passing_score` -> `PASSING_SCORE` environment variable
/// - `continue_mode` -> `-c` flag
///
/// The process's stdout/stderr are streamed via `run-output` Tauri events.
/// When the process exits, a `run-exit` event is emitted.
#[cfg(unix)]
#[tauri::command]
async fn start_run(app: tauri::AppHandle, request: StartRunRequest) -> Result<(), String> {
    let state = get_run_state();
    let mut state_guard = state.lock().await;

    // Check if a process is already running
    if state_guard.process.is_some() {
        return Err("A run is already in progress. Stop the current run before starting a new one.".to_string());
    }

    // Validate project path
    let project_path = Path::new(&request.project_path);
    if !project_path.is_dir() {
        return Err(format!("Project path is not a directory: {}", request.project_path));
    }

    // Find run.sh in autoresearch directory (relative to the app)
    // run.sh is in the autoresearch project root, which is the parent of desktop_app
    let autoresearch_root = project_path
        .parent()
        .ok_or("Cannot determine autoresearch root directory")?;
    let run_sh_path = autoresearch_root.join("run.sh");
    if !run_sh_path.is_file() {
        return Err(format!("run.sh not found at: {}", run_sh_path.display()));
    }

    // Build command arguments and environment variables
    let args = build_run_args(&request);
    let env_vars = build_run_env_vars(&request);

    // Spawn the process with a new process group
    let mut cmd = TokioCommand::new(&run_sh_path);
    cmd.args(&args)
        .current_dir(autoresearch_root)
        .stdout(StdStdio::piped())
        .stderr(StdStdio::piped())
        .kill_on_drop(false); // Don't kill on drop - we want to manage the process lifecycle

    // Set environment variables
    for (key, value) in &env_vars {
        cmd.env(key, value);
    }

    // Set up process group on Unix
    // SAFETY: pre_exec is safe as long as the closure doesn't panic or call unsafe code
    unsafe {
        cmd.pre_exec(move || {
            // Create a new process group with the child's PID as the PGID
            let pid = libc::getpid();
            if libc::setpgid(pid, pid) < 0 {
                // Log error but don't fail the spawn
                eprintln!("Warning: Failed to set process group: {}", std::io::Error::last_os_error());
            }
            Ok(())
        });
    }

    // Spawn the process
    let mut child = cmd
        .spawn()
        .map_err(|e| format!("Failed to start run.sh: {e}"))?;

    let pid = child.id().ok_or("Failed to get process ID")?;

    // Store the PID for process group management
    state_guard.process = Some(RunProcess {
        pid,
        project_path: request.project_path.clone(),
        issue_number: request.issue_number,
        last_progress: None,
    });
    drop(state_guard);

    // Reset the killed flag
    get_was_killed().store(false, Ordering::SeqCst);

    emit_iteration_progress(&app).await;

    // Clone app handle for the spawned task
    let app_clone = app.clone();
    let state_clone = get_run_state();

    // Take stdout/stderr before waiting on the process
    let stdout = child.stdout.take();
    let stderr = child.stderr.take();

    // Spawn a task to wait for process exit and emit event
    tokio::spawn(async move {
        let status = child.wait().await;

        emit_iteration_progress(&app_clone).await;

        // Check if we were killed by stop_run
        let was_killed = get_was_killed().swap(false, Ordering::SeqCst);

        // Clear the process state
        {
            let mut state_guard = state_clone.lock().await;
            state_guard.process = None;
        }

        // Only emit exit event if we weren't killed by stop_run
        // (stop_run emits its own event)
        if !was_killed {
            let exit_event = match status {
                Ok(status) => RunExitEvent {
                    exit_code: status.code(),
                    killed: false,
                },
                Err(_) => RunExitEvent {
                    exit_code: None,
                    killed: false,
                },
            };

            let _ = app_clone.emit("run-exit", &exit_event);
        }
    });

    // Handle stdout streaming
    if let Some(stdout) = stdout {
        let app_clone = app.clone();
        tokio::spawn(async move {
            let mut reader = TokioBufReader::new(stdout).lines();
            while let Ok(Some(line)) = reader.next_line().await {
                let _ = app_clone.emit("run-output", &line);
                emit_iteration_progress(&app_clone).await;
            }
        });
    }

    // Handle stderr streaming
    if let Some(stderr) = stderr {
        let app_clone = app.clone();
        tokio::spawn(async move {
            let mut reader = TokioBufReader::new(stderr).lines();
            while let Ok(Some(line)) = reader.next_line().await {
                let _ = app_clone.emit("run-output", &line);
                emit_iteration_progress(&app_clone).await;
            }
        });
    }

    Ok(())
}

/// Stops the currently running run.sh process by sending SIGTERM to its process group.
#[cfg(unix)]
#[tauri::command]
async fn stop_run(app: tauri::AppHandle) -> Result<(), String> {
    let state = get_run_state();
    let mut state_guard = state.lock().await;

    let process = state_guard.process.take().ok_or("No run is in progress")?;
    let pid = process.pid;

    // Mark that we're killing via stop_run, so the wait task doesn't emit duplicate event
    get_was_killed().store(true, Ordering::SeqCst);

    // Send SIGTERM to the process group
    // Use the PID as PGID since we set it in pre_exec
    let pgid = pid as i32;

    // Use nix to send signal to process group
    use nix::sys::signal::{killpg, Signal};
    use nix::unistd::Pid;

    match killpg(Pid::from_raw(pgid), Signal::SIGTERM) {
        Ok(()) => {
            emit_iteration_progress(&app).await;
            // Emit exit event with killed flag
            let exit_event = RunExitEvent {
                exit_code: None,
                killed: true,
            };
            let _ = app.emit("run-exit", &exit_event);
            Ok(())
        }
        Err(e) => {
            // Restore process state on error
            state_guard.process = Some(process);
            get_was_killed().store(false, Ordering::SeqCst);
            Err(format!("Failed to stop process: {e}"))
        }
    }
}

/// Current status of run.sh process management.
#[derive(serde::Serialize, Debug, Clone, Copy, PartialEq, Eq)]
enum RunStatus {
    /// No process is running.
    Idle,
    /// A run.sh process is currently executing.
    Running,
}

/// Returns the current status of run.sh process management.
#[cfg(unix)]
#[tauri::command]
async fn get_run_status() -> Result<RunStatus, String> {
    let state = get_run_state();
    let state_guard = state.lock().await;

    if state_guard.process.is_some() {
        Ok(RunStatus::Running)
    } else {
        Ok(RunStatus::Idle)
    }
}

/// Non-Unix stub for get_run_status.
#[cfg(not(unix))]
#[tauri::command]
async fn get_run_status() -> Result<RunStatus, String> {
    Ok(RunStatus::Idle)
}

/// Non-Unix stub for start_run (not supported on Windows).
#[cfg(not(unix))]
#[tauri::command]
async fn start_run(_app: tauri::AppHandle, _request: StartRunRequest) -> Result<(), String> {
    Err("run.sh process management is only supported on Unix systems".to_string())
}

/// Non-Unix stub for stop_run (not supported on Windows).
#[cfg(not(unix))]
#[tauri::command]
async fn stop_run(_app: tauri::AppHandle) -> Result<(), String> {
    Err("run.sh process management is only supported on Unix systems".to_string())
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_store::Builder::default().build())
        .invoke_handler(tauri::generate_handler![
            select_project_dir,
            detect_project_config,
            get_recent_project,
            save_recent_project,
            list_issues,
            check_processed_issues,
            get_issue_detail,
            list_issue_log_sources,
            read_issue_log_content,
            start_run,
            stop_run,
            get_run_status,
            get_iteration_progress,
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}

#[cfg(test)]
mod tests {
    use super::{
        classify_log_source, get_issue_detail_sync, iteration_number, list_issue_log_sources_sync,
        map_issue_detail_command_error, parse_issue_detail, read_issue_log_content_sync,
        resolve_issue_log_source_path, workflow_issue_dir, IssueDetail, IssueLogSource,
    };
    use super::{build_run_args, build_run_env_vars, StartRunRequest};
    use super::{
        build_iteration_progress, get_iteration_progress_sync, infer_phase,
        parse_iteration_from_log_md, parse_iteration_from_terminal, parse_tasks_json, Phase,
        SubtaskStatus,
    };
    #[cfg(unix)]
    use super::RunProcessState;
    use std::fs;
    use std::path::PathBuf;

    fn create_temp_project_dir(test_name: &str) -> PathBuf {
        let root = std::env::temp_dir()
            .join(format!("autoresearch-log-viewer-{test_name}-{}", std::process::id()));
        let _ = fs::remove_dir_all(&root);
        fs::create_dir_all(&root).expect("temp project dir should be created");
        root
    }

    #[test]
    fn parse_issue_detail_returns_structured_data() {
        let detail = parse_issue_detail(
            r#"{
                "body": "Issue description",
                "comments": [
                    {
                        "id": "IC_kwDOA",
                        "author": { "login": "alice" },
                        "body": "first comment",
                        "createdAt": "2026-04-24T10:00:00Z"
                    }
                ]
            }"#,
        )
        .expect("issue detail should parse");

        assert_eq!(
            detail,
            IssueDetail {
                body: "Issue description".to_string(),
                comments: vec![super::GhComment {
                    id: "IC_kwDOA".to_string(),
                    author: super::GhCommentAuthor {
                        login: "alice".to_string(),
                    },
                    body: "first comment".to_string(),
                    created_at: "2026-04-24T10:00:00Z".to_string(),
                }],
            }
        );
    }

    #[test]
    fn parse_issue_detail_reports_invalid_json() {
        let error = parse_issue_detail("{invalid json").expect_err("invalid json should fail");

        assert!(error.contains("Failed to parse gh output"));
        assert!(error.contains("{invalid json"));
    }

    #[test]
    fn issue_detail_error_maps_missing_issue() {
        let error =
            map_issue_detail_command_error(27, "GraphQL: Could not resolve to an issue with the number of 27.");

        assert_eq!(error, "Issue #27 not found");
    }

    #[test]
    fn issue_detail_error_preserves_other_gh_failures() {
        let error = map_issue_detail_command_error(27, "network timeout");

        assert_eq!(error, "gh issue view failed: network timeout");
    }

    #[test]
    fn get_issue_detail_rejects_non_directory_path() {
        let error = get_issue_detail_sync("/path/that/does/not/exist", 27)
            .expect_err("invalid path should fail");

        assert_eq!(error, "Path is not a directory: /path/that/does/not/exist");
    }

    #[test]
    fn classify_log_source_maps_known_workflow_files() {
        assert_eq!(classify_log_source("terminal.log"), ("terminal", "终端日志".to_string()));
        assert_eq!(classify_log_source("log.md"), ("summary", "工作流摘要".to_string()));
        assert_eq!(
            classify_log_source("iteration-2-codex-review.log"),
            ("iteration", "iteration-2-codex-review.log".to_string())
        );
    }

    #[test]
    fn iteration_number_extracts_numeric_prefix() {
        assert_eq!(iteration_number("iteration-2-codex-review.log"), Some(2));
        assert_eq!(iteration_number("iteration-10-claude.log"), Some(10));
        assert_eq!(iteration_number("terminal.log"), None);
    }

    #[test]
    fn workflow_issue_dir_requires_existing_issue_directory() {
        let project_dir = create_temp_project_dir("workflow-dir");
        let error = workflow_issue_dir(project_dir.to_string_lossy().as_ref(), 30)
            .expect_err("missing workflow dir should fail");

        assert_eq!(error, "Workflow logs for Issue #30 not found");
        fs::remove_dir_all(project_dir).expect("temp dir cleanup should succeed");
    }

    #[test]
    fn list_issue_log_sources_returns_sorted_sources() {
        let project_dir = create_temp_project_dir("list-sources");
        let workflow_dir = project_dir.join(".autoresearch/workflows/issue-30");
        fs::create_dir_all(&workflow_dir).expect("workflow dir should be created");
        fs::write(workflow_dir.join("iteration-10-codex-review.log"), "iteration10").expect("iteration log");
        fs::write(workflow_dir.join("iteration-2-codex-review.log"), "iteration").expect("iteration log");
        fs::write(workflow_dir.join("terminal.log"), "terminal").expect("terminal log");
        fs::write(workflow_dir.join("log.md"), "summary").expect("summary log");

        let sources = list_issue_log_sources_sync(project_dir.to_string_lossy().as_ref(), 30)
            .expect("sources should load");

        assert_eq!(
            sources,
            vec![
                IssueLogSource {
                    id: "terminal.log".to_string(),
                    label: "终端日志".to_string(),
                    kind: "terminal".to_string(),
                    updated_at: sources[0].updated_at.clone(),
                    size_bytes: 8,
                },
                IssueLogSource {
                    id: "log.md".to_string(),
                    label: "工作流摘要".to_string(),
                    kind: "summary".to_string(),
                    updated_at: sources[1].updated_at.clone(),
                    size_bytes: 7,
                },
                IssueLogSource {
                    id: "iteration-2-codex-review.log".to_string(),
                    label: "iteration-2-codex-review.log".to_string(),
                    kind: "iteration".to_string(),
                    updated_at: sources[2].updated_at.clone(),
                    size_bytes: 9,
                },
                IssueLogSource {
                    id: "iteration-10-codex-review.log".to_string(),
                    label: "iteration-10-codex-review.log".to_string(),
                    kind: "iteration".to_string(),
                    updated_at: sources[3].updated_at.clone(),
                    size_bytes: 11,
                },
            ]
        );

        fs::remove_dir_all(project_dir).expect("temp dir cleanup should succeed");
    }

    #[test]
    fn resolve_issue_log_source_path_rejects_path_traversal() {
        let project_dir = create_temp_project_dir("reject-traversal");
        let workflow_dir = project_dir.join(".autoresearch/workflows/issue-30");
        fs::create_dir_all(&workflow_dir).expect("workflow dir should be created");

        let error = resolve_issue_log_source_path(
            project_dir.to_string_lossy().as_ref(),
            30,
            "../terminal.log",
        )
        .expect_err("traversal should fail");

        assert_eq!(error, "Invalid log source id: ../terminal.log");
        fs::remove_dir_all(project_dir).expect("temp dir cleanup should succeed");
    }

    #[test]
    fn read_issue_log_content_reads_utf8_lossy_text() {
        let project_dir = create_temp_project_dir("read-content");
        let workflow_dir = project_dir.join(".autoresearch/workflows/issue-30");
        fs::create_dir_all(&workflow_dir).expect("workflow dir should be created");
        fs::write(workflow_dir.join("terminal.log"), b"line one\nline two").expect("terminal log");

        let content = read_issue_log_content_sync(
            project_dir.to_string_lossy().as_ref(),
            30,
            "terminal.log",
        )
        .expect("log content should load");

        assert_eq!(content.source_id, "terminal.log");
        assert_eq!(content.text, "line one\nline two");
        assert!(content.updated_at.is_some());

        fs::remove_dir_all(project_dir).expect("temp dir cleanup should succeed");
    }

    // ========================================
    // Process management tests
    // ========================================

    #[test]
    fn build_run_args_includes_required_options() {
        let request = StartRunRequest {
            project_path: "/test/project".to_string(),
            issue_number: 42,
            max_iter: Some(10),
            agents: Some("claude,codex".to_string()),
            passing_score: Some(90),
            continue_mode: Some(true),
        };

        let args = build_run_args(&request);

        // Check required options
        assert!(args.contains(&"-p".to_string()));
        assert!(args.contains(&"/test/project".to_string()));
        assert!(args.contains(&"-a".to_string()));
        assert!(args.contains(&"claude,codex".to_string()));
        assert!(args.contains(&"-c".to_string()));
        assert!(args.contains(&"42".to_string()));
        assert!(args.contains(&"10".to_string()));
    }

    #[test]
    fn build_run_args_omits_optional_when_none() {
        let request = StartRunRequest {
            project_path: "/test/project".to_string(),
            issue_number: 42,
            max_iter: None,
            agents: None,
            passing_score: None,
            continue_mode: None,
        };

        let args = build_run_args(&request);

        assert!(args.contains(&"-p".to_string()));
        assert!(args.contains(&"/test/project".to_string()));
        assert!(args.contains(&"42".to_string()));
        // Optional args should not be present
        assert!(!args.contains(&"-a".to_string()));
        assert!(!args.contains(&"-c".to_string()));
    }

    #[test]
    fn build_run_args_ignores_empty_agents() {
        let request = StartRunRequest {
            project_path: "/test/project".to_string(),
            issue_number: 42,
            max_iter: None,
            agents: Some("".to_string()),
            passing_score: None,
            continue_mode: None,
        };

        let args = build_run_args(&request);

        assert!(!args.contains(&"-a".to_string()));
    }

    #[test]
    fn build_run_args_continue_mode_defaults_false() {
        let request = StartRunRequest {
            project_path: "/test/project".to_string(),
            issue_number: 42,
            max_iter: None,
            agents: None,
            passing_score: None,
            continue_mode: None,
        };

        let args = build_run_args(&request);

        assert!(!args.contains(&"-c".to_string()));
    }

    #[test]
    fn build_run_env_vars_includes_passing_score() {
        let request = StartRunRequest {
            project_path: "/test/project".to_string(),
            issue_number: 42,
            max_iter: None,
            agents: None,
            passing_score: Some(95),
            continue_mode: None,
        };

        let env_vars = build_run_env_vars(&request);

        assert_eq!(env_vars.len(), 1);
        assert_eq!(env_vars[0].0, "PASSING_SCORE");
        assert_eq!(env_vars[0].1, "95");
    }

    #[test]
    fn build_run_env_vars_empty_when_no_passing_score() {
        let request = StartRunRequest {
            project_path: "/test/project".to_string(),
            issue_number: 42,
            max_iter: None,
            agents: None,
            passing_score: None,
            continue_mode: None,
        };

        let env_vars = build_run_env_vars(&request);

        assert!(env_vars.is_empty());
    }

    #[cfg(unix)]
    #[test]
    fn run_process_state_default_is_idle() {
        let state = RunProcessState::default();

        assert!(state.process.is_none());
    }

    // ========================================
    // Iteration progress tests
    // ========================================

    #[test]
    fn parse_tasks_json_returns_subtasks() {
        let dir = create_temp_project_dir("parse-tasks");
        fs::write(
            dir.join("tasks.json"),
            r#"{
                "issueNumber": 42,
                "subtasks": [
                    {"id": "T-001", "title": "First task", "description": "", "acceptanceCriteria": [], "priority": 1, "passes": false},
                    {"id": "T-002", "title": "Second task", "description": "", "acceptanceCriteria": [], "priority": 2, "passes": true}
                ]
            }"#,
        )
        .expect("tasks.json should be written");

        let subtasks = parse_tasks_json(&dir);

        assert_eq!(subtasks.len(), 2);
        assert_eq!(subtasks[0].id, "T-001");
        assert_eq!(subtasks[0].title, "First task");
        assert!(!subtasks[0].passes);
        assert_eq!(subtasks[1].id, "T-002");
        assert_eq!(subtasks[1].title, "Second task");
        assert!(subtasks[1].passes);

        fs::remove_dir_all(dir).expect("cleanup");
    }

    #[test]
    fn parse_tasks_json_returns_empty_when_missing() {
        let dir = create_temp_project_dir("parse-tasks-missing");

        let subtasks = parse_tasks_json(&dir);

        assert!(subtasks.is_empty());
        fs::remove_dir_all(dir).expect("cleanup");
    }

    #[test]
    fn parse_tasks_json_returns_empty_on_invalid_json() {
        let dir = create_temp_project_dir("parse-tasks-invalid");
        fs::write(dir.join("tasks.json"), "{not valid json").expect("write");

        let subtasks = parse_tasks_json(&dir);

        assert!(subtasks.is_empty());
        fs::remove_dir_all(dir).expect("cleanup");
    }

    #[test]
    fn infer_phase_idle_when_empty() {
        let dir = create_temp_project_dir("phase-idle");

        assert_eq!(infer_phase(&dir), Phase::Idle);
        fs::remove_dir_all(dir).expect("cleanup");
    }

    #[test]
    fn infer_phase_planning_when_only_planning_log() {
        let dir = create_temp_project_dir("phase-planning");
        fs::write(dir.join("planning.log"), "planning output").expect("write");

        assert_eq!(infer_phase(&dir), Phase::Planning);
        fs::remove_dir_all(dir).expect("cleanup");
    }

    #[test]
    fn infer_phase_implementation_when_iteration_log_only() {
        let dir = create_temp_project_dir("phase-impl");
        fs::write(dir.join("planning.log"), "").expect("write");
        fs::write(dir.join("iteration-1-claude.log"), "impl output").expect("write");

        assert_eq!(infer_phase(&dir), Phase::Implementation);
        fs::remove_dir_all(dir).expect("cleanup");
    }

    #[test]
    fn infer_phase_review_when_review_log_exists() {
        let dir = create_temp_project_dir("phase-review");
        fs::write(dir.join("planning.log"), "").expect("write");
        fs::write(dir.join("iteration-2-claude.log"), "").expect("write");
        fs::write(dir.join("iteration-2-codex-review.log"), "review").expect("write");

        assert_eq!(infer_phase(&dir), Phase::Review);
        fs::remove_dir_all(dir).expect("cleanup");
    }

    #[test]
    fn infer_phase_build_lint_test_when_hard_gate_log() {
        let dir = create_temp_project_dir("phase-blt");
        fs::write(dir.join("planning.log"), "").expect("write");
        fs::write(dir.join("iteration-3-claude.log"), "").expect("write");
        fs::write(dir.join("iteration-3-codex-review.log"), "").expect("write");
        fs::write(dir.join("hard-gate-3.log"), "gate results").expect("write");

        assert_eq!(infer_phase(&dir), Phase::BuildLintTest);
        fs::remove_dir_all(dir).expect("cleanup");
    }

    #[test]
    fn infer_phase_uses_latest_iteration() {
        let dir = create_temp_project_dir("phase-latest");
        // Iteration 1 completed with review + hard-gate
        fs::write(dir.join("iteration-1-claude.log"), "").expect("write");
        fs::write(dir.join("iteration-1-codex-review.log"), "").expect("write");
        fs::write(dir.join("hard-gate-1.log"), "").expect("write");
        // Iteration 2 in progress (implementation only)
        fs::write(dir.join("iteration-2-codex.log"), "").expect("write");

        assert_eq!(infer_phase(&dir), Phase::Implementation);
        fs::remove_dir_all(dir).expect("cleanup");
    }

    #[test]
    fn parse_iteration_from_terminal_extracts_last_match() {
        let content = "\
[2026-04-25 08:46:39] 🔄 迭代 1/42\n\
[2026-04-25 09:21:17] 🔄 迭代 2/42\n\
[2026-04-25 09:30:00] 🔄 迭代 3/42\n";

        assert_eq!(parse_iteration_from_terminal(content), Some((3, 42)));
    }

    #[test]
    fn parse_iteration_from_terminal_returns_none_when_no_match() {
        let content = "some log output\nno iteration markers here\n";

        assert_eq!(parse_iteration_from_terminal(content), None);
    }

    #[test]
    fn parse_iteration_from_terminal_handles_continue_mode() {
        let content = "\
[2026-04-25 09:21:17] 继续运行: 已完成 1 轮，再跑 41 轮 (总计 42)\n\
[2026-04-25 09:21:17] 🔄 迭代 2/42\n";

        assert_eq!(parse_iteration_from_terminal(content), Some((2, 42)));
    }

    #[test]
    fn parse_iteration_from_log_md_extracts_iteration_and_total() {
        let content = "\
# Issue #30 实现日志\n\
\n\
### 迭代 2 - Codex (实现)\n\
\n\
### 迭代 4 - Claude (实现)\n\
\n\
## 最终结果\n\
- 总迭代次数: 5\n";

        assert_eq!(parse_iteration_from_log_md(content), Some((4, 5)));
    }

    #[test]
    fn build_iteration_progress_aggregates_data() {
        let dir = create_temp_project_dir("build-progress");
        fs::write(
            dir.join("tasks.json"),
            r#"{"issueNumber": 42, "subtasks": [
                {"id": "T-001", "title": "A", "description": "", "acceptanceCriteria": [], "priority": 1, "passes": true},
                {"id": "T-002", "title": "B", "description": "", "acceptanceCriteria": [], "priority": 2, "passes": false},
                {"id": "T-003", "title": "C", "description": "", "acceptanceCriteria": [], "priority": 3, "passes": true}
            ]}"#,
        )
        .expect("write");
        fs::write(dir.join("planning.log"), "").expect("write");
        fs::write(dir.join("iteration-2-claude.log"), "").expect("write");
        fs::write(dir.join("terminal.log"), "[time] 🔄 迭代 2/16\n").expect("write");

        let progress = build_iteration_progress(&dir);

        assert_eq!(progress.current_iteration, 2);
        assert_eq!(progress.total_iterations, 16);
        assert_eq!(progress.phase, Phase::Implementation);
        assert_eq!(progress.subtasks.len(), 3);
        assert_eq!(progress.subtasks[0].status, SubtaskStatus::Passing);
        assert_eq!(progress.subtasks[1].status, SubtaskStatus::Pending);
        assert_eq!(progress.subtasks[2].status, SubtaskStatus::Passing);
        assert_eq!(progress.passed_count, 2);
        assert_eq!(progress.total_count, 3);

        fs::remove_dir_all(dir).expect("cleanup");
    }

    #[test]
    fn build_iteration_progress_falls_back_to_log_md_when_terminal_missing() {
        let dir = create_temp_project_dir("build-progress-log-md");
        fs::write(dir.join("planning.log"), "").expect("write");
        fs::write(dir.join("iteration-3-claude.log"), "").expect("write");
        fs::write(
            dir.join("log.md"),
            "\
# Issue #31 实现日志\n\
\n\
### 迭代 3 - Claude (实现)\n\
\n\
## 最终结果\n\
- 总迭代次数: 7\n",
        )
        .expect("write");

        let progress = build_iteration_progress(&dir);

        assert_eq!(progress.current_iteration, 3);
        assert_eq!(progress.total_iterations, 7);

        fs::remove_dir_all(dir).expect("cleanup");
    }

    #[test]
    fn build_iteration_progress_falls_back_to_log_md_when_terminal_has_no_match() {
        let dir = create_temp_project_dir("build-progress-terminal-fallback");
        fs::write(dir.join("planning.log"), "").expect("write");
        fs::write(dir.join("iteration-2-claude.log"), "").expect("write");
        fs::write(dir.join("terminal.log"), "no iteration marker here\n").expect("write");
        fs::write(
            dir.join("log.md"),
            "\
# Issue #31 实现日志\n\
\n\
### 迭代 2 - Codex (实现)\n\
\n\
## 最终结果\n\
- 总迭代次数: 42\n",
        )
        .expect("write");

        let progress = build_iteration_progress(&dir);

        assert_eq!(progress.current_iteration, 2);
        assert_eq!(progress.total_iterations, 42);

        fs::remove_dir_all(dir).expect("cleanup");
    }

    #[test]
    fn get_iteration_progress_returns_idle_for_missing_workflow() {
        let dir = create_temp_project_dir("progress-missing");

        let progress = get_iteration_progress_sync(dir.to_string_lossy().as_ref(), 999)
            .expect("should return idle");

        assert_eq!(progress.phase, Phase::Idle);
        assert_eq!(progress.current_iteration, 0);
        assert!(progress.subtasks.is_empty());

        fs::remove_dir_all(dir).expect("cleanup");
    }

    #[test]
    fn get_iteration_progress_returns_data_for_existing_workflow() {
        let dir = create_temp_project_dir("progress-existing");
        let workflow_dir = dir.join(".autoresearch/workflows/issue-42");
        fs::create_dir_all(&workflow_dir).expect("create workflow dir");
        fs::write(
            workflow_dir.join("tasks.json"),
            r#"{"issueNumber": 42, "subtasks": [
                {"id": "T-001", "title": "Task", "description": "", "acceptanceCriteria": [], "priority": 1, "passes": false}
            ]}"#,
        )
        .expect("write");
        fs::write(workflow_dir.join("planning.log"), "plan").expect("write");

        let progress = get_iteration_progress_sync(dir.to_string_lossy().as_ref(), 42)
            .expect("should return progress");

        assert_eq!(progress.phase, Phase::Planning);
        assert_eq!(progress.total_count, 1);
        assert_eq!(progress.passed_count, 0);
        assert_eq!(progress.subtasks[0].status, SubtaskStatus::Pending);

        fs::remove_dir_all(dir).expect("cleanup");
    }

    #[test]
    fn build_iteration_progress_marks_current_subtask_failing_after_failed_review() {
        let dir = create_temp_project_dir("build-progress-failing");
        fs::write(
            dir.join("tasks.json"),
            r#"{"issueNumber": 42, "subtasks": [
                {"id": "T-001", "title": "Passed", "description": "", "acceptanceCriteria": [], "priority": 1, "passes": true},
                {"id": "T-002", "title": "Current", "description": "", "acceptanceCriteria": [], "priority": 2, "passes": false},
                {"id": "T-003", "title": "Later", "description": "", "acceptanceCriteria": [], "priority": 3, "passes": false}
            ]}"#,
        )
        .expect("write");
        fs::write(dir.join("planning.log"), "").expect("write");
        fs::write(dir.join("iteration-2-claude.log"), "").expect("write");
        fs::write(dir.join("iteration-2-codex-review.log"), "").expect("write");
        fs::write(dir.join("terminal.log"), "[time] 🔄 迭代 2/16\n").expect("write");
        fs::write(dir.join(".last_score"), "79\n").expect("write");

        let progress = build_iteration_progress(&dir);

        assert_eq!(progress.subtasks[0].status, SubtaskStatus::Passing);
        assert_eq!(progress.subtasks[1].status, SubtaskStatus::Failing);
        assert_eq!(progress.subtasks[2].status, SubtaskStatus::Pending);

        fs::remove_dir_all(dir).expect("cleanup");
    }
}
