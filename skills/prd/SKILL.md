---
name: prd
description: "Generate a Product Requirements Document (PRD) for a new feature, then decompose it into implementable Issues. Use when planning a feature, starting a new project, or when asked to create a PRD. Triggers on: create a prd, write prd for, plan this feature, requirements for, spec out, 写PRD, 需求文档, 需求分析, 规格说明."
user-invocable: true
---

# PRD Generator + Issue Decomposer

Create detailed Product Requirements Documents that are clear, actionable, and suitable for implementation. After PRD is confirmed, decompose it into small, independent Issues and create them in the user's chosen platform.

---

## The Job

1. Receive a feature description from the user
2. Ask 3-5 essential clarifying questions (with lettered options)
3. Generate a structured PRD based on answers
4. **Present PRD to user for review** — ask "Please review the PRD. Let me know if any adjustments are needed, or reply OK to confirm."
5. Apply any adjustments, then save to `tasks/prd-[feature-name].md`
6. **Decompose PRD into Issues** — break each User Story into one or more independent, implementable Issues
7. **Ask user to choose Issue creation mode** — GitHub / Local / Baidu iCafe
8. **Create Issues** in the chosen platform

**Important:** Do NOT start implementing. Just create the PRD and Issues.

---

## Step 1: Clarifying Questions

Ask only critical questions where the initial prompt is ambiguous. Focus on:

- **Problem/Goal:** What problem does this solve?
- **Core Functionality:** What are the key actions?
- **Scope/Boundaries:** What should it NOT do?
- **Success Criteria:** How do we know it's done?

### Format Questions Like This:

```
1. What is the primary goal of this feature?
   A. Improve user onboarding experience
   B. Increase user retention
   C. Reduce support burden
   D. Other: [please specify]

2. Who is the target user?
   A. New users only
   B. Existing users only
   C. All users
   D. Admin users only

3. What is the scope?
   A. Minimal viable version
   B. Full-featured implementation
   C. Just the backend/API
   D. Just the UI
```

This lets users respond with "1A, 2C, 3B" for quick iteration. Remember to indent the options.

---

## Edge Cases & Fallback

| Scenario | Handling |
|----------|----------|
| User skips clarifying questions (e.g., replies "whatever", "just write it") | Fill with reasonable defaults, mark with `[Assumption]` in PRD, prompt user to confirm during review |
| User input is too vague (e.g., "add a feature") | Ask once for specifics; if still vague, infer from project context and mark assumptions |
| `tasks/` directory does not exist | Auto-create `tasks/` directory |
| feature-name is hard to extract from input | Ask the user directly: "Suggested PRD filename is prd-XXX.md, please confirm or modify" |
| User requests PRD changes after review | Apply changes and re-save without re-running the clarification flow |
| PRD content exceeds 500 lines | Suggest the user consider splitting into multiple sub-feature PRDs |
| User declines Issue creation | Just save the PRD, skip Step 3 |
| `gh` CLI not authenticated for GitHub mode | Show error, suggest `gh auth login`, offer to switch to Local mode |
| `icafe-cli` / `icode-cli` not installed for baidu mode | Show error, suggest installation, offer to switch to Local mode |
| Issue folder does not exist for Local mode | Auto-create the folder |

---

## Step 2: PRD Structure

Generate the PRD with these sections:

### 1. Introduction/Overview
Brief description of the feature and the problem it solves. Use plain language — avoid jargon or explain it. Assume the reader may be a junior developer or AI agent.

### 2. Goals
Specific, measurable objectives (bullet list).

### 3. User Stories
Each story needs:
- **Title:** Short descriptive name
- **Description:** "As a [user], I want [feature] so that [benefit]"
- **Acceptance Criteria:** Verifiable checklist of what "done" means

**Numbering rule:** US-001, US-002, US-003... (three digits, starting from 001). Each US should be independently implementable, ideally completable within one agent session.

Each story should be small enough to implement in one focused session.

**Acceptance criteria self-check template:** Each criterion must satisfy at least one of the following, otherwise it is considered "vague" and must be rewritten:
- Observable: describes a specific UI state or API response (e.g., "button shows confirmation dialog")
- Testable: has clear input/output pairs (e.g., "entering an empty email shows a red warning")
- Verifiable: can be checked by tools (e.g., "Typecheck/lint passes")
- ❌ Bad example: "works correctly", "good user experience", "excellent performance" → these are unverifiable

**Format:**
```markdown
### US-001: [Title]
**Description:** As a [user], I want [feature] so that [benefit].

**Acceptance Criteria:**
- [ ] Specific verifiable criterion
- [ ] Another criterion
- [ ] Typecheck/lint passes
- [ ] **[UI stories only]** Verify in browser using dev-browser skill
```

