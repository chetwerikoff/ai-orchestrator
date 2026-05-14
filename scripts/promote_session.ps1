param()
$ErrorActionPreference = "Stop"

$projectRoot = (Resolve-Path ".").Path
$aiLoop = Join-Path $projectRoot ".ai-loop"
$draftPath = Join-Path $aiLoop "_debug\session_draft.md"
$failuresPath = Join-Path $aiLoop "failures.md"
$seedHeaderLines = @(
    "# Failures log",
    "# Appended by scripts/promote_session.ps1 $([char]0x2014) do not edit manually.",
    "# Rotate: >200 lines overflow to archive/failures/<date>.md"
)
$utf8NoBom = New-Object System.Text.UTF8Encoding $false

function Ensure-FileWithSeedHeader {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        [System.IO.File]::WriteAllText($Path, ($script:seedHeaderLines -join "`n") + "`n", $script:utf8NoBom)
    }
}

if (-not (Test-Path -LiteralPath $draftPath)) {
    Write-Warning "promote_session: no session draft at $draftPath - nothing to promote."
    exit 0
}

Ensure-FileWithSeedHeader -Path $failuresPath

$draftContent = [System.IO.File]::ReadAllText($draftPath, $utf8NoBom)
if ([string]::IsNullOrWhiteSpace($draftContent)) {
    Write-Warning "promote_session: draft is empty; removing draft only."
    Remove-Item -LiteralPath $draftPath -Force -ErrorAction SilentlyContinue
    exit 0
}

[System.IO.File]::AppendAllText($failuresPath, "`n---`n" + $draftContent.TrimEnd() + "`n", $utf8NoBom)

# Draft snapshot destination: `.ai-loop/archive/rolls/` (timestamped filenames).
$rollsDir = Join-Path $aiLoop "archive\rolls"
New-Item -ItemType Directory -Force -Path $rollsDir | Out-Null
$stamp = Get-Date -Format "yyyy-MM-dd_HH-mm"
$rolledPath = Join-Path $rollsDir ("{0}.md" -f $stamp)
[System.IO.File]::WriteAllText($rolledPath, $draftContent.TrimEnd() + "`n", $utf8NoBom)

Remove-Item -LiteralPath $draftPath -Force

function Rotate-LargeFailuresLog {
    param([string]$Path)
    $allLines = @([System.IO.File]::ReadAllLines($Path, $utf8NoBom))
    if ($allLines.Length -le 200) {
        return $null
    }
    if ($allLines.Length -lt 3) {
        return $null
    }

    $header = @($allLines[0], $allLines[1], $allLines[2])
    $body = @()
    if ($allLines.Length -gt 3) {
        $body = @($allLines[3..($allLines.Length - 1)])
    }

    # Cap total rows at 200: freeze first three header lines (seed) and retain newest body slots.
    $bodySlots = 200 - $header.Length
    if ($body.Length -le $bodySlots) {
        return $null
    }

    $overflowCount = $body.Length - $bodySlots
    $overflow = @($body[0..($overflowCount - 1)])
    $keptBody = @($body[$overflowCount..($body.Length - 1)])

    $failuresArchiveDir = Join-Path $aiLoop "archive\failures"
    New-Item -ItemType Directory -Force -Path $failuresArchiveDir | Out-Null
    $day = Get-Date -Format "yyyy-MM-dd"
    $slicePath = Join-Path $failuresArchiveDir ("{0}.md" -f $day)
    $sliceHeader = "# Archived failures snippet`n"
    if (Test-Path -LiteralPath $slicePath) {
        [System.IO.File]::AppendAllText($slicePath, "`n---`n" + ($overflow -join "`n") + "`n", $utf8NoBom)
    }
    else {
        $sliceTxt = $sliceHeader + ($overflow -join "`n").TrimEnd() + "`n"
        [System.IO.File]::WriteAllText($slicePath, $sliceTxt, $utf8NoBom)
    }

    $newLines = @($header + $keptBody)
    [System.IO.File]::WriteAllText($Path, ($newLines -join "`n").TrimEnd() + "`n", $utf8NoBom)
    return @{ SlicePath = $slicePath; OverflowLines = $overflow.Length; FinalLines = $newLines.Length }
}

$rotation = Rotate-LargeFailuresLog -Path $failuresPath

$postLines = @([System.IO.File]::ReadAllLines($failuresPath, $utf8NoBom))
Write-Host "promote_session: appended draft to failures.md ($($postLines.Length) lines)."
Write-Host "promote_session: archived draft roll -> $(Split-Path $rolledPath -Leaf)"
if ($rotation) {
    Write-Host "promote_session: rotated $($rotation.OverflowLines) overflow lines -> $($rotation.SlicePath)"
    Write-Host "promote_session: failures.md trimmed to $($rotation.FinalLines) lines total."
}

exit 0
