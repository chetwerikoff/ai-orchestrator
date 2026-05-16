# User ASK

## Goal

Improve the console summary after each Codex review in `ai_loop_auto.ps1`.

When Codex returns `FIX_REQUIRED`, the terminal should show the verdict, a short human-readable reason from the review, and token usage when Codex reported it. When Codex returns `PASS`, the terminal should continue to show the verdict and should also show token usage when available.

## Affected files (your best guess - planner will verify)

- `scripts/ai_loop_auto.ps1`
- `scripts/record_token_usage.ps1`
- `tests/test_orchestrator_validation.py`
- `tests/test_token_usage.py`
- `.ai-loop/project_summary.md`

## Out-of-scope (explicit boundaries)

- `docs/archive/**`
- `.ai-loop/_debug/**`
- `ai_loop.py`
- Changing Codex verdict parsing semantics
- Changing fix-loop behavior
- Changing commit/staging behavior
- Making token usage recording fatal
- Inventing token counts or estimating from text length
- Running live Codex/Cursor/Claude CLIs in tests
- Git commit or push

## Proposed approach (optional)

After `Run-CodexReview` and `Get-CodexVerdict`, print a compact console block derived from `.ai-loop/codex_review.md`, for example:

```text
Codex verdict: FIX_REQUIRED
Codex reason: HIGH - Out-of-scope queued task files are modified/added...
Codex tokens: 28,976
See: .ai-loop\codex_review.md
```

For PASS:

```text
Codex verdict: PASS
Codex tokens: 28,976
```

Reason extraction:

1. Parse `.ai-loop/codex_review.md` conservatively.
2. Prefer the first non-`none` bullet from `CRITICAL`, then `HIGH`, then `MEDIUM`.
3. Strip leading `- ` and collapse whitespace for one-line console output.
4. If no reason can be extracted, print only `See: .ai-loop\codex_review.md` rather than guessing.
5. Do not print the full review body.

Token extraction:

1. Reuse existing token parsing logic where possible, preferably `ConvertFrom-CliTokenUsage` from `scripts/record_token_usage.ps1`.
2. If parsed usage has `TotalTokens`, print that total.
3. If only input/output counts are available, print total when computable and optionally include the split.
4. If no parseable token usage exists, omit the token line or print a concise `Codex tokens: unavailable` message chosen by the planner.
5. Do not infer or estimate tokens from review length.

## Constraints / context the planner may not know

- Today the PASS path prints `Codex verdict: PASS`, but the `FIX_REQUIRED` path can proceed directly to fix prompt extraction and implementer rerun without clearly showing the verdict or reason.
- Recent Codex review output can include explicit token usage lines such as:

  ```text
  tokens used
  28,976
  ```

- `scripts/record_token_usage.ps1` already contains parser logic for explicit usage text; avoid duplicating token parsing if a small helper reuse is cleaner.
- Console output should be short and operator-focused. Full details remain in `.ai-loop/codex_review.md`.
- Token usage display is informational only and must not affect PASS/FIX_REQUIRED behavior.
- Tests should use representative Codex review text fixtures or helper-level tests, not live Codex CLI.
