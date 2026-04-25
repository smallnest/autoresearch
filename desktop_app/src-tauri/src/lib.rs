use std::fs;
use std::path::Path;
use std::process::Command;
use std::process::Stdio as StdStdio;
use std::sync::Arc;
use std::sync::OnceLock;
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
#[derive(Debug, serde::Serialize)]
struct ProjectConfig {
    has_autoresearch_dir: bool,
    has_program_md: bool,
    has_agents_dir: bool,
}

/// Frontend-facing contents for a supported configuration file.
#[derive(Debug, serde::Serialize, PartialEq, Eq)]
struct ConfigFileContent {
    file_id: String,
    relative_path: String,
    content: String,
    source: String,
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

/// Score trend point extracted from a review log for one iteration.
#[derive(serde::Serialize, Debug, Clone, PartialEq, Eq)]
struct ScoreHistoryPoint {
    /// Iteration number (1-based).
    iteration: i32,
    /// Review score on a 0-100 scale.
    score: i32,
    /// Optional short summary extracted from the review text.
    review_summary: Option<String>,
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
    /// Last review score (0–100), None if no review yet.
    last_score: Option<i32>,
    /// Score threshold for passing (default 85).
    passing_score: i32,
    /// Short summary extracted from the latest review.
    review_summary: Option<String>,
    /// Historical review scores ordered by iteration ascending.
    score_history: Vec<ScoreHistoryPoint>,
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
// Score extraction helpers
// ========================================

use regex::Regex;

const PROGRAM_TEMPLATE: &str = include_str!("../../../program.md");
const CLAUDE_AGENT_TEMPLATE: &str = include_str!("../../../agents/claude.md");
const CODEX_AGENT_TEMPLATE: &str = include_str!("../../../agents/codex.md");
const OPENCODE_AGENT_TEMPLATE: &str = include_str!("../../../agents/opencode.md");

fn supported_config_file(file_id: &str) -> Option<(&'static str, &'static str)> {
    match file_id {
        "program.md" => Some(("program.md", PROGRAM_TEMPLATE)),
        "agents/claude.md" => Some(("agents/claude.md", CLAUDE_AGENT_TEMPLATE)),
        "agents/codex.md" => Some(("agents/codex.md", CODEX_AGENT_TEMPLATE)),
        "agents/opencode.md" => Some(("agents/opencode.md", OPENCODE_AGENT_TEMPLATE)),
        _ => None,
    }
}

fn score_number_regex() -> &'static Regex {
    static REGEX: OnceLock<Regex> = OnceLock::new();
    REGEX.get_or_init(|| Regex::new(r"\d+\.?\d*").expect("valid score number regex"))
}

fn explicit_hundred_regex() -> &'static Regex {
    static REGEX: OnceLock<Regex> = OnceLock::new();
    REGEX.get_or_init(|| Regex::new(r"(\d+\.?\d*)\s*/\s*100").expect("valid X/100 regex"))
}

fn bold_hundred_regex() -> &'static Regex {
    static REGEX: OnceLock<Regex> = OnceLock::new();
    REGEX.get_or_init(|| Regex::new(r"(?i)\*\*(评分|Score)[^*]*100").expect("valid bold 100 regex"))
}

fn total_score_table_regex() -> &'static Regex {
    static REGEX: OnceLock<Regex> = OnceLock::new();
    REGEX.get_or_init(|| {
        Regex::new(r"(\*\*)?总分(\*\*)?\s*\|.*\*\*\d").expect("valid total score table regex")
    })
}

fn total_score_arrow_regex() -> &'static Regex {
    static REGEX: OnceLock<Regex> = OnceLock::new();
    REGEX.get_or_init(|| Regex::new(r"总分.*→").expect("valid total score arrow regex"))
}

fn explicit_ten_regex() -> &'static Regex {
    static REGEX: OnceLock<Regex> = OnceLock::new();
    REGEX.get_or_init(|| Regex::new(r"(\d+\.?\d*)\s*/\s*10\b").expect("valid X/10 regex"))
}

fn bold_score_regex() -> &'static Regex {
    static REGEX: OnceLock<Regex> = OnceLock::new();
    REGEX.get_or_init(|| Regex::new(r"(?i)\*\*(评分|Score)").expect("valid bold score regex"))
}

fn plain_score_regex() -> &'static Regex {
    static REGEX: OnceLock<Regex> = OnceLock::new();
    REGEX.get_or_init(|| Regex::new(r"(?i)(评分|Score)\s*:").expect("valid plain score regex"))
}

fn dimension_exclude_regex() -> &'static Regex {
    static REGEX: OnceLock<Regex> = OnceLock::new();
    REGEX.get_or_init(|| Regex::new(r"各维度|维度").expect("valid dimension exclude regex"))
}

fn summary_score_patterns() -> &'static [Regex; 4] {
    static REGEXES: OnceLock<[Regex; 4]> = OnceLock::new();
    REGEXES.get_or_init(|| {
        [
            Regex::new(r"\d+\.?\d*\s*/\s*100").expect("valid summary 100 regex"),
            Regex::new(r"(?i)\*\*(评分|Score)").expect("valid summary bold regex"),
            Regex::new(r"(?i)(评分|Score)\s*:").expect("valid summary plain regex"),
            Regex::new(r"总分").expect("valid summary total regex"),
        ]
    })
}

/// Extracts a score from free-text review output.
///
/// Mirrors the 6-pattern cascade in `lib/scoring.sh`'s `extract_score()`:
///   1. Explicit `X/100`
///   2. `**评分: X/100**` or `**Score: X/100**`
///   3. 总分 table row (e.g. `| **总分** | ... | **8.5** |` or `总分 → 85`)
///   4. `X/10` (converted ×10)
///   5. `**评分: X**` or `**Score: X**` (≤10 converted ×10)
///   6. `评分: X` or `Score: X` (excluding lines with 各维度/维度, ≤10 converted ×10)
///
/// Returns `None` when no pattern matches (caller can treat as 0).
fn extract_score(review: &str) -> Option<i32> {
    // Pattern 1: X/100
    if let Some(caps) = explicit_hundred_regex().captures(review) {
        if let Some(score) = parse_score_str(caps.get(1).unwrap().as_str()) {
            return Some(score);
        }
    }

    // Pattern 2: **评分: X/100** or **Score: X/100**
    for line in review.lines() {
        if bold_hundred_regex().is_match(line) {
            if let Some(m) = score_number_regex().find(line) {
                if let Some(score) = parse_score_str(m.as_str()) {
                    return Some(score);
                }
            }
        }
    }

    // Pattern 3: 总分 table row — either `| **总分** | ... | **8.5** |` or `总分.*→`
    // The shell version takes the last number via `tail -1`, then multiplies by 10.
    for line in review.lines() {
        if total_score_table_regex().is_match(line) || total_score_arrow_regex().is_match(line) {
            if let Some(m) = score_number_regex().find_iter(line).last() {
                if let Some(score) = parse_score_str_scaled(m.as_str(), 10.0) {
                    return Some(score);
                }
            }
        }
    }

    // Pattern 4: X/10 (multiply by 10)
    // Rust regex doesn't support lookahead, so use \b word boundary instead.
    if let Some(caps) = explicit_ten_regex().captures(review) {
        if let Some(score) = parse_score_str_scaled(caps.get(1).unwrap().as_str(), 10.0) {
            return Some(score);
        }
    }

    // Pattern 5: **评分: X** or **Score: X** (≤10 → ×10)
    for line in review.lines() {
        if bold_score_regex().is_match(line) {
            if let Some(m) = score_number_regex().find(line) {
                if let Some(score) = parse_score_str(m.as_str()) {
                    if score == 0 {
                        return Some(0);
                    }
                    return Some(if score <= 10 { score * 10 } else { score });
                }
            }
        }
    }

    // Pattern 6: 评分: X or Score: X (exclude 各维度/维度 lines, ≤10 → ×10)
    for line in review.lines() {
        if plain_score_regex().is_match(line) && !dimension_exclude_regex().is_match(line) {
            if let Some(m) = score_number_regex().find(line) {
                if let Some(score) = parse_score_str(m.as_str()) {
                    if score == 0 {
                        return Some(0);
                    }
                    return Some(if score <= 10 { score * 10 } else { score });
                }
            }
        }
    }

    None
}

