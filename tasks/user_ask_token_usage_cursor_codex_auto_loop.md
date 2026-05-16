# User ASK

## Goal

Make token usage reports populate reliably for the normal task-first / auto-loop path when Cursor and Codex expose real parseable usage data.

Specifically, a successful `ai_loop_task_first.ps1` / `ai_loop_auto.ps1` PASS should append token records for Cursor and Codex when their CLI output contains usage, and should not print duplicate `No token usage records found` messages from back-to-back report calls.

## Affected files (your best guess - planner will verify)

- `scripts/ai_loop_auto.ps1`
- `scripts/ai_loop_task_first.ps1`
- `scripts/run_cursor_agent.ps1`
- `scripts/record_token_usage.ps1`
- `scripts/show_token_report.ps1`
- `tests/test_token_usage.py`
- `tests/test_orchestrator_validation.py`
- `docs/workflow.md`
- `.ai-loop/project_summary.md`

## Out-of-scope (explicit boundaries)

- `docs/archive/**`
- `.ai-loop/_debug/**`
- `ai_loop.py`
- Changing Codex review verdict semantics
- Changing Cursor implementer behavior
- Making token usage recording fatal
- Inventing token counts, estimating from text length, or storing account identifiers/secrets
- Running implementers, live Codex/Cursor CLIs, git commit, or git push as part of tests

## Proposed approach (optional)

Fix Codex first:

1. In the normal auto-loop path, `ai_loop_auto.ps1` calls `codex exec` directly through `Run-CodexReview`, not through `run_codex_reviewer.ps1`.
2. Add or strengthen the token-recording hook immediately after `Run-CodexReview` captures joined Codex stdout/stderr, using `Write-CliCaptureTokenUsageIfParsed`.
3. Pass the active iteration number, provider `codex`, clear script/source name, model when known, and project root hint.
4. Avoid double-recording the same usage block for one Codex call.

Fix Cursor second:

1. `run_cursor_agent.ps1` already calls `Write-CliCaptureTokenUsageIfParsed`, but it can only record when Cursor CLI output matches a supported parser format.
2. Extend `ConvertFrom-CliTokenUsage` only for stable real Cursor usage strings if they exist.
3. If Cursor CLI does not emit token usage in the current mode, document that limitation instead of fabricating values.

Fix report duplication:

1. `ai_loop_auto.ps1` prints a token report on PASS.
2. `ai_loop_task_first.ps1` also prints a token report after auto-loop returns.
3. Avoid printing the same empty/non-empty report twice in a normal task-first PASS path.

## Constraints / context the planner may not know

- `show_token_report.ps1` reads `.ai-loop/token_usage.jsonl`; if absent or empty, it prints `No token usage records found.`
- Existing token parsing is intentionally conservative. It should recognize explicit provider usage output only.
- Token recording must remain non-blocking.
- Preserve backward compatibility with existing `.ai-loop/token_usage.jsonl` records and report output sections.
