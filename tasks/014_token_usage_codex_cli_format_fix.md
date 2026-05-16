# Task: Token usage Codex CLI format fix

## Project context

Before implementation, read in order (stop when sufficient):

1. `AGENTS.md`
2. `.ai-loop/task.md`
3. `.ai-loop/project_summary.md`
4. `.ai-loop/repo_map.md`
5. `scripts/record_token_usage.ps1`
6. `tests/test_token_usage.py`

For iteration 2 or later on the same task, also read `.ai-loop/implementer_summary.md` and `.ai-loop/failures.md` before the first fix attempt.

## Goal

Extend `ConvertFrom-CliTokenUsage` in `scripts/record_token_usage.ps1` so Codex CLI summary output that reports total tokens only (for example `tokens used 32,372` on one line or split across two lines) is parsed into the existing usage object shape. Today only JSON usage fields and `Input tokens:` / `Output tokens:` pairs are recognized, so `.ai-loop/token_usage.jsonl` can stay empty after Codex runs even when `.ai-loop/codex_review.md` contains a usable total. This is a narrow parser/hook fix for step-2 recording, not limits or wrapper expansion.

## Scope

Allowed:

- Extend `ConvertFrom-CliTokenUsage` in `scripts/record_token_usage.ps1` only as needed for Codex `tokens used` patterns and documented return shape.
- Add or update focused tests in `tests/test_token_usage.py`.
- Update `.ai-loop/implementer_summary.md` after the iteration.
- Update `.ai-loop/project_summary.md` only if durable status or risk text is wrong after the fix.

Not allowed:

- Add or require `config/token_limits.yaml`.
- Add `.ai-loop/reports/` or change reporting UX beyond what existing hooks already do.
- Modify `scripts/run_*.ps1` wrappers or orchestration scripts (`ai_loop_auto.ps1`, `ai_loop_plan.ps1`, `ai_loop_task_first.ps1`, `continue_ai_loop.ps1`).
- Change commit/push logic, `SafeAddPaths`, or Codex review flow.
- Tests that write runtime token logs without cleanup.

## Files in scope

- `scripts/record_token_usage.ps1`
- `tests/test_token_usage.py`
- `.ai-loop/implementer_summary.md`
- `.ai-loop/project_summary.md` optional updates only if warranted

## Files out of scope

- `docs/archive/**`
- `.ai-loop/_debug/**`
- `ai_loop.py`
- `scripts/run_claude_planner.ps1`
- `scripts/run_claude_reviewer.ps1`
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
- Unrelated specs under `tasks/` unless explicitly listed here

## Required behavior

1. Parse Codex-style totals when the captured text includes either:
   - two adjacent lines where the first is `tokens used` (case-insensitive, trimmed) and the next line is a comma-separated integer total; or
   - a single line matching `tokens used` followed by the integer total (with optional comma separators), for example `tokens used 32,372`.
2. For a successful parse from this Codex summary path, return an object consistent with existing recorder expectations with at least: `InputTokens = $null`, `OutputTokens = $null`, `TotalTokens` set to the numeric total, `Source = "cli_log"`, and `Quality = "exact"` when the value is taken as the CLI-reported total as-is; use `Quality = "unknown"` plus a short clarifying comment only when the implementation must infer or normalize beyond a single explicit total token count line.
3. Preserve parser precedence: richer formats (for example structured JSON with input/output fields) must continue to win over total-only `tokens used` text when both appear.
4. Keep behavior non-blocking: callers must not hard-fail when usage cannot be parsed; extend parsing without introducing terminating errors or mandatory dependencies.

## Tests

Add or update tests in `tests/test_token_usage.py`:

- `test_convert_codex_tokens_used_single_line`
- `test_convert_codex_tokens_used_multiline`
- A precedence test proving OpenAI-style JSON still yields input/output/total when unrelated `tokens used` text appears in the same blob.

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

After the iteration, update `.ai-loop/implementer_summary.md` with:

1. Changed files (brief).
2. Test count and pass/fail outcome (not full log).
3. Exact Codex CLI text shapes now parsed.
4. Skipped items with reason (if any).
5. Remaining limitations (for example total-only lines cannot populate input/output split).

## Project summary update

Update `.ai-loop/project_summary.md` only if token-recording or Codex-related durable claims are inaccurate after this fix; otherwise state no update in the summary file itself is needed.

## Output hygiene

- Do not duplicate the full task narrative into `.ai-loop/project_summary.md`; keep durable notes minimal.
- Do not write to `.ai-loop/_debug/` for this work.
- Do not create git commits or pushes unless a separate human request explicitly asks for them.
- Do not edit `docs/archive/` or unrelated queued specs under `tasks/`.

## Important

- Assumption: Codex emits ASCII digits with optional thousands separators; normalization should strip commas before `[int]` or `[long]` conversion and reject ambiguous multiples totals deterministically (prefer existing patterns in `ConvertFrom-CliTokenUsage` for locale and overflow).
- Match existing property names and types returned by `ConvertFrom-CliTokenUsage` for other sources so `Write-CliCaptureTokenUsageIfParsed` and JSONL consumers stay unchanged.
- If the diff risks exceeding ~80 lines, split follow-up into a separate ordered task rather than expanding scope here.
- Architect note: none; the requested scope (parser + tests only, wrappers untouched) matches the simplest fix consistent with `AGENTS.md` and the file-based hook design.

## Order

14
