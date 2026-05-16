# User ASK

## Goal

Improve auto-loop observability so the terminal clearly shows when Codex returned `FIX_REQUIRED` and the orchestrator is entering a fix iteration.

This is a small logging/UX task, not a logic change to Codex review behavior.

## Affected files (your best guess - planner will verify)

- `scripts/ai_loop_auto.ps1`
- `tests/test_orchestrator_validation.py`
- `.ai-loop/project_summary.md`

## Out-of-scope (explicit boundaries)

- `docs/archive/**`
- `.ai-loop/_debug/**`
- `ai_loop.py`
- Changing Codex verdict parsing
- Changing fix-loop semantics
- Changing safe-add/staging behavior
- Changing Codex prompt or reviewer output requirements
- Running live Codex/Cursor/Claude CLIs
- Git commit or push

## Proposed approach (optional)

In `scripts/ai_loop_auto.ps1`, after:

```powershell
$codexVerdict = Get-CodexVerdict
```

the PASS path already prints:

```text
Codex verdict: PASS
```

Add equivalent visible output for the non-PASS path before extracting the fix prompt and running the implementer, for example:

```text
Codex verdict: FIX_REQUIRED
Extracting fix prompt for implementer...
Running implementer fix pass...
```

Keep messages concise and consistent with existing `Write-Host` style.

## Constraints / context the planner may not know

- Today the terminal shows `Codex verdict: PASS` only on the PASS path.
- On `FIX_REQUIRED`, the script can go straight from `Running Codex review...` to `Running implementer...` and `AI LOOP ITERATION 2 / 5`, which makes it look like the verdict disappeared.
- The behavior is probably correct once `FIX_REQUIRED` is recognized; the missing piece is clear operator feedback.
- Do not change when the fix loop runs, how prompts are extracted, or what files are committed.
- Tests can be minimal: verify the relevant status/log string is emitted in a stubbed or function-level harness if existing patterns make that cheap. If not, document the manual verification path in the task.
