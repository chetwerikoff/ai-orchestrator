# Task: Reduce Codex review context with bounded reviewer artifacts

## Project context

Required reading before starting (in order; stop when you have enough):

1. `AGENTS.md` at repo root — working rules and forbidden paths
2. `.ai-loop/task.md` — this task
3. `.ai-loop/project_summary.md` — durable project orientation
4. `.ai-loop/implementer_summary.md` — only if this is iteration 2+

Do not read by default:

- `docs/archive/` — superseded design documents
- `.ai-loop/archive/` — historical task rolls
- `.ai-loop/_debug/` — raw agent stdout, debug-only

## Goal

Reduce tokens consumed during Codex review by replacing AGENTS.md (full working rules) with a short `reviewer_context.md` scoped to what the reviewer actually needs, and by changing the reading rule for test output so `test_output.txt` is not read by default when `test_failures_summary.md` is present.

Three concrete changes:

1. **New `templates/reviewer_context.md`** — a short (<=40 lines) static file with only reviewer-relevant rules extracted from AGENTS.md: working scope, queued `tasks/*.md` protection, safe staging expectations, `project_summary.md` update rule, no full-pytest-rerun rule. AGENTS.md stays as explicit fallback at item 9 in the reading list.
2. **Update embedded `Run-CodexReview` prompt** in `scripts/ai_loop_auto.ps1` and `templates/codex_review_prompt.md` — replace AGENTS.md with `reviewer_context.md` in reading list; strengthen the `test_failures_summary.md`-first rule so `test_output.txt` is read only when the summary is absent or explicitly insufficient; strengthen the `last_diff.patch` rule to prefer reading only changed files relevant to findings.
3. **Install** `templates/reviewer_context.md` via `scripts/install_into_project.ps1`.

## Scope

Allowed:
- Create `templates/reviewer_context.md`
- Edit `scripts/ai_loop_auto.ps1` — embedded `Run-CodexReview` `$prompt` here-string only
- Edit `templates/codex_review_prompt.md`
- Edit `scripts/install_into_project.ps1` — add one `Copy-Item` line for `reviewer_context.md`
- Edit `tests/test_orchestrator_validation.py` — add 2-3 test functions

Not allowed:
- Change `Run-CodexReview` function logic (only the `$prompt` here-string content)
- Modify `AGENTS.md` content
- Change git staging, commit, or push logic
- Delete or modify queued task specs under `tasks/`
- Add new PowerShell functions or subsystems
- Create `test_output_tail.txt` or other new runtime artifacts

## Files in scope

- `templates/reviewer_context.md` — new file (create)
- `scripts/ai_loop_auto.ps1` — embedded `$prompt` here-string in `Run-CodexReview` only
- `templates/codex_review_prompt.md` — reading list and test/diff rules
- `scripts/install_into_project.ps1` — one new `Copy-Item` line
- `tests/test_orchestrator_validation.py` — new test functions

## Files out of scope

- `docs/archive/**`
- `.ai-loop/_debug/**`
- `ai_loop.py`
- `AGENTS.md`
- `scripts/ai_loop_task_first.ps1`, `scripts/ai_loop_plan.ps1`, `scripts/ai_loop_auto.ps1` (except the `$prompt` here-string)
- `tasks/` — leave all existing queued specs unmodified

## Required behavior

### 1. `templates/reviewer_context.md`

Create a new file with reviewer-relevant rules only. Must stay <=40 lines. Required content:

- **Editable paths**: what the implementer may and must not edit (from AGENTS.md working scope)
- **Queued task spec protection**: do not suggest deleting `tasks/*.md` unless the active task includes them in scope; they are queued specs, not scratch outputs
- **Safe staging expectations**: which paths SafeAddPaths stages (from AGENTS.md safe paths section)
- **`project_summary.md` update rule**: update only for durable architecture decisions, not task logs
- **Test execution policy**: orchestrator already ran pytest; no full-suite rerun; targeted single-test run allowed only when a specific finding requires it

### 2. Updated reading list in embedded prompt and template

Replace the reading list in **both** `scripts/ai_loop_auto.ps1` (`Run-CodexReview` `$prompt`) and `templates/codex_review_prompt.md` with:

```
Read in this priority order (stop reading once verdict is clear):

1. `.ai-loop/task.md` — current task contract
2. `.ai-loop/reviewer_context.md` — bounded working-rules summary (preferred over AGENTS.md)
3. `.ai-loop/implementer_summary.md` — implementer's report on the latest iteration
4. `.ai-loop/diff_summary.txt` — short git diff --stat
5. `.ai-loop/test_failures_summary.md` — filtered failures (read when present; do not read test_output.txt unless this summary is absent or insufficient)
6. `.ai-loop/last_diff.patch` — full diff only when exact patch context is required for a specific finding; prefer reading only the changed files relevant to that finding
7. `.ai-loop/test_output.txt` — raw pytest output (read only when test_failures_summary.md is absent or insufficient)
8. `.ai-loop/git_status.txt` — short porcelain status
9. `AGENTS.md` — full working rules (read only when reviewer_context.md is insufficient)
```

