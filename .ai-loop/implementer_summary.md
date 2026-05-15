# Implementer summary

## Changed files (7 total)

1. **New:** `templates/reviewer_context.md`
2. **Edited:** `scripts/ai_loop_auto.ps1` (Run-CodexReview `$prompt` here-string only: reading list + diff/test policy text)
3. **Edited:** `templates/codex_review_prompt.md` (reading list + diff/test rules)
4. **Edited:** `scripts/install_into_project.ps1` (Copy-Item for `reviewer_context.md`)
5. **Edited:** `tests/test_orchestrator_validation.py` (three new tests)
6. **Edited:** `.ai-loop/implementer_summary.md` (this file)
7. **Edited:** `.ai-loop/project_summary.md` (C13 bullet, stage, last task)

## Tests

- `python -m pytest tests/test_orchestrator_validation.py -q` — pass (includes `test_reviewer_context_template_exists`, `test_embedded_prompt_uses_reviewer_context_not_agents_as_default`, `test_codex_template_skips_test_output_when_failures_summary_present`).
- `python -m pytest -q` — **155 passed** (full repo).
- PowerShell AST: `ai_loop_auto.ps1` is covered by `test_powershell_orchestrator_scripts_parse_cleanly`; task checklist `Parser::ParseFile` on `install_into_project.ps1` was not re-run in this session (copy-only edit; low risk).

## Implementation

- Added bounded reviewer rules template (≤40 lines) covering editable paths, `tasks/` protection, `SafeAddPaths`, `project_summary.md` discipline, and test policy.
- Embedded Codex prompt and `codex_review_prompt.md` now read `reviewer_context.md` before `AGENTS.md`; conditional wording for `test_output.txt` vs `test_failures_summary.md`; strengthened diff guidance (prefer changed files over full patch).
- Installer copies `reviewer_context.md` into target `.ai-loop/`.

## Skipped

- `.ai-loop/implementer_result.md` — not needed (task completed in-repo).

## Remaining risks

- Models may still open `AGENTS.md` early despite ordering; item 9 keeps an explicit fallback path.
- Existing installs lack `reviewer_context.md` until reinstall or manual copy; `install_into_project.ps1` seeds it for new installs.
