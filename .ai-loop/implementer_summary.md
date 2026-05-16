# Implementer summary

## Changed files

- `scripts/ai_loop_task_first.ps1` — After scope preflight, **manual** `Initialize-AiLoopPlannerChain` (`planner_command` = `manual`, empty reviewer fields, `no_revision` = true) runs **before** the `-SkipInitialCursor` branch so skip-implementer / harness runs still create or preserve `.ai-loop/chain.json`. `TaskFirstManualChainSessionActive` remains true only when this invocation wrote or replaced the file (unchanged archive-on-terminal-failure semantics for chains this script opened).
- `tests/test_token_usage.py` — `test_ai_loop_task_first_skip_initial_cursor_opens_manual_chain` and `test_ai_loop_task_first_skip_initial_cursor_preserves_existing_chain` (scratch tree, `fake_auto_loop.ps1`, no live CLIs).
- `.ai-loop/repo_map.md` — Dropped transient `tests/.token_limits_scratch/...` lines from the committed map.

## Tests

- `python -m pytest -q` — **229 passed** (one `PytestCacheWarning` on `.pytest_cache` only).

## Implementation summary

**Token ledger (JSONL):** optional fields include `planner_chain_id`, `phase`, `role`, `fix_iteration_index`, `prompt_bytes`, plus planner metadata (`planner_command`, `reviewer_command`, `max_review_iters`, `no_revision`) on planner-class rows; older lines still parse.

**`chain.json`:** runtime gitignored file opened by `ai_loop_plan.ps1` or manual task-first; existing file is kept unless `-ForceNewChain`; archived to `.ai-loop/_debug/chains/<id>.json` and removed on PASS or terminal failure from `ai_loop_auto.ps1` (and task-first only archives when this run created the chain).

**Wrappers:** planner / reviewer / implementer / Codex review / wrap-up pass chain context and `prompt_bytes` where stdin is a single string; `ConvertFrom-CliTokenUsage` and `-DedupeId` behavior unchanged.

**`show_token_report.ps1 -ByChain`:** groups JSONL by `planner_chain_id`, rolls up roles, reports max implementer `fix_iteration_index`.

**This fix:** task-first `-SkipInitialCursor` no longer skips manual chain initialization.

## Task-specific verification

- Full PowerShell `Parser::ParseFile` list from `.ai-loop/task.md` not re-run as a separate step; `test_ai_loop_task_first_ps1_parse_clean` and repo pytest cover script parse health.

## Remaining risks

- Default Cursor Agent output often lacks parseable token lines; `prompt_bytes` and `cli_capture_unparsed` rows remain the usable visibility when that happens.
- `-SkipInitialCursor` still skips implementer-side `AI_LOOP_TOKEN_*` env wiring; only chain open/preserve moved earlier.
- Parallel races on `chain.json` still require operator discipline or `-ForceNewChain` when intentionally replacing a chain.
