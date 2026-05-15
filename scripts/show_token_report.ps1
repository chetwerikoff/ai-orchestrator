$ErrorActionPreference = "Continue"

function Get-NullableIntZero {
    param($Value)
    if ($null -eq $Value) {
        return 0L
    }
    try {
        return [long]$Value
    }
    catch {
        return 0L
    }
}

function Parse-RecordsFromJsonl {
    param([string[]]$Lines)
    $list = New-Object System.Collections.Generic.List[object]
    foreach ($line in $Lines) {
        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }
        try {
            $list.Add(($line | ConvertFrom-Json -ErrorAction Stop))
        }
        catch {
            continue
        }
    }
    return $list.ToArray()
}

function Get-TimestampComparable {
    param($Record)
    $ts = ""
    foreach ($p in $Record.PSObject.Properties) {
        if ($p.Name -eq "timestamp") {
            $ts = [string]$p.Value
            break
        }
    }
    if ([string]::IsNullOrWhiteSpace($ts)) {
        return ""
    }
    return $ts
}

function Sum-TokensForRecord {
    param($Record)
    $inTok = 0L
    $outTok = 0L
    $totTok = 0L
    foreach ($p in $Record.PSObject.Properties) {
        if ($p.Name -eq "input_tokens" -and $null -ne $p.Value) {
            $inTok = Get-NullableIntZero -Value $p.Value
        }
        elseif ($p.Name -eq "output_tokens" -and $null -ne $p.Value) {
            $outTok = Get-NullableIntZero -Value $p.Value
        }
        elseif ($p.Name -eq "total_tokens" -and $null -ne $p.Value) {
            $totTok = Get-NullableIntZero -Value $p.Value
        }
    }
    if ($totTok -eq 0L -and ($inTok -ne 0L -or $outTok -ne 0L)) {
        $totTok = $inTok + $outTok
    }
    return @{
        In  = $inTok
        Out = $outTok
        Tot = $totTok
    }
}

function Get-RecordField {
    param(
        $Record,
        [string]$Name
    )
    foreach ($p in $Record.PSObject.Properties) {
        if ($p.Name -eq $Name) {
            return [string]$p.Value
        }
    }
    return ""
}

$consoleLines = New-Object System.Collections.Generic.List[string]

