# Task: Scope-filter staging and review artifacts

## Project context
- `AGENTS.md`
- `.ai-loop/task.md`
- `.ai-loop/project_summary.md`
- `.ai-loop/repo_map.md`

## Goal
Modify `scripts/ai_loop_auto.ps1` so that `Stage-SafeProjectFiles` and the `git_status.txt` written by `Save-TestAndDiff` both respect the same scoped file set: always include **DurableAlwaysCommit** (the `.ai-loop/` subset of `SafeAddPaths`) and include other `SafeAddPaths` entries only when they appear in the `## Files in scope` section of `.ai-loop/task.md` (**ActiveScope**). This prevents concurrent unrelated working-tree files ÔÇö such as `tasks/user_ask_*.md` created by a parallel agent ÔÇö from being staged into the current task's commit or appearing in Codex review artifacts.

## Scope
Allowed:
- Add `$DurableAlwaysCommitPaths` array in `ai_loop_auto.ps1` (`.ai-loop/` entries from SafeAddPaths)
- Add `Get-ActiveScope` helper in `ai_loop_auto.ps1` parsing `## Files in scope` bullets from `.ai-loop/task.md` (reuse regex already used by C12 helpers)
- Add `Test-PathUnderSafeAddEntry` helper: checks whether a resolved path falls under any SafeAddPaths entry
- Modify `Stage-SafeProjectFiles`: stage `$DurableAlwaysCommitPaths` unconditionally; for non-durable paths, iterate `ActiveScope` entries and stage each only when it is covered by a `SafeAddPaths` entry; skip staging entire SafeAddPaths directory blobs when they are not DurableAlwaysCommit
- Modify `Save-TestAndDiff`: after running `git status --porcelain`, filter output lines to only include paths in the stage set before writing `git_status.txt`; leave `last_diff.patch` and `diff_summary.txt` unfiltered (`git diff HEAD` is naturally scoped to tracked changes)
- Brief wording addition to `templates/codex_review_prompt.md` noting `git_status.txt` is pre-filtered to task scope plus durable paths
- `AGENTS.md`: add a paragraph under "Safe paths" documenting the DurableAlwaysCommit / ActiveScope distinction
- `docs/safety.md`: add a paragraph describing the new stage-set formula
- `docs/architecture.md`: add DD-024 entry
- `tests/test_orchestrator_validation.py`: add/update tests (see Tests section)

Not allowed:
- Changing Codex verdict parsing
- Deleting, reverting, or moving any `tasks/**` file
- Weakening or removing C12 guards (`Test-FixPromptArtifactsTasksConflict`, `Stop-UnsafeQueueCleanup`, `Test-WorkingTreeTasksConflictWithScope`)
- Making staging destructive
- Running live Codex/Cursor/Claude CLIs
- Git commit or push
- Editing `ai_loop.py`
- Editing `docs/archive/**` or `.ai-loop/_debug/**`
- Changing `scripts/ai_loop_task_first.ps1` scope-parsing logic (separate path; no changes needed)
- Changing `SafeAddPaths` literal values

## Files in scope
- `scripts/ai_loop_auto.ps1`
- `templates/codex_review_prompt.md`
- `docs/safety.md`
- `docs/architecture.md`
- `AGENTS.md`
- `tests/test_orchestrator_validation.py`

## Files out of scope
- `docs/archive/**`
- `.ai-loop/_debug/**`
- `ai_loop.py`
- `scripts/ai_loop_task_first.ps1`
- `scripts/continue_ai_loop.ps1`
- `docs/workflow.md`
- `docs/decisions.md`
- `templates/task.md`

## Required behavior

1. **Define `$DurableAlwaysCommitPaths`**: a script-level array in `ai_loop_auto.ps1` listing the `.ai-loop/` paths from `SafeAddPaths`: `.ai-loop/task.md`, `.ai-loop/implementer_summary.md`, `.ai-loop/project_summary.md`, `.ai-loop/repo_map.md`, `.ai-loop/failures.md`, `.ai-loop/archive/rolls/`, `.ai-loop/_debug/session_draft.md`.

