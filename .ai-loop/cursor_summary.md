# Cursor Summary

## Changed files

- `scripts/ai_loop_auto.ps1`, `scripts/continue_ai_loop.ps1` -- default `SafeAddPaths` includes repo-root `ai_loop.py` and `pytest.ini` for guarded intent-to-add review.
- `README.md` -- optional `-SafeAddPaths` example updated to match script defaults (including `ai_loop.py`, `pytest.ini`, `setup.cfg`).
- `.ai-loop/project_summary.md` -- durable note on default safe paths and refreshed stage / last-task lines.

## Test result

Command: `python ai_loop.py after-cursor --test-cmd "python -m pytest -q"` (runs `python -m pytest -q`).

Result: **4 passed** in 0.01s (exit code 0).

## Implementation summary

- Satisfied `.ai-loop/next_cursor_prompt.md`: root orchestrator and pytest config are in the default safe-add list; documentation stays consistent with the scripts.

## Task-specific CLI / live run

Per `.ai-loop/task.md`, validation is `python -m pytest` only; covered by the `after-cursor` test command above. No separate application command.

## Remaining risks

- Target repos that keep the Python entry elsewhere still need a custom `-SafeAddPaths` string.
- Gitignored loop files (`codex_review.md`, `next_cursor_prompt.md`, some artifacts) may not appear in `git diff`; reviewers should open those paths locally when needed.
