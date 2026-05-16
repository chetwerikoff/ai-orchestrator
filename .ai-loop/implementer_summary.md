# Implementer summary

## Changed files

- `scripts/run_claude_reviewer.ps1` — `--workspace` + `--model` parsing; merged `stdout`/`stderr` via `2>&1`; replay to pipeline; workspace `Push-Location`; non-fatal `Write-CliCaptureTokenUsageIfParsed` on exit `0`.
- `docs/workflow.md` — Token journal subsection (`token_usage.jsonl` intent vs loop health; Cursor gaps).
- `.ai-loop/project_summary.md` — `run_claude_reviewer.ps1` + token-report bullet clarified (reviewer journaling; Cursor only when CLI format matches).
- `tests/test_token_usage.py` — AST parse test + `run_claude_reviewer` journaling harness.

## Tests

`python -m pytest -q` — **172 passed** (warning: `.pytest_cache` WinError 183 unrelated to changes).

Verification: reviewer PS1 validated by `tests/test_token_usage.py` `Parser::ParseFile` harness (`test_run_claude_reviewer_ps1_parse_clean`). Standalone nested `powershell -NoProfile ParseFile(...)` did not execute in this environment; CI/local can run as in AGENTS.md if needed.

## Implementation (3–5 lines)

Merged capture + replay matches other Claude wrappers. After success, dot-sources `record_token_usage.ps1` and records with `-Provider anthropic`, `-Iteration 0`, `ProjectRootHint`/`--workspace` resolution aligned with `run_claude_planner.ps1`.

## Skipped

- **`record_token_usage.ps1` / `run_cursor_agent.ps1`**: No repeatable in-repo Cursor CLI sample justified a new `ConvertFrom-CliTokenUsage` branch beyond existing parsers.

## Remaining risks

- If Claude reviewer output mixes usage text in an unseen shape, journaling still no-ops silently (existing parser contract).
- `2>&1` without `cmd /c` may differ from planner’s NativeCommand workaround in edge shells; aligns with task-specified merged capture approach.
