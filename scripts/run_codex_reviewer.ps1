# No param block: keeps $input available for the pipeline.
# $input = piped prompt; $args = forwarded flags (--workspace, --model).

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

$tempFile = Join-Path $env:TEMP "codex_review_$([System.IO.Path]::GetRandomFileName()).md"
[System.IO.File]::WriteAllText($tempFile, $promptText, [System.Text.Encoding]::UTF8)

$pushed = $false
$exitCode = 1
try {
    if ($workspace -and (Test-Path -LiteralPath $workspace)) {
        Push-Location $workspace
        $pushed = $true
    }

    $helpText = ""
    try {
        $prevProbeEA = $ErrorActionPreference
        $ErrorActionPreference = "SilentlyContinue"
        $helpText = (& codex exec --help | Out-String)
        $ErrorActionPreference = $prevProbeEA
    } catch { }

    $codexArgs = @()
    if (-not [string]::IsNullOrWhiteSpace($model)) {
        $codexArgs = @("--model", $model)
    }
    $codexArgs = $codexArgs + @("exec")

    $prevEA = $ErrorActionPreference
    $ErrorActionPreference = "Continue"

    if ($helpText -match '(?i)--file\b') {
        $codexArgs = $codexArgs + @("--file", $tempFile)
        & codex @codexArgs
    } else {
        Get-Content -LiteralPath $tempFile -Raw -Encoding UTF8 | & codex @codexArgs
    }

    $exitCode = $LASTEXITCODE
    $ErrorActionPreference = $prevEA
}
finally {
    if ($pushed) { Pop-Location }
    Remove-Item -LiteralPath $tempFile -Force -ErrorAction SilentlyContinue
}

exit $exitCode
