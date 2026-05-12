# Cursor summary

- **Changed:** `scripts/ai_loop_auto.ps1`, `scripts/ai_loop_task_first.ps1`, `scripts/continue_ai_loop.ps1` — default `SafeAddPaths` literal now includes `AGENTS.md` after `README.md`; `docs/safety.md` safe-staging list matches; `tests/test_orchestrator_validation.py` asserts `AGENTS.md` in default segments; `AGENTS.md` Safe paths paragraph updated to the new literal; `.ai-loop/project_summary.md` design bullet + last task note aligned with O02 fix.
- **`AGENTS.md`:** **78** lines (`readlines()` count); **nine** required `##` headers unchanged.
- **Tests:** `python -m pytest -q` → **24 passed**.
- **`ai_loop_task_first.ps1 -NoPush`:** skipped — interactive Cursor-first orchestrator; not run from this agent session.
- **Implementation:** Per `.ai-loop/next_cursor_prompt.md`: orchestrator final commit can auto-stage `AGENTS.md` without manual `-SafeAddPaths` overrides.
- **Risks:** `README.md` optional-parameters example still documents the older `-SafeAddPaths` string without `AGENTS.md` (cosmetic; default orchestrator behavior uses the scripts’ literal).
