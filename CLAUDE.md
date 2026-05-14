# CLAUDE.md

## 1. Project overview

`ai-orchestrator` is a local PowerShell-based AI development loop that installs into any git project and coordinates:

- an **implementer** (Cursor Agent `agent` CLI by default; swappable with `-CursorCommand`, e.g. `scripts/run_opencode_agent.ps1` for OpenCode + local Qwen)
- a **technical reviewer** (Codex CLI — different model family, independent signal)
- optional **pytest** gate + post-fix command
- safe git staging and conditional commit/push

**Main purpose:** Automate the implement → test → review → fix cycle under a strict file-based contract so no hidden chat state is required. The loop is installed into target projects (e.g. `H2N_parser/h2n-range-extractor`) via `scripts/install_into_project.ps1`.

**Current development direction (as of 2026-05-14):**
- Phase 0 (complete 2026-05-11): validated OpenCode + `llama-server` on Windows with a trivial task; Qwen3-Coder-30B-A3B-Instruct Q3_K_M passes (challenger A); Qwen2.5-Coder-14B fails.
- Phase 1 A/B (IN PROGRESS since 2026-05-13): comparing Cursor vs three Qwen models (:8081 30B MoE / :8082 27B dense / :8083 35B MoE) on real H2N tasks. Cursor remains production (DD-021) until Qwen proves stable across ≥5 real tasks.
- C06 (complete 2026-05-14): `run_opencode_scout.ps1` SCOUT role framing + short-output guard in `run_scout_pass.ps1` + installer copy.

**Important modules and directories:**

| Path | Role |
|------|------|
| `scripts/ai_loop_task_first.ps1` | Task-first entrypoint: refresh repo map → optional scout → implementer → hand-off to auto loop |
| `scripts/ai_loop_auto.ps1` | Main loop: test + diff → Codex review → fix iterations → final gate → safe commit/push |
| `scripts/continue_ai_loop.ps1` | Resume wrapper; reloads persisted implementer from `.ai-loop/implementer.json` |
| `scripts/run_cursor_agent.ps1` | Cursor Agent wrapper (production implementer) |
| `scripts/run_opencode_agent.ps1` | OpenCode wrapper for Phase 1 A/B |
| `scripts/run_scout_pass.ps1` | Optional read-only scout pre-pass (`-WithScout`); auto-substitutes `run_opencode_scout.ps1` when agent wrapper is `run_opencode_agent.ps1` |
| `scripts/run_opencode_scout.ps1` | SCOUT-role OpenCode wrapper (C06); separate from IMPLEMENTER wrapper to avoid role confusion |
| `scripts/build_repo_map.ps1` | Generates deterministic `.ai-loop/repo_map.md`; called automatically by task-first when map is absent or >1 h old |
| `scripts/install_into_project.ps1` | Copies scripts + templates into a target project |
| `scripts/wrap_up_session.ps1` | Opt-in (`-WithWrapUp`) post-pass session draft → `.ai-loop/_debug/session_draft.md` |
| `scripts/promote_session.ps1` | Manual promotion of session draft into `.ai-loop/failures.md` (DD-023) |
| `templates/` | Files copied into target projects; must stay in sync with `install_into_project.ps1` |
| `tests/test_orchestrator_validation.py` | Pytest smoke tests for parsers, safe-path parity, delta semantics, prompt assembly |
| `docs/architecture.md` | Single source of truth for target design + numbered DD log (§12) |
| `docs/decisions.md` | Compact DD index (may lag architecture.md — arch doc wins) |
| `tasks/context_audit/` | Queued task specs (O01–O06, DD-011, D01–D03); not default orientation |
| `.ai-loop/project_summary.md` | Durable project-level memory (purpose, decisions, stage, risks, next steps) |
| `.ai-loop/repo_map.md` | Committed, script-generated file index |
| `.ai-loop/failures.md` | Cross-session recurring failure fingerprints (rolling 200-line cap, overflow → `.ai-loop/archive/failures/`) |

## 2. Role: Senior Software Architect

