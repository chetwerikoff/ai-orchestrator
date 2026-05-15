# Task: Protect queued task specs from unintended deletion

## Project context

Required reading:
- `AGENTS.md` ÔÇö working rules and Git hygiene policy
- `.ai-loop/project_summary.md` ÔÇö durable design decisions
- `templates/codex_review_prompt.md` ÔÇö Codex instruction template
- `templates/task.md` ÔÇö task contract template

## Goal

Add explicit agent instructions to prevent Codex and other reviewers from recommending deletion or modification of queued task specifications under `tasks/` unless the active task explicitly includes `tasks/` or that specific file in scope. Queued specs are committed via `SafeAddPaths` as durable project state; this task documents the protection rule in agent-facing templates and durable project context so reviewers understand they are not scratch files to be deleted during cleanup.

## Scope

Allowed:
- Add protection rule to `AGENTS.md` Git hygiene section
- Add scope-drift warning to `templates/codex_review_prompt.md` (Codex instructions)
- Add output hygiene reminder to `templates/task.md`
- Add test assertions that the protection rule exists in both AGENTS.md and codex prompt
- Add durable design note to `.ai-loop/project_summary.md`
- Update `tests/test_orchestrator_validation.py` with new test functions

Not allowed:
- Modify `SafeAddPaths` literal or its deployment in scripts
- Change git staging or commit logic
- Delete existing queued task specs under `tasks/`
- Add new subsystems or abstractions

## Files in scope

- `AGENTS.md`  Git hygiene: add queued task spec protection rule
- `templates/codex_review_prompt.md`  Add scope-drift rule for tasks/ files
- `templates/task.md`  Output hygiene: add reminder about queued specs
- `tests/test_orchestrator_validation.py`  Add assertion tests
- `.ai-loop/project_summary.md`  Add durable design note

## Files out of scope

- `docs/archive/**`
- `.ai-loop/_debug/**`
- `ai_loop.py`
- `scripts/` (no code changes to orchestrator logic)
- Existing queued task specs under `tasks/` (leave unmodified)
- `SafeAddPaths` deployment locations in `scripts/ai_loop_auto.ps1`, `scripts/ai_loop_task_first.ps1`, `scripts/continue_ai_loop.ps1`, `docs/safety.md`

## Required behavior

1. **AGENTS.md**: Add a Git hygiene bullet stating:
   - Queued task specs under `tasks/` are protected from deletion/modification unless the active `.ai-loop/task.md` explicitly includes `tasks/` or that file in `## Files in scope`
   - Untracked `tasks/*.md` files are intentional queue specs, not scratch files; agents must not recommend deletion without explicit scope

2. **templates/codex_review_prompt.md**: Add an explicit instruction block:
   - Codex must not suggest deletion or modification of `tasks/*.md` files unless the active task includes `tasks/` or that specific file in `## Files in scope` and requests queue cleanup
   - Rationale: these are queued task specifications maintained by the planner, not scratch/temporary files

3. **templates/task.md**: Add output hygiene bullet:
   - Implementer reminder: do not delete queued task specs under `tasks/` unless the active task explicitly requests it in scope

4. **tests/test_orchestrator_validation.py**: Add two new test functions:
   - `test_agents_protects_queued_tasks()` ÔÇö asserts protection language exists in `AGENTS.md` (e.g., "tasks/" and "protected" or "queued")
   - `test_codex_prompt_protects_queued_tasks()` ÔÇö asserts scope-drift warning exists in `templates/codex_review_prompt.md` (e.g., "tasks/" and "scope" in same context)

5. **`.ai-loop/project_summary.md`**: Add a concise design note under "Important Design Decisions":
   - Queued task specs under `tasks/` are protected from deletion/modification in agent instructions (AGENTS.md, codex_review_prompt.md) unless the active task explicitly includes them in scope

## Tests

```powershell
python -m pytest tests/test_orchestrator_validation.py::test_agents_protects_queued_tasks -v
python -m pytest tests/test_orchestrator_validation.py::test_codex_prompt_protects_queued_tasks -v
python -m pytest -q
```

Verify:
- New test functions pass (simple string presence checks)
- All existing tests continue to pass

## Verification

