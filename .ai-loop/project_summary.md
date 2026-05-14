# Project Summary

## Project Purpose

`ai-orchestrator` is a local PowerShell-based AI development loop that coordinates an implementer (Cursor Agent by default; OpenCode/Qwen via wrapper), Codex review, optional tests, and guarded git commit/push using a file contract under `.ai-loop/`.

## Current Architecture

- `ai_loop.py` -- experimental GitHub PR orchestrator; separate from the primary PowerShell loop.
- `scripts/ai_loop_task_first.ps1` -- task-first entry: auto-refreshes `.ai-loop/repo_map.md` at start when missing or older than one hour (non-fatal); resets `implementer_summary.md`, saves the effective implementer selection, runs the configured implementer, gates on a path-set delta plus `.ai-loop/implementer_result.md` mtime/existence, then invokes `ai_loop_auto.ps1`. See **DD-022** for optional `-WithScout` and **DD-023** for optional `-WithWrapUp`.
- `scripts/ai_loop_auto.ps1` — test/diff capture, Codex review, fix-loop, final test gate, safe staging, commit/push. Codex instructions use a single-quoted here-string so fenced JSON survives for `codex exec` and `Extract-FixPromptFromFile`. Optional `-WithWrapUp` (DD-023) runs `scripts/wrap_up_session.ps1` post-pass toward `.ai-loop/_debug/session_draft.md` without affecting exit codes when wrap-up errs.
- `scripts/continue_ai_loop.ps1` -- resume wrapper for `ai_loop_auto.ps1 -Resume`; forwards explicit `-CursorCommand`, `-CursorModel`, and `-WithWrapUp`.
- `scripts/run_cursor_agent.ps1` and `scripts/run_opencode_agent.ps1` -- implementer wrappers; parameter names remain `-CursorCommand` / `-CursorModel` for compatibility.
- `scripts/run_opencode_scout.ps1` -- OpenCode scout role wrapper (same stdin/`opencode run` flow as `run_opencode_agent.ps1` but SCOUT framing so scout instructions are not overridden by the implementer message).
- `scripts/run_scout_pass.ps1` -- optional read-only scout pre-pass for `-WithScout` (DD-022); writes gitignored `.ai-loop/_debug/scout_*` artifacts only. When `-CommandName` points at `run_opencode_agent.ps1`, the pass auto-substitutes `run_opencode_scout.ps1` beside this script to avoid role conflict; warns and falls back if the scout wrapper is missing. Short scout output (under 200 bytes) is treated as a non-fatal startup failure with a warning.
- `tests/test_orchestrator_validation.py` — parser smoke tests, safe-path parity, task-first delta semantics, implementer-state resume behavior, prompt parsing (C02 uses a dot-sourced PowerShell harness so `$STABLE_PREAMBLE` / `Get-TaskScopeBlocks` are not reimplemented in Python), dynamic step-label checks, repo map determinism checks, Codex `Run-CodexReview`/template fenced-json assertions. Added wrap-up (`wrap_up_session.ps1`) plus manual promote (`promote_session.ps1`) checks for DD-023.
- `.ai-loop/repo_map.md` is a committed, script-generated file index. `ai_loop_task_first.ps1` invokes `scripts/build_repo_map.ps1` automatically when the map is absent or stale (>1 h); regenerate manually after structural changes if you need immediate freshness; deterministic output is pinned by tests.
- `templates/` -- target-project scaffolds, including `implementer_summary_template.md`, `codex_review_prompt.md`, `project_summary.md`, `task.md`, and `opencode.json`.
- `scripts/install_into_project.ps1` -- copies orchestrator scripts (including `run_scout_pass.ps1` and `run_opencode_scout.ps1` for DD-022 `-WithScout`, plus `wrap_up_session.ps1` and `promote_session.ps1` for DD-023) and `templates/` into a target project; when adding or removing files under `templates/`, update this script so installs stay complete (see AGENTS.md templates contract).

## Current Pipeline / Workflow

For a new task, run `ai_loop_task_first.ps1`. It runs the implementer first, then hands off to `ai_loop_auto.ps1` only after meaningful implementation side effects or an accepted no-code marker in `.ai-loop/implementer_result.md`. For existing changes, run `ai_loop_auto.ps1` directly. Codex reviews after tests/diff capture; `PASS` triggers final tests and safe commit/push unless `-NoPush`; `FIX_REQUIRED` writes `.ai-loop/next_implementer_prompt.md` and reruns the selected implementer.

Resume uses `.ai-loop/implementer.json` (runtime, gitignored) to reload the last effective wrapper/model when `-CursorCommand` is omitted. Explicit `-CursorCommand` / `-CursorModel` on `continue_ai_loop.ps1` or `ai_loop_auto.ps1 -Resume` override persisted state.

## Important Design Decisions

