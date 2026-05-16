# Task: Codex FIX_REQUIRED terminal visibility

## Project context

Implementers must read in order: `AGENTS.md`, `.ai-loop/task.md`, `.ai-loop/project_summary.md`, `.ai-loop/repo_map.md`. On iteration 2+, also read `.ai-loop/implementer_summary.md` and `.ai-loop/failures.md`.

## Goal

When `scripts/ai_loop_auto.ps1` completes a Codex review and the parsed verdict is not `PASS`, the operator should see an immediate, explicit `FIX_REQUIRED` announcement in the terminal before the script extracts the fix prompt and invokes the implementer, matching the clarity of the existing `Codex verdict: PASS` line on the success path. This is observability only: no change to verdict parsing, fix extraction, staging, or when the fix loop runs.

## Scope

- **Allowed:** Concise `Write-Host` lines in `scripts/ai_loop_auto.ps1` on the non-`PASS` path after `Get-CodexVerdict`; the same messaging on the resume path that reuses an existing `codex_review.md` and calls `Extract-FixPrompt` before `Run-ImplementerFix` (for parity with the main loop); a small static-source test in `tests/test_orchestrator_validation.py`; a short durable note in `.ai-loop/project_summary.md` under the observability/operator-UX story.
- **Not allowed:** Changes to `Get-ReviewVerdict` / `Get-CodexVerdict`, `Extract-FixPrompt` / JSON or markdown extraction, C12 guard behavior, `SafeAddPaths` / staging, Codex prompt text, live CLI test runs, commits or pushes, `docs/archive/**`, `.ai-loop/_debug/**`, or `ai_loop.py`.

## Files in scope

- `scripts/ai_loop_auto.ps1`
- `tests/test_orchestrator_validation.py`
- `.ai-loop/project_summary.md`
- `tasks/` (C12: queued specs present in working tree; scope acknowledges coexistence with this iteration)
- `tasks/` (C12: queued specs present in working tree; scope acknowledges coexistence with this iteration)

## Files out of scope

- `docs/archive/**`
- `.ai-loop/_debug/**`
- `ai_loop.py`
- `templates/codex_review_prompt.md` and other templates (operator messages only; no prompt edits)
- `docs/architecture.md` and `docs/decisions.md` (no design decision required for log lines)

## Required behavior

1. In the main `for` loop, immediately after `$codexVerdict = Get-CodexVerdict`, when the verdict is not `PASS` (i.e., treat as `FIX_REQUIRED` / fix path): emit a leading blank line for readability (same spirit as the `PASS` branch), then print exactly `Codex verdict: FIX_REQUIRED` via `Write-Host` so it mirrors the existing `Codex verdict: PASS` label.
2. Before calling `Extract-FixPrompt` on that branch, emit one short `Write-Host` line such as `Extracting fix prompt for implementer...` so the operator sees why control flow pauses before the implementer.
3. Do not add a second ÔÇ£running implementerÔÇØ banner beyond what `Run-ImplementerFix` already prints (`Running implementer (non-interactive) via: ...`); avoid duplicate or conflicting wording there.
4. In `Try-ResumeFromExistingReview`, when an existing `codex_review.md` is present, the verdict is not `PASS`, and the script is about to run `Extract-FixPrompt` followed by `Run-ImplementerFix` (not the early-exit `PASS` resume path), emit the same two lines (verdict + extracting) before extraction so resume behaves like the main loop.
5. If `Extract-FixPrompt` returns false, existing error `Write-Host` / exit behavior must remain; do not imply that an implementer run will follow after a failed extraction.

## Tests

1. Add or extend a test in `tests/test_orchestrator_validation.py` that reads `scripts/ai_loop_auto.ps1` as UTF-8 text and asserts the presence of the new `FIX_REQUIRED` verdict line string and the extracting line string in the script source (same lightweight style as other `ai_loop_auto` substring/structure checks). Optionally assert that the `FIX_REQUIRED` line appears after the main-loop `Get-CodexVerdict` call site to avoid accidental duplication in unrelated regions.
2. Run `python -m pytest -q`.

## Verification

```powershell
python -m pytest -q
```

```powershell
powershell -NoProfile -Command "[void][System.Management.Automation.Language.Parser]::ParseFile('scripts\ai_loop_auto.ps1', [ref]$null, [ref]$null)"
```

## Implementer summary requirements

1. List changed files (brief).
2. Test result (count, not full output).
3. Implemented work (3ÔÇô5 lines): what was printed on `FIX_REQUIRED`, and where (main loop vs resume).
4. Skipped items with reason (if any).
5. Remaining risks (1ÔÇô3 bullets).

## Project summary update

Add a concise sentence under the current pipeline / operator-UX area noting that the auto loop now prints an explicit `Codex verdict: FIX_REQUIRED` line (and a short ÔÇ£extracting fix promptÔÇØ line) before the fix iteration, so the verdict is visible alongside the existing `PASS` message. No architectural claims beyond that.

## Output hygiene

- Do not duplicate the full task body into `.ai-loop/implementer_summary.md`.
- Do not write under `.ai-loop/_debug/` except what existing scripts already do.
- Do not create a git commit unless a separate human request explicitly asks for it.
- Do not add or modify files under `docs/archive/**`.

## Important

- Assumption: ÔÇ£non-PASSÔÇØ after `Get-CodexVerdict` is always the fix path to be announced; do not reinterpret verdict strings.
- **Architect note:** User-proposed third line `Running implementer fix pass...` is omitted because `Run-ImplementerFix` already emits a clear implementer banner; adding another line would be noisy and redundant.
- **Architect note:** Resume path `Try-ResumeFromExistingReview` when `next_implementer_prompt.md` already exists and the script jumps straight to `Run-ImplementerFix` is left unchanged (that path already announces resume); only the ÔÇ£existing review, re-extractÔÇØ branch is aligned with the main loop messaging.
- Keep the total diff near the ~80-line policy; this should be a small insert plus one test and a short `project_summary` tweak.

## Order
