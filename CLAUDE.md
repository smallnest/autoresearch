# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

autoresearch is a fully automated software development tool: given a GitHub Issue number, it implements the feature through multi-agent iterative review, then auto-creates a PR, merges it, and closes the Issue. The entire runtime is a single Bash script (`run.sh`).

## Running

```bash
# Process Issue #N in the current directory's project
./run.sh 42

# With project path, max iterations, or continue mode
./run.sh -p /path/to/project 42 16
./run.sh -c 42 10              # Continue from last interrupted iteration
```

There are no build/test/lint commands for autoresearch itself. The only test file is `tests/test_extract_score.sh` which tests the score parsing logic.

## Architecture

### Iteration Loop

```
Planning Phase: First agent reads Issue → outputs tasks.json with subtask breakdown
Iteration 1: Agent implements current subtask → tests run
Iteration 2+: Agent round-robin review + fix per subtask
    → Score >= 85? → mark subtask passed → advance to next subtask
    → Score < 85?  → agent fixes based on review feedback → next iteration
    → All subtasks passed? → auto commit/PR/merge/close Issue
```

If planning fails (no tasks.json generated), falls back to original mode: implement entire Issue in one go.

Agent rotation (from iteration 2): `(iter - 1) % N` where N = number of agents.

### Subtask System (tasks.json)

Planning phase (before iteration 1) asks the first agent to split the Issue into subtasks, saved to `.autoresearch/workflows/issue-N/tasks.json`:

```json
{
  "issueNumber": 42,
  "subtasks": [
    { "id": "T-001", "title": "...", "description": "...", "acceptanceCriteria": [...], "priority": 1, "passes": false }
  ]
}
```

- Each iteration focuses on one `passes: false` subtask
- Quality gate passes → `mark_subtask_passed()` sets `passes: true`
- `all_subtasks_passed()` → enters PR/merge flow
- No tasks.json (planning failure) → backward-compatible original mode

### Agent Invocation

Agents are external CLIs called via `run_with_retry()` with exponential backoff:
- **Claude**: `claude -p "$prompt" --dangerously-skip-permissions`
- **Codex**: `codex exec --full-auto "$prompt"`
- **OpenCode**: `opencode run "$prompt"`

### Prompt Assembly

Each agent prompt composes these parts:
1. Task context (Issue info, project path, language, iteration)
2. Subtask section (current subtask details + progress) — from `get_subtask_section()` / `get_subtask_review_section()`
3. `program.md` content — global rules and constraints
4. Agent-specific instructions from `agents/<name>.md`

For review prompts, only task context + subtask review section + agent instructions are included (no program.md).

### Configuration Override (Two-Tier)

Project-level configs in `$PROJECT_ROOT/.autoresearch/` take precedence over defaults in the autoresearch directory:
- `agents/<name>.md` — agent persona and review rubric
- `program.md` — implementation rules and code standards

### Score Extraction

`extract_score()` parses free-text review output using 6 cascading regex patterns (X/100, **评分: X/100**, 总分 table, X/10, **评分: X**, 评分: X). If no score is found, defaults to 0; review functions fall back to 50 on extraction failure.

### Continue Mode (`-c`)

Restores state from `.autoresearch/workflows/issue-N/` log files: iteration count, last score, consecutive failure count, last review feedback, and subtask state (from tasks.json). MAX_ITERATIONS becomes `last_iteration + new_count`.

## Key Design Constraints

- Agents cannot push to remote, close Issues, create PRs, or modify CI/CD — only `run.sh` performs those privileged operations after quality gates pass
- `program.md` contains code standards for Go/Python/TypeScript/Rust/Frontend — the README advises trimming to only the target project's language to save tokens
- Consecutive iteration failures >= 2 triggers a hard stop
- Default passing score is 85/100, configurable via `PASSING_SCORE` env var
