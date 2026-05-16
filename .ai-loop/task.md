# Task: Reliable token usage + single report on PASS

## Project context

- `AGENTS.md`
- `.ai-loop/task.md`
- `.ai-loop/project_summary.md`
- `.ai-loop/repo_map.md`

## Goal

On the normal `ai_loop_task_first.ps1` ÔåÆ `ai_loop_auto.ps1` path ending in Codex PASS, ensure token usage rows are appended to `.ai-loop/token_usage.jsonl` when Codex and Cursor CLIs emit output that `ConvertFrom-CliTokenUsage` already recognizes or can be extended to recognize with **stable, explicit** usage stringsÔÇöwithout making recording fatal, inventing counts, or logging secrets. Also ensure the console token report is not shown twice for the same PASS tail (including the empty-state `No token usage records found.` line).

## Scope

**Allowed:**

- Extend conservative CLI usage parsing only for **real, documented** Cursor/Codex output patterns already observed or verified in this repoÔÇÖs parsers/tests.
- Wire **non-blocking** `Write-CliCaptureTokenUsageIfParsed` (or equivalent existing helper) on the **`Run-CodexReview` joined capture path** in `ai_loop_auto.ps1`, with a clear `script_name`/source label consistent with existing JSONL rows.
- Deduplicate records for a single capture using existing mechanisms (e.g. `-DedupeId` / same-session semantics) so one Codex invocation does not create duplicate rows.
- Adjust `ai_loop_task_first.ps1` vs `ai_loop_auto.ps1` so PASS does not invoke `show_token_report.ps1` redundantly while preserving at least one report when useful (e.g. still show report when task-first runs auto-loop in configurations that skip auto-loopÔÇÖs report).
- Add/adjust unit tests with **no live CLIs** (fixture strings / subprocesses that stub scripts only).

**Not allowed:**

- Changing Codex verdict / review semantics.
- Changing implementer selection or Cursor agent behavior beyond parsing additional **stable** usage text from CLI output.
- Making token recording failures block the loop.
- Estimating tokens from prompt length or storing account identifiers.
- `docs/archive/**`, `.ai-loop/_debug/**`, `ai_loop.py`.

## Files in scope

- `scripts/ai_loop_auto.ps1`
- `scripts/ai_loop_task_first.ps1`
- `scripts/run_cursor_agent.ps1`
- `scripts/record_token_usage.ps1`
- `scripts/show_token_report.ps1` ÔÇö only if required to avoid duplicate empty-state messaging alongside script-level gating
- `tests/test_token_usage.py`
- `tests/test_orchestrator_validation.py` ÔÇö only if task-first / auto-loop chaining tests need updating
- `.ai-loop/project_summary.md` ÔÇö brief durable note if behavior or Cursor visibility limits change

## Files out of scope

- `docs/archive/**`
- `.ai-loop/_debug/**`
- `ai_loop.py`
- `docs/workflow.md` ÔÇö unless a user-facing workflow caveat is strictly necessary after implementation; prefer `project_summary.md` for a short durable note
- `tasks/**`
- `templates/**` (unless installer copy parity is requiredÔÇöunlikely here)

## Required behavior

1. **Codex (auto-loop):** After `Run-CodexReview` yields the joined stdout/stderr string that is already used for `.ai-loop/codex_review.md` (or immediately alongside that capture point), call the existing non-blocking token recorder path so parseable Codex usage appends to `.ai-loop/token_usage.jsonl` with a **distinct, stable** `script_name` / source label (reuse the existing `ai_loop_auto.codex_review` convention if it already matches this capture path; otherwise align naming in one place and update tests accordingly).
2. **Deduping:** For each Codex review capture, ensure duplicate appends do not occur for the same usage block (prefer `-DedupeId` or the existing dedupe contract documented in `Write-CliCaptureTokenUsageIfParsed`).
3. **Cursor:** If the Cursor agent CLI emits additional **stable** usage formats in supported modes, extend `ConvertFrom-CliTokenUsage` only with patterns covered by new fixture tests; if no stable emission exists in-repo, do **not** fabricateÔÇörecord nothing and document the limitation briefly in `.ai-loop/project_summary.md` under token reporting notes.
4. **Report duplication:** Ensure a **single** tail report for the normal task-first PASS path: if `ai_loop_auto.ps1` already printed the report on PASS, `ai_loop_task_first.ps1` must not print it again (including the `No token usage records found.` empty case). Preserve reporting for paths where task-first completes without the auto-loop report.
5. **Regression safety:** Existing JSONL rows and report sections remain backward compatible; tests prove parsing/dedupe/report gating without invoking real `codex`/`cursor`.

