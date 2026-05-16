param(
    [int]$MaxIterations = 5,
    [string]$CommitMessage = "AI loop auto update",
    [switch]$Resume,
    [switch]$NoPush,
    [string]$TestCommand = "python -m pytest",
    [string]$PostFixCommand = "",
    [string]$SafeAddPaths = "src/,tests/,README.md,AGENTS.md,scripts/,docs/,tasks/,templates/,ai_loop.py,pytest.ini,.gitignore,requirements.txt,pyproject.toml,setup.cfg,pyrightconfig.json,.ai-loop/task.md,.ai-loop/implementer_summary.md,.ai-loop/project_summary.md,.ai-loop/repo_map.md,.ai-loop/failures.md,.ai-loop/archive/rolls/,.ai-loop/_debug/session_draft.md",
    [string]$CursorCommand = "",
    [string]$CursorModel = "",
    [switch]$WithWrapUp
)

$ErrorActionPreference = "Continue"

$ProjectRoot = (Resolve-Path ".").Path
$AiLoop = Join-Path $ProjectRoot ".ai-loop"
$Tmp = Join-Path $ProjectRoot ".tmp"

try {
    . (Join-Path $PSScriptRoot "record_token_usage.ps1")
}
catch {
    Write-Warning "record_token_usage.ps1 load failed (token recording disabled): $($_.Exception.Message)"
}

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
        $projectSummaryStub = @"
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
"@
        $projectSummaryStub | Set-Content $projectSummary -Encoding UTF8
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

function Save-GitReviewArtifactsForCodex {
    param(
        [string]$GitStatusOut,
        [string]$DiffPatchOut,
        [string]$DiffStatOut
    )

    Push-Location $ProjectRoot
    try {
        @(git status --short --porcelain --untracked-files=all 2>$null) |
            Set-Content -LiteralPath $GitStatusOut -Encoding UTF8
        @(git diff HEAD 2>$null) | Set-Content -LiteralPath $DiffPatchOut -Encoding UTF8
        @(git diff --stat HEAD 2>$null) | Set-Content -LiteralPath $DiffStatOut -Encoding UTF8
    }
    finally {
        Pop-Location
    }
}

function Save-TestAndDiff {
    Ensure-AiLoopFiles

    Write-Host ""
    Write-Host "Running tests..."
    Invoke-CommandToFile $TestCommand (Join-Path $AiLoop "test_output.txt") | Out-Null
    $testExit = $LASTEXITCODE

    Write-Host "Saving git status and diff for Codex review..."
    Save-GitReviewArtifactsForCodex `
        -GitStatusOut (Join-Path $AiLoop "git_status.txt") `
        -DiffPatchOut (Join-Path $AiLoop "last_diff.patch") `
        -DiffStatOut (Join-Path $AiLoop "diff_summary.txt")

    if ($testExit -ne 0) {
        Write-Host "Tests failed; generating filtered failures summary..."
        $filterScript = Join-Path $ProjectRoot "scripts\filter_pytest_failures.py"
        if (Test-Path $filterScript) {
            python $filterScript `
                --input  (Join-Path $AiLoop "test_output.txt") `
                --output (Join-Path $AiLoop "test_failures_summary.md")
        }
        # If filter script is missing, skip silently - test_output.txt remains
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

function Get-TaskHeadingForTokenUsage {
    param([string]$TaskFilePath)

    try {
        if (-not (Test-Path -LiteralPath $TaskFilePath)) {
            return ""
        }
        foreach ($line in Get-Content -LiteralPath $TaskFilePath -ErrorAction SilentlyContinue) {
            $t = [string]$line
            $m = [regex]::Match($t, '^\s*#\s*(.+)$')
            if ($m.Success) {
                return $m.Groups[1].Value.Trim()
            }
        }
        return ""
    }
    catch {
        return ""
    }
}

function Register-CodexTokenUsageAttempt {
    param(
        [string]$CodexText,
        [int]$Iteration,
        [string]$TaskMdPath
    )

    try {
        if ($null -eq (Get-Command -Name ConvertFrom-CliTokenUsage -ErrorAction SilentlyContinue)) {
            return
        }
        $parsed = ConvertFrom-CliTokenUsage -Text $CodexText
        if (-not $parsed) {
            return
        }
        if ($null -eq (Get-Command -Name Write-TokenUsageRecord -ErrorAction SilentlyContinue)) {
            return
        }
        $heading = Get-TaskHeadingForTokenUsage -TaskFilePath $TaskMdPath
        Write-TokenUsageRecord `
            -TaskName $heading `
            -ScriptName "ai_loop_auto.ps1" `
            -Iteration $Iteration `
            -Provider "codex" `
            -Model "codex" `
            -InputTokens $parsed.InputTokens `
            -OutputTokens $parsed.OutputTokens `
            -TotalTokens $parsed.TotalTokens `
            -Confidence "unknown" `
            -Source $parsed.Source `
            -Quality $parsed.Quality
    }
    catch {
        Write-Warning "Codex token usage recording failed (non-blocking): $($_.Exception.Message)"
    }
}

