# Reviewer context (bounded)

Codex-facing summary of implementer rules. Prefer this file over full `AGENTS.md` unless you still lack clarity after reading it.

## Editable paths

**May edit:** `scripts/`, `tests/`, `templates/`, `docs/` (except `docs/archive/`), `README.md`, `AGENTS.md`, `.gitignore`, `pytest.ini`, `requirements.txt`, `.ai-loop/task.md`, `.ai-loop/implementer_summary.md`, `.ai-loop/project_summary.md`, `.ai-loop/repo_map.md`, `.ai-loop/failures.md`, and `ai_loop.py` only when the active task explicitly allows it.

**Do not edit:** `docs/archive/`, `.ai-loop/_debug/`, files in downstream target projects via this repo, or anything outside the working-scope list unless the task puts it in scope.

## Queued task spec protection

Never recommend deleting or rewriting `tasks/*.md` unless `.ai-loop/task.md` lists `tasks/` or that exact path under `## Files in scope`. Those files are queued planner specs, not disposable scratch.

## Safe staging expectations

Commits use the default `SafeAddPaths` allow-list from `AGENTS.md`: durable project paths (`src/`, `tests/`, `scripts/`, `docs/`, `tasks/`, `templates/`, etc.), `.ai-loop/task.md`, `.ai-loop/implementer_summary.md`, `.ai-loop/project_summary.md`, `.ai-loop/repo_map.md`, `.ai-loop/failures.md`, `.ai-loop/archive/rolls/`, optional promoted `.ai-loop/_debug/session_draft.md`, plus standard root meta (`README.md`, `AGENTS.md`, tool configs named there).

## project_summary.md update rule

Touch `.ai-loop/project_summary.md` only when durable architecture or workflow context changes—not for iteration narratives (those stay in `implementer_summary.md`).

## Test execution policy

Pytest already ran in the orchestrator. Do not demand a full-suite rerun. A targeted single-test run is allowed only when a concrete finding requires it; put one line in `FINAL_NOTE` stating exactly what ran and why (when requesting or assuming verification).
