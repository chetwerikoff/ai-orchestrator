# Implementer summary

## Changed files

- `templates/task.md` — appended optional final `## Order` section with HTML note; blank-by-default for standalone tasks.
- `templates/planner_prompt.md` — documented `## Order` in Output format (series numbering rules, self-contained tasks).
- `scripts/ai_loop_plan.ps1` — after successful `.ai-loop/task.md` write, optional queue copy to repo-root `tasks/NNN_slug.md` when `## Order` captures a positive integer; non-fatal `try/catch`.
- `tests/test_orchestrator_validation.py` — `test_order_regex_match`, `test_order_slug_derivation`, `test_order_queue_filename_format`; extended `test_ai_loop_plan_structural_invariants` for queue-save markers.
- `.ai-loop/project_summary.md` — C10 planner queue behavior and Current Stage / Last Completed Task updates.

## Regex / slug (mirror of planner script)

- Order capture: `(?m)^##\s+Order\s*\r?\n\s*(\d+)`
- Slug: lowercase → replace runs of non-alphanumeric with `_` → strip leading/trailing `_` → truncate to 40 chars and trim trailing `_`.
- Queue filename: PowerShell ``tasks\{0:000}_{1}.md -f $N, $slug``; pytest uses Python ``"{0:03d}_{1}.md".format(...)`` (same zero-padding width; Python `{0:000}` is not the PS `-f` specifier).

## Tests

- Command: `python -m pytest -q`
- Result: **122 passed** (1 unrelated pytest cache warning on Windows).

## Task-specific verification

- PowerShell parse: `Parser::ParseFile` on `scripts\ai_loop_plan.ps1` — **not executed here** (shell invocation rejected in this environment); repo already covers planner scripts via `test_planner_scripts_parse_cleanly` when `powershell`/`pwsh` is on PATH.
- Manual smoke (`Select-String` on templates): skipped here; templates contain `## Order` and planner prompt mentions Order.

## Edge cases beyond spec

- None (empty slug after derivation skips queue write silently).

## Remaining risks

- `tasks/` is not in default `SafeAddPaths`; queue files are not auto-staged by the orchestrator until that literal is extended in sync across drivers and `docs/safety.md`.
- Queue filename derives from `# Task:` title only; duplicate titles overwrite with warning.
