# C05 — Wrap-up session + failures log

**Project:** `ai-git-orchestrator`
**CWD when running:** `C:\Users\che\Documents\Projects\ai-git-orchestrator`
**How to run:**
```powershell
# Paste everything below "---" into .ai-loop\task.md, then:
powershell -ExecutionPolicy Bypass -File .\scripts\ai_loop_task_first.ps1 -NoPush
```
**Prerequisites:** C03 complete and merged (drivers have stable prompt pipeline).
**Decision record:** DD-023 — see `docs/decisions.md`.

## Files in scope

- `scripts/**`
- `tests/**`
- `.ai-loop/failures.md`, `.ai-loop/archive/rolls/**`
- `AGENTS.md`
- `docs/decisions.md`, `docs/safety.md`

## Files out of scope

- `docs/archive/**`
- `tasks/context_audit/**`

---

## Project context

`ai-git-orchestrator` drives an AI coding loop via three PowerShell scripts:
`scripts/ai_loop_auto.ps1`, `scripts/ai_loop_task_first.ps1`, and
`scripts/ai_loop_task_continue.ps1`. After a successful loop run (`final_status
PASS`) there is currently no mechanism to capture what the session did or what
failed along the way. Failed test output accumulates in `.ai-loop/test_output.txt`
but is never summarised across sessions.

This task adds two opt-in capabilities:

1. **Wrap-up** (`-WithWrapUp`): after PASS, runs
   `scripts/wrap_up_session.ps1` which writes a human-readable session draft to
   `.ai-loop/_debug/session_draft.md`. Non-fatal — a wrap-up failure does not
   change the exit code.

2. **Failures log** (`failures.md`): `scripts/promote_session.ps1` (run manually
   by the developer) appends the draft to `.ai-loop/failures.md`, moves it to
   `archive/rolls/YYYY-MM-DD_HH-MM.md`, and rotates `failures.md` when it
   exceeds 200 lines (overflow → `archive/failures/<date>.md`).

The goal is cross-session memory for recurring failure patterns without adding
external services, vector DBs, or a classifier.

## Goal

1. Add `-WithWrapUp` switch to all three driver scripts.
2. Create `scripts/wrap_up_session.ps1` — called post-PASS inside the drivers.
3. Create `scripts/promote_session.ps1` — called manually by the developer to
   persist the draft into `failures.md`.
4. Seed `.ai-loop/failures.md` (empty with header comment).
5. Create `.ai-loop/archive/rolls/.gitkeep` so the directory is tracked.
6. Update `SafeAddPaths` in all 4 locations to include `failures.md`,
   `archive/rolls/`, `_debug/session_draft.md`.
7. Update `AGENTS.md`: add rule "Read `.ai-loop/failures.md` on iteration ≥ 2".
8. Record decision DD-023 in `docs/decisions.md`.

## Scope

**Allowed:**
- `scripts/ai_loop_auto.ps1` — add `-WithWrapUp` switch; call `wrap_up_session.ps1` post-PASS (non-fatal)
- `scripts/ai_loop_task_first.ps1` — same
- `scripts/ai_loop_task_continue.ps1` — same
- `scripts/wrap_up_session.ps1` — new file
- `scripts/promote_session.ps1` — new file
- `.ai-loop/failures.md` — new seed file (header only)
- `.ai-loop/archive/rolls/.gitkeep` — new
- `AGENTS.md` — add failures.md read rule
- `docs/decisions.md` — append DD-023
- `docs/safety.md` — update SafeAddPaths allowlist
- `tests/test_orchestrator_validation.py` — add 2 new tests

**Not allowed:**
- No `.ai-memory/` directory or any files inside it
- No embedding, semantic search, or vector index of any kind
- No external HTTP calls from wrap-up or promote scripts
- No classifier or ML model invocation
- No changes to `.gitignore` beyond what is strictly needed for the new `_debug/` and `archive/` paths (those are already excluded in C04 if run; if C04 was not run yet, add `_debug/` exclusion here)
- No modification of the Codex review prompt or implementer prompt (those are C03 scope)
- Do not make `-WithWrapUp` the default — it must remain opt-in

## Files likely to change

```
scripts/ai_loop_auto.ps1
scripts/ai_loop_task_first.ps1
scripts/ai_loop_task_continue.ps1
scripts/wrap_up_session.ps1          ← new
scripts/promote_session.ps1          ← new
.ai-loop/failures.md                 ← new (seed)
.ai-loop/archive/rolls/.gitkeep      ← new
AGENTS.md
docs/decisions.md
docs/safety.md
tests/test_orchestrator_validation.py
```

## Required behavior

### `scripts/wrap_up_session.ps1`

Called by drivers after PASS when `-WithWrapUp` is set. Must:

1. Read `.ai-loop/test_output.txt` (last pytest run).
2. Read `.ai-loop/implementer_summary.md` (last implementer output).
3. Write `.ai-loop/_debug/session_draft.md` with the following sections:

```markdown
# Session draft — <ISO-8601 datetime>

## Changed files
<list from implementer_summary.md "## Changed files" section, or "(none recorded)">

## Failures observed
<FAILED lines extracted from test_output.txt, or "(none)">

## Notes
(fill in manually before promoting)
```

4. Must not throw a terminating error. Wrap the entire body in `try/catch`; on
   error, `Write-Warning "wrap_up_session: $_"` and exit 0.
5. Must not read or write any file outside `.ai-loop/`. Do not read the task
   spec, source files, or git history.

### `scripts/promote_session.ps1`

Run manually by the developer. Must:

