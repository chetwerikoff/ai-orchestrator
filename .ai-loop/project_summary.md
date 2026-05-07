# Project Summary

## Project purpose

Local PowerShell-based AI development loop that coordinates Cursor (implementer), Codex (review), optional tests, and guarded git commit/push using a file-based contract under `.ai-loop/`.

## Current architecture

- `ai_loop.py` -- experimental GitHub PR orchestrator (stdlib-only); separate from the primary PowerShell Cursor + Codex loop; does not replace `scripts/ai_loop_auto.ps1` / `ai_loop_task_first.ps1`.
- `scripts/ai_loop_auto.ps1`, `scripts/continue_ai_loop.ps1`, `scripts/install_into_project.ps1` -- PowerShell drivers and installer.
- `scripts/ai_loop_task_first.ps1` -- task-first entry: clears a defined set of `.ai-loop` runtime artifacts, stubs `cursor_summary.md`, runs Cursor, gates on filtered porcelain **delta** from `git status --porcelain --untracked-files=all` plus **per-path SHA256 snapshots** for files referenced by filtered porcelain (excluding orchestrator scratch paths), merged with **filesystem change detection** for gitignored `.ai-loop/cursor_implementation_result.md` (merged into the full delta for `IMPLEMENTATION_STATUS: DONE_NO_CODE_CHANGES_REQUIRED` when the sole change is that result file). Paths that resolve to **directories** use a deterministic recursive manifest hash (nested relative paths + file hashes) so edits under an already-untracked tree cannot appear as `Exists=true` with a meaningless hash. Then invokes `ai_loop_auto.ps1` forwarding `-NoPush`, `-TestCommand`, `-PostFixCommand`, and `-SafeAddPaths`.
- `tests/test_ai_loop.py` -- pytest coverage for pure helpers (`slugify`, `write_text_safe`). The `write_text_safe` test uses a unique-named scratch file under `tests/` removed in `finally`, avoiding pytest `tmp_path`, basetemp under `.tmp/`, repo-root temp dirs, and `tempfile.TemporaryDirectory(dir=repo)` (all problematic on some Windows setups).
- `tests/test_orchestrator_validation.py` -- PowerShell parser smoke check for `ai_loop_auto.ps1` / `ai_loop_task_first.ps1` plus reference tests for porcelain-line delta semantics and merged delta semantics (porcelain + content/hash snapshots via `content_changed_paths` + ignored result file via `result_changed_during_pass`) used by the task-first marker gate, including stable porcelain under an untracked **directory** path when the directory fingerprint changes; asserts default `SafeAddPaths` literals stay in parity across `ai_loop_auto.ps1`, `ai_loop_task_first.ps1`, and `continue_ai_loop.ps1` and include `docs/` and `templates/`.
- `pytest.ini` -- limits collection to `tests/` via `testpaths` and skips common runtime dirs (`.ai-loop`, `.tmp`, stray root temp names, caches) via `norecursedirs` so pytest does not wander the repo root by default.
- `.ai-loop/*.md` -- task file, durable summary, review prompts, cursor summary template.

## Current pipeline / workflow

Install scripts into a target repo, author task and context. For a **new** task, run `ai_loop_task_first.ps1` (Cursor first, then `ai_loop_auto.ps1` when there is a meaningful implementation delta). For **existing** changes, run `ai_loop_auto.ps1` directly. Review artifacts, continue or commit per safety model (`SafeAddPaths`, ignored runtime files). After Codex returns `PASS`, the PowerShell orchestrator runs the final test gate (`Commit-And-Push`), then stages safe paths and pushes unless `-NoPush`. Resume mode respects existing `next_cursor_prompt.md` or `codex_review.md` (`PASS` → final gate + commit/push; `FIX_REQUIRED` → extract fix prompt → Cursor).

## Important design decisions