**Important:** 
- Acceptance criteria must be verifiable, not vague. "Works correctly" is bad. "Button shows confirmation dialog before deleting" is good.
- **For any story with UI changes:** Always include "Verify in browser using dev-browser skill" as acceptance criteria. This ensures visual verification of frontend work.

### 4. Functional Requirements
Numbered list of specific functionalities:
- "FR-1: The system must allow users to..."
- "FR-2: When a user clicks X, the system must..."

**FR specification:** Each FR starts with `FR-N:` (N increments from 1), uses "system must / system shall" phrasing, and describes **one** specific behavior. Avoid combining multiple "and"-linked behaviors in a single FR.

### 5. Non-Goals (Out of Scope)
What this feature will NOT include. Critical for managing scope.

### 6. Design Considerations (Optional)
- UI/UX requirements
- Link to mockups if available
- Relevant existing components to reuse

### 7. Technical Considerations (Optional)
- Known constraints or dependencies
- Integration points with existing systems
- Performance requirements

### 8. Success Metrics
How will success be measured?
- "Reduce time to complete X by 50%"
- "Increase conversion rate by 10%"

### 9. Open Questions
Remaining questions or areas needing clarification.

---

## Output

- **Format:** Markdown (`.md`)
- **Location:** `tasks/`
- **Filename:** `prd-[feature-name].md` (kebab-case)

---

## Step 3: Issue Decomposition & Creation

After the PRD is saved, decompose it into implementable Issues and create them.

### 3.1 Decompose PRD into Issues

Based on the PRD's User Stories and Functional Requirements, generate a list of Issues. Follow these rules:

- **One Issue per User Story** — each US-XXX becomes at least one Issue
- **Split large stories** — if a US has 5+ acceptance criteria or spans frontend + backend, split into 2-3 smaller Issues with clear dependencies
- **Merge tiny stories** — if a US has only 1-2 trivial criteria, merge it with a related US into a single Issue
- **Each Issue must be independently implementable** — a single agent session should be able to complete it
- **Number Issues sequentially** starting from 1

**Issue format:**

```
Issue #N: [Title]
---
Description: [From US description, with context]
Acceptance Criteria:
- [ ] [From US acceptance criteria]
- [ ] ...
Dependencies: [None / Issue #X]
Type: [backend / frontend / fullstack / ui / infra]
Priority: [high / medium / low]
```

**Present the Issue list to the user for review:**

```
📋 Generated N Issues from PRD:

#1: Add priority field to database (backend, high)
#2: Display priority indicator on task cards (frontend, high) — depends on #1
#3: Add priority selector to task edit (frontend, medium) — depends on #1
#4: Filter tasks by priority (frontend, medium) — depends on #1, #2

Please review. You can:
- Remove issues: "remove #3"
- Merge issues: "merge #2 and #3"
- Add issues: "add an issue for sorting by priority"
- Adjust: "change #2 priority to high"
- Confirm: reply OK to proceed
```

Wait for user confirmation before creating any Issues.

### 3.2 Ask User to Choose Creation Mode

After user confirms the Issue list, ask:

```
Choose where to create these Issues:

A. GitHub (via gh CLI)
B. Local (save as .md files)
C. Baidu iCafe (via icafe-cli)

Your choice:
```

### 3.3 Mode-Specific Parameters & Creation

#### Mode A: GitHub

**Prerequisites:** `gh` CLI installed and authenticated.

**Actions:**
1. For each Issue, run:
   ```bash
   gh issue create --title "[Title]" --body "[Description + Acceptance Criteria]" --label "[type]" --label "priority: [priority]"
   ```
2. If labels don't exist, create them first or skip the `--label` flag
3. Report created Issue numbers and URLs

#### Mode B: Local

**Ask user:**
```
Where should I save the Issue files? (default: .autoresearch/issues)
```

**Actions:**
1. If the specified folder does not exist, create it with `mkdir -p`
2. For each Issue #N, save a file named `issue-NNN-[slug].md` (zero-padded to 3 digits):
   ```markdown
   # [Title]

   ## Description
   [Description from Issue]

   ## Acceptance Criteria
   - [ ] [criterion 1]
   - [ ] [criterion 2]

   ## Dependencies
   [None / Issue #X]

   ## Type
   [backend / frontend / fullstack / ui / infra]

   ## Priority
   [high / medium / low]
   ```
3. Report created file paths

#### Mode C: Baidu iCafe

**Ask user:**
```
Please provide the iCafe space prefix code (--space):
```

Optionally ask:
```
Target branch for iCode CR? (default: master)
```

**Prerequisites:** `icafe-cli` installed and logged in.

