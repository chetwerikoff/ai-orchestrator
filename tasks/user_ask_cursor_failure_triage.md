# User ASK

## Goal

Add a Cursor-powered failure triage workflow that runs before asking Claude for help when a task execution fails. The workflow should gather recent orchestrator artifacts automatically, accept an optional user-provided problem description file, and produce a concise diagnostic brief for Claude.

The goal is to reduce Claude token spend on log/file discovery while preserving Claude as the final decision-maker for root cause, fix strategy, or replanning.

## Affected files (your best guess - planner will verify)

- `scripts/triage_failure.ps1` (new)
- `templates/failure_triage_prompt.md` (new)
- `scripts/run_cursor_agent.ps1`
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
- Changing implementation/review loop behavior
- Auto-fixing code
- Running full test suites
- Committing or pushing

## Proposed approach (optional)

Add a new read-only script:

```powershell
.\scripts\triage_failure.ps1 -ProblemFile path\to\problem.md
```

Also support:

```powershell
.\scripts\triage_failure.ps1 -Message "I ran X and got Y"
.\scripts\triage_failure.ps1 -ProblemFile path\to\problem.md -IncludeDebug
```

The script should:

1. Read an optional problem description from `-ProblemFile`.
2. Read an optional inline description from `-Message`.
3. Auto-gather recent failure context:
   - recent `.ai-loop/*.txt`;
   - recent `.ai-loop/*.md`;
   - `git status --short`;
   - diff stat / short diff summary;
   - `.ai-loop/task.md`;
   - `.ai-loop/implementer_summary.md`;
   - `.ai-loop/project_summary.md`;
   - `.ai-loop/repo_map.md`;
   - terminal log if the user provided one as `-ProblemFile`.
4. Avoid `.ai-loop/_debug/**` by default. Add `-IncludeDebug` only for cases where raw agent output is explicitly needed.
5. Build a bounded prompt from `templates/failure_triage_prompt.md`.
6. Run Cursor via `scripts/run_cursor_agent.ps1` in read-only diagnostic mode.
7. Write the result to:

   ```text
   .ai-loop/failure_triage.md
   ```

The Cursor output should be concise and stable:

```md
# Failure Triage Brief

## Symptom
...

## Command that failed
...

## Most likely cause
...

## Evidence
- `path`: fact

## Relevant files
- `path`: why relevant

## What was checked
- ...

## What was not checked
- ...

## Suggested next action
- ...

## Confidence
Low | Medium | High
```

The triage pass must be advisory only. Claude receives this brief plus the user's raw problem description and decides the actual fix/replan.

## Constraints / context the planner may not know

- The script must not edit project files other than writing `.ai-loop/failure_triage.md` and bounded temporary prompt/output artifacts if needed.
- The script must not run full pytest. It may read existing test outputs.
- The script must not run implementer/reviewer/planner agents except Cursor for the diagnostic pass.
- The prompt must explicitly tell Cursor: read-only, no edits, no fixes, no broad refactors, concise diagnostic brief only.
- Keep context bounded. Do not blindly paste huge logs; prefer latest files and tail/head limits.
- Add `.ai-loop/failure_triage.md` and any temporary triage artifacts to `.gitignore`.
- If adding installer support, copy the new script/template to target projects.
- Update `AGENTS.md` or `docs/workflow.md` so future agents know to use failure triage before asking Claude to diagnose a failed run.
- The planner should choose the simplest implementation. If a single script plus one template is enough, do not introduce a larger subsystem.
