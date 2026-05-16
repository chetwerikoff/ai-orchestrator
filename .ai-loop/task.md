# Task: Codex review console summary

## Project context

Required reading for the implementer:

- `AGENTS.md`
- `.ai-loop/task.md`
- `.ai-loop/project_summary.md`
- `.ai-loop/repo_map.md`

## Goal

After each Codex review in `scripts/ai_loop_auto.ps1`, emit a short, operator-focused console summary: always show the resolved verdict (`PASS` or `FIX_REQUIRED`); on `FIX_REQUIRED`, add a single-line human-readable reason extracted conservatively from `.ai-loop/codex_review.md` when possible; when Codex output included parseable token usage, show token totals using the same parsing rules as the existing CLI usage pipeline (no invented counts). Full detail remains in `.ai-loop/codex_review.md`.

## Scope

Allowed:

- Add a small internal helper (or reuse existing functions via dot-source) in `scripts/ai_loop_auto.ps1` to build the summary lines from `.ai-loop/codex_review.md` after `Run-CodexReview` / verdict resolution.
- Reuse `ConvertFrom-CliTokenUsage` from `scripts/record_token_usage.ps1` for token extraction from the review artifact text (avoid duplicating regex/parser tables).
- Add/update tests using static fixtures or harness-level checks (no live `codex` CLI).

Not allowed:

- Changing how `PASS` vs `FIX_REQUIRED` is parsed or ordered relative to fix-loop behavior (aside from adding/logging console output).
- Changing staging, commit/push, or C12 queue-protection gates.
- Making token usage parsing or display affect control flow beyond printing.
- Editing `docs/archive/**`, `.ai-loop/_debug/**`, or `ai_loop.py`.

## Files in scope

- `scripts/ai_loop_auto.ps1`
- `scripts/record_token_usage.ps1` ÔÇö only if needed to expose or stabilize a reuse boundary for `ConvertFrom-CliTokenUsage` / merged stdout+stderr text handling without copying parsers
- `tests/test_orchestrator_validation.py`
- `tests/test_token_usage.py` ÔÇö only if token-display logic is tested next to existing usage-parser coverage instead of growing orchestrator tests unnecessarily
- `.ai-loop/project_summary.md`
- `tasks/user_ask_codex_review_console_summary.md`

## Files out of scope

- `docs/archive/**`
- `.ai-loop/_debug/**`
- `ai_loop.py`
- `templates/codex_review_prompt.md` (unless a template change is strictly necessary to guarantee section headings; default is no template change)
- `tasks/**` except paths listed under Files in scope above
- Any other paths not listed under Files in scope

## Required behavior

1. After Codex review completes and the verdict is determined (`Get-CodexVerdict` / equivalent single source of truth already used by the loop), print a compact block to the host console before any follow-on actions (including fix-prompt extraction on `FIX_REQUIRED`).
2. Always print a verdict line using the existing canonical wording/style already used for `Codex verdict: PASS` (extend rather than introducing multiple conflicting verdict labels).
3. For `FIX_REQUIRED` only, print at most one `Codex reason:` line derived from `.ai-loop/codex_review.md`:
   - Scan section headings case-insensitively for severity buckets in priority order: `CRITICAL`, then `HIGH`, then `MEDIUM`.
   - Within the first matching section that contains at least one bullet line with a trimmed payload not equal to `none` (case-insensitive), take the first such bullet.
   - Strip leading markdown bullet markers (`-`, `*`), collapse internal whitespace/newlines to a single line, hard-cap length defensively for terminal usability (pick a reasonable max, e.g., 200ÔÇô260 chars, with ellipsis), and print as `Codex reason: ...`.
   - If no qualifying bullet exists in those sections, omit `Codex reason:` entirely (do not guess from free text).
