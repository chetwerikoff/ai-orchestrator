# Task: Reduce Codex review context with bounded reviewer artifacts

## Project context

Required reading before starting (in order; stop when you have enough):

1. `AGENTS.md` ÔÇö working rules and forbidden paths
2. `.ai-loop/task.md` ÔÇö this task
3. `.ai-loop/project_summary.md` ÔÇö durable project orientation
4. `.ai-loop/implementer_summary.md` ÔÇö only if this is iteration 2+

Do not read by default:

- `docs/archive/` ÔÇö superseded design documents
- `.ai-loop/archive/` ÔÇö historical task rolls
- `.ai-loop/_debug/` ÔÇö raw agent stdout, debug-only

## Goal

Reduce tokens consumed during Codex review by replacing AGENTS.md (full working rules) with a short `reviewer_context.md` scoped to what the reviewer actually needs, and by updating the reading rule for test output so `test_output.txt` is not read by default when `test_failures_summary.md` is present. Three concrete deliverables: (1) create `templates/reviewer_context.md` (Ôëñ40 lines), (2) update the reading list and conditional rules in both `scripts/ai_loop_auto.ps1`'s embedded `Run-CodexReview` `$prompt` here-string and `templates/codex_review_prompt.md`, (3) install the new template via `scripts/install_into_project.ps1` and add three targeted tests.

## Scope

Allowed:
- Create `templates/reviewer_context.md`
- Edit `scripts/ai_loop_auto.ps1` ÔÇö embedded `$prompt` here-string in `Run-CodexReview` only
- Edit `templates/codex_review_prompt.md` ÔÇö reading list and test/diff rules
- Edit `scripts/install_into_project.ps1` ÔÇö add one `Copy-Item` line for `reviewer_context.md`
- Edit `tests/test_orchestrator_validation.py` ÔÇö add three test functions
- Edit `.ai-loop/implementer_summary.md` ÔÇö post-iteration summary
- Edit `.ai-loop/project_summary.md` ÔÇö durable C13 bullet

Not allowed:
- Change `Run-CodexReview` function logic (only the `$prompt` here-string content)
- Modify `AGENTS.md` content
- Change git staging, commit, or push logic
- Delete or modify queued task specs under `tasks/`
- Add new PowerShell functions or subsystems
- Create `test_output_tail.txt` or other new runtime artifacts
- Convert the single-quoted here-string `@'...'@` to double-quoted `@"..."@`

## Files in scope

- `templates/reviewer_context.md` (new)    reviewer-scoped rules, Ôëñ40 lines
- `scripts/ai_loop_auto.ps1`               `$prompt` here-string inside `Run-CodexReview` only
- `templates/codex_review_prompt.md`       reading list and conditional test/diff rules
- `scripts/install_into_project.ps1`       one new `Copy-Item` line
- `tests/test_orchestrator_validation.py`  three new test functions
- `.ai-loop/implementer_summary.md`        post-iteration summary
- `.ai-loop/project_summary.md`            C13 bullet under Important Design Decisions

## Files out of scope

- `docs/archive/**`
- `.ai-loop/_debug/**`
- `ai_loop.py`
- `AGENTS.md`
- `scripts/ai_loop_task_first.ps1`
- `scripts/ai_loop_plan.ps1`
- All other sections of `scripts/ai_loop_auto.ps1` beyond the `$prompt` here-string
- `tasks/` ÔÇö leave all existing queued specs unmodified

## Required behavior

### 1. `templates/reviewer_context.md`

Create a new file with reviewer-relevant rules only. Must stay Ôëñ40 lines. Required content sections (brief, no verbatim duplication of AGENTS.md):

- **Editable paths**: what the implementer may and must not edit (working scope from AGENTS.md)
- **Queued task spec protection**: do not suggest deleting `tasks/*.md` unless the active task includes them in scope; they are queued specs, not scratch outputs
- **Safe staging expectations**: which paths `SafeAddPaths` stages (from AGENTS.md safe paths section)
- **`project_summary.md` update rule**: update only for durable architecture decisions, not task logs
- **Test execution policy**: orchestrator already ran pytest; no full-suite rerun; targeted single-test run allowed only when a specific finding requires it, with a one-line reason in `FINAL_NOTE`

