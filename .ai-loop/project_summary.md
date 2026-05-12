# Project Summary

## Project purpose

Local PowerShell-based AI development loop that coordinates Cursor (implementer), Codex (review), optional tests, and guarded git commit/push using a file-based contract under `.ai-loop/`.

## Current architecture

- `ai_loop.py` -- experimental GitHub PR orchestrator (stdlib-only); separate from the primary PowerShell Cursor + Codex loop; does not replace `scripts/ai_loop_auto.ps1` / `ai_loop_task_first.ps1`.
- `scripts/ai_loop_auto.ps1`, `scripts/continue_ai_loop.ps1`, `scripts/install_into_project.ps1` -- PowerShell drivers and installer.
- `scripts/ai_loop_task_first.ps1` -- task-first entry: clears a defined set of `.ai-loop` runtime artifacts, stubs `cursor_summary.md`, runs Cursor, gates on a **path-set** delta from `git status --porcelain --untracked-files=all` (excluding orchestrator scratch paths) plus **mtime/existence** for `.ai-loop/cursor_implementation_result.md`. `Get-ImplementationDeltaPaths` emits sorted paths on the pipeline (avoids Windows PowerShell turning empty `return @()` into `$null`); `Invoke-CursorImplementation` assigns `@(Get-ImplementationDeltaPaths)` and uses `Compare-Object @($beforePaths) @($afterPaths)` so empty sets compare reliably. Then invokes `ai_loop_auto.ps1` forwarding `-NoPush`, `-TestCommand`, `-PostFixCommand`, and `-SafeAddPaths`.
- `tests/test_ai_loop.py` -- pytest coverage for pure helpers (`slugify`, `write_text_safe`). The `write_text_safe` test uses a unique-named scratch file under `tests/` removed in `finally`, avoiding pytest `tmp_path`, basetemp under `.tmp/`, repo-root temp dirs, and `tempfile.TemporaryDirectory(dir=repo)` (all problematic on some Windows setups).
- `tests/test_orchestrator_validation.py` -- PowerShell parser smoke checks for the driver scripts; `SafeAddPaths` default parity across `ai_loop_auto.ps1`, `ai_loop_task_first.ps1`, and `continue_ai_loop.ps1`; porcelain-flag and path-set / marker-gate reference tests; native-arg helper `ConvertTo-CrtSafeArg` present in both drivers with assertions on `-Value` usage and minimum call counts where applicable (`python -m pytest -q` passes with current drivers).
- Test failure context for Codex review is provided by `scripts/filter_pytest_failures.py` (deterministic, no LLM) writing `.ai-loop/test_failures_summary.md` when pytest fails. It parses pytest’s `FAILURES` section (through `short test summary info`), pairs underscore-delimited traceback blocks with ordered `FAILED …` lines from the short summary, and keeps the final session count line out of traceback fences (including thin layouts where the closing line looks like `1 failed, … in 5.0s` without `===` wrappers). Thin layouts without `FAILURES` still fall back to scanning leading `FAILED` lines. `Save-TestAndDiff` also writes `.ai-loop/diff_summary.txt` via `git diff --stat`.
- `pytest.ini` -- limits collection to `tests/` via `testpaths` and skips common runtime dirs (`.ai-loop`, `.tmp`, stray root temp names, caches) via `norecursedirs` so pytest does not wander the repo root by default.
- `docs/archive/` — dated superseded design / review Markdown under `docs/` (O01 moved three root-level review/diagnostic files to `2026-05-11_*.md` without editing file bodies).
- `docs/architecture.md` — separates current state (§0) from target design (§1+); **§9** inlines the deferred multi-script / `orchestrator/` factory blueprint (**§10–§11** spell safety + companion references; archives hold verbatim critiques). **`docs/decisions.md`** carries **DD-001..DD-021** with placeholders for numbers absent from **`docs/architecture.md`** §12. OpenCode llama.cpp proxy documented as **DD-020** (see §5.3, §12). Decision log §12 lists concrete entries plus gaps between DD-007..DD-010 and DD-012..DD-019.
- `.ai-loop/*.md` -- task file, durable summary, review prompts, cursor summary template.

## Current pipeline / workflow

Install scripts into a target repo, author task and context. For a **new** task, run `ai_loop_task_first.ps1` (Cursor first, then `ai_loop_auto.ps1` when there is a meaningful implementation delta). For **existing** changes, run `ai_loop_auto.ps1` directly. Review artifacts, continue or commit per safety model (`SafeAddPaths`, ignored runtime files). After Codex returns `PASS`, the PowerShell orchestrator runs the final test gate (`Commit-And-Push`), then stages safe paths and pushes unless `-NoPush`. Resume mode respects existing `next_cursor_prompt.md` or `codex_review.md` (`PASS` → final gate + commit/push; `FIX_REQUIRED` → extract fix prompt → Cursor).

## Important design decisions

