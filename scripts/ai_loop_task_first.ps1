param(
    [int]$MaxIterations = 10,
    [string]$CommitMessage = "AI loop task implementation",
    [string]$TaskPath = ".ai-loop\task.md",
    [string]$AutoLoopScript = ".\scripts\ai_loop_auto.ps1",
    [string]$CursorCommand = ".\scripts\run_cursor_agent.ps1",
    [string]$CursorModel = "",
    [switch]$SkipInitialCursor,
    [switch]$NoPush,
    [string]$TestCommand = "python -m pytest",
    [string]$PostFixCommand = "",
    [string]$SafeAddPaths = "src/,tests/,README.md,AGENTS.md,scripts/,docs/,templates/,ai_loop.py,pytest.ini,.gitignore,requirements.txt,pyproject.toml,setup.cfg,.ai-loop/task.md,.ai-loop/cursor_summary.md,.ai-loop/project_summary.md"
)
$ErrorActionPreference = "Stop"
$ProjectRoot = (Resolve-Path ".").Path
$AiLoop = Join-Path $ProjectRoot ".ai-loop"
$ResultPathRelative = ".ai-loop/cursor_implementation_result.md"

function ConvertTo-CrtSafeArg {
    # Workaround for a Windows PowerShell 5.1 native-command quoting bug: when a splatted argv
    # element contains both whitespace and embedded double quotes, PS does not escape the inner
    # quotes correctly, and node-CRT re-splits the argument so tokens like `->` leak out as
    # standalone args (rejected by commander.js as unknown options). Pre-escape per MS CRT rules:
    # double any run of backslashes that immediately precedes a quote, then turn the quote into \".
    param([string]$Value)
    return [regex]::Replace($Value, '(\\*)"', { param($m) ($m.Groups[1].Value * 2) + '\"' })
}

function Write-Section {
    param([string]$Text)
    Write-Host ""
    Write-Host "==============================`n$Text`n==============================" -ForegroundColor Cyan
}

function Assert-FileExists {
    param([string]$Path, [string]$Message)
    if (-not (Test-Path $Path)) { throw "$Message Path: $Path" }
}

function Assert-CommandExists {
    param([string]$CommandName)
    if (-not (Get-Command $CommandName -ErrorAction SilentlyContinue)) {
        throw "Command '$CommandName' not found. Install Cursor Agent CLI or pass -CursorCommand `"YOUR_COMMAND_NAME`"."
    }
}

function Clear-AiLoopRuntimeState {
    # Same file list as ai_loop_auto.ps1. Task-first always removes all listed files (no env guard).
    # Auto applies the AI_LOOP_CHAIN_FROM_TASK_FIRST omission only when spawned from this script after Cursor.
    $files = @(
        ".ai-loop\codex_review.md", ".ai-loop/next_cursor_prompt.md", ".ai-loop/cursor_agent_output.txt",
        ".ai-loop/cursor_implementation_output.txt", ".ai-loop/cursor_implementation_prompt.md", ".ai-loop/cursor_implementation_result.md",
        ".ai-loop/test_output.txt", ".ai-loop/test_output_before_commit.txt", ".ai-loop/last_diff.patch", ".ai-loop/final_status.md",
        ".ai-loop/git_status.txt", ".ai-loop/post_fix_output.txt", ".ai-loop/claude_final_review.md"
    )
    foreach ($rel in $files) {
        Remove-Item (Join-Path $ProjectRoot $rel) -Force -ErrorAction SilentlyContinue
    }
}

function Initialize-CursorSummaryForImplementation {
    $cursorSummaryPath = Join-Path $AiLoop "cursor_summary.md"
    $body = @(
        "# Cursor summary", "",
        "This file was reset at the start of the task-first Cursor pass so automated review does not see stale context.",
        "",
        "The implementer must update this file before finishing: what changed, tests run, task-specific command output or skip reason, and remaining risks."
    ) -join "`n"
    New-Item -ItemType Directory -Force $AiLoop | Out-Null
    Set-Content -Path $cursorSummaryPath -Value $body -Encoding UTF8
}

function Get-ImplementationDeltaPaths {
    $lines = @(git status --porcelain --untracked-files=all 2>$null)
    if ($LASTEXITCODE -ne 0) { return }
    $skip = @(".ai-loop/cursor_summary.md", ".ai-loop/cursor_implementation_prompt.md", ".ai-loop/cursor_implementation_output.txt")
    $seen = New-Object "System.Collections.Generic.HashSet[string]"
    foreach ($line in $lines) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $t = $line.TrimEnd()
        if ($t.Length -lt 4) { continue }
        $rest = $t.Substring(3).Trim()
        $path = if ($rest -match " -> ") { ($rest -split " -> ")[-1].Trim() } else { $rest }
        $norm = ($path -replace "\\", "/")
        if ($skip -contains $norm) { continue }
        [void]$seen.Add($norm)
    }
    # Emit via pipeline so callers can safely use @(Get-ImplementationDeltaPaths); an empty `return @()` unwraps to $null in Windows PowerShell and breaks Compare-Object.
    $seen | Sort-Object
}

