# Task: Token usage foundation ÔÇö JSONL record + console report

## Project context
- `AGENTS.md`
- `.ai-loop/task.md`
- `.ai-loop/project_summary.md`

## Goal
Establish a minimal token-usage tracking foundation: a PowerShell helper (`record_token_usage.ps1`) that appends structured JSONL records to `.ai-loop/token_usage.jsonl`, a report script (`show_token_report.ps1`) that reads those records and prints a formatted console summary, and a non-fatal call to the report at the end of `ai_loop_auto.ps1`. No CLI output parsing in this task ÔÇö confidence will be `unknown` for records written here. Subsequent tasks will wire in real token counts from each provider wrapper and add config-based limit display.

## Scope
Allowed:
- Create `scripts/record_token_usage.ps1` and `scripts/show_token_report.ps1`
- Modify `scripts/ai_loop_auto.ps1` to call `show_token_report.ps1` non-fatally at end of each full pass
- Modify `.gitignore` to exclude `.ai-loop/token_usage.jsonl` and `.ai-loop/token_usage_summary.md`
- Add `tests/test_token_usage.py` with PowerShell parse checks and subprocess integration tests
- Update `.ai-loop/project_summary.md` to record Task 1 completion

Not allowed:
- Parsing token data from any CLI wrapper output (Task 2)
- `config/token_limits.yaml` or limit enforcement (Task 3)
- Writing `.ai-loop/token_usage_summary.md` or `.ai-loop/reports/` (later tasks)
- Modifying `SafeAddPaths` in any orchestrator script ÔÇö `token_usage.jsonl` is runtime-only and stays gitignored
- Touching `ai_loop_task_first.ps1`, `ai_loop_plan.ps1`, or any `run_*.ps1` wrapper

## Files in scope
- `scripts/record_token_usage.ps1` (new)
- `scripts/show_token_report.ps1` (new)
- `scripts/ai_loop_auto.ps1`
- `.gitignore`
- `tests/test_token_usage.py` (new)
- `.ai-loop/project_summary.md`

## Files out of scope
- `docs/archive/**`
- `.ai-loop/_debug/**`
- `ai_loop.py`
- `scripts/ai_loop_task_first.ps1`
- `scripts/ai_loop_plan.ps1`
- `scripts/run_claude_planner.ps1`
- `scripts/run_codex_reviewer.ps1`
- `scripts/run_opencode_agent.ps1`
- `scripts/run_cursor_agent.ps1`
- `scripts/run_opencode_scout.ps1`
- `scripts/install_into_project.ps1`
- `scripts/continue_ai_loop.ps1`

## Required behavior

1. **`scripts/record_token_usage.ps1`** defines one function `Write-TokenUsageRecord`. Parameters (all optional, keyword-named):
   - `TaskName` (string, default `""`)
   - `ScriptName` (string, default `""`)
   - `Iteration` (int, default `0`)
   - `Provider` (string, default `"unknown"`)
   - `Model` (string, default `""`)
   - `InputTokens` (nullable int, default `$null`)
   - `OutputTokens` (nullable int, default `$null`)
   - `TotalTokens` (nullable int, default `$null`)
   - `EstimatedCostUsd` (nullable double, default `$null`)
   - `Confidence` (string, default `"unknown"` ÔÇö allowed values: `exact`, `estimated`, `unknown`)
   - `Source` (string, default `"unknown"`)

   Builds a hashtable with snake_case keys, adds `timestamp` (ISO-8601 UTC), converts to a single-line JSON string via `ConvertTo-Json -Compress -Depth 3`, and appends it to `.ai-loop/token_usage.jsonl` resolved as `Join-Path (Split-Path $PSScriptRoot -Parent) '.ai-loop\token_usage.jsonl'`. Creates the file if absent. On any write error, emits `Write-Warning` and returns without throwing.

2. **`scripts/show_token_report.ps1`** resolves `.ai-loop/token_usage.jsonl` via `Join-Path (Split-Path $PSScriptRoot -Parent) '.ai-loop\token_usage.jsonl'`. If absent or empty, exits silently (exit code 0). Reads all lines, skips blank or malformed JSON with a `Write-Warning`. Groups valid records by `task_name`. For each group, prints to stdout:
   ```
   ==============================
   TOKEN USAGE REPORT
   ==============================
   Task: <task_name>
     [<timestamp>]  Script: <script_name>  Iter: <iteration>
     Provider/model: <provider>/<model>
     Tokens -- in: <InputTokens|?>  out: <OutputTokens|?>  total: <TotalTokens|?>
     Confidence: <confidence>   Source: <source>
   ...
   --- Totals (known records only) ---
     in: N   out: N   total: N
   ==============================
   ```
   Null/missing numeric values render as `?`. Non-fatal on any error.

3. **`scripts/ai_loop_auto.ps1`**: immediately before the script's final successful exit (after the final test gate and safe-staging), add a non-fatal call:
   ```powershell
   try { & "$PSScriptRoot\show_token_report.ps1" } catch { Write-Warning "Token report failed: $_" }
   ```
   Must not alter the script's exit code. Do not add the call inside error/failure paths.

4. **`.gitignore`**: add entries `.ai-loop/token_usage.jsonl` and `.ai-loop/token_usage_summary.md` (pre-emptive exclusion for Task 2). Place them near the existing `.ai-loop/` gitignore block.

5. No records are written automatically by `ai_loop_auto.ps1` in this task. The console report simply displays whatever is already in the JSONL (empty on first run). Record-write integration is Task 2.

## Tests
Add `tests/test_token_usage.py`:

