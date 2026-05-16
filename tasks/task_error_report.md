# Task: Failure-to-task planner wrapper (Cursor ÔåÆ Claude ÔåÆ Codex review)

## Project context

- `AGENTS.md`
- `.ai-loop/project_summary.md` (planner/task-first behavior, Claude reviewer variant A semantics, reviewer trace behavior)
- `.ai-loop/repo_map.md` (`scripts/` entry points, `templates/`)
- Existing planner contract in `templates/planner_prompt.md` / authored `.ai-loop/task.md` conventions (implementer neutrality; **cursor draft brief advisory only** applies to planning prompts, not to this orchestration script)
- Implementer iterations 2+: `.ai-loop/implementer_summary.md` (routine)

## Goal

Give operators a manual, reproducible shortcut that turns ÔÇ£what failed?ÔÇØ into a repaired `.ai-loop/task.md` without a separate curated triage handoff: bundle bounded failure/context evidence, invoke the existing **`scripts/ai_loop_plan.ps1` pipeline with Cursor drafting the task**, run **blocking Claude task review first** (`scripts/run_claude_reviewer.ps1` / variant A semantics), then run a **second, final Codex reviewer pass** (`scripts/run_codex_reviewer.ps1`) against the drafted task before handing off to the human and `scripts/ai_loop_task_first.ps1`. The script must not run the implementation loop tests, Codex implementation review gate, git commit/push, or OpenCode scout/implementer.

## Scope

Allowed:

- Add a thin PowerShell wrapper `scripts/plan_failure_fix.ps1` that gathers **bounded**, **explicitly categorized** snippets (truncate with clear banners).
- Compose a deterministic **USER ASK** string/file used as planner input describing ÔÇ£produce a minimal repair task for this failureÔÇØ while attaching evidence.
- Call `scripts/ai_loop_plan.ps1` as the sole planner subsystem (no duplicated reviewer/planner internals).
- When the Claude-first review leg succeeds and `.ai-loop/task.md` reflects the drafted task, invoke **Codex** using the repositoryÔÇÖs reviewer prompt/template pattern already used by `ai_loop_plan.ps1` advisory review (reuse `templates/reviewer_prompt.md` as the canonical reviewer wording source for the Codex stdin prompt body), and persist Codex reviewer stdout/errors to **one clear trace file** adjacent to planner tracing.
- Respect blocking semantics deterministically (`ISSUES:` with allowed tags ÔçÆ non-zero wrapper exit unless overridable; see Required behavior).
- Update installer + `.gitignore` if new durable/transient filenames require it under `.ai-loop/`.
- Update `docs/workflow.md` plus a concise pointer line in `AGENTS.md`; refresh `.ai-loop/project_summary.md` ÔÇ£Current Architecture / Important Design Decisions / Next Likely StepsÔÇØ only enough to advertise the pathway.
- Add a small subprocess smoke test validating argument validation + deterministic ÔÇ£composed ask writtenÔÇØ/`ai_loop_plan` delegation (mock PlannerCommand), plus (if feasible without env CLIs) a dry-run Codex reviewer stub expectation.

Not allowed:

- Edits under `docs/archive/**`, `.ai-loop/_debug/**` content as durable outputs unless `-IncludeDebug` is set and bounded.
- Any change to **`ai_loop.py`**.
- Editing `templates/` reviewer/planner internals beyond referencing existing templates from the new script/tests (no wholesale rewrites).
- Running `pytest` full-suite from the wrapper, running `scripts/ai_loop_task_first.ps1`, `scripts/ai_loop_auto.ps1`, wrappers that invoke implementers/OpenCode scouts, git commit/push, or emitting `failure_triage.md` as primary deliverable output (no manual mid artifact).

## Files in scope

- `scripts/plan_failure_fix.ps1` (new)
- `scripts/ai_loop_plan.ps1` (only tiny, unavoidable integration hooks if `--%` shim cannot pass complex stdin; otherwise **avoid** edits)
- `scripts/install_into_project.ps1`
- `.gitignore` (only if new `.ai-loop/*.md|*.txt` scratch/trace patterns are needed beyond existing ignores)
- `tests/test_orchestrator_validation.py`
- `docs/workflow.md`
- `AGENTS.md`
- `.ai-loop/project_summary.md`
- `templates/reviewer_prompt.md` (reference-only from tests or script text assembly; edit only if a **single-line** breadcrumb/header is unavoidableÔÇöprefer zero edits)