2. **Add `Get-ActiveScope`**: reads `.ai-loop/task.md`, extracts bullet lines from `## Files in scope` (strip leading `- ` and trailing `(new...)` annotations), and returns them as a string array. If the section is absent or yields no entries, return an empty array (fail-closed: callers treat missing scope as empty).

3. **Add `Test-PathUnderSafeAddEntry`**: given a candidate path string and the SafeAddPaths list, return `$true` if the path starts with (or equals) any SafeAddPaths entry after normalizing separators. Used to prevent ActiveScope entries from staging paths outside the allowlist.

4. **Modify `Stage-SafeProjectFiles`**:
   - First pass: `git add` each entry in `$DurableAlwaysCommitPaths` when the path exists (unchanged from existing behavior for these entries).
   - Second pass: call `Get-ActiveScope`; for each entry in ActiveScope, if `Test-PathUnderSafeAddEntry` is true and the path is not already covered by `$DurableAlwaysCommitPaths`, call `git add` on it.
   - Do **not** call `git add` on directory-blob SafeAddPaths entries (e.g., `tasks/`, `scripts/`) that are not in `$DurableAlwaysCommitPaths` and not present verbatim in ActiveScope.
   - If ActiveScope is empty, emit a warning `[scope-filter] ActiveScope is empty; staging durable paths only.` and stage only DurableAlwaysCommit paths.

5. **Modify `Save-TestAndDiff`**:
   - After running `git status --porcelain`, filter each output line: keep the line if its path component falls under `$DurableAlwaysCommitPaths` or passes `Test-PathUnderSafeAddEntry` AND the path prefix is in `ActiveScope Ôê¬ DurableAlwaysCommitPaths`. Unrecognized / out-of-scope paths are silently excluded.
   - Write the filtered lines to `git_status.txt`.
   - `last_diff.patch` (`git diff HEAD`) and `diff_summary.txt` (`git diff --stat HEAD`) remain unfiltered; untracked files do not appear in tracked-file diffs so no filtering is needed there.

6. **Update `templates/codex_review_prompt.md`**: add one sentence near the `git_status.txt` reference noting it is pre-filtered to the task's `## Files in scope` plus durable orchestrator state paths; out-of-scope concurrent working-tree files are intentionally excluded.

7. **Update `AGENTS.md` safe-paths section**: document the three-set model (DurableAlwaysCommit / ActiveScope / SafeAddPaths) and the fail-closed behavior when `## Files in scope` is missing.

8. **Update `docs/safety.md`**: add or expand a paragraph describing the stage-set formula:  
   `Stage set = DurableAlwaysCommit Ôê¬ (ActiveScope Ôê® SafeAddPaths)`  
   with the fail-closed rule for missing scope.

9. **Add DD-024 to `docs/architecture.md`** ┬º12: "Scope-filtered staging and review artifacts ÔÇö Stage set narrows to DurableAlwaysCommit Ôê¬ (ActiveScope Ôê® SafeAddPaths); git_status.txt pre-filtered to same set."

## Tests

Add to `tests/test_orchestrator_validation.py`:

- **`test_scope_filter_excludes_tasks_user_ask`**: PowerShell subprocess (or dot-source harness) ÔÇö given a task.md whose `## Files in scope` does not list `tasks/user_ask_foo.md`, verify that `Stage-SafeProjectFiles` does not invoke `git add tasks/user_ask_foo.md`.
- **`test_scope_filter_includes_explicit_tasks_file`**: given a task.md whose `## Files in scope` explicitly lists `tasks/016_feature.md`, verify it is staged.
- **`test_durable_paths_always_staged`**: given a task.md with an empty `## Files in scope`, verify that `.ai-loop/task.md` and `.ai-loop/project_summary.md` are still staged.
- **`test_git_status_filtered`**: verify that `git_status.txt` after `Save-TestAndDiff` does not include an out-of-scope `tasks/user_ask_foo.md` line, while an in-scope path (e.g., `scripts/ai_loop_auto.ps1`) is retained.
- **`test_missing_scope_section_fail_closed`**: task.md with no `## Files in scope` section ÔåÆ `Get-ActiveScope` returns empty array ÔåÆ staging warning emitted; only durable paths are staged.

