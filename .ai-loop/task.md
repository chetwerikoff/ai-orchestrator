# C01b — Auto-invoke build_repo_map.ps1 at loop start

**Project:** `ai-git-orchestrator`
**CWD when running:** `C:\Users\che\Documents\Projects\ai-git-orchestrator`
**How to run:**
```powershell
# Paste everything below "---" into .ai-loop\task.md, then:
powershell -ExecutionPolicy Bypass -File .\scripts\ai_loop_task_first.ps1 -NoPush
```
**Prerequisites:** C01 complete and merged (`scripts/build_repo_map.ps1` exists).

---

## Project context

`scripts/build_repo_map.ps1` was added in C01 but is never called automatically.
The implementer receives `.ai-loop/repo_map.md` in `SafeAddPaths` and AGENTS.md
tells it to read the map on the first iteration — but the file may be absent or
stale if the developer hasn't run the script manually.

## Goal

Call `build_repo_map.ps1` automatically at the start of `ai_loop_task_first.ps1`
if the map is absent or older than 1 hour. Non-fatal — a failure must not block
the loop.

## Scope

**Allowed:**
- `scripts/ai_loop_task_first.ps1` — add stale-check + auto-invoke before Step 1

**Not allowed:**
- No changes to `ai_loop_auto.ps1` or `continue_ai_loop.ps1`
- No changes to `build_repo_map.ps1` itself
- No new parameters or flags
- No changes to tests (existing `test_build_repo_map_is_deterministic` is sufficient)

## Files in scope

- `scripts/ai_loop_task_first.ps1`

## Files out of scope

- `scripts/ai_loop_auto.ps1`
- `scripts/continue_ai_loop.ps1`
- `scripts/build_repo_map.ps1`
- `tests/`

## Required behavior

Add the following block near the top of `ai_loop_task_first.ps1`, after
parameters are parsed and before `Write-Section "STEP 1"`:

```powershell
# Auto-refresh repo map if absent or stale (>1 h).
$repoMapPath = Join-Path $PSScriptRoot "..\. ai-loop\repo_map.md"
$repoMapScript = Join-Path $PSScriptRoot "build_repo_map.ps1"
$needsRefresh = (-not (Test-Path $repoMapPath)) -or `
    ((Get-Date) - (Get-Item $repoMapPath).LastWriteTime).TotalHours -gt 1
if ($needsRefresh -and (Test-Path $repoMapScript)) {
    try {
        & $repoMapScript
    } catch {
        Write-Warning "build_repo_map.ps1 failed (non-fatal): $_"
    }
}
```

Rules:
- Non-fatal: wrap in `try/catch`; on error `Write-Warning` and continue.
- Only runs when `build_repo_map.ps1` exists (safe on fresh clones without C01).
- Path to `repo_map.md` must be resolved relative to `$PSScriptRoot` (i.e.
  `../. ai-loop/repo_map.md` from `scripts/`).

## Tests

No new tests required — `test_build_repo_map_is_deterministic` already covers
the script. Optionally add a static assertion:

```python
def test_task_first_auto_invokes_repo_map() -> None:
    text = Path("scripts/ai_loop_task_first.ps1").read_text(encoding="utf-8")
    assert "build_repo_map.ps1" in text
    assert "TotalHours" in text
```

## Verification

1. `python -m pytest -q` — all tests pass, no regressions.
2. `scripts/ai_loop_task_first.ps1` contains `build_repo_map.ps1` and `TotalHours`.
3. Delete `.ai-loop/repo_map.md`, run `ai_loop_task_first.ps1 -NoPush` on a
   trivial task — map is regenerated before Step 1 output appears.

## Cursor summary requirements

- `## Changed files` — `scripts/ai_loop_task_first.ps1` only
- `## Tests` — exact pytest result line
- `## Implementation` — 2–3 bullets
- `## Remaining risks` — at most 2 bullets

## Project summary update

Update `project_summary.md`: note that `ai_loop_task_first.ps1` auto-refreshes
`repo_map.md` at start if absent or stale (> 1 h).

## Important

- If `build_repo_map.ps1` does not exist (e.g. pre-C01 install), the block must
  silently skip — do not throw.
- Do not add a `-SkipRepoMap` flag. If the developer needs to skip, they can
  pre-create the file.
