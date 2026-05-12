# D03 — Compact h2n-claude-review REVIEW_STATE.md

**Project:** `H2N_parser/h2n-claude-review`
**CWD:** `C:\Users\che\Documents\Projects\H2N_parser\h2n-claude-review`
**Prerequisite:** none (standalone, no dependency on D01/D02).
**Risk:** low — orientation file only, no code changes.

This task is run manually (Claude or human edits the file directly) — not via the PowerShell AI loop, since `h2n-claude-review` does not use `ai_loop_task_first.ps1`.

---

## Project context

`h2n-claude-review` is the business-logic review brain for the H2N project. Claude reads `REVIEW_STATE.md` at the start of each session for orientation. The file currently has **386 lines** structured as:

- `## Current focus` (lines 3–293, ~291 lines) — detailed review of the reference dashboard feature
- `## Previous focus` (lines 294–372, ~79 lines) — completed, should be archived
- `## Previous focus (F008 fix)` / `## Previous focus (F006)` / `## Earlier focus` / `## Before that` (lines 373–411) — all completed, should be archived
- `## Current commands` (lines 412–431)
- Confirmed findings, snapshot verification (lines 432–386 end)

The accumulation of "Previous focus" sections is exactly the context bloat pattern identified in the audit.

## Goal

Rewrite `REVIEW_STATE.md` to **≤ 80 lines** by:
1. Condensing `## Current focus` to the verdict + blockers + next actions only.
2. Removing all "Previous focus", "Earlier focus", "Before that" history sections.
3. Keeping `## Key confirmed findings` intact (it's durable).
4. Keeping snapshot verification commands (useful cross-session).
5. Dropping `## Current commands` if covered by `COMMANDS.md` (check first).

## Scope

**Allowed:**
- `REVIEW_STATE.md` — rewrite.

**Not allowed:**
- Any other file in the project.

## Required behavior

After the rewrite, `REVIEW_STATE.md` must contain:

### 1. Current focus (≤ 30 lines)

```markdown
## Current focus

**<feature name> — reviewed <date> (parser HEAD `<sha>`).**

Verdict: **<verdict>**

Task contract (3–5 bullets, key points only):
- ...

Review evidence (3–5 bullets, key facts only):
- ...

Delivery blockers:
- ...

Next action:
- <single most important next step>
```

### 2. Key confirmed findings (keep as-is, ~12 lines)

The section starting at line 486 in the current file — contains confirmed binary format facts (`.h2nstatl`, `.statprofile`, stat ID format, color ranges). Keep verbatim.

### 3. Snapshot verification commands (keep as-is, ~15 lines)

The PowerShell commands for SHA verification. Keep verbatim.

**Must omit:**
- All "Previous focus", "Earlier focus", "Before that", "Before that (F004)", "task_fix_render_grouping completed" sections.
- "Current commands" section if it duplicates `COMMANDS.md`.
- Detailed evidence tables, full JSON field lists, long bullet chains already captured in `cursor_tasks/` or `findings/`.

## Files likely to change

- `REVIEW_STATE.md` (rewrite, 386 → ≤ 80 lines)

## Verification

1. `(Get-Content REVIEW_STATE.md | Measure-Object -Line).Lines` — must be ≤ 80.
2. File contains `## Current focus` with verdict and next action.
3. File contains `## Key confirmed findings`.
4. File contains NO heading matching `Previous focus`, `Earlier focus`, `Before that`.
5. `COMMANDS.md` still exists and is unchanged.