/// Parse a numeric string (possibly with a decimal point) into an integer score.
fn parse_score_str(s: &str) -> Option<i32> {
    s.parse::<f64>().ok().map(|v| v.round() as i32)
}

/// Parse a numeric string and multiply by a factor before rounding.
/// Used for scores on a 10-point scale that need ×10 conversion.
fn parse_score_str_scaled(s: &str, factor: f64) -> Option<i32> {
    s.parse::<f64>().ok().map(|v| (v * factor).round() as i32)
}

/// Extracts a brief review summary from the text surrounding the score line.
///
/// Finds the first line that looks like a score, then returns up to 3 non-empty
/// lines around it as the key summary.
fn extract_review_summary(review: &str) -> Option<String> {
    let lines: Vec<&str> = review.lines().collect();

    for (i, line) in lines.iter().enumerate() {
        let is_score_line = summary_score_patterns().iter().any(|re| re.is_match(line));
        if !is_score_line {
            continue;
        }

        let mut selected = vec![i];

        if let Some(previous) = nearest_non_empty_line(&lines, i, SearchDirection::Backward) {
            selected.push(previous);
        }
        if let Some(next) = nearest_non_empty_line(&lines, i, SearchDirection::Forward) {
            selected.push(next);
        }

        selected.sort_unstable();
        selected.dedup();

        let summary = selected
            .into_iter()
            .take(3)
            .map(|idx| lines[idx].trim())
            .filter(|line| !line.is_empty())
            .collect::<Vec<_>>()
            .join("\n");

        if !summary.is_empty() {
            return Some(summary);
        }
    }

    None
}

#[derive(Clone, Copy)]
enum SearchDirection {
    Backward,
    Forward,
}

