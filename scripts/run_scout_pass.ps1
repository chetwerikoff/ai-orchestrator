param(
    [Parameter(Mandatory)][string]$ProjectRoot,
    [string]$CommandName = ".\scripts\run_cursor_agent.ps1",
    [string]$Model = ""
)
$ErrorActionPreference = "Stop"

function Write-ScoutWarning {
    param([string]$Message)
    Write-Warning "Scout pass: $Message"
}

$root = (Resolve-Path -LiteralPath $ProjectRoot).Path
$aiLoop = Join-Path $root ".ai-loop"
$debugDir = Join-Path $aiLoop "_debug"
New-Item -ItemType Directory -Force -Path $debugDir | Out-Null

$promptPath = Join-Path $debugDir "scout_prompt.md"
$outputPath = Join-Path $debugDir "scout_output.txt"
$resultPath = Join-Path $debugDir "scout.json"

Remove-Item -LiteralPath $resultPath -Force -ErrorAction SilentlyContinue

$scoutPrompt = @'
You are the SCOUT in a local AI development loop.

Job:
- Read .ai-loop/task.md, .ai-loop/repo_map.md, AGENTS.md.
- Identify the smallest set of files relevant to the task.
- Do NOT edit any file.
- Do NOT call any non-read tool.

Output ONLY a single fenced JSON block, no prose:

```json
{
  "relevant_files": ["src/foo.py", "tests/test_foo.py"],
  "notes": "one-line summary of why these files"
}
```
'@

$enc = New-Object System.Text.UTF8Encoding $false
[System.IO.File]::WriteAllText($promptPath, $scoutPrompt + "`n", $enc)

$agentArgs = @("--print", "--trust", "--workspace", $root)
if (-not [string]::IsNullOrWhiteSpace($Model)) { $agentArgs += @("--model", $Model) }

# Auto-swap opencode_agent -> opencode_scout to avoid IMPLEMENTER role conflict.
$resolvedCommand = $CommandName
if ($CommandName -match 'run_opencode_agent') {
    $scoutWrapper = Join-Path $PSScriptRoot "run_opencode_scout.ps1"
    if (Test-Path -LiteralPath $scoutWrapper) {
        $resolvedCommand = $scoutWrapper
    } else {
        Write-ScoutWarning "run_opencode_scout.ps1 not found beside run_scout_pass.ps1; using original command (role framing may conflict)."
    }
}

try {
    $scoutPrompt | & $resolvedCommand @agentArgs *> $outputPath
}
catch {
    Write-ScoutWarning "implementer invocation failed: $($_.Exception.Message)"
    exit 0
}

if ($LASTEXITCODE -ne 0) {
    Write-ScoutWarning "implementer exited with code $LASTEXITCODE (see $outputPath)."
    exit 0
}

if (-not (Test-Path -LiteralPath $outputPath)) {
    Write-ScoutWarning "no output file at $outputPath."
    exit 0
}

$raw = Get-Content -LiteralPath $outputPath -Raw -Encoding UTF8
if ([string]::IsNullOrWhiteSpace($raw)) {
    Write-ScoutWarning "scout output was empty."
    exit 0
}

if ($raw.Length -lt 200) {
    Write-ScoutWarning "scout output is suspiciously short ($($raw.Length) bytes) - likely a session startup failure. See $outputPath."
    exit 0
}

$m = [regex]::Match($raw, '(?s)```json\s*\r?\n?(.*?)```')
if (-not $m.Success) {
    Write-ScoutWarning 'no ```json fenced block found in scout output.'
    exit 0
}

$jsonText = $m.Groups[1].Value.Trim()
try {
    $parsed = $jsonText | ConvertFrom-Json -ErrorAction Stop
}
catch {
    Write-ScoutWarning "scout JSON parse failed: $($_.Exception.Message)"
    exit 0
}

$outJson = ($parsed | ConvertTo-Json -Depth 10) + "`n"
[System.IO.File]::WriteAllText($resultPath, $outJson, $enc)
exit 0