1. Run `python -m pytest tests/test_orchestrator_validation.py -q` ÔÇö all tests pass
2. Manually inspect `AGENTS.md` ÔÇö Git hygiene section contains new bullet about `tasks/` protection
3. Manually inspect `templates/codex_review_prompt.md` ÔÇö contains instruction about not recommending `tasks/` file deletion unless in scope
4. Manually inspect `templates/task.md` ÔÇö output hygiene section includes reminder about queued specs
5. Manually inspect `.ai-loop/project_summary.md` ÔÇö durable note on task queue protection is present
6. `grep -r "tasks/" AGENTS.md templates/codex_review_prompt.md` ÔÇö confirms both files mention `tasks/` protection

## Implementer summary requirements

After implementation:

1. **Changed files**: 5 files modified
   - `AGENTS.md`: 1 new Git hygiene bullet (~3ÔÇô4 lines)
   - `templates/codex_review_prompt.md`: scope-drift instruction (~3ÔÇô4 lines)
   - `templates/task.md`: output hygiene reminder (~2 lines)
   - `tests/test_orchestrator_validation.py`: 2 new test functions (~12ÔÇô15 lines)
   - `.ai-loop/project_summary.md`: 1 durable design note (~2ÔÇô3 lines)

2. **Test result**: All tests pass; new assertions confirm protection rule language is present in AGENTS.md and codex_review_prompt.md

3. **Implemented work**: Added agent instructions and durable documentation to protect queued task specs under `tasks/` from unintended deletion. Codex and implementer now have explicit rules (via templates and AGENTS.md) to avoid suggesting `tasks/` file deletions unless the active task explicitly includes them in scope. Git staging protection via `SafeAddPaths` remains as second line of defense.

4. **Skipped items**: None

5. **Remaining risks**:
   - Agent behavior depends on prompt compliance; outdated or misconfigured agents may not respect the new instructions (mitigation: `SafeAddPaths` provides git-layer protection regardless)
   - Human users can still manually delete queued specs outside the agent loop; this rule guides agent recommendations only

## Project summary update

Add one bullet under "Important Design Decisions" or "Current Stage":

```
- **Task queue protection**: Queued task specs under `tasks/` are protected from 
  deletion/modification in agent instructions unless the active `.ai-loop/task.md` 
  explicitly includes `tasks/` or the specific file in scope. Git staging (SafeAddPaths) 
  provides final protection; review-layer instructions prevent Codex from recommending 
  unintended cleanup.
```

Or more concise:

```
- **C12 Task queue protection**: Queued task specs under `tasks/` protected in AGENTS.md 
  and codex_review_prompt.md from deletion/modification unless active task includes them 
  in scope.
```

## Output hygiene

- Do not add multi-paragraph narrative to `.ai-loop/project_summary.md` ÔÇö one concise bullet note only
- Do not write debug output to `.ai-loop/_debug/`
- Do not commit anything other than the five modified files
- Do not move or delete existing queued task specs

## Important

- **Architect decision (adopting user proposal)**: The user's proposed approach is sound and aligns with project conventions. AGENTS.md documents working rules; templates guide agent behavior; project_summary.md records durable design decisions. This task uses all three to add review-layer defense for queued task specs. No divergence from the user's proposal.

- **Why this approach**: `SafeAddPaths` protects `tasks/` files at the git staging layer, preventing accidental deletion during commit. However, Codex review happens *before* staging and can recommend deletion without knowing `tasks/` are durable queue specs. This task adds instructional protection (agent-facing prompt language) so reviewers understand the boundary and do not recommend unintended cleanup.

- **Scope distinction**: The rule explicitly allows legitimate queue modification when the active task includes `tasks/` in scope (e.g., "clean up old queue entries"). It blocks Codex from suggesting deletion without that explicit scope ÔÇö defense-in-depth.

- **Test strategy**: New assertions use simple string presence checks (`"tasks/" in file_content and "scope" in file_content`, etc.). No parsing or complex logic required; the goal is to verify the protection language was written, not to enforce behavior.

- **No existing queue deletion**: Per the user's explicit boundary, existing untracked task files under `tasks/` must not be deleted as part of this task. Any existing queue spec is treated as intentional and protected.

## Order

Standalone task; no dependencies.