Key changes from current reading list:
- `reviewer_context.md` is item 2 (replaces AGENTS.md as default reading)
- `AGENTS.md` moves to item 9 as explicit fallback
- Item 5 explicitly says skip `test_output.txt` when failures summary is present
- Item 6 strengthened: prefer reading only changed files; full patch only when exact context required
- Item 7 is now conditional

### 3. `install_into_project.ps1`

Add one `Copy-Item` line beside the existing `codex_review_prompt.md` copy (around line 48):

```powershell
Copy-Item (Join-Path $Root "templates\reviewer_context.md") (Join-Path $TargetAiLoop "reviewer_context.md") -Force
```

### 4. Tests in `tests/test_orchestrator_validation.py`

Add three test functions using the existing `_extract_run_codex_review_prompt_literal()` helper and file-read patterns already in the test file:

- `test_reviewer_context_template_exists()` — asserts `templates/reviewer_context.md` exists and len > 0
- `test_embedded_prompt_uses_reviewer_context_not_agents_as_default()` — extracts the `Run-CodexReview` `$prompt` literal; asserts `"reviewer_context.md"` appears in the literal and appears before `"AGENTS.md"` (AGENTS.md only as fallback)
- `test_codex_template_skips_test_output_when_failures_summary_present()` — reads `templates/codex_review_prompt.md`; asserts `"test_failures_summary.md"` appears before `"test_output.txt"` AND at least one of `"absent"`, `"insufficient"`, `"only when"` appears in proximity to `"test_output.txt"`

## Tests

```powershell
python -m pytest tests/test_orchestrator_validation.py::test_reviewer_context_template_exists -v
python -m pytest tests/test_orchestrator_validation.py::test_embedded_prompt_uses_reviewer_context_not_agents_as_default -v
python -m pytest tests/test_orchestrator_validation.py::test_codex_template_skips_test_output_when_failures_summary_present -v
python -m pytest -q
```

Verify:
- All three new tests pass
- All existing tests continue to pass, especially:
  - `test_run_codex_review_prompt_preserves_literal_json_fence`
  - `test_codex_review_template_shows_nested_json_fence`
  - `test_codex_template_reads_test_failures_before_raw_pytest_output`
  - `test_codex_prompt_protects_queued_tasks`

## Verification

1. `python -m pytest tests/test_orchestrator_validation.py -q` — all tests pass
2. `wc -l templates/reviewer_context.md` — <=40 lines
3. `grep -n "reviewer_context" scripts/ai_loop_auto.ps1` — confirmed in embedded prompt
4. `grep -n "reviewer_context" templates/codex_review_prompt.md` — confirmed in template
5. `grep -n "reviewer_context" scripts/install_into_project.ps1` — confirmed in installer
6. `grep -n "test_output.txt" templates/codex_review_prompt.md` — only appears with conditional wording

## Implementer summary requirements

Update `.ai-loop/implementer_summary.md` with:

1. Changed files (4 edited + 1 new = 5 total).
2. Test result (all pass, including 3 new assertions).
3. What was implemented.
4. What was skipped and why.
5. Remaining risks (e.g., Codex may ignore `reviewer_context.md` and read AGENTS.md anyway; mitigated by reviewer_context.md being listed first and AGENTS.md as explicit fallback).

## Project summary update

Add one concise bullet under "Important Design Decisions":

```
- **C13 Codex review context reduction:** Replaced AGENTS.md as default reviewer reading
  with bounded `templates/reviewer_context.md` (<=40 lines, reviewer-scoped rules only).
  test_output.txt now conditional on test_failures_summary.md being absent or insufficient.
  AGENTS.md kept as explicit fallback (item 9 in reading list).
```

Update "Last Completed Task" and "Current Stage" accordingly.

## Output hygiene

- Do not write to `.ai-loop/_debug/`
- Do not commit or push
- Do not delete or modify existing queued task specs under `tasks/`
- Do not add new PowerShell functions; only change the `$prompt` here-string content in `Run-CodexReview`
- `templates/reviewer_context.md` must be <=40 lines — keep it bounded

## Important

- The embedded `$prompt` in `Run-CodexReview` uses a single-quoted here-string (`@'...'@`). Do not convert it to double-quoted (`@"..."@`) — that would break the fenced JSON block. Edit only the reading list and rule text inside the existing single-quoted block.
- Existing test `test_run_codex_review_prompt_preserves_literal_json_fence` asserts `$prompt = @'` — it will fail if the quote style changes.
- The existing helper `_extract_run_codex_review_prompt_literal()` in `test_orchestrator_validation.py` can be reused in the new embedded-prompt test.
- Keep `templates/codex_review_prompt.md` and the embedded `$prompt` structurally consistent. They do not need to be character-identical, but the reading list order and conditional rules must match.
- The "Check" section (was task completed, are tests meaningful, etc.) is unchanged — only the reading list and test/diff rules are updated.

## Order

13
