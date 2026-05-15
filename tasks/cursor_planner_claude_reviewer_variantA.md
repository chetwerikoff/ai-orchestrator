# Task: Cursor planner + Claude architecture reviewer (variant A)

## Project context
- `AGENTS.md`
- `.ai-loop/project_summary.md`
- `.ai-loop/repo_map.md`

## Goal

Add an opt-in cheap planning mode: Cursor (or any -PlannerCommand) drafts task.md,
then Claude reviews it for architecture/scope/safety. If Claude finds blocking issues,
the script exits non-zero and does NOT write .ai-loop/task.md — human fixes and reruns.
No auto-revision loop (variant A). Claude as planner remains the unchanged default.

Invocation:
```powershell
.\scripts\ai_loop_plan.ps1 `
    -AskFile tasks\ask.md `
    -PlannerCommand .\scripts\run_cursor_agent.ps1 `
    -ReviewerCommand .\scripts\run_claude_reviewer.ps1 `
    -WithReview -NoRevision
```

## Scope

Allowed:
- Create `scripts/run_claude_reviewer.ps1`
- Create `templates/claude_task_reviewer_prompt.md`
- Modify `scripts/ai_loop_plan.ps1`: add `-NoRevision` switch; extend `Test-ReviewerOutputStrict`
  to accept `[architecture]` and `[safety]` categories; build lighter reviewer prompt
  (no repo_map) when `-NoRevision` is set; lookup `claude_task_reviewer_prompt.md`
- Add `tests/test_claude_reviewer.py`
- Update `docs/workflow.md`
- Update `.ai-loop/project_summary.md`

Not allowed:
- Changing default `-PlannerCommand` or `-ReviewerCommand` values
- Modifying auto-revision loop for existing `-WithReview` without `-NoRevision`
- Adding auto-revision to variant A (this task is variant A only)
- Touching `ai_loop_task_first.ps1`, `ai_loop_auto.ps1`, `continue_ai_loop.ps1`
- Touching `run_codex_reviewer.ps1` or `run_claude_planner.ps1`

## Files in scope

- `scripts/run_claude_reviewer.ps1` (new)
- `templates/claude_task_reviewer_prompt.md` (new)
- `scripts/ai_loop_plan.ps1`
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

### 1. scripts/run_claude_reviewer.ps1

Mirror structure of `run_claude_planner.ps1`:
- No `param()` block; reads prompt from `$input | Out-String`
- Parses `--model` from `$args`; default model `claude-haiku-4-5-20251001`
- Calls: `$promptText | claude --print --model $model`
- Same `$ErrorActionPreference` save/restore pattern around the `claude` call
- `$exitCode = 1` before `try`; sets `$exitCode = $LASTEXITCODE` inside `try`
- `exit $exitCode`
- No `ConvertTo-CrtSafeArg` needed (prompt via stdin, not CLI arg)

### 2. templates/claude_task_reviewer_prompt.md

Role: **Architecture Reviewer**. You receive a draft `task.md` and raw user ASK.
Identify blocking architectural, scope, or safety issues only.

Output rules (strict):
- EXACTLY one of:
  - `NO_BLOCKING_ISSUES` (bare line, nothing else)
  - `ISSUES:` block where every non-blank line matches:
    `- [architecture|scope|missing|safety|logic|complexity] <text>`
- No preamble. No task rewrite. No full task.md output.
- Flag only: wrong scope for stated goal, invented files, missing critical
  safety constraint, architectural conflict with AGENTS.md or project_summary.md,
  missing required behavior that makes the task unimplementable.
- When in doubt, prefer `NO_BLOCKING_ISSUES`.

### 3. scripts/ai_loop_plan.ps1 changes

**A.** Add `-NoRevision` switch parameter.

**B.** Extend `Test-ReviewerOutputStrict` (currently ~line 104).
Change category regex from:
```
'^\s*-\s*\[(logic|complexity|scope|missing)\]\s+\S'
```
To:
```
'^\s*-\s*\[(logic|complexity|scope|missing|architecture|safety)\]\s+\S'
```
Backward-compatible: existing Codex reviewer output still passes unchanged.

**C.** Lighter reviewer prompt when `-NoRevision` is set.
Omit `repo_map.md` from the reviewer prompt.
Reviewer receives: reviewer_prompt_content + AGENTS.md + project_summary.md +
raw USER ASK + `# Draft task.md` header + draft content.
Reduces reviewer input from ~30KB to ~15KB.

**D.** Claude task reviewer prompt lookup.
When `$ReviewerCommand` contains `run_claude_reviewer`, look up:
  1. `.ai-loop/claude_task_reviewer_prompt.md`
  2. `templates/claude_task_reviewer_prompt.md`
