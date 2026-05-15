$ErrorActionPreference = "Continue"

function Get-NullableIntDisplay {
    param($Value)
    if ($null -eq $Value) { return "?" }
    return "$Value"
}

try {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    $jsonlPath = Join-Path $repoRoot '.ai-loop\token_usage.jsonl'

    if (-not (Test-Path -LiteralPath $jsonlPath)) {
        exit 0
    }

    $raw = Get-Content -LiteralPath $jsonlPath -ErrorAction Stop
    $nonBlankLines = @($raw | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($nonBlankLines.Count -eq 0) {
        exit 0
    }

    $records = @()
    foreach ($line in $nonBlankLines) {
        try {
            $records += ($line | ConvertFrom-Json)
        }
        catch {
            Write-Warning "Malformed JSONL line skipped."
        }
    }

    if ($records.Count -eq 0) {
        exit 0
    }

    $groups = $records | Group-Object -Property {
        $tn = $_.PSObject.Properties["task_name"]
        if ($tn) { [string]$tn.Value } else { "" }
    } | Sort-Object Name

    Write-Output "=============================="
    Write-Output "TOKEN USAGE REPORT"
    Write-Output "=============================="

    foreach ($g in $groups) {
        Write-Output "Task: $($g.Name)"
        foreach ($rec in $g.Group) {
            $scriptNm = ""
            $ts = ""
            $iter = ""
            $prov = ""
            $mod = ""
            $conf = ""
            $src = ""
            $inTok = $null
            $outTok = $null
            $totTok = $null

            foreach ($p in $rec.PSObject.Properties) {
                switch ($p.Name) {
                    "script_name" { $scriptNm = [string]$p.Value }
                    "timestamp" { $ts = [string]$p.Value }
                    "iteration" { $iter = "$($p.Value)" }
                    "provider" { $prov = [string]$p.Value }
                    "model" { $mod = [string]$p.Value }
                    "confidence" { $conf = [string]$p.Value }
                    "source" { $src = [string]$p.Value }
                    "input_tokens" { $inTok = $p.Value }
                    "output_tokens" { $outTok = $p.Value }
                    "total_tokens" { $totTok = $p.Value }
                }
            }

            Write-Output "  [$ts]  Script: $scriptNm  Iter: $iter"
            Write-Output "  Provider/model: $prov/$mod"
            Write-Output "  Tokens -- in: $(Get-NullableIntDisplay $inTok)  out: $(Get-NullableIntDisplay $outTok)  total: $(Get-NullableIntDisplay $totTok)"
            Write-Output "  Confidence: $conf   Source: $src"
        }
    }

    $sumIn = [long]0
    $sumOut = [long]0
    $sumTot = [long]0

    foreach ($rec in $records) {
        foreach ($p in $rec.PSObject.Properties) {
            if ($p.Name -eq "input_tokens" -and $null -ne $p.Value) {
                $sumIn += [long]$p.Value
            }
            elseif ($p.Name -eq "output_tokens" -and $null -ne $p.Value) {
                $sumOut += [long]$p.Value
            }
            elseif ($p.Name -eq "total_tokens" -and $null -ne $p.Value) {
                $sumTot += [long]$p.Value
            }
        }
    }

    Write-Output ""
    Write-Output "--- Totals (known records only) ---"
    Write-Output "  in: $sumIn   out: $sumOut   total: $sumTot"
    Write-Output "=============================="
}
catch {
    Write-Warning $_.Exception.Message
}

exit 0
