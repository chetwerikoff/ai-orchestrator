param(
    [int]$MaxIterations = 10,

    [string]$CommitMessage = "AI loop task implementation",

    [string]$TaskPath = ".ai-loop\task.md",

    [string]$AutoLoopScript = ".\scripts\ai_loop_auto.ps1",

    # This orchestrator uses Cursor Agent CLI as `agent`.
    # If your local command is different, pass -CursorCommand "your-command".
    [string]$CursorCommand = "agent",

    [string]$CursorModel = "",

    [switch]$SkipInitialCursor,

    [switch]$NoPush,

    [string]$TestCommand = "python -m pytest",

    [string]$PostFixCommand = "",

    [string]$SafeAddPaths = "src/,tests/,README.md,scripts/,docs/,templates/,ai_loop.py,pytest.ini,.gitignore,requirements.txt,pyproject.toml,setup.cfg,.ai-loop/task.md,.ai-loop/cursor_summary.md,.ai-loop/project_summary.md"
)

$ErrorActionPreference = "Stop"

$ProjectRoot = (Resolve-Path ".").Path
$AiLoop = Join-Path $ProjectRoot ".ai-loop"
$ResultPathRelative = ".ai-loop/cursor_implementation_result.md"

function Write-Section {
    param([string]$Text)
    Write-Host ""
    Write-Host "==============================" -ForegroundColor Cyan
    Write-Host $Text -ForegroundColor Cyan
    Write-Host "==============================" -ForegroundColor Cyan
}

function Assert-FileExists {
    param(
        [string]$Path,
        [string]$Message
    )

    if (-not (Test-Path $Path)) {
        throw "$Message Path: $Path"
    }
}

function Assert-CommandExists {
    param([string]$CommandName)

    $cmd = Get-Command $CommandName -ErrorAction SilentlyContinue
    if (-not $cmd) {
        throw @"
Command '$CommandName' was not found.

What to do:
1. Check Cursor Agent CLI is installed and available in PATH.
2. Try:
   Get-Command agent
   Get-Command cursor-agent
   Get-Command cursor
3. If your Cursor CLI command has a different name, run this script with:
   -CursorCommand "YOUR_COMMAND_NAME"
"@
    }
}

function Get-GitShortStatus {
    $status = git status --short 2>$null
    if ($LASTEXITCODE -ne 0) {
        return ""
    }
    return ($status -join [Environment]::NewLine)
}

function Clear-AiLoopRuntimeState {
    $files = @(
        ".ai-loop\codex_review.md",
        ".ai-loop\next_cursor_prompt.md",
        ".ai-loop\cursor_agent_output.txt",
        ".ai-loop\cursor_implementation_output.txt",
        ".ai-loop\cursor_implementation_prompt.md",
        ".ai-loop\cursor_implementation_result.md",
        ".ai-loop\test_output.txt",
        ".ai-loop\test_output_before_commit.txt",
        ".ai-loop\last_diff.patch",
        ".ai-loop\final_status.md",
        ".ai-loop\git_status.txt",
        ".ai-loop\post_fix_output.txt",
        ".ai-loop\claude_final_review.md"
    )

    foreach ($rel in $files) {
        $full = Join-Path $ProjectRoot $rel
        Remove-Item $full -Force -ErrorAction SilentlyContinue
    }
}

function Initialize-CursorSummaryForImplementation {
    # Avoid Codex reading a stale per-task summary; the implementer must replace this body.
    $cursorSummaryPath = Join-Path $AiLoop "cursor_summary.md"
    $body = @"
# Cursor summary

This file was reset at the start of the task-first Cursor pass so automated review does not see stale context.

The implementer must update this file before finishing: what changed, tests run, task-specific command output or skip reason, and remaining risks.
"@
    New-Item -ItemType Directory -Force $AiLoop | Out-Null
    Set-Content -Path $cursorSummaryPath -Value $body -Encoding UTF8
}

