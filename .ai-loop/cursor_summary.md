# Cursor summary — O05 (templates hardening)

- **templates/task.md**: Read-priority block (AGENTS.md first), forbidden paths (`docs/archive/`, `.ai-loop/archive/`, `_debug`), new **Output hygiene** section before **Important**.
- **templates/codex_review_prompt.md**: Priority-order **Read:** list (`diff_summary` / conditional `test_failures_summary` preferred over raw artefacts when present), deferral sentence before **Return exactly:**; **`VERDICT: PASS or FIX_REQUIRED`**, **`FIX_PROMPT_FOR_CURSOR:`**, **`FINAL_NOTE:`** unchanged in the required block.
- **templates/project_summary.md**: Top HARD RULES HTML comment + **`AGENTS.md`** pointer; **Last completed task** constrained to most recent only.
- **templates/cursor_summary_template.md**: HARD RULES comment + **`AGENTS.md`** note; italic **~N lines** targets merged into **`##`** headers (ordering unchanged).

**Tests:** `python -m pytest -q` → **24 passed**.

**Verification:** Critical Codex delimiter strings intact in template; template line budgets met (counts checked via tooling).

**Risks:** Target projects copied before reinstall keep old stubs until `install_into_project.ps1` is re-run manually.
