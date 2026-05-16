<#
.SYNOPSIS
    Writes `.ai-loop\_debug\session_draft.md` via read-only ingest of orchestrator artefacts (non-fatal).
#>

try {
    $ErrorActionPreference = "Stop"
    $projectRoot = (Resolve-Path ".").Path
    $aiLoop = Join-Path $projectRoot ".ai-loop"
    $testPath = Join-Path $aiLoop "test_output.txt"
    $summaryPath = Join-Path $aiLoop "implementer_summary.md"
    $draftPath = Join-Path $aiLoop "_debug\session_draft.md"

    if (-not (Test-Path $aiLoop)) {
        New-Item -ItemType Directory -Force -Path $aiLoop | Out-Null
    }
    New-Item -ItemType Directory -Force -Path (Split-Path $draftPath -Parent) | Out-Null

    function Get-ChangedFilesSectionFromSummary {
        param([string]$Content)
        if ([string]::IsNullOrWhiteSpace($Content)) {
            return "(none recorded)"
        }
        $lines = $Content -split "`r?`n"
        $in = $false
        $block = New-Object System.Collections.Generic.List[string]
        foreach ($ln in $lines) {
            if ($ln -match '^\#\#\s+Changed files\b') {
                $in = $true
                continue
            }
            if ($in -and $ln -match '^\#\#') {
                break
            }
            if ($in) {
                [void]$block.Add($ln)
            }
        }
        $trimmedBody = (($block.ToArray()) -join "`n").Trim()
        if ([string]::IsNullOrWhiteSpace($trimmedBody)) {
            return "(none recorded)"
        }
        return $trimmedBody
    }

    $summaryTxt = ""
    if (Test-Path -LiteralPath $summaryPath) {
        $summaryTxt = Get-Content -LiteralPath $summaryPath -Raw -Encoding UTF8
    }
    $changed = Get-ChangedFilesSectionFromSummary -Content $summaryTxt

    $failureLines = @()
    if (Test-Path -LiteralPath $testPath) {
        $failureLines = @(Get-Content -LiteralPath $testPath -Encoding UTF8 |
            Where-Object { $_ -match '\bFAILED\b' })
    }
    $failuresTxt = "(none)"
    if ($failureLines.Count -gt 0) {
        $failuresTxt = ($failureLines -join "`n").TrimEnd()
        if ([string]::IsNullOrWhiteSpace($failuresTxt)) {
            $failuresTxt = "(none)"
        }
    }

    $ts = ([DateTime]::UtcNow.ToString("o"))
    $em = [char]0x2014
    @"
# Session draft $em $ts

## Changed files
$changed

## Failures observed
$failuresTxt

## Notes
(fill in manually before promoting)
"@ | Set-Content -LiteralPath $draftPath -Encoding UTF8

    # Non-blocking token ledger row (phase/role wrap_up; no fix_iteration_index; prompt_bytes omitted when 0).
    try {
        $ledgerTask = ""
        $ledgerChain = ""
        $chainPathLedger = [System.IO.Path]::Combine($aiLoop, "chain.json")
        if (Test-Path -LiteralPath $chainPathLedger) {
            try {
                $cj = Get-Content -LiteralPath $chainPathLedger -Raw -Encoding UTF8 | ConvertFrom-Json
                if ($null -ne $cj.planner_chain_id) {
                    $ledgerChain = [string]$cj.planner_chain_id
                }
                if ($null -ne $cj.task_name) {
                    $ledgerTask = [string]$cj.task_name
                }
            }
            catch {
            }
        }
        $jsonlPath = [System.IO.Path]::Combine($projectRoot, ".ai-loop", "token_usage.jsonl")
        $loopDirTok = [System.IO.Path]::GetDirectoryName($jsonlPath)
        if (-not (Test-Path -LiteralPath $loopDirTok)) {
            New-Item -ItemType Directory -Force -Path $loopDirTok | Out-Null
        }
        $recRow = [ordered]@{
            task_name          = $ledgerTask
            script_name        = "wrap_up_session.ps1"
            iteration          = 0
            provider           = "unknown"
            model              = ""
            input_tokens       = $null
            output_tokens      = $null
            total_tokens       = $null
            estimated_cost_usd = $null
            confidence         = "unknown"
            source             = "unknown"
            quality            = "unknown"
            timestamp          = [datetime]::UtcNow.ToString("o")
            phase              = "wrap_up"
            role               = "wrap_up"
        }
        if (-not [string]::IsNullOrWhiteSpace($ledgerChain)) {
            $recRow.planner_chain_id = $ledgerChain
        }
        $lineTok = ($recRow | ConvertTo-Json -Compress -Depth 6)
        [System.IO.File]::AppendAllText($jsonlPath, $lineTok + [Environment]::NewLine)
    }
    catch {
        Write-Warning "wrap_up_session token ledger: $_"
    }
}
catch {
    Write-Warning "wrap_up_session: $_"
}
exit 0