function Get-FilteredPorcelainLinesForImplementation {
    # Exclude script-managed outputs so we detect edits made by the agent, not the orchestrator.
    # `--untracked-files=all` lists nested untracked paths instead of collapsing to a lone `?? dir/`
    # line; combine with directory manifests so stable directory porcelain still fingerprints edits.
    $raw = @(git status --porcelain --untracked-files=all 2>$null)
    if ($LASTEXITCODE -ne 0) {
        return @()
    }

    $skipPatterns = @(
        "/cursor_summary\.md",
        "\\cursor_summary\.md",
        "/cursor_implementation_prompt\.md",
        "\\cursor_implementation_prompt\.md",
        "/cursor_implementation_output\.txt",
        "\\cursor_implementation_output\.txt"
    )

    return @($raw | Where-Object {
            $line = $_
            $skip = $false
            foreach ($pat in $skipPatterns) {
                if ($line -match $pat) {
                    $skip = $true
                    break
                }
            }
            -not $skip
        })
}

function Compare-PorcelainSets {
    param(
        [string[]]$BeforeLines,
        [string[]]$AfterLines
    )

    $b = (($BeforeLines | Sort-Object) -join "`n").Trim()
    $a = (($AfterLines | Sort-Object) -join "`n").Trim()
    return ($b -ne $a)
}

function Test-IsOrchestratorScratchImplementationPath {
    param([string]$NormPath)

    $scratchNames = @(
        "cursor_summary.md",
        "cursor_implementation_prompt.md",
        "cursor_implementation_output.txt"
    )
    foreach ($name in $scratchNames) {
        if ($NormPath -eq $name) {
            return $true
        }
        if ($NormPath.EndsWith("/$name")) {
            return $true
        }
    }
    return $false
}

function Get-NormalizedImplementationPathsFromFilteredPorcelain {
    param([string[]]$Lines)

    $rawPaths = @(Get-NormalizedPathsFromPorcelain -Lines $Lines)
    return @($rawPaths | Where-Object {
            -not [string]::IsNullOrWhiteSpace($_) -and
            -not (Test-IsOrchestratorScratchImplementationPath -NormPath $_)
        })
}

function Get-ImplementationContentSnapshotTable {
    param([string[]]$NormPaths)

    $table = @{}
    foreach ($norm in ($NormPaths | Sort-Object -Unique)) {
        if ([string]::IsNullOrWhiteSpace($norm)) {
            continue
        }
        if (Test-IsOrchestratorScratchImplementationPath -NormPath $norm) {
            continue
        }
        $relWin = $norm -replace "/", "\"
        $full = Join-Path $ProjectRoot $relWin
        $table[$norm] = Get-ResultFileSnapshot -FullPathParam $full
    }
    return $table
}

function Get-CursorProducedPathsFromContentDelta {
    param(
        $BeforeTable,
        $AfterTable
    )

    $allPaths = New-Object System.Collections.Generic.HashSet[string]
    foreach ($k in $BeforeTable.Keys) {
        [void]$allPaths.Add([string]$k)
    }
    foreach ($k in $AfterTable.Keys) {
        [void]$allPaths.Add([string]$k)
    }

    $changed = New-Object System.Collections.Generic.List[string]
    foreach ($p in $allPaths) {
        $b = $BeforeTable[$p]
        $a = $AfterTable[$p]
        if ($null -eq $b) {
            $b = @{ Exists = $false; Hash = $null }
        }
        if ($null -eq $a) {
            $a = @{ Exists = $false; Hash = $null }
        }

        $existDiff = ($b.Exists -ne $a.Exists)
        $hashDiff = ($false)
        if ($b.Exists -and $a.Exists -and ($b.Hash -ne $a.Hash)) {
            $hashDiff = $true
        }
        if ($existDiff -or $hashDiff) {
            $changed.Add($p)
        }
    }
    return @($changed)
}

