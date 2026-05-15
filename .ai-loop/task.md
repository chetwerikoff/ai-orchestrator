# Task: Token usage step 2 ÔÇö real parsing and auto-recording

## Project context
- `AGENTS.md`
- `.ai-loop/task.md`
- `.ai-loop/project_summary.md`
- `.ai-loop/implementer_summary.md` (if iteration > 1)

## Goal
Implement real token-count parsing and automatic JSONL recording for the token usage system. The foundation (recorder, report script, gitignore, tests) is in place from step 1. This task adds: a `ConvertFrom-CliTokenUsage` PowerShell function that extracts token counts from CLI output text, optional `source` and `quality` fields on the JSONL schema, automatic recording of Codex review token usage inside `ai_loop_auto.ps1`, and an enhanced `show_token_report.ps1` that aggregates by model and by iteration and also writes `.ai-loop/token_usage_summary.md`. All new behavior is non-blocking.

## Scope
Allowed:
- Adding `ConvertFrom-CliTokenUsage` to `scripts/record_token_usage.ps1`
- Adding optional `-Source` and `-Quality` parameters to `Write-TokenUsageRecord`
- Parsing Codex output in `scripts/ai_loop_auto.ps1` and calling `Write-TokenUsageRecord`
- Extending `scripts/show_token_report.ps1` for by-model / by-iteration aggregation and writing `.ai-loop/token_usage_summary.md`
- Adding `.ai-loop/token_usage_summary.md` to `.gitignore`
- Updating `tests/test_token_usage.py`
- Updating `.ai-loop/project_summary.md`

Not allowed:
- Touching implementer wrapper scripts (`run_cursor_agent.ps1`, `run_opencode_agent.ps1`, `run_opencode_scout.ps1`, `run_claude_planner.ps1`, `run_codex_reviewer.ps1`) ÔÇö deferred to step 3
- Adding `config/token_limits.yaml` or limits display ÔÇö deferred to step 3
- Adding `.ai-loop/reports/` or timestamped report exports ÔÇö deferred to step 3
- Modifying `ai_loop_plan.ps1`, `ai_loop_task_first.ps1`, or `continue_ai_loop.ps1`
- Editing `ai_loop.py`
- Writing to `docs/archive/**`

## Files in scope
- `scripts/record_token_usage.ps1`
- `scripts/show_token_report.ps1`
- `scripts/ai_loop_auto.ps1`
- `tests/test_token_usage.py`
- `.gitignore`
- `.ai-loop/project_summary.md`

## Files out of scope
- `docs/archive/**`
- `.ai-loop/_debug/**`
- `ai_loop.py`
- `scripts/run_cursor_agent.ps1`
- `scripts/run_opencode_agent.ps1`
- `scripts/run_opencode_scout.ps1`
- `scripts/run_claude_planner.ps1`
- `scripts/run_codex_reviewer.ps1`
- `scripts/ai_loop_plan.ps1`
- `scripts/ai_loop_task_first.ps1`
- `scripts/continue_ai_loop.ps1`

## Required behavior

1. **Add `ConvertFrom-CliTokenUsage` to `record_token_usage.ps1`**:
   - Accepts a single string parameter (raw text to parse).
   - Tries patterns in order, returning on first match:
     a. JSON key `"input_tokens"` + `"output_tokens"` (Claude API) ÔÇö source `api_response`, quality `exact`
     b. JSON key `"prompt_tokens"` + `"completion_tokens"` (OpenAI/Codex API) ÔÇö source `api_response`, quality `exact`
     c. Plain-text lines `Input tokens: N` / `Output tokens: N` (Claude CLI text) ÔÇö source `cli_log`, quality `exact`
   - Returns a hashtable `@{ InputTokens = N; OutputTokens = N; TotalTokens = N; Source = "..."; Quality = "exact" }` on match; `$null` when no pattern matches.
   - Pure function, no side effects, no I/O.

2. **Add `-Source` and `-Quality` optional parameters to `Write-TokenUsageRecord`**:
   - Both default to `"unknown"` when omitted so all existing call sites continue to work without changes.
   - Write both fields into the JSONL record on every call.

