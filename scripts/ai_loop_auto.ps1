param(
    [int]$MaxIterations = 10,
    [string]$CommitMessage = "AI loop auto update",
    [switch]$Resume,
    [switch]$NoPush,
    [string]$TestCommand = "python -m pytest",
    [string]$PostFixCommand = "",
    [string]$SafeAddPaths = "src/,tests/,README.md,AGENTS.md,scripts/,docs/,templates/,ai_loop.py,pytest.ini,.gitignore,requirements.txt,pyproject.toml,setup.cfg,.ai-loop/task.md,.ai-loop/implementer_summary.md,.ai-loop/project_summary.md,.ai-loop/repo_map.md,.ai-loop/failures.md,.ai-loop/archive/rolls/,.ai-loop/_debug/session_draft.md",
    [string]$CursorCommand = "",
    [string]$CursorModel = "",
    [switch]$WithWrapUp
)

$ErrorActionPreference = "Continue"

$ProjectRoot = (Resolve-Path ".").Path
$AiLoop = Join-Path $ProjectRoot ".ai-loop"
$Tmp = Join-Path $ProjectRoot ".tmp"

New-Item -ItemType Directory -Force -Path $AiLoop | Out-Null
New-Item -ItemType Directory -Force -Path $Tmp | Out-Null

function Get-ImplementerStatePath {
    param([string]$AiLoopRoot)
    return (Join-Path $AiLoopRoot "implementer.json")
}

function Read-ImplementerStateObject {
    param([string]$JsonPath)
    if (-not (Test-Path -LiteralPath $JsonPath)) {
        return $null
    }
    try {
        $raw = Get-Content -LiteralPath $JsonPath -Raw -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace($raw)) {
            Write-Host "WARNING: Implementer state file is empty: $JsonPath - ignoring." -ForegroundColor Yellow
            return $null
        }
        return ($raw | ConvertFrom-Json)
    }
    catch {
        Write-Host "WARNING: Invalid implementer state JSON at $JsonPath - ignoring. $_" -ForegroundColor Yellow
        return $null
    }
}

function Normalize-ImplementerStateFields {
    param($StateObj)
    if (-not $StateObj) { return $null }
    $names = @($StateObj.PSObject.Properties.Name)
    $cmd = ""
    if ($names -contains "implementer_command") { $cmd = [string]$StateObj.implementer_command }
    $model = ""
    if ($names -contains "implementer_model") { $model = [string]$StateObj.implementer_model }
    return @{ Command = $cmd.Trim(); Model = $model.Trim() }
}

function Test-ImplementerCommandResolvable {
    param(
        [string]$Raw,
        [string]$ProjectRoot
    )
    if ([string]::IsNullOrWhiteSpace($Raw)) { return $false }
    $t = $Raw.Trim()
    if ([System.IO.Path]::IsPathRooted($t)) {
        return (Test-Path -LiteralPath $t)
    }
    $rel = $t -replace '^\.(\\|/)', ''
    $underRoot = Join-Path $ProjectRoot $rel
    if (Test-Path -LiteralPath $underRoot) {
        return $true
    }
    if (Test-Path -LiteralPath $t) {
        return $true
    }
    if (Get-Command -Name $t -ErrorAction SilentlyContinue) {
        return $true
    }
    return $false
}

function Save-ImplementerState {
    param(
        [string]$AiLoopRoot,
        [string]$Command,
        [string]$Model,
        [string]$Source
    )
    $path = Get-ImplementerStatePath -AiLoopRoot $AiLoopRoot
    $m = if ($null -eq $Model) { "" } else { [string]$Model }
    $ordered = [ordered]@{
        schema_version        = 1
        implementer_command   = $Command
        implementer_model     = $m
        selected_at           = (Get-Date).ToUniversalTime().ToString("o")
        source                = $Source
    }
    $json = ($ordered | ConvertTo-Json -Depth 6)
    $enc = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($path, $json + "`n", $enc)
}