4. Token usage line(s):
   - Prefer parsing merged review text (same bytes operators rely on today ÔÇö typically `.ai-loop/codex_review.md` content after write) through `ConvertFrom-CliTokenUsage` from `scripts/record_token_usage.ps1`.
   - If a credible total exists (`TotalTokens` or computable total from recognized input/output fields), print `Codex tokens:` using locale-neutral grouping consistent with existing console reporting in this repo (or plain digits if no grouping helper exists).
   - If only partial fields exist but a total is still computable, print the total; optionally include a compact split only when it fits one short line.
   - If no parseable usage exists, omit the token line entirely (do not infer from review length).
5. Always print a single trailing pointer line `See: .ai-loop/codex_review.md` using a repo-relative path form consistent with existing script output on Windows (either forward slashes or `Join-Path`-style display ÔÇö pick one consistent style used nearby in `ai_loop_auto.ps1`).
6. Ensure the summary printing does not alter PASS/FIX branching, resume behavior, or retry loops beyond console output ordering/clarity.
7. Keep the change within the repoÔÇÖs ~80-line preferred edit budget; if reuse forces a small exported helper in `record_token_usage.ps1`, keep it minimal and callable from `ai_loop_auto.ps1`.

## Tests

1. Add coverage that proves the summary formatting rules using representative `.ai-loop/codex_review.md` fixtures (embedded strings), including:
   - `FIX_REQUIRED` path shows verdict + selected reason bullet precedence (`CRITICAL` over `HIGH`, etc.).
   - Missing/empty severity sections yield no `Codex reason:` line (no guessing).
   - Token usage present in Codex-style `tokens used` blocks prints a token line; absent usage omits token line.
2. Prefer extending existing orchestrator harness patterns in `tests/test_orchestrator_validation.py` if they already dot-source relevant functions; otherwise place parser-level tests in `tests/test_token_usage.py` only if it reduces duplication.
3. Run `python -m pytest -q`.

## Verification

- `python -m pytest -q`
- `powershell -NoProfile -Command "[void][System.Management.Automation.Language.Parser]::ParseFile('scripts\\ai_loop_auto.ps1', [ref]$null, [ref]$null)"`
- If `record_token_usage.ps1` changes materially:  
  `powershell -NoProfile -Command "[void][System.Management.Automation.Language.Parser]::ParseFile('scripts\\record_token_usage.ps1', [ref]$null, [ref]$null)"`

## Implementer summary requirements

- Changed files (brief)
- Test result (count, not full output)
- Implemented work (3ÔÇô5 lines)
- Skipped items with reason
- Remaining risks (1ÔÇô3 bullets)

## Project summary update

Update `.ai-loop/project_summary.md` under **Current Stage** / **Last Completed Task** (whichever matches repo convention after this lands) with one short durable sentence: Codex reviews now emit a compact console summary (verdict, optional one-line reason on `FIX_REQUIRED`, optional token totals via shared usage parsing) with details remaining in `.ai-loop/codex_review.md`.

## Output hygiene

- Do not duplicate the full task spec into `.ai-loop/implementer_summary.md`.
- Do not write under `.ai-loop/_debug/**`.
- Do not create a git commit unless a separate human request explicitly asks for it.
- Do not write under `docs/archive/**`.

## Important

- Assumption: `.ai-loop/codex_review.md` remains the authoritative artifact and includes severity headings often enough for the reason heuristic to be useful; when absent, skipping `Codex reason:` is expected behavior.
- Implementer must avoid printing duplicate `Codex verdict:` lines on paths that already printed them ÔÇö consolidate via one helper call rather than stacking legacy prints.
- Architect note: USER ASK allowed `Codex tokens: unavailable`; this task omits the token line when usage is not parseable to keep console output minimal and avoid implying a definitive ÔÇ£missing metricÔÇØ state that could be confused with a tooling error.
- Architect note: Reason extraction is intentionally limited to `CRITICAL`/`HIGH`/`MEDIUM` bullet sections only (not full-review scraping) to stay conservative and aligned with the USER ASKÔÇÖs proposed heuristic.

## Order