function Get-ResultFileMeta {
    param([string]$FullPath)
    if (-not (Test-Path -LiteralPath $FullPath)) {
        return @{ Exists = $false; LastWriteTimeUtc = $null }
    }
    $item = Get-Item -LiteralPath $FullPath
    return @{ Exists = $true; LastWriteTimeUtc = $item.LastWriteTimeUtc }
}

function Test-CursorResultAllowsNoCodeChanges {
    param([string]$ResultFullPath)
    if (-not (Test-Path -LiteralPath $ResultFullPath)) { return $false }
    $text = Get-Content -LiteralPath $ResultFullPath -Raw
    return [bool]([regex]::IsMatch($text, '(?im)^IMPLEMENTATION_STATUS:\s*DONE_NO_CODE_CHANGES_REQUIRED\s*$'))
}

function Write-NoChangesFinalStatus {
    $body = @"
STATUS: FAILED
REASON: NO_CHANGES_AFTER_CURSOR
DETAIL: Cursor implementation ran twice with no working-tree path delta (after excluding orchestrator scratch paths) and no update to .ai-loop/cursor_implementation_result.md on disk. Codex review was skipped.
"@
    New-Item -ItemType Directory -Force $AiLoop | Out-Null
    $body | Set-Content -Path (Join-Path $AiLoop "final_status.md") -Encoding UTF8
}