function Run-CodexReview {
    Ensure-AiLoopFiles

    $prompt = @'
You are the reviewer in an authenticated development loop.

Read in this priority order (stop reading once verdict is clear):

1. `.ai-loop/task.md` - current task contract
2. `.ai-loop/reviewer_context.md` - bounded working-rules summary (preferred over AGENTS.md)
3. `.ai-loop/implementer_summary.md` - implementer's report on the latest iteration
4. `.ai-loop/diff_summary.txt` - short git diff --stat
5. `.ai-loop/test_failures_summary.md` - filtered failures (read when present; do not read test_output.txt unless this summary is absent or insufficient)
6. `.ai-loop/last_diff.patch` - full diff only when exact patch context is required for a specific finding; prefer reading only the changed files relevant to that finding
7. `.ai-loop/test_output.txt` - raw pytest output (read only when test_failures_summary.md is absent or insufficient)
8. `.ai-loop/git_status.txt` - short porcelain status
9. `AGENTS.md` - full working rules (read only when reviewer_context.md is insufficient)

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

If `diff_summary.txt` reports more than 300 changed lines OR more than 8 changed files, read `diff_summary.txt` first. Prefer opening only the repository files changed for the relevant finding instead of loading all of `last_diff.patch`. Load `last_diff.patch` only when exact patch context is required; if you load it, justify briefly in `FINAL_NOTE`.

## Test execution policy

The orchestrator already ran `pytest` before this review. Prefer `.ai-loop/test_failures_summary.md` when present; do not read `.ai-loop/test_output.txt` unless that summary is absent or insufficient for your finding. Do not re-run the full test suite. A targeted run of a single test file or test (`python -m pytest -q path/to/test_file.py::test_name`) is allowed only when a specific finding in this review requires direct verification. If you run any tests, state in one line in `FINAL_NOTE` exactly what you ran and why.

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
    $codexOutPath = Join-Path $AiLoop "codex_review.md"

    try {
        $codexStdoutStderr = @(& codex @codexArgs 2>&1)
        $codexExit = $LASTEXITCODE

        $textLines = foreach ($item in $codexStdoutStderr) {
            if ($item -is [System.Management.Automation.ErrorRecord]) {
                $item.ToString()
            }
            else {
                [string]$item
            }
        }
        $joinedOut = ($textLines -join [Environment]::NewLine).TrimEnd()
        $joinedOut | Set-Content -LiteralPath $codexOutPath -Encoding UTF8 -ErrorAction SilentlyContinue

        return $codexExit
    }
    catch {
        Write-Warning "Codex invocation error (token capture may be incomplete): $($_.Exception.Message)"
        try {
            & codex @codexArgs 2>&1 | Out-File -LiteralPath $codexOutPath -Encoding utf8
        }
        catch {
            Write-Warning "Codex fallback redirect failed: $($_.Exception.Message)"
        }
        return $LASTEXITCODE
    }
}