function Apply-ResumeImplementerState {
    param(
        [string]$ProjectRoot,
        [string]$AiLoopRoot,
        [bool]$IsResume,
        $BoundParameters
    )
    if (-not $IsResume) {
        return
    }
    # Explicit -CursorCommand wins entirely: do not read implementer.json, merge a persisted model,
    # or warn about missing state when the operator is not using persisted command selection.
    if ($BoundParameters.ContainsKey("CursorCommand")) {
        return
    }
    $jsonPath = Get-ImplementerStatePath -AiLoopRoot $AiLoopRoot
    if (-not (Test-Path -LiteralPath $jsonPath)) {
        Write-Host "WARNING: Implementer state not found at $jsonPath - resume uses the default Cursor implementer wrapper; persisted model will not be applied." -ForegroundColor Yellow
        return
    }
    $state = Read-ImplementerStateObject -JsonPath $jsonPath
    $norm = Normalize-ImplementerStateFields -StateObj $state
    $persistedCommandRejected = $false

    if ($norm -and -not [string]::IsNullOrWhiteSpace($norm.Command)) {
        if (Test-ImplementerCommandResolvable -Raw $norm.Command -ProjectRoot $ProjectRoot) {
            $script:CursorCommand = $norm.Command
        }
        else {
            Write-Host "WARNING: Persisted implementer command is not reachable as a path and is not discoverable via Get-Command: $($norm.Command). Falling back to the default Cursor wrapper; persisted model will not be applied." -ForegroundColor Yellow
            $persistedCommandRejected = $true
        }
    }
    elseif ($state) {
        Write-Host "WARNING: Implementer state at $jsonPath has no non-empty command - using default Cursor wrapper; persisted model will not be applied." -ForegroundColor Yellow
        $persistedCommandRejected = $true
    }

    if (-not $BoundParameters.ContainsKey("CursorModel") -and -not $persistedCommandRejected) {
        if ($norm -and -not [string]::IsNullOrWhiteSpace($norm.Model)) {
            $script:CursorModel = $norm.Model
        }
    }
}

$script:defaultImplementerWrapper = Join-Path $PSScriptRoot "run_cursor_agent.ps1"
Apply-ResumeImplementerState -ProjectRoot $ProjectRoot -AiLoopRoot $AiLoop -IsResume $Resume.IsPresent -BoundParameters $PSBoundParameters

$effectiveImplementerCmd = if (-not [string]::IsNullOrWhiteSpace($CursorCommand)) { $CursorCommand } else { $script:defaultImplementerWrapper }
$effectiveImplementerModel = if ($null -eq $CursorModel) { "" } else { [string]$CursorModel }
Save-ImplementerState -AiLoopRoot $AiLoop -Command $effectiveImplementerCmd -Model $effectiveImplementerModel -Source "ai_loop_auto.ps1"

# Keep pytest/temp files local to avoid Windows Temp PermissionError issues.
$env:TEMP = $Tmp
$env:TMP = $Tmp
$env:PYTEST_DEBUG_TEMPROOT = $Tmp

function Clear-AiLoopRuntimeState {
    # Duplicated from ai_loop_task_first.ps1 (no shared module). When ai_loop_auto.ps1 is spawned
    # from task-first right after the implementer pass, $env:AI_LOOP_CHAIN_FROM_TASK_FIRST skips deleting
    # implementer_result.md so the implementer handoff stays intact.
    $files = @(
        ".ai-loop/codex_review.md",
        ".ai-loop/next_implementer_prompt.md",
        ".ai-loop/test_output.txt",
        ".ai-loop/test_output_before_commit.txt",
        ".ai-loop/test_failures_summary.md",
        ".ai-loop/last_diff.patch",
        ".ai-loop/diff_summary.txt",
        ".ai-loop/final_status.md",
        ".ai-loop/git_status.txt",
        ".ai-loop/post_fix_output.txt",
        ".ai-loop/claude_final_review.md",
        ".ai-loop/implementer_result.md",
        ".ai-loop/_debug/implementer_prompt.md",
        ".ai-loop/_debug/implementer_output.txt",
        ".ai-loop/_debug/implementer_fix_output.txt"
    )
    if ($env:AI_LOOP_CHAIN_FROM_TASK_FIRST -eq "1") {
        $files = $files | Where-Object { $_ -notmatch 'implementer_result\.md' }
    }
    foreach ($rel in $files) {
        Remove-Item (Join-Path $ProjectRoot $rel) -Force -ErrorAction SilentlyContinue
    }
}