function Invoke-CursorImplementation {
    param([string]$TaskFile, [string]$CommandName, [string]$Model, [string]$ExtraInstructions = "")
    $taskText = Get-Content $TaskFile -Raw
    $prompt = @"
You are the IMPLEMENTER in a local AI development loop.

Your job:
- Read and execute the task below.
- Modify the repository files as needed.
- Do NOT do a review-only pass.
- Do NOT hand the task to Codex.
- Implement the task directly.
- Prefer small, focused changes.
- Run relevant tests if practical.
- Leave the repository in a state ready for Codex review.

Important:
- The review/fix loop will be started after you finish.
- If something is impossible, write a clear note into .ai-loop/cursor_implementation_result.md.
- Otherwise, edit the codebase directly.
- You MUST update .ai-loop/cursor_summary.md (a fresh stub was written at run start): list changed files, test results, implementation summary, task-specific command output or why it was skipped, and remaining risks.

TASK:
$taskText
"@
    if (-not [string]::IsNullOrWhiteSpace($ExtraInstructions)) {
        $prompt += "`n`n$($ExtraInstructions.Trim())`n"
    }
    New-Item -ItemType Directory -Force $AiLoop | Out-Null
    $promptPath = Join-Path $AiLoop "cursor_implementation_prompt.md"
    $outputPath = Join-Path $AiLoop "cursor_implementation_output.txt"
    Set-Content -Path $promptPath -Value $prompt -Encoding UTF8
    Write-Host "Cursor implementation prompt saved to: $promptPath"
    Write-Host "Cursor implementation output will be saved to: $outputPath"
    Write-Host "Running Cursor implementer..."
    $resultFull = Join-Path $ProjectRoot ".ai-loop\cursor_implementation_result.md"
    $beforeMeta = Get-ResultFileMeta -FullPath $resultFull
    $beforePaths = @(Get-ImplementationDeltaPaths)
    $agentArgs = @("--print", "--trust", "--workspace", $ProjectRoot)
    if (-not [string]::IsNullOrWhiteSpace($Model)) { $agentArgs += @("--model", $Model) }
    # Prompt via stdin to avoid cmd.exe ~8 191-char batch-line limit (ERROR_ACCESS_DENIED).
    # run_cursor_agent.ps1 calls node.exe directly so stdin is never dropped mid-chain.
    $prompt | & $CommandName @agentArgs *> $outputPath
    if ($LASTEXITCODE -ne 0) {
        throw "Cursor implementation failed with exit code $LASTEXITCODE. See: $outputPath"
    }
    Write-Host "Cursor implementation finished. See: $outputPath"
    $afterPaths = @(Get-ImplementationDeltaPaths)
    $afterMeta = Get-ResultFileMeta -FullPath $resultFull
    $resultChanged = ($beforeMeta.Exists -ne $afterMeta.Exists)
    if (-not $resultChanged -and $afterMeta.Exists) {
        $resultChanged = ($beforeMeta.LastWriteTimeUtc -ne $afterMeta.LastWriteTimeUtc)
    }
    $hadPathDelta = $null -ne (Compare-Object @($beforePaths) @($afterPaths))
    return [PSCustomObject]@{
        HadAgentSideEffects     = ($hadPathDelta -or $resultChanged)
        ResultChangedDuringPass = $resultChanged
        BeforePaths             = $beforePaths
        AfterPaths              = $afterPaths
    }
}

function Invoke-AutoReviewLoop {
    param(
        [string]$ScriptPath,
        [int]$Iterations,
        [string]$Message,
        [switch]$NoPush,
        [string]$TestCommand,
        [string]$PostFixCommand,
        [string]$SafeAddPaths,
        [switch]$ChainHandoffFromCursor
    )
    Assert-FileExists -Path $ScriptPath -Message "Auto loop script was not found."
    Write-Host "Running existing Codex review/fix loop..."
    $psArgs = @("-ExecutionPolicy", "Bypass", "-File", $ScriptPath, "-MaxIterations", "$Iterations", "-CommitMessage", $Message, "-TestCommand", $TestCommand, "-SafeAddPaths", $SafeAddPaths)
    if (-not [string]::IsNullOrWhiteSpace($PostFixCommand)) { $psArgs += @("-PostFixCommand", $PostFixCommand) }
    if ($NoPush) { $psArgs += "-NoPush" }
    if ($ChainHandoffFromCursor) {
        $env:AI_LOOP_CHAIN_FROM_TASK_FIRST = "1"
    }
    try {
        & powershell @psArgs
        if ($LASTEXITCODE -ne 0) { throw "Existing auto loop failed with exit code $LASTEXITCODE." }
    }
    finally {
        Remove-Item Env:\AI_LOOP_CHAIN_FROM_TASK_FIRST -ErrorAction SilentlyContinue
    }
}

Write-Section "AI LOOP TASK-FIRST START"
Assert-FileExists -Path $TaskPath -Message "Task file was not found."
Assert-FileExists -Path $AutoLoopScript -Message "Existing auto loop script was not found."
Write-Host "Project root: $ProjectRoot  Task: $TaskPath  Cursor: $CursorCommand  Iterations: $MaxIterations  NoPush: $NoPush  Tests: $TestCommand  SafeAdd: $SafeAddPaths"