function Test-ImplementationHadAgentSideEffects {
    param(
        [string[]]$BeforeLines,
        [string[]]$AfterLines,
        $BeforeContentTable,
        $AfterContentTable,
        [bool]$ResultChangedDuringPass = $false
    )

    $hadPorcelainDelta = Compare-PorcelainSets -BeforeLines $BeforeLines -AfterLines $AfterLines
    $contentDeltaPaths = @(Get-CursorProducedPathsFromContentDelta `
            -BeforeTable $BeforeContentTable `
            -AfterTable $AfterContentTable)
    $hadContentDelta = $contentDeltaPaths.Count -gt 0
    return ($hadPorcelainDelta -or $hadContentDelta -or $ResultChangedDuringPass)
}

function Get-NormalizedPathsFromPorcelain {
    param([string[]]$Lines)

    $paths = New-Object System.Collections.Generic.HashSet[string]
    foreach ($line in $Lines) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $trimmed = $line.TrimEnd()
        if ($trimmed.Length -lt 4) { continue }

        $rest = $trimmed.Substring(3).Trim()
        if ($rest -match " -> ") {
            $parts = $rest -split " -> "
            foreach ($p in $parts) {
                [void]$paths.Add(($p.Trim() -replace '\\', '/'))
            }
        }
        else {
            [void]$paths.Add(($rest -replace '\\', '/'))
        }
    }
    return @($paths)
}

function Build-PorcelainPathToLineMap {
    param([string[]]$Lines)

    $map = @{}
    foreach ($line in $Lines) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $trimmed = $line.TrimEnd()
        $paths = Get-NormalizedPathsFromPorcelain -Lines @($trimmed)
        foreach ($p in $paths) {
            $map[$p] = $trimmed
        }
    }
    return $map
}

function Get-CursorProducedPathsFromPorcelainDelta {
    param(
        [string[]]$BeforeLines,
        [string[]]$AfterLines
    )

    $beforeMap = Build-PorcelainPathToLineMap -Lines $BeforeLines
    $afterMap = Build-PorcelainPathToLineMap -Lines $AfterLines

    $allPaths = New-Object System.Collections.Generic.HashSet[string]
    foreach ($k in $beforeMap.Keys) { [void]$allPaths.Add($k) }
    foreach ($k in $afterMap.Keys) { [void]$allPaths.Add($k) }

    $changed = New-Object System.Collections.Generic.List[string]
    foreach ($p in $allPaths) {
        $b = $beforeMap[$p]
        $a = $afterMap[$p]
        $bNull = ($null -eq $b)
        $aNull = ($null -eq $a)
        if ($bNull -ne $aNull -or (($null -ne $b) -and ($null -ne $a) -and ($b -ne $a))) {
            $changed.Add($p)
        }
    }
    return @($changed)
}

