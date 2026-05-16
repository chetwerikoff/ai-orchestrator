# $PSScriptRoot is empty when this file is dot-sourced from some -Command harnesses; fix to this file's directory.
$script:_RecordTokenUsageScriptDir = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($script:_RecordTokenUsageScriptDir)) {
    $script:_RecordTokenUsageScriptDir = Split-Path -LiteralPath $MyInvocation.MyCommand.Path -Parent
}

# Per-process dedupe for Write-CliCaptureTokenUsageIfParsed -DedupeId (same capture text twice for one logical call).
$script:_CliCaptureDedupeLastFpById = @{}

function ConvertFrom-CliTokenUsage {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Text
    )

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return $null
    }

    # (a) Claude API JSON — input_tokens + output_tokens
    $rxInApi = '"input_tokens"\s*:\s*(\d+)'
    $rxOutApi = '"output_tokens"\s*:\s*(\d+)'
    $mInA = [regex]::Match($Text, $rxInApi)
    $mOutA = [regex]::Match($Text, $rxOutApi)
    if ($mInA.Success -and $mOutA.Success) {
        $inTok = [long]$mInA.Groups[1].Value
        $outTok = [long]$mOutA.Groups[1].Value
        return @{
            InputTokens  = $inTok
            OutputTokens = $outTok
            TotalTokens  = $inTok + $outTok
            Source       = "api_response"
            Quality      = "exact"
        }
    }

    # (b) OpenAI / Codex API JSON — prompt_tokens + completion_tokens
    $mInB = [regex]::Match($Text, '"prompt_tokens"\s*:\s*(\d+)')
    $mOutB = [regex]::Match($Text, '"completion_tokens"\s*:\s*(\d+)')
    if ($mInB.Success -and $mOutB.Success) {
        $inTok = [long]$mInB.Groups[1].Value
        $outTok = [long]$mOutB.Groups[1].Value
        return @{
            InputTokens  = $inTok
            OutputTokens = $outTok
            TotalTokens  = $inTok + $outTok
            Source       = "api_response"
            Quality      = "exact"
        }
    }

    # (c) Claude CLI plain-text log lines
    $mInC = [regex]::Match($Text, '(?im)^\s*Input\s+tokens:\s*(\d+)\s*$')
    $mOutC = [regex]::Match($Text, '(?im)^\s*Output\s+tokens:\s*(\d+)\s*$')
    if ($mInC.Success -and $mOutC.Success) {
        $inTok = [long]$mInC.Groups[1].Value
        $outTok = [long]$mOutC.Groups[1].Value
        return @{
            InputTokens  = $inTok
            OutputTokens = $outTok
            TotalTokens  = $inTok + $outTok
            Source       = "cli_log"
            Quality      = "exact"
        }
    }

    # (d) Codex CLI summary — total-only "tokens used" (same line or next line)
    $mCodex1 = [regex]::Match($Text, '(?im)(?:^|\r?\n)\s*tokens\s+used\s+([\d,]+)\s*(?:\r?\n|$)')
    if ($mCodex1.Success) {
        $totalStr = ($mCodex1.Groups[1].Value -replace ',', '').Trim()
        if ($totalStr -match '^\d+$') {
            $totalTok = [long]$totalStr
            return @{
                InputTokens  = $null
                OutputTokens = $null
                TotalTokens  = $totalTok
                Source       = "cli_log"
                Quality      = "exact"
            }
        }
    }

    $mCodex2 = [regex]::Match($Text, '(?im)(?:^|\r?\n)\s*tokens\s+used\s*\r?\n\s*([\d,]+)\s*(?:\r?\n|$)')
    if ($mCodex2.Success) {
        $totalStr = ($mCodex2.Groups[1].Value -replace ',', '').Trim()
        if ($totalStr -match '^\d+$') {
            $totalTok = [long]$totalStr
            return @{
                InputTokens  = $null
                OutputTokens = $null
                TotalTokens  = $totalTok
                Source       = "cli_log"
                Quality      = "exact"
            }
        }
    }

    return $null
}

