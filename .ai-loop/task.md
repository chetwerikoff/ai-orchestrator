# Task: Fix-loop task queue protection guard

## Project context

- `AGENTS.md`
- `.ai-loop/task.md`
- `.ai-loop/project_summary.md`
- `.ai-loop/repo_map.md`

## Goal

Add a two-layer guard that prevents the fix loop from instructing the implementer to delete or revert `tasks/` queue specs that are not in the active task's scope. Layer 1 (proactive): strengthen `templates/codex_review_prompt.md` with prominent, unambiguous language so Codex stops recommending `tasks/` cleanup. Layer 2 (reactive): add an orchestrator-level check in `scripts/ai_loop_auto.ps1` that inspects the extracted fix-prompt JSON immediately after `Extract-FixPromptFromFile` and, when any `files` entry matches `tasks/` but that path is absent from the active task.md's `## Files in scope` section, halts the iteration with a distinct `UNSAFE_QUEUE_CLEANUP` status and a clear human-readable message rather than forwarding the instruction to the implementer.

## Scope

Allowed:
- Edit `templates/codex_review_prompt.md` ÔÇö reinforce task-queue-protection language
- Edit `scripts/ai_loop_auto.ps1` ÔÇö add a guard function and call site in the fix loop
- Edit `AGENTS.md` ÔÇö minor reinforcement of C12 wording
- Edit `tests/test_orchestrator_validation.py` ÔÇö add unit test for the new guard logic
- Edit `.ai-loop/project_summary.md` ÔÇö record C12 reactive guard as landed

Not allowed:
- Changing Codex verdict parsing or `Get-ReviewVerdict`
- Modifying `tasks/` files
- Changing `scripts/ai_loop_task_first.ps1` preflight logic
- Broad scope-gated staging redesign (tracked separately in `tasks/user_ask_scope_gated_review_and_staging.md`)
- Running live CLIs, git commit, or git push
- Any file under `docs/archive/**` or `.ai-loop/_debug/**`
- `ai_loop.py`

## Files in scope

- `templates/codex_review_prompt.md`
- `scripts/ai_loop_auto.ps1`
- `AGENTS.md`
- `tests/test_orchestrator_validation.py`
- `.ai-loop/project_summary.md`

## Files out of scope

- `docs/archive/**`
- `.ai-loop/_debug/**`
- `ai_loop.py`
- `tasks/**` (protected queue specs; do not edit)
- `scripts/ai_loop_task_first.ps1`
- `scripts/ai_loop_plan.ps1`
- `docs/decisions.md`

## Required behavior