## Tests

- Extend `tests/test_token_usage.py` with:
  - Codex stdout/stderr fixture(s) proving the **auto-loop capture path** records rows when parseable.
  - Dedupe proof for a single synthetic capture id (no double rows).
  - Cursor parser additions only with **minimal fixture lines** tied to real formats.
- Update `tests/test_orchestrator_validation.py` only if subprocess/harness coverage is needed for task-first vs auto-loop report fan-out.
- Run `python -m pytest -q`.

## Verification

```powershell
python -m pytest -q
pyright
powershell -NoProfile -Command "[void][System.Management.Automation.Language.Parser]::ParseFile('scripts\ai_loop_auto.ps1', [ref]$null, [ref]$null)"
powershell -NoProfile -Command "[void][System.Management.Automation.Language.Parser]::ParseFile('scripts\ai_loop_task_first.ps1', [ref]$null, [ref]$null)"
powershell -NoProfile -Command "[void][System.Management.Automation.Language.Parser]::ParseFile('scripts\run_cursor_agent.ps1', [ref]$null, [ref]$null)"
powershell -NoProfile -Command "[void][System.Management.Automation.Language.Parser]::ParseFile('scripts\record_token_usage.ps1', [ref]$null, [ref]$null)"
powershell -NoProfile -Command "[void][System.Management.Automation.Language.Parser]::ParseFile('scripts\show_token_report.ps1', [ref]$null, [ref]$null)"
```

## Implementer summary requirements

1. Changed files (brief list).
2. `python -m pytest -q` result (counts only).
3. What was implemented (3ÔÇô5 lines): Codex hook, dedupe, Cursor parser deltas (if any), report de-dup behavior.
4. Skipped items with reason (e.g., no stable Cursor usage string found).
5. Remaining risks (1ÔÇô3 bullets).

## Project summary update

Add or tighten a short **Known limitation** bullet under token reporting if Cursor CLI still emits no parseable usage in current default mode; otherwise note that Codex capture path now records on the same joined output used for review. No unrelated edits.

## Output hygiene

- Do not duplicate the full task narrative into `.ai-loop/implementer_summary.md`.
- Do not write to `.ai-loop/_debug/**`.
- Do not commit.
- Do not write under `docs/archive/**`.

## Important

- Assumption: Duplicate `No token usage records found.` is caused by **back-to-back** `show_token_report.ps1` invocations on the chained task-first PASS path; fix by a narrow flag/handshake already hinted in repo (`ai_loop_auto.ps1` marker comment in `repo_map.md`) or an equivalent minimal guardÔÇödo not broaden scope to other subsystems.
- If a separate `codex_review.md` scrape already appends rows, reconcile with the **joined capture** hook so JSONL does not double-count the same review; prefer one authoritative capture site.
- Architect note: user listed `docs/workflow.md`; this task keeps durable documentation in `.ai-loop/project_summary.md` only to stay within the ~80-line change budget and avoid parallel doc driftÔÇöexpand to `docs/workflow.md` only if human reviewers insist on user-guide visibility.
- Architect note: user proposed ÔÇ£Fix Codex first / Cursor second / duplication thirdÔÇØÔÇöimplementation order is flexible as long as tests cover each behavior; prefer landing **dedupe + single report** early to stabilize CI output.
- Architect note: any Cursor parser extension must include **fixture-backed** proof; absent real samples, ship **documentation-only** for Cursor in `project_summary.md` rather than speculative regexes.

## Order

1
