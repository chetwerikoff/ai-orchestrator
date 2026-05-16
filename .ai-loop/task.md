# Task: Fix Codex verdict false-PASS safety bug

## Project context

- `AGENTS.md`
- `.ai-loop/task.md`
- `.ai-loop/project_summary.md`

## Goal

Fix `Get-ReviewVerdict` in `scripts/ai_loop_auto.ps1` so it only accepts a line whose entire content (after trimming) is exactly `VERDICT: PASS` or `VERDICT: FIX_REQUIRED`. The current regex matches `PASS` embedded inside instruction text such as `VERDICT: PASS or FIX_REQUIRED`, which caused the orchestrator to skip the fix loop and commit/push after a real `FIX_REQUIRED` response. After the fix, the last exact verdict line wins; absent any exact verdict line the function must return `FIX_REQUIRED` (safe default unchanged).

## Scope

Allowed:
- Modify `Get-ReviewVerdict` in `scripts/ai_loop_auto.ps1` (regex / line-matching logic only)
- Add focused tests in `tests/test_orchestrator_validation.py`
- Update `.ai-loop/project_summary.md` (last completed task + notes)

Not allowed:
- Changing Codex review prompt text or semantics
- Changing safe-add, staging, or commit/push behavior
- Changing task scope filtering, queue, or planner logic
- Running live CLIs (Codex, Cursor, Claude, OpenCode)
- Any changes to `docs/archive/**`, `.ai-loop/_debug/**`, `ai_loop.py`

## Files in scope

- `scripts/ai_loop_auto.ps1`
- `tests/test_orchestrator_validation.py`
- `.ai-loop/project_summary.md`

## Files out of scope

- `docs/archive/**`
- `.ai-loop/_debug/**`
- `ai_loop.py`
- `templates/**`
- `scripts/install_into_project.ps1`
- All other scripts

## Required behavior

1. Locate `Get-ReviewVerdict` in `scripts/ai_loop_auto.ps1`.
2. Replace the current pattern (which matches `VERDICT: PASS` anywhere in a line) with line-anchored matching: split the file content on newlines, trim each line, test each trimmed line against `^VERDICT:\s*(PASS|FIX_REQUIRED)$`. Collect all matches.
3. If at least one exact match is found, return the verdict from the **last** matched line (`PASS` or `FIX_REQUIRED`). Last-line semantics handle transcripts where prompt text or examples appear before the final assistant answer.
4. If no exact match is found, return `FIX_REQUIRED` (safe default ÔÇö unchanged behavior).
5. The fix must be contained inside `Get-ReviewVerdict`; no caller changes required.
6. Run the PowerShell parse check on `scripts/ai_loop_auto.ps1` to confirm no syntax errors.

## Tests

Add or update in `tests/test_orchestrator_validation.py` ÔÇö use the existing dot-sourced PowerShell harness pattern already present in that file:

1. `VERDICT: PASS` (exact, only line) ÔåÆ returns `PASS`.
2. `VERDICT: FIX_REQUIRED` (exact, only line) ÔåÆ returns `FIX_REQUIRED`.
3. `VERDICT: PASS or FIX_REQUIRED` (instruction text, no exact verdict) ÔåÆ returns `FIX_REQUIRED`.
4. `Return exactly: VERDICT: PASS or FIX_REQUIRED` ÔåÆ returns `FIX_REQUIRED`.
5. Transcript with prompt text (`VERDICT: PASS or FIX_REQUIRED`) on an early line and `VERDICT: FIX_REQUIRED` on a later line ÔåÆ returns `FIX_REQUIRED` (last exact verdict wins).
6. Transcript with prompt text on an early line and `VERDICT: PASS` as the final exact line ÔåÆ returns `PASS`.
7. Empty / missing review file ÔåÆ returns `FIX_REQUIRED`.

Run: `python -m pytest -q`

## Verification

```powershell
# PowerShell parse check
powershell -NoProfile -Command "[void][System.Management.Automation.Language.Parser]::ParseFile('scripts\ai_loop_auto.ps1', [ref]$null, [ref]$null)"
```

```bash
python -m pytest -q
```

Both must pass with zero errors/failures.

## Implementer summary requirements

1. Which lines in `Get-ReviewVerdict` were changed and what the old pattern was.
2. What the new line-split + anchored-regex logic looks like (brief).
3. Test count before and after (`python -m pytest -q` totals).
4. Any edge cases encountered (e.g., CRLF line endings, BOM).
5. Remaining risks, if any.

## Project summary update

Update **Last Completed Task** to: "Fixed critical false-PASS verdict bug in `Get-ReviewVerdict` (`ai_loop_auto.ps1`): line-anchored regex now required; last exact verdict line wins; instruction text containing both verdict strings no longer triggers PASS."

Add to **Notes For Future AI Sessions**: "Verdict parsing in `Get-ReviewVerdict` uses line-split + `^VERDICT:\s*(PASS|FIX_REQUIRED)$` anchoring; last exact line wins. Do not weaken back to substring matching."

## Output hygiene

- Do not duplicate task content into the implementer summary.
- Do not write to `.ai-loop/_debug/`.
- Do not commit or push.
- Do not write to `docs/archive/`.

## Important

The user's proposed approach is sound and adopted without divergence. Implementation notes for the implementer:

- PowerShell `[System.IO.File]::ReadAllText` or `Get-Content -Raw` followed by `-split '\r?\n'` handles both CRLF and LF correctly on Windows.
- The anchored pattern `^VERDICT:\s*(PASS|FIX_REQUIRED)$` with `-match` on a trimmed line is sufficient; no lookahead needed.
- The existing dot-sourced PowerShell harness in `test_orchestrator_validation.py` should be reused for the new tests rather than spawning separate `powershell -Command` subprocesses; follow whichever pattern the existing `Get-ReviewVerdict` tests (if any) already use.
- This is a **critical safety regression**: correctness is the only priority; do not add unrelated refactors.
