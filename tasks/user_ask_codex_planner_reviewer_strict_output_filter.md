# User ASK

## Goal

Fix planner review runs that use the default Codex reviewer so `ai_loop_plan.ps1 -WithReview` can mechanically validate the reviewer result even when Codex CLI output includes telemetry or transcript lines such as `tokens used`.

The reviewer may internally emit or expose token usage for journaling, but the stdout returned to `ai_loop_plan.ps1` must be exactly one strict reviewer answer: either `NO_BLOCKING_ISSUES` or a valid `ISSUES:` block.

## Affected files (your best guess - planner will verify)

- `scripts/run_codex_reviewer.ps1`
- `scripts/ai_loop_plan.ps1`
- `scripts/record_token_usage.ps1`
- `tests/test_orchestrator_validation.py`
- `tests/test_token_usage.py`
- `.ai-loop/project_summary.md`

## Out-of-scope (explicit boundaries)

- `docs/archive/**`
- `.ai-loop/_debug/**`
- `ai_loop.py`
- Changing planner task generation semantics
- Weakening `Test-ReviewerOutputStrict` to accept arbitrary transcript text
- Removing token usage journaling
- Running live Codex/Cursor/Claude CLIs in tests
- Git commit or push

## Proposed approach (optional)

Prefer fixing the wrapper boundary instead of relaxing the strict validator:

1. `run_codex_reviewer.ps1` should capture full Codex stdout/stderr internally.
2. It may pass the full captured text to `Write-CliCaptureTokenUsageIfParsed` so token usage is still journaled when parseable.
3. It should emit to stdout only the final strict reviewer payload expected by `ai_loop_plan.ps1`.
4. Strip or ignore wrapper/transcript/telemetry lines such as `Reading prompt from stdin...`, `OpenAI Codex ...`, `codex`, `tokens used`, and token count lines.
5. If a strict payload cannot be extracted confidently, keep safe malformed/degraded behavior rather than fabricating `NO_BLOCKING_ISSUES`.

## Constraints / context the planner may not know

- A recent `ai_loop_plan.ps1 -WithReview` run produced a valid task, and Codex effectively answered `NO_BLOCKING_ISSUES`, but review was marked `REVIEWER_OUTPUT_MALFORMED`.
- Trace showed extra lines around the answer, including `codex`, `NO_BLOCKING_ISSUES`, `tokens used`, and a token count.
- `ai_loop_plan.ps1` intentionally requires strict reviewer output. Do not weaken that contract.
- Token usage reporting should still work by separating captured text for token parsing from strict answer returned to planner.
