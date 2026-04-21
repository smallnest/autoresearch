use std::fs;
use std::path::Path;
use std::process::Command;

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
fn detect_project_config(project_path: String) -> Result<ProjectConfig, String> {
    let base = Path::new(&project_path);
    if !base.is_dir() {
        return Err(format!("Path is not a directory: {}", project_path));
    }
    Ok(ProjectConfig {
        has_autoresearch_dir: base.join(".autoresearch").is_dir(),
        has_program_md: base.join(".autoresearch").join("program.md").is_file(),
        has_agents_dir: base.join(".autoresearch").join("agents").is_dir(),
    })
}

/// Retrieves the most recently opened project path from the Tauri store.
#[tauri::command]
async fn get_recent_project(app: tauri::AppHandle) -> Result<Option<String>, String> {
    let store = tauri_plugin_store::StoreExt::store(&app, "app.json")
        .map_err(|e| format!("Failed to open store: {}", e))?;
    let value = store
        .get("recent_project")
        .and_then(|v| v.as_str().map(String::from));
    Ok(value)
}

/// Saves the project path to the Tauri store as the most recent project.
#[tauri::command]
async fn save_recent_project(app: tauri::AppHandle, path: String) -> Result<(), String> {
    let store = tauri_plugin_store::StoreExt::store(&app, "app.json")
        .map_err(|e| format!("Failed to open store: {}", e))?;
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
    let entries = fs::read_dir(&workflows_dir).map_err(|e| format!("Failed to read workflows dir: {}", e))?;
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
fn list_issues(project_path: String) -> Result<IssuesResult, String> {
    let base = Path::new(&project_path);
    if !base.is_dir() {
        return Err(format!("Path is not a directory: {}", project_path));
    }

    // Check that gh is available
    let gh_check = Command::new("gh")
        .args(["--version"])
        .current_dir(base)
        .output()
        .map_err(|_| "gh CLI is not installed or not found in PATH".to_string())?;

    if !gh_check.status.success() {
        return Err("gh CLI check failed — please ensure gh is installed and accessible".to_string());
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
        .map_err(|e| format!("Failed to execute gh: {}", e))?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        return Err(format!("gh issue list failed: {}", stderr.trim()));
    }

    let stdout = String::from_utf8_lossy(&output.stdout);
    let issues: Vec<GhIssue> = serde_json::from_str(&stdout)
        .map_err(|e| format!("Failed to parse gh output: {}. Output: {}", e, stdout))?;

    let processed_numbers = get_processed_issue_numbers(base)?;

    Ok(IssuesResult {
        issues,
        processed_numbers,
    })
}

/// Returns a list of Issue numbers that have already been processed by autoresearch.
#[tauri::command]
fn check_processed_issues(project_path: String) -> Result<Vec<i64>, String> {
    let base = Path::new(&project_path);
    if !base.is_dir() {
        return Err(format!("Path is not a directory: {}", project_path));
    }
    get_processed_issue_numbers(base)
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
    ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
