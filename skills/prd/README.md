# PRD Generator + Issue Decomposer Skill

Generate structured Product Requirements Documents (PRD) for new features, then decompose them into implementable Issues.

## Features

- Asks 3-5 clarifying questions with lettered options for quick iteration
- Generates well-structured PRD with user stories, functional requirements, non-goals, and more
- Supports user review and adjustment before saving
- Saves output to `tasks/prd-[feature-name].md`
- **Decomposes PRD into small, independent, implementable Issues**
- **Creates Issues in three platforms: GitHub / Local / Baidu iCafe**
- Bilingual (Chinese & English) edge case handling

## Issue Creation Modes

| Mode | Tool | Notes |
|------|------|-------|
| **GitHub** | `gh issue create` | Requires `gh` CLI authenticated |
| **Local** | `.md` files | Asks user for folder path, auto-creates if not exists |
| **Baidu iCafe** | `icafe-cli card create` | Asks user for `--space` parameter, default `--target-branch` is `master` |

## Usage

Trigger with prompts like:

- "create a prd for..."
- "write prd for..."
- "写PRD"
- "需求文档"
- "需求分析"

## Files

- `SKILL.md` — Skill definition and instructions
- `test-prompts.json` — Test prompts for validation

## Attribution

This skill is adapted from [ralph/skills/prd](https://github.com/snarktank/ralph/tree/main/skills/prd).