I am acting as the **Senior Software Architect** for this project.

Responsibilities:
- Develop the project according to the existing plan (architecture.md, tasks/context_audit/, open DD decisions).
- Review business logic of existing tasks for correctness and completeness before implementation.
- Generate new tasks when gaps, improvements, or risks are identified (place in `tasks/` or `tasks/context_audit/`).
- Make architectural decisions and document reasoning as DD-NNN entries in `docs/architecture.md` §12, with a pointer added to `docs/decisions.md`.

## 3. Key architectural principles and constraints

### Invariants (non-negotiable)
- **File-based memory** (DD-001): agents do not depend on chat state; all durable state is in `.ai-loop/`.
- **Safe staging only** (DD-004): never `git add -A`; only `SafeAddPaths` are staged. The literal lives in all three driver scripts and `docs/safety.md` — keep them in sync.
- **Independent reviewer** (DD-003): Codex gates commit/push; it must not share the same blind spots as the implementer.
- **Runtime artifacts off VCS** (DD-005): `codex_review.md`, `implementer_result.md`, `implementer.json`, `_debug/`, test outputs, diffs, `final_status.md` are gitignored and never staged by default.
- **Single loop per repo**: never run two orchestrators against one working tree simultaneously.
- **Implementer-neutral naming**: all `.ai-loop/` artifact names use `implementer_*`, not `cursor_*`. Parameter names `-CursorCommand` / `-CursorModel` are retained only for CLI compatibility.

### Architecture boundaries
- `docs/architecture.md` §0 = current ground truth; §1+ = aspirational target. When they conflict, §0 wins.
- `docs/decisions.md` may lag `architecture.md` §12 — architecture doc wins.
- `docs/archive/` = history only; never edit.
- `ai_loop.py` = experimental GitHub PR orchestrator; separate from the PowerShell loop; do not change unless a task explicitly authorizes it.
- `tasks/context_audit/` = queued specs; do not treat as orientation.

### Implementation constraints
- PowerShell 5.1 (Windows): no `&&`/`||` pipeline chaining, no ternary, no null-coalescing. Use `if ($?) { ... }` and explicit `$null` checks.
- Unicode em dash (U+2014) in PS1 files must be built with `[char]0x2014` to survive `Parser::ParseFile`.
- Empty array returns from functions can become `$null` in PS5.1; callers must wrap with `@(...)`.
- Codex prompt must use a single-quoted here-string so fenced JSON survives without escaping.
- `build_repo_map.ps1` output is deterministic and pinned by tests; regenerate and update tests when filesystem contracts change.

### Testing / validation expectations
- `python -m pytest -q` must stay green before any merge.
- PowerShell parse check (see AGENTS.md `## Commands`) must pass for all modified `.ps1` files.
- Tests cover: parser smoke, safe-path parity, task-first delta semantics, implementer-state resume, prompt parsing, dynamic step labels, repo map determinism, Codex template assertions, wrap-up + promote (DD-023), scout message and scout-pass markers (C06).

### Automation-loop assumptions
- `ai_loop_task_first.ps1` clears stale `.ai-loop` runtime artifacts (except `task.md`) at start.
- If the implementer makes no relevant git changes twice, Codex is skipped and the loop exits non-zero with `NO_CHANGES_AFTER_IMPLEMENTER`.
- If the only delta is `implementer_result.md`, it must contain exactly `IMPLEMENTATION_STATUS: DONE_NO_CODE_CHANGES_REQUIRED` on its own line (regex `(?im)^IMPLEMENTATION_STATUS:\s*DONE_NO_CODE_CHANGES_REQUIRED\s*$`).
- `MaxIterations` is 10 in scripts; DD-011 recommends 3 — **alignment pending** (not yet changed).
- Optional `-WithScout`: runs `run_scout_pass.ps1` before implementer; non-fatal on failure; output under `.ai-loop/_debug/`; not staged.
- Optional `-WithWrapUp`: emits `_debug/session_draft.md` post-pass; `promote_session.ps1` is manual.

