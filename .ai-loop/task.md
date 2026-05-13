# Task: Introduce Implementer-Neutral Loop Artifacts

## Project context

Required reading before starting, in order:

1. `AGENTS.md` at repo root - working rules and safe paths.
2. `.ai-loop/project_summary.md` - durable project orientation.
3. `docs/architecture.md` - especially current state vs target OpenCode/Qwen sections.
4. `docs/workflow.md` and `docs/safety.md` - only as needed for file protocol and safe staging.

Do not read by default:

- `docs/archive/`
- `.ai-loop/_debug/`

## Goal

Reduce Cursor-specific naming in the orchestration contract so OpenCode/Qwen runs are easier to understand, while preserving backward compatibility for existing target projects and scripts.

Current names such as `cursor_summary.md`, `next_cursor_prompt.md`, `FIX_PROMPT_FOR_CURSOR`, `Run-CursorFix`, and "Running Cursor agent" still work technically, but they create misleading operator feedback when the implementer is OpenCode/Qwen.

Introduce implementer-neutral names and messages:

- `implementer_summary.md`
- `next_implementer_prompt.md`
- `FIX_PROMPT_FOR_IMPLEMENTER`
- implementer-neutral function/log wording where practical

Keep legacy Cursor names as aliases during the transition.

## Scope

Allowed:

- Update `scripts/` orchestration logic.
- Update `templates/` prompt/summary templates.
- Update `docs/`, `README.md`, and `.ai-loop/project_summary.md` only if the durable contract changes.
- Update/add tests under `tests/`.

Not allowed:

- Do not remove support for existing `cursor_summary.md`, `next_cursor_prompt.md`, or `FIX_PROMPT_FOR_CURSOR`.
- Do not change the core Cursor/OpenCode execution behavior except for neutral naming, alias handling, and clearer logs.
- Do not touch `docs/archive/`.
- Do not edit `ai_loop.py`.

## Required behavior

1. The loop should prefer neutral artifact names for new runs:
   - implementation summary: `.ai-loop/implementer_summary.md`
   - next fix prompt: `.ai-loop/next_implementer_prompt.md`

2. Backward compatibility must remain:
   - Existing `.ai-loop/cursor_summary.md` must still be accepted by Codex review.
   - Existing `.ai-loop/next_cursor_prompt.md` must still be accepted in resume/fix mode.
   - Codex reviews returning `FIX_PROMPT_FOR_CURSOR:` must still be parsed.

3. Prefer writing both neutral and legacy aliases where that is the least risky transition path:
   - If `implementer_summary.md` is updated by the implementer, keep `cursor_summary.md` available for old prompts/tests.
   - If `next_implementer_prompt.md` is extracted, keep `next_cursor_prompt.md` available for old resume flows.

4. Review prompts should tell Codex to read the neutral artifact first, then fall back to legacy names.

5. Implementer/fix prompts should use neutral wording:
   - "implementer" instead of "Cursor" when the selected wrapper may be Cursor or OpenCode.
   - Avoid misleading console logs like "Running Cursor agent" when `-CursorCommand` points to `run_opencode_agent.ps1`.

6. Parameter names may remain `-CursorCommand` / `-CursorModel` for compatibility, but logs and docs should clarify that these are currently generic implementer wrapper/model parameters.

7. `continue_ai_loop.ps1` should be checked for the same transition risk:
   - If it needs neutral or alias support, update it.
   - If it still cannot preserve the selected implementer command/model across resume, document the limitation or fix it in scope if small.

## Files likely to change

- `scripts/ai_loop_task_first.ps1`
- `scripts/ai_loop_auto.ps1`
- `scripts/continue_ai_loop.ps1`
- `templates/codex_review_prompt.md`
- `templates/cursor_summary_template.md` or a new neutral summary template
- `scripts/install_into_project.ps1` if template/script copy lists change
- `tests/test_orchestrator_validation.py`
- `docs/workflow.md`, `docs/safety.md`, `README.md`, `.ai-loop/project_summary.md` if public contract changes

## Tests

Run:

```powershell
python -m pytest -q
```

Also run PowerShell parse checks:

```powershell
powershell -NoProfile -Command "[void][System.Management.Automation.Language.Parser]::ParseFile('scripts\ai_loop_auto.ps1', [ref]$null, [ref]$null)"
powershell -NoProfile -Command "[void][System.Management.Automation.Language.Parser]::ParseFile('scripts\ai_loop_task_first.ps1', [ref]$null, [ref]$null)"
powershell -NoProfile -Command "[void][System.Management.Automation.Language.Parser]::ParseFile('scripts\continue_ai_loop.ps1', [ref]$null, [ref]$null)"
```

Add or update tests for:

1. `FIX_PROMPT_FOR_IMPLEMENTER` parsing.
2. Legacy `FIX_PROMPT_FOR_CURSOR` parsing still works.
3. Resume/fix mode accepts `next_implementer_prompt.md`.
4. Legacy `next_cursor_prompt.md` resume/fix mode still works.
5. Safe/runtime cleanup handles both neutral and legacy artifacts.
6. Prompt templates mention neutral artifacts without breaking legacy compatibility.

## Verification

1. Search results should show no misleading user-facing "Running Cursor agent" message in generic implementer paths.
2. Codex review prompt should read neutral summary/fix artifacts first and legacy names as fallback.
3. Existing tests still pass.
4. No runtime-only files are added to `SafeAddPaths`.
5. `docs/safety.md` remains in sync if runtime exclusions or safe paths change.

## Cursor summary requirements

Update `.ai-loop/cursor_summary.md` with:

1. Changed files.
2. Test result.
3. What was implemented.
4. What legacy aliases remain and why.
5. Remaining risks.

If a new `.ai-loop/implementer_summary.md` is introduced during the task, write the same current-iteration summary there as well, while keeping `.ai-loop/cursor_summary.md` for compatibility.

## Project summary update

Update `.ai-loop/project_summary.md` only with durable contract changes, such as:

- neutral implementer artifact names;
- legacy alias policy;
- resume behavior for selected implementer command/model.

Do not add per-iteration history.

## Important

- This task is a naming/contract transition, not a full OpenCode/Qwen context-builder implementation.
- Preserve the existing Cursor production path.
- Preserve OpenCode/Qwen invocation through `-CursorCommand .\scripts\run_opencode_agent.ps1`.
- Keep changes focused and reversible.
