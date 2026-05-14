# C06 — Fix scout role framing + short-output warning

**Project:** `ai-orchestrator`
**CWD when running:** `C:\Users\che\Documents\Projects\ai-orchestrator`
**How to run:**
```powershell
# Paste everything below "---" into .ai-loop\task.md, then:
powershell -ExecutionPolicy Bypass -File .\scripts\ai_loop_task_first.ps1 -NoPush
```
**Bug report:** `tasks/scout_bug_report.md`
**Fixes:** Bug 2 (high) + Bug 3 (low). Bug 1 already resolved.

---

## Files in scope

- `scripts/run_opencode_scout.ps1`
- `scripts/run_scout_pass.ps1`
- `scripts/install_into_project.ps1`
- `tests/test_orchestrator_validation.py`
- `.ai-loop/implementer_summary.md`
- `.ai-loop/project_summary.md`

## Files out of scope

- `scripts/run_opencode_agent.ps1`
- `scripts/ai_loop_task_first.ps1`
- `scripts/ai_loop_auto.ps1`
- `docs/`
- `templates/`
- `AGENTS.md`
- `tasks/**`
- `.ai-loop/_debug/**`

## Project context

`scripts/run_scout_pass.ps1` runs a scout pre-pass before the implementer when
`-WithScout` is set. It receives `-CommandName $CursorCommand` from
`ai_loop_task_first.ps1` (line 350). When the user runs with
`-CursorCommand .\scripts\run_opencode_agent.ps1`, that wrapper is used for the
scout session.

`run_opencode_agent.ps1` hardcodes its main OpenCode message as:
> "You are the IMPLEMENTER. Read the attached file completely and execute every
> instruction in it. Do not summarise or review — implement directly."

The scout prompt is passed only as a file attachment (`-f $tempFile`). The model
receives contradictory role instructions: IMPLEMENTER from the wrapper, SCOUT from
the attachment. Result: session exits in ~1 second with no tool calls, `scout.json`
is never created.

Additionally, when the session exits silently, `run_scout_pass.ps1` only warns if
output is empty — it does not detect a suspiciously short output (e.g. 50 bytes)
that indicates a startup failure rather than a real response.

## Goal

1. Create `scripts/run_opencode_scout.ps1` — minimal clone of
   `run_opencode_agent.ps1` with SCOUT role message.
2. Update `scripts/run_scout_pass.ps1`:
   - Auto-substitute `run_opencode_scout.ps1` when `$CommandName` resolves to
     `run_opencode_agent.ps1`.
   - Add short-output guard (< 200 bytes → warn + exit 0).
3. Update `scripts/install_into_project.ps1` to copy `run_opencode_scout.ps1`
   into the target project's `scripts/`.
4. Add 2 tests.

## Scope

**Files in scope:**
- `scripts/run_opencode_scout.ps1` — new file
- `scripts/run_scout_pass.ps1` — auto-substitute logic + short-output guard
- `scripts/install_into_project.ps1` — add copy of `run_opencode_scout.ps1`
- `tests/test_orchestrator_validation.py` — 2 new tests

**Files out of scope:**
- `scripts/run_opencode_agent.ps1` — must not be modified
- `scripts/ai_loop_task_first.ps1` — no changes needed; already passes `-CommandName`
- `scripts/ai_loop_auto.ps1`
- `docs/`, `templates/`, `AGENTS.md`

## Required behavior

### `scripts/run_opencode_scout.ps1`

Minimal clone of `run_opencode_agent.ps1`. Change only the main message line:

```powershell
# run_opencode_scout.ps1 — scout role wrapper for OpenCode
# Change only this line vs run_opencode_agent.ps1:
$message = "You are the SCOUT. Read the attached instructions and output only the requested JSON block. Do NOT edit any file."
```

All other parameters, flags, and invocation logic must be identical to
`run_opencode_agent.ps1`.

### `scripts/run_scout_pass.ps1` — auto-substitute logic

After `$CommandName` is resolved and before the scout invocation, add:

```powershell
# Auto-swap opencode_agent → opencode_scout to avoid IMPLEMENTER role conflict.
$resolvedCommand = $CommandName
if ($CommandName -match 'run_opencode_agent') {
    $scoutWrapper = Join-Path $PSScriptRoot "run_opencode_scout.ps1"
    if (Test-Path -LiteralPath $scoutWrapper) {
        $resolvedCommand = $scoutWrapper
    } else {
        Write-ScoutWarning "run_opencode_scout.ps1 not found beside run_scout_pass.ps1; using original command (role framing may conflict)."
    }
}
```

Replace `$CommandName` with `$resolvedCommand` in the invocation line (line 50).

### `scripts/run_scout_pass.ps1` — short-output guard (Bug 3)

After reading `$raw` and checking for empty, add before the JSON regex:

```powershell
if ($raw.Length -lt 200) {
    Write-ScoutWarning "scout output is suspiciously short ($($raw.Length) bytes) — likely a session startup failure. See $outputPath."
    exit 0
}
```

### `scripts/install_into_project.ps1`

Add one line alongside the existing `run_opencode_agent.ps1` copy:

```powershell
Copy-Item (Join-Path $Root "scripts\run_opencode_scout.ps1") (Join-Path $TargetScripts "run_opencode_scout.ps1") -Force
```

## Tests

Add to `tests/test_orchestrator_validation.py`:

**Test 1 — `run_opencode_scout.ps1` exists and has SCOUT message:**
```python
def test_run_opencode_scout_has_scout_role_message() -> None:
    script = Path("scripts/run_opencode_scout.ps1")
    assert script.exists(), "scripts/run_opencode_scout.ps1 must exist"
    content = script.read_text(encoding="utf-8")
    assert "SCOUT" in content, "must contain SCOUT role message"
    assert "IMPLEMENTER" not in content, "must not reuse IMPLEMENTER message"
```

**Test 2 — `run_scout_pass.ps1` contains auto-substitute and short-output guard:**
```python
def test_run_scout_pass_has_auto_substitute_and_short_output_guard() -> None:
    content = Path("scripts/run_scout_pass.ps1").read_text(encoding="utf-8")
    assert "run_opencode_scout" in content, "missing auto-substitute for opencode_agent"
    assert "200" in content, "missing short-output guard (< 200 bytes)"
```

Both tests must pass alongside the existing suite (baseline + 2 new, no regressions).

## Verification

1. `python -m pytest -q` — all tests pass, +2 new green.
2. `scripts/run_opencode_scout.ps1` exists, contains `SCOUT`, does not contain
   `IMPLEMENTER`.
3. `scripts/run_scout_pass.ps1` contains `run_opencode_scout` (auto-substitute)
   and `200` (short-output guard).
4. `scripts/install_into_project.ps1` copies `run_opencode_scout.ps1`.

## Cursor summary requirements

- `## Changed files` — list every file modified or created
- `## Tests` — exact pytest result line
- `## Implementation` — 3–5 bullets
- `## Remaining risks` — at most 2 bullets

## Project summary update

Update `project_summary.md` to mention:
- `scripts/run_opencode_scout.ps1` as the OpenCode scout role wrapper
- Auto-substitute logic in `run_scout_pass.ps1`

## Important

- `run_opencode_agent.ps1` must NOT be modified — it is the production implementer
  wrapper and is used in all non-scout passes.
- The auto-substitute must only trigger on `run_opencode_agent` — must not affect
  `run_cursor_agent.ps1` or other wrappers.
- If `run_opencode_scout.ps1` does not exist at substitute time, fall back to the
  original `$CommandName` with a `Write-ScoutWarning` (non-fatal).