- Implementer prompt = `$STABLE_PREAMBLE` + `FILES IN SCOPE:` / `FILES OUT OF SCOPE:` blocks parsed from `task.md` + `TASK:` body. Required sections in `templates/task.md`; missing sections produce a warning, not a failure.
- Optional `-WithScout` (DD-022) runs `scripts/run_scout_pass.ps1` before the implementer pass and inserts `RELEVANT FILES (from scout):` after the scope blocks when scout returns a non-empty `relevant_files` list. Off by default; failures are non-fatal.
- Active PowerShell artifacts are implementer-neutral: `implementer_summary.md`, `next_implementer_prompt.md`, `implementer_result.md`, `FIX_PROMPT_FOR_IMPLEMENTER`, and `_debug/implementer_*`. Optional wrap-up emits `_debug/session_draft.md`; running `promote_session.ps1` elevates drafts into tracked `.ai-loop/failures.md` (manual only, rolling retention per DD-023).
- Wrap-up draft headings and the `failures.md` seed use Unicode em dash (U+2014) in emitted markdown. Orchestrator `.ps1` sources build that character with `[char]0x2014` / subexpressions so literals stay ASCII-friendly for Windows PowerShell 5.1 `Parser::ParseFile`.
- Codex emits `FIX_PROMPT_FOR_IMPLEMENTER` as JSON (`fix_required`, `files`, `changes[]`, `acceptance`); `Extract-FixPromptFromFile` prefers JSON and falls back to the legacy free-text regex with a warning. Codex prompt forbids full-suite re-runs (orchestrator pre-captures pytest output); targeted single-test runs are allowed with a one-line reason in `FINAL_NOTE`.
- Legacy Cursor-named alias artifacts are removed from the active PowerShell contract; summary, next-fix prompt, fix label, result marker, and debug outputs use implementer-neutral names.
- `run_cursor_agent.ps1` remains because it is the real Cursor wrapper, not a legacy alias. `-CursorCommand` / `-CursorModel` remain as compatibility parameter names.
- `SafeAddPaths` stages durable files only: project files plus `.ai-loop/task.md`, `.ai-loop/implementer_summary.md`, `.ai-loop/project_summary.md`, `.ai-loop/repo_map.md`, `.ai-loop/failures.md`, `.ai-loop/archive/rolls/`, plus optional tracked `.ai-loop/_debug/session_draft.md` snippets when deliberately promoted upstream.
- Runtime outputs (`codex_review.md`, diffs, test logs, `implementer_result.md`, `implementer.json`, `_debug/`, final status) are gitignored and not staged by default.
- `docs/architecture.md` is the source of truth for target design; `docs/decisions.md` is the numbered index.

## Known Risks / Constraints

- External CLIs (`codex`, Cursor Agent, OpenCode, local llama.cpp servers) must be installed and authenticated/configured where used.
- On Windows PowerShell, empty array returns can become `$null`; path-set helpers emit through the pipeline and callers wrap with `@(...)`.
- `ai_loop.py` still carries older experimental Cursor-centric terminology and is intentionally separate from the active PowerShell loop unless a task explicitly authorizes changing it.

## Current Stage

Stable. Phase 1 A/B closed (2026-05-14): Cursor confirmed as permanent default implementer (DD-021 resolved). Proxy (DD-020) retired. `MaxIterations` default set to 5 (DD-011 resolved). `CLAUDE.md` added for Claude Code sessions and excluded from repo_map. All orchestrator queue tasks (O01–O06, DD-011) complete.

## Last Completed Task

DD-011 / housekeeping: MaxIterations default 10→5 in all driver scripts; docs and decisions updated; Phase 1 A/B closed; DD-020/DD-021 resolved.

## Next Likely Steps

1. H2N target project cleanup: D01 (compact project_summary.md) → D02 (reinstall scripts + AGENTS.md) → D03 (compact REVIEW_STATE.md, manual).
2. Use task-first for new work; use `continue_ai_loop.ps1` for interrupted loops; optionally pass `-WithWrapUp`, then periodically run `promote_session.ps1` to refresh `failures.md`.

## Notes For Future AI Sessions

- Untracked root-level scratch `.md` files are picked up by `scripts/build_repo_map.ps1` into `.ai-loop/repo_map.md`; delete them or move them under ignored paths before regenerating the map so metadata stays clean.
- Keep durable project-level context here; put per-iteration detail in `.ai-loop/implementer_summary.md`.
- Use `.ai-loop/task.md` as the task source of truth.
- Do not read or write `.ai-loop/_debug/` unless explicitly debugging raw agent output.
- Per AGENTS.md, `tasks/context_audit/` holds queued specs, not default orientation; do not treat ad-hoc material under `tasks/` or `.claude/` as durable repo state or let it pollute the Codex gate.