function Get-ReviewVerdict {
    param(
        [string]$ReviewFile
    )

    if (!(Test-Path $ReviewFile)) {
        return "FIX_REQUIRED"
    }

    $review = Get-Content $ReviewFile -Raw
    if ($null -eq $review) {
        $review = ""
    }
    if ($review.Length -gt 0 -and [int][char]$review[0] -eq 0xFEFF) {
        $review = $review.Substring(1)
    }

    # Line-anchored only: substring hits like `VERDICT: PASS or FIX_REQUIRED` must not imply PASS.
    $verdictRe = [regex]::new(
        '^\s*VERDICT:\s*(PASS|FIX_REQUIRED)\s*$',
        ([System.Text.RegularExpressions.RegexOptions]::IgnoreCase -bor
            [System.Text.RegularExpressions.RegexOptions]::Compiled)
    )
    $lastVerdict = $null
    foreach ($line in ($review -split '\r?\n')) {
        $t = $line.Trim()
        $m = $verdictRe.Match($t)
        if ($m.Success) {
            $g = $m.Groups[1].Value.ToUpperInvariant()
            if ($g -eq 'PASS') {
                $lastVerdict = 'PASS'
            }
            elseif ($g -eq 'FIX_REQUIRED') {
                $lastVerdict = 'FIX_REQUIRED'
            }
        }
    }
    if ($null -ne $lastVerdict) {
        return $lastVerdict
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

function Get-FixPromptJsonObjectFromReview {
    param([string]$ReviewFile)
    if (!(Test-Path -LiteralPath $ReviewFile)) {
        return $null
    }
    $review = Get-Content -LiteralPath $ReviewFile -Raw -ErrorAction SilentlyContinue
    if (!$review) {
        return $null
    }
    $jsonMatch = [regex]::Match(
        $review,
        '(?ms)FIX_PROMPT_FOR_IMPLEMENTER:\s*```json\s*(?<json>[\s\S]*?)\s*```',
        [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
    )
    if (-not $jsonMatch.Success) {
        return $null
    }
    $jsonText = $jsonMatch.Groups['json'].Value.Trim()
    try {
        return $jsonText | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        return $null
    }
}

function Test-IsUnderTasksQueuePath {
    param([string]$CandidatePath)
    if ([string]::IsNullOrWhiteSpace([string]$CandidatePath)) {
        return $false
    }
    $norm = ([string]$CandidatePath).Trim() -replace '\\', '/'
    if ($norm.StartsWith('./')) {
        $norm = $norm.Substring(2)
    }
    return $norm.StartsWith('tasks/', [System.StringComparison]::OrdinalIgnoreCase)
}

function Test-TaskMdScopeAllowsTasksQueue {
    param([string]$TaskMdPath)
    if (-not (Test-Path -LiteralPath $TaskMdPath)) {
        return $false
    }

    $lines = @(Get-Content -LiteralPath $TaskMdPath -ErrorAction SilentlyContinue)
    $inScope = $false
    foreach ($line in $lines) {
        if ($line -match '^\s*##\s') {
            if ($inScope) {
                break
            }
            if ($line -match '^\s*##\s+Files\s+in\s+scope\s*$') {
                $inScope = $true
            }
            continue
        }
        if ($inScope) {
            $trim = $line.Trim()
            if ($trim -match '^(?:[-*]|\d+\.)\s' -and $trim -match '(?i)tasks') {
                return $true
            }
        }
    }

    return $false
}

function Get-FixObjectTasksPathHits {
    param([object]$FixData)

    $hits = [System.Collections.Generic.List[string]]::new()
    if ($null -eq $FixData) {
        return @()
    }

    foreach ($f in @($FixData.files)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$f)) {
            $sf = ([string]$f).Trim()
            if (Test-IsUnderTasksQueuePath -CandidatePath $sf) {
                [void]$hits.Add($sf)
            }
        }
    }

    foreach ($c in @($FixData.changes)) {
        if (-not $c) {
            continue
        }
        foreach ($prop in 'path', 'file') {
            $v = $c.$prop
            if ($null -eq $v) {
                continue
            }
            $sv = ([string]$v).Trim()
            if ([string]::IsNullOrWhiteSpace($sv)) {
                continue
            }
            if (Test-IsUnderTasksQueuePath -CandidatePath $sv) {
                [void]$hits.Add($sv)
            }
        }
    }

    return @($hits | Select-Object -Unique)
}

function Get-FixMarkdownTasksPathHits {
    param([string]$PromptMarkdownPath)

    $hits = [System.Collections.Generic.List[string]]::new()
    if (-not (Test-Path -LiteralPath $PromptMarkdownPath)) {
        return @()
    }

    $lines = @(Get-Content -LiteralPath $PromptMarkdownPath -ErrorAction SilentlyContinue)
    $mode = 'none'
    foreach ($line in $lines) {
        if ($line -match '(?i)^\s*##\s') {
            if ($mode -eq 'files') {
                $mode = 'past_files'
            }
            elseif ($mode -eq 'changes') {
                $mode = 'past_changes'
            }

            if ($line -match '(?i)^\s*##\s+files\s+to\s+change\s*$') {
                $mode = 'files'
                continue
            }
            if ($line -match '(?i)^\s*##\s+changes\s*$') {
                $mode = 'changes'
                continue
            }
            continue
        }

        if ($mode -eq 'files') {
            if ($line -match '^\s*-\s+(.+)$') {
                $item = $Matches[1].Trim().Trim([char]0x0060).Trim()
                if (Test-IsUnderTasksQueuePath -CandidatePath $item) {
                    [void]$hits.Add($item)
                }
            }
            continue
        }

        if ($mode -eq 'changes') {
            if ($line -match '-\s*\([^)]*\)\s*`([^`]+)`') {
                $item = $Matches[1].Trim()
                if (Test-IsUnderTasksQueuePath -CandidatePath $item) {
                    [void]$hits.Add($item)
                }
            }
            continue
        }
    }

    return @($hits | Select-Object -Unique)
}

function Test-FixPromptTasksConflict {
    param(
        [object]$FixData,
        [string]$TaskMdPath
    )

    $hits = @(Get-FixObjectTasksPathHits -FixData $FixData)
    if ($hits.Count -eq 0) {
        return $false
    }

    if (Test-TaskMdScopeAllowsTasksQueue -TaskMdPath $TaskMdPath) {
        return $false
    }

    return $true
}

function Test-FixPromptArtifactsTasksConflict {
    param(
        [object]$FixData,
        [string]$PromptMarkdownPath,
        [string]$TaskMdPath
    )

    $set = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($p in @(Get-FixObjectTasksPathHits -FixData $FixData)) {
        [void]$set.Add($p)
    }
    foreach ($p in @(Get-FixMarkdownTasksPathHits -PromptMarkdownPath $PromptMarkdownPath)) {
        [void]$set.Add($p)
    }

    $hits = @($set)
    if ($hits.Count -eq 0) {
        return $false
    }

    if (Test-TaskMdScopeAllowsTasksQueue -TaskMdPath $TaskMdPath) {
        return $false
    }

    return $true
}

function Get-FixPromptArtifactTasksOffenders {
    param(
        [object]$FixData,
        [string]$PromptMarkdownPath
    )

    $set = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($p in @(Get-FixObjectTasksPathHits -FixData $FixData)) {
        [void]$set.Add($p)
    }
    foreach ($p in @(Get-FixMarkdownTasksPathHits -PromptMarkdownPath $PromptMarkdownPath)) {
        [void]$set.Add($p)
    }

    return @($set | Sort-Object)
}

function Stop-UnsafeQueueCleanup {
    param(
        [Parameter(Mandatory)][string[]]$OffendingPaths,
        [Parameter(Mandatory)][string]$HumanSummary,
        [Parameter(Mandatory)][string]$ConsoleLine,
        [Parameter(Mandatory)][string]$FinalReasonLine
    )

    $uniq = @(
        $OffendingPaths |
            Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } |
            Select-Object -Unique
    )

    Write-Warning "UNSAFE_QUEUE_CLEANUP: protected tasks/ queue conflict ($ConsoleLine). Paths: $($uniq -join ', ')"

    $resultPath = Join-Path $AiLoop "implementer_result.md"
    $detail = ($uniq | ForEach-Object { "- $_" }) -join "`n"
    $unsafeBody = @"
UNSAFE_QUEUE_CLEANUP

$HumanSummary

Offending paths:
$detail
"@
    $unsafeBody | Set-Content -Path $resultPath -Encoding UTF8

    $unsafeFinal = @"
STATUS: UNSAFE_QUEUE_CLEANUP
REASON: $FinalReasonLine
DETAIL: See .ai-loop/implementer_result.md
"@
    Write-FinalStatus $unsafeFinal
    Write-Host ""
    Write-Host "UNSAFE_QUEUE_CLEANUP: $ConsoleLine" -ForegroundColor Yellow
    exit 1
}

