# Task: Failure-to-task planner wrapper

## Project context
Required reading for the implementer: `AGENTS.md`, `.ai-loop/task.md`, `.ai-loop/project_summary.md`, `.ai-loop/repo_map.md`, and `.ai-loop/implementer_summary.md` when iterating.

## Goal
Provide a thin manual shortcut from a failure description (inline and/or a log file) plus bounded repository/orchestrator context into a **reviewed** `.ai-loop/task.md` repair spec, by delegating to the existing `scripts/ai_loop_plan.ps1` pipeline with **Cursor as planner** and **Claude as the single-pass architecture reviewer** (`-WithReview -NoRevision`), so the human can open the drafted task and run `scripts/ai_loop_task_first.ps1` as today without an intermediate hand-pasted triage brief.

## Scope
**Allowed:**
- Add `scripts/plan_failure_fix.ps1` that assembles a bounded evidence bundle, writes a **temporary** ask file (not `.ai-loop/user_ask.md`), and dot-sources or `&`-invokes `scripts/ai_loop_plan.ps1` with the same effective flags as the reference flow below.
- Install-time copy of the new script via `scripts/install_into_project.ps1`.
- Minimal documentation in `AGENTS.md` and `docs/workflow.md` describing when and how to run the wrapper.
- Durable index update in `.ai-loop/project_summary.md` for the new workflow.
- Tests: extend `tests/test_orchestrator_validation.py` so the new script participates in the existing PowerShell AST parse coverage (same pattern as other orchestrator scripts).
- Optional non-fatal `Push-Location` to the repo root derived from `$PSScriptRoot` so the wrapper works when launched by full path.

**Not allowed:**
- Running the implementer, `ai_loop_task_first.ps1`, `ai_loop_auto.ps1`, full pytest, Codex implementation review, OpenCode, git commit, or git push from the new script.
- Introducing a second planner implementation, a durable `.ai-loop/failure_triage.md` as the primary handoff artifact, or changing `ai_loop_plan.ps1` review/planner semantics beyond what is needed to invoke it.
- Reading or writing under `.ai-loop/_debug/**` unless `-IncludeDebug` is set; even then, keep inclusion strictly bounded.
- Editing `docs/archive/**`, `tasks/**` queue specs, or `ai_loop.py`.

## Files in scope
- `scripts/plan_failure_fix.ps1` (new)
- `scripts/install_into_project.ps1`
- `tests/test_orchestrator_validation.py`
- `docs/workflow.md`
- `AGENTS.md`
- `.ai-loop/project_summary.md`

## Files out of scope
- `docs/archive/**`
- `.ai-loop/_debug/**` (except what the user explicitly opts into via `-IncludeDebug`, and only as read-only bounded snippets)
- `ai_loop.py`
- `templates/planner_prompt.md` (unless a one-line cross-link in docs is needed; prefer no change)
- `scripts/ai_loop_plan.ps1` (invoke as-is; do not fork behavior)
- Queued specs under `tasks/**` not listed here

## Required behavior
1. Expose parameters at minimum: `[string]$Message = ''`, `[string]$ProblemFile = ''`, and `[switch]$IncludeDebug`. Require that at least one of `$Message` or `$ProblemFile` resolves to non-blank content after trim (after reading the file when given); otherwise exit with a clear error and non-zero code.
2. Resolve the repository root as the parent of `scripts/` (from `$PSScriptRoot`), `Push-Location` there for the duration of the run, and resolve paths (including `$ProblemFile`) against that root when relative.
3. Build a **single composed USER ASK** markdown body that: states the goal (produce a normal `templates/task.md`-shaped repair task); includes the user’s inline message and/or the problem file path and excerpt; includes **bounded** evidence sections for `git status --short`, `git diff --stat` (or equivalent compact diff summary), and the standard durable context files when present: `.ai-loop/task.md`, `.ai-loop/implementer_summary.md`, `.ai-loop/project_summary.md`, `.ai-loop/repo_map.md`.
4. Add an **optional** “Recent `.ai-loop` root artifacts” section: include a small, **recency-bounded** subset of non-debug `.ai-loop/*.md` and `.ai-loop/*.txt` (exclude anything under `.ai-loop/_debug/` unless `-IncludeDebug`), sorted by last write time, with **per-file and total byte caps** and explicit `TRUNCATED` banners when cutting content. Do not scan subfolders for this step (root of `.ai-loop` only).
5. When `-IncludeDebug` is set, append a **small** debug evidence section (e.g., only the single newest matching implementer-related text artifact, or a clearly documented cap such as last N kilobytes), never bulk-ingesting the whole tree.
6. Write the composed ask to a unique file under `$env:TEMP` (UTF-8), then invoke `scripts/ai_loop_plan.ps1` with **`-AskFile` pointing at that temp file** (avoid huge inline `-Ask` command lines on Windows), **`-PlannerCommand` resolved to `Join-Path $PSScriptRoot 'run_cursor_agent.ps1'`**, **`-WithReview`**, **`-ReviewerCommand` resolved to `Join-Path $PSScriptRoot 'run_claude_reviewer.ps1'`**, **`-NoRevision`**, **`-Force`**, and **without** `-WithDraft`. Forward the child exit code. Do not leave the temp ask file in `.ai-loop/` by default.
7. Do not overwrite `.ai-loop/user_ask.md` as part of this workflow.
8. After adding the script, update `scripts/install_into_project.ps1` to copy `plan_failure_fix.ps1` alongside other orchestration scripts.
9. Regenerate `.ai-loop/repo_map.md` after the change via `scripts/build_repo_map.ps1` so the index lists the new script (non-fatal if run fails in a sandbox, but required in a normal dev environment).

