# No param block: keeps $input available for the pipeline.
# $input = piped prompt lines; $args = forwarded flags.

$model = "claude-haiku-4-5-20251001"

$i = 0
while ($i -lt $args.Count) {
    switch ($args[$i]) {
        "--model" { $model = $args[$i + 1]; $i += 2; break }
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

$exitCode = 1
try {
    $prevEA = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    $promptText | claude --print --model $model
    $exitCode = $LASTEXITCODE
    $ErrorActionPreference = $prevEA
}
finally {
}

exit $exitCode
