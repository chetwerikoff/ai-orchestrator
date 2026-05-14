# Scout pass bug report

**Project:** h2n-range-extractor  
**Date:** 2026-05-14  
**Observed by:** Senior architect review during loop run with `qwen3-6-35b-a3b`

---

## Bug 1: `build_repo_map.ps1` not transferred to project

### Symptom
`repo_map.md` never created. Scout logs `File not found: .ai-loop/repo_map.md` and falls back
to exploring the codebase itself — causing context overflow (142K > 131K tokens) on first run,
or violating the `read-only` scout contract on subsequent runs.

### Root cause
`ai_loop_task_first.ps1` (lines 321–332) already contains auto-refresh logic:

```powershell
$repoMapScript = Join-Path $PSScriptRoot "build_repo_map.ps1"
if ($needsRefresh -and (Test-Path $repoMapScript)) {
    & $repoMapScript
}
```

The guard `(Test-Path $repoMapScript)` silently skips generation when the file is absent —
**no warning, no error**. `build_repo_map.ps1` exists in the orchestrator template but was
never copied into this project's `scripts/` directory.

### Fix
Copy `build_repo_map.ps1` from the orchestrator template into `scripts/`. No code changes needed.

---

## Bug 2: Scout uses IMPLEMENTER wrapper — wrong role framing

### Symptom
Scout session exits in ~1 second with no tool calls and no JSON output. `scout.json` is never
created. Orchestrator proceeds without `relevant_files`, negating the scout pass entirely.

### Root cause
`run_scout_pass.ps1` (line 50) pipes the scout prompt to `$CommandName`:

```powershell
$scoutPrompt | & $CommandName @agentArgs *> $outputPath
```

`$CommandName` defaults to `run_opencode_agent.ps1`, which hardcodes the main OpenCode message as:

```powershell
$message = "You are the IMPLEMENTER. Read the attached file completely and execute every instruction in it. Do not summarise or review - implement directly."
```

The scout prompt is passed only as a **file attachment** (`-f $tempFile`). The model therefore
receives two contradictory role instructions:

| Source | Content |
|---|---|
| Main message | "You are the IMPLEMENTER, execute directly" |
| Attachment | "You are the SCOUT, do NOT edit, output only JSON" |

With `repo_map.md` now present the model attempts to output the JSON block immediately, but the
session exits before the output is captured — or the model silently defers due to role confusion.

In earlier runs (without `repo_map.md`) the model defaulted to exploration tool calls, which
produced visible output and partially masked the bug.

### Fix options

**Option A — dedicated scout wrapper (recommended)**  
Create `scripts/run_opencode_scout.ps1` as a minimal clone of `run_opencode_agent.ps1` with the
message corrected:

```powershell
# run_opencode_scout.ps1 — change only this line:
$message = "You are the SCOUT. Read the attached instructions and output only the requested JSON block. Do NOT edit any file."
```

Update `run_scout_pass.ps1` to use it by default:

```powershell
# run_scout_pass.ps1 — replace default CommandName logic:
$defaultScoutCommand = Join-Path $PSScriptRoot "run_opencode_scout.ps1"
if ([string]::IsNullOrWhiteSpace($CommandName)) { $CommandName = $defaultScoutCommand }
```

**Option B — call OpenCode directly from run_scout_pass.ps1**  
Remove the wrapper dependency. `run_scout_pass.ps1` already knows the project root, model, and
prompt. Call `opencode run` inline:

```powershell
$tempFile = [System.IO.Path]::GetTempFileName() + ".md"
[System.IO.File]::WriteAllText($tempFile, $scoutPrompt, [System.Text.Encoding]::UTF8)
opencode run "Output only the JSON block described in the attached file." -f $tempFile --model $Model
Remove-Item $tempFile -ErrorAction SilentlyContinue
```

This eliminates the role-framing mismatch entirely and keeps the scout self-contained.

---

## Bug 3: No warning when scout output is suspiciously short

### Symptom
When the scout exits silently (Bug 2), `run_scout_pass.ps1` only warns if `scout.json` is
absent — but gives no indication of *why*. The orchestrator continues as if the scout never ran.

### Fix
Add a size/content guard before the JSON regex in `run_scout_pass.ps1`:

```powershell
if ($raw.Length -lt 200) {
    Write-ScoutWarning "scout output is suspiciously short ($($raw.Length) bytes) — likely a session startup failure. See $outputPath."
    exit 0
}
```

---

## Summary

| # | Bug | Severity | Fix effort |
|---|---|---|---|
| 1 | `build_repo_map.ps1` missing in project | Medium | Copy one file |
| 2 | Scout uses IMPLEMENTER role framing | High | New 20-line wrapper or inline call |
| 3 | No warning on short scout output | Low | 3-line guard in run_scout_pass.ps1 |

Bug 1 is already fixed in this session (file is now present and `repo_map.md` generates correctly).  
Bugs 2 and 3 require changes in the orchestrator template.
