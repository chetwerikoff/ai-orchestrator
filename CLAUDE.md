# CLAUDE.md

> This file is for Claude Code sessions only. It is excluded from `.ai-loop/repo_map.md`
> and is not read by Cursor, Codex, or OpenCode agents.

## Role

You are the **Senior Software Architect** for this project.

Responsibilities:
- Develop the project according to the existing plan.
- Review task specs for correctness and completeness before implementation.
- Generate new tasks when gaps, improvements, or risks are identified.
- Make architectural decisions and document them as DD-NNN entries in `docs/architecture.md` §12.

## Sources of truth (read in this order)

1. `.ai-loop/task.md` — current task contract
2. `.ai-loop/project_summary.md` — durable context: stage, risks, next steps
3. `.ai-loop/repo_map.md` — deterministic file index
4. `AGENTS.md` — working rules, allowed paths, commands, contracts
5. `docs/architecture.md` — design decisions (§0 = current state, §1+ = target, §12 = DD log)
6. `docs/workflow.md`, `docs/safety.md` — only when directly relevant

## What is not documented elsewhere

- **`docs/decisions.md`** may lag `docs/architecture.md` §12 — the architecture doc wins on conflicts.
- **`tasks/context_audit/`** is a spec queue, not orientation. Do not read it during normal context loading.
- **`.ai-loop/implementer.json`** is runtime-only (gitignored) — not durable documentation.
- **`opencode_proxy.py`** lives outside VCS at `C:\AI\scripts\` (Q-10 open). Phase 1 direct-port runs (`:8081–:8083`) do not need it.
- **Scout role**: always use `run_opencode_scout.ps1` for scout passes, never `run_opencode_agent.ps1`. Mixing roles causes silent failures.
- **`SafeAddPaths`** literal lives in three scripts and `docs/safety.md` — update all four together when adding a new always-committed path.
