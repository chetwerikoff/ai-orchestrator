# Implementer summary

## Changed files

- `scripts/run_codex_reviewer.ps1` — Set `$exitCode = 1` before the `try` that runs `codex`, matching `run_claude_planner.ps1` so failures before `$LASTEXITCODE` assignment exit non-zero.
- `scripts/ai_loop_plan.ps1` — Replaced five corrupted `?` placeholders in user-facing strings with `$([char]0x2014)` (em dash at runtime).
- `scripts/run_claude_planner.ps1` — No edits; no literal UTF-8 em-dash bytes and no string changes needed.
- `templates/reviewer_prompt.md` — Replaced seven ` ? ` placeholders with ` -- ` per template convention.
- `templates/planner_prompt.md` — Replaced twenty-one ` ? ` placeholders with ` -- `; left real sentence-ending `?` in checklist bullets unchanged.
- `tests/test_orchestrator_validation.py` — Added `test_run_codex_reviewer_initializes_exit_code_before_try` and `test_planner_related_ps1_has_no_utf8_em_dash_literal_bytes`.

## Exit code init

`$exitCode = 1` is present in `run_codex_reviewer.ps1` and occurs before the first `try {`.

## Em dash cleanup (literal `E2 80 94` in sources)

| File | Literal em-dash bytes in file (before) | Replaced in this pass |
|------|----------------------------------------|------------------------|
| `run_codex_reviewer.ps1` | 0 (none) | N/A |
| `run_claude_planner.ps1` | 0 (none) | N/A |
| `ai_loop_plan.ps1` | 0 (none); five strings used `?` corruption | 5 → `$([char]0x2014)` |
| `templates/reviewer_prompt.md` | 0; used `?` placeholders | 7 → ` -- ` |
| `templates/planner_prompt.md` | 0; used `?` placeholders | 21 → ` -- ` |

## Get-Content / template reads

`ai_loop_plan.ps1` has no `Get-Content` calls; template bodies use `[System.IO.File]::ReadAllText`. No `-Encoding UTF8` additions were applicable.

## Tests

- `python -m pytest -q`: **116 passed** (1 PytestCacheWarning on this machine; unrelated to changes). Parser smoke for the three scripts is covered by `test_planner_scripts_parse_cleanly`.

## PowerShell parse

Could not run a standalone `ParseFile` invocation from this agent shell (command rejected); `test_planner_scripts_parse_cleanly` exercises the same AST parse for `run_codex_reviewer.ps1`, `run_claude_planner.ps1`, and `ai_loop_plan.ps1` and passed.

## Remaining risks

- If new prose is pasted into `.ps1` strings with a literal em dash from a Unicode editor, the binary guard test should catch it; reviewers should prefer `$([char]0x2014)` or ASCII ` -- ` in templates.