Optional (only if Powershell quoting forces externalization):

- `.ai-loop/failure_fix_bundle_header.md` (new, tracked **only** if unavoidable; strongly prefer composing header text inside `plan_failure_fix.ps1`)

Mark any **new ephemeral** staged prompts under `%TEMP%` only (preferred); do not assume new tracked prompts.

## Files out of scope

- `docs/archive/**`
- `.ai-loop/_debug/**`
- `ai_loop.py`
- `tasks/context_audit/**`
- Bulk edits to orchestrator internals (`scripts/ai_loop_auto.ps1`, `scripts/run_cursor_agent.ps1`, `scripts/run_opencode_agent.ps1`, etc.) unless a **minimal** safe extension is unavoidable (should be avoided by design)

## Required behavior

1. **CLI surface**: support `-ProblemFile` (optional readable path), `-Message` (optional inline text), mutually satisfiable combined input; require **at least one** of `{ProblemFile, Message}`; fail fast otherwise with clear error text.
2. **`-IncludeDebug`**: default OFF; ON includes **tiny** excerpts from `.ai-loop/_debug/*` newest-by-mtime (cap file count & bytes **per file**) with truncation banners; if absent/unreadable, continue with warningÔÇönot fatal unless user passes a strict optional switch (do **not** add extra switches unless neededÔÇöstay with two modes only).
3. **Auto context bundle** (bounded, newest-first `.ai-loop` root `*.txt` / `*.md` **excluding** `_debug/` when `-IncludeDebug` off): cap count + per-file bytes; omit unreadable paths with warnings; attach `git status --short`; attach `git diff --stat`; always include verbatim (bounded) excerpts of `.ai-loop/task.md`, `.ai-loop/implementer_summary.md`, `.ai-loop/project_summary.md`, `.ai-loop/repo_map.md` when present; include user problem file/Message body (bounded).
4. **Planner invocation**: synthesize `-Ask`/`-AskFile` (prefer `%TEMP%\ai_orchestrator_failure_fix_*.ask.txt`) whose first lines state role (ÔÇ£failure-to-taskÔÇØ), then sections `EVIDENCE`, `USER PROBLEM`; call `scripts/ai_loop_plan.ps1` **from the orchestrator repo root resolution rules consistent with sibling scripts**, with `-PlannerCommand` defaulting `scripts/run_cursor_agent.ps1`, `-ReviewerCommand scripts/run_claude_reviewer.ps1`, `-WithReview`, `-NoRevision`, **`MaxReviewIterations` set to match variant A semantics (single Claude review pass)**; include `-AskFile` pointing at temp ask when quoting risk exists; propagate non-zero exits from planner leg without masking.
5. **Codex final reviewer pass**: feed `templates/reviewer_prompt.md` content plus the composed failure ask excerpts + trimmed `.ai-loop/task.md` into `scripts/run_codex_reviewer.ps1` stdin pipeline exactly like other wrappers (no bespoke Python reviewer); normalize output using the repositoryÔÇÖs reviewer strictness expectations already codified alongside planner review (reuse the same malformed/blocked branching concept as Codex reviewer in `ai_loop_plan.ps1`ÔÇödo **not** reimplement full loop).
6. **Trace outputs**: reuse `.ai-loop/planner_review_trace.md` from `ai_loop_plan.ps1`; additionally persist Codex reviewer stdout verbatim to **` .ai-loop/planner_final_codex_review.md `** **only during this wrapper** when present (gitignored if not yet covered); prepend `TIMESTAMP UTC` banner line.
7. **Blocking readiness**: wrapper exit **`2`** if Claude reviewer semantics block task write **`or`** Codex final reviewer emits blocking `ISSUES:` per strict parser rules used elsewhere; **`0`** when draft task exists AND Codex path clean or explicitly `NO_BLOCKING_ISSUES` (parity with existing planner degraded-success policy only where unavoidableÔÇöprefer fail-closed for this operator entrypoint).
8. **Installer**: extend `scripts/install_into_project.ps1` to copy `scripts/plan_failure_fix.ps1` beside other orchestrator utilities; no new tracked template requirement.
9. **Docs**: explain sequence `plan_failure_fix ÔåÆ human review task.md ÔåÆ ai_loop_task_first.ps1`; note Claude blocks dangerous scope; Codex final advisor; `_debug` opt-in hazards.

