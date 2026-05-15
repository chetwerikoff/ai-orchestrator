# Task: add -WithDraft Cursor brief pass to planner

## Project context
- `AGENTS.md`
- `.ai-loop/task.md`
- `.ai-loop/project_summary.md`
- `.ai-loop/repo_map.md`

## Goal
Add an optional `-WithDraft` flag to `scripts/ai_loop_plan.ps1` that runs a read-only Cursor brief pass before Claude planning. When enabled, Cursor ingests the raw ASK and project context, produces a compact advisory markdown brief saved to `.ai-loop/task_draft_brief.md` (gitignored, non-fatal), and that brief is appended to Claude's planner prompt as advisory-only input under a clearly labelled section. Strengthen `templates/planner_prompt.md` so Claude is explicitly reminded to optimize for the best project architecture rather than mechanically translate the user's proposal or the Cursor brief.

## Scope
Allowed:
- Add `-WithDraft` switch and optional `-DraftCommand` string parameter to `scripts/ai_loop_plan.ps1`
- Create `templates/draft_brief_prompt.md` (Cursor draft brief prompt template)
- Strengthen `templates/planner_prompt.md` with explicit architect-optimizes language and advisory brief handling
- Update `scripts/install_into_project.ps1` to copy `draft_brief_prompt.md` into target projects
- Add `.ai-loop/task_draft_brief.md` to `.gitignore`
- Add tests in `tests/test_orchestrator_validation.py`
- Update `AGENTS.md` and `.ai-loop/project_summary.md` to document the new flag
- Minor mention in `docs/workflow.md`

Not allowed:
- Creating a separate `ai_loop_draft.ps1` script
- Creating a new `run_cursor_draft.ps1` wrapper script
- Modifying `ai_loop_auto.ps1`, `ai_loop_task_first.ps1`, `continue_ai_loop.ps1`, or reviewer logic
- Changing implementer or reviewer behavior after `task.md` is created
- Replacing Claude as the final planner/architect
- OS-level sandboxing or file-system monitoring to enforce draft read-only
- Vector indexes, embedding stores, or AST symbol indexes

## Files in scope
- `scripts/ai_loop_plan.ps1`
- `scripts/install_into_project.ps1`
- `templates/draft_brief_prompt.md` (new)
- `templates/planner_prompt.md`
- `tests/test_orchestrator_validation.py`
- `AGENTS.md`
- `.gitignore`
- `.ai-loop/project_summary.md`
- `docs/workflow.md`

## Files out of scope
- `docs/archive/**`
- `.ai-loop/_debug/**`
- `ai_loop.py`
- `scripts/ai_loop_auto.ps1`
- `scripts/ai_loop_task_first.ps1`
- `scripts/continue_ai_loop.ps1`
- `scripts/run_cursor_agent.ps1`
- `scripts/run_opencode_agent.ps1`
- All other implementer, reviewer, or scout scripts

## Required behavior

1. **`-WithDraft` and `-DraftCommand` parameters**: `ai_loop_plan.ps1` gains a `-WithDraft` switch and a `-DraftCommand` string (default: `"run_cursor_agent.ps1"`). When `-WithDraft` is absent, all existing behavior is unchanged.

2. **Draft prompt construction**: When `-WithDraft` is set, build the draft prompt by concatenating in order: (a) draft brief prompt template ÔÇö prefer `.ai-loop/draft_brief_prompt.md` when present in the working directory, falling back to `templates/draft_brief_prompt.md`; this is the same local-override pattern used for `planner_prompt.md` in `ai_loop_plan.ps1`; (b) the contents of `AGENTS.md`; (c) the contents of `.ai-loop/project_summary.md`; (d) the contents of `.ai-loop/repo_map.md`; (e) the raw ASK content (same source already used for the planner prompt).

3. **Draft pass execution**: Resolve `-DraftCommand` using the same path-lookup logic as `-PlannerCommand` (look beside `ai_loop_plan.ps1` in `$PSScriptRoot`). Pipe the draft prompt to the resolved wrapper. Capture stdout as the brief. Treat a non-zero exit code as a non-fatal failure: emit `Write-Warning "[plan] -WithDraft: draft command exited with error; proceeding without brief."` and set brief to `$null`.

