# Task: Fix reviewer exit-code and em-dash encoding bugs

## Project context
- `AGENTS.md`
- `.ai-loop/task.md`
- `.ai-loop/project_summary.md`

## Goal
Fix two bugs introduced in the C09 planner review loop. First: `run_codex_reviewer.ps1` does not initialize `$exitCode = 1` before its `try` block, so when `codex` throws an exception the wrapper exits 0 instead of 1, silently masking failures. Second: literal em-dash characters (U+2014) in several `.ps1` scripts and `.md` templates are not encoded safely for Windows PowerShell 5.1, producing `?` corruption when the strings are read or embedded and causing the LLM to receive mangled advisory text such as "you are advisory only ? the architect".

## Scope
Allowed:
- Add `$exitCode = 1` before the `try` block in `run_codex_reviewer.ps1`
- Replace literal em-dash characters in `.ps1` files with `[char]0x2014` per project convention
- Add `-Encoding UTF8` to `Get-Content` calls that read `.md` template files in `ai_loop_plan.ps1`
- Replace literal em-dash in `.md` templates with ` -- ` (spaceÔÇôdouble-hyphenÔÇôspace)
- Add targeted pytest coverage for both fixes

Not allowed:
- Changing argument or parameter signatures
- Modifying any script not listed in Files in scope
- Altering `ai_loop_auto.ps1`, `ai_loop_task_first.ps1`, or `continue_ai_loop.ps1`

## Files in scope
- `scripts/run_codex_reviewer.ps1`         fix $exitCode init + em-dash literals
- `scripts/run_claude_planner.ps1`         em-dash literals (verify; fix if present)
- `scripts/ai_loop_plan.ps1`               em-dash in string literals + Get-Content encoding
- `templates/reviewer_prompt.md`           em-dash ÔåÆ ` -- `
- `templates/planner_prompt.md`            em-dash ÔåÆ ` -- `
- `tests/test_orchestrator_validation.py`  add tests for both fixes

## Files out of scope
- `docs/archive/**`
- `.ai-loop/_debug/**`
- `ai_loop.py`
- `scripts/ai_loop_auto.ps1`
- `scripts/ai_loop_task_first.ps1`
- `scripts/continue_ai_loop.ps1`
- All scripts not listed above

## Required behavior
1. Open `scripts/run_codex_reviewer.ps1`. Immediately before the outermost `try` block that invokes `codex`, add `$exitCode = 1` if absent. Verify the `catch` block does not overwrite it, and the `exit $exitCode` at the end propagates the correct code (0 on clean codex run via `$exitCode = $LASTEXITCODE` inside `try`, 1 on exception).
2. In `scripts/run_codex_reviewer.ps1` and `scripts/run_claude_planner.ps1`: scan for any literal em-dash byte (UTF-8: `E2 80 94`). Replace each occurrence in a string with a `[char]0x2014` subexpression, e.g. `"advisory only $([char]0x2014) the architect"`.
3. In `scripts/ai_loop_plan.ps1`: apply the same em-dash substitution to all string literals (including `$revisionInstructions` and any inline prompt fragments). Additionally, for each `Get-Content` call that reads a `.md` template file, add `-Encoding UTF8` if it is absent.
4. In `templates/reviewer_prompt.md` and `templates/planner_prompt.md`: replace every literal em-dash with ` -- `. Do not introduce other prose changes.
5. Run PowerShell parse checks on all modified `.ps1` files. Run `python -m pytest -q` and confirm no regressions.
6. Add targeted tests as described in the Tests section.

## Tests
Add to `tests/test_orchestrator_validation.py`:

- **exit-code test**: Read `scripts/run_codex_reviewer.ps1` as text. Assert the string `$exitCode = 1` appears, and that its position in the file is before the first occurrence of `try {`.
- **em-dash binary tests**: For each of `scripts/run_codex_reviewer.ps1`, `scripts/run_claude_planner.ps1`, and `scripts/ai_loop_plan.ps1`, open in binary mode and assert `b'\xe2\x80\x94'` is not present.

Run: `python -m pytest -q`

## Verification
```powershell
powershell -NoProfile -Command "[void][System.Management.Automation.Language.Parser]::ParseFile('scripts\run_codex_reviewer.ps1', [ref]$null, [ref]$null)"
powershell -NoProfile -Command "[void][System.Management.Automation.Language.Parser]::ParseFile('scripts\run_claude_planner.ps1', [ref]$null, [ref]$null)"
powershell -NoProfile -Command "[void][System.Management.Automation.Language.Parser]::ParseFile('scripts\ai_loop_plan.ps1', [ref]$null, [ref]$null)"
python -m pytest -q
python -c "import sys; d=open('scripts/run_codex_reviewer.ps1','rb').read(); sys.exit(0 if b'\xe2\x80\x94' not in d else 1)"
python -c "import sys; d=open('scripts/ai_loop_plan.ps1','rb').read(); sys.exit(0 if b'\xe2\x80\x94' not in d else 1)"
```

## Implementer summary requirements
1. List each file changed and the specific change (one line per file).
2. Confirm `$exitCode = 1` is now present before `try` in `run_codex_reviewer.ps1`.
3. State which `.ps1` files had literal em-dashes and how many were replaced (or "none found" per file).
4. Test result: pass/fail count only.
5. Any remaining risks or edge cases.

## Project summary update
No update needed. These are targeted bug fixes; current stage and risk notes remain accurate.

## Output hygiene
- Do not duplicate task content into `.ai-loop/project_summary.md`.
- Do not write debug output to `.ai-loop/_debug/` unless wrap-up is active.
- Do not commit ÔÇö the orchestrator handles git.
- Do not write to `docs/archive/`.

## Important
- **Bug 1 (exit code)**: The reference pattern is `run_claude_planner.ps1`, which initializes `$exitCode = 1` before its `try`, then sets `$exitCode = $LASTEXITCODE` after the command inside `try`. `run_codex_reviewer.ps1` is missing the initialization, so an unhandled exception leaves `$exitCode` as `$null` ÔåÆ `exit $null` ÔåÆ exit 0. One-line fix; verify the catch block does not accidentally reset `$exitCode` to 0.
- **Bug 2 (em-dash encoding)**: AGENTS.md already mandates `[char]0x2014` in `.ps1` sources for exactly this reason. The `.md` templates are read by PowerShell 5.1 `Get-Content` (defaulting to Windows-1252) before being forwarded to the LLM; the two-part fix (replace em-dashes in `.md` with ` -- ` AND add `-Encoding UTF8` to the reader) is belt-and-suspenders and the safest cross-editor approach.
- **Architect note**: The user's implicit suggestion of "re-save as UTF-8 with BOM" was considered and rejected. BOM presence is invisible in most editors, fragile across Git operations, and not auditable in code review. Replacing em-dashes in prose templates with ` -- ` is semantically equivalent for LLM consumption and permanently eliminates the encoding variable.
- Implementer must check **all three** `.ps1` files for literal em-dashes even if the user only mentioned some; the corruption may be present wherever the planner/reviewer advisory text was copy-pasted.
- Total code change is well under 40 lines. No split into subtasks is needed.
