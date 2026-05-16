# Task: Token usage reliability (Codex path + report dedupe + Cursor parser)

## Project context

Required reading for the implementer:

- `AGENTS.md`
- `.ai-loop/task.md` (this file, once published)
- `.ai-loop/project_summary.md`
- `.ai-loop/repo_map.md`

## Goal

Improve reliability of appended token-usage rows and console reporting on the normal task-first and auto-loop path: when Codex and Cursor CLIs emit parseable usage, successful passes should persist those rows non-fatally; eliminate back-to-back duplicate token reports (including repeated `No token usage records found.` lines) when `ai_loop_task_first.ps1` chains into `ai_loop_auto.ps1` and the auto-loop already printed the report on PASS.

## Scope

**Allowed:**

- Add or extend non-fatal token capture immediately after Codex review CLI output is captured in the auto-loop (the path that uses `Run-CodexReview` / `codex exec` directly, not only the `run_codex_reviewer.ps1` wrapper used elsewhere).
- Extend `ConvertFrom-CliTokenUsage` only for additional **stable, explicit** Cursor CLI usage patterns already observed in real output (no guessing, no text-length estimation).
- Remove or gate redundant `show_token_report.ps1` invocations so a normal successful task-first PASS does not print the same report twice.
- Add or extend unit tests with subprocess/harness patterns already used in this repo (no live Cursor/Codex CLIs, no git commit/push).
- Brief, accurate documentation of Cursor limitations if the CLI still does not emit a supported format in common modes.

**Not allowed:**

- Changing Codex verdict / review semantics.
- Making token recording fatal to the loop.
- Fabricating token counts or recording secrets / account identifiers.
- Editing `docs/archive/**`, `.ai-loop/_debug/**`, or `ai_loop.py`.
- Broad refactors of orchestration beyond the hooks and call-site coordination described here.

## Files in scope

- `scripts/ai_loop_auto.ps1`
- `scripts/ai_loop_task_first.ps1`
- `scripts/record_token_usage.ps1`
- `scripts/run_cursor_agent.ps1` only if aCursor-specific normalization must occur at capture time before parsing (prefer parser-only changes)
- `tests/test_token_usage.py`
- `tests/test_orchestrator_validation.py` only if an existing harness proves the cleanest place for task-first / auto chaining assertions
- `docs/workflow.md`
- `.ai-loop/project_summary.md`

## Files out of scope

- `docs/archive/**`
- `.ai-loop/_debug/**`
- `ai_loop.py`
- `tasks/context_audit/**` (default)
- Wholesale changes to `scripts/run_codex_reviewer.ps1` unless strictly necessary for shared helpers (the main review loop records from `Run-CodexReview`; avoid parallel recording paths that double-append for the same invocation)

## Required behavior

1. **Codex auto-loop capture:** After `Run-CodexReview` (or the single choke point that already joins Codex stdout/stderr for the review) completes successfully enough to return captured text to the rest of the script, invoke the existing non-blocking helper (`Write-CliCaptureTokenUsageIfParsed` or equivalent in `record_token_usage.ps1`) with a clear `script_name`/provider discriminator (for example `codex` / `ai_loop_auto`) and meaningful metadata when available (model if known, iteration label if cheaply available, repo root hint consistent with other recorders). Recording must not change exit codes or review outcomes.
2. **No double-append for one Codex call:** Ensure the new Codex hook does not write duplicate rows for identical usage parsed from the same review invocation (choose the smallest reliable guard: e.g., single call site, or skip when the parsed fingerprint matches an append in the same run scope).
3. **Cursor parsing:** Extend `ConvertFrom-CliTokenUsage` only when you can point to a concrete, stable pattern (document the exemplar string shape in the implementation comment or test fixture). If unsupported, do not invent parsers; rely on documentation updates.
4. **Report de-duplication:** On the normal task-first path where `ai_loop_task_first.ps1` invokes `ai_loop_auto.ps1` and auto exits zero, do not immediately run `show_token_report.ps1` again if auto already printed the report for that PASS. Preserve a sensible report on paths where auto did not run or did not print (for example non-zero auto exit), without surprising silenceÔÇöprefer the smallest conditional around the task-first tail `show_token_report.ps1` call.
5. **Compatibility:** Existing `.ai-loop/token_usage.jsonl` rows and `show_token_report.ps1` sections remain backward compatible; additions are additive fields or new `script_name` values, not breaking renames.
6. **Docs/summary:** Update `docs/workflow.md` only to reflect user-visible behavior (where reports appear; Cursor limitation if applicable). Update `.ai-loop/project_summary.md` only if durable architecture text about token reporting changes.

## Tests

- Extend `tests/test_token_usage.py` to cover: Codex-like merged output parsing path for the new recorder inputs; any new Cursor pattern with afixture string; dedupe guard behavior if implementable without live CLI.
- Run `python -m pytest -q`; if PowerShell is touched, keep existing parse-check posture for edited scripts (see `AGENTS.md`).

## Verification

- `python -m pytest -q`
- PowerShell parse check on each edited `.ps1` under `scripts/` (copy the one-line `Parser::ParseFile` pattern from `AGENTS.md` for those files).

## Implementer summary requirements

- List changed files briefly.
- State pytest result as a count summary, not a full log.
- Summarize implemented behavior in 3ÔÇô5 lines (Codex hook, dedupe, Cursor parser or doc-only, report tail behavior).
- Note anything skipped with reason.
- List 1ÔÇô3 remaining risks (for example reliance on CLI output stability).

## Project summary update

Update the token-usage / reporting bullets in **Current Architecture** or **Current Stage** if behavior changes (Codex rows from auto-loop; single report per successful task-first PASS). If only tests/helpers change, write **no update needed**.

## Output hygiene

- Do not duplicate the full task narrative into `.ai-loop/implementer_summary.md`.
- Do not write new files under `.ai-loop/_debug/`.
- Do not create a git commit unless a separately scoped task authorizes it.
- Do not edit `docs/archive/**`.

## Important

- Assume **`Run-CodexReview` is the authoritative capture site** for normal Codex review output in `ai_loop_auto.ps1`; hook there rather than expecting `run_codex_reviewer.ps1` to run in that path.
- Keep the change set near the **~80 changed lines** policy; if the combined diff wants to grow, land **Codex recording + dedupe + report gating** first in one iteration, then Cursor parser extensions in a follow-up iteration (still within this taskÔÇÖs files) before expanding scope.
- **Architect note:** User listed `scripts/show_token_report.ps1`; prefer fixing duplicate messages by **coordinating callers** (`ai_loop_auto.ps1` vs `ai_loop_task_first.ps1`) rather than adding stateful de-duplication inside the report script, unless call-site gating is insufficient.
- **Architect note:** User proposed extending Cursor handling in `run_cursor_agent.ps1`; prefer **`ConvertFrom-CliTokenUsage` in `record_token_usage.ps1`** so all CLI wrappers benefit uniformly; touch `run_cursor_agent.ps1` only if capture-time normalization is unavoidable.
- **Architect note:** Dedupe for Codex should mean **one logical write per review invocation**, not weakening parsers or suppressing legitimate later reviews across iterations.

## Order

1
