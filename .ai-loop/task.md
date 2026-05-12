# O02 — Create AGENTS.md at orchestrator root

- **Target project:** `ai-git-orchestrator`
- **CWD:** `C:\Users\che\Documents\Projects\ai-git-orchestrator`
- **Invocation:** copy section below `---` into `.ai-loop\task.md`, then run

  ```powershell
  powershell -ExecutionPolicy Bypass -File .\scripts\ai_loop_task_first.ps1 -NoPush
  ```

- **Prerequisites:** O01 completed (so the root namespace is clean).
- **Risk:** low (new file, no existing file modified beyond an optional
  README.md pointer).
- **Estimated lines touched:** +1 new file (~70 lines), maybe +2 lines in
  README.md for a pointer.

---

# Task: Create root AGENTS.md with concise working rules

## Project context

Before starting, read:

- `.ai-loop/project_summary.md`
- `.ai-loop/task.md`
- `.ai-loop/cursor_summary.md` if it exists

Background:

There is currently no `AGENTS.md` or `CLAUDE.md` at the root of any of the
three projects (`ai-git-orchestrator`, `H2N_parser/h2n-range-extractor`,
`H2N_parser/h2n-claude-review`). The context audit (2026-05-12) identified
this as a gap: rules are scattered across `docs/safety.md`,
`docs/workflow.md`, inline PowerShell prompts, and project_summary prose.

This task creates the orchestrator's `AGENTS.md` first. The other two
projects get their own files in deferred tasks D02/D04.

## Goal

Produce a concise (50–80 line) `AGENTS.md` at repo root that gives any AI
agent (Cursor, Codex, Claude, or any tool that respects this convention) the
working rules in one place, with pointers — not duplications — to detailed
docs.

## Scope

### Allowed

- Create new file `AGENTS.md` at repo root.
- Optionally add one line to `README.md` pointing to `AGENTS.md` near the
  top.

### Not allowed

- Do **not** copy the entire content of `docs/architecture.md`,
  `docs/safety.md`, `docs/workflow.md`, `docs/decisions.md` into `AGENTS.md`.
  Use pointers.
- Do **not** modify any file in `scripts/`, `tests/`, `templates/`,
  `.ai-loop/`, `docs/` (except optionally `README.md` as noted above).
- Do **not** create a `CLAUDE.md` in this task. That can be a follow-up if
  needed; for now `AGENTS.md` covers all agents.
- Do **not** include forbidden-paths rules for target projects here. This
  file is about `ai-git-orchestrator` itself.

## Files likely to change

- new file: `AGENTS.md`
- optionally: `README.md` (add one pointer line)

## Required behavior

Create `AGENTS.md` with **exactly the structure below**. Adapt the bracketed
placeholders to actual current state. Total length target: 50–80 lines.