Fall back to existing reviewer prompt with `Write-Warning` if neither found.

**E.** Variant A exit behavior when `-NoRevision` is set and reviewer returns `ISSUES`:
- Write to `.ai-loop/planner_review_trace.md`:
  `REVIEW_STATUS: BLOCKING_ISSUES_FOUND -- task.md was NOT written`
  followed by the issues list
- Print issues to console with `-ForegroundColor Red`
- Do NOT write `.ai-loop/task.md`
- `exit 2`

When `NO_BLOCKING_ISSUES`: write task.md as normal.
When `MALFORMED`: `Write-Warning`, write task.md anyway (same degraded behavior as today).

**F.** `-NoRevision` without `-WithReview`: emit
`Write-Warning "-NoRevision has no effect without -WithReview"` and continue.

**G.** `-NoRevision` with `-WithReview`: clamp `MaxReviewIterations` to 1 internally
(one review pass, no revision loop).

### 4. Reviewer prompt context assembly

When `-NoRevision` is set, `ai_loop_plan.ps1` assembles the reviewer prompt as:
```
<claude_task_reviewer_prompt content>

## AGENTS.md
<agents content>

## Project Summary
<project_summary content>

## Raw User ASK
<raw ask>

## Draft task.md
<draft content>
```
No `repo_map.md`. No `planner_prompt.md`.

## Tests

Add `tests/test_claude_reviewer.py`:

- **test_run_claude_reviewer_parse_check** — `Parser::ParseFile` on `scripts/run_claude_reviewer.ps1`; assert exit 0.
- **test_claude_task_reviewer_prompt_exists** — `assert Path("templates/claude_task_reviewer_prompt.md").exists()`
- **test_reviewer_strict_accepts_architecture_and_safety** — dot-source `ai_loop_plan.ps1`; call `Test-ReviewerOutputStrict` with `"ISSUES:\n- [architecture] bad scope\n- [safety] missing guard"`; assert result == `"ISSUES"`.
- **test_reviewer_strict_rejects_unknown_category** — same with `"ISSUES:\n- [unknown] something"`; assert result == `"MALFORMED"`.
- **test_claude_reviewer_default_model_is_haiku** — read `scripts/run_claude_reviewer.ps1`; assert `"haiku"` in content (case-insensitive).

Run: `python -m pytest -q tests/test_claude_reviewer.py`

## Verification

```powershell
powershell -NoProfile -Command "[void][System.Management.Automation.Language.Parser]::ParseFile('scripts\run_claude_reviewer.ps1', [ref]`$null, [ref]`$null)"
powershell -NoProfile -Command "[void][System.Management.Automation.Language.Parser]::ParseFile('scripts\ai_loop_plan.ps1', [ref]`$null, [ref]`$null)"
python -m pytest -q tests/test_claude_reviewer.py
python -m pytest -q
```

## Implementer summary requirements

1. Files created and modified, one line each.
2. Exact regex change in `Test-ReviewerOutputStrict` (before/after).
3. How lighter reviewer context (no repo_map) was implemented.
4. Default model for `run_claude_reviewer.ps1` confirmed.
5. Test result: pass/fail count.
6. One or two risks for variant B (auto-revision) as a forward note.

## Project summary update

Add to Current Architecture: `scripts/run_claude_reviewer.ps1` — Claude Haiku-based
architecture reviewer for opt-in cheap planning mode; invoked with
`-PlannerCommand Cursor -ReviewerCommand run_claude_reviewer.ps1 -WithReview -NoRevision`;
variant A only (no auto-revision); strict output extended with `[architecture|safety]`;
lighter reviewer context (no repo_map); task.md not written on blocking issues (exit 2).

## Output hygiene

- Do not commit.
- Do not write to `.ai-loop/_debug/`.
- Do not write to `docs/archive/`.
- Do not duplicate this task into `project_summary.md`.

## Important

- **SAFETY RULE**: if Claude reviewer outputs `ISSUES` and `-NoRevision` is set,
  task.md MUST NOT be written. Exit 2. Human is the revision loop in variant A.
- **BACKWARD COMPAT**: existing `-WithReview` without `-NoRevision` must behave
  exactly as before. The only changes to the existing code path:
  (1) extended category regex in `Test-ReviewerOutputStrict` (additive only),
  (2) `claude_task_reviewer_prompt.md` lookup (fallback to existing if not found).
- `run_claude_reviewer.ps1` wraps `claude --print` (same as `run_claude_planner.ps1`),
  NOT `codex`. Do not reuse `run_codex_reviewer.ps1` pattern for the claude call.
- `Test-ReviewerOutputStrict` is dot-sourced in tests; do not change its signature.