1. **`templates/codex_review_prompt.md`** ÔÇö add a visually distinct block (e.g. `> PROTECTED:` blockquote or a `---` fenced rule) stating: files under `tasks/` are protected concurrent-work queue entries; do not recommend deleting, reverting, or "cleaning up" any `tasks/*.md` file unless the active `## Files in scope` section explicitly lists it or a `tasks/` glob. Violations of this rule make the review invalid. Place this block prominently (before or at the top of the reviewer's "out-of-scope / do not touch" guidance, not buried).

2. **`scripts/ai_loop_auto.ps1`** ÔÇö add a helper function `Test-FixPromptTasksConflict` with signature `param([object]$FixData, [string]$TaskMdPath)` that:
   a. Collects all file paths from `$FixData.files` (string array; tolerate `$null` gracefully with `@(...)`).
   b. Identifies any entry where the normalized path starts with `tasks/` or `tasks\` (case-insensitive).
   c. If none found, returns `$false` (no conflict).
   d. Reads `## Files in scope` lines from `$TaskMdPath` using `Select-String` or line split; if the section contains a bullet that includes the word `tasks` (case-insensitive), returns `$false` (task explicitly scoped into `tasks/`).
   e. Otherwise returns `$true` (protected-queue conflict detected).

3. **`scripts/ai_loop_auto.ps1`** ÔÇö immediately after the call to `Extract-FixPromptFromFile` (before invoking the implementer in the fix loop), call `Test-FixPromptTasksConflict`. If it returns `$true`:
   a. Write a `Write-Warning` message naming the conflicting `tasks/` paths.
   b. Write a human-readable summary to `.ai-loop/implementer_result.md` containing the text `UNSAFE_QUEUE_CLEANUP` and listing the offending paths.
   c. Break or `return` out of the current fix iteration (do not invoke the implementer).
   d. The loop's outer exit code should reflect a non-pass outcome (existing `FAIL` or an analogous non-zero path is acceptable; do not invent a new exit-code value).

4. **`AGENTS.md`** ÔÇö under the existing C12 entry in `## Important Design Decisions` (or wherever it appears), append one sentence: "A reactive orchestrator guard (`Test-FixPromptTasksConflict` in `ai_loop_auto.ps1`) enforces this at runtime: if the extracted fix-prompt JSON references `tasks/` paths not in scope, the iteration halts with `UNSAFE_QUEUE_CLEANUP` before the implementer is invoked."

5. **`tests/test_orchestrator_validation.py`** ÔÇö add at minimum two tests:
   - `test_fix_prompt_tasks_conflict_detected`: a PowerShell subprocess (or dot-source harness pattern already used in C02 tests) that sources `ai_loop_auto.ps1`, creates a synthetic `$FixData` object with a `files` array containing `tasks/some_task.md`, a task.md without `tasks/` in `## Files in scope`, calls `Test-FixPromptTasksConflict`, and asserts the return value is `$true`.
   - `test_fix_prompt_tasks_conflict_clear_when_in_scope`: same setup but task.md's `## Files in scope` includes a `tasks/` bullet; asserts return value is `$false`.

## Tests

- `python -m pytest -q` must pass with no regressions.
- New tests must pass: `test_fix_prompt_tasks_conflict_detected`, `test_fix_prompt_tasks_conflict_clear_when_in_scope`.
- PowerShell parse check must pass for `scripts/ai_loop_auto.ps1`:
  ```
  powershell -NoProfile -Command "[void][System.Management.Automation.Language.Parser]::ParseFile('scripts\ai_loop_auto.ps1', [ref]$null, [ref]$null)"
  ```

## Verification

```powershell
# Parse check
powershell -NoProfile -Command "[void][System.Management.Automation.Language.Parser]::ParseFile('scripts\ai_loop_auto.ps1', [ref]$null, [ref]$null)"
```

```
python -m pytest -q --tb=short
```

Manually confirm:
- `templates/codex_review_prompt.md` contains the `PROTECTED:` block within the first screenful of the file (or at a clearly prominent location).
- `AGENTS.md` contains the new sentence referencing `Test-FixPromptTasksConflict`.

## Implementer summary requirements

1. Changed files (brief description per file).
2. Test result: count passed/failed (`python -m pytest -q` output line).
3. Summary of implemented guard logic in `ai_loop_auto.ps1` (3ÔÇô5 lines).
4. Any items skipped with reason.
5. Remaining risks or follow-up items (1ÔÇô3 bullets).

## Project summary update

Record in `## Current Stage`: "C12 reactive guard landed: `Test-FixPromptTasksConflict` in `ai_loop_auto.ps1` halts the fix loop with `UNSAFE_QUEUE_CLEANUP` when extracted fix-prompt JSON references unscoped `tasks/` paths; `templates/codex_review_prompt.md` reinforced with prominent PROTECTED block."

Update `## Notes For Future AI Sessions` to include: "`Test-FixPromptTasksConflict` is the runtime enforcement of C12; it fires after `Extract-FixPromptFromFile` in the fix loop. Do not weaken or remove it without an explicit task."

## Output hygiene

- Do not duplicate task content into `.ai-loop/project_summary.md`.
- Do not write to `.ai-loop/_debug/` unless debugging raw output.
- Do not commit or push.
- Do not write to `docs/archive/`.

## Important

**Assumptions:**

- `$FixData.files` is the canonical place to find the file list in the JSON fix prompt (consistent with the existing `fix_required`, `files`, `changes[]` JSON schema documented in project_summary.md). The function should also check `$FixData.changes` entries for a `file` or `path` field as a secondary scan, in case Codex places paths there but not in `files`. Keep it simple: one pass over both locations with `@(...)` null guards.
- The existing dot-source harness pattern used for C02 PowerShell tests in `tests/test_orchestrator_validation.py` is the right template for the new tests. Follow that exact pattern rather than inventing a new subprocess approach.
- "Break out of the current fix iteration" means the fix-loop iteration exits without calling the implementer. The overall script should then proceed to its normal non-pass exit (existing behavior); no new exit code value is needed.

**Architect notes on divergence from user proposal:**

- `Architect note:` User proposed an option to "filter those `tasks/**` delete directives while preserving in-scope fix directives." This task uses a hard-halt (`UNSAFE_QUEUE_CLEANUP`) rather than filtering, because silently stripping Codex instructions risks hiding real bugs and leaves the loop in an undefined state. A human reviewer is the right gate when this fires; filtered-and-continued behavior can be added later if the halt proves too aggressive.
- `Architect note:` User listed `scripts/ai_loop_auto.ps1` changes as "before or around fix-prompt handling." This task specifies the insertion point precisely: immediately after `Extract-FixPromptFromFile`, before the implementer invocation, to avoid any ambiguity about where the guard fires.
- `Architect note:` `AGENTS.md` edit is a single appended sentence to the existing C12 entry, not a new section. Keeping it co-located with C12 avoids duplicating the explanation and matches the existing pattern for adding runtime enforcement notes.
