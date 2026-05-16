# Task: Scope-filter diff_summary.txt and last_diff.patch for Codex review

## Project context

Required reading before starting:

1. `AGENTS.md`
2. `.ai-loop/project_summary.md`
3. `scripts/ai_loop_auto.ps1` — focus on `Save-GitReviewArtifactsForCodex` (~line 489), `Get-ActiveScope`, `Test-PorcelainPathInReviewFilter`, `$script:DurableAlwaysCommitPaths`

## Goal

`git_status.txt` is already scope-filtered before Codex review. But `diff_summary.txt`
and `last_diff.patch` are generated from bare `git diff HEAD` — unfiltered. Codex reads
`diff_summary.txt` at priority 4 and `last_diff.patch` at priority 6, so staged
deletions/additions/edits of `tasks/` files (e.g. a user-deleted queue spec) appear in
the diff, Codex flags them, the fix prompt references `tasks/` paths, and
`UNSAFE_QUEUE_CLEANUP` fires — even though `git_status.txt` correctly omitted them.

Fix: generate `diff_summary.txt` and `last_diff.patch` using the same scope-filtered
path list that already drives `git_status.txt`.

## Required behavior

In `Save-GitReviewArtifactsForCodex`:

1. Build a list of **scoped paths** = `DurableAlwaysCommitPaths` + paths from `Get-ActiveScope`
   that also pass `Test-PathUnderSafeAddEntry` (same logic as the status filter).

2. Replace the two bare `git diff HEAD` calls (current lines ~514-515) with:
   `git diff HEAD -- <scoped-path-1> <scoped-path-2> ...`
   using the scoped path list. If the list is empty fall back to bare `git diff HEAD`
   (fail-open so the reviewer still gets a diff).

3. The same scoped path list drives both `last_diff.patch` (`git diff HEAD --`)
   and `diff_summary.txt` (`git diff --stat HEAD --`).

4. Do not change the `git_status.txt` filtering logic — it already works correctly.

5. Update `.ai-loop/project_summary.md` to note that all three review artifacts
   (`git_status.txt`, `diff_summary.txt`, `last_diff.patch`) are now scope-filtered.

## Scope

Allowed:
- Edit `scripts/ai_loop_auto.ps1` — `Save-GitReviewArtifactsForCodex` only
- Edit `tests/test_orchestrator_validation.py` — add/update unit tests
- Edit `.ai-loop/project_summary.md`
- Edit `.ai-loop/implementer_summary.md`

Not allowed:
- Changing `Test-GitStatusLinePassesScopeFilter` or `git_status.txt` logic
- Changing `Stage-SafeProjectFiles`
- Changing `Extract-FixPrompt` / `Stop-UnsafeQueueCleanup`
- Changing `templates/codex_review_prompt.md`
- `scripts/ai_loop_task_first.ps1`, `scripts/ai_loop_plan.ps1`
- `docs/archive/**`, `.ai-loop/_debug/**`, `ai_loop.py`
- `tasks/**`
- Git commit or push

## Files in scope

- `scripts/ai_loop_auto.ps1`
- `tests/test_orchestrator_validation.py`
- `.ai-loop/project_summary.md`
- `.ai-loop/implementer_summary.md`

## Files out of scope

- `docs/archive/**`
- `.ai-loop/_debug/**`
- `ai_loop.py`
- `tasks/**`
- `scripts/ai_loop_task_first.ps1`
- `scripts/ai_loop_plan.ps1`
- `templates/codex_review_prompt.md`

## Tests

- All existing tests must pass (`python -m pytest -q`).
- Add unit tests for `Save-GitReviewArtifactsForCodex` (or the helper that builds
  the scoped path list) covering:
  1. A staged `tasks/` deletion is excluded from scoped diff args when `tasks/`
     is not in active scope.
  2. A scoped file (`scripts/foo.ps1`) is included in diff args when it is in scope.
  3. Empty scope list falls back to bare `git diff HEAD`.

## Important

- Change is confined to `Save-GitReviewArtifactsForCodex`: replace 2 lines, add
  ~15-20 lines of path-list building. Target total diff <= 40 lines.
- Use the existing `Get-ActiveScope`, `Test-PathUnderSafeAddEntry`,
  `$script:DurableAlwaysCommitPaths` — do not duplicate their logic.
- PowerShell splatting for `git diff HEAD --` with a path array:
  build as `@($durablePaths + $scopedPaths)` and pass as positional args after `--`.
