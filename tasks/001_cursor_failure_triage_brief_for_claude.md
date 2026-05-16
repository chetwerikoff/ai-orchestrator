# Task: Cursor failure triage brief for Claude

## Project context

Required reading for the implementer:

- `AGENTS.md`
- `.ai-loop/task.md` (this file)
- `.ai-loop/project_summary.md`
- `.ai-loop/repo_map.md`

## Goal

Add an optional, manual **read-only Cursor diagnostic pass** that gathers bounded orchestrator state (recent `.ai-loop` artifacts, core durable loop files, git status, and a compact diff summary), merges optional user-supplied problem text or file content, invokes Cursor Agent once via the existing stdin wrapper, and writes a single advisory brief to `.ai-loop/failure_triage.md` so humans can paste it to Claude with less token overhead than raw log hunting.

## Scope

**Allowed:**

- New PowerShell script under `scripts/` plus one prompt template under `templates/`.
- `.gitignore` entries for the triage output and any deterministic transient paths the script uses.
- Installer updates so target projects receive the script and template.
- Focused pytest coverage that validates wiring (e.g., script parses, writes expected output path when Cursor is stubbed or skipped via test harness pattern already used for planner/task-first).
- Brief documentation updates in `AGENTS.md`, `docs/workflow.md`, and `.ai-loop/project_summary.md` describing **when and how** to run triage before asking Claude for diagnosis.

**Not allowed:**

- Changes to `ai_loop.py`, `docs/archive/**`, or routine reads/writes under `.ai-loop/_debug/**` except optional `-IncludeDebug` intake paths explicitly scoped by the task.
- Auto-invoking triage from `ai_loop_auto.ps1`, `ai_loop_task_first.ps1`, or planner flows (stay manual/opt-in).
- Running pytest suites, Codex, Claude planner/reviewer, OpenCode implementer, or any fix/editing automation from the triage script.

## Files in scope

- `scripts/triage_failure.ps1` (new)
- `templates/failure_triage_prompt.md` (new)
- `.gitignore`
- `scripts/install_into_project.ps1`
- `tests/test_orchestrator_validation.py`
- `AGENTS.md`
- `docs/workflow.md`
- `.ai-loop/project_summary.md`

## Files out of scope

- `docs/archive/**`
- `.ai-loop/_debug/**` (except where `-IncludeDebug` explicitly permits bounded reads described in this task)
- `ai_loop.py`
- `scripts/run_cursor_agent.ps1` (unless a blocking defect appears; default is no change)
- `templates/codex_review_prompt.md`, `scripts/ai_loop_auto.ps1`, `scripts/ai_loop_task_first.ps1`, `scripts/ai_loop_plan.ps1`
- `tasks/**` queue specs (unless later task explicitly lists them)

## Required behavior

1. **`scripts/triage_failure.ps1`** exposes at minimum:
   - `-ProblemFile` (optional path to a user note or pasted log file),
   - `-Message` (optional inline text),
   - `-IncludeDebug` (switch; when set, may include **bounded** excerpts from `.ai-loop/_debug/`; when absent, do not read `_debug`),
   - `-RepoRoot` or equivalent optional anchor defaulting to the invocation directory resolution pattern consistent with other `scripts/*.ps1` callers (pick one simple convention and document it in comments only if needed).
2. Resolve the orchestrator repo root reliably (same general approach as existing scripts: walk upward for `.git` or known markers—mirror an existing helper pattern from nearby scripts rather than inventing a new subsystem).
3. **Auto-gather bounded context** into the stdin payload (not necessarily separate disk concatenation):
   - Always include full contents of: `.ai-loop/task.md`, `.ai-loop/implementer_summary.md`, `.ai-loop/project_summary.md`, `.ai-loop/repo_map.md` when present (truncate individual files with a clear banner if oversized—prefer generous head/tail over silent omission).
   - Include `git status --short` and a **compact** diff summary (stat or similar short form acceptable; avoid dumping entire working tree diff when huge—cap with explicit note when truncated).
   - Enumerate and inline **recent** `.ai-loop/*.md` and `.ai-loop/*.txt` with freshness/size caps (e.g., sort by last write time, take newest few, per-file byte/limit with truncation banner). Skip `_debug` unless `-IncludeDebug`.
   - If `-ProblemFile` points at a path outside `.ai-loop`, treat it as user-supplied narrative/log **bounded** the same way (never blindly paste multi-megabyte files).
   - Merge `-Message` when provided (bounded).
