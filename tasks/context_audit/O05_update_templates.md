# O05 — Update all 4 files in templates/ with AGENTS.md reference, read priority, anti-leak rules

- **Target project:** `ai-git-orchestrator`
- **CWD:** `C:\Users\che\Documents\Projects\ai-git-orchestrator`
- **Invocation:** copy section below `---` into `.ai-loop\task.md`, then run

  ```powershell
  powershell -ExecutionPolicy Bypass -File .\scripts\ai_loop_task_first.ps1 -NoPush
  ```

- **Prerequisites:** O01..O04 completed.
- **Risk:** low. Templates are inert files until copied into a target
  project. Bad edits propagate only on next `install_into_project.ps1`
  run.
- **Estimated lines touched:** ~60 lines across 4 files.

---

# Task: Update templates/ files with AGENTS.md reference, explicit read priority, and anti-history-leak rules

## Project context

Before starting, read:

- `.ai-loop/project_summary.md`
- `.ai-loop/task.md`
- `.ai-loop/cursor_summary.md` if it exists
- `AGENTS.md` (root) — the rules these templates should align with
- `templates/task.md` — current state
- `templates/codex_review_prompt.md` — current state
- `templates/project_summary.md` — current state
- `templates/cursor_summary_template.md` — current state
- `scripts/install_into_project.ps1` — to confirm which files get copied

## Background

The current templates work but encode an outdated mental model:

- `templates/task.md` tells implementers to read `project_summary.md` and
  `task.md` but does not mention `AGENTS.md`, does not prescribe a read
  order, and does not prohibit reading the archive directories.
- `templates/codex_review_prompt.md` lists files to read in a flat order
  with no priority and reads raw `test_output.txt`. After O06 (next task)
  the reviewer should prefer `test_failures_summary.md` when it exists.
- `templates/project_summary.md` is just a structural template with TODO
  placeholders. It does not warn the implementer against accumulating a
  growing list of "Earlier rolls" — exactly the antipattern the audit
  found in H2N parser's project_summary.md.
- `templates/cursor_summary_template.md` is a passive scaffold. It does
  not enforce "current iteration only, no historical rolls".

This task hardens all four templates without changing the file contract
(filenames, section names that scripts grep for must stay).

## Goal

Update each template to:

1. Reference `AGENTS.md` as required reading.
2. State an explicit read priority.
3. Prohibit prior-task history in the file (where applicable).
4. Where applicable, prefer filtered artefacts over raw artefacts.

Templates stay short (no template should exceed ~80 lines after edit).

## Scope

### Allowed

- Edit `templates/task.md`
- Edit `templates/codex_review_prompt.md`
- Edit `templates/project_summary.md`
- Edit `templates/cursor_summary_template.md`

### Not allowed

- Do **not** rename any template file. `install_into_project.ps1` copies
  by exact name.
- Do **not** modify `scripts/install_into_project.ps1` or any other script.
- Do **not** modify the parseable / regex-matched portions of any
  template. Specifically:
  - The Codex review template's "VERDICT: PASS or FIX_REQUIRED" and
    "FIX_PROMPT_FOR_CURSOR:" / "FINAL_NOTE:" labels are parsed by
    `Get-ReviewVerdict` and `Extract-FixPromptFromFile` in
    `ai_loop_auto.ps1`. **Keep these exact strings.**
  - The cursor_summary template's section ordering is referenced in
    several places. Keep top-level `##` sections and their order; you
    may add new ones at the end.
- Do **not** include references to artefacts that do not yet exist as of
  this task (e.g. `test_failures_summary.md` is created in O06). Use
  conditional wording: "if `test_failures_summary.md` exists, read it
  first; otherwise read `test_output.txt`".
- Do **not** modify any file in `docs/`, `.ai-loop/`, `scripts/`,
  `tests/`, `AGENTS.md`, `README.md`.

## Files likely to change

- `templates/task.md`
- `templates/codex_review_prompt.md`
- `templates/project_summary.md`
- `templates/cursor_summary_template.md`

## Required behavior

### Template 1: `templates/task.md`

Current header section starts with "## Project context" and lists three
files to read. Replace with:

