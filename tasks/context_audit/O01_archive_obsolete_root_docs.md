# O01 — Archive obsolete root docs

- **Target project:** `ai-git-orchestrator`
- **CWD:** `C:\Users\che\Documents\Projects\ai-git-orchestrator`
- **Invocation:** copy section below `---` into `.ai-loop\task.md`, then run

  ```powershell
  powershell -ExecutionPolicy Bypass -File .\scripts\ai_loop_task_first.ps1 -NoPush
  ```

- **Prerequisites:** none. This is the first task in the orchestrator queue.
- **Risk:** very low (pure file moves, no content change, fully reversible
  with `git mv` back).
- **Estimated lines touched:** 3 file moves, possibly small README.md update if
  it references any of the moved files.

---

# Task: Archive obsolete root-level architecture documents

## Project context

Before starting, read:

- `.ai-loop/project_summary.md`
- `.ai-loop/task.md`
- `.ai-loop/cursor_summary.md` if it exists

Background (for the implementer):

The repository root currently contains five large markdown files that
compete for context every time an agent loads "project documentation":

```text
task.md                                340 lines  (current task — KEEP)
README.md                              187 lines  (keep)
architecture_review.md                1312 lines  (historical, supersede)
opencode_harness_expert_review.md     1154 lines  (historical, supersede)
qwen_opencode_problem_for_claude.md    512 lines  (P0 diagnostic, superseded)
```

The last three are historical / superseded reviews. They were useful at the
time but should not be discoverable as primary documentation. `docs/architecture.md`
is now the active architectural source of truth, and the audit at
`docs/context_audit.md` (or in chat) is the latest review.

## Goal

Move the three superseded root markdown files into `docs/archive/` with a date
prefix so they remain in history but are off the root namespace and off the
default agent read path.

## Scope

### Allowed

- `git mv` each of the three files into `docs/archive/` with date-prefixed
  names (see Required behavior).
- Create the `docs/archive/` directory if it does not exist.
- If `README.md` references the moved files by name, update those references
  to point to the new paths in `docs/archive/`.
- Update `.gitignore` only if archive paths need explicit inclusion (they
  should not — `docs/` is tracked by default).

### Not allowed

- Do **not** modify the contents of the moved files. Only rename / move.
- Do **not** delete the files (this is archival, not removal).
- Do **not** touch `docs/architecture.md`, `docs/decisions.md`,
  `docs/workflow.md`, `docs/safety.md` in this task.
- Do **not** modify any file in `scripts/`, `tests/`, `templates/`,
  `.ai-loop/` (except the task contract files this template already covers).
- Do **not** touch `task.md` at repo root — it is the current task surface.

## Files likely to change

- `architecture_review.md` → `docs/archive/2026-05-11_architecture_review.md`
- `opencode_harness_expert_review.md` → `docs/archive/2026-05-11_opencode_harness_expert_review.md`
- `qwen_opencode_problem_for_claude.md` → `docs/archive/2026-05-11_qwen_opencode_problem.md`
- `README.md` — only if it references the moved filenames
- new directory: `docs/archive/`

## Required behavior

1. Verify the three source files exist at repo root:

   ```powershell
   Test-Path .\architecture_review.md
   Test-Path .\opencode_harness_expert_review.md
   Test-Path .\qwen_opencode_problem_for_claude.md
   ```

   All three must return `True`.

2. Create `docs/archive/` if not present:

   ```powershell
   New-Item -ItemType Directory -Force -Path .\docs\archive | Out-Null
   ```