function ConvertTo-CrtSafeArg {
    # Workaround for a Windows PowerShell 5.1 native-command quoting bug: when a splatted argv
    # element contains both whitespace and embedded double quotes, PS does not escape the inner
    # quotes correctly, and node-CRT re-splits the argument so tokens like `->` leak out as
    # standalone args (rejected by commander.js as unknown options). Pre-escape per MS CRT rules:
    # double any run of backslashes that immediately precedes a quote, then turn the quote into \".
    param([string]$Value)
    return [regex]::Replace($Value, '(\\*)"', { param($m) ($m.Groups[1].Value * 2) + '\"' })
}

function Write-FinalStatus {
    param([string]$Text)
    $Text | Set-Content (Join-Path $AiLoop "final_status.md") -Encoding UTF8
}

function Ensure-AiLoopFiles {
    $projectSummary = Join-Path $AiLoop "project_summary.md"
    $implementerSummary = Join-Path $AiLoop "implementer_summary.md"
    $taskFile = Join-Path $AiLoop "task.md"
    $summaryStub = "# Implementer summary`n`nNo task has been completed yet."

    if (!(Test-Path $projectSummary)) {
        @"
# Project Summary

## Project purpose

TODO: Describe the purpose of this project.

## Current architecture

TODO: List main modules/components.

## Current pipeline / workflow

TODO: Describe workflow.

## Important design decisions

- TODO

## Known risks / constraints

- TODO

## Current stage

TODO

## Last completed task

TODO

## Next likely steps

1. TODO

## Notes for future AI sessions

- Keep durable project-level context here.
"@ | Set-Content $projectSummary -Encoding UTF8
    }

    if (-not (Test-Path $implementerSummary)) {
        $summaryStub | Set-Content $implementerSummary -Encoding UTF8
    }

    if (!(Test-Path $taskFile)) {
        "# Task: TODO`n`nDescribe the current task." | Set-Content $taskFile -Encoding UTF8
    }
}

function Invoke-CommandToFile {
    param(
        [string]$Command,
        [string]$OutputFile
    )

    Write-Host "Running: $Command"
    powershell -NoProfile -Command $Command *> $OutputFile
    return $LASTEXITCODE
}

function Get-SafeAddPathList {
    if (!$SafeAddPaths) { return @() }
    return $SafeAddPaths.Split(",") | ForEach-Object { $_.Trim() } | Where-Object { $_ }
}

function Add-IntentToAddForReview {
    foreach ($path in Get-SafeAddPathList) {
        if (Test-Path $path) {
            git add -N $path 2>$null
        }
    }
}

function Save-TestAndDiff {
    Ensure-AiLoopFiles

    Write-Host ""
    Write-Host "Running tests..."
    Invoke-CommandToFile $TestCommand (Join-Path $AiLoop "test_output.txt") | Out-Null
    $testExit = $LASTEXITCODE

    Write-Host "Saving git status and diff..."
    git status --short > (Join-Path $AiLoop "git_status.txt")

    Add-IntentToAddForReview
    git diff > (Join-Path $AiLoop "last_diff.patch")
    git diff --stat > (Join-Path $AiLoop "diff_summary.txt")

    if ($testExit -ne 0) {
        Write-Host "Tests failed; generating filtered failures summary..."
        $filterScript = Join-Path $ProjectRoot "scripts\filter_pytest_failures.py"
        if (Test-Path $filterScript) {
            python $filterScript `
                --input  (Join-Path $AiLoop "test_output.txt") `
                --output (Join-Path $AiLoop "test_failures_summary.md")
        }
        # If filter script is missing, skip silently — test_output.txt remains
        # available for the reviewer as fallback.
    }

    return $testExit
}

function Run-PostFixCommand {
    if (!$PostFixCommand) {
        return 0
    }

    Write-Host ""
    Write-Host "Running post-fix command..."
    Invoke-CommandToFile $PostFixCommand (Join-Path $AiLoop "post_fix_output.txt") | Out-Null
    return $LASTEXITCODE
}

