param(
    [switch]$ExportReport,
    [string]$LimitsYamlPath = "",
    [switch]$ByChain,
    [switch]$GroupByChain
)

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

function Get-RecordIntField {
    param(
        $Record,
        [string]$Name
    )
    foreach ($p in $Record.PSObject.Properties) {
        if ($p.Name -eq $Name -and $null -ne $p.Value) {
            try {
                return [long]$p.Value
            }
            catch {
                return 0L
            }
        }
    }
    return 0L
}

function Format-PlannerFormDecomposedLines {
    param($GroupRecords)

    $plRow = $null
    $revRow = $null
    foreach ($r in $GroupRecords) {
        $rlc = (Get-RecordField -Record $r -Name "role").ToLowerInvariant()
        if ($null -eq $plRow -and ($rlc -eq "planner" -or $rlc -eq "planner_revision")) {
            $plRow = $r
        }
        if ($null -eq $revRow -and $rlc -eq "planner_review") {
            $revRow = $r
        }
        if ($null -ne $plRow -and $null -ne $revRow) {
            break
        }
    }

    $plCmd = ""
    if ($null -ne $plRow) {
        $plCmd = Get-RecordField -Record $plRow -Name "planner_command"
    }
    if ([string]::IsNullOrWhiteSpace($plCmd)) { $plCmd = "(unknown)" }

    $revCmdPl = ""
    if ($null -ne $plRow) {
        $revCmdPl = Get-RecordField -Record $plRow -Name "reviewer_command"
    }
    $revCmdRv = ""
    if ($null -ne $revRow) {
        $revCmdRv = Get-RecordField -Record $revRow -Name "reviewer_command"
    }
    $revCmd = $revCmdPl
    if ([string]::IsNullOrWhiteSpace($revCmd)) {
        $revCmd = $revCmdRv
    }
    if ([string]::IsNullOrWhiteSpace($revCmd)) { $revCmd = "(unknown)" }

    $maxRev = $null
    $noRevTxt = "(unknown)"
    if ($null -ne $plRow) {
        foreach ($pr in $plRow.PSObject.Properties) {
            if ($pr.Name -eq "max_review_iters" -and $null -ne $pr.Value) {
                try {
                    $maxRev = [int]$pr.Value
                }
                catch {
                    $maxRev = $null
                }
            }
            if ($pr.Name -eq "no_revision" -and $null -ne $pr.Value) {
                try {
                    $noRevTxt = [string][bool]$pr.Value
                }
                catch {
                    $noRevTxt = "(unknown)"
                }
            }
        }
    }
    if ($null -eq $maxRev) {
        $maxRevDisp = "(unknown)"
    }
    else {
        $maxRevDisp = [string]$maxRev
    }

    $plProv = "(unknown)"
    $plMod = "(unknown)"
    if ($null -ne $plRow) {
        $pp = Get-RecordField -Record $plRow -Name "provider"
        $pm = Get-RecordField -Record $plRow -Name "model"
        if (-not [string]::IsNullOrWhiteSpace($pp)) { $plProv = $pp }
        if (-not [string]::IsNullOrWhiteSpace($pm)) { $plMod = $pm }
    }

    $rvProv = "(unknown)"
    $rvMod = "(unknown)"
    if ($null -ne $revRow) {
        $rp = Get-RecordField -Record $revRow -Name "provider"
        $rm = Get-RecordField -Record $revRow -Name "model"
        if (-not [string]::IsNullOrWhiteSpace($rp)) { $rvProv = $rp }
        if (-not [string]::IsNullOrWhiteSpace($rm)) { $rvMod = $rm }
    }

    $lines = New-Object System.Collections.Generic.List[string]
    [void]$lines.Add("planner_form (decomposed):")
    [void]$lines.Add("  planner_command: $plCmd")
    [void]$lines.Add("  planner provider/model: $plProv / $plMod")
    [void]$lines.Add("  reviewer_command: $revCmd")
    [void]$lines.Add("  reviewer provider/model: $rvProv / $rvMod")
    [void]$lines.Add("  max_review_iters: $maxRevDisp")
    [void]$lines.Add("  no_revision: $noRevTxt")
    return $lines
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

function Parse-TokenLimitsYamlBlob {
    param([string]$YamlText)

    $providers = @{}
    if ([string]::IsNullOrWhiteSpace($YamlText)) {
        return @{ Providers = $providers }
    }

    $inProviders = $false
    $provIndent = -1
    $curProv = ""

    foreach ($segment in ($YamlText -split "`r?`n")) {
        $line = ($segment -replace '(^|[ \t])#.*$', '$1').TrimEnd()
        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }
        if (-not ($line -match '^([ ]*)(.+)$')) {
            continue
        }

        $leadLen = $Matches[1].Length
        $rest = $Matches[2].TrimEnd()

        if (-not $inProviders) {
            if ($rest -match '^providers:\s*$') {
                $inProviders = $true
                $provIndent = $leadLen
                $curProv = ""
            }
            continue
        }

        if ($leadLen -le $provIndent -and ($rest -match '^(\w|\.|-)+:\s*')) {
            break
        }

        if (-not ($rest -match '^([A-Za-z0-9_-]+):\s*(.*)$')) {
            continue
        }

        $k = $Matches[1]
        $vTail = $Matches[2].Trim()
        $depth = $leadLen - $provIndent

        if ($depth -eq 2 -and ($vTail -eq "")) {
            $curProv = $k.ToLowerInvariant()
            if (-not $providers.ContainsKey($curProv)) {
                $providers[$curProv] = @{}
            }
        }
        elseif ($depth -eq 4 -and $curProv -ne "" -and @("daily", "weekly", "monthly") -contains $k) {
            $providers[$curProv][$k] = $vTail
        }
    }

    return @{ Providers = $providers }
}