- **Parse check** `scripts/record_token_usage.ps1` via `Parser::ParseFile` (same pattern as existing tests in `test_orchestrator_validation.py`).
- **Parse check** `scripts/show_token_report.ps1` the same way.
- **Subprocess integration for `Write-TokenUsageRecord`**: invoke from the repo root (the project root, resolved relative to the test file) via:
  ```
  powershell -NoProfile -Command ". scripts\record_token_usage.ps1; Write-TokenUsageRecord -TaskName 'pytest_task' -Provider 'anthropic' -Confidence 'unknown'"
  ```
  Before running, delete `.ai-loop/token_usage.jsonl` if it exists (cleanup). After running, assert exit code 0; read `.ai-loop/token_usage.jsonl`; assert it contains exactly one line; assert it parses as JSON with `task_name == "pytest_task"`. Restore (delete) the file in teardown.
- **Subprocess integration for `show_token_report.ps1` with no JSONL**: ensure `.ai-loop/token_usage.jsonl` does not exist, invoke `powershell -NoProfile -File scripts\show_token_report.ps1`; assert exit code 0 and no exception in stderr.

Run: `python -m pytest -q tests/test_token_usage.py`

## Verification
```powershell
powershell -NoProfile -Command "[void][System.Management.Automation.Language.Parser]::ParseFile('scripts\record_token_usage.ps1', [ref]`$null, [ref]`$null)"
powershell -NoProfile -Command "[void][System.Management.Automation.Language.Parser]::ParseFile('scripts\show_token_report.ps1', [ref]`$null, [ref]`$null)"
```
```
python -m pytest -q tests/test_token_usage.py
python -m pytest -q
```

## Implementer summary requirements
1. List each new file created and each modified file with a one-line description of the change.
2. Test result: pass/fail count; note any skipped tests and why.
3. Confirm `Write-TokenUsageRecord` is non-fatal on write error and `show_token_report.ps1` exits 0 on missing JSONL.
4. Note any JSONL schema fields omitted and the reason.
5. List one to three risks for Task 2 (CLI output parsing ÔÇö format volatility, stderr vs stdout capture, etc.).

## Project summary update
Add to "Current Stage": token-usage tracking foundation complete (Task 1 of 3); `scripts/record_token_usage.ps1` + `scripts/show_token_report.ps1` created; `ai_loop_auto.ps1` displays console report at end of each pass; `.ai-loop/token_usage.jsonl` gitignored; real token parsing and record writes deferred to Task 2; config/limits to Task 3.

## Output hygiene
- Do not duplicate task content into `project_summary.md`.
- Do not write debug output to `.ai-loop/_debug/`.
- Do not commit; the orchestrator handles commit/push.
- Do not write to `docs/archive/`.

## Important

**Architect note ÔÇö proposal scope reduced to Task 1 of 3:** The user's proposal covers a complete token tracking system: multi-source parsing, confidence levels, config-based limit enforcement, a reports directory, and a persistent summary file. That is 300ÔÇô500+ lines across 6ÔÇô8 files ÔÇö well beyond the ~80-line policy. This task covers only the foundation: schema, append helper, report printer, and a display call in `ai_loop_auto.ps1`. CLI parsing, config limits, and any tracked summary file are sequenced below.

**Architect note ÔÇö no automatic stub records written in Task 1:** Writing `confidence=unknown` records for every Codex invocation adds JSONL noise with zero informational content. The report call is wired in so the display path exists; Task 2 adds record-write calls once real token data is parseable from at least one provider.

**Architect note ÔÇö `config/token_limits.yaml` deferred to Task 3:** Introducing a new `config/` directory requires a decision on whether it enters `SafeAddPaths`. That evaluation belongs after real usage numbers exist. Task 3 will propose the config schema and SafeAddPaths update together.

**Architect note ÔÇö `token_usage.jsonl` is gitignored (runtime output):** The project convention is that runtime files (codex_review.md, test logs, implementer_result.md) are gitignored. The JSONL file follows the same convention. A human-readable tracked summary (`token_usage_summary.md`) may be added in Task 2 with a SafeAddPaths update if it proves durable enough to commit.

**Path resolution:** Both new scripts must resolve `.ai-loop/` from `Split-Path $PSScriptRoot -Parent` (the repo root), not `$PWD`. This is consistent with other scripts in `scripts/`. Because path resolution is fixed to `$PSScriptRoot`, integration tests must run from the real repo root (not a temp shadow directory) and clean up the real `.ai-loop/token_usage.jsonl` before and after. Tests are responsible for teardown so the file does not persist between test runs.

**JSON field naming:** Use snake_case keys in the JSONL output (`task_name`, `script_name`, `input_tokens`, etc.). Build the hashtable explicitly rather than relying on PowerShell object serialisation so field names are deterministic.

**`Parser::ParseFile` test compatibility:** The existing test harness uses `[System.Management.Automation.Language.Parser]::ParseFile` with two `[ref]` params. Match that exact pattern in the new tests; do not introduce a different parse-check approach.

**Series plan:**
- **Task 1 (this):** Foundation ÔÇö JSONL schema, `Write-TokenUsageRecord`, `show_token_report.ps1`, non-fatal display call in `ai_loop_auto.ps1`, gitignore, tests.
- **Task 2:** Provider parsing ÔÇö capture token counts from `claude --print` stdout in `run_claude_planner.ps1`; from `codex exec` stdout in `run_codex_reviewer.ps1`; write records with `confidence=exact` or `estimated`; add `Write-TokenUsageRecord` calls in `ai_loop_auto.ps1` per iteration.
- **Task 3:** Config + limits ÔÇö `config/token_limits.yaml`; limit display in report; SafeAddPaths update if summary becomes tracked; optional tracked `.ai-loop/token_usage_summary.md`.

## Order
1
