# No param block: keeps $input available for the pipeline.
# $input = piped prompt; $args = forwarded flags (--workspace, --model).

function ConvertTo-CrtSafeArg {
    # Omit top-level/param syntax per wrapper contract tests.
    $Value = $args[0]
    return [regex]::Replace([string]$Value, '(\\*)"', { ($args[0].Groups[1].Value * 2) + '\"' })
}

$workspace = $null
$model = ""

$i = 0
while ($i -lt $args.Count) {
    switch ($args[$i]) {
        "--workspace" { $workspace = $args[$i + 1]; $i += 2; break }
        "--model" { $model = $args[$i + 1]; $i += 2; break }
        default { $i++ }
    }
}

$promptText = ($input | Out-String).Trim()
if ([string]::IsNullOrWhiteSpace($promptText)) {
    Write-Error "run_codex_reviewer: no prompt received on stdin."
    exit 1
}

$pushed = $false
try {
    if ($workspace -and (Test-Path -LiteralPath $workspace)) {
        Push-Location $workspace
        $pushed = $true
    }
    $codexArgs = @("exec", (ConvertTo-CrtSafeArg $promptText))
    if (-not [string]::IsNullOrWhiteSpace($model)) {
        $codexArgs = @("--model", $model) + $codexArgs
    }
    $prevEA = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    & codex @codexArgs
    $exitCode = $LASTEXITCODE
    $ErrorActionPreference = $prevEA
}
finally {
    if ($pushed) { Pop-Location }
}

exit $exitCode