Run full suite: `python -m pytest -q`

## Verification

```powershell
# PowerShell parse check
powershell -NoProfile -Command "[void][System.Management.Automation.Language.Parser]::ParseFile('scripts\ai_loop_auto.ps1', [ref]`$null, [ref]`$null)"

# Full test suite
python -m pytest -q

# Targeted new tests
python -m pytest -q tests/test_orchestrator_validation.py -k "scope_filter or durable_paths or git_status_filtered or missing_scope"
```

## Implementer summary requirements

1. List every function added or modified in `scripts/ai_loop_auto.ps1` with a one-line description.
2. Confirm parse check passes for `ai_loop_auto.ps1`.
3. Report pytest count (passing / total); call out any new test failures.
4. Note any behavior that could not be tested without a live git repo (explain workaround or skip).
5. List any items skipped with reason.

## Project summary update

Record under "Last Completed Task": scope-filtered staging and review artifacts landed (DD-024); `Stage-SafeProjectFiles` now stages only DurableAlwaysCommit unconditionally, plus ActiveScope Ôê® SafeAddPaths; `git_status.txt` filtered to same set; fail-closed when `## Files in scope` is absent.

## Output hygiene

- Do not duplicate task content into `implementer_summary.md`.
- Do not write debug output to `.ai-loop/_debug/` unless `-WithWrapUp` is active.
- Do not commit or push.
- Do not write to `docs/archive/`.

## Important

**Architect notes on divergence from user's proposal:**

- `Architect note:` The user proposed the stage set as `DurableAlwaysCommit + ((SafeAddPaths ÔêÆ DurableAlwaysCommit) Ôê® ActiveScope)`. The implementation realization inverts the iteration order: instead of iterating SafeAddPaths and intersecting with ActiveScope (which requires directory-expansion logic), iterate ActiveScope and check each entry against SafeAddPaths via `Test-PathUnderSafeAddEntry`. Result is identical but avoids enumerating filesystem contents of directory blobs.

- `Architect note:` `last_diff.patch` and `diff_summary.txt` are intentionally left unfiltered. `git diff HEAD` operates on tracked files only; new untracked files (the primary concern) do not appear. Filtering diff output would require path-scoped `git diff HEAD -- <paths>` which risks silently excluding legitimate tracked changes; the risk/benefit does not justify the complexity.

- `Architect note:` `docs/workflow.md` is excluded from scope. The behavioral change is adequately documented in `AGENTS.md` and `docs/safety.md`; `workflow.md` describes the high-level orchestration steps and does not need updating for this internal staging refinement.

- `Architect note:` `scripts/ai_loop_task_first.ps1` is excluded. It already has its own scope-parsing for the preflight check. The `Get-ActiveScope` function added here lives in `ai_loop_auto.ps1` and is not shared; duplication is intentional to avoid cross-script coupling. If both parsers diverge, a future consolidation task can factor them out.

**Behavioral change to flag for human reviewer:**  
Currently, when `## Files in scope` is absent, `Stage-SafeProjectFiles` stages everything in `SafeAddPaths` (including `tasks/`, `scripts/`, etc.). After this change, missing scope ÔåÆ only `DurableAlwaysCommit` is staged. This is intentional (fail-closed per user's constraint) but is a breaking change for any workflow that relies on omitting `## Files in scope` to stage all modified paths. The warning message (step 4) makes the behavior visible in console output. If this is too aggressive, the reviewer may relax it to "missing scope ÔåÆ stage all SafeAddPaths (current behavior)" by amending Required behavior step 4 before handing to the implementer.

**Size warning:** This task touches approximately 55ÔÇô70 lines of new/modified PowerShell plus minor doc edits. If the implementer's diff exceeds 80 lines of PS1, they must stop, split the remaining work into a follow-on task, and submit what is complete and tested.

**C12 interaction:** The existing `Test-WorkingTreeTasksConflictWithScope` / `Test-FixPromptArtifactsTasksConflict` / `Stop-UnsafeQueueCleanup` guards must remain intact and are not replaced by this change. This task adds a proactive filter layer; C12 remains the reactive guard.
