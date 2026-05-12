# O04 — Sync docs/decisions.md, docs/workflow.md, README.md with architecture.md

- **Target project:** `ai-git-orchestrator`
- **CWD:** `C:\Users\che\Documents\Projects\ai-git-orchestrator`
- **Invocation:** copy section below `---` into `.ai-loop\task.md`, then run

  ```powershell
  powershell -ExecutionPolicy Bypass -File .\scripts\ai_loop_task_first.ps1 -NoPush
  ```

- **Prerequisites:** O03 completed (architecture.md is the source of truth
  for DD-020, DD-021, Q-10, §0 current state).
- **Risk:** low. All three files are small; updates are additive plus a
  couple of factual corrections.
- **Estimated lines touched:** ~80 lines added across three files.

---

# Task: Synchronize decisions.md, workflow.md, README.md with the restructured architecture.md

## Project context

Before starting, read:

- `.ai-loop/project_summary.md`
- `.ai-loop/task.md`
- `.ai-loop/cursor_summary.md` if it exists
- `AGENTS.md`
- `docs/architecture.md` §0 (Current state), §12 (Decision Log), §13 (Open
  Questions) — to pull current truth
- `docs/decisions.md` — file you will extend
- `docs/workflow.md` — file you will lightly update
- `README.md` — file you may lightly update

## Background

After O03, `docs/architecture.md` has a "§0 Current state" section and an
extended §12 Decision Log (DD-001..DD-021) plus Q-10. The companion docs
have not been updated yet:

- `docs/decisions.md` currently lists only DD-001..DD-006.
- `docs/workflow.md` describes the current Cursor + Codex workflow
  accurately but does not point at architecture.md §0 / §1+ separation.
- `README.md` is accurate for current state but does not mention
  `AGENTS.md` (will be addressed by the optional README line in O02, or
  here if O02 skipped it).

## Goal

Make `docs/decisions.md`, `docs/workflow.md`, `README.md` consistent with
`docs/architecture.md` after O03. No re-architecture: just propagate the
decisions, add pointers, and remove inaccuracies.

## Scope

### Allowed

- Edit `docs/decisions.md`:
  - Add DD-007 through DD-021 entries (short summary + pointer to
    `docs/architecture.md §12` for full rationale).
  - Add a one-line preamble at top: "Full rationale and risks are in
    `docs/architecture.md` §12 Decision Log. This file is a numbered index."
- Edit `docs/workflow.md`:
  - Add a one-line note near the top pointing readers to
    `docs/architecture.md §0` for current state vs §1+ for target.
  - Update the safe paths list at the bottom if it diverges from the
    actual literal in `ai_loop_auto.ps1` (it currently matches; just
    re-verify).
- Edit `README.md`:
  - If `AGENTS.md` pointer was not added by O02, add one line near top.
  - Update the "What it does" or "Requirements" subsection to mention that
    OpenCode + Qwen is in Phase 0/1 (not the default implementer) so
    readers do not expect the canonical workflow to involve local models
    by default. One sentence is enough.
  - Update the "Install into a target project" subsection's file list
    (currently lists 7 paths including `.ai-loop/codex_review_prompt.md`
    and `.ai-loop/cursor_summary_template.md`). Verify against
    `scripts/install_into_project.ps1` and fix any drift.

### Not allowed

- Do **not** modify `docs/architecture.md` (that was O03; this is sync).
- Do **not** modify `docs/safety.md` (safe paths literal lives there in
  prose; only update if it diverges from the script literal).
- Do **not** modify any file in `scripts/`, `tests/`, `templates/`,
  `.ai-loop/`.
- Do **not** introduce new decisions in this task. Only mirror what
  `docs/architecture.md` already records.
- Do **not** expand `docs/decisions.md` into a full essay. Each entry is
  one short paragraph + pointer.

## Files likely to change

- `docs/decisions.md` (extend)
- `docs/workflow.md` (small addition)
- `README.md` (small corrections)

## Required behavior

### Part 1: `docs/decisions.md`

Current state: lists DD-001 through DD-006. Each is a short paragraph.

Add at top of file (right under the `# Design Decisions` heading):

```markdown
Full rationale, risks, and supersession status for each decision are in
`docs/architecture.md` §12 Decision Log. This file is a numbered index;
treat the architecture-doc version as authoritative when they diverge.
```

Add entries DD-007 through DD-021 below DD-006. For each, write a single
short paragraph (2–4 lines) that summarizes the decision and links to
architecture.md. Do **not** copy the full rationale from architecture.md —
this file is an index.

Template for each entry:

```markdown
## DD-NNN: <short title>

<2-4 line summary of the decision and its current status>

See `docs/architecture.md` §12 DD-NNN for rationale and risk notes.
```

For DD-007 through DD-021, pull the title and one-line summary directly
from the corresponding entry in `docs/architecture.md` §12. If a decision
listed in architecture.md does not yet have a clearly defined title in
that doc, use the implementer's best judgment to pick a concise title
(≤8 words) and note "(title may need revision)" in cursor_summary.md.

DD-020 and DD-021 (added by O03) MUST be present.

If any of DD-007 through DD-019 are not yet defined in
`docs/architecture.md` §12 (because the architecture doc skipped numbers),
note the gap explicitly:

```markdown
## DD-NNN: (reserved / not yet defined)

Placeholder; see `docs/architecture.md` §12 for current decision numbering.
```

This makes future drift visible without forcing a fabrication.

### Part 2: `docs/workflow.md`

Add a single paragraph near the top of the file (after the `# Workflow`
heading, before the existing `## Overview`):