```markdown
# AGENTS.md

Working rules for AI agents operating in `ai-git-orchestrator`.
Read this file once at the start of any task; it points to deeper docs only
when needed.

## Project purpose (one line)

PowerShell-based AI development loop coordinating Cursor (implementer),
Codex (technical reviewer), and safe git commit/push for target projects.

## Working scope

You may edit:

- `scripts/` — orchestration logic
- `tests/` — orchestrator validation tests
- `templates/` — files copied into target projects by `install_into_project.ps1`
- `docs/` — architecture, decisions, safety, workflow (NOT `docs/archive/`)
- `README.md`, `AGENTS.md`, `.gitignore`, `pytest.ini`, `requirements.txt`
- `.ai-loop/task.md`, `.ai-loop/cursor_summary.md`, `.ai-loop/project_summary.md`
- `tasks/` — queued task specs

Never edit (forbidden):

- `docs/archive/` — superseded design documents, history-only
- `.ai-loop/_debug/` — raw agent stdout, debug-only (will exist after O06)
- target project files via this repo
- `ai_loop.py` unless task explicitly authorizes (it is experimental and
  separate from the PowerShell loop)

## Read priority

When loading context for a task, read in this order. Stop reading when you
have enough information:

1. `.ai-loop/task.md` — current task contract (always)
2. `.ai-loop/project_summary.md` — durable orientation (always)
3. `AGENTS.md` — this file (always, once)
4. `.ai-loop/cursor_summary.md` — previous iteration only (if N > 1)
5. `docs/architecture.md` — only if task is architecture-related
6. `docs/decisions.md`, `docs/workflow.md`, `docs/safety.md` — only when
   directly relevant to task scope

Do not read by default:

- `docs/archive/` — only by explicit task request
- `tasks/context_audit/` — those are queued specs, not orientation
- `.ai-loop/_debug/` — for human debugging only

## Commands

Test: `python -m pytest -q`
Test with traceback: `python -m pytest -q --tb=short`

PowerShell parse check:

```powershell
powershell -NoProfile -Command "[void][System.Management.Automation.Language.Parser]::ParseFile('scripts\ai_loop_auto.ps1', [ref]$null, [ref]$null)"
powershell -NoProfile -Command "[void][System.Management.Automation.Language.Parser]::ParseFile('scripts\ai_loop_task_first.ps1', [ref]$null, [ref]$null)"
```

## Safe paths (committed by orchestrator)

The default `SafeAddPaths` literal is:

`src/,tests/,README.md,scripts/,docs/,templates/,ai_loop.py,pytest.ini,.gitignore,requirements.txt,pyproject.toml,setup.cfg,.ai-loop/task.md,.ai-loop/cursor_summary.md,.ai-loop/project_summary.md`

This literal lives in `scripts/ai_loop_auto.ps1`, `scripts/ai_loop_task_first.ps1`,
`scripts/continue_ai_loop.ps1`, and is documented in `docs/safety.md`. Keep
them in sync. If you add a new always-commit path, update all four places.

## Templates contract

When you add or remove a file in `templates/`, also check
`scripts/install_into_project.ps1` to update what is auto-copied into target
projects.

## Decision document policy

- `docs/architecture.md` is the single source of truth for target design.
- `docs/decisions.md` tracks numbered `DD-XXX` decisions.
- When a decision is superseded, do not delete it. Mark it superseded inline
  and keep the entry; add the new decision with a higher number.

## Cursor summary contract

After every iteration, update `.ai-loop/cursor_summary.md` with:

- Changed files (brief list)
- Test result (count, not full output)
- What was implemented (3-5 lines)
- Skipped items with reason
- Remaining risks (1-3 bullets)

Do NOT include:

- Earlier task history ("Earlier roll", "Prior task", etc.)
- Full diffs
- Multi-page narratives

Target length: under 50 lines.

## Git hygiene

- Do not commit `.ai-loop/_debug/` content
- Do not commit `.tmp/`, `input/`, `output/`
- Use `git mv` for renames so history is preserved
- Do not commit secrets — check `docs/safety.md` for the recommended scan

## When in doubt

Ask the user. Do not invent commands, paths, or behaviors that are not
documented here or in the linked docs.
```

After creating `AGENTS.md`, optionally add a single line near the top of
`README.md` (e.g. right after the title or first paragraph):

```markdown
See `AGENTS.md` for AI-agent working rules.
```

Only add this line if `README.md` does not already mention `AGENTS.md`.

## Tests

Run:

```powershell
python -m pytest -q
```

Expected: same passing count as before this task. No new tests are required
for this task (a placeholder check that `AGENTS.md` exists is acceptable but
optional — see "Optional test" below).

### Optional test (allowed, not required)

If you want to lock in the file's presence, add a one-line test to
`tests/test_orchestrator_validation.py`:

```python
def test_agents_md_exists():
    assert Path("AGENTS.md").is_file()
```

Skip this if it would expand the test file structure significantly.

## Verification

1. `AGENTS.md` exists at repo root:

   ```powershell
   Test-Path .\AGENTS.md
   ```

   Returns `True`.

2. Line count is 50–80:

   ```powershell
   (Get-Content .\AGENTS.md | Measure-Object -Line).Lines
   ```

3. File mentions all required sections by header name:

   ```powershell
   Select-String -Path .\AGENTS.md -Pattern "^## (Project purpose|Working scope|Read priority|Commands|Safe paths|Templates contract|Decision document policy|Cursor summary contract|Git hygiene)" |
     Measure-Object | Select-Object -ExpandProperty Count
   ```

   Should return 9 (one match per required `##` header).

4. `pytest -q` passes.

5. No file in `docs/archive/` was modified (only the new `AGENTS.md` and
   possibly `README.md`):

   ```powershell
   git status --short
   ```

   Should only show `AGENTS.md` (new) and optionally `README.md` (modified).

## Cursor summary requirements

Update `.ai-loop/cursor_summary.md` with:

1. `AGENTS.md` created with ~N lines.
2. Whether `README.md` was updated with the pointer line (yes/no).
3. Whether optional test was added (yes/no).
4. `pytest -q` result.

Do not include the content of `AGENTS.md` in the summary. A line count + 9
section headers is sufficient.

Target length: 10–15 lines.

## Project summary update

Update `.ai-loop/project_summary.md` only if durable architecture changed.
For this task, add one line to "Important design decisions" or "Notes for
future AI sessions":

- "Working rules for AI agents are in `AGENTS.md` at repo root."

## Important

- Stay within the 50–80 line target for `AGENTS.md`. If you find yourself
  copying paragraphs from `docs/safety.md` or `docs/workflow.md`, stop and
  replace with a pointer link.
- Do not duplicate `docs/architecture.md` content. Reference it.
- Do not commit. The orchestrator handles commit after Codex PASS.
- Use exactly the section headers given in "Required behavior". Codex review
  will check for their presence (verification step 3).
