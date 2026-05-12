# D02 — Update h2n-range-extractor agent setup

**Project:** `H2N_parser/h2n-range-extractor`
**CWD for install step:** `C:\Users\che\Documents\Projects\ai-git-orchestrator`
**CWD for AGENTS.md / gitignore step:** `C:\Users\che\Documents\Projects\H2N_parser\h2n-range-extractor`
**Prerequisite:** D01 completed (project_summary.md compacted).
**Risk:** medium — updates production scripts in target project.

How to run:
```powershell
# Step 1: reinstall scripts and templates from updated orchestrator
cd C:\Users\che\Documents\Projects\ai-git-orchestrator
powershell -ExecutionPolicy Bypass -File .\scripts\install_into_project.ps1 `
    -TargetProject "C:\Users\che\Documents\Projects\H2N_parser\h2n-range-extractor"
# (Do NOT pass -OverwriteTask or -OverwriteProjectSummary — preserve existing files)

# Step 2: paste task spec below into h2n-range-extractor\.ai-loop\task.md, then:
cd C:\Users\che\Documents\Projects\H2N_parser\h2n-range-extractor
powershell -ExecutionPolicy Bypass -File .\scripts\ai_loop_task_first.ps1 -NoPush
```

---

## Project context

After D01, `project_summary.md` is compact. The scripts and templates in `h2n-range-extractor` were installed on 2026-05-07 — before the O05 template updates and O06 script changes. The project also has a 3-line placeholder `AGENTS.md` and a `.gitignore` that doesn't account for the new O06 artifacts (`.ai-loop/_debug/`, `diff_summary.txt`, `test_failures_summary.md`).

## Goal

1. Reinstall scripts and templates from updated `ai-git-orchestrator` (the install step above).
2. Write a proper `AGENTS.md` for `h2n-range-extractor`.
3. Update `.gitignore` to cover O06 artifacts.
4. Move `.ai-loop/cursor_agent_output.txt` (if present) to `.ai-loop/_debug/cursor_agent_output.txt`.

## Scope

**Allowed:**
- `AGENTS.md` (replace 3-line placeholder)
- `.gitignore` (add missing entries)
- `git mv .ai-loop/cursor_agent_output.txt .ai-loop/_debug/cursor_agent_output.txt` (if file exists)
- `.ai-loop/codex_review_prompt.md`, `.ai-loop/cursor_summary_template.md` — already overwritten by the install step above; no manual edit needed.
- `scripts/` — already overwritten by the install step above; no manual edit needed.

**Not allowed:**
- `src/`, `tests/` — no code changes.
- `.ai-loop/project_summary.md`, `.ai-loop/task.md` — do not overwrite.
- `scripts/check_changed_stat.ps1` — project-specific helper, not managed by orchestrator.

## Required behavior

### AGENTS.md content

Write `AGENTS.md` at the repo root with these sections:

```
# AGENTS.md

Working rules for AI agents operating in `h2n-range-extractor`.

## Project purpose (one line)
Python research tool that reverse-engineers Hand2Note 4 config exports (.h2nconfig as ZIP) to surface color/numeric byte-region candidates as ranked heuristic artifacts.

## Working scope
You may edit:
- `src/` — application logic
- `tests/` — pytest coverage
- `README.md`, `AGENTS.md`, `.gitignore`, `requirements.txt`, `pytest.ini`
- `.ai-loop/task.md`, `.ai-loop/cursor_summary.md`, `.ai-loop/project_summary.md`

Never edit:
- `.ai-loop/_debug/` — raw agent stdout, debug-only
- `input/`, `extracted/`, `output/` — local data, not committed
- `scripts/ai_loop_auto.ps1`, `scripts/ai_loop_task_first.ps1`, `scripts/continue_ai_loop.ps1`,
  `scripts/run_cursor_agent.ps1`, `scripts/filter_pytest_failures.py` — managed by ai-git-orchestrator;
  reinstall via install_into_project.ps1 if updates are needed.

## Read priority
1. `.ai-loop/task.md` — current task contract (always)
2. `.ai-loop/project_summary.md` — durable orientation (always)
3. `AGENTS.md` — this file (always, once)
4. `.ai-loop/cursor_summary.md` — previous iteration only (if N > 1)
5. Source file(s) directly relevant to the task