function Run-CodexReview {
    Ensure-AiLoopFiles

    $prompt = @'
You are the reviewer in an authenticated development loop.

Read in this priority order (stop reading once verdict is clear):

1. `.ai-loop/task.md` — current task contract
2. `.ai-loop/project_summary.md` — durable project orientation
3. `AGENTS.md` at repo root — working rules
4. `.ai-loop/implementer_summary.md` — implementer's report on the latest iteration
5. `.ai-loop/diff_summary.txt` — short `git diff --stat`; if it reports more than 300 changed lines OR more than 8 changed files, read this before loading large diffs.
6. `.ai-loop/test_failures_summary.md` — filtered failures (**read this before** raw pytest output when present; generated only when pytest fails)
7. `.ai-loop/test_output.txt` — pytest output (the orchestrator already ran tests; use when item 6 is absent or you need full session output)
8. `.ai-loop/last_diff.patch` — full git diff (only when items above are not sufficient)
9. `.ai-loop/git_status.txt` — short porcelain status

Review the latest changes.

Important:
- project_summary.md is durable project context.
- task.md is the current task contract.
- The user explicitly authorized the scope described in .ai-loop/task.md.
- If the implementer deferred the task instead of implementing it, mark FIX_REQUIRED and provide a concrete fix prompt.
- If new files are required by the task, make sure they are present in the diff/status.
- Do not ask for manual steps unless absolutely required.

Check:
1. Was the task completed?
2. Are tests meaningful and passing?
3. Are there Critical or High issues?
4. Is project_summary.md updated when durable project-level context changed?
5. Is it safe to run the final test gate, commit, and push?

## Diff size budget

If `diff_summary.txt` reports more than 300 changed lines OR more than 8 changed files, read `diff_summary.txt` first. Do not load `last_diff.patch` unless a specific finding requires it; if you need to load it, justify briefly in `FINAL_NOTE`.

## Test execution policy

The orchestrator already ran `pytest` before this review; results are in `.ai-loop/test_output.txt` (and, on failure, `.ai-loop/test_failures_summary.md`). Do not re-run the full test suite. A targeted run of a single test file or a single test (`python -m pytest -q path/to/test_file.py::test_name`) is allowed only when a specific finding in this review requires direct verification. If you run any tests, state in one line in `FINAL_NOTE` exactly what you ran and why.

Return exactly:

VERDICT: PASS or FIX_REQUIRED

CRITICAL:
- ...

HIGH:
- ...

MEDIUM:
- ...

FIX_PROMPT_FOR_IMPLEMENTER:
Between this label and `FINAL_NOTE:`, write either the literal `none` when no fixes are required, or one fenced JSON block that satisfies the schema below.

```json
{
  "fix_required": true,
  "files": ["src/foo.py", "tests/test_foo.py"],
  "changes": [
    { "path": "src/foo.py", "kind": "edit|add|delete", "what": "one-line directive" }
  ],
  "acceptance": "pytest -q passes; <other concrete criteria>"
}
```

Rules:
- `fix_required` must be `true` whenever your verdict is `FIX_REQUIRED`, and `false` when your verdict is `PASS`.
- `files` is the deduplicated union of `changes[].path`.
- Each `changes[].kind` must be exactly one of: `edit`, `add`, `delete`.
- `acceptance` is a single concrete sentence.
- The fenced JSON must be valid JSON (parseable by `ConvertFrom-Json`).

FINAL_NOTE:
Brief summary.
'@

    Write-Host ""
    Write-Host "Running Codex review..."

    $codexArgs = @("exec", (ConvertTo-CrtSafeArg -Value $prompt))
    & codex @codexArgs > (Join-Path $AiLoop "codex_review.md")
    return $LASTEXITCODE
}

function Get-ReviewVerdict {
    param(
        [string]$ReviewFile
    )

    if (!(Test-Path $ReviewFile)) {
        return "FIX_REQUIRED"
    }

    $review = Get-Content $ReviewFile -Raw

    if ($review -match "VERDICT:\s*PASS") {
        return "PASS"
    }

    return "FIX_REQUIRED"
}

function Get-CodexVerdict {
    return Get-ReviewVerdict -ReviewFile (Join-Path $AiLoop "codex_review.md")
}

function Format-FixPromptFromObject {
    param($FixObject)

    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.AppendLine("# Fix prompt")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("## Files to change")
    foreach ($f in @($FixObject.files)) {
        if ([string]::IsNullOrWhiteSpace([string]$f)) {
            continue
        }
        [void]$sb.AppendLine("- $f")
    }
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("## Changes")
    foreach ($c in @($FixObject.changes)) {
        if (-not $c) {
            continue
        }
        $kind = [string]$c.kind
        $p = [string]$c.path
        $what = [string]$c.what
        [void]$sb.AppendLine("- ($kind) ``$p`` - $what")
    }
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("## Acceptance")
    [void]$sb.AppendLine([string]$FixObject.acceptance)
    return $sb.ToString()
}

