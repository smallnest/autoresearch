# src-tauri

## Process Management
- Use Tauri-managed `Arc<Mutex<Option<ProcessState>>>` for app-wide run state instead of a standalone `static Mutex`; commands can receive it via `tauri::State`.
- `ProcessState` should keep both the process `pid` and a shared child handle (`Arc<tokio::sync::Mutex<tokio::process::Child>>`) so async wait tasks and stop logic can coordinate on the same process.
- Clear the stored state with a PID match check to avoid an old watcher wiping out a newer run that started after stop/restart.
- Attach stdout/stderr readers and exit watchers only after the new `ProcessState` has been stored; otherwise a fast-exiting child can race the state write and leave a stale `running` entry behind.

## Unix Process Groups
- On Unix, start `run.sh` with `tokio::process::Command` and set the child process group in `pre_exec` via `nix::unistd::setpgid(0, 0)`.
- When terminating the Unix run group, prefer `nix::sys::signal::killpg` with the stored PID as the process-group id.

## run.sh Invocation Contract
- In desktop-app commands, `projectPath` refers to the repository being processed, not the autoresearch installation directory. Resolve the `run.sh` executable relative to the autoresearch app/repo root, then pass the selected repository via `-p <projectPath>` when the target project is outside the autoresearch repo itself.
- Keep argument-building tests separate from process-spawn tests; pure tests can cover flag ordering, but start/exit event behavior needs at least one integration-style backend test that exercises real child stdout/stderr forwarding.

## Workflow Logs
- Workflow log browsing should stay inside `.autoresearch/workflows/issue-N/`; expose file metadata and file contents through Tauri commands rather than letting the frontend assemble arbitrary filesystem paths.
- Validate `source_id` as a single filename (no path separators or `..`) before reading a workflow log file to avoid traversal bugs.
- Keep workflow log ordering stable for the UI: `terminal.log` first, `log.md` second, then iteration logs, then other files alphabetically.
- When sorting iteration logs, parse the numeric prefix from `iteration-N-...` and sort by `N`; plain lexicographic ordering will put `iteration-10` before `iteration-2`.
- Any helper that selects the "latest review" must share the same tie-break rule as score-history aggregation for duplicate `iteration-N-*-review.log` files; otherwise the score badge, summary, and trend chart can show conflicting data from the same iteration.
- For iteration progress, parse `terminal.log` first for `🔄 迭代 N/M`; if that marker is missing, fall back to `log.md` by reading the last `### 迭代 N - ...` heading and the last `总迭代次数: N` entry.
- `iteration-progress` 事件应携带 `issue_number` 和完整 `IterationProgress`，前端可以据此忽略非当前 Issue 的推送，避免全局 store 串数据。
- `tasks.json` 的 `passes` 只能表达“已通过/未通过”；如果 UI 需要 `pending/passing/failing`，应在 Rust 侧基于当前 subtask 和最新 review / hard-gate 结果生成显式 `status` 字段。

## Project Config Initialization
- `init_project_config` should only create missing files under `<project>/.autoresearch/`; never overwrite an existing `program.md` or existing agent template file.
- Reuse the repo-root `program.md` and `agents/*.md` as built-in templates via `include_str!`, so desktop init stays aligned with CLI defaults without runtime filesystem lookups.
- Keep the command return type consistent with `detect_project_config` by returning the refreshed `ProjectConfig` after initialization; the frontend can use that directly to refresh badge state.
- `detect_project_config` must report only `.autoresearch/` overrides, not similarly named files at the repo root; the desktop app should reflect the same config source that `run.sh` actually reads.
- Config editor commands should expose only a fixed whitelist (`program.md`, `agents/claude.md`, `agents/codex.md`, `agents/opencode.md`) instead of arbitrary relative paths; read falls back to built-in templates, while write/reset always materialize the project override under `<project>/.autoresearch/`.
- When saving or resetting a project config override, create a sibling `.bak` backup of the previous project file before overwriting so the frontend does not need separate backup logic.
- `read_config_file` should fail fast when a whitelisted target path exists but is not a regular file; silently falling back to the built-in template hides broken project state from the UI.
- Apply the same fail-fast rule to ancestor path conflicts too: if `<project>/.autoresearch` or an intermediate parent exists as a regular file, `read_config_file` should surface that broken state instead of pretending the default template is usable.
- Whitelisting logical file ids is not enough for config-file commands: reject symlinked ancestors and symlinked target files too, otherwise `<project>/.autoresearch` can point outside the project and `fs::write` / `fs::copy` will still touch arbitrary paths.
- Do not use `Path::exists()` / `is_file()` alone for config security checks; broken symlinks return false there. Use `symlink_metadata`-based inspection so dangling target files and dangling `.bak` symlinks are rejected before read/write.

## Tests
- Keep process-management tests in `src/lib.rs` as pure helper tests where possible; use a short-lived `sh -c "exit 0"` child on Unix to verify shared state stores both PID and handle without adding sleeps.
- For frontend-facing file commands, return enough metadata (`file_id`, `relative_path`, `source`) for the UI to render source/target labels without reconstructing backend path rules on the client.
- For config-file write/reset work (Issue #34 / T-002), Rust tests must cover both first-time materialization into `<project>/.autoresearch/` and overwrite-with-backup; covering only the overwrite case is not enough for acceptance.
- Do not treat `reset_config_file` as covered just because `write_config_file` already has a first-write test; reset needs its own first-materialization test to prove default-template restore also creates the project override when the file was previously absent.
- Add a negative test for symlink escapes in config-file commands; directory/file-shape validation alone does not prove writes stay under the selected project root.
- Symlink-escape coverage should include dangling symlinks too; a broken target or broken backup symlink can still be followed by `fs::write` / `fs::copy` if validation only checks `exists()`.
- T-002 review should be scored against `.autoresearch/workflows/issue-N/planning.log` when `tasks.json` contains placeholder acceptance text; the Rust acceptance bar here is command registration plus `.autoresearch` materialization, `.bak` backup, default-template reset, and rejection of non-whitelisted targets.
- Helper functions that only exist for unit tests should either be exercised by production code or annotated deliberately; this crate runs `cargo clippy -- -D warnings`, so otherwise `dead_code` will fail the build.
- For review-text helpers, prefer deterministic line-based extraction around the matched score line: keep the score line itself plus the nearest non-empty context lines, instead of taking an arbitrary leading window that may drop the actual summary sentence after the score.
