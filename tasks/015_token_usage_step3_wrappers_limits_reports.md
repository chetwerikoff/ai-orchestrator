# Task: Token usage step 3 - wrappers, limits, and reports

## Project context

Required reading before starting:

1. `AGENTS.md`
2. `.ai-loop/task.md`
3. `.ai-loop/project_summary.md`
4. `scripts/record_token_usage.ps1`
5. `scripts/show_token_report.ps1`
6. Wrapper scripts named in the files-in-scope section
7. `tests/test_token_usage.py`

## Goal

Complete the remaining token usage work from `tasks/task_token_usage_reports_and_journal.md`: record usage from the key planner/reviewer/implementer wrapper calls where available, show configured daily/weekly/monthly limit status without inventing unknown values, and optionally export timestamped human-readable reports for later analysis.

This task follows the completed foundation and step 2 work. Keep the implementation conservative and non-blocking.

## Scope

Allowed:
- Add `config/token_limits.yaml` if the task determines a simple config is worthwhile
- Extend `scripts/show_token_report.ps1` to display known/unknown/not-applicable limits
- Add token usage recording to selected wrapper scripts with available CLI output
- Add timestamped report export under `.ai-loop/reports/`
- Update `.gitignore` for generated runtime reports
- Update `scripts/install_into_project.ps1` if new committed templates/config need installation
- Update tests in `tests/test_token_usage.py` and targeted orchestrator validation tests if needed
- Update `.ai-loop/project_summary.md` and `.ai-loop/implementer_summary.md`

Not allowed:
- Make token usage failures fatal
- Invent provider plan limits when they are unknown
- Store secrets or account identifiers
- Add a database, service, embedding index, or large reporting subsystem
- Change safe git commit/push behavior except for a clearly justified SafeAddPaths update for committed config only

## Files in scope

- `scripts/record_token_usage.ps1`
- `scripts/show_token_report.ps1`
- `scripts/run_claude_planner.ps1`
- `scripts/run_codex_reviewer.ps1`
- `scripts/run_cursor_agent.ps1`
- `scripts/run_opencode_agent.ps1`
- `scripts/run_opencode_scout.ps1`
- `scripts/ai_loop_plan.ps1`
- `scripts/ai_loop_task_first.ps1`
- `scripts/install_into_project.ps1`
- `.gitignore`
- `config/token_limits.yaml` (new, optional)
- `tests/test_token_usage.py`
- `.ai-loop/project_summary.md`
- `.ai-loop/implementer_summary.md`

## Files out of scope

- `docs/archive/**`
- `.ai-loop/_debug/**`
- `ai_loop.py`
- `scripts/ai_loop_auto.ps1` except if a report call must stay consistent with other entry points
- `scripts/continue_ai_loop.ps1`
- Unrelated queued task specs under `tasks/`

## Required behavior

1. **Wrapper recording**
   - Record token usage for key model invocations when the wrapper output includes parseable usage.
   - At minimum evaluate Claude planner/reviewer wrappers, Codex reviewer wrapper, Cursor wrapper, and OpenCode wrappers.
   - If a wrapper cannot reliably expose usage, do not fake values. Record nothing or record an explicit unknown only if it is useful and does not create noisy JSONL.

2. **Script-level final report**
   - After `ai_loop_plan.ps1` and `ai_loop_task_first.ps1` complete successfully, show the same report path used by `ai_loop_auto.ps1`, non-fatally.
   - Do not add report calls to failure paths unless the script already has enough clean context and the call cannot hide the original failure.

3. **Limits config**
   - If added, keep `config/token_limits.yaml` small and documented by example comments or README-style inline keys.
   - Support `daily`, `weekly`, and `monthly` values when known.
   - Support explicit `unknown` and `not_applicable` states.
   - Local providers should show billing limits as not applicable unless configured otherwise.

4. **Report output**
   - Keep existing Total, By model, and By iteration sections.
   - Add a Limits section that never invents values.
   - If no usage records exist, continue to print `No token usage records found.` and exit 0.
   - Optionally write `.ai-loop/reports/token_usage_<timestamp>.md`; failures must warn only.

5. **Journal format**
   - Preserve backward compatibility with existing `.ai-loop/token_usage.jsonl` records.
   - Include enough fields to support task, script, iteration, provider, model, source, quality, and totals.

## Tests

Add focused tests for:

- Limit config parsing with known, unknown, and not-applicable values
- Report output showing percentages only when limits are numeric
- Missing config produces explicit unknown/not configured text, not failure
- Timestamped report export path is created when enabled
- Wrapper parse/record helper path using representative CLI output strings
- Existing no-record and malformed-record behavior still exits 0

Run:

```powershell
python -m pytest tests/test_token_usage.py -q
python -m pytest -q
```

## Verification

```powershell
powershell -NoProfile -Command "[void][System.Management.Automation.Language.Parser]::ParseFile('scripts\show_token_report.ps1', [ref]$null, [ref]$null)"
powershell -NoProfile -Command "[void][System.Management.Automation.Language.Parser]::ParseFile('scripts\record_token_usage.ps1', [ref]$null, [ref]$null)"
python -m pytest -q
```

Add parse checks for edited wrapper scripts when they are touched.

## Implementer summary requirements

Report:

1. Changed files and why
2. Test result
3. Which wrappers now record usage and which remain unknown
4. Limits behavior for known, unknown, and local providers
5. Remaining risks, especially CLI output format volatility

## Output hygiene

- Do not commit or push.
- Do not write to `.ai-loop/_debug/`.
- Do not delete or modify unrelated queued task specs under `tasks/`.
- Keep generated `.ai-loop/token_usage.jsonl`, `.ai-loop/token_usage_summary.md`, and `.ai-loop/reports/` out of git unless a separate durable-summary decision is made.

## Order

15
