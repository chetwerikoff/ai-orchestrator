# Implementer summary

## Changed files (why)

- `scripts/record_token_usage.ps1` — `Get-TaskHeadingForJournal`, `Write-CliCaptureTokenUsageIfParsed` for shared non-fatal wrapper recording.
- `scripts/show_token_report.ps1` — optional `-ExportReport` / `-LimitsYamlPath`; Limits section (rolling UTC windows; % only for numeric budgets); timestamped `.ai-loop/reports/token_usage_*.md`.
- `config/token_limits.yaml` — committed example optional budgets (`unknown` / `not_applicable` / numeric).
- `scripts/run_claude_planner.ps1`, `scripts/run_codex_reviewer.ps1`, `scripts/run_cursor_agent.ps1`, `scripts/run_opencode_agent.ps1`, `scripts/run_opencode_scout.ps1` — capture CLI output, merge stderr where needed, record when `ConvertFrom-CliTokenUsage` matches.
- `scripts/ai_loop_plan.ps1`, `scripts/ai_loop_task_first.ps1` — on success invoke `show_token_report.ps1` like `ai_loop_auto.ps1`.
- `scripts/install_into_project.ps1` — copy `record_token_usage.ps1`, `show_token_report.ps1`, install default `config/token_limits.yaml` when absent.
- `.gitignore` — `.ai-loop/reports/`, `tests/.token_limits_scratch/`.
- `tests/test_token_usage.py`, `tests/test_orchestrator_validation.py` — coverage for limits/export/malformed JSONL/wrapper parse; relax codex/claude invariant tests for `2>&1` capture.
- `.ai-loop/project_summary.md` — token usage step 3 noted in Current Stage.

## Tests

- `python -m pytest tests/test_token_usage.py -q` → **28 passed**
- `python -m pytest tests -q` → **170 passed** (after validation test updates)

## Wrapper recording

| Wrapper | Records when | Still unknown if |
|--------|----------------|------------------|
| `run_claude_planner.ps1` | Claude stdout/stderr matches known parsers (e.g. API JSON, `Input tokens:` / `Output tokens:`) | No usage lines in output |
| `run_codex_reviewer.ps1` | Codex output matches JSON or `tokens used` summary | Total-only or missing lines |
| `run_cursor_agent.ps1` | Same parsers on merged node stdout/stderr | Cursor CLI emits no recognized usage block |
| `run_opencode_agent.ps1` / `run_opencode_scout.ps1` | OpenCode output matches same parsers | Local stack prints no parseable usage |

## Limits behavior

- Numeric caps in `config/token_limits.yaml` → rolling usage vs limit with **percentage**.
- `unknown` or missing key → **no percentage**; message states unknown / not configured.
- `not_applicable` (or spelling variants) → **not applicable**.
- Local heuristic (`local-` models, `local` in provider, `llama` / `ollama` in model): missing keys treated as **not applicable** unless YAML sets an explicit value (including explicit `unknown`).

## Task-specific command output

- PowerShell `Parser::ParseFile` not re-run in-summary; CI covers via pytest AST checks on touched scripts.

## Remaining risks

- External CLIs change log shape; regex-first parsing can miss new formats without updates.
- Successful `ai_loop_task_first` runs `show_token_report` after `ai_loop_auto` may already have printed a report (duplicate console block, non-fatal).
- Rolling window labels are UTC and approximate (7-day / 30-day rolling), not provider billing cycles.
