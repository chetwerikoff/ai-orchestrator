# Task: completion-banner

## Project context

- `AGENTS.md`
- `.ai-loop/task.md`
- `.ai-loop/project_summary.md`

## Goal

Replace the `Write-Section "AI LOOP TASK-FIRST START"` call at the top of the main body and the `Write-Section "AI LOOP TASK-FIRST DONE"` call at the very end of `scripts/ai_loop_task_first.ps1` with versions that include the task short name parsed from the first line of `.ai-loop/task.md`. If the name cannot be read, emit the banner without it. No other behaviour, exit codes, or scripts change.

Note: `Write-Section` (defined inside the script) already emits the three-line `==============================` wrapper. The only change is the string passed to it.

## Scope

Allowed:
- Edit `scripts/ai_loop_task_first.ps1` to emit the banner
- Add one test to `tests/test_orchestrator_validation.py` verifying the banner separator string exists in the script

Not allowed:
- Changing exit codes or loop flow
- Adding new files
- Touching `ai_loop_auto.ps1`, `continue_ai_loop.ps1`, or any other script
- Modifying `task.md` content (only reading it)

## Files in scope

- `scripts/ai_loop_task_first.ps1`
- `tests/test_orchestrator_validation.py`

## Files out of scope

- `docs/archive/**`
- `.ai-loop/_debug/**`
- `ai_loop.py`
- All other scripts not listed above

## Required behavior

1. Near the top of the main script body (just before or just after the `Assert-FileExists` calls, around line 347), read the first line of `$TaskPath`. If it matches `^#\s*Task:\s*(.+)`, capture the trimmed task name into `$taskName`; otherwise set `$taskName = ""`. This read must be silent/non-fatal — use `try/catch` so a missing file does not abort the script.

2. Replace `Write-Section "AI LOOP TASK-FIRST START"` (currently line 346) with:
   - If `$taskName` is non-empty: `Write-Section "AI LOOP TASK: $taskName START"`
   - Fallback (name empty): `Write-Section "AI LOOP TASK-FIRST START"` (unchanged)

3. Replace `Write-Section "AI LOOP TASK-FIRST DONE"` (currently the last line) with:
   - If `$taskName` is non-empty: `Write-Section "AI LOOP TASK: $taskName DONE"`
   - Fallback: `Write-Section "AI LOOP TASK-FIRST DONE"` (unchanged)

4. Because both banners need `$taskName`, extract it once before the first `Write-Section` call and reuse the same variable at the end.

5. The `Write-Section` function itself must not be modified. No colour changes. No other `Write-Section` or `Write-Host` calls change.

## Tests

Add two tests in `tests/test_orchestrator_validation.py`:

```python
def test_completion_banner_separator_present():
    """ai_loop_task_first.ps1 must contain the banner separator string."""
    content = Path("scripts/ai_loop_task_first.ps1").read_text(encoding="utf-8")
    assert "==============================" in content, \
        "completion banner separator missing from ai_loop_task_first.ps1"

def test_task_name_banners_present():
    """Both START and DONE banners must reference the task name variable."""
    content = Path("scripts/ai_loop_task_first.ps1").read_text(encoding="utf-8")
    assert "AI LOOP TASK:" in content and "START" in content, \
        "START banner with task name missing from ai_loop_task_first.ps1"
    assert "AI LOOP TASK:" in content and "DONE" in content, \
        "DONE banner with task name missing from ai_loop_task_first.ps1"
```

Run: `python -m pytest -q`

## Verification

```powershell
# 1. PowerShell parse check
powershell -NoProfile -Command "[void][System.Management.Automation.Language.Parser]::ParseFile('scripts\ai_loop_task_first.ps1', [ref]`$null, [ref]`$null)"

# 2. Confirm banner separator is present
powershell -NoProfile -Command "if (!(Select-String -Path 'scripts\ai_loop_task_first.ps1' -Pattern '={10}')) { exit 1 }"

# 3. Confirm START banner with task name is present
powershell -NoProfile -Command "if (!(Select-String -Path 'scripts\ai_loop_task_first.ps1' -Pattern 'AI LOOP TASK:.*START')) { exit 1 }"

# 4. Confirm DONE banner with task name is present
powershell -NoProfile -Command "if (!(Select-String -Path 'scripts\ai_loop_task_first.ps1' -Pattern 'AI LOOP TASK:.*DONE')) { exit 1 }"

# 5. Full test suite
python -m pytest -q
```

## Implementer summary requirements

1. Which lines in `ai_loop_task_first.ps1` were changed and what they now contain (show before/after).
2. How the task-name extraction was written in PowerShell (the regex and try/catch structure).
3. Test count before/after.
4. Edge cases handled: file missing, regex no-match (confirm fallback emits original string).
5. Remaining risks (if any).

## Project summary update

No update needed.

## Output hygiene

- Do not duplicate task content into the implementer summary.
- Do not write to `.ai-loop/_debug/`.
- Do not commit.
- Do not write to `docs/archive/`.

## Important

- The task name extraction reads only the first line of `$TaskPath`; no full parse is needed. Failure to read must be silent (non-fatal) — the banner still emits without the name (original text).
- `ai_loop_task_first.ps1` already reads `task.md` in `Get-TaskScopeBlocks` and `Invoke-ImplementerImplementation` using `Get-Content -LiteralPath ... -Raw -Encoding UTF8`. The implementer should use the same one-liner (`(Get-Content -LiteralPath $TaskPath -TotalCount 1 -Encoding UTF8 -ErrorAction SilentlyContinue)`) for the first-line read rather than introducing a new helper function.
- Both `Write-Section` calls must use the same `$taskName` variable extracted once at the top of the main body, not two separate reads.
- Architect note: fallback is the original banner text (`AI LOOP TASK-FIRST START` / `AI LOOP TASK-FIRST DONE`), not a placeholder like `UNKNOWN TASK`.
- Architect note: the format `AI LOOP TASK: <name> START` / `AI LOOP TASK: <name> DONE` keeps output grep-friendly and unambiguous in CI logs.
