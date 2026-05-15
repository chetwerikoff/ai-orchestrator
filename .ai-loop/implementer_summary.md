# Implementer summary

## Changed files

- `scripts/record_token_usage.ps1` — Added `ConvertFrom-CliTokenUsage` (three regex-ordered patterns); added `-Quality` parameter; JSONL now includes `quality` on every record.
- `scripts/show_token_report.ps1` — Replaced report with totals, by-model / by-iteration aggregates, `Path::Combine` paths, empty/malformed JSONL handling ("No token usage records found."), `Write-Host` output, writes `.ai-loop/token_usage_summary.md` (non-fatal on error).
- `scripts/ai_loop_auto.ps1` — Dot-sources recorder; merges Codex stdout+stderr into `codex_review.md`; after each review iteration calls `ConvertFrom-CliTokenUsage` + `Write-TokenUsageRecord` in a non-blocking try path.
- `tests/test_token_usage.py` — Parser test for `ai_loop_auto.ps1`; conversion/write/report/chain tests via PowerShell subprocess.
- `.ai-loop/project_summary.md` — Current stage + last completed task + pwsh Combine note for `show_token_report.ps1`.
- `.gitignore` — No change (`token_usage_summary.md` already listed near `token_usage.jsonl`).

## Tests

- `python -m pytest -q` — **144 passed** (all tests; same run includes 14 tests in `test_token_usage.py`).

## Task-specific CLI

- Verification `ParseFile` for the three `.ps1` scripts: covered by AST parser tests inside `tests/test_token_usage.py` (`test_*_parse_clean` + `test_ai_loop_auto_ps1_parse_clean`). Separate one-liner ParseFile invocation was not run in this shell (sandbox rejected); parity with CI is via pytest harness.

## Implementation notes

- Parsed patterns: Claude API JSON (`input_tokens`/`output_tokens`), OpenAI/Codex-style JSON (`prompt_tokens`/`completion_tokens`), Claude CLI plain text (`Input tokens:` / `Output tokens:` lines).
- Codex hook reads **combined capture** written to `.ai-loop/codex_review.md` immediately after `Run-CodexReview` (stdout merged with stderr via `2>&1` before `Set-Content`), then parses that text — file holds the authoritative combined capture for downstream review and tokens.

## Deferred / unchanged from spec

- None of the forbidden files were touched. Model string stays literal `codex` when Codex emits no finer model identifier in merged output.

## Remaining risks

- Codex or other CLIs changing token/logging format could stop matches until patterns are extended.
- `show_token_report.ps1` summary write can fail disk-permissions paths; surfaced as warnings only while the script exits 0.
- JSON with both Claude and OpenAI key names could match the Claude branch first depending on substring order.
