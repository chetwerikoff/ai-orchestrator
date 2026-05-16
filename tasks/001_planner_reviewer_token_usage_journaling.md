# Task: Planner reviewer token usage journaling

## Project context

Implementers must read: `AGENTS.md`, `.ai-loop/task.md`, `.ai-loop/project_summary.md`, `.ai-loop/repo_map.md`. On iteration 2+, also `.ai-loop/implementer_summary.md` and `.ai-loop/failures.md`.

## Goal

Ensure planning workflows that use Cursor as the planner wrapper and Claude (`run_claude_reviewer.ps1`) as the optional task reviewer leave parseable token usage in `.ai-loop/token_usage.jsonl` when the underlying CLIs emit formats already understood by `ConvertFrom-CliTokenUsage`, so a successful `scripts/ai_loop_plan.ps1` run does not finish with `No token usage records found` solely because the Claude reviewer pass was never journaled. Cursor planner usage must still be recorded only when captured stdout/stderr matches a supported, explicit parser caseÔÇönever inferred or fabricated.

## Scope

**Allowed:**

- Extend `scripts/run_claude_reviewer.ps1` to capture merged Claude CLI stream output, preserve existing stdout behavior for callers, and on successful exit dot-source `scripts/record_token_usage.ps1` and call `Write-CliCaptureTokenUsageIfParsed` in a non-fatal try/catch with warning text consistent with other wrappers.
- Parse forwarded `--workspace` and `--model` flags for journal metadata (`ProjectRootHint`, model), mirroring the resolution pattern used in `scripts/run_claude_planner.ps1` (absolute hint when the workspace path exists; otherwise fall back to current location).
- Inspect real or fixture-backed Cursor CLI capture strings; if and only if a stable, repeatable usage pattern is confirmed, extend `ConvertFrom-CliTokenUsage` in `scripts/record_token_usage.ps1` narrowly and add representative tests.
- Update `tests/test_token_usage.py` with stubbed or string-based coverage (no live Cursor or Claude).
- Minimal clarification in `docs/workflow.md` and durable note in `.ai-loop/project_summary.md` that the report reflects parseable provider output, not loop success.

**Not allowed:**

- Changing planner vs reviewer selection, invocation wiring in `scripts/ai_loop_plan.ps1`, or making token recording failures fatal.
- Inventing token counts, estimating from text length, or storing secrets/account identifiers.
- Git commit, push, implementer/Codex implementation-review runs, or edits under `docs/archive/**`, `.ai-loop/_debug/**`, or `ai_loop.py`.

## Files in scope

- `scripts/run_claude_reviewer.ps1`
- `scripts/record_token_usage.ps1` ÔÇö only if a verified Cursor output format warrants a new parser branch
- `scripts/run_cursor_agent.ps1` ÔÇö only if the Cursor investigation shows parser support is required without changing recording semantics
- `tests/test_token_usage.py`
- `docs/workflow.md`
- `.ai-loop/project_summary.md`

## Files out of scope

- `docs/archive/**`
- `.ai-loop/_debug/**`
- `ai_loop.py`
- `scripts/ai_loop_plan.ps1` ÔÇö no behavioral changes beyond whatever journal entries child wrappers emit
- `scripts/show_token_report.ps1` ÔÇö unless an empty-state message bug is proven after reviewer journaling (default: leave unchanged)
- `tests/test_orchestrator_validation.py`
- `tasks/**`
- `templates/**`, `scripts/install_into_project.ps1` ÔÇö not required for this fix

## Required behavior

