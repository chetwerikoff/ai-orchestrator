# No param block: keeps $input available for the pipeline.
# $input = piped prompt lines; $args = forwarded flags.

$workspace = $null
$model = "claude-haiku-4-5-20251001"

$i = 0
while ($i -lt $args.Count) {
    switch ($args[$i]) {
        "--workspace" {
            $workspace = $args[$i + 1]
            $i += 2
            break
        }
        "--model" {
            $model = $args[$i + 1]
            $i += 2
            break
        }
        default { $i++ }
    }
}

$promptText = ($input | Out-String).TrimEnd()
if ([string]::IsNullOrWhiteSpace($promptText)) {
    Write-Error "run_claude_reviewer: no prompt received on stdin."
    exit 1
}

if ([string]::IsNullOrWhiteSpace($model)) {
    $model = "claude-haiku-4-5-20251001"
}

$scriptRootReviewer = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($scriptRootReviewer)) {
    $scriptRootReviewer = Split-Path -LiteralPath $MyInvocation.MyCommand.Path -Parent
}

$projHintReviewer = ""
if ($workspace -and (Test-Path -LiteralPath $workspace)) {
    $projHintReviewer = [System.IO.Path]::GetFullPath($workspace.Trim())
}
else {
    try { $projHintReviewer = (Get-Location).Path } catch { $projHintReviewer = "" }
}

$pushed = $false
$exitCode = 1
try {
    if ($workspace -and (Test-Path $workspace)) {
        Push-Location $workspace
        $pushed = $true
    }
    $prevEA = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    $claudeLines = @($promptText | claude --print --model $model 2>&1)
    $exitCode = $LASTEXITCODE
    $ErrorActionPreference = $prevEA
    foreach ($ln in @($claudeLines)) {
        Write-Output $ln
    }

    try {
        if ($exitCode -eq 0) {
            $cap = (@($claudeLines) | ForEach-Object { "$_" }) -join "`n"
            . (Join-Path $scriptRootReviewer "record_token_usage.ps1")
            $pbCr = 0
            try {
                $pbCr = [System.Text.Encoding]::UTF8.GetByteCount($promptText)
            }
            catch {
                $pbCr = 0
            }
            Write-CliCaptureTokenUsageIfParsed `
                -CapturedText $cap `
                -ScriptName "run_claude_reviewer.ps1" `
                -Provider "anthropic" `
                -Model $model `
                -Iteration 0 `
                -ProjectRootHint $projHintReviewer `
                -Phase $(if ($null -ne $env:AI_LOOP_TOKEN_PHASE -and -not [string]::IsNullOrWhiteSpace([string]$env:AI_LOOP_TOKEN_PHASE)) { [string]$env:AI_LOOP_TOKEN_PHASE } else { "" }) `
                -Role $(if ($null -ne $env:AI_LOOP_TOKEN_ROLE -and -not [string]::IsNullOrWhiteSpace([string]$env:AI_LOOP_TOKEN_ROLE)) { [string]$env:AI_LOOP_TOKEN_ROLE } else { "" }) `
                -FixIterationIndex -1 `
                -PromptBytes $pbCr
        }
    }
    catch {
        Write-Warning "Anthropic reviewer token recording skipped (non-blocking): $($_.Exception.Message)"
    }
}
finally {
    if ($pushed) { Pop-Location }
}

exit $exitCode
