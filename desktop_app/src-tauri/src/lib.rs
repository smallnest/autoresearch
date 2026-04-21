use std::path::Path;

/// Configuration detection result for a project directory.
#[derive(serde::Serialize)]
struct ProjectConfig {
    has_autoresearch_dir: bool,
    has_program_md: bool,
    has_agents_dir: bool,
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
    ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
