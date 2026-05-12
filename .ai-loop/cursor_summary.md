# Cursor summary

## O01 — Archived root docs (destinations)

Three files live under `docs/archive/` (content unchanged; git move / index as tracked archival paths):

1. `docs/archive/2026-05-11_architecture_review.md` (from `architecture_review.md`)
2. `docs/archive/2026-05-11_opencode_harness_expert_review.md` (from `opencode_harness_expert_review.md`)
3. `docs/archive/2026-05-11_qwen_opencode_problem.md` (from `qwen_opencode_problem_for_claude.md`)

## Reference updates

- **`README.md`:** no references to the old basenames; **no change**.
- **Other tracked docs:** searched under `docs/` (excluding archive content in verification); **no** updates required for broken links to the old root paths.

## Fix prompt (this iteration)

- **Out-of-scope `docs/architecture.md`:** removed from the index (`git rm --cached -f`) and deleted from the working tree so O01 stays limited to the three dated archive files plus loop artifacts. Archived Markdown bodies were **not** edited.

## Changed files (this iteration)

- `.ai-loop/cursor_summary.md` — this file.
- `.ai-loop/project_summary.md` — durable O01 scope clarification (`docs/archive/` moves only; `docs/architecture.md` out of scope for that pass).
- `.ai-loop/git_status.txt` — refreshed after cleanup.
- `.ai-loop/test_output.txt` — refreshed from `python -m pytest -q`.

## Tests

- `python -m pytest -q` → **24 passed**, **0 skipped** (~0.19s, exit 0). Full console capture: `.ai-loop/test_output.txt`.

## Task-specific live run

- `powershell -ExecutionPolicy Bypass -File .\scripts\ai_loop_task_first.ps1 -NoPush` — **skipped**: full Cursor + Codex orchestrator run with local CLIs/UI; fix-prompt cleanup applied directly in-repo without re-invoking the driver.

## Remaining risks

- If git does not show rename similarity for a move, history is still preserved via byte-identical content; `git log --follow` on the archived paths remains viable.
- Untracked `.claude/` and `tasks/context_audit/` paths may still appear in porcelain; staging should stay within orchestrator `SafeAddPaths` only.
- Formal `docs/architecture.md` (and supporting doc sync) remain **future queued tasks** (e.g. O03+) — **not** introduced as staged content under O01.