Do not read by default:
- `.ai-loop/_debug/` — human debugging only
- `.ai-loop/*.json`, `.ai-loop/*.xlsx`, `.ai-loop/*_report.md` — large analysis mirrors, gitignored

## Commands
Test: `python -m pytest -q`
Test with traceback: `python -m pytest -q --tb=short`
Smoke: see `.ai-loop/task.md` for current smoke command.

## Safe paths (committed by orchestrator)
`src/,tests/,README.md,AGENTS.md,scripts/,requirements.txt,pytest.ini,.gitignore,.ai-loop/task.md,.ai-loop/cursor_summary.md,.ai-loop/project_summary.md`

## Key invariants
- `.ai-loop/` mirror flags (`--no-mirror-ai-loop`) prevent large analysis files from being written to `.ai-loop/` during smoke runs; default is mirror-on.
- `openpyxl` requires XML-safe strings — use `sanitize_for_excel()` before writing cell values.
- `stat_id_window` default is 64; widening raises false-positive int32 attachment risk.
- `--allow-content-source` relaxes strict source selection in `analyze-popup`; only use when task explicitly requires it.

## Cursor summary contract
After each iteration, update `.ai-loop/cursor_summary.md` with:
- changed files (brief)
- test result (count, not full output)
- implemented work (3–5 lines)
- skipped items with reason
- remaining risks (1–3 bullets)

Do NOT include prior-roll history, full diffs, or multi-page narratives. Target: under 50 lines.

## Git hygiene
- Do not commit `.ai-loop/_debug/`, `.tmp/`, `input/`, `extracted/`, `output/`.
- Use `git mv` for renames.
- Do not commit secrets.
```

### .gitignore additions

Add to `.gitignore` (after the existing AI loop runtime artifacts section):

```
# O06 artifacts (ai-git-orchestrator ≥ 2026-05-12)
.ai-loop/_debug/
.ai-loop/diff_summary.txt
.ai-loop/test_failures_summary.md
```

### _debug dir

If `.ai-loop/cursor_agent_output.txt` exists:
```powershell
New-Item -ItemType Directory -Force -Path .ai-loop\_debug | Out-Null
git mv .ai-loop\cursor_agent_output.txt .ai-loop\_debug\cursor_agent_output.txt
```

## Files likely to change

- `AGENTS.md` (replace)
- `.gitignore` (append 3 lines)
- `scripts/ai_loop_auto.ps1` (reinstalled from orchestrator)
- `scripts/ai_loop_task_first.ps1` (reinstalled)
- `scripts/continue_ai_loop.ps1` (reinstalled)
- `scripts/run_cursor_agent.ps1` (new)
- `scripts/filter_pytest_failures.py` (new)
- `.ai-loop/codex_review_prompt.md` (reinstalled from templates)
- `.ai-loop/cursor_summary_template.md` (reinstalled)
- `.ai-loop/_debug/cursor_agent_output.txt` (moved, if source exists)

## Tests

Run `python -m pytest -q` after all changes. Expected: same pass count as before (no code changes).

## Verification

1. `AGENTS.md` exists at repo root, has sections: Project purpose, Working scope, Read priority, Commands, Safe paths, Key invariants, Cursor summary contract, Git hygiene.
2. `.gitignore` contains `.ai-loop/_debug/`, `.ai-loop/diff_summary.txt`, `.ai-loop/test_failures_summary.md`.
3. `scripts/run_cursor_agent.ps1` and `scripts/filter_pytest_failures.py` exist.
4. `.ai-loop/cursor_agent_output.txt` does NOT exist at old path (moved or already absent).
5. `python -m pytest -q` passes with same count.
6. `git status --short` shows no unintended modifications outside the allowed file list.

## Cursor summary requirements

- Changed files (list)
- Whether install_into_project was run and which files it updated
- Test result (count only)
- Any files that could not be moved (e.g. cursor_agent_output.txt absent — OK)

## Project summary update

No update needed — D01 already produced a fresh `project_summary.md`.

## Important

- The install step (run from `ai-git-orchestrator` CWD) must happen BEFORE the Cursor task runs, so the reinstalled scripts are in place.
- Do NOT pass `-OverwriteTask` or `-OverwriteProjectSummary` to `install_into_project.ps1` — the existing `.ai-loop/task.md` and `.ai-loop/project_summary.md` must be preserved.
- The `scripts/check_changed_stat.ps1` is project-specific and should not be touched.
