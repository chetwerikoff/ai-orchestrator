# User ASK

## Goal

Fix Codex verdict parsing in `ai_loop_auto.ps1` so the orchestrator cannot treat prompt/instruction text such as `VERDICT: PASS or FIX_REQUIRED` as an actual `PASS` verdict.

The correct behavior is to accept only a real verdict line from Codex output, so `VERDICT: FIX_REQUIRED` reliably enters the fix loop and never proceeds to commit/push.

## Affected files (your best guess - planner will verify)

- `scripts/ai_loop_auto.ps1`
- `tests/test_orchestrator_validation.py`
- `.ai-loop/project_summary.md`

## Out-of-scope (explicit boundaries)

- `docs/archive/**`
- `.ai-loop/_debug/**`
- `ai_loop.py`
- Changing Codex review prompt semantics
- Changing safe-add/staging behavior
- Changing task scope filtering or queue behavior
- Running live Codex/Cursor/Claude CLIs
- Git commit or push

## Proposed approach (optional)

Update `Get-ReviewVerdict` so it only recognizes whole verdict lines:

```text
VERDICT: PASS
VERDICT: FIX_REQUIRED
```

Do not let these strings match:

```text
VERDICT: PASS or FIX_REQUIRED
Return exactly: VERDICT: PASS or FIX_REQUIRED
```

Prefer a line-based implementation or a multiline regex anchored to the full line. If multiple exact verdict lines appear in a transcript, use the last exact verdict line, because the file may include prompt text, echoed examples, or earlier transcript content before the final assistant answer.

## Constraints / context the planner may not know

- A recent run committed/pushed after Codex actually returned `VERDICT: FIX_REQUIRED` because `Get-ReviewVerdict` matched `VERDICT: PASS` inside instruction text.
- This is a critical safety bug independent of task queue or staging policy.
- Keep the fix small and targeted. Do not redesign review artifacts or staging in this task.
- Preserve current fallback behavior: missing review file or no exact PASS should remain safe, i.e. `FIX_REQUIRED`.