function Read-TokenLimitsConfig {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path)) {
        return @{ Ok = $false; Present = $false; Providers = @{} }
    }

    try {
        $rawLimits = [System.IO.File]::ReadAllText($Path)
        $blob = Parse-TokenLimitsYamlBlob -YamlText $rawLimits
        return @{ Ok = $true; Present = $true; Providers = $blob.Providers }
    }
    catch {
        return @{ Ok = $false; Present = $true; Providers = @{} }
    }
}

function Convert-LimitFieldToSpec {
    param([string]$Raw)

    if ($null -eq $Raw) {
        return @{ Kind = "missing" }
    }

    $t = ($Raw + "").Trim().ToLowerInvariant()
    if ([string]::IsNullOrWhiteSpace($t)) {
        return @{ Kind = "missing" }
    }
    if ($t -eq "unknown") {
        return @{ Kind = "unknown" }
    }
    if ($t -eq "not_applicable" -or $t -eq "not-applicable" -or $t -eq "not applicable") {
        return @{ Kind = "na" }
    }
    if ($t -match '^[0-9]+$') {
        return @{ Kind = "numeric"; Value = [long]$t }
    }
    return @{ Kind = "unknown" }
}

function Test-LocalUsageHeuristic {
    param(
        [string]$Provider,
        [string]$Model
    )
    $p = ($Provider + "").ToLowerInvariant()
    $m = ($Model + "").ToLowerInvariant()
    if ($p -match 'local' -or $m -match 'local-' -or $m -match 'llama' -or $m -match 'ollama') {
        return $true
    }
    return $false
}

function Try-RecordTimestampUtc {
    param([string]$Iso)

    if ([string]::IsNullOrWhiteSpace($Iso)) {
        return $null
    }
    try {
        return [datetime]::Parse($Iso, $null, [System.Globalization.DateTimeStyles]::RoundtripKind).ToUniversalTime()
    }
    catch {
        return $null
    }
}

