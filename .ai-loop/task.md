# Task: Quote task name in START/DONE banners

## Project context

- `AGENTS.md`
- `.ai-loop/project_summary.md`

## Goal

The completion banners in `scripts/ai_loop_task_first.ps1` currently emit:

```
AI LOOP TASK: Fix reviewer exit-code and em-dash encoding bugs START
```

They must emit:

```
AI LOOP TASK: "Fix reviewer exit-code and em-dash encoding bugs" START
```

Add double quotes around `$taskName` in both banner calls.

## Scope

Allowed:
- Edit the two `Write-Section` banner calls in `scripts/ai_loop_task_first.ps1`

Not allowed:
- Changing any other line in any file

## Files in scope

- `scripts/ai_loop_task_first.ps1`

## Files out of scope

- Everything else

## Required behavior

1. Find the line that calls `Write-Section` with the START banner. It currently looks like one of:
   ```powershell
   Write-Section "AI LOOP TASK: $taskName START"
   ```
   Change it to:
   ```powershell
   Write-Section "AI LOOP TASK: `"$taskName`" START"
   ```
   (Use PowerShell backtick-escaped quotes inside the double-quoted string.)

2. Find the line that calls `Write-Section` with the DONE banner and apply the same change:
   ```powershell
   Write-Section "AI LOOP TASK: `"$taskName`" DONE"
   ```

3. The fallback path (when `$taskName` is empty or blank) must remain unchanged — emit the original text without quotes.

4. Do not modify `Write-Section` itself.

## Verification

```powershell
powershell -NoProfile -Command "[void][System.Management.Automation.Language.Parser]::ParseFile('scripts\ai_loop_task_first.ps1', [ref]`$null, [ref]`$null)"
python -m pytest -q
```

## Implementer summary requirements

1. Show the exact before/after lines changed.
2. Test count.

## Output hygiene

- Do not commit.
- Do not write to `.ai-loop/_debug/`.
