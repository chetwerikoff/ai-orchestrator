# Project Summary

## Project purpose

Local PowerShell-based AI development loop that coordinates Cursor (implementer), Codex (review), Claude (final review), optional tests, and guarded git commit/push using a file-based contract under `.ai-loop/`.

## Current architecture

- `ai_loop.py` -- orchestration entry (diff/status artifacts, optional test command, review integration hooks). `after-cursor` writes `.ai-loop/last_diff.patch`, `.ai-loop/git_status.txt` (`git status --short`), and optional `.ai-loop/test_output.txt`. Captured subprocess stdout/stderr uses UTF-8 with replacement on decode errors to avoid Windows console encoding failures.
- `scripts/ai_loop_auto.ps1`, `scripts/continue_ai_loop.ps1`, `scripts/install_into_project.ps1` -- PowerShell drivers and installer.
- `tests/test_ai_loop.py` -- pytest coverage for pure helpers (`slugify`, `write_text_safe`). The `write_text_safe` test uses a unique-named scratch file under `tests/` removed in `finally`, avoiding pytest `tmp_path`, basetemp under `.tmp/`, repo-root temp dirs, and `tempfile.TemporaryDirectory(dir=repo)` (all problematic on some Windows setups).
- `pytest.ini` -- limits collection to `tests/` via `testpaths` and skips common runtime dirs (`.ai-loop`, `.tmp`, stray root temp names, caches) via `norecursedirs` so pytest does not wander the repo root by default.
- `.ai-loop/*.md` -- task file, durable summary, review prompts, cursor summary template.

## Current pipeline / workflow

Install scripts into a target repo, author task and context, run `ai_loop_auto.ps1`, review artifacts, continue or commit per safety model (`SafeAddPaths`, ignored runtime files).

## Important design decisions

- Staging is restricted to explicit safe paths; runtime outputs under `.ai-loop/` (e.g. `last_diff.patch`, `test_output.txt`, `git_status.txt`, reviews) stay out of commits by default.
- Default `SafeAddPaths` in `ai_loop_auto.ps1` and `continue_ai_loop.ps1` includes repo-root `ai_loop.py` and `pytest.ini` so intent-to-add review covers the Python entry and pytest config.
- `project_summary.md` holds long-lived context; it is not a per-task changelog.
- Parity between the Python `after-cursor` step and PowerShell `Save-TestAndDiff` includes a short git status file for reviewers.

## Known risks / constraints

- External CLIs (`agent`, `codex`, `claude`) must be installed and authenticated where those steps are used.

## Current stage

**In progress / reviewable:** Default `SafeAddPaths` covers root `ai_loop.py` and `pytest.ini`; README optional-parameters example matches those defaults. Pytest remains root-safe via `pytest.ini`; `after-cursor` artifacts refreshed.

## Last completed task

Per `.ai-loop/next_cursor_prompt.md`: extend default `SafeAddPaths` with repo-root `ai_loop.py` and `pytest.ini`; align README `-SafeAddPaths` example with script defaults; rerun `after-cursor` with pytest.

## Next likely steps

1. Stage root `ai_loop.py`, `pytest.ini`, `tests/`, and other paths listed in orchestrator `SafeAddPaths` when committing.
2. Re-run `ai_loop_auto.ps1` / Codex or Claude when ready for the next review round or feature.

## Notes for future AI sessions

- Keep durable project-level context here; put per-iteration detail in `.ai-loop/cursor_summary.md`.
