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
    [string]$SafeAddPaths = "src/,tests/,README.md,AGENTS.md,scripts/,docs/,templates/,ai_loop.py,pytest.ini,.gitignore,requirements.txt,pyproject.toml,setup.cfg,.ai-loop/task.md,.ai-loop/implementer_summary.md,.ai-loop/project_summary.md"
)
$ErrorActionPreference = "Stop"
$ProjectRoot = (Resolve-Path ".").Path
$AiLoop = Join-Path $ProjectRoot ".ai-loop"
$ResultPathRelative = ".ai-loop/implementer_result.md"

function ConvertTo-CrtSafeArg {
    # Workaround for a Windows PowerShell 5.1 native-command quoting bug: when a splatted argv
    # element contains both whitespace and embedded double quotes, PS does not escape the inner
    # quotes correctly, and node-CRT re-splits the argument so tokens like `->` leak out as
    # standalone args (rejected by commander.js as unknown options). Pre-escape per MS CRT rules:
    # double any run of backslashes that immediately precedes a quote, then turn the quote into \".
    param([string]$Value)
    return [regex]::Replace($Value, '(\\*)"', { param($m) ($m.Groups[1].Value * 2) + '\"' })
}

function Save-ImplementerStateAt {
    param(
        [string]$AiLoopRoot,
        [string]$Command,
        [string]$Model,
        [string]$Source
    )
    New-Item -ItemType Directory -Force -Path $AiLoopRoot | Out-Null
    $path = Join-Path $AiLoopRoot "implementer.json"
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

function Write-Section {
    param([string]$Text)
    Write-Host ""
    Write-Host "==============================`n$Text`n==============================" -ForegroundColor Cyan
}

function Get-ImplementerStepDisplayLabel {
    <#
    UX-only label for STEP 1 section headers from effective -CursorCommand / -CursorModel.
    Qwen/OpenCode cues are evaluated before generic "agent" substring on the wrapper path.
    #>
    param(
        [string]$Command,
        [string]$Model
    )
    $cmdRaw = if ([string]::IsNullOrWhiteSpace($Command)) { "" } else { $Command.Trim() }
    $modRaw = if ($null -eq $Model) { "" } else { [string]$Model }
    $tail = if ([string]::IsNullOrWhiteSpace($cmdRaw)) { "" } else { Split-Path $cmdRaw -Leaf }
    $hay = (($cmdRaw + "`n" + $tail).ToLowerInvariant())
    $mod = $modRaw.ToLowerInvariant()
    $qwenCue = (
        $hay.Contains("run_opencode_agent.ps1") -or
        $hay.Contains("opencode") -or
        $mod.Contains("qwen")
    )
    if ($qwenCue) { return "QWEN" }
    $cursorCue = (
        $hay.Contains("run_cursor_agent.ps1") -or
        $hay.Contains("cursor") -or
        $hay.Contains("agent")
    )
    if ($cursorCue) { return "CURSOR" }
    return "IMPLEMENTER"
}

function Assert-FileExists {
    param([string]$Path, [string]$Message)
    if (-not (Test-Path $Path)) { throw "$Message Path: $Path" }
}

function Assert-CommandExists {
    param([string]$CommandName)
    if (-not (Get-Command $CommandName -ErrorAction SilentlyContinue)) {
        throw "Command '$CommandName' not found. Install the implementer's CLI (e.g. Cursor Agent) or pass -CursorCommand `"YOUR_SCRIPT_OR_EXE`"."
    }
}

function Clear-AiLoopRuntimeState {
    # Same file list as ai_loop_auto.ps1. Task-first always removes all listed files (no env guard).
    # Auto applies the AI_LOOP_CHAIN_FROM_TASK_FIRST omission only when spawned from this script after the implementer pass.
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
    foreach ($rel in $files) {
        Remove-Item (Join-Path $ProjectRoot $rel) -Force -ErrorAction SilentlyContinue
    }
}

function Initialize-ImplementerSummaryForImplementation {
    $implementerSummaryPath = Join-Path $AiLoop "implementer_summary.md"
    $body = @(
        "# Implementer summary", "",
        "This file was reset at the start of the task-first implementer pass so automated review does not see stale context.",
        "",
        "The implementer must update this file before finishing: what changed, tests run, task-specific command output or skip reason, and remaining risks."
    ) -join "`n"
    New-Item -ItemType Directory -Force $AiLoop | Out-Null
    Set-Content -Path $implementerSummaryPath -Value $body -Encoding UTF8
}

function Get-ImplementationDeltaPaths {
    $lines = @(git status --porcelain --untracked-files=all 2>$null)
    if ($LASTEXITCODE -ne 0) { return }
    $skip = @(".ai-loop/implementer_summary.md")
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

function Test-ImplementerResultAllowsNoCodeChanges {
    param([string]$ResultFullPath)
    if (-not (Test-Path -LiteralPath $ResultFullPath)) { return $false }
    $text = Get-Content -LiteralPath $ResultFullPath -Raw
    return [bool]([regex]::IsMatch($text, '(?im)^IMPLEMENTATION_STATUS:\s*DONE_NO_CODE_CHANGES_REQUIRED\s*$'))
}

function Write-NoChangesFinalStatus {
    $body = @"
STATUS: FAILED
REASON: NO_CHANGES_AFTER_IMPLEMENTER
DETAIL: Implementer ran twice with no working-tree path delta (after excluding orchestrator scratch paths) and no update to .ai-loop/implementer_result.md on disk. Codex review was skipped.
"@
    New-Item -ItemType Directory -Force $AiLoop | Out-Null
    $body | Set-Content -Path (Join-Path $AiLoop "final_status.md") -Encoding UTF8
}

function Invoke-ImplementerImplementation {
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
- If something is impossible, write a clear note into .ai-loop/implementer_result.md.
- Otherwise, edit the codebase directly.
- You MUST update .ai-loop/implementer_summary.md (a fresh stub was written at run start): list changed files, test results, implementation summary, task-specific command output or why it was skipped, and remaining risks.

TASK:
$taskText
"@
    if (-not [string]::IsNullOrWhiteSpace($ExtraInstructions)) {
        $prompt += "`n`n$($ExtraInstructions.Trim())`n"
    }
    New-Item -ItemType Directory -Force $AiLoop | Out-Null
    $debugDir = Join-Path $AiLoop "_debug"
    New-Item -ItemType Directory -Force -Path $debugDir | Out-Null
    $promptPath = Join-Path $debugDir "implementer_prompt.md"
    $outputPath = Join-Path $debugDir "implementer_output.txt"
    Set-Content -Path $promptPath -Value $prompt -Encoding UTF8
    Write-Host "Implementer prompt saved to: $promptPath"
    Write-Host "Implementer output will be saved to: $outputPath"
    Write-Host "Running implementer via: $CommandName ..."
    $resultFull = Join-Path $ProjectRoot ".ai-loop\implementer_result.md"
    $beforeMeta = Get-ResultFileMeta -FullPath $resultFull
    $beforePaths = @(Get-ImplementationDeltaPaths)
    $agentArgs = @("--print", "--trust", "--workspace", $ProjectRoot)
    if (-not [string]::IsNullOrWhiteSpace($Model)) { $agentArgs += @("--model", $Model) }
    # Prompt via stdin to avoid cmd.exe ~8 191-char batch-line limit (ERROR_ACCESS_DENIED).
    # run_cursor_agent.ps1 calls node.exe directly so stdin is never dropped mid-chain.
    $prompt | & $CommandName @agentArgs *> $outputPath
    if ($LASTEXITCODE -ne 0) {
        throw "Implementer run failed with exit code $LASTEXITCODE. See: $outputPath"
    }
    Write-Host "Implementer finished. See: $outputPath"
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
        [switch]$ChainHandoffFromImplementer,
        [string]$FixerCommand = "",
        [string]$FixerModel = ""
    )
    Assert-FileExists -Path $ScriptPath -Message "Auto loop script was not found."
    Write-Host "Running existing Codex review/fix loop..."
    $psArgs = @("-ExecutionPolicy", "Bypass", "-File", $ScriptPath, "-MaxIterations", "$Iterations", "-CommitMessage", $Message, "-TestCommand", $TestCommand, "-SafeAddPaths", $SafeAddPaths)
    if (-not [string]::IsNullOrWhiteSpace($PostFixCommand)) { $psArgs += @("-PostFixCommand", $PostFixCommand) }
    if (-not [string]::IsNullOrWhiteSpace($FixerCommand)) { $psArgs += @("-CursorCommand", $FixerCommand) }
    if (-not [string]::IsNullOrWhiteSpace($FixerModel)) { $psArgs += @("-CursorModel", $FixerModel) }
    if ($NoPush) { $psArgs += "-NoPush" }
    if ($ChainHandoffFromImplementer) {
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
Write-Host "Project root: $ProjectRoot  Task: $TaskPath  Implementer (-CursorCommand): $CursorCommand  Iterations: $MaxIterations  NoPush: $NoPush  Tests: $TestCommand  SafeAdd: $SafeAddPaths"

if (-not $SkipInitialCursor) {
    Clear-AiLoopRuntimeState
    Initialize-ImplementerSummaryForImplementation
    Save-ImplementerStateAt -AiLoopRoot $AiLoop -Command $CursorCommand -Model $CursorModel -Source "ai_loop_task_first.ps1"
    $step1Label = Get-ImplementerStepDisplayLabel -Command $CursorCommand -Model $CursorModel
    Write-Section "STEP 1: $step1Label IMPLEMENTATION"
    if (-not [string]::IsNullOrWhiteSpace([string]$CursorModel)) {
        Write-Host "Model: $CursorModel"
    }
    Assert-CommandExists -CommandName $CursorCommand
    $retryBody = @"
The previous implementer pass produced no meaningful implementation delta in the working tree.

You MUST either:
1. edit repository files to implement the task, or
2. create/update .ai-loop/implementer_result.md explaining exactly why no file changes are required or why you are blocked.

Do not only summarize or review.
Do not hand the task to Codex.
Do not stop without changing a file unless you write the blocked/no-change explanation file.

If no code changes are truly required, include this exact line in .ai-loop/implementer_result.md:
IMPLEMENTATION_STATUS: DONE_NO_CODE_CHANGES_REQUIRED

Also update .ai-loop/implementer_summary.md (see initial instructions): changed files, tests, summary, task-specific command or skip reason, risks.
"@
    $implOutcome = Invoke-ImplementerImplementation -TaskFile $TaskPath -CommandName $CursorCommand -Model $CursorModel -ExtraInstructions ""
    if (-not $implOutcome.HadAgentSideEffects) {
        Write-Host "No relevant working tree changes after first implementer pass; retrying with stricter instructions..." -ForegroundColor Yellow
        $implOutcome = Invoke-ImplementerImplementation -TaskFile $TaskPath -CommandName $CursorCommand -Model $CursorModel -ExtraInstructions $retryBody
    }
    if (-not $implOutcome.HadAgentSideEffects) {
        Write-NoChangesFinalStatus
        Write-Host "NO_CHANGES_AFTER_IMPLEMENTER: Implementer produced no repo changes after two attempts. Codex review was skipped. See .ai-loop\final_status.md" -ForegroundColor Red
        exit 1
    }
    $resultFull = Join-Path $ProjectRoot ".ai-loop\implementer_result.md"
    $delta = New-Object "System.Collections.Generic.HashSet[string]"
    foreach ($o in @(Compare-Object (@($implOutcome.BeforePaths)) (@($implOutcome.AfterPaths)))) {
        [void]$delta.Add([string]$o.InputObject)
    }
    $resultNorm = ($ResultPathRelative -replace "\\", "/")
    if ($implOutcome.ResultChangedDuringPass) { [void]$delta.Add($resultNorm) }
    if ($delta.Count -gt 0) {
        $onlyResult = ($delta.Count -eq 1) -and $delta.Contains($resultNorm)
        if ($onlyResult -and -not (Test-ImplementerResultAllowsNoCodeChanges -ResultFullPath $resultFull)) {
            $msg = "Blocked: After this implementer pass, the only working-tree delta (excluding orchestrator scratch files) was .ai-loop/implementer_result.md, but IMPLEMENTATION_STATUS: DONE_NO_CODE_CHANGES_REQUIRED was not present.`n`nPre-existing edits in other files do not bypass this rule. Add that status line (exact label) if no new repo edits are needed, or implement the task in tracked project files."
            $detail = @"
STATUS: FAILED
REASON: RESULT_ONLY_WITHOUT_DONE_NO_CODE_MARKER
DETAIL: Only .ai-loop/implementer_result.md changed in the implementer pass delta and IMPLEMENTATION_STATUS: DONE_NO_CODE_CHANGES_REQUIRED was not found.
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
    Write-Host "Skipping initial implementer pass because -SkipInitialCursor was provided." -ForegroundColor Yellow
}

Write-Section "STEP 2: CODEX REVIEW / FIX LOOP"
Invoke-AutoReviewLoop -ScriptPath $AutoLoopScript -Iterations $MaxIterations -Message $CommitMessage -NoPush:$NoPush -TestCommand $TestCommand -PostFixCommand $PostFixCommand -SafeAddPaths $SafeAddPaths -ChainHandoffFromImplementer:$(-not $SkipInitialCursor) -FixerCommand $CursorCommand -FixerModel $CursorModel
Write-Section "AI LOOP TASK-FIRST DONE"
