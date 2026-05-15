# $PSScriptRoot is empty when this file is dot-sourced from some -Command harnesses; fix to this file's directory.
$script:_RecordTokenUsageScriptDir = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($script:_RecordTokenUsageScriptDir)) {
    $script:_RecordTokenUsageScriptDir = Split-Path -LiteralPath $MyInvocation.MyCommand.Path -Parent
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
        [string]$Source = "unknown"
    )

    $scriptDir = ([string]$script:_RecordTokenUsageScriptDir).Trim()
    if ([string]::IsNullOrWhiteSpace($scriptDir)) {
        Write-Warning 'record_token_usage.ps1 could not resolve its script directory.'
        return
    }

    if (-not ([System.IO.Path]::IsPathRooted($scriptDir))) {
        $scriptDir = [System.IO.Path]::GetFullPath((Join-Path ([Environment]::CurrentDirectory) $scriptDir.TrimStart('\', '/')))
    } else {
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
            task_name           = $TaskName
            script_name         = $ScriptName
            iteration           = $Iteration
            provider            = $Provider
            model               = $Model
            input_tokens        = $InputTokens
            output_tokens       = $OutputTokens
            total_tokens        = $TotalTokens
            estimated_cost_usd  = $EstimatedCostUsd
            confidence          = $Confidence
            source              = $Source
            timestamp           = [datetime]::UtcNow.ToString("o")
        }

        $line = ($record | ConvertTo-Json -Compress -Depth 3)
        [System.IO.File]::AppendAllText($jsonlPath, $line + [Environment]::NewLine)
    }
    catch {
        Write-Warning $_.Exception.Message
        return
    }
}
