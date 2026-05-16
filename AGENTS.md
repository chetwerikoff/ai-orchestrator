# AGENTS.md

Working rules for AI agents operating in `ai-orchestrator`. Read this file once at the start of any task; it points to deeper docs only when needed.

## Project purpose (one line)
PowerShell-based AI development loop coordinating an implementer (often Cursor Agent; configurable via script parameters), Codex (technical reviewer), and safe git commit/push for target projects.

## Working scope
You may edit:

- `scripts/` — orchestration logic
- `tests/` — orchestrator validation tests
- `templates/` — files copied into target projects by `install_into_project.ps1`
- `docs/` — architecture, decisions, safety, workflow (**not** `docs/archive/`)
- `README.md`, `AGENTS.md`, `.gitignore`, `pytest.ini`, `requirements.txt`
- `.ai-loop/task.md`, `.ai-loop/implementer_summary.md`, `.ai-loop/project_summary.md`, `.ai-loop/repo_map.md`, `.ai-loop/failures.md`
- `tasks/` — queued task specs

Never edit:

- `docs/archive/` — superseded design documents, history-only
- `.ai-loop/_debug/` — raw agent stdout, debug-only (exists after O06)
- target project files through this repo
- `ai_loop.py` unless the task explicitly authorizes it (experimental; separate from the PowerShell loop)

## Read priority
When loading context, read in this order and stop when you have enough:

1. `.ai-loop/task.md` — current task contract (always)
2. `.ai-loop/project_summary.md` — durable orientation (always)
3. `.ai-loop/repo_map.md` — deterministic file index (always)
4. `AGENTS.md` — this file (always, once)
5. `.ai-loop/implementer_summary.md` — previous iteration only (if N > 1)
6. `.ai-loop/failures.md` — cross-session recurring failure fingerprints (recommended once you reach iteration 2).
7. `docs/architecture.md` — only if the task is architecture-related
8. `docs/decisions.md`, `docs/workflow.md`, `docs/safety.md` — only when directly relevant

**Rule:** From iteration **2 onward**, read `.ai-loop/failures.md` for recurring failure patterns before writing your first fix attempt in that iteration.

Do not read by default:

- `docs/archive/` — unless the task explicitly asks
- `tasks/context_audit/` — queued specs, not orientation
- `.ai-loop/_debug/` — human debugging only

## Commands
Test: `python -m pytest -q` · Test with traceback: `python -m pytest -q --tb=short` · Type check: `pyright` · LSP: `pyright-langserver --stdio`

PowerShell parse check:

```powershell
powershell -NoProfile -Command "[void][System.Management.Automation.Language.Parser]::ParseFile('scripts\ai_loop_auto.ps1', [ref]$null, [ref]$null)"
powershell -NoProfile -Command "[void][System.Management.Automation.Language.Parser]::ParseFile('scripts\ai_loop_task_first.ps1', [ref]$null, [ref]$null)"
powershell -NoProfile -Command "[void][System.Management.Automation.Language.Parser]::ParseFile('scripts\continue_ai_loop.ps1', [ref]$null, [ref]$null)"
powershell -NoProfile -Command "[void][System.Management.Automation.Language.Parser]::ParseFile('scripts\build_repo_map.ps1', [ref]$null, [ref]$null)"
powershell -NoProfile -Command "[void][System.Management.Automation.Language.Parser]::ParseFile('scripts\ai_loop_plan.ps1', [ref]$null, [ref]$null)"
```

## Safe paths (committed by orchestrator)
The default `SafeAddPaths` literal is `src/,tests/,README.md,AGENTS.md,scripts/,docs/,tasks/,templates/,ai_loop.py,pytest.ini,.gitignore,requirements.txt,pyproject.toml,setup.cfg,pyrightconfig.json,.ai-loop/task.md,.ai-loop/implementer_summary.md,.ai-loop/project_summary.md,.ai-loop/repo_map.md,.ai-loop/failures.md,.ai-loop/archive/rolls/,.ai-loop/_debug/session_draft.md`. It lives in `scripts/ai_loop_auto.ps1`, `scripts/ai_loop_task_first.ps1`, `scripts/continue_ai_loop.ps1`, and `docs/safety.md`; keep them in sync when adding an always-commit path.