4. Build the Cursor stdin prompt from `templates/failure_triage_prompt.md` plus clearly labeled sections for gathered artifacts (the template must state **read-only**, **no edits**, **no fixes**, **concise brief only**, and require output shaped for downstream Claude consumption).
5. Invoke **`scripts/run_cursor_agent.ps1`** via repo-relative path beside `$PSScriptRoot` with the composed stdin payload (same general invocation expectations as other wrappers); failures must emit clear errors and avoid partial misleading writes when Cursor fails pre-output.
6. Write Cursor stdout (normalized UTF-8) to **`.ai-loop/failure_triage.md`**, overwriting prior runs; heading targets should match the USER ASK structure closely enough that paste-to-Claude is frictionless (`# Failure Triage Brief` plus the listed sections).
7. **`scripts/install_into_project.ps1`** copies the new script and template into target projects alongside existing orchestrator payloads (follow existing copy loops and naming).
8. **`.gitignore`** ignores at minimum `.ai-loop/failure_triage.md`; also ignore any fixed transient filenames the script writes under `.ai-loop/` for prompt staging **only if** the implementation chooses deterministic paths there (prefer `$env:TEMP` transient files to minimize `.ai-loop` clutter—if so, document that choice briefly in `docs/workflow.md`).
9. **Tests**: add a small deterministic check under `tests/test_orchestrator_validation.py` that exercises argument parsing / dry-ish behavior without requiring a live Cursor CLI where feasible (follow existing subprocess harness patterns used for planner/task-first tests); if full stdin plumbing cannot be stubbed cheaply, test file gathering truncation banners and “skip `_debug` unless switch” logic via controlled scratch dirs under `tests/` fixtures.

## Tests

- Extend `tests/test_orchestrator_validation.py` with minimal coverage for `triage_failure.ps1` (parse + non-interactive behavior path).
- Run `python -m pytest -q`.

## Verification

```powershell
python -m pytest -q
```

```powershell
powershell -NoProfile -Command "[void][System.Management.Automation.Language.Parser]::ParseFile('scripts\triage_failure.ps1', [ref]$null, [ref]$null)"
```

Manual smoke (human):

```powershell
.\scripts\triage_failure.ps1 -Message "example"
```

## Implementer summary requirements

1. List changed files briefly.
2. Report pytest count summary only (pass/fail counts).
3. 3–5 lines describing behavior added.
4. Note anything skipped with reason.
5. 1–3 bullets on risks/limitations (e.g., Cursor absent, huge logs truncated).

## Project summary update

Record under workflow/operational notes: triage script path, outputs `.ai-loop/failure_triage.md`, advisory-only, recommended manual step before Claude diagnosis after failures; mention `-IncludeDebug` caution.

## Output hygiene

- Do not duplicate this entire `task.md` into `.ai-loop/implementer_summary.md`.
- Do not write raw multi-session debug dumps into `.ai-loop/_debug/` from this task unless already standard for failures investigation.
- Do not create git commits unless a separate human request explicitly asks.
- Do not write to `docs/archive/**`.

## Important

- Assumption: triage remains **manual** (`.\scripts\triage_failure.ps1 ...`) and is not wired into automated loop scripts in this task.
- Assumption: “recent orchestrator artifacts” means **bounded excerpts** from `.ai-loop` root-level logs/markdown/text plus the always-include durable files; never bulk-include entire `_debug` trees unless `-IncludeDebug`, and even then cap aggressively with explicit truncation markers.
- Architect note: **No default edits to `scripts/run_cursor_agent.ps1`.** Read-only discipline belongs in `templates/failure_triage_prompt.md` and the assembled stdin sections; changing the wrapper adds coupling without enabling new capability.
- Architect note: **Do not add `failure_triage.md` to `SafeAddPaths`** or orchestrator auto-stage lists; it is intentionally gitignored and advisory/transient-to-human workflow.
- Architect note: If total implementation threatens the ~80-line soft budget, implement the smallest useful slice first (script + template + gitignore + installer), then tests/docs in the same PR only if still within budget—otherwise split follow-up task (see Order).

## Order

1