```markdown
## Project context

Required reading before starting (in order; stop when you have enough):

1. `AGENTS.md` at repo root — working rules and forbidden paths
2. `.ai-loop/task.md` — this task
3. `.ai-loop/project_summary.md` — durable project orientation
4. `.ai-loop/cursor_summary.md` — only if this is iteration 2+

Do not read by default:

- `docs/archive/` — superseded design documents
- `.ai-loop/archive/` — historical task rolls
- `.ai-loop/_debug/` — raw agent stdout, debug-only
```

Keep all other sections of the template intact. They are reasonable as-is.

Add a new section right before "## Important" at the end:

```markdown
## Output hygiene

The implementer must not:

- duplicate this task description into `.ai-loop/cursor_summary.md`
- include earlier task narrative in `.ai-loop/project_summary.md`
- write to `.ai-loop/_debug/` or `docs/archive/`
- commit or push (the orchestrator handles git)
```

### Template 2: `templates/codex_review_prompt.md`

This is the prompt Codex receives. Replace the "Read:" block with:

```markdown
Read in this priority order (stop reading once verdict is clear):

1. `.ai-loop/task.md` — current task contract
2. `.ai-loop/project_summary.md` — durable project orientation
3. `AGENTS.md` at repo root — working rules
4. `.ai-loop/cursor_summary.md` — implementer's report on the latest
   iteration
5. `.ai-loop/diff_summary.txt` — `git diff --stat` short overview
   (if present)
6. `.ai-loop/test_output.txt` — pytest -q output
7. `.ai-loop/test_failures_summary.md` — filtered failures
   (if present; this file is generated only when pytest fails)
8. `.ai-loop/last_diff.patch` — full git diff (only if items 5–7 are
   not sufficient)
9. `.ai-loop/git_status.txt` — short porcelain status
```

Note: items 5 and 7 (`diff_summary.txt`, `test_failures_summary.md`) are
introduced by O06. Until O06 runs, these files do not exist; the
"(if present)" wording handles that gracefully.

Keep the "Check:" numbered list and the "Return exactly:" block intact.
Specifically these EXACT strings must remain unchanged (regex-matched in
scripts):

- `VERDICT: PASS or FIX_REQUIRED`
- `FIX_PROMPT_FOR_CURSOR:`
- `FINAL_NOTE:`

Add a new sentence at the bottom of the prompt template, right before the
`Return exactly:` block:

```markdown
Do not request manual steps unless absolutely required. If the implementer
deferred the task instead of implementing it, return `VERDICT: FIX_REQUIRED`
with a concrete fix prompt.
```

(The current template already says something similar; merge without
duplication.)

### Template 3: `templates/project_summary.md`

This template is what gets copied into a target project's
`.ai-loop/project_summary.md` on first install. It is a scaffold with
TODO placeholders.

Add a single block at the very top (before the existing `# Project Summary`
heading or as a Markdown comment under the heading):

```markdown
<!--
HARD RULES for project_summary.md:

1. This file is DURABLE orientation, not a per-task changelog.
2. Target length: under 80 lines. If the file exceeds 100 lines, compact
   it: move "Earlier roll" / "Last completed task" content into
   .ai-loop/archive/rolls/<date>_<topic>.md.
3. Do NOT accumulate "Earlier roll" sections in this file. The
   "Last completed task" section holds ONLY the most recent task.
4. Do NOT copy code, function signatures, or backtick-heavy API surfaces.
   Use prose pointers to source files.
5. Active design constraints stay here. Historical decisions go to
   docs/decisions.md.

When in doubt: ask, does this help an agent orient on the NEXT task?
If no, it belongs in archive/.
-->
```

Keep the existing section structure (## Project purpose, ## Current
architecture, etc.). Do not add new top-level sections.

If the current template has a "## Last completed task" section with
multiple bullets/blocks, add a one-line constraint right under that
heading:

```markdown
Most recent task only. Older tasks belong in `.ai-loop/archive/rolls/`.
```

### Template 4: `templates/cursor_summary_template.md`

This template is what the orchestrator resets to a stub on each task run
(see `Initialize-CursorSummaryForImplementation` in
`ai_loop_task_first.ps1`).

