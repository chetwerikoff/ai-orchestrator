# Task: Fix Commit-And-Push working-tree guard for tasks/ queue files

## Project context

Required reading before starting:

1. `AGENTS.md`
2. `.ai-loop/task.md`
3. `.ai-loop/project_summary.md`
4. `scripts/ai_loop_auto.ps1` — focus on `Commit-And-Push`, `Stage-SafeProjectFiles`, `Get-WorkingTreeTasksPathsRelative`, `Test-WorkingTreeTasksConflictWithScope`, `Stop-UnsafeQueueCleanup`

## Goal

`Commit-And-Push` currently blocks any PASS-verdict commit when untracked
`tasks/*.md` files exist in the working tree — even if those files are
concurrent queue entries created by the planner in parallel and would never be
staged or committed by the current task. This causes loops to exit with
`UNSAFE_QUEUE_CLEANUP` after a clean PASS, requiring manual workarounds.

Fix the guard so that untracked `tasks/` queue files do not block PASS commits.
The reactive fix-prompt guard (in `Extract-FixPrompt`) must remain intact.

## Root cause

Two separate problems interact:

1. `Stage-SafeProjectFiles` runs `git add tasks/` unconditionally when `tasks/`
   is in `SafeAddPaths`, which stages untracked `tasks/*.md` files regardless
   of active task scope.
2. `Test-WorkingTreeTasksConflictWithScope` (called from `Commit-And-Push`)
   collects **both** tracked changes AND untracked files under `tasks/` and
   blocks the commit if any exist outside scope — even after the PASS verdict
   and before staging runs.

## Required behavior

1. **Remove the `Test-WorkingTreeTasksConflictWithScope` call from
   `Commit-And-Push`** (lines 1522–1530). The working-tree pre-commit gate is
   the wrong abstraction: untracked files that will not be staged pose no
   commit risk, and the check fires before staging happens anyway.

2. **Fix `Stage-SafeProjectFiles`** to skip the `tasks/` prefix when the
   active `task.md ## Files in scope` does not include `tasks/` or a specific
   `tasks/…` path. Use `Test-TaskMdScopeAllowsTasksQueue` (already present)
   to decide. Paths in `$script:DurableAlwaysCommitPaths` are never gated and
   must always be staged as before.

   Concrete rule:
   - For each path in `Get-SafeAddPathList`:
     - If the path starts with `tasks/` or `tasks\` **and**
       `Test-TaskMdScopeAllowsTasksQueue` returns `$false` → skip `git add`
       for that path; emit a one-line `Write-Host` noting it was skipped.
     - Otherwise stage as before.

3. **`Test-WorkingTreeTasksConflictWithScope` and
   `Get-WorkingTreeTasksPathsRelative`** — keep the functions; they are still
   used by the fix-prompt guard path. Do not delete them.

4. **No behavior change** to `Extract-FixPrompt` / `Stop-UnsafeQueueCleanup`
   — the reactive guard that blocks when Codex fix-prompt targets `tasks/`
   paths must remain intact.

5. **Update `.ai-loop/project_summary.md`** to record that the working-tree
   commit gate was removed from `Commit-And-Push` and replaced by scope-gated
   staging in `Stage-SafeProjectFiles`.

## Scope

Allowed:
- Edit `scripts/ai_loop_auto.ps1` — `Commit-And-Push` and `Stage-SafeProjectFiles`
- Edit `tests/test_orchestrator_validation.py` — update/add unit tests
- Edit `.ai-loop/project_summary.md`
- Edit `.ai-loop/implementer_summary.md`

Not allowed:
- Changing `Extract-FixPrompt`, `Test-FixPromptArtifactsTasksConflict`,
  `Stop-UnsafeQueueCleanup` (fix-prompt guard must stay)
- Changing `templates/codex_review_prompt.md`
- Changing `scripts/ai_loop_task_first.ps1` or `scripts/ai_loop_plan.ps1`
- Deleting `Test-WorkingTreeTasksConflictWithScope` or
  `Get-WorkingTreeTasksPathsRelative`
- `docs/archive/**`, `.ai-loop/_debug/**`, `ai_loop.py`
- `tasks/**` (protected queue specs; do not edit)
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

- Existing tests must continue to pass (`python -m pytest -q`).
- Add unit tests covering:
  1. `Stage-SafeProjectFiles` skips `tasks/` when scope omits `tasks/` (mock
     `git add` or test the gating logic in isolation).
  2. `Stage-SafeProjectFiles` stages `tasks/` when scope includes `tasks/`.
  3. `Commit-And-Push` does NOT call `Stop-UnsafeQueueCleanup` when
     `tasks/*.md` files are untracked and scope omits `tasks/`.

## Important

- Keep the change small. Target ≤ 40 new/modified lines of PowerShell.
- Do not add new parameters to `Stage-SafeProjectFiles` or `Commit-And-Push`
  beyond what is needed to read the active `task.md` path (already available
  via `$AiLoop` module-level variable).
- After the fix, a PASS verdict with untracked `tasks/user_ask_*.md` files in
  the working tree must proceed to commit without error.