- `docs/architecture.md` is the single source of truth for target design; §0 is factual today, §1 onward is aspirational until phased rollout completes; **§9** embeds the full deferred-component blueprint inline (critique-heavy expert review prose stays archived). **DD-020** records the required `opencode_proxy` stack (port 8090); **DD-021** keeps Cursor as production implementer through Phase 1.
- Staging is restricted to explicit safe paths; runtime outputs under `.ai-loop/` (e.g. `last_diff.patch`, `test_output*.txt`, `git_status.txt`, Cursor implementation scratch/result files, reviews) stay out of commits by default.
- Raw agent stdout and implementation scratch (`cursor_agent_output.txt`, `cursor_implementation_prompt.md`, `cursor_implementation_output.txt`) live under `.ai-loop/_debug/` (gitignored). Reviewer agents must not read that directory; `cursor_implementation_result.md` stays at `.ai-loop/` root for the gated contract.
- Task-first mode enforces “result only” completions using a **symmetric path-set** delta from `git status --porcelain --untracked-files=all` after excluding the same orchestrator scratch paths (`cursor_summary.md`, implementation prompt/output), merged with **last-write-time / existence** checks for `.ai-loop/cursor_implementation_result.md`; each task-first run resets `cursor_summary.md` to a stub so Codex does not read stale summaries.
- Default `SafeAddPaths` in `ai_loop_auto.ps1`, `continue_ai_loop.ps1`, and `ai_loop_task_first.ps1` includes `src/`, `tests/`, `README.md`, `AGENTS.md`, `scripts/`, `docs/`, `templates/`, `ai_loop.py`, pytest/config paths, and the durable `.ai-loop/task.md`, `.ai-loop/cursor_summary.md`, `.ai-loop/project_summary.md` trio. `docs/safety.md` documents that same default list (path order matches the shared literal).
- `project_summary.md` holds long-lived context; it is not a per-task changelog.
- Parity between the Python `after-cursor` step and PowerShell `Save-TestAndDiff` includes a short git status file for reviewers.
- Codex is the automated review gate before commit/push; Codex PASS triggers final tests then commit/push.
- Inline `Run-CodexReview` prompt in `ai_loop_auto.ps1` instructs reviewers to load `.ai-loop/diff_summary.txt` next to `.ai-loop/last_diff.patch`, and to read `.ai-loop/test_failures_summary.md` when it exists before falling back to `.ai-loop/test_output.txt`.

## Known risks / constraints

- Native-arg escaping expectations in `tests/test_orchestrator_validation.py` should stay aligned whenever Cursor stdin / argv forwarding changes in the drivers; current repo state passes full pytest (`python -m pytest -q`).
- External CLIs (`codex`; Cursor agent via `run_cursor_agent.ps1` / local install) must be installed and authenticated where those steps are used.
- On Windows PowerShell, an empty array returned with `return @()` from a function can surface as `$null` to callers; task-first path capture avoids that for the implementation-delta helper (pipeline output + `@(Get-ImplementationDeltaPaths)` / wrapped `Compare-Object`).

## Current stage

**Reviewable:** O04 companion doc sync (**`docs/decisions.md`**, **`docs/workflow.md`**, **`README.md`**). **`python -m pytest -q`** passes with current orchestrator validation (including native-arg helper checks). PowerShell orchestrator still uses Codex-only automated review; post-Codex PASS runs final test gate, commit, and optional push. Task-first mode gates Codex until Cursor produces a path-set delta or updates the result file on disk; `ai_loop_auto.ps1` skips Codex when the tree is clean before review (exits **6** / **7**) and clears stale `.ai-loop` runtime artifacts on non-resume starts.

## Last completed task

**O04 (doc companion sync):** `docs/decisions.md`, `docs/workflow.md`, and `README.md` aligned with `docs/architecture.md` (indexed DD-007..DD-021 with placeholders where §12 gaps exist; workflow current-vs-target pointer; README `AGENTS.md`, OpenCode/Qwen phase note, install-into-target list checked against `scripts/install_into_project.ps1`). README optional `-SafeAddPaths` example matches script default ordering (includes `AGENTS.md` after `README.md`).

## Next likely steps

1. Stage root `ai_loop.py`, `pytest.ini`, `tests/`, `scripts/`, `docs/`, `templates/`, **`AGENTS.md`**, and other paths listed in orchestrator `SafeAddPaths` when committing.
2. Re-run `ai_loop_task_first.ps1` or `ai_loop_auto.ps1` / Codex when ready for the next task or review round.

## Notes for future AI sessions

- Templates in `templates/` enforce `AGENTS.md` reading and anti-history-leak rules. See `tasks/context_audit/O05_update_templates.md` for rationale.
- `docs/decisions.md` is the numbered index; `docs/architecture.md` §12 is the authoritative version with rationale.
- Working rules for AI agents are in `AGENTS.md` at repo root.
- Keep durable project-level context here; put per-iteration detail in `.ai-loop/cursor_summary.md`.
- Use **`.ai-loop/task.md`** as the task source of truth; do not reintroduce a duplicate root `task.md`.
