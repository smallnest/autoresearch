# PRD Generator Skill

Generate structured Product Requirements Documents (PRD) for new features.

## Features

- Asks 3-5 clarifying questions with lettered options for quick iteration
- Generates well-structured PRD with user stories, functional requirements, non-goals, and more
- Supports user review and adjustment before saving
- Saves output to `tasks/prd-[feature-name].md`
- Bilingual (Chinese & English) edge case handling

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