function Get-TaskHeadingForJournal {
    param([string]$TaskFilePath)

    if ([string]::IsNullOrWhiteSpace($TaskFilePath) -or -not (Test-Path -LiteralPath $TaskFilePath)) {
        return ""
    }
    try {
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

function Resolve-RepoRootFromProjectHint {
    param([string]$ProjectRootHint)

    if ([string]::IsNullOrWhiteSpace($ProjectRootHint)) {
        return ""
    }
    try {
        $r = [System.IO.Path]::GetFullPath(($ProjectRootHint.Trim()))
        return $r
    }
    catch {
        return ""
    }
}

function Read-AiLoopChainObject {
    param([string]$ProjectRoot)
    if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
        return $null
    }
    $chainPath = [System.IO.Path]::Combine($ProjectRoot.Trim(), '.ai-loop', 'chain.json')
    if (-not (Test-Path -LiteralPath $chainPath)) {
        return $null
    }
    try {
        $raw = Get-Content -LiteralPath $chainPath -Raw -ErrorAction Stop
        return ($raw | ConvertFrom-Json -ErrorAction Stop)
    }
    catch {
        Write-Warning "chain.json read skipped (non-blocking): $($_.Exception.Message)"
        return $null
    }
}

function Initialize-AiLoopPlannerChain {
    param(
        [Parameter(Mandatory = $true)][string]$ProjectRoot,
        [switch]$ForceNewChain,
        [switch]$Manual,
        [string]$PlannerCommand = "",
        [string]$PlannerModel = "",
        [string]$ReviewerCommand = "",
        [string]$ReviewerModel = "",
        [int]$MaxReviewIters = 0,
        [bool]$NoRevision = $false,
        [string]$TaskFileRelative = ".ai-loop/task.md"
    )

    $result = @{ Wrote = $false; ChainId = "" }
    try {
        $root = [System.IO.Path]::GetFullPath($ProjectRoot.Trim())
        $loopDir = [System.IO.Path]::Combine($root, '.ai-loop')
        if (-not (Test-Path -LiteralPath $loopDir)) {
            New-Item -ItemType Directory -Force -Path $loopDir | Out-Null
        }
        $chainPath = [System.IO.Path]::Combine($loopDir, 'chain.json')
        if ((Test-Path -LiteralPath $chainPath) -and -not $ForceNewChain) {
            Write-Warning "[chain] chain.json already exists; keeping existing planner_chain_id (use -ForceNewChain to replace)."
            return $result
        }

        $taskPath = if ([System.IO.Path]::IsPathRooted($TaskFileRelative)) {
            $TaskFileRelative
        }
        else {
            [System.IO.Path]::Combine($root, $TaskFileRelative.TrimStart('\', '/'))
        }
        $taskHead = Get-TaskHeadingForJournal -TaskFilePath $taskPath

        if ($Manual) {
            $pf = @{
                planner_command   = "manual"
                planner_model     = ""
                reviewer_command  = ""
                reviewer_model     = ""
                max_review_iters  = 0
                no_revision       = $true
            }
        }
        else {
            $pf = @{
                planner_command   = $PlannerCommand
                planner_model     = $PlannerModel
                reviewer_command  = $ReviewerCommand
                reviewer_model     = $ReviewerModel
                max_review_iters  = $MaxReviewIters
                no_revision       = $NoRevision
            }
        }

        $id = ([guid]::NewGuid().ToString("N").Substring(0, 8))
        $obj = [ordered]@{
            planner_chain_id = $id
            task_name        = $taskHead
            started_at_utc   = [datetime]::UtcNow.ToString("o")
            planner_form     = $pf
        }
        $jsonText = ($obj | ConvertTo-Json -Compress -Depth 6)
        [System.IO.File]::WriteAllText($chainPath, $jsonText + [Environment]::NewLine)
        $result.Wrote = $true
        $result.ChainId = $id
    }
    catch {
        Write-Warning "[chain] Initialize-AiLoopPlannerChain failed (non-blocking): $($_.Exception.Message)"
    }
    return $result
}

function Update-AiLoopPlannerChainTaskName {
    param(
        [Parameter(Mandatory = $true)][string]$ProjectRoot,
        [Parameter(Mandatory = $true)][string]$TaskFilePath
    )
    try {
        $root = [System.IO.Path]::GetFullPath($ProjectRoot.Trim())
        $chainPath = [System.IO.Path]::Combine($root, '.ai-loop', 'chain.json')
        if (-not (Test-Path -LiteralPath $chainPath)) {
            return
        }
        $heading = Get-TaskHeadingForJournal -TaskFilePath $TaskFilePath
        $raw = Get-Content -LiteralPath $chainPath -Raw -ErrorAction Stop
        $o = $raw | ConvertFrom-Json -ErrorAction Stop
        $o | Add-Member -NotePropertyName task_name -NotePropertyValue $heading -Force
        $jsonText = ($o | ConvertTo-Json -Depth 10 -Compress)
        [System.IO.File]::WriteAllText($chainPath, $jsonText + [Environment]::NewLine)
    }
    catch {
        Write-Warning "[chain] Update-AiLoopPlannerChainTaskName failed (non-blocking): $($_.Exception.Message)"
    }
}

function Archive-AiLoopChainIfPresent {
    param([Parameter(Mandatory = $true)][string]$ProjectRoot)
    try {
        $root = [System.IO.Path]::GetFullPath($ProjectRoot.Trim())
        $chainPath = [System.IO.Path]::Combine($root, '.ai-loop', 'chain.json')
        if (-not (Test-Path -LiteralPath $chainPath)) {
            return
        }
        $raw = Get-Content -LiteralPath $chainPath -Raw -ErrorAction Stop
        $o = $raw | ConvertFrom-Json -ErrorAction Stop
        $id = [string]$o.planner_chain_id
        if ([string]::IsNullOrWhiteSpace($id)) {
            $id = "unknown"
        }
        $destDir = [System.IO.Path]::Combine($root, '.ai-loop', '_debug', 'chains')
        if (-not (Test-Path -LiteralPath $destDir)) {
            New-Item -ItemType Directory -Force -Path $destDir | Out-Null
        }
        $dest = [System.IO.Path]::Combine($destDir, "$id.json")
        [System.IO.File]::WriteAllText($dest, $raw.TrimEnd() + [Environment]::NewLine)
        Remove-Item -LiteralPath $chainPath -Force -ErrorAction Stop
    }
    catch {
        Write-Warning "[chain] Archive-AiLoopChainIfPresent failed (non-blocking): $($_.Exception.Message)"
    }
}

function Write-CliCaptureTokenUsageIfParsed {
    param(
        [AllowEmptyString()][string]$CapturedText,
        [Parameter(Mandatory = $true)][string]$ScriptName,
        [Parameter(Mandatory = $true)][string]$Provider,
        [string]$Model = "",
        [int]$Iteration = 0,
        [string]$ProjectRootHint = "",
        [string]$DedupeId = "",
        [string]$PlannerChainId = "",
        [string]$Phase = "",
        [string]$Role = "",
        [int]$FixIterationIndex = -1,
        [int]$PromptBytes = 0,
        [string]$PlannerCommandFromChain = "",
        [string]$ReviewerCommandFromChain = ""
    )

    try {
        if (-not $CapturedText) {
            $CapturedText = ""
        }

        if ([string]::IsNullOrWhiteSpace($Phase) -and $null -ne $env:AI_LOOP_TOKEN_PHASE) {
            $Phase = [string]$env:AI_LOOP_TOKEN_PHASE
        }
        if ([string]::IsNullOrWhiteSpace($Role) -and $null -ne $env:AI_LOOP_TOKEN_ROLE) {
            $Role = [string]$env:AI_LOOP_TOKEN_ROLE
        }
        if ($FixIterationIndex -lt 0 -and $null -ne $env:AI_LOOP_TOKEN_FIX_ITER) {
            $efi = [string]$env:AI_LOOP_TOKEN_FIX_ITER
            if ($efi -match '^-?\d+$') {
                $FixIterationIndex = [int]$efi
            }
        }

        $hint = Resolve-RepoRootFromProjectHint -ProjectRootHint $ProjectRootHint
        $chainObj = $null
        if (-not [string]::IsNullOrWhiteSpace($hint)) {
            $chainObj = Read-AiLoopChainObject -ProjectRoot $hint
        }

        $chainIdUse = $PlannerChainId
        if ([string]::IsNullOrWhiteSpace($chainIdUse) -and $null -ne $chainObj) {
            $chainIdUse = [string]$chainObj.planner_chain_id
        }

        $mriFromChain = $null
        $nrFromChain = $null
        if ($null -ne $chainObj -and $chainObj.planner_form) {
            $pf = $chainObj.planner_form
            if ([string]::IsNullOrWhiteSpace($PlannerCommandFromChain) -and ($pf.PSObject.Properties.Name -contains 'planner_command')) {
                $PlannerCommandFromChain = [string]$pf.planner_command
            }
            if ([string]::IsNullOrWhiteSpace($ReviewerCommandFromChain) -and ($pf.PSObject.Properties.Name -contains 'reviewer_command')) {
                $ReviewerCommandFromChain = [string]$pf.reviewer_command
            }
            if ($pf.PSObject.Properties.Name -contains 'max_review_iters') {
                try {
                    $mriFromChain = [int]$pf.max_review_iters
                }
                catch { }
            }
            if ($pf.PSObject.Properties.Name -contains 'no_revision') {
                try {
                    $nrFromChain = [bool]$pf.no_revision
                }
                catch { }
            }
        }

        if ($null -eq (Get-Command -Name ConvertFrom-CliTokenUsage -ErrorAction SilentlyContinue)) {
            return
        }
        $parsed = ConvertFrom-CliTokenUsage -Text $CapturedText

        $dedupeKeyTrimmed = ""
        $dedupeFp = ""
        $runDedupe = -not [string]::IsNullOrWhiteSpace($DedupeId)
        if ($runDedupe) {
            $enc = New-Object System.Text.UTF8Encoding $false
            $bytes = $enc.GetBytes([string]$CapturedText)
            $sha = [System.Security.Cryptography.SHA256]::Create()
            try {
                $hash = $sha.ComputeHash($bytes)
            }
            finally {
                $sha.Dispose()
            }
            $dedupeFp = [BitConverter]::ToString($hash) -replace '-', ''
            $dedupeKeyTrimmed = $DedupeId.Trim()
            if ($script:_CliCaptureDedupeLastFpById.ContainsKey($dedupeKeyTrimmed) -and $script:_CliCaptureDedupeLastFpById[$dedupeKeyTrimmed] -eq $dedupeFp) {
                return
            }
        }

        if ($null -eq (Get-Command -Name Write-TokenUsageRecord -ErrorAction SilentlyContinue)) {
            return
        }

        $taskPath = ""
        if (-not [string]::IsNullOrWhiteSpace($hint)) {
            $candidate = [System.IO.Path]::Combine($hint, ".ai-loop", "task.md")
            if (Test-Path -LiteralPath $candidate) {
                $taskPath = $candidate
            }
        }
        $heading = Get-TaskHeadingForJournal -TaskFilePath $taskPath

        $roleLc = ($Role + "").ToLowerInvariant()
        $plCmdOut = ""
        $revCmdOut = ""
        $mriOut = $null
        $nrOut = $null
        if ($roleLc -eq 'planner' -or $roleLc -eq 'planner_revision') {
            $plCmdOut = $PlannerCommandFromChain
            if ($null -ne $mriFromChain) { $mriOut = $mriFromChain }
            if ($null -ne $nrFromChain) { $nrOut = $nrFromChain }
        }
        elseif ($roleLc -eq 'planner_review') {
            $revCmdOut = $ReviewerCommandFromChain
        }

        if ($null -ne $parsed) {
            Write-TokenUsageRecord `
                -TaskName $heading `
                -ScriptName $ScriptName `
                -Iteration $Iteration `
                -Provider $Provider `
                -Model $Model `
                -InputTokens $parsed.InputTokens `
                -OutputTokens $parsed.OutputTokens `
                -TotalTokens $parsed.TotalTokens `
                -Confidence "unknown" `
                -Source $parsed.Source `
                -Quality $parsed.Quality `
                -PlannerChainId $chainIdUse `
                -Phase $Phase `
                -Role $Role `
                -FixIterationIndex $(if ($FixIterationIndex -ge 0) { $FixIterationIndex } else { -1 }) `
                -PromptBytes $PromptBytes `
                -PlannerCommandRow $plCmdOut `
                -ReviewerCommandRow $revCmdOut `
                -MaxReviewItersRow $mriOut `
                -NoRevisionRow $nrOut
            if ($runDedupe -and $dedupeKeyTrimmed -ne "" -and $dedupeFp -ne "") {
                $script:_CliCaptureDedupeLastFpById[$dedupeKeyTrimmed] = $dedupeFp
            }
            return
        }

        $wantsMeta = (-not [string]::IsNullOrWhiteSpace($Phase)) -or (-not [string]::IsNullOrWhiteSpace($Role)) -or (-not [string]::IsNullOrWhiteSpace($chainIdUse))
        if ($PromptBytes -gt 0 -and $wantsMeta) {
            Write-TokenUsageRecord `
                -TaskName $heading `
                -ScriptName $ScriptName `
                -Iteration $Iteration `
                -Provider $Provider `
                -Model $Model `
                -InputTokens $null `
                -OutputTokens $null `
                -TotalTokens $null `
                -Confidence "unknown" `
                -Source "cli_capture_unparsed" `
                -Quality "unknown" `
                -PlannerChainId $chainIdUse `
                -Phase $Phase `
                -Role $Role `
                -FixIterationIndex $(if ($FixIterationIndex -ge 0) { $FixIterationIndex } else { -1 }) `
                -PromptBytes $PromptBytes `
                -PlannerCommandRow $plCmdOut `
                -ReviewerCommandRow $revCmdOut `
                -MaxReviewItersRow $mriOut `
                -NoRevisionRow $nrOut
            if ($runDedupe -and $dedupeKeyTrimmed -ne "" -and $dedupeFp -ne "") {
                $script:_CliCaptureDedupeLastFpById[$dedupeKeyTrimmed] = $dedupeFp
            }
        }
    }
    catch {
        Write-Warning "Token usage wrapper capture skipped (non-blocking): $($_.Exception.Message)"
    }
}

function Write-TokenUsageRecord {
    param(
        [string]$TaskName = "",
        [string]$ScriptName = "",
        [int]$Iteration = 0,
        [string]$Provider = "unknown",
        [string]$Model = "",
        $InputTokens = $null,
        $OutputTokens = $null,
        $TotalTokens = $null,
        $EstimatedCostUsd = $null,
        [string]$Confidence = "unknown",
        [string]$Source = "unknown",
        [string]$Quality = "unknown",
        [string]$PlannerChainId = "",
        [string]$Phase = "",
        [string]$Role = "",
        [int]$FixIterationIndex = -1,
        [int]$PromptBytes = 0,
        [string]$PlannerCommandRow = "",
        [string]$ReviewerCommandRow = "",
        [object]$MaxReviewItersRow = $null,
        [object]$NoRevisionRow = $null
    )

    $scriptDir = ([string]$script:_RecordTokenUsageScriptDir).Trim()
    if ([string]::IsNullOrWhiteSpace($scriptDir)) {
        Write-Warning 'record_token_usage.ps1 could not resolve its script directory.'
        return
    }

    if (-not ([System.IO.Path]::IsPathRooted($scriptDir))) {
        $scriptDir = [System.IO.Path]::GetFullPath((Join-Path ([Environment]::CurrentDirectory) $scriptDir.TrimStart('\', '/')))
    }
    else {
        $scriptDir = [System.IO.Path]::GetFullPath($scriptDir)
    }

    $repoRoot = Split-Path $scriptDir -Parent

    # Join-Path ignores -Path when -ChildPath is relative and starts with '.' (pwsh); use Combine for .ai-loop.
    $jsonlPath = [System.IO.Path]::Combine($repoRoot, '.ai-loop', 'token_usage.jsonl')

    try {
        $loopDir = [System.IO.Path]::GetDirectoryName($jsonlPath)
        if (-not (Test-Path -LiteralPath $loopDir)) {
            New-Item -ItemType Directory -Force -Path $loopDir | Out-Null
        }

        $record = [ordered]@{
            task_name          = $TaskName
            script_name        = $ScriptName
            iteration          = $Iteration
            provider           = $Provider
            model              = $Model
            input_tokens       = $InputTokens
            output_tokens      = $OutputTokens
            total_tokens       = $TotalTokens
            estimated_cost_usd = $EstimatedCostUsd
            confidence         = $Confidence
            source             = $Source
            quality            = $Quality
            timestamp          = [datetime]::UtcNow.ToString("o")
        }
        if (-not [string]::IsNullOrWhiteSpace($PlannerChainId)) {
            $record.planner_chain_id = $PlannerChainId
        }
        if (-not [string]::IsNullOrWhiteSpace($Phase)) {
            $record.phase = $Phase
        }
        if (-not [string]::IsNullOrWhiteSpace($Role)) {
            $record.role = $Role
        }
        if ($FixIterationIndex -ge 0) {
            $record.fix_iteration_index = $FixIterationIndex
        }
        if ($PromptBytes -gt 0) {
            $record.prompt_bytes = $PromptBytes
        }
        $roleLc = ($Role + "").ToLowerInvariant()
        if ($roleLc -eq 'planner' -or $roleLc -eq 'planner_revision') {
            if (-not [string]::IsNullOrWhiteSpace($PlannerCommandRow)) {
                $record.planner_command = $PlannerCommandRow
            }
            if ($null -ne $MaxReviewItersRow) {
                $record.max_review_iters = [int]$MaxReviewItersRow
            }
            if ($null -ne $NoRevisionRow) {
                $record.no_revision = [bool]$NoRevisionRow
            }
        }
        if ($roleLc -eq 'planner_review' -and -not [string]::IsNullOrWhiteSpace($ReviewerCommandRow)) {
            $record.reviewer_command = $ReviewerCommandRow
        }

        $line = ($record | ConvertTo-Json -Compress -Depth 6)
        [System.IO.File]::AppendAllText($jsonlPath, $line + [Environment]::NewLine)
    }
    catch {
        Write-Warning $_.Exception.Message
        return
    }
}
