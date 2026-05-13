# Project Summary

## Project Purpose

`ai-orchestrator` is a local PowerShell-based AI development loop that coordinates an implementer (Cursor Agent by default; OpenCode/Qwen via wrapper), Codex review, optional tests, and guarded git commit/push using a file contract under `.ai-loop/`.

## Current Architecture

- `ai_loop.py` -- experimental GitHub PR orchestrator; separate from the primary PowerShell loop.
- `scripts/ai_loop_task_first.ps1` -- task-first entry: resets `implementer_summary.md`, saves the effective implementer selection, runs the configured implementer, gates on a path-set delta plus `.ai-loop/implementer_result.md` mtime/existence, then invokes `ai_loop_auto.ps1`.
- `scripts/ai_loop_auto.ps1` -- test/diff capture, Codex review, fix-loop, final test gate, safe staging, commit/push.
- `scripts/continue_ai_loop.ps1` -- resume wrapper for `ai_loop_auto.ps1 -Resume`; forwards explicit `-CursorCommand` / `-CursorModel` overrides.
- `scripts/run_cursor_agent.ps1` and `scripts/run_opencode_agent.ps1` -- implementer wrappers; parameter names remain `-CursorCommand` / `-CursorModel` for compatibility.
- `scripts/install_into_project.ps1` -- copies drivers, wrappers, templates, and `opencode.json` into target projects without clobbering existing task/project summary unless requested.
- `tests/test_orchestrator_validation.py` -- parser smoke tests, safe-path parity, task-first delta semantics, implementer-state resume behavior, prompt parsing, dynamic step-label checks, and repo map determinism checks.
- `.ai-loop/repo_map.md` is a committed, script-generated file index. Regenerate via `scripts/build_repo_map.ps1` after structural changes; deterministic output is pinned by tests.
- `templates/` -- target-project scaffolds, including `implementer_summary_template.md`, `codex_review_prompt.md`, `project_summary.md`, `task.md`, and `opencode.json`.

## Current Pipeline / Workflow

For a new task, run `ai_loop_task_first.ps1`. It runs the implementer first, then hands off to `ai_loop_auto.ps1` only after meaningful implementation side effects or an accepted no-code marker in `.ai-loop/implementer_result.md`. For existing changes, run `ai_loop_auto.ps1` directly. Codex reviews after tests/diff capture; `PASS` triggers final tests and safe commit/push unless `-NoPush`; `FIX_REQUIRED` writes `.ai-loop/next_implementer_prompt.md` and reruns the selected implementer.

Resume uses `.ai-loop/implementer.json` (runtime, gitignored) to reload the last effective wrapper/model when `-CursorCommand` is omitted. Explicit `-CursorCommand` / `-CursorModel` on `continue_ai_loop.ps1` or `ai_loop_auto.ps1 -Resume` override persisted state.

## Important Design Decisions

- Active PowerShell artifacts are implementer-neutral: `implementer_summary.md`, `next_implementer_prompt.md`, `implementer_result.md`, `FIX_PROMPT_FOR_IMPLEMENTER`, and `_debug/implementer_*`.
- Legacy Cursor-named alias artifacts are removed from the active PowerShell contract; summary, next-fix prompt, fix label, result marker, and debug outputs use implementer-neutral names.
- `run_cursor_agent.ps1` remains because it is the real Cursor wrapper, not a legacy alias. `-CursorCommand` / `-CursorModel` remain as compatibility parameter names.
- `SafeAddPaths` stages durable files only: project files plus `.ai-loop/task.md`, `.ai-loop/implementer_summary.md`, `.ai-loop/project_summary.md`, and `.ai-loop/repo_map.md`.
- Runtime outputs (`codex_review.md`, diffs, test logs, `implementer_result.md`, `implementer.json`, `_debug/`, final status) are gitignored and not staged by default.
- `docs/architecture.md` is the source of truth for target design; `docs/decisions.md` is the numbered index.

## Known Risks / Constraints

- External CLIs (`codex`, Cursor Agent, OpenCode, local llama.cpp servers) must be installed and authenticated/configured where used.
- On Windows PowerShell, empty array returns can become `$null`; path-set helpers emit through the pipeline and callers wrap with `@(...)`.
- `ai_loop.py` still carries older experimental Cursor-centric terminology and is intentionally separate from the active PowerShell loop unless a task explicitly authorizes changing it.

## Current Stage

Reviewable: PowerShell loop supports persisted implementer selection, dynamic STEP 1 labels (`CURSOR`, `QWEN`, `IMPLEMENTER`), OpenCode/Qwen wrapper execution, and implementer-neutral active artifacts. `python -m pytest -q` should pass before committing any further change.

## Last Completed Task

OpenCode/Qwen integration and neutral implementer contract were introduced while preserving Cursor as the default production implementer through Phase 1.

## Next Likely Steps

1. Run `python -m pytest -q` and PowerShell parser checks after each script contract change.
2. Use task-first for new work; use `continue_ai_loop.ps1` for interrupted review/fix loops so persisted implementer state can be reused.

## Notes For Future AI Sessions

- Keep durable project-level context here; put per-iteration detail in `.ai-loop/implementer_summary.md`.
- Use `.ai-loop/task.md` as the task source of truth.
- Do not read or write `.ai-loop/_debug/` unless explicitly debugging raw agent output.
