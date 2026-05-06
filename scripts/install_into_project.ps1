param(
    [Parameter(Mandatory=$true)]
    [string]$TargetProject,
    [switch]$OverwriteTask
)

$Root = Resolve-Path "."
$Target = Resolve-Path $TargetProject

$TargetScripts = Join-Path $Target "scripts"
$TargetAiLoop = Join-Path $Target ".ai-loop"

New-Item -ItemType Directory -Force -Path $TargetScripts | Out-Null
New-Item -ItemType Directory -Force -Path $TargetAiLoop | Out-Null

Copy-Item (Join-Path $Root "scripts\ai_loop_auto.ps1") (Join-Path $TargetScripts "ai_loop_auto.ps1") -Force
Copy-Item (Join-Path $Root "scripts\continue_ai_loop.ps1") (Join-Path $TargetScripts "continue_ai_loop.ps1") -Force

$TaskTarget = Join-Path $TargetAiLoop "task.md"
if ($OverwriteTask -or !(Test-Path $TaskTarget)) {
    Copy-Item (Join-Path $Root "templates\task.md") $TaskTarget -Force
}

Copy-Item (Join-Path $Root "templates\codex_review_prompt.md") (Join-Path $TargetAiLoop "codex_review_prompt.md") -Force
Copy-Item (Join-Path $Root "templates\claude_final_review_prompt.md") (Join-Path $TargetAiLoop "claude_final_review_prompt.md") -Force
Copy-Item (Join-Path $Root "templates\cursor_summary_template.md") (Join-Path $TargetAiLoop "cursor_summary_template.md") -Force

Write-Host "AI git orchestrator installed into: $Target"
Write-Host "Next:"
Write-Host "1. Edit .ai-loop\task.md in the target project."
Write-Host "2. Run: powershell -ExecutionPolicy Bypass -File .\scripts\ai_loop_auto.ps1 -CommitMessage `"Your commit message`""
