# Implementer summary

## Changed files

- `scripts/record_token_usage.ps1` — `Write-CliCaptureTokenUsageIfParsed` gains optional `-DedupeId` (SHA-256 fingerprint of capture text per id; skips duplicate append after a successful write).
- `scripts/ai_loop_auto.ps1` — Codex review journaling via `Write-CliCaptureTokenUsageIfParsed` with `script_name` **`ai_loop_auto.codex_review`** and per-iteration `-DedupeId`; `Set-PassTokenReportEmittedFlag` marks when PASS path runs `show_token_report.ps1` successfully (resume + normal PASS).
- `scripts/ai_loop_task_first.ps1` — Clears marker before chaining; after successful auto, skips tail `show_token_report.ps1` when the flag exists (removes stale flag afterward).
- `docs/workflow.md`, `.ai-loop/project_summary.md` — Token journal labels, task-first single report behavior, Cursor parsing limitations.
- `tests/test_token_usage.py` — Dedupe test, `ai_loop_auto.codex_review` capture test, `ai_loop_task_first` parse smoke.

## Tests

- `python -m pytest -q` → **204 passed** (1 PytestCacheWarning on Windows cache path; environmental).

## Task-specific commands

- PowerShell AST parse: repository tests include `_parse_file_via_ast` for edited `*.ps1` (same posture as `AGENTS.md` one-liners).

## Implementation (short)

- Auto-loop Codex rows use the shared CLI capture helper with project-root hint, distinct `script_name`, and dedupe guard for accidental double-hooks in one process.
- Task-first no longer prints a second token report on a chained PASS when the child auto loop already succeeded at `show_token_report.ps1`.
- No new Cursor CLI parser: documented that only existing stable patterns are recognized (no guessing).

## Skipped

- None required; no capture-time changes in `run_cursor_agent.ps1` (no confirmed additional Cursor output shape).

## Remaining risks

- Codex/Cursor CLI output formats can change; `ConvertFrom-CliTokenUsage` and journals depend on stable patterns.
- `.tmp/pass_token_report_shown.flag` is only for task-first vs auto coordination; it is deleted at each `ai_loop_auto.ps1` start and before each chained child run.