### 2. Updated reading list in embedded prompt and template

Replace the reading list in **both** `scripts/ai_loop_auto.ps1` (`Run-CodexReview` `$prompt`) and `templates/codex_review_prompt.md` with:

```
Read in this priority order (stop reading once verdict is clear):

1. `.ai-loop/task.md` ÔÇö current task contract
2. `.ai-loop/reviewer_context.md` ÔÇö bounded working-rules summary (preferred over AGENTS.md)
3. `.ai-loop/implementer_summary.md` ÔÇö implementer's report on the latest iteration
4. `.ai-loop/diff_summary.txt` ÔÇö short git diff --stat
5. `.ai-loop/test_failures_summary.md` ÔÇö filtered failures (read when present; do not read test_output.txt unless this summary is absent or insufficient)
6. `.ai-loop/last_diff.patch` ÔÇö full diff only when exact patch context is required for a specific finding; prefer reading only the changed files relevant to that finding
7. `.ai-loop/test_output.txt` ÔÇö raw pytest output (read only when test_failures_summary.md is absent or insufficient)
8. `.ai-loop/git_status.txt` ÔÇö short porcelain status
9. `AGENTS.md` ÔÇö full working rules (read only when reviewer_context.md is insufficient)
```

Key changes from current reading list:
- `reviewer_context.md` is item 2 (replaces AGENTS.md as default reading)
- `AGENTS.md` moves to item 9 as explicit fallback
- Item 5 explicitly says skip `test_output.txt` when failures summary is present
- Item 6 strengthened: prefer reading only changed files; full patch only when exact context required
- Item 7 is now conditional

The two files (embedded prompt and template) do not need to be character-identical, but the reading list order and conditional rules must match.

### 3. `scripts/install_into_project.ps1`

Add one `Copy-Item` line beside the existing `codex_review_prompt.md` copy:

```powershell
Copy-Item (Join-Path $Root "templates\reviewer_context.md") (Join-Path $TargetAiLoop "reviewer_context.md") -Force
```

### 4. Tests in `tests/test_orchestrator_validation.py`

Add three test functions using the existing `_extract_run_codex_review_prompt_literal()` helper and file-read patterns already present:

- `test_reviewer_context_template_exists()` ÔÇö asserts `templates/reviewer_context.md` exists, `len > 0`, and line count Ôëñ40
- `test_embedded_prompt_uses_reviewer_context_not_agents_as_default()` ÔÇö extracts the `Run-CodexReview` `$prompt` literal; asserts `"reviewer_context.md"` appears in the literal; asserts the index of `"reviewer_context.md"` is less than the index of `"AGENTS.md"` (AGENTS.md only as fallback)
- `test_codex_template_skips_test_output_when_failures_summary_present()` ÔÇö reads `templates/codex_review_prompt.md`; asserts `"test_failures_summary.md"` appears before `"test_output.txt"`; locates the line containing `"test_output.txt"` and asserts that at least one of `"absent"`, `"insufficient"`, or `"only when"` appears within the same line or within 3 lines before or after it (proximity check, not file-wide)

## Tests

```
python -m pytest tests/test_orchestrator_validation.py::test_reviewer_context_template_exists -v
python -m pytest tests/test_orchestrator_validation.py::test_embedded_prompt_uses_reviewer_context_not_agents_as_default -v
python -m pytest tests/test_orchestrator_validation.py::test_codex_template_skips_test_output_when_failures_summary_present -v
python -m pytest -q
```

Verify all three new tests pass and all existing tests continue to pass, especially:
- `test_run_codex_review_prompt_preserves_literal_json_fence`
- `test_codex_review_template_shows_nested_json_fence`
- `test_codex_template_reads_test_failures_before_raw_pytest_output`
- `test_codex_prompt_protects_queued_tasks`

## Verification

