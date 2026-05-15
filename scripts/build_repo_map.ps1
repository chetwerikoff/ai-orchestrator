<#
.SYNOPSIS
    Generate a deterministic `.ai-loop/repo_map.md` index for the repository tree.

.DESCRIPTION
    Walks configured roots, extracts one-line summaries from file headers, and writes
    UTF-8 (no BOM) output capped at 250 lines (warning only if exceeded).
#>
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$OutPath = Join-Path $RepoRoot ".ai-loop/repo_map.md"

function Test-RepoMapSkipPath {
    param([string]$RelNorm)
    if ($RelNorm -match '(^|/)docs/archive(/|$)') { return $true }
    if ($RelNorm -match '(^|/)\.ai-loop/_debug(/|$)') { return $true }
    if ($RelNorm -match '(^|/)\.ai-loop/archive(/|$)') { return $true }
    if ($RelNorm -match '(^|/)(\.tmp|__pycache__|\.git|\.pytest_cache|\.claude|node_modules|input|output)(/|$)') { return $true }
    if ($RelNorm -eq 'CLAUDE.md') { return $true }
    return $false
}

function Normalize-RelPath {
    param([string]$FullPath)
    $r = $FullPath.Substring($RepoRoot.Length).TrimStart('\', '/')
    return ($r -replace '\\', '/')
}

function Get-FirstHashCommentLine {
    param([string[]]$Lines)
    foreach ($ln in $Lines) {
        if ($ln -match '^\s*#\s*(.+)$') {
            return $Matches[1].Trim()
        }
    }
    return $null
}

function Get-Ps1Summary {
    param([string]$Text, [string[]]$Lines)
    $blocks = [regex]::Matches($Text, '<#([\s\S]*?)#>')
    foreach ($m in $blocks) {
        $inner = $m.Groups[1].Value -split "`r?`n"
        for ($i = 0; $i -lt $inner.Length; $i++) {
            if ($inner[$i] -match '^\s*\.SYNOPSIS\s*$') {
                for ($j = $i + 1; $j -lt $inner.Length; $j++) {
                    $cand = $inner[$j].Trim()
                    if ($cand.Length -gt 0) { return $cand }
                }
                break
            }
        }
    }
    $hc = Get-FirstHashCommentLine -Lines $Lines
    if ($hc) { return $hc }
    return "(no header summary)"
}

function Get-PySummary {
    param([string]$Text, [string[]]$Lines)
    $t = $Text.TrimStart()
    while ($true) {
        if ($t.StartsWith('#!')) {
            $idx = $t.IndexOfAny(@([char]10, [char]13))
            if ($idx -lt 0) { break }
            $t = $t.Substring($idx).TrimStart("`r`n")
            continue
        }
        break
    }
    if ($t.Length -ge 3 -and ($t.StartsWith('"""') -or $t.StartsWith("'''"))) {
        $q = $t.Substring(0, 3)
        $rest = $t.Substring(3)
        $end = $rest.IndexOf($q)
        if ($end -ge 0) {
            $body = $rest.Substring(0, $end)
            $first = ($body -split "`r?`n" | Where-Object { $_.Trim().Length -gt 0 } | Select-Object -First 1)
            if ($first) { return $first.Trim() }
        }
    }
    $hc = Get-FirstHashCommentLine -Lines $Lines
    if ($hc) { return $hc }
    return "(no header summary)"
}

function Get-MdSummary {
    param([string[]]$Lines)
    foreach ($ln in $Lines) {
        if ($ln -match '^\s*#\s+([^#].*)$') { return $Matches[1].Trim() }
    }
    foreach ($ln in $Lines) {
        $t = $ln.Trim()
        if ($t.Length -gt 0) { return $t }
    }
    return "(no header summary)"
}

function Get-GenericCommentSummary {
    param([string[]]$Lines)
    foreach ($ln in $Lines) {
        if ($ln -match '^\s*#\s*(.+)$') { return $Matches[1].Trim() }
        if ($ln -match '^\s*;\s*(.+)$') { return $Matches[1].Trim() }
        if ($ln -match '^\s*//\s*(.+)$') { return $Matches[1].Trim() }
    }
    return "(no header summary)"
}

function Get-OneLineSummary {
    param([string]$RelPath, [string]$FullPath)
    $ext = [System.IO.Path]::GetExtension($RelPath).ToLowerInvariant()
    $raw = [System.IO.File]::ReadAllText($FullPath)
    $lines = $raw -split "`r?`n"

    switch ($ext) {
        '.ps1' { return (Get-Ps1Summary -Text $raw -Lines $lines) }
        '.py' { return (Get-PySummary -Text $raw -Lines $lines) }
        '.md' { return (Get-MdSummary -Lines $lines) }
        { $_ -in '.ini', '.cfg', '.toml', '.json' } { return (Get-GenericCommentSummary -Lines $lines) }
        Default { return (Get-GenericCommentSummary -Lines $lines) }
    }
}

try {
    $seen = @{}
    $collected = New-Object System.Collections.Generic.List[object]

    $rootExts = @('.md', '.py', '.ps1', '.ini', '.cfg', '.toml', '.json')
    foreach ($f in Get-ChildItem -LiteralPath $RepoRoot -File -Force) {
        $ext = $f.Extension.ToLowerInvariant()
        if ($rootExts -notcontains $ext) { continue }
        $rn = Normalize-RelPath -FullPath $f.FullName
        if ($rn.Contains('/')) { continue }
        if (Test-RepoMapSkipPath -RelNorm $rn) { continue }
        if ($seen.ContainsKey($rn)) { continue }
        $seen[$rn] = $true
        $collected.Add([pscustomobject]@{ Rel = $rn; Full = $f.FullName })
    }

    $walkDirs = @('src', 'scripts', 'templates', 'docs', 'tests')
    foreach ($dir in $walkDirs) {
        $base = Join-Path $RepoRoot $dir
        if (-not (Test-Path -LiteralPath $base)) { continue }
        foreach ($f in Get-ChildItem -LiteralPath $base -Recurse -File -Force -ErrorAction Stop) {
            $rn = Normalize-RelPath -FullPath $f.FullName
            if (Test-RepoMapSkipPath -RelNorm $rn) { continue }
            if ($seen.ContainsKey($rn)) { continue }
            $seen[$rn] = $true
            $collected.Add([pscustomobject]@{ Rel = $rn; Full = $f.FullName })
        }
    }

    $byGroup = @{}
    foreach ($it in ($collected | Sort-Object { $_.Rel })) {
        $gk = if ($it.Rel -match '/') { ($it.Rel -split '/')[0] } else { '' }
        if (-not $byGroup.ContainsKey($gk)) {
            $byGroup[$gk] = New-Object System.Collections.Generic.List[object]
        }
        $byGroup[$gk].Add($it)
    }

    $groupOrder = ($byGroup.Keys | Sort-Object)
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('# Repo map')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('> Generated by `scripts/build_repo_map.ps1`. Do not edit by hand.')
    [void]$sb.AppendLine('> Regenerate after structural changes; tests pin determinism.')
    [void]$sb.AppendLine('')

    $emDash = [char]0x2014
    foreach ($gk in $groupOrder) {
        $label = if ($gk -eq '') { 'Top-level' } else { "$gk/" }
        [void]$sb.AppendLine("## $label")
        [void]$sb.AppendLine('')
        foreach ($it in $byGroup[$gk]) {
            $sum = Get-OneLineSummary -RelPath $it.Rel -FullPath $it.Full
            $sumOne = ($sum -replace "`r?`n", ' ').Trim()
            [void]$sb.AppendLine(('- `{0}` {1} {2}' -f $it.Rel, $emDash, $sumOne))
        }
        [void]$sb.AppendLine('')
    }

    $text = $sb.ToString().TrimEnd() + "`n"
    $lineCount = ($text -split "`r?`n").Count
    if ($lineCount -gt 250) {
        Write-Warning "repo_map.md has $lineCount lines (cap 250); refine selection in a follow-up task."
    }

    $ai = Join-Path $RepoRoot '.ai-loop'
    if (-not (Test-Path -LiteralPath $ai)) {
        New-Item -ItemType Directory -Force -Path $ai | Out-Null
    }

    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($OutPath, $text, $utf8NoBom)
    exit 0
} catch {
    Write-Error $_
    exit 1
}
