# Task: Cursor planner + Claude architecture reviewer (variant A)

## Project context
- `AGENTS.md`
- `.ai-loop/task.md`
- `.ai-loop/project_summary.md`
- `.ai-loop/repo_map.md`

## Goal

Add an opt-in planning mode where Cursor (or any `-PlannerCommand`) drafts `task.md` and Claude reviews it for architectural, scope, and safety issues. With `-WithReview -NoRevision`, the review is a single pass: if blocking issues are found the script exits 2 without writing `.ai-loop/task.md`; the human is the revision loop. Claude as default planner and the existing `-WithReview` revision loop remain completely unchanged.

## Scope

Allowed:
- Create `scripts/run_claude_reviewer.ps1`
- Create `templates/claude_task_reviewer_prompt.md`
- Modify `scripts/ai_loop_plan.ps1` (add `-NoRevision` switch, extend category regex, lighter reviewer context when `-NoRevision`, Claude reviewer prompt lookup, variant A exit behavior)
- Modify `scripts/install_into_project.ps1` to copy `claude_task_reviewer_prompt.md` (AGENTS.md templates contract)
- Add `tests/test_claude_reviewer.py`
- Update `docs/workflow.md` with a brief note about the new mode
- Update `.ai-loop/project_summary.md`

Not allowed:
- Changing default `-PlannerCommand` or `-ReviewerCommand` values
- Modifying the existing `-WithReview` revision loop (without `-NoRevision`)
- Adding auto-revision to this variant
- Touching `scripts/ai_loop_task_first.ps1`, `scripts/ai_loop_auto.ps1`, `scripts/continue_ai_loop.ps1`
- Touching `scripts/run_codex_reviewer.ps1` or `scripts/run_claude_planner.ps1`
- Touching `docs/architecture.md`

## Files in scope

- `scripts/run_claude_reviewer.ps1` (new)
- `templates/claude_task_reviewer_prompt.md` (new)
- `scripts/ai_loop_plan.ps1`
- `scripts/install_into_project.ps1`  add copy of `claude_task_reviewer_prompt.md` alongside `reviewer_prompt.md`
- `tests/test_claude_reviewer.py` (new)
- `docs/workflow.md`
- `.ai-loop/project_summary.md`

## Files out of scope

- `scripts/ai_loop_task_first.ps1`
- `scripts/ai_loop_auto.ps1`
- `scripts/continue_ai_loop.ps1`
- `scripts/run_codex_reviewer.ps1`
- `scripts/run_claude_planner.ps1`
- `docs/architecture.md`
- `docs/archive/**`
- `.ai-loop/_debug/**`
- `ai_loop.py`

## Required behavior

1. **`scripts/run_claude_reviewer.ps1`** ÔÇö mirror `run_claude_planner.ps1` exactly: no `param()` block; reads prompt via `$input | Out-String`; parses `--model` from `$args`; default model `claude-haiku-4-5-20251001`; calls `$promptText | claude --print --model $model`; same `$ErrorActionPreference` save/restore pattern; `$exitCode = 1` before `try`, sets `$exitCode = $LASTEXITCODE` inside; `exit $exitCode`. No `ConvertTo-CrtSafeArg` needed.

2. **`templates/claude_task_reviewer_prompt.md`** ÔÇö role: **Architecture Reviewer**. You receive a draft `task.md` and raw user ASK. Identify blocking architectural, scope, or safety issues only. Output rules (strict): exactly one of `NO_BLOCKING_ISSUES` (bare line, nothing else) or an `ISSUES:` block where every non-blank line matches `- [architecture|scope|missing|safety|logic|complexity] <text>`. No preamble, no task rewrite, no full `task.md` echo. Flag only: wrong scope for stated goal, invented file paths, missing critical safety constraint, architectural conflict with `AGENTS.md` or `project_summary.md`, missing required behavior that makes the task unimplementable. When in doubt, prefer `NO_BLOCKING_ISSUES`.

3. **`scripts/ai_loop_plan.ps1` ÔÇö change A**: add `-NoRevision` switch parameter to the `param()` block.

4. **`scripts/ai_loop_plan.ps1` ÔÇö change B**: extend `Test-ReviewerOutputStrict` category regex (currently near line 104) from `(logic|complexity|scope|missing)` to `(logic|complexity|scope|missing|architecture|safety)`. This is additive; existing Codex reviewer output still passes.

5. **`scripts/ai_loop_plan.ps1` ÔÇö change C**: lighter reviewer context when `-NoRevision` is set. Omit `repo_map.md` from the reviewer prompt. Reviewer receives (in order): reviewer prompt content + `## AGENTS.md` + agents content + `## Project Summary` + project summary content + `## Raw User ASK` + ask text + `## Draft task.md` + draft content. No `planner_prompt.md` included.

6. **`scripts/ai_loop_plan.ps1` ÔÇö change D**: Claude task reviewer prompt lookup. When `$ReviewerCommand` contains the string `run_claude_reviewer` (case-insensitive), attempt to load: (1) `.ai-loop/claude_task_reviewer_prompt.md`, (2) `templates/claude_task_reviewer_prompt.md`. If neither found, emit `Write-Warning` and fall back to the existing reviewer prompt variable.

7. **`scripts/ai_loop_plan.ps1` ÔÇö change E**: `-NoRevision` without `-WithReview` emits `Write-Warning "-NoRevision has no effect without -WithReview"` and continues normally.

