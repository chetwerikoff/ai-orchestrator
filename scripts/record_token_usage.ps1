# $PSScriptRoot is empty when this file is dot-sourced from some -Command harnesses; fix to this file's directory.
$script:_RecordTokenUsageScriptDir = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($script:_RecordTokenUsageScriptDir)) {
    $script:_RecordTokenUsageScriptDir = Split-Path -LiteralPath $MyInvocation.MyCommand.Path -Parent
}

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
        [string]$Quality = "unknown"
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
            quality             = $Quality
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
