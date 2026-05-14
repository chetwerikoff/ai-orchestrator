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
    $promptText | cmd /c claude --print --model $model --tools '""' --system-prompt $systemPrompt
    $exitCode = $LASTEXITCODE
    $ErrorActionPreference = $prevEA
}
finally {
    if ($pushed) { Pop-Location }
}

exit $exitCode