8. **`scripts/ai_loop_plan.ps1` ÔÇö change F**: when both `-NoRevision` and `-WithReview` are set, clamp `$MaxReviewIterations` to 1 internally before entering the reviewer block (one review pass, no revision loop).

9. **`scripts/ai_loop_plan.ps1` ÔÇö change G**: variant A exit behavior. When `-NoRevision` is set and the reviewer returns `ISSUES`: write to `.ai-loop/planner_review_trace.md` the line `REVIEW_STATUS: BLOCKING_ISSUES_FOUND -- task.md was NOT written` followed by the issues list; print the issues to console with `-ForegroundColor Red`; do NOT write `.ai-loop/task.md`; `exit 2`. When `NO_BLOCKING_ISSUES`: write `task.md` as normal. When `MALFORMED`: `Write-Warning`, write `task.md` anyway (same degraded behavior as today).

10. **`scripts/install_into_project.ps1`** ÔÇö add a copy step for `templates/claude_task_reviewer_prompt.md` ÔåÆ `.ai-loop/claude_task_reviewer_prompt.md` alongside the existing `reviewer_prompt.md` copy, so installed target projects get the Claude reviewer prompt.

## Tests

Add `tests/test_claude_reviewer.py`:

- **test_run_claude_reviewer_parse_check** ÔÇö `Parser::ParseFile` on `scripts/run_claude_reviewer.ps1`; assert exit code 0.
- **test_claude_task_reviewer_prompt_exists** ÔÇö `assert Path("templates/claude_task_reviewer_prompt.md").exists()`.
- **test_reviewer_strict_accepts_architecture_and_safety** ÔÇö dot-source `scripts/ai_loop_plan.ps1` in a subprocess; call `Test-ReviewerOutputStrict` with `"ISSUES:\n- [architecture] bad scope\n- [safety] missing guard"`; assert result equals `"ISSUES"`.
- **test_reviewer_strict_rejects_unknown_category** ÔÇö same harness with `"ISSUES:\n- [unknown] something"`; assert result equals `"MALFORMED"`.
- **test_claude_reviewer_default_model_is_haiku** ÔÇö read `scripts/run_claude_reviewer.ps1`; assert `"haiku"` appears in content (case-insensitive).

Run: `python -m pytest -q tests/test_claude_reviewer.py`

Full suite: `python -m pytest -q`

## Verification

```powershell
powershell -NoProfile -Command "[void][System.Management.Automation.Language.Parser]::ParseFile('scripts\run_claude_reviewer.ps1', [ref]`$null, [ref]`$null)"
powershell -NoProfile -Command "[void][System.Management.Automation.Language.Parser]::ParseFile('scripts\ai_loop_plan.ps1', [ref]`$null, [ref]`$null)"
python -m pytest -q tests/test_claude_reviewer.py
python -m pytest -q
```

## Implementer summary requirements

1. Files created and modified, one line each.
2. Exact regex change in `Test-ReviewerOutputStrict` (before/after one-liner).
3. How lighter reviewer context (no repo_map when `-NoRevision`) was implemented ÔÇö which code block, approximate line number.
4. Default model for `run_claude_reviewer.ps1` confirmed.
5. `install_into_project.ps1` copy step confirmed (template contract).
6. Test result: pass/fail count; one or two forward risks for variant B (auto-revision).

## Project summary update

Add to **Current Architecture**: `scripts/run_claude_reviewer.ps1` ÔÇö Claude Haiku-based architecture reviewer for opt-in cheap planning mode; invoked with `-PlannerCommand <cursor-wrapper> -ReviewerCommand run_claude_reviewer.ps1 -WithReview -NoRevision`; variant A only (no auto-revision loop); `Test-ReviewerOutputStrict` extended with `[architecture|safety]` categories (backward compatible); reviewer context omits `repo_map.md`; `task.md` not written on blocking issues (`exit 2`). `templates/claude_task_reviewer_prompt.md` installed to `.ai-loop/claude_task_reviewer_prompt.md` by `install_into_project.ps1`.

## Output hygiene

- Do not commit.
- Do not write to `.ai-loop/_debug/`.
- Do not write to `docs/archive/`.
- Do not duplicate task detail into `project_summary.md`.

## Important

- **SAFETY RULE**: when `-NoRevision` is set and reviewer returns `ISSUES`, `.ai-loop/task.md` MUST NOT be written. Exit 2. Human is the revision loop in variant A ÔÇö this is non-negotiable.
- **BACKWARD COMPAT**: the existing `-WithReview` code path (without `-NoRevision`) must behave exactly as before. The only changes touching that path are: (1) the additive category regex extension in `Test-ReviewerOutputStrict` and (2) the Claude reviewer prompt lookup (falls back to existing prompt when template not found). No other existing behavior changes.
- `run_claude_reviewer.ps1` wraps `claude --print` (same as `run_claude_planner.ps1`), NOT `codex exec`. Do not reuse the `run_codex_reviewer.ps1` invocation pattern.
- `Test-ReviewerOutputStrict` is dot-sourced in tests; do not change its function signature.
- **Architect note**: user's proposal omitted `scripts/install_into_project.ps1`; added to scope per AGENTS.md templates contract ÔÇö when a file is added to `templates/`, the installer must be updated to copy it into target projects.
- The `run_claude_reviewer` string-match lookup for the Claude-specific prompt (change D) is intentionally loose (substring, case-insensitive) so that wrapper variants like `.\scripts\run_claude_reviewer.ps1` or `run_claude_reviewer` all match.
