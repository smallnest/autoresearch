# desktop_app

## Architecture
- Tauri v2 desktop application with Rust backend and web frontend
- Rust commands are defined in `src-tauri/src/lib.rs` using `#[tauri::command]` macro
- Plugins are registered in the `tauri::Builder` chain in `run()`
- Capabilities (permissions) are configured in `src-tauri/capabilities/default.json`

## Dependencies
- `tauri-plugin-dialog`: Native file/folder dialogs (`DialogExt`)
- `tauri-plugin-store`: Key-value persistence (`StoreExt`, stored in `app.json`)
- `tauri-plugin-opener`: Default opener plugin

## Tauri Commands
- Commands use `tauri::AppHandle` for accessing plugins
- Async commands should avoid blocking calls in production; `blocking_pick_folder()` is acceptable for dialog simplicity
- Store plugin path: `"app.json"` stores app-level data like `recent_project`

## Notes
- `detect_project_config` checks for `.autoresearch/`, `.autoresearch/program.md`, `.autoresearch/agents/`
- `select_project_dir` returns `Option<String>` (None if user cancels)
- The lib name is `desktop_app_lib` (not `desktop_app`) to avoid Windows naming conflict