- Staging is restricted to explicit safe paths; runtime outputs under `.ai-loop/` (e.g. `last_diff.patch`, `test_output*.txt`, `git_status.txt`, Cursor implementation scratch/result files, reviews) stay out of commits by default.
- Task-first mode enforces “result only” completions using the **Cursor pass** porcelain **delta** from `--untracked-files=all` output merged with **content hashes** for paths shown in filtered porcelain (excluding the same scratch paths as porcelain filtering) plus on-disk change detection for `.ai-loop/cursor_implementation_result.md` (so gitignored results still participate); orchestrator excludes `cursor_summary.md` plus implementation prompt/output lines from porcelain-driven snapshots; pre-existing unrelated dirt on paths whose porcelain line is unchanged **does** contribute when file bytes change during the pass; **directory** paths in the snapshot set use a recursive manifest hash so nested untracked edits cannot be missed when porcelain lines stay stable; **`Get-ResultFileSnapshot` never returns `Exists=true` with null/empty `Hash`** (uses `FILEHASH_UNREADABLE` / `SNAPSHOT_HASH_UNAVAILABLE` sentinels when hashing fails) so content deltas cannot spuriously agree on `(Exists, $null)`; each task-first run resets `cursor_summary.md` to a stub so Codex does not read stale summaries.
- Default `SafeAddPaths` in `ai_loop_auto.ps1`, `continue_ai_loop.ps1`, and `ai_loop_task_first.ps1` includes repo-root `ai_loop.py`, `pytest.ini`, `docs/`, and `templates/` so intent-to-add review covers the Python entry, pytest config, and durable docs/templates. `docs/safety.md` documents that same default list (path order matches the shared literal).
- `project_summary.md` holds long-lived context; it is not a per-task changelog.
- Parity between the Python `after-cursor` step and PowerShell `Save-TestAndDiff` includes a short git status file for reviewers.
- Codex is the automated review gate before commit/push; Codex PASS triggers final tests then commit/push.

## Known risks / constraints

- External CLIs (`agent`, `codex`) must be installed and authenticated where those steps are used.

## Current stage

**In progress / reviewable:** PowerShell orchestrator uses Codex-only automated review; post-Codex PASS runs final test gate, commit, and optional push. Task-first mode gates Codex until Cursor produces meaningful changes, with auto-loop flag parity (`-NoPush`, `-TestCommand`, `-PostFixCommand`, `-SafeAddPaths`), porcelain delta from `--untracked-files=all`, filtered-path content snapshots (files: SHA256; directories: recursive manifest hash) plus filesystem merge for gitignored `.ai-loop/cursor_implementation_result.md`, and marker enforcement for no-code completions.

## Last completed task

Task-first delta detection hardening: keep porcelain via `git status --porcelain --untracked-files=all` with documented rationale; `Get-ResultFileSnapshot` seals `Exists=true` snapshots with non-null hashes (file try/catch + directory manifest unchanged structurally); pytest guards `--untracked-files=all` in script plus stable `?? dir/` directory fingerprint regression; `docs/workflow.md` documents exact `(?im)^IMPLEMENTATION_STATUS:\s*DONE_NO_CODE_CHANGES_REQUIRED\s*$` marker regex aligned with `Test-CursorResultAllowsNoCodeChanges`.

Default `SafeAddPaths` parity: `docs/` and `templates/` added to orchestrator defaults; pytest guards parity across `ai_loop_auto.ps1`, `ai_loop_task_first.ps1`, and `continue_ai_loop.ps1`.

Task-first gate: filesystem-backed detection for gitignored `cursor_implementation_result.md`; porcelain deltas plus SHA256 snapshots over filtered-porcelain paths (excluding orchestrator scratch filenames); pytest coverage for merged delta edge cases including stable porcelain lines with changing file bytes.

Docs/safety hygiene: `docs/safety.md` “default safe paths” matches the shared default `SafeAddPaths` literal; stray repo-root `task.md` removed (use `.ai-loop/task.md` only).

## Next likely steps

1. Stage root `ai_loop.py`, `pytest.ini`, `tests/`, `scripts/`, `docs/`, `templates/`, and other paths listed in orchestrator `SafeAddPaths` when committing.
2. Re-run `ai_loop_task_first.ps1` or `ai_loop_auto.ps1` / Codex when ready for the next task or review round.

## Notes for future AI sessions

- Keep durable project-level context here; put per-iteration detail in `.ai-loop/cursor_summary.md`.
