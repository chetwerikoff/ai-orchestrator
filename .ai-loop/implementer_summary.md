# Implementer summary — Dynamic STEP 1 headers

## Changed files

- `scripts/ai_loop_task_first.ps1` — added `Get-ImplementerStepDisplayLabel`; STEP 1 uses `STEP 1: <label> IMPLEMENTATION`; optional `Model: …` line when `-CursorModel` non-empty.
- `tests/test_orchestrator_validation.py` — asserts helper presence, Qwen-before-Cursor ordering, Cursor cues, and no legacy `STEP 1: IMPLEMENTER PASS`.
- `.ai-loop/project_summary.md` — noted UX-only STEP 1 label mapping; test count 55.

## Tests

`python -m pytest -q`: **55 passed**.

Recommended locally per AGENTS.md:

```powershell
powershell -NoProfile -Command "[void][System.Management.Automation.Language.Parser]::ParseFile('scripts\ai_loop_task_first.ps1', [ref]$null, [ref]$null)"
powershell -NoProfile -Command "[void][System.Management.Automation.Language.Parser]::ParseFile('scripts\ai_loop_auto.ps1', [ref]$null, [ref]$null)"
```

(Not re-invoked in this session.)

## Display label mapping (`Get-ImplementerStepDisplayLabel`)

Case-insensitive checks on wrapper path + leaf plus `-CursorModel`:

1. **QWEN** if wrapper/path/name matches `run_opencode_agent.ps1` substring or contains `opencode`, or model contains `qwen`.
2. Else **CURSOR** if wrapper/path/name matches `run_cursor_agent.ps1` or contains `cursor` or `agent`.
3. Else **IMPLEMENTER**.

OpenCode/Qwen is evaluated before the generic `agent` substring so `run_opencode_agent.ps1` stays **QWEN**.

## Fallback

Unknown wrappers with none of the above substrings → **STEP 1: IMPLEMENTER IMPLEMENTATION**.

## Skipped

- `scripts/ai_loop_auto.ps1` unchanged — no `STEP 1: IMPLEMENTER PASS`-style header there; fix-pass messaging already generic.

## Remaining risks

- Heuristic labels: any path containing `cursor`/`agent`/`opencode`/`qwen` follows the rules above; unrelated filenames could show **CURSOR** incorrectly.
- Empty `-CursorCommand` defaults are not passed into the helper from task-first (param default is always non-empty in normal use).
