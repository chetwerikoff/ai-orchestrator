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

$scriptRootReviewer = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($scriptRootReviewer)) {
    $scriptRootReviewer = Split-Path -LiteralPath $MyInvocation.MyCommand.Path -Parent
}

$projHintCodexRv = ""
if ($workspace -and (Test-Path -LiteralPath $workspace)) {
    $projHintCodexRv = [System.IO.Path]::GetFullPath(($workspace.Trim()))
}
else {
    try { $projHintCodexRv = (Get-Location).Path } catch { $projHintCodexRv = "" }
}

$codexDisplayModelRv = ""
if (-not [string]::IsNullOrWhiteSpace([string]$model)) { $codexDisplayModelRv = [string]$model }

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

    $codexLines = @()
    if ($helpText -match '(?i)--file\b') {
        $codexArgs = $codexArgs + @("--file", $tempFile)
        $codexLines = @(& codex @codexArgs 2>&1)
    } else {
        $codexLines = @(Get-Content -LiteralPath $tempFile -Raw -Encoding UTF8 | & codex @codexArgs 2>&1)
    }

    foreach ($seg in @($codexLines)) {
        Write-Output $seg
    }

    $exitCode = $LASTEXITCODE
    try {
        if ($exitCode -eq 0) {
            $capCodexRv = (@($codexLines) | ForEach-Object { "$_" }) -join "`n"
            . (Join-Path $scriptRootReviewer "record_token_usage.ps1")
            $pbRv = 0
            try {
                $pbRv = [System.Text.Encoding]::UTF8.GetByteCount($promptText)
            }
            catch {
                $pbRv = 0
            }
            Write-CliCaptureTokenUsageIfParsed `
                -CapturedText $capCodexRv `
                -ScriptName "run_codex_reviewer.ps1" `
                -Provider "codex" `
                -Model $(if ([string]::IsNullOrWhiteSpace($codexDisplayModelRv)) { "codex" } else { $codexDisplayModelRv }) `
                -Iteration 0 `
                -ProjectRootHint $projHintCodexRv `
                -Phase $(if ($null -ne $env:AI_LOOP_TOKEN_PHASE -and -not [string]::IsNullOrWhiteSpace([string]$env:AI_LOOP_TOKEN_PHASE)) { [string]$env:AI_LOOP_TOKEN_PHASE } else { "" }) `
                -Role $(if ($null -ne $env:AI_LOOP_TOKEN_ROLE -and -not [string]::IsNullOrWhiteSpace([string]$env:AI_LOOP_TOKEN_ROLE)) { [string]$env:AI_LOOP_TOKEN_ROLE } else { "" }) `
                -FixIterationIndex -1 `
                -PromptBytes $pbRv
        }
    }
    catch {
        Write-Warning "Codex reviewer token recording skipped (non-blocking): $($_.Exception.Message)"
    }
    $ErrorActionPreference = $prevEA
}
finally {
    if ($pushed) { Pop-Location }
    Remove-Item -LiteralPath $tempFile -Force -ErrorAction SilentlyContinue
}

exit $exitCode
