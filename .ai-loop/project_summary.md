# Project Summary

## Project purpose

Local PowerShell-based AI development loop that coordinates Cursor (implementer), Codex (review), optional tests, and guarded git commit/push using a file-based contract under `.ai-loop/`.

## Current architecture

- `ai_loop.py` -- experimental GitHub PR orchestrator (stdlib-only); separate from the primary PowerShell Cursor + Codex loop; does not replace `scripts/ai_loop_auto.ps1` / `ai_loop_task_first.ps1`.
- `scripts/ai_loop_auto.ps1`, `scripts/continue_ai_loop.ps1`, `scripts/install_into_project.ps1` -- PowerShell drivers and installer.
- `scripts/ai_loop_task_first.ps1` -- task-first entry: clears a defined set of `.ai-loop` runtime artifacts, stubs `cursor_summary.md`, runs Cursor, gates on a **path-set** delta from `git status --porcelain --untracked-files=all` (excluding orchestrator scratch paths) plus **mtime/existence** for `.ai-loop/cursor_implementation_result.md`. `Get-ImplementationDeltaPaths` emits sorted paths on the pipeline (avoids Windows PowerShell turning empty `return @()` into `$null`); `Invoke-CursorImplementation` assigns `@(Get-ImplementationDeltaPaths)` and uses `Compare-Object @($beforePaths) @($afterPaths)` so empty sets compare reliably. Then invokes `ai_loop_auto.ps1` forwarding `-NoPush`, `-TestCommand`, `-PostFixCommand`, and `-SafeAddPaths`.
- `tests/test_ai_loop.py` -- pytest coverage for pure helpers (`slugify`, `write_text_safe`). The `write_text_safe` test uses a unique-named scratch file under `tests/` removed in `finally`, avoiding pytest `tmp_path`, basetemp under `.tmp/`, repo-root temp dirs, and `tempfile.TemporaryDirectory(dir=repo)` (all problematic on some Windows setups).
- `tests/test_orchestrator_validation.py` -- PowerShell parser smoke check for `ai_loop_auto.ps1` / `ai_loop_task_first.ps1`, parity and porcelain-flag checks, path-set delta + marker-gate reference tests, auto-loop no-op reason literals, and `SafeAddPaths` parity across `ai_loop_auto.ps1`, `ai_loop_task_first.ps1`, and `continue_ai_loop.ps1` (includes `docs/` and `templates/`).
- `pytest.ini` -- limits collection to `tests/` via `testpaths` and skips common runtime dirs (`.ai-loop`, `.tmp`, stray root temp names, caches) via `norecursedirs` so pytest does not wander the repo root by default.
- `docs/archive/` -- dated superseded design / review Markdown under `docs/` (O01 moved three root-level review/diagnostic files to `2026-05-11_*.md` without editing file bodies). O01 does **not** introduce or stage `docs/architecture.md`; that remains a separate doc-maintenance task when scheduled.
- `.ai-loop/*.md` -- task file, durable summary, review prompts, cursor summary template.

## Current pipeline / workflow

Install scripts into a target repo, author task and context. For a **new** task, run `ai_loop_task_first.ps1` (Cursor first, then `ai_loop_auto.ps1` when there is a meaningful implementation delta). For **existing** changes, run `ai_loop_auto.ps1` directly. Review artifacts, continue or commit per safety model (`SafeAddPaths`, ignored runtime files). After Codex returns `PASS`, the PowerShell orchestrator runs the final test gate (`Commit-And-Push`), then stages safe paths and pushes unless `-NoPush`. Resume mode respects existing `next_cursor_prompt.md` or `codex_review.md` (`PASS` → final gate + commit/push; `FIX_REQUIRED` → extract fix prompt → Cursor).

## Important design decisions

- Staging is restricted to explicit safe paths; runtime outputs under `.ai-loop/` (e.g. `last_diff.patch`, `test_output*.txt`, `git_status.txt`, Cursor implementation scratch/result files, reviews) stay out of commits by default.
- Task-first mode enforces “result only” completions using a **symmetric path-set** delta from `git status --porcelain --untracked-files=all` after excluding the same orchestrator scratch paths (`cursor_summary.md`, implementation prompt/output), merged with **last-write-time / existence** checks for `.ai-loop/cursor_implementation_result.md`; each task-first run resets `cursor_summary.md` to a stub so Codex does not read stale summaries.
- Default `SafeAddPaths` in `ai_loop_auto.ps1`, `continue_ai_loop.ps1`, and `ai_loop_task_first.ps1` includes repo-root `ai_loop.py`, `pytest.ini`, `docs/`, and `templates/` so intent-to-add review covers the Python entry, pytest config, and durable docs/templates. `docs/safety.md` documents that same default list (path order matches the shared literal).
- `project_summary.md` holds long-lived context; it is not a per-task changelog.
- Parity between the Python `after-cursor` step and PowerShell `Save-TestAndDiff` includes a short git status file for reviewers.
- Codex is the automated review gate before commit/push; Codex PASS triggers final tests then commit/push.

## Known risks / constraints

- External CLIs (`agent`, `codex`) must be installed and authenticated where those steps are used.
- On Windows PowerShell, an empty array returned with `return @()` from a function can surface as `$null` to callers; task-first path capture avoids that for the implementation-delta helper (pipeline output + `@(Get-ImplementationDeltaPaths)` / wrapped `Compare-Object`).

## Current stage

**In progress / reviewable:** PowerShell orchestrator uses Codex-only automated review; post-Codex PASS runs final test gate, commit, and optional push. Task-first mode gates Codex until Cursor produces a path-set delta or updates the result file on disk; `ai_loop_auto.ps1` skips Codex when the tree is clean before review (exits **6** / **7**) and clears stale `.ai-loop` runtime artifacts on non-resume starts.

## Last completed task

Task-first **path-set comparison hardening** plus **helper cleanup:** `Test-ResultFileChangedDuringPass` / `Assert-CanProceedAfterImplementation` removed in favor of inlined equivalent checks; `Get-ImplementationDeltaPaths` remains the single path-set helper. Prior: empty-set `Compare-Object` hardening, P0 porcelain path-set + result mtime, auto-loop clean-tree exits 6/7, Claude review template removed. Latest hygiene pass: removed untracked root `task.md` and `.claude/` local settings so only `.ai-loop/task.md` documents the task.

## Next likely steps

1. Stage root `ai_loop.py`, `pytest.ini`, `tests/`, `scripts/`, `docs/`, `templates/`, and other paths listed in orchestrator `SafeAddPaths` when committing.
2. Re-run `ai_loop_task_first.ps1` or `ai_loop_auto.ps1` / Codex when ready for the next task or review round.

## Notes for future AI sessions

- Keep durable project-level context here; put per-iteration detail in `.ai-loop/cursor_summary.md`.
- Use **`.ai-loop/task.md`** as the task source of truth; do not reintroduce a duplicate root `task.md` or editor-local `.claude/` permission files — they are not part of the repo contract.