function Extract-FixPrompt {
    $codexReview = Join-Path $AiLoop "codex_review.md"
    $tmp = Join-Path $AiLoop "next_implementer_prompt.md"
    $taskMd = Join-Path $AiLoop "task.md"
    $ok = Extract-FixPromptFromFile -ReviewFile $codexReview -OutputPromptFile $tmp
    if ($ok) {
        $fixObj = Get-FixPromptJsonObjectFromReview -ReviewFile $codexReview
        if (Test-FixPromptArtifactsTasksConflict -FixData $fixObj -PromptMarkdownPath $tmp -TaskMdPath $taskMd) {
            $uniq = @(Get-FixPromptArtifactTasksOffenders -FixData $fixObj -PromptMarkdownPath $tmp)
            Stop-UnsafeQueueCleanup `
                -OffendingPaths $uniq `
                -HumanSummary "The Codex fix prompt references tasks/ paths that are not covered by the active task.md ## Files in scope section. The orchestrator halted before invoking the implementer." `
                -ConsoleLine "fix iteration halted (protected tasks/ paths in Codex fix prompt)" `
                -FinalReasonLine "Fix prompt targeted protected tasks/ queue paths outside the active task scope."
        }
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
    Write-Host 'Staging safe project paths...'

    Push-Location $ProjectRoot
    try {
        foreach ($rel in @(Get-SafeAddPathList)) {
            if ([string]::IsNullOrWhiteSpace($rel)) {
                continue
            }
            git add -- $rel.Trim() 2>$null
        }
    }
    finally {
        Pop-Location
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

function Get-WorkingTreeTasksPathsRelative {
    param([string]$ProjectRoot)

    $hits = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    Push-Location $ProjectRoot
    try {
        $gitDir = git rev-parse --git-dir 2>$null
        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace([string]$gitDir)) {
            return @()
        }

        foreach ($raw in @(git diff HEAD --name-only 2>$null)) {
            $line = ([string]$raw).Trim()
            if ([string]::IsNullOrWhiteSpace($line)) {
                continue
            }
            $norm = $line -replace '\\', '/'
            if ($norm.StartsWith('./')) {
                $norm = $norm.Substring(2)
            }
            if (Test-IsUnderTasksQueuePath -CandidatePath $norm) {
                [void]$hits.Add($norm)
            }
        }

        foreach ($raw in @(git ls-files --others --exclude-standard 2>$null)) {
            $line = ([string]$raw).Trim()
            if ([string]::IsNullOrWhiteSpace($line)) {
                continue
            }
            $norm = $line -replace '\\', '/'
            if ($norm.StartsWith('./')) {
                $norm = $norm.Substring(2)
            }
            if (Test-IsUnderTasksQueuePath -CandidatePath $norm) {
                [void]$hits.Add($norm)
            }
        }
    }
    finally {
        Pop-Location
    }

    return @($hits | Sort-Object)
}

function Test-WorkingTreeTasksConflictWithScope {
    param(
        [string]$ProjectRoot,
        [string]$TaskMdPath
    )

    if (Test-TaskMdScopeAllowsTasksQueue -TaskMdPath $TaskMdPath) {
        return $false
    }

    $paths = @(Get-WorkingTreeTasksPathsRelative -ProjectRoot $ProjectRoot)
    return ($paths.Count -gt 0)
}

function Commit-And-Push {
    Ensure-AiLoopFiles

    $taskMdGate = Join-Path $AiLoop "task.md"
    if (Test-WorkingTreeTasksConflictWithScope -ProjectRoot $ProjectRoot -TaskMdPath $taskMdGate) {
        $wtOff = @(Get-WorkingTreeTasksPathsRelative -ProjectRoot $ProjectRoot)
        Stop-UnsafeQueueCleanup `
            -OffendingPaths $wtOff `
            -HumanSummary "The git working tree still contains tasks/ paths while the active task.md ## Files in scope section does not cover tasks/. Resolve by reverting or staging those paths outside this loop, adding tasks/ (or the specific files) to scope, or committing manually before relying on Codex PASS." `
            -ConsoleLine "final gate blocked (tasks/ working-tree changes outside active scope)" `
            -FinalReasonLine "Working tree has tasks/ changes while active task scope omits tasks/."
    }

    Write-Host ""
    Write-Host "Preparing Git commit..."

    Write-Host "Running final test gate before commit..."
    Invoke-CommandToFile $TestCommand (Join-Path $AiLoop "test_output_before_commit.txt") | Out-Null

    if ($LASTEXITCODE -ne 0) {
        Write-FinalStatus "ABORTED: tests failed before commit. Push skipped."
        Write-Host "ABORTED: tests failed before commit. Push skipped."
        exit 5
    }

    Save-GitReviewArtifactsForCodex `
        -GitStatusOut (Join-Path $AiLoop "git_status.txt") `
        -DiffPatchOut (Join-Path $AiLoop "last_diff.patch") `
        -DiffStatOut (Join-Path $AiLoop "diff_summary.txt")

    Stage-SafeProjectFiles

    $staged = @(git diff --cached --name-only 2>$null)

    if (@($staged).Count -eq 0) {
        Write-Host "Nothing staged for commit under SafeAddPaths (no matching changes or nothing to stage)."
        return $false
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

    return $true
}

function Try-ResumeFromExistingReview {
    Ensure-AiLoopFiles

    if (!$Resume) {
        return $false
    }

    Write-Host ""
    Write-Host "Resume mode enabled."

    $nextNeutral = Join-Path $AiLoop "next_implementer_prompt.md"
    $codexReview = Join-Path $AiLoop "codex_review.md"

    if (Test-Path $nextNeutral) {
        Write-Host "Resuming from existing next_implementer_prompt.md..."
        $taskMd = Join-Path $AiLoop "task.md"
        $fixObjResume = Get-FixPromptJsonObjectFromReview -ReviewFile $codexReview
        if (Test-FixPromptArtifactsTasksConflict -FixData $fixObjResume -PromptMarkdownPath $nextNeutral -TaskMdPath $taskMd) {
            $uniqResume = @(Get-FixPromptArtifactTasksOffenders -FixData $fixObjResume -PromptMarkdownPath $nextNeutral)
            Stop-UnsafeQueueCleanup `
                -OffendingPaths $uniqResume `
                -HumanSummary "The Codex fix prompt references tasks/ paths that are not covered by the active task.md ## Files in scope section. The orchestrator halted before invoking the implementer." `
                -ConsoleLine "resume halted (protected tasks/ paths in existing fix prompt)" `
                -FinalReasonLine "Fix prompt targeted protected tasks/ queue paths outside the active task scope."
        }
        Run-ImplementerFix | Out-Null
        return $true
    }

    if (Test-Path $codexReview) {
        $codexVerdict = Get-CodexVerdict

        if ($codexVerdict -eq "PASS") {
            Write-Host "Existing Codex verdict is PASS. Running final test gate, commit, and push."
            $didCommit = Commit-And-Push
            if ($didCommit) {
                Write-FinalStatus "PASS from resume mode. Changes committed and pushed if NoPush was not enabled."
            }
            else {
                Write-FinalStatus "PASS from resume mode. Commit skipped - nothing staged under SafeAddPaths."
            }
            Write-Host "Final status: PASS"
            if ($WithWrapUp) {
                & "$PSScriptRoot\wrap_up_session.ps1"
            }
            try { & "$PSScriptRoot\show_token_report.ps1" } catch { Write-Warning "Token report failed: $_" }
            exit 0
        }

        Write-Host ""
        Write-Host "Codex verdict: FIX_REQUIRED"
        Write-Host "Extracting fix prompt for implementer..."

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
            Write-FinalStatus (
                "STATUS: FAILED`n" +
                "REASON: REVIEW_STARTED_ON_CLEAN_TREE`n" +
                "DETAIL: Working tree is clean before Codex review. Use scripts/ai_loop_task_first.ps1 when starting from scratch with an implementer pass, or make changes before calling REVIEW-only mode."
            )
            Write-Host ""
            Write-Host "Clean tree on iteration 1: skipping Codex. Prefer task-first (ai_loop_task_first.ps1) when the working tree has no changes yet." -ForegroundColor Yellow
            exit 6
        }
        Write-FinalStatus (
            "STATUS: FAILED`n" +
            "REASON: NO_CHANGES_AFTER_IMPLEMENTER_FIX`n" +
            "DETAIL: No working-tree changes before Codex review on iteration $i after the implementer fix pass."
        )
        Write-Host ""
        Write-Host ('Iteration ' + $i + ': working tree clean before Codex (implementer fix produced no git-visible changes). See .ai-loop\final_status.md') -ForegroundColor Yellow
        exit 7
    }

    Run-CodexReview | Out-Null

    try {
        $codexMd = Join-Path $AiLoop "codex_review.md"
        $combinedCodexCapture = ""
        if (Test-Path -LiteralPath $codexMd) {
            $combinedCodexCapture = Get-Content -LiteralPath $codexMd -Raw -ErrorAction SilentlyContinue
        }
        Register-CodexTokenUsageAttempt -CodexText $combinedCodexCapture -Iteration $i -TaskMdPath (Join-Path $AiLoop "task.md")
    }
    catch {
        Write-Warning "Codex token usage hook skipped: $($_.Exception.Message)"
    }

    $codexVerdict = Get-CodexVerdict

    if ($codexVerdict -eq "PASS") {
        Write-Host ""
        Write-Host "Codex verdict: PASS"

        $didCommit = Commit-And-Push

        if ($didCommit) {
            Write-FinalStatus "PASS after iteration $i. Codex=PASS. Changes committed and pushed if NoPush was not enabled."
        }
        else {
            Write-FinalStatus "PASS after iteration $i. Codex=PASS. Commit skipped - nothing staged under SafeAddPaths."
        }

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
        try { & "$PSScriptRoot\show_token_report.ps1" } catch { Write-Warning "Token report failed: $_" }
        exit 0
    }

    Write-Host ""
    Write-Host "Codex verdict: FIX_REQUIRED"
    Write-Host "Extracting fix prompt for implementer..."

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