## Templates contract
When you add or remove a file in `templates/`, also check `scripts/install_into_project.ps1` so auto-copied target files stay correct.

## Decision document policy
- `docs/architecture.md` is the single source of truth for target design.
- `docs/decisions.md` tracks numbered `DD-XXX` decisions; when superseded, mark inline and keep the entry; add replacements with higher numbers — never delete.

## Implementer summary contract
After each iteration, update `.ai-loop/implementer_summary.md` with:

- changed files (brief)
- test result (count, not full output)
- implemented work (3–5 lines)
- skipped items with reason
- remaining risks (1–3 bullets)

Do **not** include prior-roll history, full diffs, or multi-page narratives. Target length: under 50 lines.

## Git hygiene
- Do not commit `.ai-loop/_debug/` content, `.tmp/`, `input/`, or `output/`. Use `git mv` for renames.
- Do not commit secrets — see `docs/safety.md` for the recommended scan.
- **`.ai-loop/implementer.json`** is runtime-only (gitignored): local wrapper paths and model IDs for resume — not durable project documentation.
- **C12 (task queue protection):** **Queued task specs** under `tasks/` are protected from deletion or modification unless the active `.ai-loop/task.md` explicitly includes `tasks/` or that specific file under `## Files in scope`. Untracked `tasks/*.md` files are intentional queue specs from the planner, not scratch files; do not recommend deleting them (or "cleaning them up") without explicit task scope. Reactive guards in `ai_loop_auto.ps1` enforce this: **`Test-FixPromptArtifactsTasksConflict`** / **`Stop-UnsafeQueueCleanup`** halt before the implementer when the fix prompt (JSON plus markdown fallback) references unscoped `tasks/` paths—including on `-Resume` from `next_implementer_prompt.md`. **`Test-WorkingTreeTasksConflictWithScope`** blocks the PASS/commit gate while unscoped `tasks/` working-tree paths remain.

## Retrieval policy

- Prefer `rg` (ripgrep) and `Read` for code navigation. Use `.ai-loop/repo_map.md` for layout.
- Do not propose a vector index, embedding store, or AST symbol index for code in this repo. They have been evaluated and declined (see `tasks/claude_ai_orcestrator_context_plan_report.md` §6, §13).
- For narrative history (`docs/archive/`, future `.ai-loop/archive/rolls/`), RAG may earn its place later—not now.

## Task size policy

- Prefer tasks that touch ≤80 lines. Split larger work into ordered subtasks (see `tasks/context_audit/` for examples).
- If a task naturally exceeds that budget, flag it in the task spec rather than silently growing the diff.

## Simplicity policy

Default to the simplest implementation that solves the goal. Engineering over-complexity is a recurring failure mode in agent-generated work — pretty abstractions, "future-proofing", sophistication for its own sake.

When two solutions are equally correct, prefer:

- modifying an existing file over creating a new one;
- extending a wrapper/helper over inventing a new subsystem;
- one parameter with a clear default over multiple modes;
- inline logic over an abstraction with exactly one caller;
- a clear error message over fallback logic that hides the failure;
- fewer LLM calls over more (bounded loops, opt-in validators).

"It might be useful later" is not a justification. Splitting work into ordered subtasks beats growing one task past the ~80-line policy. Architecture proposals that add new subsystems must justify the cost against doing nothing.

The planner stage (`scripts/ai_loop_plan.ps1`, `templates/planner_prompt.md`, `templates/reviewer_prompt.md`) explicitly enforces this principle for generated `.ai-loop/task.md`; the same principle applies to all agent work in this repo. Optional `-WithDraft` on `scripts/ai_loop_plan.ps1` runs a **read-only** Cursor advisory pass first (stdin to `-DraftCommand`, default `run_cursor_agent.ps1` beside the repo `scripts/`); output is gitignored `.ai-loop/task_draft_brief.md` when valid and is appended **after `## USER ASK`** in the Claude planner prompt as advisory-only context. Failures or short output emit warnings and Claude planning continues without a brief.

If you customize the Cursor draft wording for a target project, edit `.ai-loop/draft_brief_prompt.md`; the orchestrator prefers that path over `templates/draft_brief_prompt.md` when present.

## When in doubt
Ask the user. Do not invent commands, paths, or behaviors not documented here or in the linked docs.
