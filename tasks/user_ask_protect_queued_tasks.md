# User ASK

## Goal

Prevent Codex review and other agents from recommending deletion or modification of queued task specs under `tasks/` unless the active task explicitly includes those files in scope. `tasks/` is now in `SafeAddPaths`, but reviewers can still misclassify untracked `tasks/*.md` as scratch files and ask the implementer to delete them.

## Affected files (your best guess - planner will verify)

- `AGENTS.md`
- `templates/codex_review_prompt.md`
- `templates/task.md`
- `tests/test_orchestrator_validation.py`
- `.ai-loop/project_summary.md`

## Out-of-scope (explicit boundaries)

- `docs/archive/**`
- `.ai-loop/_debug/**`
- `ai_loop.py`
- Changing `SafeAddPaths` again
- Changing git staging implementation
- Deleting or editing existing queued task specs except this ASK file if needed

## Proposed approach (optional)

Add an explicit protection rule for queued task specs:

```md
Do not delete or modify files under `tasks/` unless the active `.ai-loop/task.md`
explicitly lists that exact file or `tasks/` in scope and asks for queue cleanup.
Untracked `tasks/*.md` are queued user specs, not scratch files.
```

Apply this rule in the places that agents/reviewers actually read:

1. `AGENTS.md`
   - Add a hard rule under Git hygiene or Working scope.
   - Make clear that untracked `tasks/*.md` may be intentional queued specs.

2. `templates/codex_review_prompt.md`
   - Tell Codex to treat deletion/modification of `tasks/*.md` as scope drift unless the active task includes `tasks/` or the exact file in `## Files in scope`.
   - Tell Codex not to ask implementers to delete queued task specs merely because they are untracked.

3. `templates/task.md`
   - Add an output hygiene bullet reminding implementers not to delete queued specs under `tasks/` unless explicitly requested.

4. Tests
   - Add or update tests that assert the protection rule exists in `AGENTS.md` and `templates/codex_review_prompt.md`.

5. `.ai-loop/project_summary.md`
   - Add a concise durable note that queued task specs under `tasks/` are protected from cleanup unless explicitly in scope.

## Constraints / context the planner may not know

- `SafeAddPaths` only controls what can be staged; it does not prevent reviewers from suggesting deletion.
- This task is about reviewer/agent instruction policy, not staging implementation.
- Keep the change small and textual. Do not introduce a new queue-management subsystem.
- Avoid broad "never touch tasks/" wording that would block legitimate queue maintenance. The rule should allow edits when the active task explicitly includes `tasks/` or the exact file in scope.
- Do not delete currently untracked task ASK files.
