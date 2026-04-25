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

## Tests
- Keep process-management tests in `src/lib.rs` as pure helper tests where possible; use a short-lived `sh -c "exit 0"` child on Unix to verify shared state stores both PID and handle without adding sleeps.