function Extract-FixPromptFromFile {
    param(
        [string]$ReviewFile,
        [string]$OutputPromptFile
    )

    if (!(Test-Path $ReviewFile)) {
        return $false
    }

    $review = Get-Content $ReviewFile -Raw

    # 1) Prefer structured JSON in a ```json fence (full object; nested arrays/objects supported).
    $jsonMatch = [regex]::Match(
        $review,
        '(?ms)FIX_PROMPT_FOR_IMPLEMENTER:\s*```json\s*(?<json>[\s\S]*?)\s*```',
        [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
    )
    if ($jsonMatch.Success) {
        $jsonText = $jsonMatch.Groups['json'].Value.Trim()
        try {
            $obj = $jsonText | ConvertFrom-Json -ErrorAction Stop
            if ($obj.fix_required) {
                $rendered = Format-FixPromptFromObject -FixObject $obj
                $rendered | Set-Content -Path $OutputPromptFile -Encoding UTF8
                return $true
            }
            return $false
        }
        catch {
            Write-Warning "FIX_PROMPT JSON parse failed: $($_.Exception.Message). Falling back to free-text extractor."
        }
    }

    # 2) Fallback: legacy free-text regex (backward compatible with older Codex outputs).
    Write-Warning "FIX_PROMPT: using legacy free-text extractor (JSON block absent or unusable)."

    # Codex sometimes omits or renames FINAL_NOTE; still recover the fix prompt when the delimiter exists.
    $match = [regex]::Match(
        $review,
        "FIX_PROMPT_FOR_IMPLEMENTER:\s*(?<prompt>[\s\S]*?)FINAL_NOTE:",
        [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
    )

    $prompt = $null
    if ($match.Success) {
        $prompt = $match.Groups["prompt"].Value.Trim()
    }
    else {
        $matchTail = [regex]::Match(
            $review,
            "FIX_PROMPT_FOR_IMPLEMENTER:\s*(?<prompt>[\s\S]*)",
            [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
        )

        if (!$matchTail.Success) {
            return $false
        }

        $prompt = $matchTail.Groups["prompt"].Value.Trim()
    }

    if (!$prompt -or $prompt -eq "none") {
        Write-Host "Extract-FixPromptFromFile: extracted prompt was empty or 'none'."
        return $false
    }

    $prompt | Set-Content $OutputPromptFile -Encoding UTF8
    return $true
}

function Write-NextImplementerPrompt {
    param([string]$PromptText)
    $neutral = Join-Path $AiLoop "next_implementer_prompt.md"
    $PromptText | Set-Content $neutral -Encoding UTF8
}

function Extract-FixPrompt {
    $codexReview = Join-Path $AiLoop "codex_review.md"
    $tmp = Join-Path $AiLoop "next_implementer_prompt.md"
    $ok = Extract-FixPromptFromFile -ReviewFile $codexReview -OutputPromptFile $tmp
    if ($ok) {
        $body = Get-Content $tmp -Raw
        Write-NextImplementerPrompt -PromptText $body.TrimEnd()
    }
    return $ok
}

function Run-ImplementerFix {
    Ensure-AiLoopFiles

    $implementerPrompt = @"
Read:
- .ai-loop/project_summary.md
- .ai-loop/next_implementer_prompt.md
- .ai-loop/task.md if needed

Fix only the issues described in the next-implementer prompt file above.

Important rules:
- project_summary.md is durable project-level memory.
- The user explicitly authorized the task and the fix prompt.
- If the fix prompt asks to implement the full task from .ai-loop/task.md, do it. Do not refuse because of scope.
- Do not start unrelated features.
- Do not make unrelated refactors.
- Preserve existing behavior unless the fix prompt explicitly asks to change it.
- Do not commit or push; the PowerShell orchestrator handles git.

After changes:
1. Run the configured test command if applicable.
2. If task-specific CLI command is described in .ai-loop/task.md, run it when inputs exist; otherwise document why it was skipped.
3. Update .ai-loop/implementer_summary.md.
   - changed files
   - test result
   - implementation summary
   - task-specific outputs or skipped live-run reason
   - remaining risks
4. Update .ai-loop/project_summary.md with durable project-level changes only:
   - new modules/components
   - architecture/pipeline changes
   - important design decisions
   - current stage
   - next likely steps
"@

    Write-Host ""
    $runWrapper = if (-not [string]::IsNullOrWhiteSpace($CursorCommand)) { $CursorCommand } else { Join-Path $PSScriptRoot "run_cursor_agent.ps1" }
    Write-Host "Running implementer (non-interactive) via: $runWrapper"
    Write-Host "(Parameters -CursorCommand / -CursorModel select the implementer wrapper and model; default wrapper is the Cursor Agent CLI driver.)"

    # Prompt via stdin to the implementer wrapper (run_cursor_agent.ps1 by default,
    # or run_opencode_agent.ps1 when -CursorCommand is set).
    $debugDir = Join-Path $AiLoop "_debug"
    New-Item -ItemType Directory -Force -Path $debugDir | Out-Null
    $implementerArgs = @("--print", "--trust", "--workspace", $ProjectRoot)
    if (-not [string]::IsNullOrWhiteSpace($CursorModel)) {
        $implementerArgs += @("--model", $CursorModel)
    }
    $implementerPrompt | & $runWrapper @implementerArgs *> (Join-Path $debugDir "implementer_fix_output.txt")
    return $LASTEXITCODE
}

function Stage-SafeProjectFiles {
    Write-Host "Staging safe project files..."

    foreach ($path in Get-SafeAddPathList) {
        if (Test-Path $path) {
            git add $path
        }
    }

    # Intentionally do NOT stage runtime artifacts:
    # .ai-loop/codex_review.md
    # .ai-loop/last_diff.patch
    # .ai-loop/test_output.txt
    # .ai-loop/test_output_before_commit.txt
    # .ai-loop/next_implementer_prompt.md
    # .ai-loop/final_status.md
    # .tmp/
    # input/
    # output/
}

function Commit-And-Push {
    Ensure-AiLoopFiles

    Write-Host ""
    Write-Host "Preparing Git commit..."

    Write-Host "Running final test gate before commit..."
    Invoke-CommandToFile $TestCommand (Join-Path $AiLoop "test_output_before_commit.txt") | Out-Null

    if ($LASTEXITCODE -ne 0) {
        Write-FinalStatus "ABORTED: tests failed before commit. Push skipped."
        Write-Host "ABORTED: tests failed before commit. Push skipped."
        exit 5
    }

    Add-IntentToAddForReview
    git diff > (Join-Path $AiLoop "last_diff.patch")
    git status --short > (Join-Path $AiLoop "git_status.txt")

    $status = git status --porcelain

    if (!$status) {
        Write-Host "No changes to commit."
        return
    }

    Stage-SafeProjectFiles

    $staged = git diff --cached --name-only

    if (!$staged) {
        Write-Host "No safe staged changes to commit."
        return
    }

    Write-Host "Creating commit..."
    git commit -m $CommitMessage

    if ($LASTEXITCODE -ne 0) {
        Write-Host "Git commit failed. Push skipped."
        Write-FinalStatus "PASS, but git commit failed. Manual check required."
        exit 3
    }

    if (!$NoPush) {
        Write-Host "Pushing to remote..."
        git push

        if ($LASTEXITCODE -ne 0) {
            Write-Host "Git push failed."
            Write-FinalStatus "PASS and committed, but git push failed. Manual push required."
            exit 4
        }

        Write-Host "Git push completed."
    }
    else {
        Write-Host "NoPush enabled. Commit created locally only."
    }
}

function Try-ResumeFromExistingReview {
    Ensure-AiLoopFiles

    if (!$Resume) {
        return $false
    }

    Write-Host ""
    Write-Host "Resume mode enabled."

    $nextNeutral = Join-Path $AiLoop "next_implementer_prompt.md"

    if (Test-Path $nextNeutral) {
        Write-Host "Resuming from existing next_implementer_prompt.md..."
        Run-ImplementerFix | Out-Null
        return $true
    }

    $codexReview = Join-Path $AiLoop "codex_review.md"
    if (Test-Path $codexReview) {
        $codexVerdict = Get-CodexVerdict

        if ($codexVerdict -eq "PASS") {
            Write-Host "Existing Codex verdict is PASS. Running final test gate, commit, and push."
            Commit-And-Push
            Write-FinalStatus "PASS from resume mode. Changes committed and pushed if NoPush was not enabled."
            Write-Host "Final status: PASS"
            if ($WithWrapUp) {
                & "$PSScriptRoot\wrap_up_session.ps1"
            }
            exit 0
        }

        if (Extract-FixPrompt) {
            Write-Host "Extracted fix prompt from existing Codex review."
            Run-ImplementerFix | Out-Null
            return $true
        }
    }

    Write-Host "No usable existing review/prompt found. Starting normal loop."
    return $false
}

Ensure-AiLoopFiles

if (-not $Resume) {
    Clear-AiLoopRuntimeState
}

$resumed = Try-ResumeFromExistingReview

if ($resumed) {
    Write-Host ""
    Write-Host "Resume fix completed. Continuing with review loop..."
}

for ($i = 1; $i -le $MaxIterations; $i++) {
    Write-Host ""
    Write-Host "=============================="
    Write-Host "AI LOOP ITERATION $i / $MaxIterations"
    Write-Host "=============================="

    Save-TestAndDiff | Out-Null
    Run-PostFixCommand | Out-Null

    $porcelainLines = @(git status --porcelain --untracked-files=all 2>$null)
    $hasWork = $false
    foreach ($ln in $porcelainLines) {
        if (-not [string]::IsNullOrWhiteSpace($ln)) {
            $hasWork = $true
            break
        }
    }
    if (-not $hasWork) {
        if ($i -eq 1) {
            Write-FinalStatus @"
STATUS: FAILED
REASON: REVIEW_STARTED_ON_CLEAN_TREE
DETAIL: Working tree is clean before Codex review. Use scripts/ai_loop_task_first.ps1 when starting from scratch with an implementer pass, or make changes before calling REVIEW-only mode.
"@
            Write-Host ""
            Write-Host "Clean tree on iteration 1: skipping Codex. Prefer task-first (ai_loop_task_first.ps1) when the working tree has no changes yet." -ForegroundColor Yellow
            exit 6
        }
        Write-FinalStatus @"
STATUS: FAILED
REASON: NO_CHANGES_AFTER_IMPLEMENTER_FIX
DETAIL: No working-tree changes before Codex review on iteration $i after the implementer fix pass.
"@
        Write-Host ""
        Write-Host "Iteration $i`: working tree clean before Codex (implementer fix produced no git-visible changes). See .ai-loop\final_status.md" -ForegroundColor Yellow
        exit 7
    }

    Run-CodexReview | Out-Null

    $codexVerdict = Get-CodexVerdict

    if ($codexVerdict -eq "PASS") {
        Write-Host ""
        Write-Host "Codex verdict: PASS"

        Commit-And-Push

        Write-FinalStatus "PASS after iteration $i. Codex=PASS. Changes committed and pushed if NoPush was not enabled."

        Write-Host ""
        Write-Host "Final status: PASS"
        Write-Host "See:"
        Write-Host ".ai-loop\final_status.md"
        Write-Host ".ai-loop\codex_review.md"
        Write-Host ".ai-loop\implementer_summary.md"
        Write-Host ".ai-loop\project_summary.md"

        if ($WithWrapUp) {
            & "$PSScriptRoot\wrap_up_session.ps1"
        }
        exit 0
    }

    $hasPrompt = Extract-FixPrompt

    if (!$hasPrompt) {
        Write-FinalStatus "STOPPED: Codex requested fixes, but no fix prompt was extracted."
        Write-Host ""
        Write-Host "Stopped: Codex requested fixes, but no fix prompt was extracted."
        Write-Host "See:"
        Write-Host ".ai-loop\codex_review.md"
        exit 1
    }

    Run-ImplementerFix | Out-Null
}

Write-FinalStatus "STOPPED: max iterations reached. Manual review required."

Write-Host ""
Write-Host "Stopped: max iterations reached. Manual review required."
Write-Host "See:"
Write-Host ".ai-loop\final_status.md"
Write-Host ".ai-loop\codex_review.md"
Write-Host ".ai-loop\implementer_summary.md"
Write-Host ".ai-loop\project_summary.md"

exit 2
