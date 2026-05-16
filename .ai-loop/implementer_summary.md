# Implementer summary

## Changed files

(Token / report work already in-tree; **this Codex-fix iteration touches documentation only.**)

Implementation inventory for the reliability task:

- `scripts/ai_loop_auto.ps1` — `Run-CodexReview` calls `Write-CliCaptureTokenUsageIfParsed` on the **joined** stdout/stderr string written to `.ai-loop/codex_review.md` (same text as the capture file); **fallback path** repeats the hook when Codex redirects to file. `script_name` **`ai_loop_auto.codex_review`**, **`provider`/`model`** `codex`, per-iteration **`DedupeId`** `ai_loop_auto:codex_review:iter{Iteration}`. **No second scrape** after the loop re-reads the markdown file (console summary only). **PASS** skips `show_token_report.ps1` when **`AI_LOOP_CHAIN_FROM_TASK_FIRST`** is `1`; otherwise runs it and **`Set-PassTokenReportEmittedFlag`**. **Script startup** removes **`.tmp/pass_token_report_shown.flag`** on each **`ai_loop_auto.ps1`** run (fresh PASS tail semantics; see **`Set-PassTokenReportEmittedFlag`** comment).
- `scripts/ai_loop_task_first.ps1` — sets **`AI_LOOP_CHAIN_FROM_TASK_FIRST=1`** for the spawned auto-loop when chaining after step 1; tail **runs `show_token_report.ps1` only when** `.tmp/pass_token_report_shown.flag` **did not appear** after the child (covers normal task-first PASS with parent-only report **and** empty-state line **once**; **`-SkipInitialCursor`** retains child report + flag so parent skips duplicate).
- `scripts/record_token_usage.ps1` — **`DedupeId`**: in-process **`_CliCaptureDedupeLastFpById`**; SHA-256 fingerprint of capture text skips identical **same-id** repeats.
- `scripts/run_cursor_agent.ps1` — existing **non-blocking** `Write-CliCaptureTokenUsageIfParsed` on successful exits (still depends on recognizable CLI blocks).
- `tests/test_token_usage.py` — joined-capture / Codex **`tokens used`** and API JSON fixtures, **`test_cli_capture_dedupe_*`**, `ai_loop_*` **`Parser::ParseFile`** smoke tests, etc.

**This iteration:** `.ai-loop/implementer_summary.md` — replace stale cleanup-only narrative with accurate token-usage task summary.

## Tests

- `python -m pytest -q` — **212 passed** (1 Windows `pytest_cache` warning).
- `python -m pyright .` — **0 errors**.

## Task-specific verification

- Task.md PowerShell **`Parser::ParseFile`** checklist is exercised by **`tests/test_token_usage.py`** (`test_ai_loop_auto_ps1_parse_clean`, `test_ai_loop_task_first_ps1_parse_clean`, `test_record_token_usage_ps1_parse_clean`, `test_show_token_report_ps1_parse_clean`, `test_run_cursor_agent_ps1_parse_clean`, plus other script parse_clean tests).

## Implementation (what landed — token reliability)

1. **Codex auto-loop:** single authoritative hook at **`Run-CodexReview`** merge step; **`ai_loop_auto.codex_review`** label; errors are **`Write-Warning`**, never loop-fatal.
2. **Deduping:** per-iteration **`DedupeId`** plus hash-based skip for duplicate identical payloads in one process session.
3. **Cursor:** no new speculative parsers in-repo; **`ConvertFrom-CliTokenUsage`** still succeeds only when output matches documented patterns (**many Cursor runs still omit parseable telemetry** — see **`project_summary.md`** known-limitation bullet).
4. **Report duplication:** chained task-first PASS avoids **back-to-back** `show_token_report.ps1` (env skip in child + **flag / parent tail** handshake for other chains).

## Skipped / not changed

- **Live `codex` / `cursor` runs** — not required; fixtures + subprocess PowerShell stubs only.
- **`docs/workflow.md`** — intentionally out of task scope (**durable note stays in `project_summary.md`**).

## Remaining risks

- **Cursor default CLI output** often still lacks a **`ConvertFrom-CliTokenUsage`** match → empty JSONL rows for Cursor are expected until tooling emits stable usage text.
- **Dedupe** is **process-scoped**; new PowerShell sessions do not inherit the in-memory map (acceptable for single-pass auto-loop semantics).
- **Parallel `tasks/` queue noise** / other uncommitted specs can clutter **local `git status`** without affecting the token hooks.
