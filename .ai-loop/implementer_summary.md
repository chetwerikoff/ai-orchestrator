# Implementer summary

## Changed files

- `scripts/ai_loop_auto.ps1` (C03) — `Run-CodexReview` now instructs structured JSON for `FIX_PROMPT_FOR_IMPLEMENTER`, adds read priority for `diff_summary.txt`, **Diff size budget**, and **Test execution policy**; `Extract-FixPromptFromFile` parses fenced JSON first (`ConvertFrom-Json`), renders via `Format-FixPromptFromObject`, and falls back to the legacy free-text regex with `Write-Warning` on parse failure or missing JSON.
- `templates/codex_review_prompt.md` — mirrors the live prompt (schema, policies, read order); JSON rules line matches **`ConvertFrom-Json`** like `Run-CodexReview`.
- `tests/test_orchestrator_validation.py` (C03) — `test_extract_fix_prompt_parses_json`, `test_extract_fix_prompt_falls_back_on_invalid_json` (plus existing Codex prompt / parse coverage).
- `.ai-loop/project_summary.md` — Current Stage, Last Completed Task, and Next Likely Steps aligned to C03 (JSON/extractor design bullets were already present).

## Tests

- `python -m pytest -q` → **64 passed**.

## Task-specific commands

- `powershell -NoProfile -Command "[void][System.Management.Automation.Language.Parser]::ParseFile('scripts\ai_loop_auto.ps1', [ref]$null, [ref]$null)"` — covered by `test_powershell_orchestrator_scripts_parse_cleanly` in pytest.
- `.ai-loop/task.md` invocation `ai_loop_task_first.ps1 -NoPush` not run — full orchestrator loop needs live Codex/driver context.

## Implementation summary

- C03: Codex must emit parseable JSON between `FIX_PROMPT_FOR_IMPLEMENTER:` and `FINAL_NOTE:` (or `none`); the extractor prefers that path and writes a deterministic `next_implementer_prompt.md`. Invalid or absent JSON uses the legacy extractor so older reviews still work.
- Template JSON validity rule text now matches the in-script Codex prompt (`ConvertFrom-Json`).

## Remaining risks

- Reviews that still use legacy free-text `FIX_PROMPT_FOR_IMPLEMENTER` trigger the fallback warning for one cycle until Codex adopts JSON — expected.
- Malformed JSON in the fenced block falls back to free text; if Codex mixes broken JSON with no usable legacy text, the fix prompt may be weaker until the next review.
