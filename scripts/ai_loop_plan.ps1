param(
    [string]$Ask = "",
    [string]$AskFile = ".ai-loop\user_ask.md",
    [string]$PlannerCommand = ".\scripts\run_claude_planner.ps1",
    [string]$PlannerModel = "",
    [string]$Out = ".ai-loop\task.md",
    [switch]$Force
)
$ErrorActionPreference = "Stop"
$ProjectRoot = (Resolve-Path ".").Path

$resolvedAsk = ""
if (-not [string]::IsNullOrWhiteSpace($Ask)) {
    $resolvedAsk = $Ask
} elseif (Test-Path -LiteralPath $AskFile) {
    $resolvedAsk = [System.IO.File]::ReadAllText((Resolve-Path -LiteralPath $AskFile).Path)
} else {
    Write-Warning "No ask provided. Use -Ask `"...`" or create $AskFile."
    exit 1
}

$planPrompt = Join-Path $ProjectRoot ".ai-loop\planner_prompt.md"
if (-not (Test-Path -LiteralPath $planPrompt)) {
    $planPrompt = Join-Path $ProjectRoot "templates\planner_prompt.md"
}
if (-not (Test-Path -LiteralPath $planPrompt)) {
    Write-Warning "Planner prompt not found at .ai-loop\planner_prompt.md or templates\planner_prompt.md."
    exit 1
}
Write-Host "Using planner prompt: $planPrompt"

$agentsPath = Join-Path $ProjectRoot "AGENTS.md"
$summaryPath = Join-Path $ProjectRoot ".ai-loop\project_summary.md"
$cmdPath = $PlannerCommand
if (-not (Test-Path -LiteralPath $cmdPath)) {
    $rel = $PlannerCommand -replace '^\.\\',''
    $alt = Join-Path $ProjectRoot $rel
    if (Test-Path -LiteralPath $alt) { $cmdPath = $alt }
}
if (-not (Test-Path -LiteralPath $agentsPath)) {
    Write-Warning "missing AGENTS.md Path: $agentsPath"
    exit 1
}
if (-not (Test-Path -LiteralPath $summaryPath)) {
    Write-Warning "missing .ai-loop/project_summary.md Path: $summaryPath"
    exit 1
}
if (-not (Test-Path -LiteralPath $cmdPath)) {
    Write-Warning "missing $PlannerCommand Path: $cmdPath"
    exit 1
}

function Get-FilesInScopeSummary {
    param([Parameter(Mandatory)][string]$Text)
    $lines = $Text -split "`r?`n"
    $in = $false
    $items = @()
    foreach ($ln in $lines) {
        if ($ln -match '^\s*##\s+Files in scope\s*$') { $in = $true; continue }
        if ($in -and $ln -match '^\s*##\s+') { break }
        if (-not $in) { continue }
        if ($ln -notmatch '^\s*[-*]\s+(.+)$') { continue }
        $raw = $Matches[1].Trim()
        $new = $raw -match '\(new\)'
        $tok = ""
        if ($raw -match '^`([^`]+)`') { $tok = $Matches[1] }
        elseif ($raw -match '^(\S+)') { $tok = $Matches[1].Trim('`') }
        if (-not $tok) { continue }
        $items += $(if ($new) { "$tok (new)" } else { $tok })
    }
    return $items
}

$planTxt = [System.IO.File]::ReadAllText($planPrompt)
$repoPath = Join-Path $ProjectRoot ".ai-loop\repo_map.md"
$repoBlock = ""
if (Test-Path -LiteralPath $repoPath) {
    $repoBlock = "`n`n## repo_map.md`n" + [System.IO.File]::ReadAllText($repoPath)
} else {
    Write-Warning "repo_map.md is missing ? planner context will be limited. Run scripts/build_repo_map.ps1 first for better results."
}
$prompt = $planTxt + "`n`n## AGENTS.md`n" + [System.IO.File]::ReadAllText($agentsPath) + "`n`n## project_summary.md`n" + [System.IO.File]::ReadAllText($summaryPath) + $repoBlock + "`n`n## USER ASK`n" + $resolvedAsk

$backupMade = $false
if ((Test-Path -LiteralPath $Out) -and -not $Force) {
    Move-Item -Force -LiteralPath $Out -Destination "$Out.bak"
    $backupMade = $true
}
$tmpOut = "$Out.tmp"
$script:ExitCode = 0
try {
    $pwArgs = @("--workspace", $ProjectRoot)
    if (-not [string]::IsNullOrWhiteSpace($PlannerModel)) { $pwArgs += @("--model", $PlannerModel) }
    $rawLines = @($prompt | & $cmdPath @pwArgs)
    $output = ($rawLines | ForEach-Object { "$_" }) -join "`n"
    if ($LASTEXITCODE -ne 0) {
        $script:ExitCode = 1
        throw "Planner wrapper exited with code $LASTEXITCODE."
    }
    $first = ($output -split "`r?`n", 2)[0].TrimStart()
    if (-not $first.StartsWith("# Task:")) {
        $script:ExitCode = 2
        throw "Planner output does not start with '# Task:' (looks like a preamble or refusal)."
    }
    $required = @('## Goal', '## Scope', '## Files in scope', '## Files out of scope', '## Tests', '## Important')
    foreach ($h in $required) {
        $pattern = '(?m)^' + [regex]::Escape($h) + '\b'
        if ($output -notmatch $pattern) {
            $script:ExitCode = 2
            throw "Planner output is missing required heading '$h'."
        }
    }
    $outParent = Split-Path -Parent $Out
    if ($outParent -and -not (Test-Path -LiteralPath $outParent)) {
        New-Item -ItemType Directory -Force -Path $outParent | Out-Null
    }
    Set-Content -LiteralPath $tmpOut -Value $output -Encoding UTF8
    Move-Item -Force -LiteralPath $tmpOut -Destination $Out
    Write-Host "Wrote $Out (no obvious structural issues found).`n`nFiles in scope (extracted from task.md ? verify before running):"
    $paths = Get-FilesInScopeSummary -Text $output
    if ($paths.Count -eq 0) {
        Write-Host "  (Could not parse Files in scope ? review task.md manually.)"
    } else {
        $n = [Math]::Min(10, $paths.Count)
        for ($i = 0; $i -lt $n; $i++) { Write-Host "  $($paths[$i])" }
        if ($paths.Count -gt 10) { Write-Host "  ... ($($paths.Count - 10) more total)" }
    }
    Write-Host "`nThis is a DRAFT. Review $Out manually before running ai_loop_task_first.ps1."
    if ($backupMade) { Write-Host "Previous task.md kept at $Out.bak." }
}
catch {
    if ($script:ExitCode -eq 0) { $script:ExitCode = 1 }
    if ($backupMade -and -not (Test-Path -LiteralPath $Out)) {
        Move-Item -Force -LiteralPath "$Out.bak" -Destination $Out
    }
    if (Test-Path -LiteralPath $tmpOut) {
        Remove-Item -LiteralPath $tmpOut -Force -ErrorAction SilentlyContinue
    }
    Write-Warning $_.Exception.Message
    if ($backupMade) { Write-Warning "Restored previous $Out from backup." }
}
finally {
    exit $script:ExitCode
}
