# Task: Satisfy Codex fix prompt (next_cursor iteration)

This file defines the authorized work for the loop. It replaces the previous placeholder contract.

## Objectives

1. Replace the empty task contract and implement the fix described in `.ai-loop/next_cursor_prompt.md` (same substance as the `FIX_PROMPT_FOR_CURSOR` in `.ai-loop/codex_review.md`).

2. **Orchestrator parity:** `ai_loop.py after-cursor` must write `.ai-loop/git_status.txt` using `git status --short`, matching the PowerShell `Save-TestAndDiff` behavior, alongside `.ai-loop/last_diff.patch` and optional `.ai-loop/test_output.txt`.

3. **Tests:** Add focused unit tests for `ai_loop.py` (e.g. `slugify`, `write_text_safe`) so `python -m pytest` collects and runs at least one test and exits 0 when green.

4. **Artifacts:** Use plain ASCII in `.ai-loop/*` markdown updated by the implementer unless Unicode is required. Regenerate `.ai-loop/last_diff.patch`, `.ai-loop/test_output.txt`, and `.ai-loop/git_status.txt` after changes.

5. Update `.ai-loop/cursor_summary.md` after work. Update `.ai-loop/project_summary.md` only if durable project context changed.

## Out of scope

- Unrelated refactors, new product features beyond the above, git commit/push (orchestrator-owned).

## Task-specific CLI

No separate live application command; validation is `python -m pytest` per orchestrator defaults.