function Get-ResultFileSnapshot {
    param([string]$FullPathParam)

    if (-not (Test-Path -LiteralPath $FullPathParam)) {
        return @{ Exists = $false; Hash = $null }
    }

    $item = Get-Item -LiteralPath $FullPathParam
    $hashVal = $null

    if ($item.PSIsContainer) {
        # `Get-FileHash` is not meaningful for directories; aggregate nested file paths + hashes
        # so edits under an already-untracked tree cannot show as Exists=true with Hash=null.
        $root = $item.FullName
        $lines = New-Object System.Collections.Generic.List[string]
        Get-ChildItem -LiteralPath $FullPathParam -File -Recurse -Force -ErrorAction SilentlyContinue |
            Sort-Object FullName |
            ForEach-Object {
                $f = $_
                try {
                    $fh = Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256 -ErrorAction Stop
                    $rel = $f.FullName.Substring($root.Length).TrimStart([char[]]@('\', '/'))
                    $normRel = $rel -replace '\\', '/'
                    [void]$lines.Add("$normRel`t$($fh.Hash)")
                }
                catch {
                    $rel = $f.FullName.Substring($root.Length).TrimStart([char[]]@('\', '/'))
                    $normRel = $rel -replace '\\', '/'
                    [void]$lines.Add("$normRel`tUNREADABLE")
                }
            }

        $payload = (($lines | Sort-Object) -join "`n")
        $sha = [System.Security.Cryptography.SHA256]::Create()
        try {
            $bytes = [System.Text.Encoding]::UTF8.GetBytes($payload)
            $digest = $sha.ComputeHash($bytes)
            $hashVal = ($digest | ForEach-Object { $_.ToString("x2") }) -join ""
        }
        finally {
            if ($null -ne $sha) {
                $sha.Dispose()
            }
        }
    }
    else {
        try {
            $fh = Get-FileHash -LiteralPath $FullPathParam -Algorithm SHA256 -ErrorAction Stop
            $hashVal = $fh.Hash
        }
        catch {
            $hashVal = "FILEHASH_UNREADABLE"
        }
    }

    # Exists=true must never pair with a null/empty hash: content-delta logic treats matching nulls as "no change".
    if ([string]::IsNullOrWhiteSpace($hashVal)) {
        $hashVal = "SNAPSHOT_HASH_UNAVAILABLE"
    }

    return @{ Exists = $true; Hash = $hashVal }
}

function Test-ResultFileChangedDuringPass {
    param(
        $BeforeSnap,
        $AfterSnap
    )

    if ($BeforeSnap.Exists -ne $AfterSnap.Exists) {
        return $true
    }
    if (-not $AfterSnap.Exists) {
        return $false
    }
    return ($BeforeSnap.Hash -ne $AfterSnap.Hash)
}

function Test-CursorResultAllowsNoCodeChanges {
    param([string]$ResultFullPath)

    if (-not (Test-Path -LiteralPath $ResultFullPath)) {
        return $false
    }

    $text = Get-Content -LiteralPath $ResultFullPath -Raw
    return [bool]([regex]::IsMatch(
            $text,
            '(?im)^IMPLEMENTATION_STATUS:\s*DONE_NO_CODE_CHANGES_REQUIRED\s*$'
        ))
}

function Assert-CanProceedAfterImplementation {
    param(
        [string]$ResultFullPath,
        [string[]]$BeforePorcelainLines,
        [string[]]$AfterPorcelainLines,
        [bool]$ResultChangedDuringPass = $false,
        $BeforeContentTable,
        $AfterContentTable
    )

    $porcelainDelta = @(Get-CursorProducedPathsFromPorcelainDelta `
            -BeforeLines $BeforePorcelainLines `
            -AfterLines $AfterPorcelainLines)

    $contentDeltaPaths = @(Get-CursorProducedPathsFromContentDelta `
            -BeforeTable $BeforeContentTable `
            -AfterTable $AfterContentTable)

    $deltaPaths = New-Object System.Collections.Generic.HashSet[string]
    foreach ($p in $porcelainDelta) {
        [void]$deltaPaths.Add($p)
    }
    foreach ($p in $contentDeltaPaths) {
        [void]$deltaPaths.Add($p)
    }

    $resultNorm = ($ResultPathRelative -replace '\\', '/')
    if ($ResultChangedDuringPass) {
        [void]$deltaPaths.Add($resultNorm)
    }

    if ($deltaPaths.Count -eq 0) {
        return
    }

    $onlyResult = ($deltaPaths.Count -eq 1) -and $deltaPaths.Contains($resultNorm)

    if (-not $onlyResult) {
        return
    }

    if (Test-CursorResultAllowsNoCodeChanges -ResultFullPath $ResultFullPath) {
        return
    }

    $msg = @"
Blocked: After this Cursor pass, the only working-tree delta (excluding orchestrator scratch files) was .ai-loop/cursor_implementation_result.md, but IMPLEMENTATION_STATUS: DONE_NO_CODE_CHANGES_REQUIRED was not present.

Pre-existing edits in other files do not bypass this rule. Add that status line (exact label) if no new repo edits are needed, or implement the task in tracked project files.
"@

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

function Write-NoChangesFinalStatus {
    $body = @"
STATUS: FAILED
REASON: NO_CHANGES_AFTER_CURSOR
DETAIL: Cursor implementation completed twice but produced no meaningful implementation delta (after excluding .ai-loop/cursor_summary.md and orchestrator prompt/output scratch files, merging filesystem SHA256 snapshots for paths shown in filtered porcelain, and treating .ai-loop/cursor_implementation_result.md via filesystem when git omits it). Codex review was skipped to avoid wasting a review turn.
"@
    New-Item -ItemType Directory -Force $AiLoop | Out-Null
    $body | Set-Content -Path (Join-Path $AiLoop "final_status.md") -Encoding UTF8
}

function Invoke-CursorImplementation {
    param(
        [string]$TaskFile,
        [string]$CommandName,
        [string]$Model,
        [string]$ExtraInstructions = ""
    )

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
        $prompt += "`n`n"
        $prompt += $ExtraInstructions.Trim()
        $prompt += "`n"
    }

    New-Item -ItemType Directory -Force $AiLoop | Out-Null

    $promptPath = Join-Path $AiLoop "cursor_implementation_prompt.md"
    $outputPath = Join-Path $AiLoop "cursor_implementation_output.txt"

    Set-Content -Path $promptPath -Value $prompt -Encoding UTF8

    Write-Host "Cursor implementation prompt saved to: $promptPath"
    Write-Host "Cursor implementation output will be saved to: $outputPath"
    Write-Host "Running Cursor implementer..."

    $resultFull = Join-Path $ProjectRoot ".ai-loop\cursor_implementation_result.md"
    $beforeResultSnap = Get-ResultFileSnapshot -FullPathParam $resultFull

    $beforePorcelain = Get-FilteredPorcelainLinesForImplementation
    $beforePathSet = @(Get-NormalizedImplementationPathsFromFilteredPorcelain -Lines $beforePorcelain)
    $beforeContentTable = Get-ImplementationContentSnapshotTable -NormPaths $beforePathSet

    # Match the existing orchestrator's Cursor Agent invocation style:
    # agent --print --trust --workspace <project-root> <prompt>
    $agentArgs = @("--print", "--trust", "--workspace", $ProjectRoot)

    if (-not [string]::IsNullOrWhiteSpace($Model)) {
        $agentArgs += @("--model", $Model)
    }

    $agentArgs += $prompt

    & $CommandName @agentArgs *> $outputPath

    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        throw "Cursor implementation failed with exit code $exitCode. See: $outputPath"
    }

    Write-Host "Cursor implementation finished. See: $outputPath"

    $afterPorcelain = Get-FilteredPorcelainLinesForImplementation
    $afterResultSnap = Get-ResultFileSnapshot -FullPathParam $resultFull
    $resultChanged = Test-ResultFileChangedDuringPass -BeforeSnap $beforeResultSnap -AfterSnap $afterResultSnap

    $afterPathSet = @(Get-NormalizedImplementationPathsFromFilteredPorcelain -Lines $afterPorcelain)
    $unionPaths = @($beforePathSet + $afterPathSet | Select-Object -Unique)
    $afterContentTable = Get-ImplementationContentSnapshotTable -NormPaths $unionPaths

    $hadDelta = Test-ImplementationHadAgentSideEffects `
        -BeforeLines $beforePorcelain `
        -AfterLines $afterPorcelain `
        -BeforeContentTable $beforeContentTable `
        -AfterContentTable $afterContentTable `
        -ResultChangedDuringPass $resultChanged

    return [PSCustomObject]@{
        HadAgentSideEffects       = $hadDelta
        ResultChangedDuringPass   = $resultChanged
        BeforePorcelain           = $beforePorcelain
        AfterPorcelain            = $afterPorcelain
        BeforeContentTable        = $beforeContentTable
        AfterContentTable         = $afterContentTable
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
        [string]$SafeAddPaths
    )

    Assert-FileExists -Path $ScriptPath -Message "Auto loop script was not found."

    Write-Host "Running existing Codex review/fix loop..."

    $psArgs = @(
        "-ExecutionPolicy", "Bypass",
        "-File", $ScriptPath,
        "-MaxIterations", "$Iterations",
        "-CommitMessage", $Message,
        "-TestCommand", $TestCommand,
        "-PostFixCommand", $PostFixCommand,
        "-SafeAddPaths", $SafeAddPaths
    )
    if ($NoPush) {
        $psArgs += "-NoPush"
    }

    & powershell @psArgs

    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        throw "Existing auto loop failed with exit code $exitCode."
    }
}

Write-Section "AI LOOP TASK-FIRST START"

Assert-FileExists -Path $TaskPath -Message "Task file was not found."
Assert-FileExists -Path $AutoLoopScript -Message "Existing auto loop script was not found."

Write-Host "Project root:      $ProjectRoot"
Write-Host "Task file:         $TaskPath"
Write-Host "Auto loop script:  $AutoLoopScript"
Write-Host "Cursor command:    $CursorCommand"
Write-Host "Max iterations:    $MaxIterations"
Write-Host "Commit message:    $CommitMessage"
Write-Host "NoPush:            $NoPush"
Write-Host "Test command:      $TestCommand"
if ($PostFixCommand) {
    Write-Host "Post-fix command:  $PostFixCommand"
}
Write-Host "Safe add paths:    $SafeAddPaths"

$statusBefore = Get-GitShortStatus
if (-not [string]::IsNullOrWhiteSpace($statusBefore)) {
    Write-Host ""
    Write-Host "Current git status before task-first loop:" -ForegroundColor Yellow
    Write-Host $statusBefore
}

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
        Write-Host ""
        Write-Host "No relevant working tree changes after first Cursor pass; retrying with stricter instructions..." -ForegroundColor Yellow
        $implOutcome = Invoke-CursorImplementation -TaskFile $TaskPath -CommandName $CursorCommand -Model $CursorModel -ExtraInstructions $retryBody
    }

    if (-not $implOutcome.HadAgentSideEffects) {
        Write-NoChangesFinalStatus
        Write-Host ""
        Write-Host "NO_CHANGES_AFTER_CURSOR: Cursor produced no repo changes after two attempts. Codex review was skipped. See .ai-loop\final_status.md" -ForegroundColor Red
        exit 1
    }

    $resultFull = Join-Path $ProjectRoot ".ai-loop\cursor_implementation_result.md"
    Assert-CanProceedAfterImplementation `
        -ResultFullPath $resultFull `
        -BeforePorcelainLines $implOutcome.BeforePorcelain `
        -AfterPorcelainLines $implOutcome.AfterPorcelain `
        -ResultChangedDuringPass $implOutcome.ResultChangedDuringPass `
        -BeforeContentTable $implOutcome.BeforeContentTable `
        -AfterContentTable $implOutcome.AfterContentTable
}
else {
    Write-Host "Skipping initial Cursor implementation because -SkipInitialCursor was provided." -ForegroundColor Yellow
}

Write-Section "STEP 2: CODEX REVIEW / FIX LOOP"
Invoke-AutoReviewLoop `
    -ScriptPath $AutoLoopScript `
    -Iterations $MaxIterations `
    -Message $CommitMessage `
    -NoPush:$NoPush `
    -TestCommand $TestCommand `
    -PostFixCommand $PostFixCommand `
    -SafeAddPaths $SafeAddPaths

Write-Section "AI LOOP TASK-FIRST DONE"

$statusAfter = Get-GitShortStatus
if (-not [string]::IsNullOrWhiteSpace($statusAfter)) {
    Write-Host ""
    Write-Host "Final git status:" -ForegroundColor Yellow
    Write-Host $statusAfter
}
else {
    Write-Host "Working tree is clean."
}