1. **`run_claude_reviewer.ps1`:** Refactor the Claude invocation so combined stdout/stderr is captured into an array/list (e.g. `2>&1`), replay each line/object to the pipeline with `Write-Output` so downstream behavior matches todayÔÇÖs visible output, and preserve exit code semantics.
2. **Token journal:** After the reviewer process exits with code `0`, dot-source `record_token_usage.ps1` from this scriptÔÇÖs resolved directory (same `$PSScriptRoot` fallback pattern as `run_claude_planner.ps1` / `run_cursor_agent.ps1`), then call `Write-CliCaptureTokenUsageIfParsed` with `-ScriptName "run_claude_reviewer.ps1"`, `-Provider "anthropic"`, `-Iteration 0`, the effective model string after `--model` parsing (including default), and `-ProjectRootHint` derived from `--workspace` when valid, else current directoryÔÇösame rules as `run_claude_planner.ps1`. Wrap in try/catch; on failure emit a non-blocking warning (do not alter reviewer exit code).
3. **Argument parsing:** Add explicit `--workspace` handling so `$args` pairs are consumed correctly (today only `--model` is recognized; `ai_loop_plan.ps1` passes `--workspace` before `--model`).
4. **Cursor planner:** Read `run_cursor_agent.ps1` and existing `ConvertFrom-CliTokenUsage` branches. If recorded captures or user-supplied samples in-repo prove a stable Cursor-specific usage format, add the smallest parser extension plus tests; otherwise document that Cursor may contribute no rows when the CLI emits no parseable usage block.
5. **Compatibility:** New JSONL rows must remain backward compatible with existing consumers (`show_token_report.ps1`, limits YAML if present).

## Tests

- Extend `tests/test_token_usage.py` to cover Claude reviewer journaling: e.g. PowerShell dot-source/harness invoking the wrapper against stubbed `claude` behavior or representative captured text that exercises `Write-CliCaptureTokenUsageIfParsed` / `ConvertFrom-CliTokenUsage`, consistent with existing patterns in that file.
- If the Cursor parser is extended, add focused parse tests with the exact sample strings that justified the branch.
- Run full suite: `python -m pytest -q`.

## Verification

- `python -m pytest -q`
- `powershell -NoProfile -Command "[void][System.Management.Automation.Language.Parser]::ParseFile('scripts\run_claude_reviewer.ps1', [ref]$null, [ref]$null)"`
- If `scripts/record_token_usage.ps1` or `scripts/run_cursor_agent.ps1` is edited, repeat `Parser::ParseFile` for those paths per `AGENTS.md`.

## Implementer summary requirements

- List changed files briefly.
- State pytest result as pass count/summary only.
- Summarize implemented work in 3ÔÇô5 lines.
- Note skipped items with reason (e.g. Cursor parser not addedÔÇöno verified format).
- List 1ÔÇô3 remaining risks.

## Project summary update

Update the token-usage bullet under **Current Architecture** / **Current Stage** (whichever matches existing structure) to state that `run_claude_reviewer.ps1` participates in the JSONL journal when Claude output is parseable, and that Cursor planner rows appear only when the Cursor CLI exposes a supported usage formatÔÇöotherwise an empty report line remains legitimate.

## Output hygiene

- Do not duplicate this task body into `.ai-loop/implementer_summary.md`.
- Do not write to `.ai-loop/_debug/**`.
- Do not create a git commit unless a separate human request explicitly asks for it.
- Do not write or edit anything under `docs/archive/**`.

## Important

- Assumption: Claude reviewer stdout/stderr for `claude --print` matches formats already handled for other Claude CLI wrappers in this repo once merged capture is passed to `ConvertFrom-CliTokenUsage`; if not, extend parsing in `record_token_usage.ps1` with the same ÔÇ£representative capture onlyÔÇØ rule as Cursor.
- `ai_loop_plan.ps1` already passes `--workspace` to the reviewer wrapper; correct pairing is required for accurate `ProjectRootHint`.
- Architect note: USER ASK proposed `-Provider "claude"`; this task standardizes on `-Provider "anthropic"` to match `run_claude_planner.ps1` and existing journal conventionsÔÇö`ScriptName` distinguishes reviewer vs planner rows.
- Architect note: USER ASK listed `tests/test_orchestrator_validation.py`; coverage belongs in `tests/test_token_usage.py` unless a planner subprocess regression is demonstratedÔÇökeeps the change set within the ~80-line guideline.
- Architect note: USER ASK listed `scripts/show_token_report.ps1`; empty-state messaging is acceptable once reviewer usage is recordedÔÇöthe primary fix is journaling the missing provider pass, not redesigning the report script.

## Order

1
