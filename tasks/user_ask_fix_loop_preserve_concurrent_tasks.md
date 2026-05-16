# User ASK

## Goal

Prevent the fix loop from deleting or reverting concurrent `tasks/` user asks or queue specs that are unrelated to the active task.

When Codex returns `FIX_REQUIRED` because unrelated `tasks/*.md` files are present in the working tree, the orchestrator/implementer should not treat those files as disposable cleanup. They are often intentional queued work created by another agent while the current task is running.

## Affected files (your best guess - planner will verify)

- `templates/codex_review_prompt.md`
- `scripts/ai_loop_auto.ps1`
- `AGENTS.md`
- `.ai-loop/project_summary.md`
- `tests/test_orchestrator_validation.py`

## Out-of-scope (explicit boundaries)

- `docs/archive/**`
- `.ai-loop/_debug/**`
- `ai_loop.py`
- Deleting or moving existing `tasks/**` files
- Broad scope-gated staging redesign if it should be handled by `user_ask_scope_gated_review_and_staging.md`
- Changing Codex verdict parsing
- Running live Codex/Cursor/Claude CLIs
- Git commit or push

## Proposed approach (optional)

Add a narrow guard before or around fix-prompt handling:

1. If Codex asks to delete or revert files under `tasks/**` that are not listed in the active task's `## Files in scope`, treat that request as unsafe concurrent-work cleanup.
2. Do not pass such delete/revert instructions through to the implementer as-is.
3. Prefer stopping for human review with a clear final status, or filtering those `tasks/**` delete directives while preserving in-scope fix directives.
4. Update Codex review prompt guidance so out-of-scope `tasks/user_ask_*.md` files should be ignored as concurrent queue entries, not deleted, unless the active task explicitly includes them or they break tests.

## Constraints / context the planner may not know

- A recent fix-loop iteration removed untracked user ask files from `tasks/` after Codex flagged them as out of scope.
- Those files were intentional parallel planning artifacts, not scratch files.
- Existing AGENTS guidance says queued task specs under `tasks/` are protected from deletion/modification unless the active task explicitly includes them in scope.
- This task is a narrow safety guard for fix-loop behavior. The broader invariant that review artifacts and staging should be scope-gated is tracked separately in `tasks/user_ask_scope_gated_review_and_staging.md`.
- The orchestrator should fail safe: do not delete protected queue specs automatically just to satisfy an unrelated task's Codex review.
