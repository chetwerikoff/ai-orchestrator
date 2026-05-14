# Implementer summary

## Changed files

- `scripts/run_opencode_scout.ps1` (created / aligned — SCOUT-role OpenCode stdin wrapper, parity with `run_opencode_agent.ps1` minus message)
- `scripts/run_scout_pass.ps1` (single-quoted warning for fenced-json message so PS 5.1 parses cleanly)
- `.ai-loop/task.md` (canonical **Files in scope** / **Files out of scope** headings restored for orchestrator parsers)
- `.ai-loop/project_summary.md` (Current Stage / Last Completed Task + installer line mentions `run_opencode_scout.ps1`)

## Tests

`72 passed in 1.94s`

## Implementation

- Added `scripts/run_opencode_scout.ps1`: same stdin temp-file + `opencode run` pipeline as `run_opencode_agent.ps1`, SCOUT framing on the positional message line only (`IMPLEMENTER` string absent so OpenCode scout runs are not overwritten by implementer wording).
- `run_scout_pass.ps1`: auto-substitute `run_opencode_scout.ps1` when `$CommandName` matches `run_opencode_agent`; short-output guard `< 200` bytes; `Write-ScoutWarning` for missing fenced-json block uses single-quoted text (triple backticks) so `$` escapes do not confuse the parser; short-output diagnostic uses ASCII hyphen (UTF-8 em dash in double-quoted warnings broke PS 5.1 `ParseFile` on non-BOM UTF-8).
- `scripts/install_into_project.ps1`: already ships `run_opencode_scout.ps1` beside other scripts (verified).
- `tests/test_orchestrator_validation.py`: C06 tests for scout wrapper + scout-pass markers were already present; suite green after scout_pass parse fix.

## Task-specific commands

- Python: `python -m pytest -q`
- Extra PowerShell parser check (recommended by AGENTS): `Parser::ParseFile` on `run_scout_pass.ps1` exercised via pytest `test_powershell_orchestrator_scripts_parse_cleanly`.

## Remaining risks

- Legitimate scout JSON fenced blocks shorter than 200 bytes are treated as failures (same class as aborted sessions); callers rely on scout notes being non-trivial length.
- `run_opencode_scout.ps1` synopsis still mirrors `run_opencode_agent.ps1` wording (drop-in wording); scout is primarily invoked via `run_scout_pass.ps1` substitution rather than ai_loop piping.
