# Implementer summary

## Changed files

- `scripts/ai_loop_auto.ps1` — `Invoke-CommandToFile` now uses `Out-File -Encoding utf8` (Fix 1).
- `scripts/filter_pytest_failures.py` — `main()` reads bytes first and detects UTF-16 BOM before decoding (Fix 2).
- `tests/test_orchestrator_validation.py` — `test_ai_loop_plan_with_draft_nonfatal_when_draft_command_throws` and `test_scope_filter_excludes_tasks_user_ask` both have `try/finally: shutil.rmtree` (Fix 3 — correct test identified: scope_filter_excl was the actual leaking one).
- `.gitignore` — added `tests/.orch_*/` so leftover scratch dirs from git-repo-creating tests cannot pollute `git status` or `repo_map.md` even when Windows file locks prevent `shutil.rmtree`.
- `.ai-loop/repo_map.md` — removed transient `tests/.orch_scope_filter_excl_*` entries.

## Tests

`python -m pytest -q` — **215 passed**, 1 unrelated PytestCacheWarning. No scratch dirs leaked into git status after run.

## What was implemented

- Fix 1 (UTF-16 output): `*> $OutputFile` replaced with `Out-File -LiteralPath $OutputFile -Encoding utf8`; applies to both `$TestCommand` and `$PostFixCommand` calls automatically.
- Fix 2 (BOM detection): `filter_pytest_failures.py main()` reads raw bytes, checks `\xff\xfe` / `\xfe\xff` BOM, decodes as UTF-16 if matched, otherwise UTF-8 with replace. Placed before `.splitlines()`.
- Fix 3 (real leaking test): Task spec named the wrong test. The actual recurring leak was `test_scope_filter_excludes_tasks_user_ask` (prefix `scope_filter_excl`) which calls `git init` inside scratch dir; Windows git locks prevent cleanup. Added `tests/.orch_*/` to `.gitignore` as defence-in-depth — even if cleanup fails, git will not surface the dirs.
- Both git-repo-creating tests already have `finally: shutil.rmtree(root, ignore_errors=True)`; the gitignore line is the robust backstop.

## Remaining risks

- `shutil.rmtree(root, ignore_errors=True)` may silently fail on Windows for any new test that creates a git repo inside a scratch dir. The `.gitignore` pattern covers all `.orch_*` dirs; future tests with a different prefix would need their own gitignore line.
- `filter_pytest_failures.py` does not handle UTF-32 BOM (`\x00\x00\xfe\xff`); unlikely in practice since PowerShell 5.1 only produces UTF-16 LE or UTF-8.