if (-not $SkipInitialCursor) {
    Clear-AiLoopRuntimeState
    Initialize-CursorSummaryForImplementation
    Write-Section "STEP 1: CURSOR IMPLEMENTATION"
    Assert-CommandExists -CommandName $CursorCommand
    $retryBody = @"
The previous Cursor implementation pass produced no meaningful implementation delta in the working tree.

You MUST either:
1. edit repository files to implement the task, or
2. create/update .ai-loop/cursor_implementation_result.md explaining exactly why no file changes are required or why you are blocked.

Do not only summarize or review.
Do not hand the task to Codex.
Do not stop without changing a file unless you write the blocked/no-change explanation file.

If no code changes are truly required, include this exact line in .ai-loop/cursor_implementation_result.md:
IMPLEMENTATION_STATUS: DONE_NO_CODE_CHANGES_REQUIRED

Also update .ai-loop/cursor_summary.md (see initial instructions): changed files, tests, summary, task-specific command or skip reason, risks.
"@
    $implOutcome = Invoke-CursorImplementation -TaskFile $TaskPath -CommandName $CursorCommand -Model $CursorModel -ExtraInstructions ""
    if (-not $implOutcome.HadAgentSideEffects) {
        Write-Host "No relevant working tree changes after first Cursor pass; retrying with stricter instructions..." -ForegroundColor Yellow
        $implOutcome = Invoke-CursorImplementation -TaskFile $TaskPath -CommandName $CursorCommand -Model $CursorModel -ExtraInstructions $retryBody
    }
    if (-not $implOutcome.HadAgentSideEffects) {
        Write-NoChangesFinalStatus
        Write-Host "NO_CHANGES_AFTER_CURSOR: Cursor produced no repo changes after two attempts. Codex review was skipped. See .ai-loop\final_status.md" -ForegroundColor Red
        exit 1
    }
    $resultFull = Join-Path $ProjectRoot ".ai-loop\cursor_implementation_result.md"
    $delta = New-Object "System.Collections.Generic.HashSet[string]"
    foreach ($o in @(Compare-Object (@($implOutcome.BeforePaths)) (@($implOutcome.AfterPaths)))) {
        [void]$delta.Add([string]$o.InputObject)
    }
    $resultNorm = ($ResultPathRelative -replace "\\", "/")
    if ($implOutcome.ResultChangedDuringPass) { [void]$delta.Add($resultNorm) }
    if ($delta.Count -gt 0) {
        $onlyResult = ($delta.Count -eq 1) -and $delta.Contains($resultNorm)
        if ($onlyResult -and -not (Test-CursorResultAllowsNoCodeChanges -ResultFullPath $resultFull)) {
            $msg = "Blocked: After this Cursor pass, the only working-tree delta (excluding orchestrator scratch files) was .ai-loop/cursor_implementation_result.md, but IMPLEMENTATION_STATUS: DONE_NO_CODE_CHANGES_REQUIRED was not present.`n`nPre-existing edits in other files do not bypass this rule. Add that status line (exact label) if no new repo edits are needed, or implement the task in tracked project files."
            $detail = @"
STATUS: FAILED
REASON: RESULT_ONLY_WITHOUT_DONE_NO_CODE_MARKER
DETAIL: Only .ai-loop/cursor_implementation_result.md changed in the Cursor pass delta and IMPLEMENTATION_STATUS: DONE_NO_CODE_CHANGES_REQUIRED was not found.
"@
            New-Item -ItemType Directory -Force $AiLoop | Out-Null
            $detail | Set-Content -Path (Join-Path $AiLoop "final_status.md") -Encoding UTF8
            Write-Host ""
            Write-Host $msg -ForegroundColor Red
            exit 1
        }
    }
}
else {
    Write-Host "Skipping initial Cursor implementation because -SkipInitialCursor was provided." -ForegroundColor Yellow
}

Write-Section "STEP 2: CODEX REVIEW / FIX LOOP"
Invoke-AutoReviewLoop -ScriptPath $AutoLoopScript -Iterations $MaxIterations -Message $CommitMessage -NoPush:$NoPush -TestCommand $TestCommand -PostFixCommand $PostFixCommand -SafeAddPaths $SafeAddPaths -ChainHandoffFromCursor:$(-not $SkipInitialCursor)
Write-Section "AI LOOP TASK-FIRST DONE"
