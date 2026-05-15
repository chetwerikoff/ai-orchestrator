# Implementer summary

## Changed files (1)

- `tests/test_orchestrator_validation.py` — `test_agents_protects_queued_tasks` now requires one markdown paragraph or list item that simultaneously mentions `tasks/`, `protected` or both `deletion` and `modification`, and `files in scope` or explicit `task scope` wording (so the lone Git hygiene bullet cannot be removed without failing the test).

## Test result

- `python -m pytest tests/test_orchestrator_validation.py::test_agents_protects_queued_tasks tests/test_orchestrator_validation.py::test_codex_prompt_protects_queued_tasks -q` — pass (2 tests)
- `python -m pytest -q` — pass (134 tests)

## Implemented work

Strengthened the AGENTS.md regression so protection language must live in a single policy unit (paragraph or `-` bullet), matching the C12 Git hygiene bullet contract; file-level `tasks/` mentions alone no longer satisfy the test.

## Skipped items

- Task.md PowerShell parse checks — not requested by the fix prompt; no orchestrator script changes.

## Task-specific outputs / live-run

- No task-specific CLI beyond pytest; full suite run as configured.

## Remaining risks

- Wording refactors that keep the intent but split keywords across bullets could fail the test until copy is consolidated again (intentional guardrail).
