# User ASK

## Goal

Change planner queue handling so generated task copies use a strict monotonically increasing queue number instead of repeatedly using `## Order 1`, and move those generated queue specs into a dedicated subfolder under `tasks/` that agents do not read by default.

The goal is to keep `tasks/` usable without cluttering normal agent context, while preserving old generated task descriptions for debugging or audit when needed.

## Affected files (your best guess - planner will verify)

- `scripts/ai_loop_plan.ps1`
- `scripts/build_repo_map.ps1`
- `AGENTS.md`
- `.ai-loop/project_summary.md`
- `.ai-loop/repo_map.md`
- `tests/test_orchestrator_validation.py`
- `docs/workflow.md`
- `docs/safety.md`

## Out-of-scope (explicit boundaries)

- `docs/archive/**`
- `.ai-loop/_debug/**`
- `ai_loop.py`
- Changing implementer/reviewer behavior
- Deleting existing queued task specs unless the generated task explicitly scopes that cleanup
- Changing safe git commit/push behavior except for any required documented SafeAddPaths parity update

## Proposed approach (optional)

Introduce a dedicated generated queue folder, for example:

```text
tasks/queue/
```

New planner-generated copies should go there instead of the root `tasks/` directory:

```text
tasks/queue/014_some_task.md
tasks/queue/015_next_task.md
```

Strict queue numbering should mean:

1. `ai_loop_plan.ps1` no longer blindly trusts `## Order 1` as the filename prefix.
2. When saving a queue copy, it determines the next available integer by scanning existing generated queue files in the dedicated folder.
3. The copied filename uses the next available number with zero padding.
4. If the generated task has a meaningful `## Order`, keep it in the task body as advisory priority if useful, but do not let it create duplicate `001_*` filenames.

## Constraints / context the planner may not know

- Current `ai_loop_plan.ps1` copies `.ai-loop/task.md` to `tasks/NNN_slug.md` when it finds `## Order` followed by a positive integer.
- Because planners often emit `## Order 1`, multiple unrelated generated tasks can all appear as `001_*`.
- Agents should not read historical generated queue specs by default; read them only when a current task explicitly asks or debugging/audit requires it.
- Prefer updating the existing queue-save block in `ai_loop_plan.ps1` over adding a new subsystem.
