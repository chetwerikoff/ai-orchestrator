# User ASK

## Goal

Make Codex review artifacts and the eventual staged commit set describe the same conceptual change set.

The orchestrator should ignore unrelated concurrent working-tree files during review and should not stage them for the current task. This prevents a task run from deleting, flagging, or committing parallel `tasks/user_ask_*.md` files created by another agent while the current implementation is running.

## Affected files (your best guess - planner will verify)

- `scripts/ai_loop_auto.ps1`
- `scripts/ai_loop_task_first.ps1`
- `templates/codex_review_prompt.md`
- `docs/safety.md`
- `docs/workflow.md`
- `AGENTS.md`
- `.ai-loop/project_summary.md`
- `tests/test_orchestrator_validation.py`

## Out-of-scope (explicit boundaries)

- `docs/archive/**`
- `.ai-loop/_debug/**`
- `ai_loop.py`
- Changing Codex verdict parsing
- Deleting or moving existing `tasks/**` files
- Changing planner queue numbering/location
- Making staging destructive
- Running live Codex/Cursor/Claude CLIs
- Git commit or push

## Proposed approach (optional)

Introduce explicit concepts:

```text
SafeAddPaths = upper bound of what may ever be staged.
ActiveScope = paths/globs parsed from current `.ai-loop/task.md` `## Files in scope`.
DurableAlwaysCommit = orchestrator state files that record the current run.

Stage set =
  DurableAlwaysCommit
  +
  ((SafeAddPaths - DurableAlwaysCommit) intersect ActiveScope)
```

The same conceptual set should drive review artifacts:

```text
Review set =
  DurableAlwaysCommit
  +
  ((SafeAddPaths - DurableAlwaysCommit) intersect ActiveScope)
```

Practical behavior:

1. `tasks/user_ask_foo.md` is ignored and not staged if the active task does not include it.
2. `tasks/016_foo.md` is included if the active task explicitly lists that file.
3. `tasks/**` or `tasks/` includes generated/user task specs only when the active task explicitly scopes the whole folder.
4. Durable run files such as `.ai-loop/task.md`, `.ai-loop/implementer_summary.md`, `.ai-loop/project_summary.md`, and `.ai-loop/repo_map.md` remain eligible even if not perfectly listed in `## Files in scope`.

## Constraints / context the planner may not know

- Today `git_status.txt` can include the whole working tree, so Codex sees unrelated files created by parallel agents and may demand deletion.
- Today `SafeAddPaths` includes `tasks/`, so parallel user asks or generated queue specs can be staged into the current task commit even if Codex should not have reviewed them.
- The important invariant is: Codex review artifacts and safe-add staging must refer to the same conceptual change set.
- Do not delete or revert unrelated files. Leave out-of-scope concurrent files in the working tree uncommitted.
- If ActiveScope is missing or malformed, fail closed for scope-gated paths and still allow DurableAlwaysCommit.
