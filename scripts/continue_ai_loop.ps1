# Resumes ai_loop_auto.ps1 -Resume. Optional -CursorCommand / -CursorModel override
# .ai-loop/implementer.json (runtime); when omitted, auto-loop reloads persisted effective values.
param(
    [string]$CommitMessage = "Continue AI loop",
    [int]$MaxIterations = 5,
    [switch]$NoPush,
    [string]$TestCommand = "python -m pytest",
    [string]$PostFixCommand = "",
    [string]$SafeAddPaths = "src/,tests/,README.md,AGENTS.md,scripts/,docs/,templates/,ai_loop.py,pytest.ini,.gitignore,requirements.txt,pyproject.toml,setup.cfg,pyrightconfig.json,.ai-loop/task.md,.ai-loop/implementer_summary.md,.ai-loop/project_summary.md,.ai-loop/repo_map.md,.ai-loop/failures.md,.ai-loop/archive/rolls/,.ai-loop/_debug/session_draft.md",
    [string]$CursorCommand = "",
    [string]$CursorModel = "",
    [switch]$WithWrapUp
)

$argsList = @(
    "-ExecutionPolicy", "Bypass",
    "-File", ".\scripts\ai_loop_auto.ps1",
    "-Resume",
    "-MaxIterations", $MaxIterations,
    "-CommitMessage", $CommitMessage,
    "-TestCommand", $TestCommand,
    "-SafeAddPaths", $SafeAddPaths
)

if ($NoPush) {
    $argsList += "-NoPush"
}

if ($WithWrapUp) {
    $argsList += "-WithWrapUp"
}

if ($PostFixCommand) {
    $argsList += "-PostFixCommand"
    $argsList += $PostFixCommand
}

if (-not [string]::IsNullOrWhiteSpace($CursorCommand)) {
    $argsList += "-CursorCommand"
    $argsList += $CursorCommand
}

if (-not [string]::IsNullOrWhiteSpace($CursorModel)) {
    $argsList += "-CursorModel"
    $argsList += $CursorModel
}

powershell @argsList
