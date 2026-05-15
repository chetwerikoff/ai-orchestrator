# Implementer summary

## Changed files

- `scripts/record_token_usage.ps1` — branch `(d)` in `ConvertFrom-CliTokenUsage` for Codex CLI total-only `tokens used` (same line as the number, or number on the following line); commas stripped; `InputTokens`/`OutputTokens` null; `Source` `cli_log`; `Quality` `exact`.
- `tests/test_token_usage.py` — `test_convert_codex_tokens_used_single_line`, `test_convert_codex_tokens_used_multiline`, `test_convert_openai_json_wins_over_codex_tokens_used_text`.
- `.ai-loop/task.md` — active task updated to `014` and includes required scope sections for task-first prompt tests.
- `tasks/014_token_usage_codex_cli_format_fix.md` — queued task spec for this fix.
- `tasks/015_token_usage_step3_wrappers_limits_reports.md` — queued follow-up spec for the remaining token usage work.
- `tasks/task_token_usage_reports_and_journal.md` — restored original user ASK/reference spec.
- `.ai-loop/project_summary.md` — token usage step 2 bullet updated for the fourth parser pattern and JSON precedence.
- `.ai-loop/implementer_summary.md` — this file.

## Tests

- `python -m pytest tests/test_token_usage.py -q` → **17 passed**.
- `python -m pytest -q` → **158 passed**.
- `python -m pytest tests/test_orchestrator_validation.py::test_implementer_prompt_surfaces_scope_blocks -q` → **1 passed** after adding the required scope sections to the active task spec.

## Task-specific verification

- PowerShell `Parser::ParseFile` on `scripts/record_token_usage.ps1` passed.

## Codex CLI forms now parsed

1. Single line (own line): `tokens used 32,372` (case-insensitive; optional surrounding lines).
2. Two lines: `tokens used` then a line with only the comma-grouped integer (e.g. `32,372`).

OpenAI/Claude JSON with input/output fields still runs first and wins when both appear in the same blob.

## Remaining risks / limitations

- Total-only Codex summary cannot supply input vs output split; `input_tokens` / `output_tokens` in JSONL stay null for these records.
- Parser expects a plain integer total (with optional `,` thousands separators), not abbreviated or non-numeric summaries.
