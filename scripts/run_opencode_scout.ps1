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
    Write-Error "run_opencode_scout: no prompt received on stdin."
    exit 1
}

# Write prompt to a temp file so we can attach it via -f.
# opencode run requires a positional message; we pass a brief directive and attach
# the full prompt as a file so OpenCode reads it as context.
$tempFile = Join-Path $env:TEMP "opencode_prompt_$([System.IO.Path]::GetRandomFileName()).md"
[System.IO.File]::WriteAllText($tempFile, $promptText, [System.Text.Encoding]::UTF8)

# Brief message that instructs OpenCode to read the attached file.
# run_opencode_scout.ps1 - scout role wrapper for OpenCode
# Change only this line vs run_opencode_agent.ps1:
$message = "You are the SCOUT. Read the attached instructions and output only the requested JSON block. Do NOT edit any file."

$pushed = $false
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
    opencode run $message -f $tempFile --model $model
    $exitCode = $LASTEXITCODE
    $ErrorActionPreference = $prevEA
}
finally {
    if ($pushed) { Pop-Location }
    Remove-Item $tempFile -ErrorAction SilentlyContinue
}

exit $exitCode