**Actions:**
1. For each Issue, run:
   ```bash
   icafe-cli card create --space [SPACE] --title "[Title]" --description "[Description + Acceptance Criteria]" --cardtype "[Task/Bug/Story]"
   ```
   - Map Issue `type` to iCafe card type: `bug` → `Bug`, `ui`/`frontend` → `Story`, others → `Task`
   - Map `priority`: high → `高`, medium → `中`, low → `低`
2. If iCafe card creation fails for an Issue, log the error and continue with remaining Issues
3. Report created card sequence numbers

### 3.4 Summary Report

After all Issues are created, print a summary:

```
✅ Issue creation complete!

Mode: [GitHub / Local / Baidu iCafe]
PRD: tasks/prd-[feature-name].md
Issues created: N

#  | Title                                    | Identifier
---|------------------------------------------|------------
1  | Add priority field to database           | #42 (GitHub) / issue-001-*.md (Local) / #22210 (iCafe)
2  | Display priority indicator               | #43 / issue-002-*.md / #22211
3  | Add priority selector                    | #44 / issue-003-*.md / #22212
4  | Filter tasks by priority                 | #45 / issue-004-*.md / #22213

💡 Tip: You can now run autoresearch on each Issue:
  ./run.sh 42                    # GitHub mode
  ./run.sh 1                     # Local mode
  ./run.sh --issue-source=baidu --space=[SPACE] 22210  # Baidu iCafe mode
```

---

## Example PRD

```markdown
# PRD: Task Priority System

## Introduction

Add priority levels to tasks so users can focus on what matters most. Tasks can be marked as high, medium, or low priority, with visual indicators and filtering to help users manage their workload effectively.

## Goals

- Allow assigning priority (high/medium/low) to any task
- Provide clear visual differentiation between priority levels
- Enable filtering and sorting by priority
- Default new tasks to medium priority

## User Stories

### US-001: Add priority field to database
**Description:** As a developer, I need to store task priority so it persists across sessions.

**Acceptance Criteria:**
- [ ] Add priority column to tasks table: 'high' | 'medium' | 'low' (default 'medium')
- [ ] Generate and run migration successfully
- [ ] Typecheck passes

### US-002: Display priority indicator on task cards
**Description:** As a user, I want to see task priority at a glance so I know what needs attention first.

**Acceptance Criteria:**
- [ ] Each task card shows colored priority badge (red=high, yellow=medium, gray=low)
- [ ] Priority visible without hovering or clicking
- [ ] Typecheck passes
- [ ] Verify in browser using dev-browser skill

### US-003: Add priority selector to task edit
**Description:** As a user, I want to change a task's priority when editing it.

**Acceptance Criteria:**
- [ ] Priority dropdown in task edit modal
- [ ] Shows current priority as selected
- [ ] Saves immediately on selection change
- [ ] Typecheck passes
- [ ] Verify in browser using dev-browser skill

### US-004: Filter tasks by priority
**Description:** As a user, I want to filter the task list to see only high-priority items when I'm focused.

**Acceptance Criteria:**
- [ ] Filter dropdown with options: All | High | Medium | Low
- [ ] Filter persists in URL params
- [ ] Empty state message when no tasks match filter
- [ ] Typecheck passes
- [ ] Verify in browser using dev-browser skill

## Functional Requirements

- FR-1: Add `priority` field to tasks table ('high' | 'medium' | 'low', default 'medium')
- FR-2: Display colored priority badge on each task card
- FR-3: Include priority selector in task edit modal
- FR-4: Add priority filter dropdown to task list header
- FR-5: Sort by priority within each status column (high to medium to low)

## Non-Goals

- No priority-based notifications or reminders
- No automatic priority assignment based on due date
- No priority inheritance for subtasks

## Technical Considerations

- Reuse existing badge component with color variants
- Filter state managed via URL search params
- Priority stored in database, not computed

## Success Metrics

- Users can change priority in under 2 clicks
- High-priority tasks immediately visible at top of lists
- No regression in task list performance

## Open Questions

- Should priority affect task ordering within a column?
- Should we add keyboard shortcuts for priority changes?
```

---

## Checklist

Before saving the PRD:

- [ ] Asked clarifying questions with lettered options
- [ ] Incorporated user's answers
- [ ] User stories are small and specific
- [ ] Functional requirements are numbered and unambiguous
- [ ] Non-goals section defines clear boundaries
- [ ] Saved to `tasks/prd-[feature-name].md`

Before finishing Issue creation:

- [ ] Decomposed PRD into independent, implementable Issues
- [ ] Presented Issue list to user for review and confirmation
- [ ] Asked user to choose creation mode (GitHub / Local / Baidu iCafe)
- [ ] Collected mode-specific parameters (folder path for Local, --space for Baidu iCafe)
- [ ] Created all Issues and reported results
- [ ] Printed summary with autoresearch usage tips
