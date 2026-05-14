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
}
catch {
    Write-Warning "wrap_up_session: $_"
}
exit 0
