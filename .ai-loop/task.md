# Task: Simplify P0 follow-up — no-op guard cleanup, REVIEW-mode parity, dead-file removal

## Context

Commit `ceb8f73` ("Fix P0 orchestrator workflow issues") shipped the P0 fixes
for the task-first flow but left three problems:

1. `scripts/ai_loop_task_first.ps1` grew from ~195 to 724 lines because the
   no-op guard was implemented with directory-tree SHA256 fingerprinting,
   sentinel hash strings, and content-snapshot tables. The original
   requirement was a single check: "did Cursor produce any working-tree
   delta in tracked-or-staged-or-untracked files (excluding orchestrator
   scratch)?" Current code solves edge cases that do not occur in practice
   and makes the script unreadable for a junior dev.

2. The same no-op guard and the runtime-state cleanup were **not** added to
   `scripts/ai_loop_auto.ps1`. In REVIEW mode, an iteration with empty diff
   still calls Codex (waste of a model turn), and stale `.ai-loop` runtime
   files from a previous run can influence the new run.

3. Claude-final-review files still linger:
   - `templates/claude_final_review_prompt.md` was reduced to a "# Removed"
     stub instead of being deleted.
   - `.ai-loop/claude_final_review.md` is still present in the working tree.

This task fixes all three.

## Goal

Make `ai_loop_task_first.ps1` short and readable again, port the no-op guard
and stale-state cleanup to `ai_loop_auto.ps1`, and delete the leftover Claude
files. Keep all existing behavior that is observable from the outside:

- `final_status.md` writes `STATUS: FAILED` with `REASON: NO_CHANGES_AFTER_CURSOR`
  when Cursor produces no delta after two attempts.
- `IMPLEMENTATION_STATUS: DONE_NO_CODE_CHANGES_REQUIRED` marker still allows
  proceeding when `cursor_implementation_result.md` is the only delta.
- `Extract-FixPromptFromFile` still tolerates a missing `FINAL_NOTE:`.
- The 19 tests in `tests/test_orchestrator_validation.py` keep passing.

## Scope

### Allowed

- Rewrite the no-op detection in `scripts/ai_loop_task_first.ps1` using a
  small, readable helper (target: total script length ≤ ~300 lines).
- Add a no-op guard at the start of each iteration in
  `scripts/ai_loop_auto.ps1`.
- Add `Clear-AiLoopRuntimeState` (or equivalent) call at the start of
  `scripts/ai_loop_auto.ps1` when not running in `-Resume` mode.
- Delete `templates/claude_final_review_prompt.md`.
- Delete `.ai-loop/claude_final_review.md`.
- Update tests in `tests/test_orchestrator_validation.py` to match the
  simplified script (remove tests that asserted on internal helpers that
  no longer exist; keep tests that assert observable behavior).
- Update `docs/workflow.md`, `docs/decisions.md`, `README.md` only if they
  reference deleted helpers or files.

### Not allowed

- Do not change the public CLI: same param names, same defaults, same exit
  codes, same `final_status.md` `REASON` strings.
- Do not change the `IMPLEMENTATION_STATUS: DONE_NO_CODE_CHANGES_REQUIRED`
  regex behavior (`(?im)^IMPLEMENTATION_STATUS:\s*DONE_NO_CODE_CHANGES_REQUIRED\s*$`).
- Do not change `Extract-FixPromptFromFile`.
- Do not touch `ai_loop.py` (it stays Experimental).
- Do not introduce `state.json`, per-iteration log folders, branch creation,
  or any other P1/P2 features. They will be a separate task.

## Required behavior

### 1. Simplify no-op detection in `ai_loop_task_first.ps1`

Replace all of: `Get-FilteredPorcelainLinesForImplementation`,
`Compare-PorcelainSets`, `Test-IsOrchestratorScratchImplementationPath`,
`Get-NormalizedImplementationPathsFromFilteredPorcelain`,
`Get-ImplementationContentSnapshotTable`,
`Get-CursorProducedPathsFromContentDelta`,
`Get-NormalizedPathsFromPorcelain`, `Build-PorcelainPathToLineMap`,
`Get-CursorProducedPathsFromPorcelainDelta`, `Get-ResultFileSnapshot`,
`Test-ResultFileChangedDuringPass`, `Test-ImplementationHadAgentSideEffects`,
`Assert-CanProceedAfterImplementation`.

With a single helper that:

- runs `git status --porcelain --untracked-files=all`
- for each non-empty line, trims the leading 3-char status field and takes the path
- if the line is a rename (contains the rename token used by porcelain), takes the destination path
- normalizes backslashes to forward slashes
- filters out the orchestrator scratch files: `.ai-loop/cursor_summary.md`, `.ai-loop/cursor_implementation_prompt.md`, `.ai-loop/cursor_implementation_output.txt`
- returns the deduplicated sorted list

No SHA256, no directory hashing, no sentinel hash strings. The helper should
fit in ~15 lines of PowerShell.

Detection logic:

- Capture `Get-ImplementationDeltaPaths` once **before** the Cursor call.
- Capture it once **after** the Cursor call.
- "Had delta" iff the two sets differ, OR the result file
  `.ai-loop/cursor_implementation_result.md` was modified during the pass
  (compare `Get-Item.LastWriteTimeUtc` and existence — no hashes).