fn nearest_non_empty_line(
    lines: &[&str],
    pivot: usize,
    direction: SearchDirection,
) -> Option<usize> {
    match direction {
        SearchDirection::Backward => (0..pivot).rev().find(|&idx| !lines[idx].trim().is_empty()),
        SearchDirection::Forward => {
            ((pivot + 1)..lines.len()).find(|&idx| !lines[idx].trim().is_empty())
        }
    }
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

/// Finds the latest review log file in the workflow directory and returns its content.
/// Looks for `iteration-N-*-review.log` files and picks the one with the highest N.
fn find_latest_review_content(workflow_dir: &Path) -> Option<String> {
    let entries = fs::read_dir(workflow_dir).ok()?;
    let mut best: Option<(i32, std::path::PathBuf)> = None;

    for entry in entries.flatten() {
        let name = entry.file_name();
        let name_str = name.to_string_lossy();
        if name_str.ends_with("-review.log") {
            if let Some(n) = iteration_number(&name_str) {
                if best.as_ref().is_none_or(|(prev_n, _)| n > *prev_n) {
                    best = Some((n, entry.path()));
                }
            }
        }
    }

    let (_, path) = best?;
    fs::read_to_string(path).ok()
}

fn build_score_history(workflow_dir: &Path) -> Vec<ScoreHistoryPoint> {
    let entries = match fs::read_dir(workflow_dir) {
        Ok(entries) => entries,
        Err(_) => return Vec::new(),
    };

    let mut best_by_iteration: std::collections::BTreeMap<i32, std::path::PathBuf> =
        std::collections::BTreeMap::new();

    for entry in entries.flatten() {
        let path = entry.path();
        let Some(name) = path
            .file_name()
            .map(|name| name.to_string_lossy().to_string())
        else {
            continue;
        };

        if !name.ends_with("-review.log") {
            continue;
        }

        let Some(iteration) = iteration_number(&name) else {
            continue;
        };

        let replace = best_by_iteration
            .get(&iteration)
            .and_then(|existing| existing.file_name())
            .map(|current| name.as_str() > current.to_string_lossy().as_ref())
            .unwrap_or(true);

        if replace {
            best_by_iteration.insert(iteration, path);
        }
    }

    best_by_iteration
        .into_iter()
        .filter_map(|(iteration, path)| {
            let content = fs::read_to_string(path).ok()?;
            let score = extract_score(&content)?;
            Some(ScoreHistoryPoint {
                iteration,
                score,
                review_summary: extract_review_summary(&content),
            })
        })
        .collect()
}

/// Reads the passing score from environment variable PASSING_SCORE, defaulting to 85.
fn get_passing_score() -> i32 {
    std::env::var("PASSING_SCORE")
        .ok()
        .and_then(|v| v.trim().parse::<i32>().ok())
        .unwrap_or(85)
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
        return if has_planning {
            Phase::Planning
        } else {
            Phase::Idle
        };
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
                let total_str: String = total_rest
                    .chars()
                    .take_while(|c| c.is_ascii_digit())
                    .collect();
                if let (Ok(current), Ok(total)) =
                    (current_str.parse::<i32>(), total_str.parse::<i32>())
                {
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
            let iteration_str: String = rest.chars().take_while(|c| c.is_ascii_digit()).collect();
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

    let review_content = find_latest_review_content(workflow_dir);
    let last_score = review_content.as_deref().and_then(extract_score);
    let review_summary = review_content.as_deref().and_then(extract_review_summary);
    let passing_score = get_passing_score();
    let score_history = build_score_history(workflow_dir);

    IterationProgress {
        current_iteration,
        total_iterations,
        phase,
        subtasks,
        passed_count,
        total_count,
        last_score,
        passing_score,
        review_summary,
        score_history,
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
            last_score: None,
            passing_score: get_passing_score(),
            review_summary: None,
            score_history: Vec::new(),
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
        detect_project_config_sync(base, &project_path)
    })
    .await
    .map_err(|e| format!("Task join error: {e}"))?
}

/// Initializes missing `.autoresearch/` config files from built-in templates.
#[tauri::command]
async fn init_project_config(project_path: String) -> Result<ProjectConfig, String> {
    tokio::task::spawn_blocking(move || {
        let base = Path::new(&project_path);
        init_project_config_sync(base, &project_path)
    })
    .await
    .map_err(|e| format!("Task join error: {e}"))?
}

fn detect_project_config_sync(base: &Path, project_path: &str) -> Result<ProjectConfig, String> {
    if !base.is_dir() {
        return Err(format!("Path is not a directory: {project_path}"));
    }

    let ar = base.join(".autoresearch");
    Ok(ProjectConfig {
        has_autoresearch_dir: ar.is_dir(),
        has_program_md: ar.join("program.md").is_file(),
        has_agents_dir: ar.join("agents").is_dir(),
    })
}

fn init_project_config_sync(base: &Path, project_path: &str) -> Result<ProjectConfig, String> {
    detect_project_config_sync(base, project_path)?;

    let config_dir = base.join(".autoresearch");
    create_dir_if_missing(&config_dir, "config directory")?;

    let program_path = config_dir.join("program.md");
    write_file_if_missing(&program_path, PROGRAM_TEMPLATE, "program template")?;

    let agents_dir = config_dir.join("agents");
    create_dir_if_missing(&agents_dir, "agents directory")?;
    write_file_if_missing(
        &agents_dir.join("claude.md"),
        CLAUDE_AGENT_TEMPLATE,
        "Claude agent template",
    )?;
    write_file_if_missing(
        &agents_dir.join("codex.md"),
        CODEX_AGENT_TEMPLATE,
        "Codex agent template",
    )?;
    write_file_if_missing(
        &agents_dir.join("opencode.md"),
        OPENCODE_AGENT_TEMPLATE,
        "OpenCode agent template",
    )?;

    detect_project_config_sync(base, project_path)
}

fn create_dir_if_missing(path: &Path, label: &str) -> Result<(), String> {
    if path.exists() {
        if path.is_dir() {
            return Ok(());
        }
        return Err(format!(
            "Cannot create {label}: path exists and is not a directory: {}",
            path.display()
        ));
    }

    fs::create_dir_all(path)
        .map_err(|e| format!("Failed to create {label} at {}: {e}", path.display()))
}

fn write_file_if_missing(path: &Path, content: &str, label: &str) -> Result<(), String> {
    if path.exists() {
        if path.is_file() {
            return Ok(());
        }
        return Err(format!(
            "Cannot create {label}: path exists and is not a file: {}",
            path.display()
        ));
    }

    fs::write(path, content)
        .map_err(|e| format!("Failed to write {label} at {}: {e}", path.display()))
}

fn resolve_project_config_file_path(
    base: &Path,
    file_id: &str,
) -> Result<std::path::PathBuf, String> {
    let (relative_path, _) = supported_config_file(file_id)
        .ok_or_else(|| format!("Unsupported config file: {file_id}"))?;

    Ok(base.join(".autoresearch").join(relative_path))
}

enum ConfigPathState {
    Missing,
    Metadata(fs::Metadata),
}

fn config_path_state(path: &Path) -> Result<ConfigPathState, String> {
    match fs::symlink_metadata(path) {
        Ok(metadata) => Ok(ConfigPathState::Metadata(metadata)),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(ConfigPathState::Missing),
        Err(error) => Err(format!(
            "Failed to inspect config path {}: {error}",
            path.display()
        )),
    }
}

fn validate_config_path(base: &Path, path: &Path) -> Result<(), String> {
    let relative_path = path.strip_prefix(base).map_err(|_| {
        format!(
            "Config file path escapes project directory: {}",
            path.display()
        )
    })?;
    let mut current = base.to_path_buf();

    for component in relative_path.components() {
        current.push(component);

        let ConfigPathState::Metadata(metadata) = config_path_state(&current)? else {
            continue;
        };
        if metadata.file_type().is_symlink() {
            return Err(format!(
                "Config path contains symlink: {}",
                current.display()
            ));
        }

        if current == path {
            if !metadata.is_file() {
                return Err(format!(
                    "Config file path is not a file: {}",
                    current.display()
                ));
            }
        } else if !metadata.is_dir() {
            return Err(format!(
                "Config path ancestor is not a directory: {}",
                current.display()
            ));
        }
    }

    Ok(())
}

fn read_config_file_sync(
    base: &Path,
    project_path: &str,
    file_id: &str,
) -> Result<ConfigFileContent, String> {
    let (relative_path, default_content) = supported_config_file(file_id)
        .ok_or_else(|| format!("Unsupported config file: {file_id}"))?;

    if !base.is_dir() {
        return Err(format!("Path is not a directory: {project_path}"));
    }

    let project_config_path = resolve_project_config_file_path(base, file_id)?;
    validate_config_path(base, &project_config_path)?;

    let (content, source) = if matches!(
        config_path_state(&project_config_path)?,
        ConfigPathState::Metadata(metadata) if metadata.is_file()
    ) {
        (
            fs::read_to_string(&project_config_path).map_err(|e| {
                format!(
                    "Failed to read config file {}: {e}",
                    project_config_path.display()
                )
            })?,
            "project",
        )
    } else {
        (default_content.to_string(), "default")
    };

    Ok(ConfigFileContent {
        file_id: file_id.to_string(),
        relative_path: relative_path.to_string(),
        content,
        source: source.to_string(),
    })
}

fn ensure_parent_dir(base: &Path, path: &Path, label: &str) -> Result<(), String> {
    validate_config_path(base, path)?;
    let parent = path
        .parent()
        .ok_or_else(|| format!("Missing parent directory for {label}"))?;
    fs::create_dir_all(parent).map_err(|e| {
        format!(
            "Failed to create parent directory for {label} at {}: {e}",
            parent.display()
        )
    })
}

fn backup_existing_file(path: &Path) -> Result<(), String> {
    match config_path_state(path)? {
        ConfigPathState::Missing => return Ok(()),
        ConfigPathState::Metadata(metadata) => {
            if metadata.file_type().is_symlink() {
                return Err(format!("Config path contains symlink: {}", path.display()));
            }
            if !metadata.is_file() {
                return Err(format!(
                    "Cannot back up config file because path is not a file: {}",
                    path.display()
                ));
            }
        }
    }

    let file_name = path
        .file_name()
        .and_then(|name| name.to_str())
        .ok_or_else(|| format!("Invalid config filename: {}", path.display()))?;
    let backup_path = path.with_file_name(format!("{file_name}.bak"));
    if let ConfigPathState::Metadata(metadata) = config_path_state(&backup_path)? {
        if metadata.file_type().is_symlink() {
            return Err(format!(
                "Backup path contains symlink: {}",
                backup_path.display()
            ));
        }
        if !metadata.is_file() {
            return Err(format!(
                "Backup path is not a file: {}",
                backup_path.display()
            ));
        }
    }

    fs::copy(path, &backup_path).map_err(|e| {
        format!(
            "Failed to create backup {} from {}: {e}",
            backup_path.display(),
            path.display()
        )
    })?;

    Ok(())
}

fn write_config_file_sync(
    base: &Path,
    project_path: &str,
    file_id: &str,
    content: &str,
) -> Result<ConfigFileContent, String> {
    if !base.is_dir() {
        return Err(format!("Path is not a directory: {project_path}"));
    }

    let target_path = resolve_project_config_file_path(base, file_id)?;
    ensure_parent_dir(base, &target_path, "config file")?;
    backup_existing_file(&target_path)?;
    fs::write(&target_path, content)
        .map_err(|e| format!("Failed to write config file {}: {e}", target_path.display()))?;

    read_config_file_sync(base, project_path, file_id)
}

fn reset_config_file_sync(
    base: &Path,
    project_path: &str,
    file_id: &str,
) -> Result<ConfigFileContent, String> {
    let (_, default_content) = supported_config_file(file_id)
        .ok_or_else(|| format!("Unsupported config file: {file_id}"))?;
    write_config_file_sync(base, project_path, file_id, default_content)
}

/// Reads a supported configuration file using project overrides first, then built-in defaults.
#[tauri::command]
async fn read_config_file(
    project_path: String,
    file_id: String,
) -> Result<ConfigFileContent, String> {
    tokio::task::spawn_blocking(move || {
        let base = Path::new(&project_path);
        read_config_file_sync(base, &project_path, &file_id)
    })
    .await
    .map_err(|e| format!("Task join error: {e}"))?
}

/// Writes a supported configuration file into `<project>/.autoresearch/` and creates a `.bak`.
#[tauri::command]
async fn write_config_file(
    project_path: String,
    file_id: String,
    content: String,
) -> Result<ConfigFileContent, String> {
    tokio::task::spawn_blocking(move || {
        let base = Path::new(&project_path);
        write_config_file_sync(base, &project_path, &file_id, &content)
    })
    .await
    .map_err(|e| format!("Task join error: {e}"))?
}

/// Restores a supported configuration file to the built-in default template.
#[tauri::command]
async fn reset_config_file(
    project_path: String,
    file_id: String,
) -> Result<ConfigFileContent, String> {
    tokio::task::spawn_blocking(move || {
        let base = Path::new(&project_path);
        reset_config_file_sync(base, &project_path, &file_id)
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
    let entries =
        fs::read_dir(&workflows_dir).map_err(|e| format!("Failed to read workflows dir: {e}"))?;
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
    tokio::task::spawn_blocking(move || list_issues_sync(&project_path))
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
            "issue",
            "list",
            "--json",
            "number,title,labels,createdAt,state",
            "--limit",
            "100",
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
    serde_json::from_str(stdout)
        .map_err(|e| format!("Failed to parse gh output: {e}. Output: {stdout}"))
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

fn list_issue_log_sources_sync(
    project_path: &str,
    issue_number: i64,
) -> Result<Vec<IssueLogSource>, String> {
    let issue_dir = workflow_issue_dir(project_path, issue_number)?;
    let entries =
        fs::read_dir(&issue_dir).map_err(|e| format!("Failed to read workflow dir: {e}"))?;

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
    tokio::task::spawn_blocking(move || get_issue_detail_sync(&project_path, issue_number))
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
            "issue",
            "view",
            &issue_number.to_string(),
            "--json",
            "body,comments",
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
    let mut args = vec!["-p".to_string(), request.project_path.clone()];

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
        return Err(
            "A run is already in progress. Stop the current run before starting a new one."
                .to_string(),
        );
    }

    // Validate project path
    let project_path = Path::new(&request.project_path);
    if !project_path.is_dir() {
        return Err(format!(
            "Project path is not a directory: {}",
            request.project_path
        ));
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
                eprintln!(
                    "Warning: Failed to set process group: {}",
                    std::io::Error::last_os_error()
                );
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
            init_project_config,
            read_config_file,
            write_config_file,
            reset_config_file,
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
    #[cfg(unix)]
    use super::RunProcessState;
    use super::{
        build_iteration_progress, build_score_history, detect_project_config_sync,
        find_latest_review_content, get_iteration_progress_sync, infer_phase,
        init_project_config_sync, parse_iteration_from_log_md, parse_iteration_from_terminal,
        parse_tasks_json, read_config_file_sync, reset_config_file_sync, write_config_file_sync,
        Phase, SubtaskStatus,
    };
    use super::{build_run_args, build_run_env_vars, StartRunRequest};
    use super::{
        classify_log_source, get_issue_detail_sync, iteration_number, list_issue_log_sources_sync,
        map_issue_detail_command_error, parse_issue_detail, read_issue_log_content_sync,
        resolve_issue_log_source_path, workflow_issue_dir, IssueDetail, IssueLogSource,
    };
    use super::{extract_review_summary, extract_score};
    use std::fs;
    #[cfg(unix)]
    use std::os::unix::fs as unix_fs;
    use std::path::PathBuf;

    fn create_temp_project_dir(test_name: &str) -> PathBuf {
        let root = std::env::temp_dir().join(format!(
            "autoresearch-log-viewer-{test_name}-{}",
            std::process::id()
        ));
        let _ = fs::remove_dir_all(&root);
        fs::create_dir_all(&root).expect("temp project dir should be created");
        root
    }

    #[test]
    fn init_project_config_creates_missing_template_files() {
        let project_dir = create_temp_project_dir("init-project-config-full");

        let config = init_project_config_sync(&project_dir, project_dir.to_string_lossy().as_ref())
            .expect("init should succeed");

        assert!(config.has_autoresearch_dir);
        assert!(config.has_program_md);
        assert!(config.has_agents_dir);
        assert_eq!(
            fs::read_to_string(project_dir.join(".autoresearch/program.md"))
                .expect("program template should exist"),
            super::PROGRAM_TEMPLATE
        );
        assert_eq!(
            fs::read_to_string(project_dir.join(".autoresearch/agents/claude.md"))
                .expect("claude template should exist"),
            super::CLAUDE_AGENT_TEMPLATE
        );
        assert_eq!(
            fs::read_to_string(project_dir.join(".autoresearch/agents/codex.md"))
                .expect("codex template should exist"),
            super::CODEX_AGENT_TEMPLATE
        );
        assert_eq!(
            fs::read_to_string(project_dir.join(".autoresearch/agents/opencode.md"))
                .expect("opencode template should exist"),
            super::OPENCODE_AGENT_TEMPLATE
        );

        fs::remove_dir_all(project_dir).expect("cleanup");
    }

    #[test]
    fn init_project_config_only_fills_missing_files() {
        let project_dir = create_temp_project_dir("init-project-config-partial");
        let config_dir = project_dir.join(".autoresearch");
        let agents_dir = config_dir.join("agents");
        fs::create_dir_all(&agents_dir).expect("agents dir should exist");
        fs::write(config_dir.join("program.md"), "custom program\n").expect("program should exist");
        fs::write(agents_dir.join("codex.md"), "custom codex\n").expect("codex should exist");

        let config = init_project_config_sync(&project_dir, project_dir.to_string_lossy().as_ref())
            .expect("init should succeed");

        assert!(config.has_autoresearch_dir);
        assert!(config.has_program_md);
        assert!(config.has_agents_dir);
        assert_eq!(
            fs::read_to_string(config_dir.join("program.md")).expect("program should still exist"),
            "custom program\n"
        );
        assert_eq!(
            fs::read_to_string(agents_dir.join("codex.md")).expect("codex should still exist"),
            "custom codex\n"
        );
        assert_eq!(
            fs::read_to_string(agents_dir.join("claude.md")).expect("claude should be created"),
            super::CLAUDE_AGENT_TEMPLATE
        );
        assert_eq!(
            fs::read_to_string(agents_dir.join("opencode.md")).expect("opencode should be created"),
            super::OPENCODE_AGENT_TEMPLATE
        );

        fs::remove_dir_all(project_dir).expect("cleanup");
    }

    #[test]
    fn init_project_config_rejects_non_directory_project_path() {
        let file_path = std::env::temp_dir().join(format!(
            "autoresearch-init-project-config-file-{}",
            std::process::id()
        ));
        let _ = fs::remove_file(&file_path);
        fs::write(&file_path, "not a directory").expect("temp file should exist");

        let error = init_project_config_sync(&file_path, file_path.to_string_lossy().as_ref())
            .expect_err("file path should fail");

        assert_eq!(
            error,
            format!("Path is not a directory: {}", file_path.display())
        );
        fs::remove_file(file_path).expect("cleanup");
    }

    #[test]
    fn init_project_config_reports_conflicting_config_paths() {
        let project_dir = create_temp_project_dir("init-project-config-conflict");
        fs::write(project_dir.join(".autoresearch"), "conflict")
            .expect("conflict file should exist");

        let error = init_project_config_sync(&project_dir, project_dir.to_string_lossy().as_ref())
            .expect_err("conflicting .autoresearch file should fail");

        assert!(
            error.contains("config directory"),
            "expected config directory error, got: {error}"
        );
        assert!(
            error.contains(".autoresearch"),
            "expected path in error, got: {error}"
        );

        fs::remove_dir_all(project_dir).expect("cleanup");
    }

    #[test]
    fn detect_project_config_only_counts_autoresearch_overrides() {
        let project_dir = create_temp_project_dir("detect-project-config-overrides");
        fs::create_dir_all(project_dir.join("agents")).expect("root agents dir should exist");
        fs::write(project_dir.join("program.md"), "root program\n")
            .expect("root program should exist");

        let config =
            detect_project_config_sync(&project_dir, project_dir.to_string_lossy().as_ref())
                .expect("config should load");

        assert!(!config.has_autoresearch_dir);
        assert!(!config.has_program_md);
        assert!(!config.has_agents_dir);

        fs::remove_dir_all(project_dir).expect("cleanup");
    }

    #[test]
    fn read_config_file_prefers_project_override() {
        let project_dir = create_temp_project_dir("read-config-project-override");
        let config_dir = project_dir.join(".autoresearch");
        fs::create_dir_all(config_dir.join("agents")).expect("agents dir should exist");
        fs::write(config_dir.join("program.md"), "custom program\n").expect("program should exist");

        let config = read_config_file_sync(
            &project_dir,
            project_dir.to_string_lossy().as_ref(),
            "program.md",
        )
        .expect("config should load");

        assert_eq!(config.file_id, "program.md");
        assert_eq!(config.relative_path, "program.md");
        assert_eq!(config.content, "custom program\n");
        assert_eq!(config.source, "project");

        fs::remove_dir_all(project_dir).expect("cleanup");
    }

    #[test]
    fn read_config_file_falls_back_to_default_template() {
        let project_dir = create_temp_project_dir("read-config-default");

        let config = read_config_file_sync(
            &project_dir,
            project_dir.to_string_lossy().as_ref(),
            "agents/claude.md",
        )
        .expect("config should load");

        assert_eq!(config.file_id, "agents/claude.md");
        assert_eq!(config.relative_path, "agents/claude.md");
        assert_eq!(config.content, super::CLAUDE_AGENT_TEMPLATE);
        assert_eq!(config.source, "default");

        fs::remove_dir_all(project_dir).expect("cleanup");
    }

    #[test]
    fn read_config_file_fails_when_target_path_is_directory() {
        let project_dir = create_temp_project_dir("read-config-directory-target");
        let target_dir = project_dir.join(".autoresearch/agents/codex.md");
        fs::create_dir_all(&target_dir).expect("target directory should exist");

        let error = read_config_file_sync(
            &project_dir,
            project_dir.to_string_lossy().as_ref(),
            "agents/codex.md",
        )
        .expect_err("directory target should fail");

        assert!(
            error.contains("Config file path is not a file"),
            "unexpected error: {error}"
        );

        fs::remove_dir_all(project_dir).expect("cleanup");
    }

    #[test]
    fn read_config_file_fails_when_autoresearch_path_is_file() {
        let project_dir = create_temp_project_dir("read-config-file-ancestor");
        fs::write(project_dir.join(".autoresearch"), "broken").expect("broken file should exist");

        let error = read_config_file_sync(
            &project_dir,
            project_dir.to_string_lossy().as_ref(),
            "agents/codex.md",
        )
        .expect_err("ancestor file should fail");

        assert!(
            error.contains("Config path ancestor is not a directory"),
            "unexpected error: {error}"
        );
        assert!(
            error.contains(".autoresearch"),
            "expected ancestor path in error: {error}"
        );

        fs::remove_dir_all(project_dir).expect("cleanup");
    }

    #[test]
    fn write_config_file_creates_project_override_and_backup() {
        let project_dir = create_temp_project_dir("write-config-backup");
        let target_dir = project_dir.join(".autoresearch/agents");
        fs::create_dir_all(&target_dir).expect("agents dir should exist");
        fs::write(target_dir.join("codex.md"), "old codex\n")
            .expect("existing config should exist");

        let config = write_config_file_sync(
            &project_dir,
            project_dir.to_string_lossy().as_ref(),
            "agents/codex.md",
            "new codex\n",
        )
        .expect("write should succeed");

        assert_eq!(config.content, "new codex\n");
        assert_eq!(config.source, "project");
        assert_eq!(
            fs::read_to_string(target_dir.join("codex.md")).expect("new config should exist"),
            "new codex\n"
        );
        assert_eq!(
            fs::read_to_string(target_dir.join("codex.md.bak")).expect("backup should exist"),
            "old codex\n"
        );

        fs::remove_dir_all(project_dir).expect("cleanup");
    }

    #[test]
    fn write_config_file_materializes_first_project_override() {
        let project_dir = create_temp_project_dir("write-config-first-materialization");
        let target_path = project_dir.join(".autoresearch/program.md");

        let config = write_config_file_sync(
            &project_dir,
            project_dir.to_string_lossy().as_ref(),
            "program.md",
            "custom program\n",
        )
        .expect("first write should succeed");

        assert_eq!(config.file_id, "program.md");
        assert_eq!(config.relative_path, "program.md");
        assert_eq!(config.content, "custom program\n");
        assert_eq!(config.source, "project");
        assert_eq!(
            fs::read_to_string(&target_path).expect("project override should exist"),
            "custom program\n"
        );
        assert!(
            !target_path.with_file_name("program.md.bak").exists(),
            "first write should not create a backup when no previous file exists"
        );

        fs::remove_dir_all(project_dir).expect("cleanup");
    }

    #[test]
    fn reset_config_file_restores_default_template() {
        let project_dir = create_temp_project_dir("reset-config-default");
        let target_dir = project_dir.join(".autoresearch/agents");
        fs::create_dir_all(&target_dir).expect("agents dir should exist");
        fs::write(target_dir.join("opencode.md"), "custom opencode\n")
            .expect("existing config should exist");

        let config = reset_config_file_sync(
            &project_dir,
            project_dir.to_string_lossy().as_ref(),
            "agents/opencode.md",
        )
        .expect("reset should succeed");

        assert_eq!(config.content, super::OPENCODE_AGENT_TEMPLATE);
        assert_eq!(config.source, "project");
        assert_eq!(
            fs::read_to_string(target_dir.join("opencode.md")).expect("reset config should exist"),
            super::OPENCODE_AGENT_TEMPLATE
        );
        assert_eq!(
            fs::read_to_string(target_dir.join("opencode.md.bak")).expect("backup should exist"),
            "custom opencode\n"
        );

        fs::remove_dir_all(project_dir).expect("cleanup");
    }

    #[test]
    fn reset_config_file_materializes_first_project_override() {
        let project_dir = create_temp_project_dir("reset-config-first-materialization");
        let target_path = project_dir.join(".autoresearch/agents/claude.md");

        let config = reset_config_file_sync(
            &project_dir,
            project_dir.to_string_lossy().as_ref(),
            "agents/claude.md",
        )
        .expect("reset should materialize project override");

        assert_eq!(config.file_id, "agents/claude.md");
        assert_eq!(config.relative_path, "agents/claude.md");
        assert_eq!(config.content, super::CLAUDE_AGENT_TEMPLATE);
        assert_eq!(config.source, "project");
        assert_eq!(
            fs::read_to_string(&target_path).expect("reset config should exist"),
            super::CLAUDE_AGENT_TEMPLATE
        );
        assert!(
            !target_path.with_file_name("claude.md.bak").exists(),
            "first reset should not create a backup when no previous file exists"
        );

        fs::remove_dir_all(project_dir).expect("cleanup");
    }

    #[test]
    fn config_file_commands_reject_unsupported_file_id() {
        let project_dir = create_temp_project_dir("config-file-invalid-id");

        let error = read_config_file_sync(
            &project_dir,
            project_dir.to_string_lossy().as_ref(),
            "../secret.txt",
        )
        .expect_err("invalid file id should fail");

        assert_eq!(error, "Unsupported config file: ../secret.txt");
        fs::remove_dir_all(project_dir).expect("cleanup");
    }

    #[test]
    fn write_config_file_rejects_unsupported_file_id() {
        let project_dir = create_temp_project_dir("write-config-invalid-id");

        let error = write_config_file_sync(
            &project_dir,
            project_dir.to_string_lossy().as_ref(),
            "../secret.txt",
            "value",
        )
        .expect_err("invalid file id should fail");

        assert_eq!(error, "Unsupported config file: ../secret.txt");
        fs::remove_dir_all(project_dir).expect("cleanup");
    }

    #[test]
    fn reset_config_file_rejects_unsupported_file_id() {
        let project_dir = create_temp_project_dir("reset-config-invalid-id");

        let error = reset_config_file_sync(
            &project_dir,
            project_dir.to_string_lossy().as_ref(),
            "../secret.txt",
        )
        .expect_err("invalid file id should fail");

        assert_eq!(error, "Unsupported config file: ../secret.txt");
        fs::remove_dir_all(project_dir).expect("cleanup");
    }

    #[test]
    fn write_config_file_fails_when_target_path_is_directory() {
        let project_dir = create_temp_project_dir("write-config-directory-target");
        let target_dir = project_dir.join(".autoresearch/agents/codex.md");
        fs::create_dir_all(&target_dir).expect("target directory should exist");

        let error = write_config_file_sync(
            &project_dir,
            project_dir.to_string_lossy().as_ref(),
            "agents/codex.md",
            "new codex\n",
        )
        .expect_err("directory target should fail");

        assert!(
            error.contains("Config file path is not a file"),
            "unexpected error: {error}"
        );

        fs::remove_dir_all(project_dir).expect("cleanup");
    }

    #[cfg(unix)]
    #[test]
    fn read_config_file_rejects_symlinked_config_ancestor() {
        let project_dir = create_temp_project_dir("read-config-symlink-ancestor");
        let external_dir = create_temp_project_dir("read-config-symlink-ancestor-external");
        unix_fs::symlink(&external_dir, project_dir.join(".autoresearch"))
            .expect("symlinked config dir should exist");

        let error = read_config_file_sync(
            &project_dir,
            project_dir.to_string_lossy().as_ref(),
            "program.md",
        )
        .expect_err("symlinked config dir should fail");

        assert!(
            error.contains("Config path contains symlink"),
            "unexpected error: {error}"
        );
        assert!(
            error.contains(".autoresearch"),
            "expected symlink path in error: {error}"
        );

        fs::remove_dir_all(project_dir).expect("cleanup project");
        fs::remove_dir_all(external_dir).expect("cleanup external");
    }

    #[cfg(unix)]
    #[test]
    fn write_config_file_rejects_symlinked_target_file() {
        let project_dir = create_temp_project_dir("write-config-symlink-target");
        let target_dir = project_dir.join(".autoresearch/agents");
        let external_dir = create_temp_project_dir("write-config-symlink-target-external");
        let external_file = external_dir.join("codex.md");
        fs::create_dir_all(&target_dir).expect("agents dir should exist");
        fs::write(&external_file, "external codex\n").expect("external file should exist");
        unix_fs::symlink(&external_file, target_dir.join("codex.md"))
            .expect("symlinked target file should exist");

        let error = write_config_file_sync(
            &project_dir,
            project_dir.to_string_lossy().as_ref(),
            "agents/codex.md",
            "new codex\n",
        )
        .expect_err("symlinked target file should fail");

        assert!(
            error.contains("Config path contains symlink"),
            "unexpected error: {error}"
        );
        assert!(
            error.contains("codex.md"),
            "expected target path in error: {error}"
        );
        assert_eq!(
            fs::read_to_string(&external_file).expect("external file should remain unchanged"),
            "external codex\n"
        );

        fs::remove_dir_all(project_dir).expect("cleanup project");
        fs::remove_dir_all(external_dir).expect("cleanup external");
    }

    #[cfg(unix)]
    #[test]
    fn read_config_file_rejects_broken_symlink_target() {
        let project_dir = create_temp_project_dir("read-config-broken-symlink-target");
        let target_dir = project_dir.join(".autoresearch/agents");
        let missing_target = project_dir.join("missing-codex.md");
        fs::create_dir_all(&target_dir).expect("agents dir should exist");
        unix_fs::symlink(&missing_target, target_dir.join("codex.md"))
            .expect("broken symlink target should exist");

        let error = read_config_file_sync(
            &project_dir,
            project_dir.to_string_lossy().as_ref(),
            "agents/codex.md",
        )
        .expect_err("broken symlink target should fail");

        assert!(
            error.contains("Config path contains symlink"),
            "unexpected error: {error}"
        );
        assert!(
            error.contains("codex.md"),
            "expected target path in error: {error}"
        );

        fs::remove_dir_all(project_dir).expect("cleanup project");
    }

    #[cfg(unix)]
    #[test]
    fn write_config_file_rejects_broken_symlink_backup_path() {
        let project_dir = create_temp_project_dir("write-config-broken-symlink-backup");
        let target_dir = project_dir.join(".autoresearch/agents");
        let missing_backup_target = project_dir.join("missing-claude-backup.md");
        fs::create_dir_all(&target_dir).expect("agents dir should exist");
        fs::write(target_dir.join("claude.md"), "custom claude\n")
            .expect("project config should exist");
        unix_fs::symlink(&missing_backup_target, target_dir.join("claude.md.bak"))
            .expect("broken symlink backup path should exist");

        let error = write_config_file_sync(
            &project_dir,
            project_dir.to_string_lossy().as_ref(),
            "agents/claude.md",
            "new claude\n",
        )
        .expect_err("broken symlink backup path should fail");

        assert!(
            error.contains("Backup path contains symlink"),
            "unexpected error: {error}"
        );
        assert_eq!(
            fs::read_to_string(target_dir.join("claude.md"))
                .expect("project config should remain unchanged"),
            "custom claude\n"
        );

        fs::remove_dir_all(project_dir).expect("cleanup project");
    }

    #[cfg(unix)]
    #[test]
    fn reset_config_file_rejects_symlinked_backup_path() {
        let project_dir = create_temp_project_dir("reset-config-symlink-backup");
        let target_dir = project_dir.join(".autoresearch/agents");
        let external_dir = create_temp_project_dir("reset-config-symlink-backup-external");
        let backup_target = external_dir.join("claude.md");
        fs::create_dir_all(&target_dir).expect("agents dir should exist");
        fs::write(target_dir.join("claude.md"), "custom claude\n")
            .expect("project config should exist");
        fs::write(&backup_target, "external backup\n").expect("external backup should exist");
        unix_fs::symlink(&backup_target, target_dir.join("claude.md.bak"))
            .expect("symlinked backup path should exist");

        let error = reset_config_file_sync(
            &project_dir,
            project_dir.to_string_lossy().as_ref(),
            "agents/claude.md",
        )
        .expect_err("symlinked backup path should fail");

        assert!(
            error.contains("Backup path contains symlink"),
            "unexpected error: {error}"
        );
        assert_eq!(
            fs::read_to_string(target_dir.join("claude.md"))
                .expect("project config should remain unchanged"),
            "custom claude\n"
        );
        assert_eq!(
            fs::read_to_string(&backup_target).expect("external backup should remain unchanged"),
            "external backup\n"
        );

        fs::remove_dir_all(project_dir).expect("cleanup project");
        fs::remove_dir_all(external_dir).expect("cleanup external");
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
        let error = map_issue_detail_command_error(
            27,
            "GraphQL: Could not resolve to an issue with the number of 27.",
        );

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
        assert_eq!(
            classify_log_source("terminal.log"),
            ("terminal", "终端日志".to_string())
        );
        assert_eq!(
            classify_log_source("log.md"),
            ("summary", "工作流摘要".to_string())
        );
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
        fs::write(
            workflow_dir.join("iteration-10-codex-review.log"),
            "iteration10",
        )
        .expect("iteration log");
        fs::write(
            workflow_dir.join("iteration-2-codex-review.log"),
            "iteration",
        )
        .expect("iteration log");
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

        let content =
            read_issue_log_content_sync(project_dir.to_string_lossy().as_ref(), 30, "terminal.log")
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

    // ========================================
    // extract_score tests
    // ========================================

    #[test]
    fn extract_score_pattern1_explicit_x_out_of_100() {
        assert_eq!(extract_score("总评分 78/100"), Some(78));
        assert_eq!(extract_score("得分：85 / 100"), Some(85));
        assert_eq!(extract_score("score: 92.5/100"), Some(93));
    }

    #[test]
    fn extract_score_pattern2_bold_score_100() {
        assert_eq!(extract_score("**评分: 78/100**\n其他内容"), Some(78));
        assert_eq!(extract_score("**Score: 85/100**"), Some(85));
    }

    #[test]
    fn extract_score_pattern3_total_score_table() {
        // Markdown table row with 总分
        let input = "| **总分** | | **8.5** |";
        assert_eq!(extract_score(input), Some(85));

        // Arrow format
        let input2 = "总分 → 7.8";
        assert_eq!(extract_score(input2), Some(78));
    }

    #[test]
    fn extract_score_pattern4_x_out_of_10() {
        assert_eq!(extract_score("评分: 8/10"), Some(80));
        assert_eq!(extract_score("得分 7.5 / 10"), Some(75));
        // Should not match X/100 as pattern 4
        assert_eq!(extract_score("85/100"), Some(85)); // matched by pattern 1
    }

    #[test]
    fn extract_score_pattern5_bold_score_plain() {
        assert_eq!(extract_score("**评分: 78**"), Some(78));
        assert_eq!(extract_score("**Score: 8**"), Some(80)); // ≤10 → ×10
        assert_eq!(extract_score("**评分: 0**"), Some(0));
    }

    #[test]
    fn extract_score_pattern6_plain_score_colon() {
        assert_eq!(extract_score("评分: 85"), Some(85));
        assert_eq!(extract_score("Score: 7"), Some(70)); // ≤10 → ×10
        assert_eq!(extract_score("Score: 0"), Some(0));
    }

    #[test]
    fn extract_score_pattern6_excludes_dimension_lines() {
        // Lines with 各维度 or 维度 should be excluded
        let input = "各维度评分: 80\n评分: 75";
        assert_eq!(extract_score(input), Some(75));
    }

    #[test]
    fn extract_score_no_match() {
        assert_eq!(extract_score("没有任何评分内容"), None);
        assert_eq!(extract_score(""), None);
    }

    #[test]
    fn extract_score_decimal_rounding() {
        assert_eq!(extract_score("78.6/100"), Some(79));
        assert_eq!(extract_score("78.4/100"), Some(78));
    }

    #[test]
    fn extract_score_pattern1_takes_priority() {
        // When multiple patterns match, pattern 1 should win
        let input = "**评分: 60**\n总分 85/100";
        assert_eq!(extract_score(input), Some(85));
    }

    // ========================================
    // extract_review_summary tests
    // ========================================

    #[test]
    fn extract_review_summary_returns_context_around_score() {
        let review = "## 审核报告\n\n总体评价\n\n**评分: 78/100**\n\n代码质量不错";
        let summary = extract_review_summary(review);
        assert!(summary.is_some());
        let s = summary.unwrap();
        assert!(s.contains("总体评价"));
        assert!(s.contains("78/100"));
        assert!(s.contains("代码质量不错"));
    }

    #[test]
    fn extract_review_summary_none_for_no_score() {
        assert_eq!(
            extract_review_summary("just some text\nno scores here"),
            None
        );
    }

    #[test]
    fn extract_review_summary_limits_to_three_lines() {
        let review = "line1\nline2\nline3\n评分: 85\nline5\nline6\nline7";
        let summary = extract_review_summary(review).unwrap();
        let count = summary.lines().count();
        assert!(
            count <= 3,
            "summary should have at most 3 lines, got {count}"
        );
    }

    #[test]
    fn extract_review_summary_prefers_immediate_non_empty_neighbors() {
        let review = "封面标题\n\n章节标题\n\n评分: 85\n\n关键问题：测试覆盖不足\n\n收尾段落";
        let summary = extract_review_summary(review).unwrap();

        assert_eq!(summary, "章节标题\n评分: 85\n关键问题：测试覆盖不足");
    }

    #[test]
    fn extract_review_summary_supports_total_score_lines() {
        let review = "总体评价\n| **总分** | | **8.5** |\n建议补充边界测试";
        let summary = extract_review_summary(review).unwrap();

        assert_eq!(
            summary,
            "总体评价\n| **总分** | | **8.5** |\n建议补充边界测试"
        );
    }

    // ========================================
    // find_latest_review_content tests
    // ========================================

    #[test]
    fn find_latest_review_content_picks_highest_iteration() {
        let dir = create_temp_project_dir("find-review");
        fs::write(
            dir.join("iteration-1-codex-review.log"),
            "评分: 60/100\n旧审核",
        )
        .expect("write");
        fs::write(
            dir.join("iteration-3-claude-review.log"),
            "**评分: 85/100**\n新审核内容",
        )
        .expect("write");
        fs::write(dir.join("iteration-2-claude.log"), "implementation only").expect("write");

        let content = find_latest_review_content(&dir);
        assert!(content.is_some());
        assert!(content.unwrap().contains("85/100"));

        fs::remove_dir_all(dir).expect("cleanup");
    }

    #[test]
    fn find_latest_review_content_returns_none_when_no_review() {
        let dir = create_temp_project_dir("find-review-none");
        fs::write(dir.join("iteration-1-claude.log"), "implementation").expect("write");

        assert!(find_latest_review_content(&dir).is_none());
        fs::remove_dir_all(dir).expect("cleanup");
    }

    #[test]
    fn build_score_history_collects_one_scored_review_per_iteration() {
        let dir = create_temp_project_dir("score-history");
        fs::write(
            dir.join("iteration-1-claude-review.log"),
            "总体评价\n评分: 72\n需要补充测试",
        )
        .expect("write");
        fs::write(
            dir.join("iteration-2-codex-review.log"),
            "## 审核\n\n**评分: 88/100**\n\n实现已接近完成",
        )
        .expect("write");
        fs::write(
            dir.join("iteration-2-claude-review.log"),
            "评分: 84\n较早的同迭代审核",
        )
        .expect("write");
        fs::write(
            dir.join("iteration-3-claude-review.log"),
            "没有评分的审核文本",
        )
        .expect("write");

        let history = build_score_history(&dir);

        assert_eq!(history.len(), 2);
        assert_eq!(history[0].iteration, 1);
        assert_eq!(history[0].score, 72);
        assert_eq!(history[1].iteration, 2);
        assert_eq!(history[1].score, 88);
        assert!(history[1]
            .review_summary
            .as_deref()
            .is_some_and(|summary| summary.contains("88/100")));

        fs::remove_dir_all(dir).expect("cleanup");
    }

    #[test]
    fn build_iteration_progress_includes_score_from_review() {
        let dir = create_temp_project_dir("build-progress-score");
        fs::write(
            dir.join("tasks.json"),
            r#"{"issueNumber": 42, "subtasks": [
                {"id": "T-001", "title": "A", "description": "", "acceptanceCriteria": [], "priority": 1, "passes": false}
            ]}"#,
        )
        .expect("write");
        fs::write(dir.join("planning.log"), "").expect("write");
        fs::write(dir.join("iteration-1-claude.log"), "").expect("write");
        fs::write(
            dir.join("iteration-1-codex-review.log"),
            "## 审核报告\n\n总体评价\n\n**评分: 78/100**\n\n代码质量不错",
        )
        .expect("write");
        fs::write(dir.join("terminal.log"), "[time] 🔄 迭代 1/16\n").expect("write");

        let progress = build_iteration_progress(&dir);

        assert_eq!(progress.last_score, Some(78));
        assert_eq!(progress.passing_score, 85);
        assert!(progress.review_summary.is_some());
        assert_eq!(progress.score_history.len(), 1);
        assert_eq!(progress.score_history[0].iteration, 1);
        assert_eq!(progress.score_history[0].score, 78);
        let summary = progress.review_summary.unwrap();
        assert!(summary.contains("78/100"));

        fs::remove_dir_all(dir).expect("cleanup");
    }

    #[test]
    fn build_iteration_progress_no_score_when_no_review() {
        let dir = create_temp_project_dir("build-progress-no-score");
        fs::write(
            dir.join("tasks.json"),
            r#"{"issueNumber": 42, "subtasks": [
                {"id": "T-001", "title": "A", "description": "", "acceptanceCriteria": [], "priority": 1, "passes": false}
            ]}"#,
        )
        .expect("write");
        fs::write(dir.join("planning.log"), "").expect("write");
        fs::write(dir.join("iteration-1-claude.log"), "implementation").expect("write");
        fs::write(dir.join("terminal.log"), "[time] 🔄 迭代 1/16\n").expect("write");

        let progress = build_iteration_progress(&dir);

        assert_eq!(progress.last_score, None);
        assert_eq!(progress.review_summary, None);
        assert!(progress.score_history.is_empty());

        fs::remove_dir_all(dir).expect("cleanup");
    }
}