3. **Auto-record Codex token usage in `ai_loop_auto.ps1`**:
   - After each Codex review invocation (initial review and each fix-loop iteration), retrieve the Codex text that was already captured (stdout variable or the `codex_review.md` file ÔÇö implementer must check the existing capture pattern).
   - Call `ConvertFrom-CliTokenUsage` on that text.
   - If a non-null result is returned, call `Write-TokenUsageRecord` with provider `"codex"`, model `"codex"` (or whatever model string is available), the current iteration number, and the parsed `InputTokens`, `OutputTokens`, `TotalTokens`, `Source`, `Quality`.
   - Entire block must be wrapped in `try/catch`; failures emit a warning and do not affect exit codes.

4. **Enhance `show_token_report.ps1`**:
   - Read `.ai-loop/token_usage.jsonl`; skip unparseable lines silently.
   - If the file is missing or every line fails to parse, emit `"No token usage records found."` and exit 0.
   - Derive a task name from the `task` field of the most recent record (or `"unknown"` if absent).
   - Output sections:
     - Header: task name, script name (from most recent record's `script` field).
     - **Total**: summed input / output / total tokens across all records.
     - **By model**: one line per distinct `model` value, summed tokens.
     - **By iteration**: for each distinct `iteration` value (ascending), show model, input, output, total.
   - After writing to console (`Write-Host`), overwrite `.ai-loop/token_usage_summary.md` with the same text (non-fatal; warn on error).

5. **Update `.gitignore`**:
   - Add `.ai-loop/token_usage_summary.md` on a new line near `.ai-loop/token_usage.jsonl`.

6. **Non-blocking contract**: every new code path in `ai_loop_auto.ps1` and `show_token_report.ps1` must be guarded with `try/catch` or `-ErrorAction SilentlyContinue` such that failures produce only a warning and never change the script's exit code.

## Tests
Add or extend `tests/test_token_usage.py` using subprocess calls (matching existing test pattern):

- `test_convert_claude_api_format`: pass JSON with `input_tokens`/`output_tokens`; assert correct token values, `source == "api_response"`, `quality == "exact"`.
- `test_convert_openai_api_format`: pass JSON with `prompt_tokens`/`completion_tokens`; assert correct token values and source.
- `test_convert_cli_log_format`: pass plain text `Input tokens: 42\nOutput tokens: 18`; assert `InputTokens == 42`, `OutputTokens == 18`, `source == "cli_log"`.
- `test_convert_no_match_returns_null`: pass unrecognized text; assert `$null` return.
- `test_write_record_default_source_quality`: call `Write-TokenUsageRecord` without `-Source`/`-Quality`; read JSONL; assert record has `"source": "unknown"` and `"quality": "unknown"`.
- `test_write_record_explicit_source_quality`: call with `-Source api_response -Quality exact`; assert fields in written record.
- `test_show_report_by_model`: write two JSONL records with different `model` values; run `show_token_report.ps1`; assert stdout contains both model names and their respective summed tokens.
- `test_show_report_empty`: run `show_token_report.ps1` against missing JSONL; assert exit code 0 and "No token usage records found." in stdout.
- `test_show_report_writes_summary_md`: write one JSONL record; run `show_token_report.ps1`; assert `.ai-loop/token_usage_summary.md` exists and contains "Total".
- `test_codex_auto_record_chain`: via a PowerShell subprocess that dot-sources `record_token_usage.ps1`, call `ConvertFrom-CliTokenUsage` with OpenAI-style JSON (simulating Codex output), pipe the result into `Write-TokenUsageRecord` with `provider="codex"`, then read back the JSONL and assert a record with `source == "api_response"` and `provider == "codex"` was written. This exercises the full chain used by the `ai_loop_auto.ps1` hook without requiring a full orchestrator run.

Run: `python -m pytest -q`

## Verification
```
python -m pytest -q
powershell -NoProfile -Command "[void][System.Management.Automation.Language.Parser]::ParseFile('scripts\record_token_usage.ps1', [ref]$null, [ref]$null)"
powershell -NoProfile -Command "[void][System.Management.Automation.Language.Parser]::ParseFile('scripts\show_token_report.ps1', [ref]$null, [ref]$null)"
powershell -NoProfile -Command "[void][System.Management.Automation.Language.Parser]::ParseFile('scripts\ai_loop_auto.ps1', [ref]$null, [ref]$null)"
```

## Implementer summary requirements
1. List each changed file with a one-line description of the change made.
2. Report test count and pass/fail outcome.
3. Describe which token-count patterns are now parsed and confirm the Codex capture point used in `ai_loop_auto.ps1`.
4. Note any specified behavior that could not be implemented as written and why.
5. List 1ÔÇô3 remaining risks (e.g., Codex output format change breaking the pattern, `show_token_report.ps1` summary write failing silently).

## Project summary update
Update "Current Stage": Token usage step 2 complete ÔÇö `ConvertFrom-CliTokenUsage` (three patterns: Claude API JSON, OpenAI API JSON, Claude CLI text), `source`/`quality` fields on JSONL schema, Codex auto-recording hooked in `ai_loop_auto.ps1`, `show_token_report.ps1` enhanced with by-model / by-iteration aggregation and `token_usage_summary.md` write. Step 3 (limits config via `config/token_limits.yaml`, per-wrapper parsing, timestamped report exports) remains.

Update "Last Completed Task": Token usage step 2 ÔÇö real parsing and auto-recording.

## Output hygiene
- Do not duplicate task content into the implementer summary.
- Do not write to `.ai-loop/_debug/` except via existing orchestrator hooks.
- Do not commit ÔÇö the orchestrator handles git.
- Do not write to `docs/archive/`.

## Important
- **Architect note**: The user's proposal spans all three steps (parsing, per-wrapper recording, limits config, timestamped report exports). This task covers step 2 only. Hooking all four wrapper scripts in one pass would touch six files and exceed the ~80-line policy; Codex output is already captured by `ai_loop_auto.ps1`, making it the lowest-risk auto-record target for this iteration. Per-wrapper extraction moves to step 3.
- **Architect note**: `config/token_limits.yaml` and the limits display section (daily/weekly/monthly %) are deferred to step 3 as specified by `project_summary.md` ("config and limits to step 3"). They are not included here.
- **Architect note**: `.ai-loop/reports/token_usage_<timestamp>.md` is also deferred to step 3; it introduces a new gitignored directory and timestamp-keyed filenames that add complexity without contributing to the core parsing goal of this step.
- Reviewer issue `[logic]` accepted: `.ai-loop/project_summary.md` added to `## Files in scope`.
- Reviewer issue `[missing]` accepted: `test_codex_auto_record_chain` added to cover the auto-recording chain without a full orchestrator harness. A full subprocess test of `ai_loop_auto.ps1` is intentionally avoided ÔÇö it requires a complete orchestrator setup. The chain test (dot-source ÔåÆ parse ÔåÆ write ÔåÆ verify JSONL) is the appropriate unit boundary.
- **Assumption**: The Codex invocation in `ai_loop_auto.ps1` either stores stdout in a variable before writing it to `codex_review.md`, or writes the file and then reads it back. The implementer must inspect the current capture pattern and apply `ConvertFrom-CliTokenUsage` to whichever text is available ÔÇö variable preferred, file fallback acceptable.
- **Assumption**: Existing calls to `Write-TokenUsageRecord` inside `ai_loop_auto.ps1` (the step-1 placeholder hook) pass no `-Source`/`-Quality`; they will silently default to `"unknown"` / `"unknown"`, which is correct.
- `ConvertFrom-CliTokenUsage` must be defined in `record_token_usage.ps1` (dot-sourced by `ai_loop_auto.ps1`), not in a separate file.
- Tests call PowerShell functions via subprocess; do not reimplement PowerShell parsing logic in Python.
- The `$PSScriptRoot` fixup in `record_token_usage.ps1` (noted in project summary for `[System.IO.Path]::Combine`) must be preserved; do not regress it.