function Sum-ProviderTokensInWindows {
    param(
        $Records,
        [string]$ProviderKey,
        [datetime]$NowUtc
    )

    $dayStart = $NowUtc.Date
    $weekStart = $NowUtc.Date.AddDays(-6)
    $monthStart = $NowUtc.Date.AddDays(-29)

    $dayTot = 0L
    $weekTot = 0L
    $monthTot = 0L

    foreach ($rec in $Records) {
        $prov = (Get-RecordField -Record $rec -Name "provider").Trim()
        if ([string]::IsNullOrWhiteSpace($prov)) {
            $prov = "unknown"
        }
        if ($prov.ToLowerInvariant() -ne $ProviderKey.ToLowerInvariant()) {
            continue
        }

        $tsIso = Get-TimestampComparable -Record $rec
        $tUtc = Try-RecordTimestampUtc -Iso $tsIso
        if ($null -eq $tUtc) {
            continue
        }

        $s = Sum-TokensForRecord -Record $rec
        $tot = $s.Tot
        if ($tUtc -ge $dayStart -and $tUtc -lt $dayStart.AddDays(1)) {
            $dayTot += $tot
        }
        if ($tUtc -ge $weekStart) {
            $weekTot += $tot
        }
        if ($tUtc -ge $monthStart) {
            $monthTot += $tot
        }
    }

    return @{
        Day   = $dayTot
        Week  = $weekTot
        Month = $monthTot
    }
}

function Format-LimitUsageLine {
    param(
        [string]$Label,
        [long]$Used,
        $Spec,
        [bool]$LocalHeuristic
    )

    if ($Spec.Kind -eq "numeric") {
        $lim = $Spec.Value
        if ($lim -le 0L) {
            return "  ${Label}: used $Used / $lim (limit not positive; percentage skipped)"
        }
        $pct = [math]::Round(100.0 * [double]$Used / [double]$lim, 1)
        return "  ${Label}: used $Used / $lim ($pct%)"
    }
    if ($Spec.Kind -eq "na") {
        return "  ${Label}: not applicable"
    }
    if ($LocalHeuristic) {
        return "  ${Label}: used $Used / not applicable (local provider)"
    }
    return "  ${Label}: used $Used / unknown (percentage not computed)"
}

$consoleLines = New-Object System.Collections.Generic.List[string]

