# No param block: keeps $input available for the pipeline.
# $input = piped prompt lines; $args = forwarded flags.

$workspace = $null
$model = "claude-sonnet-4-6"

$i = 0
while ($i -lt $args.Count) {
    switch ($args[$i]) {
        "--workspace" { $workspace = $args[$i + 1]; $i += 2; break }
        "--model" { $model = $args[$i + 1]; $i += 2; break }
        default { $i++ }
    }
}

$promptText = ($input | Out-String).TrimEnd()
if ([string]::IsNullOrWhiteSpace($promptText)) {
    Write-Error "run_claude_planner: no prompt received on stdin."
    exit 1
}

if ([string]::IsNullOrWhiteSpace($model)) {
    $model = "claude-sonnet-4-6"
}

$scriptRootPlanner = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($scriptRootPlanner)) {
    $scriptRootPlanner = Split-Path -LiteralPath $MyInvocation.MyCommand.Path -Parent
}

$projHintPlanner = ""
if ($workspace -and (Test-Path -LiteralPath $workspace)) {
    $projHintPlanner = [System.IO.Path]::GetFullPath($workspace.Trim())
}
else {
    try { $projHintPlanner = (Get-Location).Path } catch { $projHintPlanner = "" }
}

$pushed = $false
$exitCode = 1
$systemPrompt = "Return only the final markdown document. The first byte of stdout must be '#'. Do not include analysis, status text, preambles, code fences, or tool calls."
try {
    if ($workspace -and (Test-Path $workspace)) {
        Push-Location $workspace
        $pushed = $true
    }
    $prevEA = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    $claudeLines = @($promptText | cmd /c claude --print --model $model --tools '""' --system-prompt $systemPrompt 2>&1)
    $exitCode = $LASTEXITCODE
    $ErrorActionPreference = $prevEA
    foreach ($ln in @($claudeLines)) {
        Write-Output $ln
    }

    try {
        if ($exitCode -eq 0) {
            $cap = (@($claudeLines) | ForEach-Object { "$_" }) -join "`n"
            . (Join-Path $scriptRootPlanner "record_token_usage.ps1")
            $rolePl = [string]$env:AI_LOOP_PLANNER_ROLE
            if ([string]::IsNullOrWhiteSpace($rolePl)) {
                $rolePl = "planner"
            }
            $pbPl = 0
            try {
                $pbPl = [System.Text.Encoding]::UTF8.GetByteCount($promptText)
            }
            catch {
                $pbPl = 0
            }
            Write-CliCaptureTokenUsageIfParsed `
                -CapturedText $cap `
                -ScriptName "run_claude_planner.ps1" `
                -Provider "anthropic" `
                -Model $model `
                -Iteration 0 `
                -ProjectRootHint $projHintPlanner `
                -Phase "planning" `
                -Role $rolePl `
                -FixIterationIndex -1 `
                -PromptBytes $pbPl
        }
    }
    catch {
        Write-Warning "Anthropic planner token recording skipped (non-blocking): $($_.Exception.Message)"
    }
}
finally {
    if ($pushed) { Pop-Location }
}

exit $exitCode
