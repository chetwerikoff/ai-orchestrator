# Task: Normalize Codex reviewer transcript before strict validation

## Project context

Required reading for the implementer:

- `AGENTS.md`
- `.ai-loop/task.md` (this file)
- `.ai-loop/project_summary.md`
- `.ai-loop/repo_map.md`

## Goal

The optional `-WithReview` path in `scripts/ai_loop_plan.ps1` passes raw `codex exec` transcript text into `Test-ReviewerOutputStrict`. That transcript can include role labels (for example a leading `codex` line), a `tokens used` footer, and duplicated echoed content, which makes strict validation fail with `MALFORMED` even when the reviewer body is valid. Normalize reviewer stdout to strip that envelope immediately before the existing strict check so correct `NO_BLOCKING_ISSUES` and `ISSUES:` responses pass without relaxing `Test-ReviewerOutputStrict`.

## Scope

**Allowed:**

- Add a small `Normalize-ReviewerOutput` helper in `scripts/ai_loop_plan.ps1`, patterned after `Normalize-PlannerOutput` (same file), and invoke it at the single reviewer path that feeds `Test-ReviewerOutputStrict`.
- Add or extend tests in `tests/test_orchestrator_validation.py` so normalization and downstream strict acceptance are covered without changing strict validation rules.

**Not allowed:**

- Changing `Test-ReviewerOutputStrict` validation rules or accepted issue tags (normalization only).
- Editing `templates/reviewer_prompt.md`, `scripts/ai_loop_auto.ps1`, or `scripts/run_codex_reviewer.ps1`.
- Committing, pushing, or writing under `docs/archive/**` or `.ai-loop/_debug/**`.
- Editing `ai_loop.py`.

## Files in scope

- `scripts/ai_loop_plan.ps1`
- `tests/test_orchestrator_validation.py`

## Files out of scope

- `docs/archive/**`
- `.ai-loop/_debug/**`
- `ai_loop.py`
- `templates/reviewer_prompt.md`
- `scripts/ai_loop_auto.ps1`
- `scripts/run_codex_reviewer.ps1`
- Any file not listed under **Files in scope**

## Required behavior

1. Implement `Normalize-ReviewerOutput` in `scripts/ai_loop_plan.ps1` following the same general style as `Normalize-PlannerOutput` (trimmed lines, simple string operations, no new dependencies).
2. Normalization semantics (after full-text processing matching these rules):
   - If the input contains a standalone trimmed line exactly `NO_BLOCKING_ISSUES`, return the string `NO_BLOCKING_ISSUES` (planner/reviewer contract: single canonical token for the clean pass case).
   - Else locate the **last** line that matches `^\s*ISSUES:\s*$`; if none, return the stripped transcript after other cleanup steps that still apply, or empty string when appropriate so strict validation fails closed as today.
   - From that `ISSUES:` line onward, remove a trailing footer: a whole line matching `tokens used` case-insensitively and everything after it on following lines.
   - Trim trailing whitespace from the result; duplicate echoed blocks are handled by taking the **last** `ISSUES:` anchor as specified.
3. At the **only** call site where reviewer stdout is validated with `Test-ReviewerOutputStrict`, pass `Normalize-ReviewerOutput`ÔÇÖs output into `Test-ReviewerOutputStrict` (do not alter `Test-ReviewerOutputStrict` itself).
4. Preserve behavior for empty or whitespace-only input: strict validation should still yield `{ Ok = $false }` as today (normalization may yield empty; strict check unchanged).
5. Do not apply this normalization to planner Claude output or other non-Codex-review pathsÔÇöonly the reviewer transcript path that currently triggers false `MALFORMED`.

## Tests

- Extend `tests/test_orchestrator_validation.py` with focused cases that invoke the same PowerShell harness pattern already used for planner/task-first helpers (dot-source or subprocess as appropriate for this repo), covering at minimum:
  - Transcript with a leading `codex` (or similar role-label) line before a valid `ISSUES:` block ÔåÆ strict acceptance unchanged from a clean file with only that block.
  - Footer `tokens used` plus numeric line removed; body still validates.
  - Two `ISSUES:` sections (echo duplicate) ÔåÆ **last** block is what strict validation sees and passes when that block is valid.
  - Clean `NO_BLOCKING_ISSUES` only ÔåÆ still valid.
  - Clean `ISSUES:` block with no wrapper ÔåÆ still valid.
  - Empty / whitespace-only ÔåÆ `{ Ok = $false }` unchanged.
- Run `python -m pytest -q`.

## Verification

```powershell
python -m pytest -q
```

```powershell
powershell -NoProfile -Command "[void][System.Management.Automation.Language.Parser]::ParseFile('scripts\ai_loop_plan.ps1', [ref]$null, [ref]$null)"
```

Optional: `pyright` if any Python typing is touched (unlikely).

## Implementer summary requirements

- List changed files briefly.
- State pytest result as count summary (not full log).
- Summarize implemented work in 3ÔÇô5 lines.
- Note any skipped items with reason.
- List 1ÔÇô3 remaining risks.

## Project summary update

Add one short bullet under an appropriate heading (for example **Last Completed Task** or **Current Stage** notes) stating that `-WithReview` now normalizes Codex reviewer transcripts before `Test-ReviewerOutputStrict`, eliminating false `MALFORMED` warnings from CLI envelope noiseÔÇöafter this task ships.

## Output hygiene

- Do not duplicate this task body into `.ai-loop/project_summary.md`; only the durable one-line note above.
- Do not write debug transcripts under `.ai-loop/_debug/` unless debugging locally outside commit scope.
- Do not create a git commit unless the human explicitly asks.
- Do not edit `docs/archive/**`.

## Important

- Reuse `Normalize-PlannerOutput` in the same file as the structural pattern only; reviewer normalization rules differ (last `ISSUES:` anchor, `tokens used` footer).
- **Architect note:** none on core approachÔÇöthe USER ASK matches repo conventions (minimal PowerShell helper, strict validator untouched, tests beside existing orchestrator validation). If implementation discovers a second call site to `Test-ReviewerOutputStrict`, normalize at both or consolidate so **all** Codex reviewer transcripts hit normalization onceÔÇöstill without editing `Test-ReviewerOutputStrict`.
- Keep the PowerShell delta small (on the order of one function plus one call-site change; total change budget ~80 lines including tests).

## Order