1. `python -m pytest tests/test_orchestrator_validation.py -q` ÔÇö all tests pass
2. Count lines in `templates/reviewer_context.md` ÔÇö must be Ôëñ40
3. `grep -n "reviewer_context" scripts/ai_loop_auto.ps1` ÔÇö confirmed in embedded prompt
4. `grep -n "reviewer_context" templates/codex_review_prompt.md` ÔÇö confirmed in template
5. `grep -n "reviewer_context" scripts/install_into_project.ps1` ÔÇö confirmed in installer
6. `grep -n "test_output.txt" templates/codex_review_prompt.md` ÔÇö only appears with conditional wording near it ("absent" or "insufficient" on the same or adjacent line)
7. PowerShell parse check for edited scripts:

```powershell
powershell -NoProfile -Command "[void][System.Management.Automation.Language.Parser]::ParseFile('scripts\ai_loop_auto.ps1', [ref]$null, [ref]$null)"
powershell -NoProfile -Command "[void][System.Management.Automation.Language.Parser]::ParseFile('scripts\install_into_project.ps1', [ref]$null, [ref]$null)"
```

## Implementer summary requirements

Update `.ai-loop/implementer_summary.md` with:

1. Changed files: 1 new (`templates/reviewer_context.md`) + 6 edited (`scripts/ai_loop_auto.ps1`, `templates/codex_review_prompt.md`, `scripts/install_into_project.ps1`, `tests/test_orchestrator_validation.py`, `.ai-loop/implementer_summary.md`, `.ai-loop/project_summary.md`) = 7 total.
2. Test result (all pass, including 3 new test functions).
3. What was implemented (reviewer_context.md, updated reading lists, installer line, tests).
4. What was skipped and why.
5. Remaining risks (e.g., Codex may ignore `reviewer_context.md` and read AGENTS.md anyway; mitigated by listing `reviewer_context.md` first and AGENTS.md as explicit fallback at item 9).

## Project summary update

Add one concise bullet under "Important Design Decisions":

```
- **C13 Codex review context reduction:** Replaced AGENTS.md as default reviewer reading
  with bounded `templates/reviewer_context.md` (Ôëñ40 lines, reviewer-scoped rules only).
  test_output.txt now conditional on test_failures_summary.md being absent or insufficient.
  AGENTS.md kept as explicit fallback (item 9 in reading list).
```

Update "Last Completed Task" to this task and "Current Stage" accordingly.

## Output hygiene

- Do not write to `.ai-loop/_debug/`
- Do not commit or push
- Do not delete or modify existing queued task specs under `tasks/`
- Do not add new PowerShell functions; only change the `$prompt` here-string content in `Run-CodexReview`
- `templates/reviewer_context.md` must be Ôëñ40 lines ÔÇö keep it bounded

## Important

- The embedded `$prompt` in `Run-CodexReview` uses a single-quoted here-string (`@'...'@`). Do not convert it to double-quoted (`@"..."@`) ÔÇö that would break the fenced JSON block inside. Edit only the reading list and rule text inside the existing single-quoted block.
- Existing test `test_run_codex_review_prompt_preserves_literal_json_fence` asserts `$prompt = @'` ÔÇö it will fail if the quote style changes.
- The existing helper `_extract_run_codex_review_prompt_literal()` in `test_orchestrator_validation.py` should be reused in the new embedded-prompt test rather than duplicating the extraction logic.
- Existing test `test_codex_template_reads_test_failures_before_raw_pytest_output` already checks ordering; the new test `test_codex_template_skips_test_output_when_failures_summary_present` adds a proximity-based conditional-wording assertion and must not duplicate what the existing test covers.
- Keep `templates/codex_review_prompt.md` and the embedded `$prompt` structurally consistent in reading list order and conditional rules; character-identical wording is not required.
- The "Check" verdict section of the Codex prompt (was task completed, are tests meaningful, etc.) is unchanged ÔÇö only the reading list and test/diff rules are updated.
- `templates/reviewer_context.md` is a static file installed to `.ai-loop/reviewer_context.md` in target projects; it is not generated at runtime. The installer copies it alongside `codex_review_prompt.md`.
- Reviewer issue [logic] accepted: file count in implementer summary requirements corrected to 1 new + 6 edited = 7 total, consistent with `## Files in scope`.

## Order

13