## Tests
- Update `tests/test_orchestrator_validation.py` so `plan_failure_fix.ps1` is included in the same PowerShell `Parser::ParseFile` sweep used for other orchestrator or planner-related scripts (extend the appropriate existing tuple/list; do not hand-roll a second harness).
- Run `python -m pytest -q`.

## Verification
- `python -m pytest -q`
- From the repo root (or document the wrapper’s root resolution):  
  `powershell -NoProfile -Command "[void][System.Management.Automation.Language.Parser]::ParseFile('scripts\plan_failure_fix.ps1', [ref]$null, [ref]$null)"`
- Spot-check: `.\scripts\plan_failure_fix.ps1 -Message "smoke: synthetic failure"` with real planner/reviewer CLIs available is optional for humans; automated tests must not require those CLIs.

## Implementer summary requirements
- List changed files briefly.
- Note pytest result as count only.
- Summarize the wrapper’s parameters, evidence bundle, and `ai_loop_plan.ps1` invocation flags in 3–5 lines.
- Call out anything skipped (e.g., live CLI smoke) with reason.
- Note 1–3 residual risks (context caps, Windows path/quoting, optional CLIs).

## Project summary update
Add a short bullet under the architecture/workflow area describing `scripts/plan_failure_fix.ps1` as the manual failure-to-task entry point (Cursor planner + Claude single-pass reviewer via `ai_loop_plan.ps1`), and that it does not run the implementer or auto loop.

## Output hygiene
- Do not duplicate the full task body into `.ai-loop/implementer_summary.md`.
- Do not write diagnostic dumps into `.ai-loop/_debug/` from the new script.
- Do not create a git commit or push.
- Do not write to `docs/archive/**`.

## Important
- Assumption: the user runs from a machine with Cursor Agent CLI and Claude reviewer CLI configured the same way as an interactive `ai_loop_plan.ps1` run; the wrapper only orchestrates file assembly and invocation.
- Architect note: **no new `templates/failure_fix_planner_prompt.md`**—the existing `templates/planner_prompt.md` / installed `.ai-loop/planner_prompt.md` remains the planner contract; the wrapper only supplies a richer `## USER ASK` body.
- Architect note: use **`-AskFile` under `%TEMP%`** instead of embedding megabyte-scale text in a `-Ask` argument to avoid Windows command-line length failures.
- Architect note: **omit `.gitignore` changes** unless an implementer introduces durable artifacts under `.ai-loop/`; temp asks must stay in `$env:TEMP`.
- Architect note: reference `ai_loop_plan.ps1` invocation matches the user’s intent: **`-PlannerCommand`** → `scripts/run_cursor_agent.ps1`, **`-ReviewerCommand`** → `scripts/run_claude_reviewer.ps1`, **`-WithReview -NoRevision -Force`**, **no `-WithDraft`**.
- Maintain the **≈80-line change budget** primarily for `plan_failure_fix.ps1`; installer, docs, summary, and a one-line parse-list edit are exempt overhead but avoid extra features beyond this spec—if temptation grows, stop and propose a follow-up task instead.

## Order
1
