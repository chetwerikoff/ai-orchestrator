# Implementer summary

## Changed files

- `scripts/run_codex_reviewer.ps1` — Removed `ConvertTo-CrtSafeArg` and positional prompt to `codex exec`. Write UTF-8 prompt to `%TEMP%\codex_review_<random>.md`, probe `codex exec --help` for `--file`, then either `codex … exec --file <temp>` or `Get-Content -Raw -Encoding UTF8 | codex … exec`; `Remove-Item` temp in `finally`. Kept `$exitCode = 1` before outer `try` (already present).
- `tests/test_orchestrator_validation.py` — `test_run_codex_reviewer_invariants` updated for temp-file design; added `test_codex_reviewer_no_inline_prompt_arg`, `test_codex_reviewer_exitcode_initialized`, `test_no_emdash_bytes_in_ps1_scripts`.

## Codex invocation

**Hybrid:** capture `codex exec --help` (stdout only, no `2>&1` so the script stays compatible with `test_run_codex_reviewer_invariants`). If help text matches `--file` (case-insensitive), run `codex [--model M] exec --file <tempFile>`. Otherwise pipe file into stdin: `Get-Content -LiteralPath $tempFile -Raw -Encoding UTF8 | codex [--model M] exec`. Avoids argv length limits in both branches; `--file` used when the installed Codex CLI documents it.

## `$exitCode = 1`

Already present before this change; left in place before the outer `try {`.

## Em-dash in `.ps1`

No literal UTF-8 em-dash bytes (`E2 80 94`) in `run_codex_reviewer.ps1`, `run_claude_planner.ps1`, or `ai_loop_plan.ps1` (verified; **0** literal replacements needed). `ai_loop_plan.ps1` already uses `$([char]0x2014)` where an em dash is intended in console output.

## `ai_loop_plan.ps1` / templates

- No `Get-Content` calls reading `.md` in `ai_loop_plan.ps1` (planner/reviewer bodies use `[System.IO.File]::ReadAllText`); no `-Encoding UTF8` additions were applicable.
- `templates/reviewer_prompt.md` and `templates/planner_prompt.md` already use ASCII ` -- ` for dash-like phrasing; no `?` corruption or U+2014 bytes found.

## Tests

`python -m pytest -q` — **119 passed** (1 pre-existing pytest cache warning on Windows).

## Task verification commands

- Full pytest: run as above.
- E2E `.\scripts\ai_loop_plan.ps1 -AskFile tasks\task_add_order_queue_support.md -WithReview` was **not run here** (automated shell blocked executing that script in this session). Run locally to confirm no “filename or extension is too long” from the reviewer step.

## Remaining risks

- If `codex exec --help` prints only to stderr, the `--file` probe may see empty text and always use stdin (still correct, no argv overflow).
- Stdin semantics depend on `codex exec` reading the full prompt from pipeline input; if a given Codex build ignores stdin, use a release that supports `--file` or adjust the wrapper after checking `codex exec --help` on that machine.
