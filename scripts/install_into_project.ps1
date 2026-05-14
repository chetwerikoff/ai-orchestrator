param(
    [Parameter(Mandatory=$true)]
    [string]$TargetProject,
    [switch]$OverwriteTask,
    [switch]$OverwriteProjectSummary,
    [switch]$OverwriteOpencodeConfig
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
Copy-Item (Join-Path $Root "scripts\run_cursor_agent.ps1") (Join-Path $TargetScripts "run_cursor_agent.ps1") -Force
Copy-Item (Join-Path $Root "scripts\run_opencode_agent.ps1") (Join-Path $TargetScripts "run_opencode_agent.ps1") -Force
Copy-Item (Join-Path $Root "scripts\run_scout_pass.ps1") (Join-Path $TargetScripts "run_scout_pass.ps1") -Force
Copy-Item (Join-Path $Root "scripts\wrap_up_session.ps1") (Join-Path $TargetScripts "wrap_up_session.ps1") -Force
Copy-Item (Join-Path $Root "scripts\promote_session.ps1") (Join-Path $TargetScripts "promote_session.ps1") -Force
Copy-Item (Join-Path $Root "scripts\build_repo_map.ps1") (Join-Path $TargetScripts "build_repo_map.ps1") -Force
Copy-Item (Join-Path $Root "scripts\filter_pytest_failures.py") (Join-Path $TargetScripts "filter_pytest_failures.py") -Force

$TaskTarget = Join-Path $TargetAiLoop "task.md"
if ($OverwriteTask -or !(Test-Path $TaskTarget)) {
    Copy-Item (Join-Path $Root "templates\task.md") $TaskTarget -Force
}

$ProjectSummaryTarget = Join-Path $TargetAiLoop "project_summary.md"
if ($OverwriteProjectSummary -or !(Test-Path $ProjectSummaryTarget)) {
    Copy-Item (Join-Path $Root "templates\project_summary.md") $ProjectSummaryTarget -Force
}

Copy-Item (Join-Path $Root "templates\codex_review_prompt.md") (Join-Path $TargetAiLoop "codex_review_prompt.md") -Force
Copy-Item (Join-Path $Root "templates\implementer_summary_template.md") (Join-Path $TargetAiLoop "implementer_summary_template.md") -Force

$OpencodeTarget = Join-Path $Target "opencode.json"
$opencodeExisted = Test-Path $OpencodeTarget
if ($OverwriteOpencodeConfig) {
    Copy-Item (Join-Path $Root "templates\opencode.json") $OpencodeTarget -Force
} elseif (!$opencodeExisted) {
    Copy-Item (Join-Path $Root "templates\opencode.json") $OpencodeTarget -Force
}

Write-Host "AI orchestrator installed into: $Target"
if ($opencodeExisted -and -not $OverwriteOpencodeConfig) {
    Write-Host "Left existing opencode.json unchanged (pass -OverwriteOpencodeConfig to replace)."
}
Write-Host "Next:"
Write-Host "1. Create AGENTS.md at the target project root (working rules for agents in that project)."
Write-Host "2. Edit .ai-loop\task.md in the target project."
Write-Host "3. Review/update .ai-loop\project_summary.md in the target project."
Write-Host "4. For a NEW task, run: powershell -ExecutionPolicy Bypass -File .\scripts\ai_loop_task_first.ps1 -CommitMessage `"Your commit message`""
Write-Host "5. For review/fix of already existing changes, run: powershell -ExecutionPolicy Bypass -File .\scripts\ai_loop_auto.ps1 -CommitMessage `"Your commit message`""