### OpenCode / Qwen constraints (Phase 1)
- Three direct `llama-server` ports: `:8081` (Qwen3-Coder-30B-A3B), `:8082` (Qwen3.6-27B), `:8083` (Qwen3.6-35B-A3B).
- No proxy required for Phase 1 — all three emit native `tool_calls[]` with `--jinja`. Proxy at `:8090` (`opencode_proxy.py`) is an optional fallback for text-format tool emitters.
- `opencode_proxy.py` currently lives **outside VCS** at `C:\AI\scripts\` (Q-10 open question — relocation to `scripts/` pending).
- Scout pass must use `run_opencode_scout.ps1` (SCOUT role), not `run_opencode_agent.ps1` (IMPLEMENTER role). `run_scout_pass.ps1` auto-substitutes when `-CommandName` targets the agent wrapper.

## 4. How to work with tasks in this project

### Where tasks live
- **Active task**: `.ai-loop/task.md` — this is the contract the implementer reads.
- **Queued specs**: `tasks/context_audit/` (orchestrator queue O01–O06, DD-011) and `tasks/` root (ad-hoc reports, future specs).
- **Templates**: `templates/task.md` — the canonical format to follow when writing new tasks.

### How task plans should be read
1. Read `.ai-loop/task.md` (current task contract) — always first.
2. Read `.ai-loop/project_summary.md` — durable orientation.
3. Read `.ai-loop/repo_map.md` — file layout.
4. Read `AGENTS.md` — working rules.
5. From iteration 2+, read `.ai-loop/failures.md` for recurring failure patterns before writing the first fix.
6. Read `docs/architecture.md` only when the task is architecture-related.

### How new tasks should be created
- Use `templates/task.md` format: `## Project context`, `## Goal`, `## Scope (Allowed / Not allowed)`, `## Files likely to change`, `## Required behavior`, `## Tests`, `## Verification`, `## Implementer summary requirements`, `## Project summary update`, `## Important`.
- Prefer tasks that touch ≤80 lines of code. Flag larger tasks explicitly rather than silently growing the diff.
- Place orchestrator tasks in `tasks/context_audit/` with an `O`/`C`/`DD`-prefixed filename; place ad-hoc or target-project tasks in `tasks/`.
- Each task file must be self-contained — no cross-file implicit context.

### How business-logic review should be performed
- Architect reviews the task spec before handing it to the implementer.
- Check: does the spec correctly describe the goal? Are acceptance criteria testable? Are scope boundaries clear? Are risks called out?
- If gaps are found, update the task spec or split into subtasks before running the loop.

### How implementation agents should consume tasks
- Run `ai_loop_task_first.ps1` for new tasks (from the project root of the **target** project, not ai-orchestrator itself when working on target projects).
- The implementer reads `.ai-loop/task.md` via the `$STABLE_PREAMBLE` + scope blocks + TASK body prompt assembly.
- After implementation, fill `.ai-loop/implementer_summary.md` per the AGENTS.md contract (changed files, test count, summary ≤50 lines).
- Run `continue_ai_loop.ps1` if the loop was interrupted.

### Artifacts produced after work
- On PASS: code changes committed (unless `-NoPush`); `.ai-loop/implementer_summary.md` filled; `.ai-loop/project_summary.md` updated with durable changes.
- On STOP: inspect `.ai-loop/codex_review.md` and `.ai-loop/implementer_summary.md`; resume with `continue_ai_loop.ps1`.
- Optional: run `promote_session.ps1` after a passing run to anchor failure history in `.ai-loop/failures.md`.

## 5. Important context for future sessions

