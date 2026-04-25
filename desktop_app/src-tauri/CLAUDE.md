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
- For iteration progress, parse `terminal.log` first for `🔄 迭代 N/M`; if that marker is missing, fall back to `log.md` by reading the last `### 迭代 N - ...` heading and the last `总迭代次数: N` entry.
- `iteration-progress` 事件应携带 `issue_number` 和完整 `IterationProgress`，前端可以据此忽略非当前 Issue 的推送，避免全局 store 串数据。
- `tasks.json` 的 `passes` 只能表达“已通过/未通过”；如果 UI 需要 `pending/passing/failing`，应在 Rust 侧基于当前 subtask 和最新 review / hard-gate 结果生成显式 `status` 字段。

## Tests
- Keep process-management tests in `src/lib.rs` as pure helper tests where possible; use a short-lived `sh -c "exit 0"` child on Unix to verify shared state stores both PID and handle without adding sleeps.