```markdown
> **Current state vs target.** This document describes the workflow that
> runs in production today (Cursor as implementer, Codex as reviewer).
> See `docs/architecture.md` §0 for a structured statement of current
> state, and §1 onwards for the target multi-model design we are
> building toward.
```

Then verify the safe paths literal at the bottom (if mentioned) matches
the literal in `scripts/ai_loop_auto.ps1` `$SafeAddPaths` parameter
default. If `workflow.md` does not contain that literal, do not add it —
`docs/safety.md` is the home for it.

No other changes to `workflow.md`.

### Part 3: `README.md`

Three small corrections:

**3.a** — If `README.md` does not yet contain a line about `AGENTS.md` (O02
optionally added one), add this single line right after the title line:

```markdown
See `AGENTS.md` for AI-agent working rules.
```

Verify first by grep:

```powershell
Select-String -Path .\README.md -Pattern "AGENTS\.md" | Measure-Object |
  Select-Object -ExpandProperty Count
```

If 0, add the line. If ≥1, leave README.md untouched for this sub-step.

**3.b** — In the "What it does" subsection (or whichever subsection
describes the implementer), add a single short sentence acknowledging that
local-model integration is in progress:

```markdown
> Local OpenCode + Qwen integration is in Phase 0/1 (see
> `docs/architecture.md §0.3`); production implementer today is Cursor.
```

This should go right after the existing "Flow: ..." codeblock, as a single
quoted note paragraph. One paragraph, two lines max.

**3.c** — Verify the install-into-target-project file list (currently
listed in `## Install into a target project`):

```text
scripts/ai_loop_auto.ps1
scripts/ai_loop_task_first.ps1
scripts/continue_ai_loop.ps1
.ai-loop/task.md
.ai-loop/project_summary.md
.ai-loop/codex_review_prompt.md
.ai-loop/cursor_summary_template.md
```

Open `scripts/install_into_project.ps1` and compare. If the actual list
differs (file added or removed), correct README to match. Do NOT modify
`scripts/install_into_project.ps1` itself.

Common drift to look for:
- Templates from `templates/` are copied INTO target's `.ai-loop/`, so the
  source path is `templates/X.md` but the README documents the target
  basename. Both lists should reflect what the user will see in their
  target project.
- If `install_into_project.ps1` copies `AGENTS.md` (it may not yet — that
  could be a future step), README should reflect actual current behavior,
  not aspiration.

If the lists already agree, no change needed for 3.c.

## Tests

Run:

```powershell
python -m pytest -q
```

Expected: same passing count.

The orchestrator-validation tests include `SafeAddPaths` parity. They do
not parse decisions.md or workflow.md, so this task should not affect
them. If a test breaks, debug rather than blindly aligning — likely a real
drift was already present.

## Verification

1. `docs/decisions.md` contains DD-001 through DD-021 (or placeholder
   entries for skipped numbers):

   ```powershell
   Select-String -Path .\docs\decisions.md -Pattern "^## DD-0\d{2}" |
     Measure-Object | Select-Object -ExpandProperty Count
   ```

   Returns 21.

2. `docs/decisions.md` references architecture.md for at least DD-007..DD-021:

   ```powershell
   Select-String -Path .\docs\decisions.md -Pattern "docs/architecture\.md" |
     Measure-Object | Select-Object -ExpandProperty Count
   ```

   Returns ≥ 15.

3. `docs/workflow.md` mentions §0 current state:

   ```powershell
   Select-String -Path .\docs\workflow.md -Pattern "§0|architecture\.md" |
     Measure-Object | Select-Object -ExpandProperty Count
   ```

   Returns ≥ 1.

4. `README.md` mentions both `AGENTS.md` and OpenCode/Qwen phase:

   ```powershell
   Select-String -Path .\README.md -Pattern "AGENTS\.md" |
     Measure-Object | Select-Object -ExpandProperty Count
   Select-String -Path .\README.md -Pattern "Phase 0|Phase 1|OpenCode|Qwen" |
     Measure-Object | Select-Object -ExpandProperty Count
   ```

   Both return ≥ 1.

5. Install file list in `README.md` matches actual behavior of
   `scripts/install_into_project.ps1` (manual visual check or grep
   pairs).

6. `pytest -q` passes.

## Cursor summary requirements

Update `.ai-loop/cursor_summary.md` with:

1. `docs/decisions.md`: extended from DD-006 to DD-021 (with N placeholder
   entries for any reserved numbers).
2. `docs/workflow.md`: added one current-vs-target note paragraph.
3. `README.md`: added AGENTS.md pointer (if missing), OpenCode/Qwen phase
   sentence, install list verified (Y/N drift fixed).
4. `pytest -q` result.

Target length: 10–15 lines.

## Project summary update

Update `.ai-loop/project_summary.md` only if durable architecture changed.
For this task, no durable architecture change — just doc sync. One line is
fine, e.g. under "Notes for future AI sessions":

- "`docs/decisions.md` is the numbered index; `docs/architecture.md` §12
  is the authoritative version with rationale."

## Important

- This is a synchronization task. **Do not introduce decisions** that are
  not in `docs/architecture.md`. If you notice missing decisions while
  writing `decisions.md`, leave a placeholder and mention it in
  `cursor_summary.md` so a follow-up task can address the gap in
  `architecture.md`.
- Do not commit. The orchestrator handles commit after Codex PASS.
- Resist scope creep. If you see other doc errors during this task,
  list them in `cursor_summary.md` "Remaining risks" — do not fix in
  this task.
