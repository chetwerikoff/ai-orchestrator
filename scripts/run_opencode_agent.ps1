<#
.SYNOPSIS
    Invoke OpenCode (opencode run) as a drop-in replacement for run_cursor_agent.ps1.

.DESCRIPTION
    Called by ai_loop_task_first.ps1 via:
        $prompt | & $CommandName @agentArgs *> $outputPath
    where agentArgs = @("--print", "--trust", "--workspace", $ProjectRoot)

    Cursor-specific flags (--print, --trust) are silently ignored.
    --workspace  changes cwd to the project root before invoking opencode.
    --model      overrides the OpenCode model (format: provider/model-id).
                 Default: local-qwen/qwen3-coder-30b-a3b

    The prompt is read from stdin and written to a temp file which is passed
    to opencode via -f.  Temp file is cleaned up on exit.

.EXAMPLE
    $prompt | .\scripts\run_opencode_agent.ps1 --workspace C:\myproject
    $prompt | .\scripts\run_opencode_agent.ps1 --workspace C:\myproject --model local-qwen-27b/qwen3-6-27b
#>

# No param() block so PowerShell does not pipeline-bind $input.
# $input = piped prompt lines; $args = forwarded flags.

$workspace = $null
$model     = "local-qwen/qwen3-coder-30b-a3b"

$i = 0
while ($i -lt $args.Count) {
    switch ($args[$i]) {
        "--workspace" { $workspace = $args[$i + 1]; $i += 2; break }
        "--model"     { $model     = $args[$i + 1]; $i += 2; break }
        default       { $i++ }   # silently skip --print, --trust, etc.
    }
}

# Collect stdin (prompt text) into a single string.
$promptText = ($input | Out-String).TrimEnd()
if ([string]::IsNullOrWhiteSpace($promptText)) {
    Write-Error "run_opencode_agent: no prompt received on stdin."
    exit 1
}

# Write prompt to a temp file so we can attach it via -f.
# opencode run requires a positional message; we pass a brief directive and attach
# the full prompt as a file so OpenCode reads it as context.
$tempFile = Join-Path $env:TEMP "opencode_prompt_$([System.IO.Path]::GetRandomFileName()).md"
[System.IO.File]::WriteAllText($tempFile, $promptText, [System.Text.Encoding]::UTF8)

$scriptRootOc = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($scriptRootOc)) {
    $scriptRootOc = Split-Path -LiteralPath $MyInvocation.MyCommand.Path -Parent
}
$projHintOc = ""
if ($workspace -and (Test-Path -LiteralPath $workspace)) {
    $projHintOc = [System.IO.Path]::GetFullPath(($workspace.Trim()))
}
else {
    try { $projHintOc = (Get-Location).Path } catch { $projHintOc = "" }
}

# Brief message that instructs OpenCode to read the attached file.
$message = "You are the IMPLEMENTER. Read the attached file completely and execute every instruction in it. Do not summarise or review - implement directly."

$pushed = $false
$exitCode = 1
try {
    if ($workspace -and (Test-Path $workspace)) {
        Push-Location $workspace
        $pushed = $true
    }

    Write-Host "Running OpenCode: model=$model workspace=$workspace"
    # opencode.ps1 (npm wrapper) lets node.exe write to stderr which triggers
    # NativeCommandError under $ErrorActionPreference = "Stop".
    # Temporarily lower to SilentlyContinue so stderr noise doesn't abort us;
    # we capture exit code manually.
    $prevEA = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    $ocLines = @(opencode run $message -f $tempFile --model $model 2>&1)
    $exitCode = $LASTEXITCODE
    $ErrorActionPreference = $prevEA
    foreach ($ol in @($ocLines)) {
        Write-Output $ol
    }
    try {
        if ($exitCode -eq 0) {
            $capOc = (@($ocLines) | ForEach-Object { "$_" }) -join "`n"
            . (Join-Path $scriptRootOc "record_token_usage.ps1")
            $pbOc = 0
            try {
                $pbOc = [System.Text.Encoding]::UTF8.GetByteCount($promptText)
            }
            catch {
                $pbOc = 0
            }
            $fiOc = -1
            if ($null -ne $env:AI_LOOP_TOKEN_FIX_ITER -and ([string]$env:AI_LOOP_TOKEN_FIX_ITER -match '^-?\d+$')) {
                $fiOc = [int]$env:AI_LOOP_TOKEN_FIX_ITER
            }
            Write-CliCaptureTokenUsageIfParsed `
                -CapturedText $capOc `
                -ScriptName "run_opencode_agent.ps1" `
                -Provider "opencode" `
                -Model $model `
                -Iteration 0 `
                -ProjectRootHint $projHintOc `
                -Phase $(if ($null -ne $env:AI_LOOP_TOKEN_PHASE -and -not [string]::IsNullOrWhiteSpace([string]$env:AI_LOOP_TOKEN_PHASE)) { [string]$env:AI_LOOP_TOKEN_PHASE } else { "" }) `
                -Role $(if ($null -ne $env:AI_LOOP_TOKEN_ROLE -and -not [string]::IsNullOrWhiteSpace([string]$env:AI_LOOP_TOKEN_ROLE)) { [string]$env:AI_LOOP_TOKEN_ROLE } else { "" }) `
                -FixIterationIndex $fiOc `
                -PromptBytes $pbOc
        }
    }
    catch {
        Write-Warning "OpenCode implementer token recording skipped (non-blocking): $($_.Exception.Message)"
    }
}
finally {
    if ($pushed) { Pop-Location }
    Remove-Item $tempFile -ErrorAction SilentlyContinue
}

exit $exitCode
