# Task: Add `tasks/` to SafeAddPaths

## Project context

Required reading before starting:

1. `AGENTS.md`
2. `.ai-loop/task.md`
3. `.ai-loop/project_summary.md`
4. `.ai-loop/repo_map.md`

Do not read by default:

- `docs/archive/`
- `.ai-loop/_debug/`

## Goal

Make queued task specs under `tasks/` eligible for orchestrator safe staging. C10 added optional `## Order` support and queue-copy output to `tasks/NNN_slug.md`, but `tasks/` is not currently included in the default `SafeAddPaths`, so queue files are written but not auto-committed by the orchestrator.

## Scope

Allowed:
- Add `tasks/` to the default `SafeAddPaths` literal everywhere it is maintained.
- Update documentation that mirrors the safe path list.
- Update tests that pin safe-path parity.
- Update `.ai-loop/project_summary.md` to remove the stale follow-up note and record the durable behavior.
- Regenerate `.ai-loop/repo_map.md` if changed files affect the map.

Not allowed:
- Changing queue filename generation or `## Order` parsing behavior.
- Changing commit/push behavior beyond the safe allowlist.
- Editing queued task content except this task file if needed.

## Files in scope

- `scripts/ai_loop_auto.ps1`
- `scripts/ai_loop_task_first.ps1`
- `scripts/continue_ai_loop.ps1`
- `docs/safety.md`
- `AGENTS.md`
- `tests/test_orchestrator_validation.py`
- `.ai-loop/project_summary.md`
- `.ai-loop/repo_map.md`

## Files out of scope

- `docs/archive/**`
- `.ai-loop/_debug/**`
- `ai_loop.py`
- `templates/**`
- `scripts/ai_loop_plan.ps1`

## Required behavior

1. Add `tasks/` to the default `SafeAddPaths` literal in all three scripts:
   - `scripts/ai_loop_auto.ps1`
   - `scripts/ai_loop_task_first.ps1`
   - `scripts/continue_ai_loop.ps1`

2. Add `tasks/` to the mirrored safe path documentation in:
   - `AGENTS.md`
   - `docs/safety.md`

3. Update any safe-path parity test in `tests/test_orchestrator_validation.py` so the scripts and docs are still required to stay synchronized.

4. Update `.ai-loop/project_summary.md`:
   - remove or revise the stale note saying `tasks/` is not currently in `SafeAddPaths`;
   - record that queued task specs are now part of the durable safe staging allowlist.

5. Regenerate `.ai-loop/repo_map.md` with `scripts/build_repo_map.ps1` if the map changes.

## Tests

Run:

```powershell
python -m pytest tests\test_orchestrator_validation.py -q
```

Add or update tests for:

1. `tasks/` appears in every default `SafeAddPaths` literal.
2. `docs/safety.md` and `AGENTS.md` remain synchronized with the script defaults.

## Verification

Run:

```powershell
powershell -NoProfile -Command "[void][System.Management.Automation.Language.Parser]::ParseFile('scripts\ai_loop_auto.ps1', [ref]`$null, [ref]`$null)"
powershell -NoProfile -Command "[void][System.Management.Automation.Language.Parser]::ParseFile('scripts\ai_loop_task_first.ps1', [ref]`$null, [ref]`$null)"
powershell -NoProfile -Command "[void][System.Management.Automation.Language.Parser]::ParseFile('scripts\continue_ai_loop.ps1', [ref]`$null, [ref]`$null)"
powershell -NoProfile -Command "[void][System.Management.Automation.Language.Parser]::ParseFile('scripts\build_repo_map.ps1', [ref]`$null, [ref]`$null)"
python -m pytest tests\test_orchestrator_validation.py -q
pyright
```

## Implementer summary requirements

Update `.ai-loop/implementer_summary.md` with:

1. Changed files.
2. Test result.
3. What was implemented.
4. What was skipped and why.
5. Remaining risks.

## Project summary update

Update `.ai-loop/project_summary.md` with durable project-level information only. Keep it concise: mention that queued task specs under `tasks/` are now included in `SafeAddPaths`, and remove the stale follow-up note.

## Output hygiene

- Do not duplicate this task description into `.ai-loop/implementer_summary.md`.
- Do not write to `.ai-loop/_debug/`.
- Do not write to `docs/archive/`.
- Do not commit or push manually.

## Important

- Keep the safe path literals synchronized exactly. AGENTS.md says this list lives in `scripts/ai_loop_auto.ps1`, `scripts/ai_loop_task_first.ps1`, `scripts/continue_ai_loop.ps1`, and `docs/safety.md`.
- This task only changes whether queued task files can be staged safely. It must not change how the planner creates queue copies or how task-first runs active tasks.
- Adding `tasks/` means generated queue specs can be committed; runtime/debug artifacts must remain excluded.

## Order