3. Move each file using `git mv` (not `Move-Item`, so git records as rename):

   ```powershell
   git mv .\architecture_review.md `
          .\docs\archive\2026-05-11_architecture_review.md

   git mv .\opencode_harness_expert_review.md `
          .\docs\archive\2026-05-11_opencode_harness_expert_review.md

   git mv .\qwen_opencode_problem_for_claude.md `
          .\docs\archive\2026-05-11_qwen_opencode_problem.md
   ```

4. Search the rest of the repository for any references to the moved files by
   their old basenames. Use the workspace search tool or:

   ```powershell
   rg -i "architecture_review\.md|opencode_harness_expert_review\.md|qwen_opencode_problem_for_claude\.md" `
      --glob '!docs/archive/*' --glob '!.git/*' --glob '!.ai-loop/*'
   ```

   Expected: zero matches outside `docs/archive/` and `.ai-loop/`. If matches
   exist (likely in `README.md` or `docs/architecture.md`):

   - In Markdown links, update the path to `docs/archive/<dated_name>.md`.
   - In prose references, prefer phrasing like
     "(see `docs/archive/2026-05-11_architecture_review.md` for the original
     review)".

5. Do **not** edit `.ai-loop/architecture.md` references — that file
   should not exist; if it does, leave it alone for now (it would be a
   separate cleanup).

## Tests

Run:

```powershell
python -m pytest -q
```

Expected: all tests pass. Currently the suite has ~23 tests in
`tests/test_ai_loop.py` and `tests/test_orchestrator_validation.py`. No
change in count is expected from this task.

The orchestrator-validation tests parse PowerShell scripts and check
`SafeAddPaths` literals. None of those reference the moved files, so the test
count should be unchanged.

## Verification

1. Three files exist at new locations:

   ```powershell
   Test-Path .\docs\archive\2026-05-11_architecture_review.md
   Test-Path .\docs\archive\2026-05-11_opencode_harness_expert_review.md
   Test-Path .\docs\archive\2026-05-11_qwen_opencode_problem.md
   ```

   All must return `True`.

2. Three files do **not** exist at old locations:

   ```powershell
   Test-Path .\architecture_review.md
   Test-Path .\opencode_harness_expert_review.md
   Test-Path .\qwen_opencode_problem_for_claude.md
   ```

   All must return `False`.

3. Git recognizes them as renames (not delete+add):

   ```powershell
   git status --short
   ```

   Should show `R  architecture_review.md -> docs/archive/2026-05-11_architecture_review.md`
   pattern (the `R` for rename), not `D` + `??`. If git did not detect the
   rename (rare on this size), the file contents are identical so git's
   rename heuristics should pick them up; if not, that's still fine — the
   important property is content preservation.

4. No broken references outside archive:

   ```powershell
   rg -i "architecture_review\.md|opencode_harness_expert_review\.md|qwen_opencode_problem_for_claude\.md" `
      --glob '!docs/archive/*' --glob '!.git/*' --glob '!.ai-loop/*' .
   ```

   Either zero matches, or all remaining matches point to the new path.

5. pytest passes:

   ```powershell
   python -m pytest -q
   ```

## Cursor summary requirements

Update `.ai-loop/cursor_summary.md` with:

1. Three files moved with `git mv` and their new locations.
2. Whether `README.md` (or any other file) was updated to fix references —
   if yes, list the file and the change in one line.
3. `pytest -q` result (count of passed / skipped tests).
4. Risks remaining: none expected. If git did not detect a rename, mention
   that the file contents are byte-identical so a future `git log --follow`
   still works on the archived files.

Do **not** include:

- A description of the moved files' contents.
- The reason they were archived (already in this task spec).
- History of previous Cursor rolls.

Target length: 15–25 lines.

## Project summary update

Update `.ai-loop/project_summary.md` only if durable architecture changed.
For this task, the only durable change is: "the orchestrator now has a
`docs/archive/` directory for superseded design documents". One line is
enough, added to the "Current architecture" or "Important design decisions"
section.

Do **not** turn `project_summary.md` into a per-task changelog.

## Important

- Do **not** modify the moved files' contents. Use `git mv` so git tracks the
  rename and history is preserved.
- Do **not** stage or commit. The orchestrator handles commit after Codex
  PASS.
- Do **not** introduce any other "while I'm here" refactors. If you notice
  other doc cleanup opportunities, leave a note in `cursor_summary.md` —
  there is a follow-up task queue for those.
- Date prefix `2026-05-11` reflects when the original reviews were produced.
  Do not change to today's date.