### Known risks
- **Q-10 / DD-020**: `opencode_proxy.py` lives at `C:\AI\scripts\` outside VCS. Phase 1 direct-port runs don't need it, but any workflow using port `:8090` breaks if the file is lost or the machine changes. Mitigation: relocate to `scripts/opencode_proxy.py` (tracked but not scheduled).
- **DD-011 pending**: `MaxIterations` default is 10 in all three driver scripts but architecture recommends 3. A dedicated task + test exists in `tasks/context_audit/DD011_cap_max_iterations.md` but is not yet run.
- **Phase 1 A/B not complete**: Cursor remains the production implementer (DD-021). Do not switch the default implementer until OpenCode+Qwen demonstrates stability across ≥5 real H2N tasks.
- **`build_repo_map.ps1` must be in target project's `scripts/`**: the task-first guard silently skips regeneration if the script is absent — no error is raised. This caused context overflow in h2n-range-extractor (scout bug report, Bug 1). `install_into_project.ps1` copies it; verify after install.
- **Templates contract**: whenever a file is added to or removed from `templates/`, `scripts/install_into_project.ps1` must also be updated. Tests don't catch this automatically.
- **`SafeAddPaths` synchronization**: the literal list lives in `ai_loop_auto.ps1`, `ai_loop_task_first.ps1`, `continue_ai_loop.ps1`, and `docs/safety.md`. All four must be updated together when adding a new always-committed path.

### Likely next steps
1. Run `python -m pytest -q` to verify green baseline after C06.
2. Run DD-011 task (`tasks/context_audit/DD011_cap_max_iterations.md`) — low risk, changes one default and pins a test.
3. Continue Phase 1 A/B data collection on H2N tasks; use `tasks/context_audit/D01_compact_h2n_project_summary.md` → `D02_update_h2n_agent_setup.md` → `D03_compact_review_state.md` in h2n target projects after orchestrator queue is fully green.
4. Decide on Q-10 (proxy relocation) before expanding OpenCode usage beyond Phase 1 A/B.
5. Claude planner integration (`ai_loop_plan_with_claude.ps1`) and Claude business review hook are deferred until the orchestrator queue is stable.

### Assumptions that must not be forgotten
- `docs/architecture.md` §0 is ground truth for what runs today; §1+ is aspirational.
- `docs/architecture.md` §12 is authoritative for DD decisions; `docs/decisions.md` is an index that may lag.
- `.ai-loop/implementer.json` is runtime-only (gitignored); it stores wrapper path and model for resume — not durable documentation.
- Untracked root-level `.md` files are picked up by `build_repo_map.ps1`; delete or move them under ignored paths before regenerating the map.
- `tasks/context_audit/` is a spec queue, not orientation material. Do not read it during normal context loading.
- Per AGENTS.md retrieval policy: do not propose vector indexes, embedding stores, or AST symbol indexes for this repo (evaluated and declined per `tasks/claude_ai_orcestrator_context_plan_report.md` §6, §13).

### Areas needing extra caution
- **PowerShell 5.1 quirks**: empty pipelines, `$null` vs empty array, no ternary, no `&&`. Test with `Parser::ParseFile` after any script edit.
- **Scout role isolation**: always use `run_opencode_scout.ps1` (SCOUT) for scout passes, never `run_opencode_agent.ps1` (IMPLEMENTER). Mixing roles caused silent failures in h2n-range-extractor (C06 bug 2).
- **Codex prompt single-quote here-string**: must remain single-quoted to protect fenced JSON in the template. Do not convert to double-quoted.
- **Git hygiene**: never commit `.ai-loop/_debug/`, `.tmp/`, `input/`, `output/`. Use `git mv` for renames. Scan for secrets before any public push.

### Inconsistencies between docs, tasks, scripts, and source
- `docs/decisions.md` DD-007 through DD-019 are listed as reserved placeholders; `docs/architecture.md` §12 jumps from DD-006 to DD-011, DD-020, DD-021, DD-022, DD-023. The gaps are intentional (reserved) but the index file looks incomplete.
- `docs/workflow.md` and `README.md` reference `MaxIterations 10` as the default example; the architecture doc (DD-011) recommends 3. This is a documented pending alignment, not a bug, but it can confuse new readers.
- `tasks/context_audit/README.md` references a project directory named `ai-git-orchestrator` in the standard invocation block — the actual repo is named `ai-orchestrator`. This is a stale path in the queue README; the task specs themselves are correct.
