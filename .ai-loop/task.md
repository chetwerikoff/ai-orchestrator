# Task: Dynamic Implementer Step Headers

## Project context

Required reading before starting:

1. `AGENTS.md` at repo root - working rules and safe paths.
2. `.ai-loop/project_summary.md` - durable orientation.
3. `docs/workflow.md` - current task-first and resume flow.
4. `docs/architecture.md` - current Cursor/OpenCode/Qwen status.

Do not read by default:

- `docs/archive/`
- `.ai-loop/_debug/`

## Goal

Make task-first console headers show the selected implementer family instead of the generic:

```text
STEP 1: IMPLEMENTER PASS
```

Expected examples:

```text
STEP 1: CURSOR IMPLEMENTATION
```

when the default Cursor wrapper is used, and:

```text
STEP 1: QWEN IMPLEMENTATION
```

when OpenCode/Qwen is selected through `-CursorCommand .\scripts\run_opencode_agent.ps1` and/or a Qwen `-CursorModel`.

This is a UX/logging change only. It must not change execution behavior.

## Scope

Allowed:

- Update `scripts/ai_loop_task_first.ps1`.
- Update `scripts/ai_loop_auto.ps1` only if fix-pass logs need the same display label.
- Update tests under `tests/`.
- Update docs only if user-facing examples or wording currently mention the generic header.

Not allowed:

- Do not change the default implementer.
- Do not remove `-CursorCommand` / `-CursorModel`.
- Do not remove legacy filenames or aliases.
- Do not implement or modify persistent implementer state unless that task has already landed and the display helper can reuse it safely.
- Do not touch `docs/archive/` or `ai_loop.py`.

## Required behavior

1. Add a small helper that derives a display label from the effective implementer command/model.

   Suggested logic:

   - If command path/name contains `run_opencode_agent.ps1`, `opencode`, or model contains `qwen`, display `QWEN`.
   - If command path/name contains `run_cursor_agent.ps1`, `cursor`, or `agent`, display `CURSOR`.
   - Otherwise display `IMPLEMENTER`.

2. Use the label in task-first section heading:

   ```text
   STEP 1: <LABEL> IMPLEMENTATION
   ```

3. Keep fallback behavior stable:

   - default command `.\scripts\run_cursor_agent.ps1` should print `STEP 1: CURSOR IMPLEMENTATION`;
   - OpenCode/Qwen command/model should print `STEP 1: QWEN IMPLEMENTATION`;
   - unknown custom wrapper should print `STEP 1: IMPLEMENTER IMPLEMENTATION` or a cleaner equivalent agreed by implementation.

4. Update nearby console lines if useful, but avoid overengineering:

   - `Running implementer via: ...` may remain generic;
   - adding model display is acceptable, e.g. `Model: local-qwen-35b/...`, when non-empty.

5. Preserve all current behavior around:

   - initial implementer pass;
   - retry pass;
   - no-change marker gate;
   - forwarding command/model into auto-loop;
   - Codex review/fix loop.

## Files likely to change

- `scripts/ai_loop_task_first.ps1`
- `scripts/ai_loop_auto.ps1` only if fix-pass logs are updated too
- `tests/test_orchestrator_validation.py`
- `README.md` / `docs/workflow.md` only if documentation mentions the exact header

## Tests

Run:

```powershell
python -m pytest -q
```

Run parser checks:

```powershell
powershell -NoProfile -Command "[void][System.Management.Automation.Language.Parser]::ParseFile('scripts\ai_loop_task_first.ps1', [ref]$null, [ref]$null)"
powershell -NoProfile -Command "[void][System.Management.Automation.Language.Parser]::ParseFile('scripts\ai_loop_auto.ps1', [ref]$null, [ref]$null)"
```

Add or update tests that assert:

1. The task-first script contains a display-label helper.
2. Cursor wrapper maps to `CURSOR`.
3. OpenCode/Qwen wrapper or model maps to `QWEN`.
4. The section heading is built from the derived label, not hard-coded to `IMPLEMENTER PASS`.

## Verification

Manual smoke commands, if practical:

```powershell
.\scripts\ai_loop_task_first.ps1 -NoPush -SkipInitialCursor
```

should not require running the implementer but should keep parser/tests green.

For real runs:

```powershell
.\scripts\ai_loop_task_first.ps1 -NoPush
```

should show:

```text
STEP 1: CURSOR IMPLEMENTATION
```

and:

```powershell
.\scripts\ai_loop_task_first.ps1 -NoPush `
  -CursorCommand .\scripts\run_opencode_agent.ps1 `
  -CursorModel local-qwen-35b/qwen3-6-35b-a3b
```

should show:

```text
STEP 1: QWEN IMPLEMENTATION
```

## Implementer summary requirements

When implemented through the loop, update `.ai-loop/implementer_summary.md` and mirror `.ai-loop/cursor_summary.md` with:

- changed files;
- test result;
- display-label mapping rules;
- any fallback behavior for unknown wrappers;
- remaining risks.

## Project summary update

Update `.ai-loop/project_summary.md` only if this becomes durable behavior worth remembering:

- dynamic step headers;
- label mapping rules;
- no execution behavior change.

Keep it short.