Add the following hard rules right under the `# Cursor Summary` heading
(as a Markdown comment block or visible note — implementer's choice):

```markdown
<!--
HARD RULES for cursor_summary.md:

1. This file describes ONLY the current iteration / task.
2. Do NOT include "Earlier roll", "Prior task", or any historical content.
3. Target length: under 50 lines.
4. Do NOT paste the full diff. Use the diff for verification, not for
   storage.
5. Do NOT duplicate the task description from .ai-loop/task.md.

Each section below has a target length; respect it.
-->
```

Update the existing section headers with target line counts in parens:

- `## Changed files` (≤ 10 lines)
- `## Test result` (≤ 5 lines — just the summary line, not full output)
- `## Implementation summary` (≤ 10 lines)
- `## Task-specific verification` (≤ 10 lines)
- `## Project summary update` (≤ 3 lines)
- `## Skipped work` (≤ 5 lines)
- `## Remaining risks` (≤ 5 lines, bullet form)

You may add the target counts in italic next to each header, e.g.:

```markdown
## Changed files
*(target: ≤ 10 lines)*
```

Section ordering must stay the same as the current template — scripts may
not care, but humans skim by position.

## Tests

Run:

```powershell
python -m pytest -q
```

Expected: same count of passing tests. None of the template files are
imported or parsed by current tests.

If `tests/test_orchestrator_validation.py` greps for specific strings
inside templates (the literal `VERDICT: PASS or FIX_REQUIRED`), those
strings must still exist after this task — verification step 4 confirms.

## Verification

1. All four template files still exist:

   ```powershell
   Test-Path .\templates\task.md
   Test-Path .\templates\codex_review_prompt.md
   Test-Path .\templates\project_summary.md
   Test-Path .\templates\cursor_summary_template.md
   ```

   All return `True`.

2. Each template references `AGENTS.md`:

   ```powershell
   @('task.md','codex_review_prompt.md','project_summary.md','cursor_summary_template.md') | ForEach-Object {
       $count = (Select-String -Path ".\templates\$_" -Pattern "AGENTS\.md" | Measure-Object).Count
       "$_ : $count"
   }
   ```

   Each returns at least 1, except `cursor_summary_template.md` may
   return 0 (that template does not need to reference AGENTS.md
   directly — it's a fill-in scaffold, not an instruction sheet).

3. Critical regex-matched strings in codex_review_prompt.md are intact:

   ```powershell
   Select-String -Path .\templates\codex_review_prompt.md -Pattern "VERDICT: PASS or FIX_REQUIRED" |
     Measure-Object | Select-Object -ExpandProperty Count
   Select-String -Path .\templates\codex_review_prompt.md -Pattern "FIX_PROMPT_FOR_CURSOR:" |
     Measure-Object | Select-Object -ExpandProperty Count
   Select-String -Path .\templates\codex_review_prompt.md -Pattern "FINAL_NOTE:" |
     Measure-Object | Select-Object -ExpandProperty Count
   ```

   All three return at least 1.

4. Each template's line count is in target range:

   ```powershell
   Get-ChildItem .\templates\*.md | ForEach-Object {
       $lines = (Get-Content $_.FullName | Measure-Object -Line).Lines
       "$($_.Name): $lines lines"
   }
   ```

   - `task.md`: ≤ 120 lines (was ~90 before; expect modest growth)
   - `codex_review_prompt.md`: ≤ 80 lines (was ~45 before)
   - `project_summary.md`: ≤ 80 lines
   - `cursor_summary_template.md`: ≤ 60 lines

5. `pytest -q` passes.

## Cursor summary requirements

Update `.ai-loop/cursor_summary.md` with:

1. Per-template, one line stating what was added (read-priority block,
   anti-leak comment, target line counts, etc.).
2. Confirmation that VERDICT / FIX_PROMPT_FOR_CURSOR / FINAL_NOTE labels
   in codex_review_prompt.md are unchanged.
3. `pytest -q` result.

Target length: 10–15 lines.

## Project summary update

Update `.ai-loop/project_summary.md` only if durable architecture changed.
One line is enough, in "Notes for future AI sessions":

- "Templates in `templates/` enforce AGENTS.md reading and anti-history-
  leak rules. See `tasks/context_audit/O05_*.md` for rationale."

## Important

- **Do not change** the parseable strings in codex_review_prompt.md. If
  unsure whether a string is parseable, check the regex usage in
  `scripts/ai_loop_auto.ps1` (`Get-ReviewVerdict`,
  `Extract-FixPromptFromFile`).
- Markdown HTML comments (`<!--...-->`) are fine inside templates — they
  render invisibly in Markdown viewers and survive copy-into-target via
  `install_into_project.ps1`.
- Keep templates short. If a section grows past the target line count,
  prune rather than break the target.
- Do not commit. The orchestrator handles commit after Codex PASS.
