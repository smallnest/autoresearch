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
Iteration 1: Claude implements → tests run
Iteration 2+: Codex/OpenCode/Claude round-robin review + fix
    → Score >= 85? → auto commit/PR/merge/close Issue
    → Score < 85?  → agent fixes based on review feedback → next iteration
```

Agent rotation (from iteration 2): `(iter - 1) % 3` maps to codex → opencode → claude → ...

### Agent Invocation

Agents are external CLIs called via `run_with_retry()` with exponential backoff:
- **Claude**: `claude -p "$prompt" --dangerously-skip-permissions`
- **Codex**: `codex exec --full-auto "$prompt"`
- **OpenCode**: `opencode run "$prompt"`

### Prompt Assembly

Each agent prompt composes three parts:
1. Task context (Issue info, project path, language, iteration)
2. `program.md` content — global rules and constraints
3. Agent-specific instructions from `agents/<name>.md`

For review prompts, only task context + agent instructions are included (no program.md).

### Configuration Override (Two-Tier)

Project-level configs in `$PROJECT_ROOT/.autoresearch/` take precedence over defaults in the autoresearch directory:
- `agents/<name>.md` — agent persona and review rubric
- `program.md` — implementation rules and code standards

### Score Extraction

`extract_score()` parses free-text review output using 6 cascading regex patterns (X/100, **评分: X/100**, 总分 table, X/10, **评分: X**, 评分: X). If no score is found, defaults to 0; review functions fall back to 50 on extraction failure.

### Continue Mode (`-c`)

Restores state from `.autoresearch/workflows/issue-N/` log files: iteration count, last score, consecutive failure count, and last review feedback. MAX_ITERATIONS becomes `last_iteration + new_count`.

## Key Design Constraints

- Agents cannot push to remote, close Issues, create PRs, or modify CI/CD — only `run.sh` performs those privileged operations after quality gates pass
- `program.md` contains code standards for Go/Python/TypeScript/Rust/Frontend — the README advises trimming to only the target project's language to save tokens
- Consecutive iteration failures >= 2 triggers a hard stop
- Default passing score is 85/100, configurable via `PASSING_SCORE` env var
