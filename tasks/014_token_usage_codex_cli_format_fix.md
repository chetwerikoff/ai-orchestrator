# Task: Token usage Codex CLI format fix

## Project context

Required reading before starting:

1. `AGENTS.md`
2. `.ai-loop/task.md`
3. `.ai-loop/project_summary.md`
4. `scripts/record_token_usage.ps1`
5. `scripts/ai_loop_auto.ps1`
6. `tests/test_token_usage.py`

## Goal

Make the existing Codex token usage hook record real usage from the current Codex CLI output. Recent `.ai-loop/codex_review.md` files contain a line like `tokens used 32,372`, but `ConvertFrom-CliTokenUsage` only recognizes JSON usage fields and `Input tokens:` / `Output tokens:` pairs. As a result, `.ai-loop/token_usage.jsonl` can remain absent even after a Codex review ran.

This is a narrow bug-fix task for the already implemented step 2, not the full step 3 limits/wrapper expansion.

## Scope

Allowed:
- Extend `ConvertFrom-CliTokenUsage` in `scripts/record_token_usage.ps1`
- Add focused tests in `tests/test_token_usage.py`
- Update `.ai-loop/implementer_summary.md`
- Update `.ai-loop/project_summary.md` only if the durable status/risk text needs correction

Not allowed:
- Add `config/token_limits.yaml`
- Add `.ai-loop/reports/`
- Modify wrapper scripts (`run_*.ps1`)
- Change orchestration flow, commit/push logic, or SafeAddPaths
- Write runtime token logs as part of tests without cleanup

## Files in scope

- `scripts/record_token_usage.ps1`
- `tests/test_token_usage.py`
- `.ai-loop/implementer_summary.md`
- `.ai-loop/project_summary.md`

## Files out of scope

- `docs/archive/**`
- `.ai-loop/_debug/**`
- `ai_loop.py`
- `scripts/run_claude_planner.ps1`
- `scripts/run_codex_reviewer.ps1`
- `scripts/run_cursor_agent.ps1`
- `scripts/run_opencode_agent.ps1`
- `scripts/run_opencode_scout.ps1`
- `scripts/ai_loop_plan.ps1`
- `scripts/ai_loop_task_first.ps1`
- `scripts/continue_ai_loop.ps1`
- `scripts/ai_loop_auto.ps1`
- `config/token_limits.yaml`
- `.ai-loop/reports/**`
- Unrelated queued task specs under `tasks/`

## Required behavior

1. Add support for Codex CLI summary lines such as:

   ```text
   tokens used
   32,372
   ```

   and single-line variants such as:

   ```text
   tokens used 32,372
   ```

2. Return a parsed object with:
   - `InputTokens = $null`
   - `OutputTokens = $null`
   - `TotalTokens = 32372`
   - `Source = "cli_log"`
   - `Quality = "exact"` if the Codex CLI value is treated as an exact reported total, otherwise `"unknown"` with a short comment explaining why.

3. Keep existing parser precedence unchanged for richer formats. JSON with input/output counts must still win over total-only CLI summary text.

4. Keep the hook non-blocking. No change should cause `ai_loop_auto.ps1` to fail when usage cannot be parsed.

## Tests

Add or update tests:

- `test_convert_codex_tokens_used_single_line`
- `test_convert_codex_tokens_used_multiline`
- A precedence test showing OpenAI JSON still returns input/output/total even if unrelated `tokens used` text appears nearby.

Run:

```powershell
python -m pytest tests/test_token_usage.py -q
python -m pytest -q
```

## Verification

```powershell
powershell -NoProfile -Command "[void][System.Management.Automation.Language.Parser]::ParseFile('scripts\record_token_usage.ps1', [ref]$null, [ref]$null)"
python -m pytest tests/test_token_usage.py -q
```

## Implementer summary requirements

Report:

1. Changed files
2. Test count and result
3. Exact Codex CLI forms now parsed
4. Remaining limitation: total-only CLI output cannot provide input/output split

## Output hygiene

- Do not commit or push.
- Do not write to `.ai-loop/_debug/`.
- Do not delete or modify unrelated queued task specs under `tasks/`.

## Order

14
