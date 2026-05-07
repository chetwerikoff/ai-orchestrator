param(
    [Parameter(Mandatory=$true)]
    [string]$TargetProject,
    [switch]$OverwriteTask,
    [switch]$OverwriteProjectSummary
)

$Root = Resolve-Path "."
$Target = Resolve-Path $TargetProject

$TargetScripts = Join-Path $Target "scripts"
$TargetAiLoop = Join-Path $Target ".ai-loop"

New-Item -ItemType Directory -Force -Path $TargetScripts | Out-Null
New-Item -ItemType Directory -Force -Path $TargetAiLoop | Out-Null

Copy-Item (Join-Path $Root "scripts\ai_loop_auto.ps1") (Join-Path $TargetScripts "ai_loop_auto.ps1") -Force
Copy-Item (Join-Path $Root "scripts\ai_loop_task_first.ps1") (Join-Path $TargetScripts "ai_loop_task_first.ps1") -Force
Copy-Item (Join-Path $Root "scripts\continue_ai_loop.ps1") (Join-Path $TargetScripts "continue_ai_loop.ps1") -Force

$TaskTarget = Join-Path $TargetAiLoop "task.md"
if ($OverwriteTask -or !(Test-Path $TaskTarget)) {
    Copy-Item (Join-Path $Root "templates\task.md") $TaskTarget -Force
}

$ProjectSummaryTarget = Join-Path $TargetAiLoop "project_summary.md"
if ($OverwriteProjectSummary -or !(Test-Path $ProjectSummaryTarget)) {
    Copy-Item (Join-Path $Root "templates\project_summary.md") $ProjectSummaryTarget -Force
}

Copy-Item (Join-Path $Root "templates\codex_review_prompt.md") (Join-Path $TargetAiLoop "codex_review_prompt.md") -Force
Copy-Item (Join-Path $Root "templates\cursor_summary_template.md") (Join-Path $TargetAiLoop "cursor_summary_template.md") -Force

Write-Host "AI git orchestrator installed into: $Target"
Write-Host "Next:"
Write-Host "1. Edit .ai-loop\task.md in the target project."
Write-Host "2. Review/update .ai-loop\project_summary.md in the target project."
Write-Host "3. For a NEW task, run: powershell -ExecutionPolicy Bypass -File .\scripts\ai_loop_task_first.ps1 -CommitMessage `"Your commit message`""
Write-Host "4. For review/fix of already existing changes, run: powershell -ExecutionPolicy Bypass -File .\scripts\ai_loop_auto.ps1 -CommitMessage `"Your commit message`""