- If no delta, retry Cursor once with the existing stricter
  `$retryBody`. If still no delta, write `NO_CHANGES_AFTER_CURSOR` and exit
  non-zero (current behavior).
- After delta is detected, if the **only** changed path is
  `.ai-loop/cursor_implementation_result.md`, require the
  `IMPLEMENTATION_STATUS: DONE_NO_CODE_CHANGES_REQUIRED` regex (current
  behavior). Otherwise proceed.

Do **not** read file contents or compute hashes for any other purpose.
Untracked directories should be expanded by `--untracked-files=all`, which
already returns a flat list of files.

### 2. Add no-op guard at the start of each iteration in `ai_loop_auto.ps1`

After `Save-TestAndDiff`, before `Run-CodexReview`, in each iteration:

- Read `git status --porcelain --untracked-files=all`.
- If the result is empty (whitespace-only), do not call Codex.
- On iteration 1: write final-status reason `REVIEW_STARTED_ON_CLEAN_TREE`,
  print a short message advising the user to run task-first instead, exit
  with code 6.
- On iteration > 1: write final-status reason `NO_CHANGES_AFTER_CURSOR_FIX`,
  print a short message naming the iteration number, exit with code 7.

Use new exit codes 6 and 7. Do not collapse them with existing codes.
Use these exact `REASON:` strings in `final_status.md`:
`REVIEW_STARTED_ON_CLEAN_TREE` and `NO_CHANGES_AFTER_CURSOR_FIX`.

### 3. Stale-state cleanup at the start of `ai_loop_auto.ps1`

When `-Resume` is **not** set, at the very start of the script (after
`Ensure-AiLoopFiles`), delete the same runtime files that
`Clear-AiLoopRuntimeState` removes in `ai_loop_task_first.ps1`. Move the
helper into a small shared place — simplest is to copy the function into
both scripts (do **not** create a new shared module). When `-Resume` is set,
do **not** clear (existing behavior must hold).

### 4. Delete leftover Claude files

- `git rm templates/claude_final_review_prompt.md`
- `Remove-Item .ai-loop/claude_final_review.md` (it is gitignored).
- Leave the entries in `.gitignore` and in the runtime-cleanup list — they
  are defensive and harmless.

### 5. Update tests

`tests/test_orchestrator_validation.py` currently has 19 tests. Some likely
assert on helpers that no longer exist after simplification.

- Keep tests that assert observable behavior: SafeAddPaths parity, PS parser
  cleanliness, presence of `--untracked-files=all`, exit-code constants.
- Remove or rewrite tests that grep for now-deleted helper names.
- Add **one** new test: `ai_loop_auto.ps1` contains the new no-op guard
  (grep for the new reason literals `REVIEW_STARTED_ON_CLEAN_TREE` and
  `NO_CHANGES_AFTER_CURSOR_FIX`).
- Add **one** new test: `templates/claude_final_review_prompt.md` does not
  exist.

The final test count is whatever it ends up being; the goal is "no broken
tests, all assertions still meaningful". Do not add tests that lock in
internal helper names.

## Files likely to change

- `scripts/ai_loop_task_first.ps1` — large simplification
- `scripts/ai_loop_auto.ps1` — add no-op guard + stale-state cleanup
- `tests/test_orchestrator_validation.py` — adjust to new shape
- `templates/claude_final_review_prompt.md` — delete
- `.ai-loop/claude_final_review.md` — delete
- `docs/workflow.md` — only if it references removed helpers
- `README.md` — only if it references removed helpers

## Tests

Run:

```powershell
python -m pytest -q
```

All tests must pass. Then validate scripts parse:

```powershell
powershell -NoProfile -Command "[void][System.Management.Automation.Language.Parser]::ParseFile('scripts/ai_loop_task_first.ps1', [ref]$null, [ref]$null)"
powershell -NoProfile -Command "[void][System.Management.Automation.Language.Parser]::ParseFile('scripts/ai_loop_auto.ps1', [ref]$null, [ref]$null)"
```

## Verification

1. `wc -l scripts/ai_loop_task_first.ps1` should be ≤ 300 (currently 724).
2. `Get-ChildItem templates/claude_final_review_prompt.md` returns nothing.
3. `Get-ChildItem .ai-loop/claude_final_review.md` returns nothing.
4. `Select-String -Path scripts/ai_loop_auto.ps1 -Pattern REVIEW_STARTED_ON_CLEAN_TREE` returns one match.
5. `python -m pytest -q` exits 0.

## Cursor summary requirements

Update `.ai-loop/cursor_summary.md` with:

1. Final line counts of both PS1 scripts (before / after).
2. Test result.
3. Which helper functions were removed and which single helper replaced them.
4. Confirmation that the four observable behaviors listed under **Goal** are
   preserved (with one-line evidence each).
5. Remaining risks.

## Project summary update

Update `.ai-loop/project_summary.md` only if durable architecture changed
(it didn't significantly — just simpler implementation). One line under
"Last completed task" is enough.

## Important

- Do **not** add `state.json`, `runs/<run_id>/` folders, branch creation,
  diff truncation, or any P1/P2 feature. Those are separate tasks.
- Do **not** rename scripts.
- Do **not** change parameter names or defaults.
- Do **not** commit or push manually. The orchestrator handles git.
- If you find yourself writing more than ~50 net new lines of PowerShell,
  stop and reconsider — this task is mostly deletion and consolidation.
