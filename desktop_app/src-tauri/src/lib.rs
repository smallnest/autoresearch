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
fn detect_project_config(project_path: String) -> Result<ProjectConfig, String> {
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
fn list_issues(project_path: String) -> Result<IssuesResult, String> {
    let base = Path::new(&project_path);
    if !base.is_dir() {
        return Err(format!("Path is not a directory: {project_path}"));
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
fn check_processed_issues(project_path: String) -> Result<Vec<i64>, String> {
    let base = Path::new(&project_path);
    if !base.is_dir() {
        return Err(format!("Path is not a directory: {project_path}"));
    }
    get_processed_issue_numbers(base)
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
fn get_issue_detail(project_path: String, issue_number: i64) -> Result<IssueDetail, String> {
    let base = Path::new(&project_path);
    if !base.is_dir() {
        return Err(format!("Path is not a directory: {project_path}"));
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
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}

#[cfg(test)]
mod tests {
    use super::{get_issue_detail, map_issue_detail_command_error, parse_issue_detail, IssueDetail};

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
        let error = get_issue_detail("/path/that/does/not/exist".to_string(), 27)
            .expect_err("invalid path should fail");

        assert_eq!(error, "Path is not a directory: /path/that/does/not/exist");
    }
}