try {
    $scriptDir = $PSScriptRoot
    if ([string]::IsNullOrWhiteSpace($scriptDir)) {
        $scriptDir = Split-Path -LiteralPath $MyInvocation.MyCommand.Path -Parent
    }
    $repoRoot = Split-Path $scriptDir -Parent
    $jsonlPath = [System.IO.Path]::Combine($repoRoot, '.ai-loop', 'token_usage.jsonl')

    $limitsPathResolved = $LimitsYamlPath
    if ([string]::IsNullOrWhiteSpace($limitsPathResolved)) {
        $limitsPathResolved = [System.IO.Path]::Combine($repoRoot, 'config', 'token_limits.yaml')
    }
    elseif (-not [System.IO.Path]::IsPathRooted($limitsPathResolved)) {
        $limitsPathResolved = [System.IO.Path]::GetFullPath((Join-Path $repoRoot $limitsPathResolved.TrimStart('\', '/')))
    }

    $limitsCfg = Read-TokenLimitsConfig -Path $limitsPathResolved

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
            if ($ByChain -or $GroupByChain) {
                $groupMap = @{}
                foreach ($rec in $records) {
                    $cid = Get-RecordField -Record $rec -Name "planner_chain_id"
                    if ([string]::IsNullOrWhiteSpace($cid)) { $cid = "<no chain>" }
                    if (-not $groupMap.ContainsKey($cid)) {
                        $groupMap[$cid] = New-Object System.Collections.ArrayList
                    }
                    [void]$groupMap[$cid].Add($rec)
                }
                $consoleLines.Add("==============================")
                $consoleLines.Add("TOKEN USAGE BY CHAIN")
                $consoleLines.Add("==============================")
                $chainIdsSorted = New-Object System.Collections.Generic.List[string]
                foreach ($gk in $groupMap.Keys) {
                    [void]$chainIdsSorted.Add([string]$gk)
                }
                $chainIdsSorted.Sort()
                foreach ($cid in $chainIdsSorted) {
                    $grp = @($groupMap[$cid])
                    $tnChain = "unknown"
                    foreach ($r0 in $grp) {
                        $t0 = Get-RecordField -Record $r0 -Name "task_name"
                        if (-not [string]::IsNullOrWhiteSpace($t0)) { $tnChain = $t0; break }
                    }
                    $consoleLines.Add("")
                    $consoleLines.Add("--- Chain: $cid ---")
                    $consoleLines.Add("task_name: $tnChain")
                    foreach ($pfl in (Format-PlannerFormDecomposedLines -GroupRecords $grp)) {
                        $consoleLines.Add($pfl)
                    }

                    $roleAgg = @{}
                    $pbAgg = @{}
                    $maxFix = [long]-1
                    foreach ($rr in $grp) {
                        $rl = Get-RecordField -Record $rr -Name "role"
                        if ([string]::IsNullOrWhiteSpace($rl)) { $rl = "(no role)" }
                        if (-not $roleAgg.ContainsKey($rl)) {
                            $roleAgg[$rl] = @{ In = 0L; Out = 0L; Tot = 0L }
                            $pbAgg[$rl] = 0L
                        }
                        $sx = Sum-TokensForRecord -Record $rr
                        $roleAgg[$rl].In += $sx.In
                        $roleAgg[$rl].Out += $sx.Out
                        $roleAgg[$rl].Tot += $sx.Tot
                        $pbAgg[$rl] += Get-RecordIntField -Record $rr -Name "prompt_bytes"
                        $rlc = $rl.ToLowerInvariant()
                        if ($rlc -eq "implementer") {
                            foreach ($pp in $rr.PSObject.Properties) {
                                if ($pp.Name -eq "fix_iteration_index" -and $null -ne $pp.Value) {
                                    try {
                                        $fv = [long]$pp.Value
                                        if ($fv -gt $maxFix) { $maxFix = $fv }
                                    }
                                    catch { }
                                }
                            }
                        }
                    }
                    foreach ($rk in ($roleAgg.Keys | Sort-Object)) {
                        $va = $roleAgg[$rk]
                        $pbv = $pbAgg[$rk]
                        $consoleLines.Add("  role $rk  tokens in:$($va.In) out:$($va.Out) total:$($va.Tot)  prompt_bytes:$pbv")
                    }
                    if ($maxFix -ge 0) {
                        $consoleLines.Add("  fix_iters (max fix_iteration_index for implementer): $maxFix")
                    }
                    else {
                        $consoleLines.Add("  fix_iters (max fix_iteration_index for implementer): 0")
                    }
                }
                $consoleLines.Add("")
                $consoleLines.Add("==============================")
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

            # --- Limits ---
            $consoleLines.Add("")
            $consoleLines.Add("Limits (user budgets from config/token_limits.yaml; UTC windows; not provider API quotas):")
            if (-not $limitsCfg.Present) {
                $consoleLines.Add("  Config missing at: $limitsPathResolved")
                $consoleLines.Add("  Treat budgets as unknown (not configured here). Percentages shown only when a numeric budget exists.")
            }
            elseif (-not $limitsCfg.Ok) {
                $consoleLines.Add("  Config present but could not be parsed: $limitsPathResolved")
                $consoleLines.Add("  Treat budgets as unknown. Percentages shown only when a numeric budget exists.")
            }

            $provSeen = New-Object System.Collections.Generic.HashSet[string]
            foreach ($rec in $records) {
                $pv = (Get-RecordField -Record $rec -Name "provider").Trim()
                if ([string]::IsNullOrWhiteSpace($pv)) {
                    [void]$provSeen.Add("unknown")
                }
                else {
                    [void]$provSeen.Add($pv.ToLowerInvariant())
                }
            }

            $nowUtcLim = [datetime]::UtcNow
            foreach ($pvKey in ($provSeen | Sort-Object)) {
                $representativeModel = ""
                foreach ($rec in $records) {
                    $rp = (Get-RecordField -Record $rec -Name "provider").Trim()
                    if ([string]::IsNullOrWhiteSpace($rp)) {
                        $rp = "unknown"
                    }
                    if ($rp.ToLowerInvariant() -ne $pvKey) {
                        continue
                    }
                    $representativeModel = Get-RecordField -Record $rec -Name "model"
                    break
                }

                $localH = Test-LocalUsageHeuristic -Provider $pvKey -Model $representativeModel
                $windows = Sum-ProviderTokensInWindows -Records $records -ProviderKey $pvKey -NowUtc $nowUtcLim

                $provMap = @{}
                if ($limitsCfg.Providers -and $limitsCfg.Providers.ContainsKey($pvKey)) {
                    $provMap = $limitsCfg.Providers[$pvKey]
                }

                $dailySpec = Convert-LimitFieldToSpec -Raw $(if ($provMap.ContainsKey("daily")) { $provMap["daily"] } else { "" })
                $weeklySpec = Convert-LimitFieldToSpec -Raw $(if ($provMap.ContainsKey("weekly")) { $provMap["weekly"] } else { "" })
                $monthlySpec = Convert-LimitFieldToSpec -Raw $(if ($provMap.ContainsKey("monthly")) { $provMap["monthly"] } else { "" })

                if ($dailySpec.Kind -eq "missing" -and $localH) {
                    $dailySpec = @{ Kind = "na" }
                }
                if ($weeklySpec.Kind -eq "missing" -and $localH) {
                    $weeklySpec = @{ Kind = "na" }
                }
                if ($monthlySpec.Kind -eq "missing" -and $localH) {
                    $monthlySpec = @{ Kind = "na" }
                }

                $consoleLines.Add("  Provider: $pvKey")
                $consoleLines.Add($(Format-LimitUsageLine -Label "daily (calendar UTC day)" -Used $windows.Day -Spec $dailySpec -LocalHeuristic $localH))
                $consoleLines.Add($(Format-LimitUsageLine -Label "weekly (rolling 7d UTC)" -Used $windows.Week -Spec $weeklySpec -LocalHeuristic $localH))
                $consoleLines.Add($(Format-LimitUsageLine -Label "monthly (rolling 30d UTC)" -Used $windows.Month -Spec $monthlySpec -LocalHeuristic $localH))
            }

            $consoleLines.Add("==============================")
            }
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

if ($ExportReport) {
    try {
        $sdEx = $PSScriptRoot
        if ([string]::IsNullOrWhiteSpace($sdEx) -and $MyInvocation.MyCommand.Path) {
            $sdEx = Split-Path -LiteralPath $MyInvocation.MyCommand.Path -Parent
        }
        if (-not [string]::IsNullOrWhiteSpace($sdEx)) {
            $rrEx = Split-Path $sdEx -Parent
            $repDir = [System.IO.Path]::Combine($rrEx, '.ai-loop', 'reports')
            if (-not (Test-Path -LiteralPath $repDir)) {
                New-Item -ItemType Directory -Force -Path $repDir | Out-Null
            }
            $stamp = [datetime]::UtcNow.ToString("yyyyMMdd_HHmmss")
            $repPath = [System.IO.Path]::Combine($repDir, "token_usage_$stamp.md")
            $rb = (($consoleLines.ToArray()) -join [Environment]::NewLine) + [Environment]::NewLine
            [System.IO.File]::WriteAllText($repPath, $rb)
        }
    }
    catch {
        Write-Warning "token usage report export skipped: $($_.Exception.Message)"
    }
}

exit 0
