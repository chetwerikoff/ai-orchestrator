# Task: Persist Implementer Selection for Resume

## Project context

Required reading before starting, in order:

1. `AGENTS.md` at repo root - working rules and safe paths.
2. `.ai-loop/project_summary.md` - durable project orientation.
3. `docs/architecture.md` - current state, file contract, and target `loop_state.json` notes.
4. `docs/workflow.md` - current task-first / resume behavior.

Do not read by default:

- `docs/archive/`
- `.ai-loop/_debug/`

## Goal

Make resume/fix runs remember which implementer wrapper/model started the task, so a Qwen/OpenCode task does not silently resume with the default Cursor wrapper when the operator runs `continue_ai_loop.ps1` without repeating `-CursorCommand` / `-CursorModel`.

Current status:

- `continue_ai_loop.ps1` accepts and forwards `-CursorCommand` / `-CursorModel`.
- Runtime artifact names are mostly implementer-neutral.
- Missing piece: selected implementer is not persisted to `.ai-loop/` state.

Introduce a small persistent state file:

```text
.ai-loop/implementer.json
```

or, if it fits existing architecture better:

```text
.ai-loop/loop_state.json
```

Use one file consistently. Prefer `implementer.json` if the implementation only stores wrapper/model selection; prefer `loop_state.json` only if broader loop state is actually introduced.

## Scope

Allowed:

- Update `scripts/ai_loop_task_first.ps1`.
- Update `scripts/ai_loop_auto.ps1`.
- Update `scripts/continue_ai_loop.ps1`.
- Update tests under `tests/`.
- Update docs/templates that describe resume behavior: `docs/workflow.md`, `docs/architecture.md`, `README.md`, `.ai-loop/project_summary.md`, and `AGENTS.md` if needed.
- Update `.gitignore` / `docs/safety.md` / `SafeAddPaths` only after deciding whether the state file is durable or runtime.

Not allowed:

- Do not remove `-CursorCommand` / `-CursorModel` parameters; they remain explicit overrides.
- Do not remove legacy artifact compatibility (`cursor_summary.md`, `next_cursor_prompt.md`, `FIX_PROMPT_FOR_CURSOR`).
- Do not change the default production implementer from Cursor.
- Do not implement the full target `src/orchestrator/loop_controller.py`.
- Do not touch `docs/archive/` or `ai_loop.py`.

## Required behavior

1. Task-first runs persist selected implementer settings before or during the initial implementer pass:

   ```json
   {
     "schema_version": 1,
     "cursor_command": ".\\scripts\\run_opencode_agent.ps1",
     "cursor_model": "local-qwen-35b/qwen3-6-35b-a3b",
     "selected_at": "<ISO timestamp>",
     "source": "ai_loop_task_first.ps1"
   }
   ```

   Field names may be more neutral (`implementer_command`, `implementer_model`) if backward-compatible docs make the mapping clear. If neutral fields are used, including legacy aliases is acceptable.

2. `ai_loop_auto.ps1 -Resume` should load persisted implementer settings when:

   - `-CursorCommand` is not explicitly provided, and
   - the persisted state file exists and contains a non-empty command.

3. Explicit CLI parameters always win over persisted state:

   - If the operator passes `-CursorCommand`, use it.
   - If the operator passes `-CursorModel`, use it.
   - Persist the effective values back to the state file so future resume remains consistent.

4. `continue_ai_loop.ps1` should keep forwarding explicit parameters, but should not require them when state exists.

5. If the state file is missing, invalid JSON, or points to a missing command:

   - fall back to current default behavior;
   - print a clear warning;
   - do not crash before normal validation unless the selected command is actually required for the current operation.

6. The state file must not cause accidental commits if it is runtime-only.

   Decide one policy and apply consistently:

   - **Runtime policy:** add `.ai-loop/implementer.json` or `.ai-loop/loop_state.json` to `.gitignore`, do not add it to `SafeAddPaths`, document it as runtime.
   - **Durable policy:** add it to `SafeAddPaths`, document why model/wrapper selection is safe and useful to commit.

   Recommended: runtime policy, because local wrapper paths and model IDs can be machine-specific.

7. Preserve current task-first behavior:

   - first implementer pass uses passed/default command/model;
   - fix passes spawned from task-first still receive the effective command/model directly;
   - resume after a stopped loop can recover the effective command/model from state.

## Files likely to change

- `scripts/ai_loop_task_first.ps1`
- `scripts/ai_loop_auto.ps1`
- `scripts/continue_ai_loop.ps1`
- `.gitignore`
- `docs/workflow.md`
- `docs/architecture.md`
- `docs/safety.md`
- `README.md`
- `.ai-loop/project_summary.md`
- `tests/test_orchestrator_validation.py`

## Tests

Run:

```powershell
python -m pytest -q
```

Run PowerShell parse checks:

```powershell
powershell -NoProfile -Command "[void][System.Management.Automation.Language.Parser]::ParseFile('scripts\ai_loop_auto.ps1', [ref]$null, [ref]$null)"
powershell -NoProfile -Command "[void][System.Management.Automation.Language.Parser]::ParseFile('scripts\ai_loop_task_first.ps1', [ref]$null, [ref]$null)"
powershell -NoProfile -Command "[void][System.Management.Automation.Language.Parser]::ParseFile('scripts\continue_ai_loop.ps1', [ref]$null, [ref]$null)"
```

Add or update tests for:

1. Task-first script writes a state file containing implementer command/model.
2. Auto-loop resume can load persisted command/model when CLI args are absent.
3. Explicit CLI command/model override persisted state.
4. Missing or invalid state falls back safely.
5. The state file is listed in `.gitignore` if runtime policy is chosen.
6. Documentation mentions that `continue_ai_loop.ps1` can resume Qwen/OpenCode from persisted state.

## Verification

1. Search docs and scripts for stale wording that says operators must always repeat `-CursorCommand` on continue. Update it.
2. Confirm `continue_ai_loop.ps1` examples mention both options:
   - automatic persisted implementer resume;
   - explicit override with `-CursorCommand` / `-CursorModel`.
3. Confirm no secrets or machine-specific model paths are staged.
4. Confirm tests pass and parser checks pass.

## Implementer summary requirements

Update `.ai-loop/implementer_summary.md` and mirror the same content to `.ai-loop/cursor_summary.md` with:

1. Changed files.
2. Test result.
3. Implemented state file policy.
4. Resume behavior before/after.
5. Remaining risks.

## Project summary update

Update `.ai-loop/project_summary.md` with durable context only:

- state file name and policy;
- resume behavior for persisted implementer selection;
- whether the file is runtime-only or safe-staged.

Do not add per-iteration history.

## Important

- This task is specifically about persisting implementer selection for resume.
- Do not broaden into full context-builder, model A/B harness, or target orchestrator package work.
- Keep Cursor as the default implementer when no override or persisted state exists.