4. **Output validation**: If the brief (trimmed) is fewer than 50 bytes, emit `Write-Warning "[plan] -WithDraft: draft returned too-short output; proceeding without brief."` and set brief to `$null`. Do not exit non-zero.

5. **Save brief**: When brief is non-null, write it to `.ai-loop/task_draft_brief.md` (UTF-8, overwrite). Log `[plan] Draft brief written to .ai-loop/task_draft_brief.md`.

6. **Inject into Claude prompt**: When brief is non-null, append the following block *after* the raw ASK content in the prompt string sent to Claude ÔÇö never before canonical context:

   ```
   ---
   ## Cursor Draft Brief (advisory ÔÇö read-only pre-pass)
   The section below is an advisory brief produced by a read-only Cursor draft pass.
   Claude must treat it as a hint only. It does not override AGENTS.md, project_summary.md,
   repo_map.md, or Claude's architectural judgment. If it conflicts with canonical context,
   ignore it and note the conflict in ## Important.

   <brief content here>
   ```

7. **`templates/draft_brief_prompt.md`** (new file): Instructions for Cursor to perform a read-only analysis and output a compact brief. Must include: (a) role statement ÔÇö advisory read-only pass, do not edit files, do not write `.ai-loop/task.md`, output only a markdown brief; (b) the fixed output format with sections `## User intent`, `## Relevant project facts`, `## Relevant files`, `## Suggested scope` (Allowed / Not allowed bullets), `## Verification candidates`, `## Open questions / risks`; (c) conciseness target: under 300 words; (d) reminder that Claude has final architectural say.

8. **`templates/planner_prompt.md` strengthening**: Reinforce, do not rewrite. Add or strengthen the following without removing existing "final say" language or the `Architect note:` divergence convention:
   - In the "You are the architect ÔÇö final say" section: make explicit that Claude's job is to produce the *optimal architecture for the project*, not to translate the user's proposal or the Cursor brief.
   - Add one sentence near the top of the "You are the architect" section: `"A Cursor Draft Brief (when present under ## Cursor Draft Brief) is advisory only. If it conflicts with canonical context or your judgment, ignore it and explain in ## Important."`
   - Require that `## Important` names every meaningful divergence from user or Cursor suggestions with a one-line `Architect note:` prefix.

9. **`install_into_project.ps1`**: Add `draft_brief_prompt.md` to the list of template files copied to target projects, following the same copy pattern used for `planner_prompt.md`, `reviewer_prompt.md`, and `user_ask_template.md`.

10. **`.gitignore`**: Add `.ai-loop/task_draft_brief.md` in the existing runtime-artifacts section alongside other gitignored `.ai-loop/` outputs.

## Tests
Add to `tests/test_orchestrator_validation.py`:
- Parse-check `scripts/ai_loop_plan.ps1` succeeds (existing test; verify it still passes after parameter addition)
- `templates/draft_brief_prompt.md` exists and is non-empty
- `scripts/ai_loop_plan.ps1` source text contains the string `WithDraft` (parameter presence smoke test)
- `scripts/ai_loop_plan.ps1` source text contains `task_draft_brief.md` (brief-save path smoke test)
- `scripts/ai_loop_plan.ps1` source text contains `proceeding without brief` (non-fatal degradation path smoke test ÔÇö covers both warning messages from steps 3 and 4)
- `scripts/ai_loop_plan.ps1` source text contains `Cursor Draft Brief` (prompt-injection label smoke test)
- `.gitignore` contains the string `task_draft_brief.md`
- `scripts/install_into_project.ps1` source text references `draft_brief_prompt.md` (install contract smoke test)

Run: `python -m pytest -q`

## Verification
```powershell
# Parse check
powershell -NoProfile -Command "[void][System.Management.Automation.Language.Parser]::ParseFile('scripts\ai_loop_plan.ps1', [ref]$null, [ref]$null)"

# Confirm -WithDraft appears in script
Select-String -Path scripts\ai_loop_plan.ps1 -Pattern 'WithDraft'

# Confirm template file created
Test-Path templates\draft_brief_prompt.md

# Run tests
python -m pytest -q
```

## Implementer summary requirements
1. Files changed and a one-line description of each change
2. Test result: pass count and any failures
3. How the draft prompt is assembled and where in the Claude prompt the brief is injected
4. Whether `-DraftCommand` path resolution follows the same logic as `-PlannerCommand` (confirm or note difference)
5. Any step from Required behavior that was skipped or modified, with reason

