# User ASK

## Goal

Fix Codex console reason extraction so `Codex reason:` is derived from the real final Codex response, not from prompt/template placeholders earlier in `.ai-loop/codex_review.md`.

The terminal must not print unhelpful placeholder reasons such as `Codex reason: ...`.

## Affected files (your best guess - planner will verify)

- `scripts/ai_loop_auto.ps1`
- `tests/test_orchestrator_validation.py`
- `.ai-loop/project_summary.md`

## Out-of-scope (explicit boundaries)

- `docs/archive/**`
- `.ai-loop/_debug/**`
- `ai_loop.py`
- Changing Codex verdict parsing semantics
- Changing fix-loop behavior
- Changing token usage parsing
- Changing commit/staging behavior
- Running live Codex/Cursor/Claude CLIs
- Git commit or push

## Proposed approach (optional)

Update the console-summary reason extractor so it analyzes only the final Codex answer region:

1. Locate the last exact verdict line using the same semantics as `Get-ReviewVerdict`, e.g. a trimmed line matching:

   ```text
   VERDICT: PASS
   VERDICT: FIX_REQUIRED
   ```

2. Search `CRITICAL:`, `HIGH:`, and `MEDIUM:` sections only after that last exact verdict line.
3. Keep priority order: first non-empty/non-`none` bullet from `CRITICAL`, then `HIGH`, then `MEDIUM`.
4. Ignore placeholder bullets such as:

   ```text
   - ...
   - ...
   ```

   or any equivalent body that trims to only dots/ellipsis.
5. If no real reason is found, omit `Codex reason:` and rely on:

   ```text
   See: .ai-loop\codex_review.md
   ```

Do not weaken the existing exact verdict parsing. This is only about selecting the correct review region for console reason display.

## Constraints / context the planner may not know

- `.ai-loop/codex_review.md` contains the full Codex transcript, including the prompt text.
- The prompt includes example severity sections such as:

  ```text
  CRITICAL:
  - ...
  HIGH:
  - ...
  MEDIUM:
  - ...
  ```

- Current reason extraction can scan from the top of the file and pick `- ...` from the prompt, producing:

  ```text
  Codex reason: ...
  ```

- Tests should use representative transcript strings with prompt/template placeholders before the final Codex answer.
- Add coverage for:
  - prompt placeholders before final `VERDICT: FIX_REQUIRED` are ignored;
  - real `HIGH` bullet after final verdict is printed;
  - `- none` and `- ...` are both ignored;
  - when no real reason exists, no `Codex reason:` line is emitted.
