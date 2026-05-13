# AGENTS.md

Working rules for AI agents operating in `ai-git-orchestrator`. Read this file once at the start of any task; it points to deeper docs only when needed.

## Project purpose (one line)
PowerShell-based AI development loop coordinating an implementer (often Cursor Agent; configurable via script parameters), Codex (technical reviewer), and safe git commit/push for target projects.

## Working scope
You may edit:

- `scripts/` — orchestration logic
- `tests/` — orchestrator validation tests
- `templates/` — files copied into target projects by `install_into_project.ps1`
- `docs/` — architecture, decisions, safety, workflow (**not** `docs/archive/`)
- `README.md`, `AGENTS.md`, `.gitignore`, `pytest.ini`, `requirements.txt`
- `.ai-loop/task.md`, `.ai-loop/implementer_summary.md`, `.ai-loop/project_summary.md`
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
3. `AGENTS.md` — this file (always, once)
4. `.ai-loop/implementer_summary.md` — previous iteration only (if N > 1)
5. `docs/architecture.md` — only if the task is architecture-related
6. `docs/decisions.md`, `docs/workflow.md`, `docs/safety.md` — only when directly relevant

Do not read by default:

- `docs/archive/` — unless the task explicitly asks
- `tasks/context_audit/` — queued specs, not orientation
- `.ai-loop/_debug/` — human debugging only

## Commands
Test: `python -m pytest -q` · Test with traceback: `python -m pytest -q --tb=short`

PowerShell parse check:

```powershell
powershell -NoProfile -Command "[void][System.Management.Automation.Language.Parser]::ParseFile('scripts\ai_loop_auto.ps1', [ref]$null, [ref]$null)"
powershell -NoProfile -Command "[void][System.Management.Automation.Language.Parser]::ParseFile('scripts\ai_loop_task_first.ps1', [ref]$null, [ref]$null)"
powershell -NoProfile -Command "[void][System.Management.Automation.Language.Parser]::ParseFile('scripts\continue_ai_loop.ps1', [ref]$null, [ref]$null)"
```

## Safe paths (committed by orchestrator)
The default `SafeAddPaths` literal is `src/,tests/,README.md,AGENTS.md,scripts/,docs/,templates/,ai_loop.py,pytest.ini,.gitignore,requirements.txt,pyproject.toml,setup.cfg,.ai-loop/task.md,.ai-loop/implementer_summary.md,.ai-loop/project_summary.md`. It lives in `scripts/ai_loop_auto.ps1`, `scripts/ai_loop_task_first.ps1`, `scripts/continue_ai_loop.ps1`, and `docs/safety.md`; keep them in sync when adding an always-commit path.

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

## When in doubt
Ask the user. Do not invent commands, paths, or behaviors not documented here or in the linked docs.