## Project summary update
Record under **Current Architecture**:
- `scripts/ai_loop_plan.ps1` now accepts `-WithDraft [-DraftCommand run_cursor_agent.ps1]`; when set, runs a read-only Cursor draft brief pass before Claude, saves output to `.ai-loop/task_draft_brief.md` (gitignored, non-fatal on short/empty output), and injects it as an advisory `## Cursor Draft Brief` section at the end of the Claude planner prompt.
- `templates/draft_brief_prompt.md` added: Cursor draft brief prompt template; installed into target projects by `install_into_project.ps1`.

Record under **Current Stage**: C11 complete ÔÇö optional `-WithDraft` Cursor advisory brief pass for `ai_loop_plan.ps1`; `templates/planner_prompt.md` strengthened with explicit architect-optimizes language.

## Output hygiene
- Do not duplicate task content into `project_summary.md`; update only the designated summary fields.
- Do not write to `.ai-loop/_debug/`.
- Do not commit; the orchestrator handles staging.
- Do not write to `docs/archive/`.

## Important
**Architect note: Option 2 (`-WithDraft` flag on `ai_loop_plan.ps1`) chosen over Option 1 (separate `ai_loop_draft.ps1` script).**
Reason: directly matches the established `-WithScout`, `-WithReview`, `-WithWrapUp` convention on existing scripts; keeps all planner invocation logic in one place; no new entry point for users to learn.

**Architect note: `run_cursor_agent.ps1` reused as the default `-DraftCommand` instead of creating a new `run_cursor_draft.ps1` wrapper.**
Reason: safety (read-only advisory) is enforced by the draft prompt content, not by a different binary. A near-duplicate wrapper adds files and a maintenance surface without behavioral benefit. The `-DraftCommand` parameter preserves flexibility for callers who want to use a different wrapper.

**Architect note: rejected [missing] OS-level read-only enforcement for the draft subprocess.**
Reason: sandboxing a subprocess against file writes is a non-trivial OS-level concern (monitoring, rollback on violation) that would add disproportionate complexity for an advisory pass. The existing scout pattern (`run_scout_pass.ps1`) also relies on prompt instructions for read-only safety, not OS enforcement. The draft brief prompt template explicitly instructs Cursor not to edit files; this is the consistent pattern in this project. Adding OS-level enforcement would violate the simplicity policy.

**Accepted reviewer issue [logic]:** Tests expanded beyond pure smoke checks to include source-text assertions for the brief-save path (`task_draft_brief.md`), the non-fatal degradation warning string (`proceeding without brief`), and the prompt-injection label (`Cursor Draft Brief`). These are fast, no-subprocess string-presence checks that give meaningful coverage of steps 3ÔÇô6 without requiring subprocess harness or blowing the line budget. Full subprocess integration tests for draft execution are deferred as they would require significant test infrastructure disproportionate to a non-fatal advisory feature.

**Fix applied (accepted from initial draft review):** Step 2 local-override precedence corrected ÔÇö prefer `.ai-loop/draft_brief_prompt.md` when present, fall back to `templates/draft_brief_prompt.md`, matching the existing `planner_prompt.md` override pattern.

**Assumption**: Draft pass failure (non-zero exit from the wrapper) is treated identically to too-short output ÔÇö warn and continue without brief. This mirrors the non-fatal degradation in `run_scout_pass.ps1` and the reviewer degradation in `ai_loop_plan.ps1`.

**Constraint**: The `## Cursor Draft Brief (advisory)` block must appear *after* the raw ASK content in Claude's prompt. Claude must read canonical context and the ASK before seeing the advisory brief.

**Constraint**: `templates/planner_prompt.md` changes must add to and reinforce existing text only ÔÇö no full rewrites. The existing `Architect note:` convention and "final say" framing must be preserved.

**Line budget note**: This task touches nine files. Actual logic additions in PowerShell are approximately 25ÔÇô30 lines in `ai_loop_plan.ps1`; the rest are small template additions, a one-line gitignore entry, install-script additions (~3 lines), and ~15 test lines. Total is near the ~80-line soft cap; implementer should resist scope creep.