## Tests

Add/extend deterministic tests under `tests/test_orchestrator_validation.py`:

- Validates parameter validation errors for missing problem inputs without invoking Cursor/Claude/Codex.
- Fakes PlannerCommand pointing to a nop script that echoes success and asserts synthesized ask artifact contains required section headers/evidence placeholders (golden substring checks).

Run: `python -m pytest -q`

## Verification

- `python -m pytest -q`
- Parser smoke (adapt list as needed):

```powershell
powershell -NoProfile -Command "[void][System.Management.Automation.Language.Parser]::ParseFile('scripts\plan_failure_fix.ps1', [ref]$null, [ref]$null)"
```

- Manual sanity (when CLIs configured): `./scripts/plan_failure_fix.ps1 -Message 'repro'` then inspect `.ai-loop/task.md` + traces.

## Implementer summary requirements

- Brief changed files bullet list.
- pytest result summary (counts only).
- 3ÔÇô5 line implemented behavior summary referencing wrapper sequence.
- Explicitly note any skipped fidelity (truncation knobs, mocked tests).
- 1ÔÇô3 residual risks.

## Project summary update

Record: existence of `scripts/plan_failure_fix.ps1`; operator order (**Cursor planner ÔåÆ Claude Haiku reviewer blocking ÔåÆ Codex final task reviewer blocking ÔåÆ human review ÔåÆ task-first ÔåÆ existing auto-loop review**); note `_debug` only via `-IncludeDebug` capped; `_debug/` remains forbidden default durable writes.

Use ÔÇ£no update neededÔÇØ **only** if identical prose already landedÔÇöprefer a short addition under Current Architecture plus Known Risks caveat about trusting bounded logs.

## Output hygiene

- Do not duplicate this whole task verbatim into `.ai-loop/implementer_summary.md`.
- Do not stash raw Cursor/Codex/Claude logs under `_debug/` from this wrapper except user `-IncludeDebug` excerpt policy.
- Do not create git commits unless a future task expressly asks.
- Do not relocate narrative into `docs/archive/**`.

## Important

- Bounded context is **mandatory**; never dump unchecked multiÔÇæMB logs; prefer head/tail with `...[truncated ### bytes]`.
- Compose planner ask in **English operator instructions** referencing evidence sections; planner already knows task template obligationsÔÇöavoid restating template except where it prevents hallucinated scopes.
- `Architect note`: user illustrated `-MaxReviewIterations 2`; this task **locks to a single Claude review tick** aligning with documented **variant A / `-NoRevision`** semantics unless code audit proves harmless extra idle iterationsÔÇöavoids phantom revision expectations.
- `Architect note`: user proposed optional `templates/failure_fix_planner_prompt.md`; **omitted**ÔÇöinline PowerShell concatenation keeps within line budget / avoids proliferating prompts; reuse canonical `templates/reviewer_prompt.md` for Codex second pass verbatim merge with failure bundle header.
- `Architect note`: user suggested chaining reviewers entirely inside extended `ai_loop_plan.ps1`; **preferred** sequential calls from `plan_failure_fix.ps1` to avoid touching core planner state machine (`ai_loop_plan.ps1` edits **discouraged**).
- `Architect note`: trace filename codified as `.ai-loop/planner_final_codex_review.md` overrides vague ÔÇ£Codex traceÔÇØ wording for deterministic operator support; add `.gitignore` entry if absent.
- `Architect note`: if combined diff threatens >80 substantive PowerShell LOC, shrink via helper sourcing pattern **or** defer Order 2 self-contained tightenings (explicitly enumerated if split).

## Order
