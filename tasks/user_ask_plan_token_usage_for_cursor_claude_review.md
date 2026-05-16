# User ASK

## Goal

Fix token usage reporting for planning runs where Cursor is used as planner and Claude is used as task reviewer, so a successful `ai_loop_plan.ps1` run does not misleadingly end with `No token usage records found` when parseable usage data is available.

The workflow should record Claude reviewer token usage through the existing token journal helper, and should only record Cursor planner usage when Cursor CLI output exposes a real parseable usage format. Do not invent token counts.

## Affected files (your best guess - planner will verify)

- `scripts/run_claude_reviewer.ps1`
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
- Changing planner/reviewer selection behavior
- Making token usage recording fatal
- Inventing token counts, estimating usage from text length, or storing account identifiers/secrets
- Running implementers, Codex implementation review, git commit, or git push

## Proposed approach (optional)

First, add token recording to `scripts/run_claude_reviewer.ps1` using the same pattern already used by other wrappers:

1. Capture combined Claude CLI output.
2. Preserve current stdout behavior.
3. On successful exit, dot-source `scripts/record_token_usage.ps1`.
4. Call `Write-CliCaptureTokenUsageIfParsed` with:
   - `ScriptName "run_claude_reviewer.ps1"`;
   - `Provider "claude"`;
   - model from `--model` when supplied;
   - `ProjectRootHint` from `--workspace` when supplied, otherwise current directory.
5. Keep token recording warnings non-fatal.

Second, evaluate Cursor planner usage:

1. Confirm what `run_cursor_agent.ps1` currently captures.
2. If real Cursor CLI output contains token usage in a stable format, extend `ConvertFrom-CliTokenUsage` narrowly for that exact format and add representative tests.
3. If Cursor CLI output does not expose token usage, leave Cursor unrecorded and document that `No token usage records found` can still be correct when no parseable provider usage is emitted.

Third, keep `ai_loop_plan.ps1` behavior unchanged except for the token journal data produced by wrappers. It should continue to call `show_token_report.ps1` at the end and should not become responsible for parsing child process usage itself.

## Constraints / context the planner may not know

- `No token usage records found` comes from `scripts/show_token_report.ps1` reading an absent or empty `.ai-loop/token_usage.jsonl`.
- `scripts/run_cursor_agent.ps1` already calls `Write-CliCaptureTokenUsageIfParsed`, but only records when captured output matches supported parser formats.
- `scripts/run_claude_reviewer.ps1` currently does not call the token usage helper, so Claude reviewer usage cannot be recorded even if its output is parseable.
- Token usage failures must remain non-blocking for planner/reviewer runs.
- Preserve backward compatibility with existing `.ai-loop/token_usage.jsonl` records.
- Tests should use representative captured output strings or stubbed wrapper behavior; do not require live Cursor or Claude CLI access.
- Add or update docs only enough to clarify that token reports reflect parseable provider output, not planner success or failure.
- Prefer the smallest implementation: wrapper hook for Claude reviewer first, parser extension for Cursor only if backed by real output samples.