1. Read `.ai-loop/_debug/session_draft.md`. If it does not exist, print a
   warning and exit 0.
2. Append the draft content to `.ai-loop/failures.md` with a `---` separator.
3. Copy the draft to `.ai-loop/archive/rolls/<YYYY-MM-DD_HH-MM>.md`.
4. Delete `.ai-loop/_debug/session_draft.md`.
5. If `.ai-loop/failures.md` exceeds 200 lines after append, move content
   beyond line 200 to `.ai-loop/archive/failures/<YYYY-MM-DD>.md` and truncate
   `failures.md` to the header + most-recent 200 lines.
6. Print a summary of what was done (files written, line counts).

### Driver changes (all three scripts)

Add `-WithWrapUp` as an optional switch parameter (default `$false`). After the
block that sets `final_status = PASS`, add:

```powershell
if ($WithWrapUp) {
    & "$PSScriptRoot\wrap_up_session.ps1"
}
```

The call must be placed **after** the final status is determined and **before**
the script exits. A failure in `wrap_up_session.ps1` must not change the exit
code of the driver.

### SafeAddPaths update

The explicit path allowlist exists in 4 locations:
- `scripts/ai_loop_auto.ps1`
- `scripts/ai_loop_task_first.ps1`
- `scripts/ai_loop_task_continue.ps1`
- `docs/safety.md`

Add to all four:
```
.ai-loop/failures.md
.ai-loop/archive/rolls/
.ai-loop/_debug/session_draft.md
```

### `.ai-loop/failures.md` seed

```markdown
# Failures log
# Appended by scripts/promote_session.ps1 — do not edit manually.
# Rotate: >200 lines overflow to archive/failures/<date>.md
```

### AGENTS.md rule

Add to AGENTS.md (in the "What to read" or equivalent section):

> On iteration ≥ 2, read `.ai-loop/failures.md` for recurring failure patterns
> before writing the first fix attempt.

### DD-023 in `docs/decisions.md`

Append:

```
## DD-023 — Opt-in wrap-up and failures log (C05)

Date: <today>
Status: accepted

Context: No cross-session memory for recurring failures existed. Options
considered: .ai-memory/ directory (rejected — adds stale-index risk and
maintenance burden), semantic search (rejected — overkill for <100k LOC),
external service (rejected — adds dependency).

Decision: Minimal two-script approach. wrap_up_session.ps1 drafts session
output post-PASS. promote_session.ps1 (manual) persists to failures.md.
200-line rolling cap with archive rotation. No classifier, no external calls.

Consequences: Developer must run promote_session.ps1 manually to persist.
The draft in _debug/ is intentionally ephemeral.
```

## Tests

Add to `tests/test_orchestrator_validation.py`:

**Test 1 — wrap_up_session script exists and has required structure:**
```python
def test_wrap_up_session_script_exists():
    script = Path("scripts/wrap_up_session.ps1")
    assert script.exists(), "scripts/wrap_up_session.ps1 must exist"
    content = script.read_text(encoding="utf-8")
    assert "session_draft.md" in content
    assert "test_output.txt" in content
    assert "implementer_summary.md" in content
    assert "try" in content.lower(), "must have try/catch for non-fatal behavior"
```

**Test 2 — promote_session script exists and references expected paths:**
```python
def test_promote_session_script_exists():
    script = Path("scripts/promote_session.ps1")
    assert script.exists(), "scripts/promote_session.ps1 must exist"
    content = script.read_text(encoding="utf-8")
    assert "failures.md" in content
    assert "archive/rolls" in content
    assert "session_draft.md" in content
```

Both tests must pass alongside the existing suite (baseline + 2 new, no regressions).

## Verification

After the task completes, verify manually:

1. `python -m pytest -q` — all tests pass, +2 new tests green.
2. `scripts/wrap_up_session.ps1` exists, contains `try/catch`, references
   `session_draft.md`, `test_output.txt`, `implementer_summary.md`.
3. `scripts/promote_session.ps1` exists, references `failures.md`,
   `archive/rolls`, `session_draft.md`.
4. All three driver scripts contain `-WithWrapUp` parameter.
5. `.ai-loop/failures.md` exists with the 3-line header.
6. `.ai-loop/archive/rolls/.gitkeep` exists.
7. SafeAddPaths in all 4 locations includes `failures.md`, `archive/rolls/`,
   `_debug/session_draft.md`.
8. `AGENTS.md` contains a rule referencing `failures.md` and "iteration ≥ 2".
9. `docs/decisions.md` contains `DD-023`.

## Cursor summary requirements

The implementer must produce `.ai-loop/implementer_summary.md` with:
- `## Changed files` — list every file modified or created
- `## Tests` — exact pytest result line (e.g. "68 passed")
- `## Implementation` — 3–5 bullet points describing what was done
- `## Remaining risks` — at most 3 bullets

## Project summary update

Update `project_summary.md` (in the target project's `.ai-loop/` directory) to
mention:
- `-WithWrapUp` flag on all three drivers
- `failures.md` as cross-session memory artifact
- `promote_session.ps1` as the manual persist step

## Important

- `wrap_up_session.ps1` must be **non-fatal**: a crash in it must not break
  a passing loop run.
- Do **not** create `.ai-memory/` or any subdirectory of it.
- Do **not** add automated promotion (cron, post-commit hook, etc.). Promotion
  is always a manual step.
- `failures.md` rotation must be deterministic — no random or hash-based names.
- If C04 was already run, `_debug/` is already in `.gitignore`; do not add a
  duplicate entry. If C04 was not run, add `.ai-loop/_debug/` to `.gitignore`.
