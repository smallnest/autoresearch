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
- `list_issues` calls `gh issue list --json` and also scans `.autoresearch/workflows/issue-*` for processed status
- `check_processed_issues` is a standalone command that only scans processed Issue numbers
- `gh` CLI errors (not installed, no repo, no auth) are surfaced as `Result::Err` strings
- `GhIssue` and `GhLabel` structs use `serde::Deserialize` to parse `gh` JSON output; `createdAt` is renamed via `#[serde(rename)]`

## Error Handling Patterns
- Tauri commands consistently use `Result<T, String>` for error handling
- All errors are surfaced as descriptive strings via `map_err(|e| format!("...", e))`
- External command errors (gh CLI) are checked via `output.status.success()` before parsing stdout
- File system errors include context about which path failed (e.g., "Failed to read workflows dir")

## JSON Parsing Patterns
- External command JSON output uses `serde_json::from_str()` with explicit error messages
- Include the raw output in parse error messages for easier debugging
- Use `#[serde(rename = "camelCase")]` for fields that differ from Rust naming conventions

## Testing Patterns
- When a Tauri command shells out to `gh`, extract pure helper functions for JSON parsing and stderr-to-user-error mapping so unit tests do not depend on a live GitHub CLI session
- For backend command tests, cover both success parsing and representative failure modes (invalid input path, malformed JSON, known `gh` stderr patterns such as missing issues)
- Keep the `#[cfg(test)] mod tests` block at the end of `src-tauri/src/lib.rs` to satisfy clippy's `items_after_test_module` lint
