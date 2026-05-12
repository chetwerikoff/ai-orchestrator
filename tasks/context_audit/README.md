# Context audit task queue

Tasks distilled from the audit delivered on 2026-05-12 (see chat history or
save to `docs/context_audit.md`). Each file is a standalone, ready-to-paste
task spec — no cross-file references, no implicit context required.

## Priority: orchestrator first

Decision (2026-05-12, user): rebuild `ai-git-orchestrator` first, then
propagate the new conventions into `H2N_parser/h2n-range-extractor` and
`H2N_parser/h2n-claude-review`.

Rationale: the orchestrator owns `templates/`, `scripts/`, and the file
contract every target project copies. Fixing those once eliminates classes of
context bloat across all current and future target projects.

## Orchestrator queue (run in this order)

All six tasks below run in **`ai-git-orchestrator`** as CWD. Standard
invocation:

```powershell
cd C:\Users\che\Documents\Projects\ai-git-orchestrator
# 1. Copy the section below "---" from the task file into .ai-loop\task.md
# 2. Verify .ai-loop\task.md matches what you want to run
powershell -ExecutionPolicy Bypass -File .\scripts\ai_loop_task_first.ps1 -NoPush
# 3. After final_status PASS, inspect diff, then commit (push manually if happy).
```

Use `-NoPush` for every task in this queue. None of these should auto-push.

| # | File | What it does | Risk | Lines touched (est.) |
|---|------|--------------|------|----------------------|
| O01 | `O01_archive_obsolete_root_docs.md` | `git mv` 3 large root .md into `docs/archive/` | very low | 3 file moves |
| O02 | `O02_create_agents_md.md` | Create root `AGENTS.md` (working rules, 70 lines) | low | +1 new file |
| O03 | `O03_actualize_architecture_doc.md` | Restructure `docs/architecture.md` into "Current state" + "Target state" sections, document the OpenCode proxy reality | medium | ~150 lines edited |
| O04 | `O04_sync_supporting_docs.md` | Extend `docs/decisions.md` DD-007..DD-021; tiny `workflow.md` and `README.md` updates | low | ~80 lines added |
| O05 | `O05_update_templates.md` | Update all 4 files in `templates/` with AGENTS.md reference, read priority, anti-leak rules | low | ~60 lines |
| O06 | `O06_filter_logs_and_hide_debug.md` | Add `test_failures_summary.md` + `diff_summary.txt` generation; move `cursor_agent_output.txt` and `cursor_implementation_*` to `.ai-loop\_debug\` | medium | ~80 lines in `ai_loop_auto.ps1` + `ai_loop_task_first.ps1` + tests |

## Why this order

- **O01 before O02**: archive cleans the root namespace so the new `AGENTS.md`
  is the visible authority, not buried among 6 docs.
- **O02 before O03**: `AGENTS.md` defines forbidden paths and read priority;
  `architecture.md` references those rules.
- **O03 before O04**: `architecture.md` is the source of truth for decisions
  DD-007..DD-021. `decisions.md` and `workflow.md` should not contradict it.
- **O04 before O05**: templates link to `docs/decisions.md`. Want a coherent
  doc set first.
- **O05 before O06**: templates encode the file contract that O06 modifies
  (new filtered artefacts, `_debug` hidden files). Templates first means O06
  doesn't have to also rewrite templates.
- **O06 last**: script changes. Higher risk than docs. Run after all docs are
  coherent — easier to test against a clean baseline.

## Acceptance for the orchestrator queue as a whole

After O01–O06 all complete:

1. `ai-git-orchestrator` root contains: `README.md`, `AGENTS.md`,
   `ai_loop.py`, `pytest.ini`, `requirements.txt`, `task.md` only.
   No other `.md` clutter.
2. `docs/` contains: `architecture.md` (restructured), `decisions.md`
   (extended), `workflow.md` (updated), `safety.md` (untouched),
   `archive/` (3 moved files).
3. `templates/` contains: `task.md`, `codex_review_prompt.md`,
   `project_summary.md`, `cursor_summary_template.md` — all updated to enforce
   AGENTS.md reference and anti-leak rules.
4. `scripts/ai_loop_auto.ps1` generates filtered `test_failures_summary.md` on
   pytest failure and `diff_summary.txt` always.
5. `cursor_agent_output.txt` / `cursor_implementation_*` files write to
   `.ai-loop/_debug/`, not `.ai-loop/`.
6. `python -m pytest -q` passes (no regression in orchestrator tests).
7. Codex review prompt in `ai_loop_auto.ps1` reads `test_failures_summary.md`
   first, falls back to `test_output.txt`.

## Next queue (run after O01–O06 are merged)

### Orchestrator hardening

| # | File | What it does | Risk |
|---|------|--------------|------|
| DD-011 | `DD011_cap_max_iterations.md` | Change default `MaxIterations` 10→3 in `ai_loop_auto.ps1` + pin test | very low |

Run via `ai_loop_task_first.ps1 -NoPush` in `ai-git-orchestrator`.

### H2N context cleanup (run in order)

| # | File | Project | What it does | Risk |
|---|------|---------|--------------|------|
| D01 | `D01_compact_h2n_project_summary.md` | h2n-range-extractor | Compact `project_summary.md` 202→≤60 lines | low |
| D02 | `D02_update_h2n_agent_setup.md` | h2n-range-extractor | Reinstall scripts + write proper `AGENTS.md` + update `.gitignore` | medium |
| D03 | `D03_compact_review_state.md` | h2n-claude-review | Compact `REVIEW_STATE.md` 386→≤80 lines (manual edit, no AI loop) | low |

Notes:
- D01 and DD-011 are independent; can run in any order.
- D02 depends on D01 (project_summary must be fresh before reinstalling templates).
- D03 is manual (h2n-claude-review does not use the PowerShell AI loop — it uses `CLAUDE.md`).
- D04 (create AGENTS.md in h2n-claude-review) was **cancelled** — the project already has `CLAUDE.md` which serves the same purpose.

## What this queue does NOT do

Out of scope until orchestrator queue completes and open questions Q1–Q10
from the audit are answered:

- Claude planner integration (new `scripts/ai_loop_plan_with_claude.ps1`)
- Claude business review hook (new `scripts/ai_loop_business_review.ps1`)
- OpenCode proxy relocation from `C:\AI\scripts\` into VCS
- `MaxIterations` default change from 10 to 3 (DD-011 — needs separate task with
  test coverage)
- Cost telemetry (`cost.jsonl`)
- Stacked PRs, parallel worktrees, dashboard UI

## How to read each task file

Each file in this directory follows the structure:

```text
# Header (project, how to run, prerequisites)
---
# Standard task spec (templates/task.md format)
## Project context
## Goal
## Scope (Allowed / Not allowed)
## Files likely to change
## Required behavior
## Tests
## Verification
## Cursor summary requirements
## Project summary update
## Important
```

The content **below the `---` separator** is what gets pasted into
`.ai-loop\task.md`. The header is just for the human queue manager (you).
