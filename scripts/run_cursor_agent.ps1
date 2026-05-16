<#
.SYNOPSIS
    Invoke the Cursor agent CLI (node.exe) directly, reading the prompt from stdin.

.DESCRIPTION
    cursor-agent ships as a .cmd wrapper that passes arguments through cmd.exe.
    When the prompt is large (~19 KB), passing it as a CLI arg causes the cmd.exe
    batch-line expander to exceed its ~8 191-char internal limit, which makes
    Windows return ERROR_ACCESS_DENIED when creating node.exe.

    Piping the prompt via stdin avoids that limit.  However stdin is silently
    dropped somewhere in the cmd.exe -> powershell.exe -> node.exe chain used by
    cursor-agent.cmd.  This script calls node.exe directly so stdin reaches it
    without interruption.

    This script has NO param() block on purpose.  A param() block would cause
    PowerShell to attempt pipeline-parameter binding on the piped prompt string
    and raise "The input object cannot be bound to any parameters".  Without a
    param() block PowerShell stores piped input in $input and positional args
    in $args, which is exactly what is forwarded to node.exe below.

.EXAMPLE
    $prompt | .\scripts\run_cursor_agent.ps1 --print --trust --workspace C:\myproject
#>

# --- version discovery (mirrors the logic in cursor-agent.ps1) -----------------

function Get-LatestCursorAgentVersion {
    $base = Join-Path $env:LOCALAPPDATA "cursor-agent\versions"
    if (-not (Test-Path $base)) {
        throw "cursor-agent versions directory not found: $base"
    }
    $dir = Get-ChildItem $base -Directory |
        Where-Object { $_.Name -match '^\d{4}\.\d{1,2}\.\d{1,2}-[a-f0-9]+$' } |
        Sort-Object {
            $p = $_.Name.Split('-')[0].Split('.')
            [int]($p[0] + $p[1].PadLeft(2, '0') + $p[2].PadLeft(2, '0'))
        } -Descending |
        Select-Object -First 1
    if (-not $dir) { throw "No versioned cursor-agent directory found under $base" }
    return $dir
}

# -------------------------------------------------------------------------------

$scriptRootCa = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($scriptRootCa)) {
    $scriptRootCa = Split-Path -LiteralPath $MyInvocation.MyCommand.Path -Parent
}

$cursorWs = $null
$cursorModelArg = ""
$ai = 0
while ($ai -lt $args.Count) {
    if ($args[$ai] -eq "--workspace" -and ($ai + 1) -lt $args.Count) {
        $cursorWs = $args[$ai + 1]
        $ai += 2
        continue
    }
    if ($args[$ai] -eq "--model" -and ($ai + 1) -lt $args.Count) {
        $cursorModelArg = [string]$args[$ai + 1]
        $ai += 2
        continue
    }
    $ai++
}
$projHintCa = ""
if ($cursorWs -and (Test-Path -LiteralPath $cursorWs)) {
    $projHintCa = [System.IO.Path]::GetFullPath(($cursorWs.Trim()))
}
else {
    try { $projHintCa = (Get-Location).Path } catch { $projHintCa = "" }
}

$versionDir = Get-LatestCursorAgentVersion
$nodePath   = Join-Path $versionDir.FullName "node.exe"
$indexPath  = Join-Path $versionDir.FullName "index.js"

if (-not (Test-Path $nodePath))  { throw "node.exe not found: $nodePath" }
if (-not (Test-Path $indexPath)) { throw "index.js not found: $indexPath" }

# $input  = prompt from stdin (set by PowerShell from the pipeline)
# $args   = forwarded agent flags (--print, --trust, --workspace, ...)
# 2>&1 merges node stderr into stdout so outer redirections capture everything.
$promptTextCa = ($input | Out-String).TrimEnd()
$capturedCa = @($promptTextCa | & $nodePath $indexPath @args 2>&1)
$exitCa = $LASTEXITCODE

foreach ($row in @($capturedCa)) {
    Write-Output $row
}

try {
    if ($exitCa -eq 0) {
        $capCaText = (@($capturedCa) | ForEach-Object { "$_" }) -join "`n"
        . (Join-Path $scriptRootCa "record_token_usage.ps1")
        $pbCa = 0
        try {
            $pbCa = [System.Text.Encoding]::UTF8.GetByteCount($promptTextCa)
        }
        catch {
            $pbCa = 0
        }
        $fiCa = -1
        if ($null -ne $env:AI_LOOP_TOKEN_FIX_ITER -and ([string]$env:AI_LOOP_TOKEN_FIX_ITER -match '^-?\d+$')) {
            $fiCa = [int]$env:AI_LOOP_TOKEN_FIX_ITER
        }
        $phaseCa = ""
        if ($null -ne $env:AI_LOOP_TOKEN_PHASE -and -not [string]::IsNullOrWhiteSpace([string]$env:AI_LOOP_TOKEN_PHASE)) {
            $phaseCa = [string]$env:AI_LOOP_TOKEN_PHASE
        }
        $roleCa = ""
        if ($null -ne $env:AI_LOOP_TOKEN_ROLE -and -not [string]::IsNullOrWhiteSpace([string]$env:AI_LOOP_TOKEN_ROLE)) {
            $roleCa = [string]$env:AI_LOOP_TOKEN_ROLE
        }
        elseif ($phaseCa -eq "planning" -and $null -ne $env:AI_LOOP_PLANNER_ROLE -and -not [string]::IsNullOrWhiteSpace([string]$env:AI_LOOP_PLANNER_ROLE)) {
            $roleCa = [string]$env:AI_LOOP_PLANNER_ROLE
        }
        Write-CliCaptureTokenUsageIfParsed `
            -CapturedText $capCaText `
            -ScriptName "run_cursor_agent.ps1" `
            -Provider "cursor" `
            -Model $(if ([string]::IsNullOrWhiteSpace($cursorModelArg)) { "" } else { $cursorModelArg }) `
            -Iteration 0 `
            -ProjectRootHint $projHintCa `
            -Phase $phaseCa `
            -Role $roleCa `
            -FixIterationIndex $fiCa `
            -PromptBytes $pbCa
    }
}
catch {
    Write-Warning "Cursor agent token recording skipped (non-blocking): $($_.Exception.Message)"
}

exit $exitCa
