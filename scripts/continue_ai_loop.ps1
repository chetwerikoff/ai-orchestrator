param(
    [string]$CommitMessage = "Continue AI loop",
    [int]$MaxIterations = 10,
    [switch]$NoPush,
    [string]$TestCommand = "python -m pytest",
    [string]$PostFixCommand = "",
    [string]$SafeAddPaths = "src/,tests/,README.md,scripts/,ai_loop.py,pytest.ini,.gitignore,requirements.txt,pyproject.toml,setup.cfg,.ai-loop/task.md,.ai-loop/cursor_summary.md,.ai-loop/project_summary.md"
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

if ($PostFixCommand) {
    $argsList += "-PostFixCommand"
    $argsList += $PostFixCommand
}

powershell @argsList
