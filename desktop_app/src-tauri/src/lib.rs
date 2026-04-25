use std::fs;
use std::path::Path;
use std::process::Command;
use std::process::Stdio as StdStdio;
use std::sync::Arc;

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

/// Result for the list_issues command, including processed status info.
#[derive(serde::Serialize)]
struct IssuesResult {
    issues: Vec<GhIssue>,
    processed_numbers: Vec<i64>,
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
    state_guard.process = Some(RunProcess { pid });
    drop(state_guard);

    // Reset the killed flag
    get_was_killed().store(false, Ordering::SeqCst);

    // Clone app handle for the spawned task
    let app_clone = app.clone();
    let state_clone = get_run_state();

    // Take stdout/stderr before waiting on the process
    let stdout = child.stdout.take();
    let stderr = child.stderr.take();

    // Spawn a task to wait for process exit and emit event
    tokio::spawn(async move {
        let status = child.wait().await;

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
            start_run,
            stop_run,
            get_run_status,
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}

#[cfg(test)]
mod tests {
    use super::{get_issue_detail_sync, map_issue_detail_command_error, parse_issue_detail, IssueDetail};
    use super::{build_run_args, build_run_env_vars, StartRunRequest};
    #[cfg(unix)]
    use super::RunProcessState;

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
}
