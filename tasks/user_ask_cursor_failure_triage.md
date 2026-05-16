# User ASK

## Goal

Add a manual failure-to-task workflow: I provide a problem description either as a file with logs or as inline text, and a new script immediately creates a repair task through the existing planner flow using Cursor as the planner, Claude as the first task reviewer, and Codex as the final task reviewer.

The workflow should eliminate the intermediate "generate a triage brief, then paste it to Claude" step. Cursor may gather and summarize bounded failure context internally, but the durable output should be a `.ai-loop/task.md` repair task that has been reviewed first by Claude and then by Codex before human review and normal `ai_loop_task_first.ps1` execution. Codex should still review the eventual implementation at the end as usual.

## Affected files (your best guess - planner will verify)

- `scripts/plan_failure_fix.ps1` (new)
- `templates/failure_fix_planner_prompt.md` (new, optional if reusing existing planner prompt is enough)
- `.gitignore`
- `scripts/install_into_project.ps1`
- `tests/test_orchestrator_validation.py`
- `docs/workflow.md`
- `AGENTS.md`
- `.ai-loop/project_summary.md`

## Out-of-scope (explicit boundaries)

- `docs/archive/**`
- `.ai-loop/_debug/**` by default, unless explicitly requested by a flag
- `ai_loop.py`
- Auto-fixing code or running the implementer from the new script
- Auto-running `ai_loop_task_first.ps1`, `ai_loop_auto.ps1`, tests, Codex implementation review, or git commit/push from the new script
- Creating a standalone Claude diagnostic brief that the user must paste manually
- Changing the core implementation/review loop behavior unless the planner finds a small wrapper integration is strictly necessary

## Proposed approach (optional)

Add a new script for failed-run replanning, for example:

```powershell
.\scripts\plan_failure_fix.ps1 -ProblemFile path\to\failure_log.md
```

Also support:

```powershell
.\scripts\plan_failure_fix.ps1 -Message "I ran X and got Y"
.\scripts\plan_failure_fix.ps1 -ProblemFile path\to\failure_log.md -IncludeDebug
```

The script should:

1. Read an optional problem/log file from `-ProblemFile`.
2. Read optional inline problem text from `-Message`.
3. Auto-gather bounded recent orchestrator context:
   - recent root-level `.ai-loop/*.txt`;
   - recent root-level `.ai-loop/*.md`;
   - `git status --short`;
   - compact diff summary such as `git diff --stat` or equivalent;
   - `.ai-loop/task.md`;
   - `.ai-loop/implementer_summary.md`;
   - `.ai-loop/project_summary.md`;
   - `.ai-loop/repo_map.md`;
   - the provided terminal log or problem file.
4. Avoid `.ai-loop/_debug/**` by default. Add `-IncludeDebug` only for cases where raw agent output is explicitly needed, and keep it aggressively bounded.
5. Compose a clear USER ASK for the existing planner: "create a task to fix this failure", with the gathered context included as evidence.
6. Invoke `scripts/ai_loop_plan.ps1` rather than duplicating planner/reviewer logic, using Cursor as planner and Claude as the first task reviewer, equivalent to:

   ```powershell
   .\scripts\ai_loop_plan.ps1 `
     -Ask "<composed failure-fix ask>" `
     -PlannerCommand .\scripts\run_cursor_agent.ps1 `
     -WithReview `
     -MaxReviewIterations 2 `
     -ReviewerCommand .\scripts\run_claude_reviewer.ps1 `
     -NoRevision `
     -Force
   ```

7. After Cursor planner and Claude reviewer finish successfully, run the existing Codex task reviewer on the generated task before considering the task ready. Prefer reusing existing planner-review prompt/wrapper behavior where practical; if `ai_loop_plan.ps1` cannot chain two reviewers directly, the new wrapper may run a second bounded review pass with `scripts/run_codex_reviewer.ps1` against the generated `.ai-loop/task.md` and the composed failure-fix ask. Codex output must be persisted in a clear review trace artifact and blocking issues must prevent silently presenting the task as ready.
8. Write the normal planner outputs:
   - `.ai-loop/task.md`;
   - `.ai-loop/planner_review_trace.md`;
   - Codex final task-review trace/output;
   - queued `tasks/NNN_*.md` copy when the generated task contains `## Order`.

The new script should be a convenience wrapper around the existing planner architecture, not a second planner subsystem. It should not produce `.ai-loop/failure_triage.md` as the primary workflow output, because I do not want to manually pass an intermediate brief to Claude.

## Constraints / context the planner may not know

- The generated repair task must follow the normal `templates/task.md` / planner output contract so `ai_loop_task_first.ps1` can consume it.
- The new script must not edit project files other than normal planner outputs and bounded temporary artifacts, if needed.
- The new script must not run full pytest. It may read existing test outputs.
- The new script must not run the implementer, OpenCode, tests, git commit, or git push.
- Cursor is the planner in this workflow. Claude is the first task reviewer for blocking architectural/scope/safety issues.
- Codex must run after Cursor and Claude as the final reviewer of the generated repair task, before the user runs implementation.
- Codex should also remain part of the normal final implementation review path after the generated task is run; this script should not replace that later implementation review.
- Keep context bounded. Do not blindly paste huge logs; prefer recent files, byte caps, and explicit truncation banners.
- If the script creates deterministic temporary prompt/output artifacts under `.ai-loop/`, add them to `.gitignore`. Prefer `$env:TEMP` for transient prompt staging when practical.
- If adding installer support, copy the new script and any new template to target projects.
- Update `AGENTS.md` or `docs/workflow.md` so future agents know to use this failure-to-task wrapper after a failed run when the user wants a new repair task.
- The planner should choose the simplest implementation. Prefer one wrapper script around `ai_loop_plan.ps1` over a new orchestration subsystem.