try {
    $scriptDir = $PSScriptRoot
    if ([string]::IsNullOrWhiteSpace($scriptDir)) {
        $scriptDir = Split-Path -LiteralPath $MyInvocation.MyCommand.Path -Parent
    }
    $repoRoot = Split-Path $scriptDir -Parent
    $jsonlPath = [System.IO.Path]::Combine($repoRoot, '.ai-loop', 'token_usage.jsonl')

    if (-not (Test-Path -LiteralPath $jsonlPath)) {
        $consoleLines.Add("No token usage records found.")
    }
    else {
        $raw = Get-Content -LiteralPath $jsonlPath -ErrorAction SilentlyContinue
        $records = Parse-RecordsFromJsonl -Lines @($raw)

        if ($records.Count -eq 0) {
            $consoleLines.Add("No token usage records found.")
        }
        else {
            $taskName = "unknown"
            $scriptName = "unknown"
            $bestTs = ""
            $bestIdx = -1
            for ($ri = 0; $ri -lt $records.Count; $ri++) {
                $ts = Get-TimestampComparable -Record $records[$ri]
                if (-not [string]::IsNullOrWhiteSpace($ts) -and $ts -gt $bestTs) {
                    $bestTs = $ts
                    $bestIdx = $ri
                }
            }
            $srcRec = if ($bestIdx -ge 0) { $records[$bestIdx] } else { $records[$records.Count - 1] }
            $tnH = Get-RecordField -Record $srcRec -Name "task_name"
            if (-not [string]::IsNullOrWhiteSpace($tnH)) {
                $taskName = $tnH
            }
            $snH = Get-RecordField -Record $srcRec -Name "script_name"
            if (-not [string]::IsNullOrWhiteSpace($snH)) {
                $scriptName = $snH
            }

            $sumIn = [long]0
            $sumOut = [long]0
            $sumTot = [long]0

            foreach ($rec in $records) {
                $s = Sum-TokensForRecord -Record $rec
                $sumIn += $s.In
                $sumOut += $s.Out
                $sumTot += $s.Tot
            }

            $modelAgg = @{}
            foreach ($rec in $records) {
                $mod = Get-RecordField -Record $rec -Name "model"
                if ([string]::IsNullOrWhiteSpace($mod)) {
                    $mod = "unknown"
                }
                $s = Sum-TokensForRecord -Record $rec
                if (-not $modelAgg.ContainsKey($mod)) {
                    $modelAgg[$mod] = @{ In = 0L; Out = 0L; Tot = 0L }
                }
                $modelAgg[$mod].In += $s.In
                $modelAgg[$mod].Out += $s.Out
                $modelAgg[$mod].Tot += $s.Tot
            }

            $iterModelAgg = @{}
            foreach ($rec in $records) {
                $iterVal = 0
                foreach ($p in $rec.PSObject.Properties) {
                    if ($p.Name -eq "iteration") {
                        try {
                            $iterVal = [int]$p.Value
                        }
                        catch {
                            $iterVal = 0
                        }
                        break
                    }
                }
                $mod = Get-RecordField -Record $rec -Name "model"
                if ([string]::IsNullOrWhiteSpace($mod)) {
                    $mod = "unknown"
                }
                $key = "$iterVal`t$mod"
                $s = Sum-TokensForRecord -Record $rec
                if (-not $iterModelAgg.ContainsKey($key)) {
                    $iterModelAgg[$key] = @{
                        Iter  = $iterVal
                        Model = $mod
                        In    = 0L
                        Out   = 0L
                        Tot   = 0L
                    }
                }
                $iterModelAgg[$key].In += $s.In
                $iterModelAgg[$key].Out += $s.Out
                $iterModelAgg[$key].Tot += $s.Tot
            }

            $consoleLines.Add("==============================")
            $consoleLines.Add("TOKEN USAGE REPORT")
            $consoleLines.Add("==============================")
            $consoleLines.Add("Task: $taskName")
            $consoleLines.Add("Script: $scriptName")
            $consoleLines.Add("")
            $consoleLines.Add("Total:  in: $sumIn   out: $sumOut   total: $sumTot")
            $consoleLines.Add("")
            $consoleLines.Add("By model:")
            foreach ($mk in ($modelAgg.Keys | Sort-Object)) {
                $v = $modelAgg[$mk]
                $consoleLines.Add("  $mk  in: $($v.In)  out: $($v.Out)  total: $($v.Tot)")
            }
            $consoleLines.Add("")
            $consoleLines.Add("By iteration:")
            $iterGroups = @($iterModelAgg.Values | Sort-Object Iter, Model)
            foreach ($row in $iterGroups) {
                $consoleLines.Add("  iter $($row.Iter)  model $($row.Model)  in: $($row.In)  out: $($row.Out)  total: $($row.Tot)")
            }
            $consoleLines.Add("==============================")
        }
    }
}
catch {
    Write-Warning $_.Exception.Message
    if ($consoleLines.Count -eq 0) {
        $consoleLines.Add("No token usage records found.")
    }
}

foreach ($ln in $consoleLines) {
    try {
        Write-Host $ln
    }
    catch {
        Write-Warning "Console write failed: $($_.Exception.Message)"
    }
}

try {
    $sdForSummary = $PSScriptRoot
    if ([string]::IsNullOrWhiteSpace($sdForSummary) -and $MyInvocation.MyCommand.Path) {
        $sdForSummary = Split-Path -LiteralPath $MyInvocation.MyCommand.Path -Parent
    }
    if (-not [string]::IsNullOrWhiteSpace($sdForSummary)) {
        $rrSum = Split-Path $sdForSummary -Parent
        $sumPath = [System.IO.Path]::Combine($rrSum, '.ai-loop', 'token_usage_summary.md')
        $body = (($consoleLines.ToArray()) -join [Environment]::NewLine) + [Environment]::NewLine
        [System.IO.File]::WriteAllText($sumPath, $body)
    }
}
catch {
    Write-Warning "token_usage_summary.md write failed: $($_.Exception.Message)"
}

exit 0
