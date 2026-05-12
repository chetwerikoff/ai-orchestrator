param(
    [int]$MaxIterations = 10,
    [string]$CommitMessage = "AI loop auto update",
    [switch]$Resume,
    [switch]$NoPush,
    [string]$TestCommand = "python -m pytest",
    [string]$PostFixCommand = "",
    [string]$SafeAddPaths = "src/,tests/,README.md,AGENTS.md,scripts/,docs/,templates/,ai_loop.py,pytest.ini,.gitignore,requirements.txt,pyproject.toml,setup.cfg,.ai-loop/task.md,.ai-loop/cursor_summary.md,.ai-loop/project_summary.md"
)

$ErrorActionPreference = "Continue"

$ProjectRoot = (Resolve-Path ".").Path
$AiLoop = Join-Path $ProjectRoot ".ai-loop"
$Tmp = Join-Path $ProjectRoot ".tmp"

New-Item -ItemType Directory -Force -Path $AiLoop | Out-Null
New-Item -ItemType Directory -Force -Path $Tmp | Out-Null

# Keep pytest/temp files local to avoid Windows Temp PermissionError issues.
$env:TEMP = $Tmp
$env:TMP = $Tmp
$env:PYTEST_DEBUG_TEMPROOT = $Tmp

function Clear-AiLoopRuntimeState {
    # Duplicated from ai_loop_task_first.ps1 (no shared module). When ai_loop_auto.ps1 is spawned
    # from task-first right after Cursor, $env:AI_LOOP_CHAIN_FROM_TASK_FIRST skips deleting
    # cursor_implementation_result.md so the implementer handoff stays intact.
    $files = @(
        ".ai-loop\codex_review.md", ".ai-loop/next_cursor_prompt.md", ".ai-loop/cursor_agent_output.txt",
        ".ai-loop/cursor_implementation_output.txt", ".ai-loop/cursor_implementation_prompt.md", ".ai-loop/cursor_implementation_result.md",
        ".ai-loop/test_output.txt", ".ai-loop/test_output_before_commit.txt", ".ai-loop/last_diff.patch", ".ai-loop/final_status.md",
        ".ai-loop/git_status.txt", ".ai-loop/post_fix_output.txt", ".ai-loop/claude_final_review.md"
    )
    if ($env:AI_LOOP_CHAIN_FROM_TASK_FIRST -eq "1") {
        $files = $files | Where-Object { $_ -notmatch 'cursor_implementation_result\.md' }
    }
    foreach ($rel in $files) {
        Remove-Item (Join-Path $ProjectRoot $rel) -Force -ErrorAction SilentlyContinue
    }
}

function ConvertTo-CrtSafeArg {
    # Workaround for a Windows PowerShell 5.1 native-command quoting bug: when a splatted argv
    # element contains both whitespace and embedded double quotes, PS does not escape the inner
    # quotes correctly, and node-CRT re-splits the argument so tokens like `->` leak out as
    # standalone args (rejected by commander.js as unknown options). Pre-escape per MS CRT rules:
    # double any run of backslashes that immediately precedes a quote, then turn the quote into \".
    param([string]$Value)
    return [regex]::Replace($Value, '(\\*)"', { param($m) ($m.Groups[1].Value * 2) + '\"' })
}

function Write-FinalStatus {
    param([string]$Text)
    $Text | Set-Content (Join-Path $AiLoop "final_status.md") -Encoding UTF8
}

function Ensure-AiLoopFiles {
    $projectSummary = Join-Path $AiLoop "project_summary.md"
    $cursorSummary = Join-Path $AiLoop "cursor_summary.md"
    $taskFile = Join-Path $AiLoop "task.md"

    if (!(Test-Path $projectSummary)) {
        @"
# Project Summary

## Project purpose

TODO: Describe the purpose of this project.

## Current architecture

TODO: List main modules/components.

## Current pipeline / workflow

TODO: Describe workflow.

## Important design decisions

- TODO

## Known risks / constraints

- TODO

## Current stage

TODO

## Last completed task

TODO

## Next likely steps

1. TODO

## Notes for future AI sessions

- Keep durable project-level context here.
"@ | Set-Content $projectSummary -Encoding UTF8
    }

    if (!(Test-Path $cursorSummary)) {
        "# Cursor Summary`n`nNo task has been completed yet." | Set-Content $cursorSummary -Encoding UTF8
    }

    if (!(Test-Path $taskFile)) {
        "# Task: TODO`n`nDescribe the current task." | Set-Content $taskFile -Encoding UTF8
    }
}

function Invoke-CommandToFile {
    param(
        [string]$Command,
        [string]$OutputFile
    )

    Write-Host "Running: $Command"
    powershell -NoProfile -Command $Command *> $OutputFile
    return $LASTEXITCODE
}

function Get-SafeAddPathList {
    if (!$SafeAddPaths) { return @() }
    return $SafeAddPaths.Split(",") | ForEach-Object { $_.Trim() } | Where-Object { $_ }
}

function Add-IntentToAddForReview {
    foreach ($path in Get-SafeAddPathList) {
        if (Test-Path $path) {
            git add -N $path 2>$null
        }
    }
}

function Save-TestAndDiff {
    Ensure-AiLoopFiles

    Write-Host ""
    Write-Host "Running tests..."
    Invoke-CommandToFile $TestCommand (Join-Path $AiLoop "test_output.txt") | Out-Null
    $testExit = $LASTEXITCODE

    Write-Host "Saving git status and diff..."
    git status --short > (Join-Path $AiLoop "git_status.txt")

    Add-IntentToAddForReview
    git diff > (Join-Path $AiLoop "last_diff.patch")

    return $testExit
}

function Run-PostFixCommand {
    if (!$PostFixCommand) {
        return 0
    }

    Write-Host ""
    Write-Host "Running post-fix command..."
    Invoke-CommandToFile $PostFixCommand (Join-Path $AiLoop "post_fix_output.txt") | Out-Null
    return $LASTEXITCODE
}

function Run-CodexReview {
    Ensure-AiLoopFiles

    $prompt = @"
You are the reviewer in an authenticated development loop.

Read:
- .ai-loop/project_summary.md
- .ai-loop/task.md
- .ai-loop/cursor_summary.md
- .ai-loop/last_diff.patch
- .ai-loop/test_output.txt
- .ai-loop/git_status.txt

Review the latest changes.

Important:
- project_summary.md is durable project context.
- task.md is the current task contract.
- The user explicitly authorized the scope described in .ai-loop/task.md.
- If Cursor deferred the task instead of implementing it, mark FIX_REQUIRED and provide a concrete fix prompt.
- If new files are required by the task, make sure they are present in the diff/status.
- Do not ask for manual steps unless absolutely required.

Check:
1. Was the task completed?
2. Are tests meaningful and passing?
3. Are there Critical or High issues?
4. Is project_summary.md updated when durable project-level context changed?
5. Is it safe to run the final test gate, commit, and push?

Return exactly:

VERDICT: PASS or FIX_REQUIRED

CRITICAL:
- ...

HIGH:
- ...

MEDIUM:
- ...

FIX_PROMPT_FOR_CURSOR:
If fixes are required, write a concrete prompt for Cursor.
If no fixes are required, write: none

FINAL_NOTE:
Brief summary.
"@

    Write-Host ""
    Write-Host "Running Codex review..."

    $codexArgs = @("exec", (ConvertTo-CrtSafeArg -Value $prompt))
    & codex @codexArgs > (Join-Path $AiLoop "codex_review.md")
    return $LASTEXITCODE
}

function Get-ReviewVerdict {
    param(
        [string]$ReviewFile
    )

    if (!(Test-Path $ReviewFile)) {
        return "FIX_REQUIRED"
    }

    $review = Get-Content $ReviewFile -Raw

    if ($review -match "VERDICT:\s*PASS") {
        return "PASS"
    }

    return "FIX_REQUIRED"
}

function Get-CodexVerdict {
    return Get-ReviewVerdict -ReviewFile (Join-Path $AiLoop "codex_review.md")
}

function Extract-FixPromptFromFile {
    param(
        [string]$ReviewFile,
        [string]$OutputPromptFile
    )

    if (!(Test-Path $ReviewFile)) {
        return $false
    }

    $review = Get-Content $ReviewFile -Raw

    # Codex sometimes omits or renames FINAL_NOTE; still recover the fix prompt when the delimiter exists.
    $match = [regex]::Match(
        $review,
        "FIX_PROMPT_FOR_CURSOR:\s*(?<prompt>[\s\S]*?)FINAL_NOTE:",
        [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
    )

    $prompt = $null
    if ($match.Success) {
        $prompt = $match.Groups["prompt"].Value.Trim()
    }
    else {
        $matchTail = [regex]::Match(
            $review,
            "FIX_PROMPT_FOR_CURSOR:\s*(?<prompt>[\s\S]*)",
            [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
        )

        if (!$matchTail.Success) {
            return $false
        }

        $prompt = $matchTail.Groups["prompt"].Value.Trim()
    }

    if (!$prompt -or $prompt -eq "none") {
        Write-Host "Extract-FixPromptFromFile: extracted prompt was empty or 'none'."
        return $false
    }

    $prompt | Set-Content $OutputPromptFile -Encoding UTF8
    return $true
}

function Extract-FixPrompt {
    $nextPromptFile = Join-Path $AiLoop "next_cursor_prompt.md"
    $codexReview = Join-Path $AiLoop "codex_review.md"
    return Extract-FixPromptFromFile -ReviewFile $codexReview -OutputPromptFile $nextPromptFile
}

function Run-CursorFix {
    Ensure-AiLoopFiles

    $cursorPrompt = @"
Read:
- .ai-loop/project_summary.md
- .ai-loop/next_cursor_prompt.md
- .ai-loop/task.md if needed

Fix only the issues described in .ai-loop/next_cursor_prompt.md.

Important rules:
- project_summary.md is durable project-level memory.
- The user explicitly authorized the task and the fix prompt.
- If .ai-loop/next_cursor_prompt.md asks to implement the full task from .ai-loop/task.md, do it. Do not refuse because of scope.
- Do not start unrelated features.
- Do not make unrelated refactors.
- Preserve existing behavior unless the fix prompt explicitly asks to change it.
- Do not commit or push; the PowerShell orchestrator handles git.

After changes:
1. Run the configured test command if applicable.
2. If task-specific CLI command is described in .ai-loop/task.md, run it when inputs exist; otherwise document why it was skipped.
3. Update .ai-loop/cursor_summary.md with:
   - changed files
   - test result
   - implementation summary
   - task-specific outputs or skipped live-run reason
   - remaining risks
4. Update .ai-loop/project_summary.md with durable project-level changes only:
   - new modules/components
   - architecture/pipeline changes
   - important design decisions
   - current stage
   - next likely steps
"@

    Write-Host ""
    Write-Host "Running Cursor agent in non-interactive mode..."

    # Prompt via stdin to run_cursor_agent.ps1, which calls node.exe directly so stdin
    # is never dropped by the cmd.exe -> powershell.exe chain in cursor-agent.cmd.
    $cursorArgs = @("--print", "--trust", "--workspace", $ProjectRoot)
    $runWrapper = Join-Path $PSScriptRoot "run_cursor_agent.ps1"
    $cursorPrompt | & $runWrapper @cursorArgs *> (Join-Path $AiLoop "cursor_agent_output.txt")
    return $LASTEXITCODE
}

function Stage-SafeProjectFiles {
    Write-Host "Staging safe project files..."

    foreach ($path in Get-SafeAddPathList) {
        if (Test-Path $path) {
            git add $path
        }
    }

    # Intentionally do NOT stage runtime artifacts:
    # .ai-loop/codex_review.md
    # .ai-loop/last_diff.patch
    # .ai-loop/test_output.txt
    # .ai-loop/test_output_before_commit.txt
    # .ai-loop/next_cursor_prompt.md
    # .ai-loop/final_status.md
    # .tmp/
    # input/
    # output/
}

function Commit-And-Push {
    Ensure-AiLoopFiles

    Write-Host ""
    Write-Host "Preparing Git commit..."

    Write-Host "Running final test gate before commit..."
    Invoke-CommandToFile $TestCommand (Join-Path $AiLoop "test_output_before_commit.txt") | Out-Null

    if ($LASTEXITCODE -ne 0) {
        Write-FinalStatus "ABORTED: tests failed before commit. Push skipped."
        Write-Host "ABORTED: tests failed before commit. Push skipped."
        exit 5
    }

    Add-IntentToAddForReview
    git diff > (Join-Path $AiLoop "last_diff.patch")
    git status --short > (Join-Path $AiLoop "git_status.txt")

    $status = git status --porcelain

    if (!$status) {
        Write-Host "No changes to commit."
        return
    }

    Stage-SafeProjectFiles

    $staged = git diff --cached --name-only

    if (!$staged) {
        Write-Host "No safe staged changes to commit."
        return
    }

    Write-Host "Creating commit..."
    git commit -m $CommitMessage

    if ($LASTEXITCODE -ne 0) {
        Write-Host "Git commit failed. Push skipped."
        Write-FinalStatus "PASS, but git commit failed. Manual check required."
        exit 3
    }

    if (!$NoPush) {
        Write-Host "Pushing to remote..."
        git push

        if ($LASTEXITCODE -ne 0) {
            Write-Host "Git push failed."
            Write-FinalStatus "PASS and committed, but git push failed. Manual push required."
            exit 4
        }

        Write-Host "Git push completed."
    }
    else {
        Write-Host "NoPush enabled. Commit created locally only."
    }
}

function Try-ResumeFromExistingReview {
    Ensure-AiLoopFiles

    if (!$Resume) {
        return $false
    }

    Write-Host ""
    Write-Host "Resume mode enabled."

    $nextPromptFile = Join-Path $AiLoop "next_cursor_prompt.md"

    if (Test-Path $nextPromptFile) {
        Write-Host "Resuming from existing next_cursor_prompt.md..."
        Run-CursorFix | Out-Null
        return $true
    }

    $codexReview = Join-Path $AiLoop "codex_review.md"
    if (Test-Path $codexReview) {
        $codexVerdict = Get-CodexVerdict

        if ($codexVerdict -eq "PASS") {
            Write-Host "Existing Codex verdict is PASS. Running final test gate, commit, and push."
            Commit-And-Push
            Write-FinalStatus "PASS from resume mode. Changes committed and pushed if NoPush was not enabled."
            Write-Host "Final status: PASS"
            exit 0
        }

        if (Extract-FixPrompt) {
            Write-Host "Extracted fix prompt from existing Codex review."
            Run-CursorFix | Out-Null
            return $true
        }
    }

    Write-Host "No usable existing review/prompt found. Starting normal loop."
    return $false
}

Ensure-AiLoopFiles

if (-not $Resume) {
    Clear-AiLoopRuntimeState
}

$resumed = Try-ResumeFromExistingReview

if ($resumed) {
    Write-Host ""
    Write-Host "Resume fix completed. Continuing with review loop..."
}

for ($i = 1; $i -le $MaxIterations; $i++) {
    Write-Host ""
    Write-Host "=============================="
    Write-Host "AI LOOP ITERATION $i / $MaxIterations"
    Write-Host "=============================="

    Save-TestAndDiff | Out-Null
    Run-PostFixCommand | Out-Null

    $porcelainLines = @(git status --porcelain --untracked-files=all 2>$null)
    $hasWork = $false
    foreach ($ln in $porcelainLines) {
        if (-not [string]::IsNullOrWhiteSpace($ln)) {
            $hasWork = $true
            break
        }
    }
    if (-not $hasWork) {
        if ($i -eq 1) {
            Write-FinalStatus @"
STATUS: FAILED
REASON: REVIEW_STARTED_ON_CLEAN_TREE
DETAIL: Working tree is clean before Codex review. Use scripts/ai_loop_task_first.ps1 when starting from scratch with Cursor, or make changes before calling REVIEW-only mode.
"@
            Write-Host ""
            Write-Host "Clean tree on iteration 1: skipping Codex. Prefer task-first (ai_loop_task_first.ps1) when the working tree has no changes yet." -ForegroundColor Yellow
            exit 6
        }
        Write-FinalStatus @"
STATUS: FAILED
REASON: NO_CHANGES_AFTER_CURSOR_FIX
DETAIL: No working-tree changes before Codex review on iteration $i after the Cursor fix pass.
"@
        Write-Host ""
        Write-Host "Iteration $i`: working tree clean before Codex (Cursor fix produced no git-visible changes). See .ai-loop\final_status.md" -ForegroundColor Yellow
        exit 7
    }

    Run-CodexReview | Out-Null

    $codexVerdict = Get-CodexVerdict

    if ($codexVerdict -eq "PASS") {
        Write-Host ""
        Write-Host "Codex verdict: PASS"

        Commit-And-Push

        Write-FinalStatus "PASS after iteration $i. Codex=PASS. Changes committed and pushed if NoPush was not enabled."

        Write-Host ""
        Write-Host "Final status: PASS"
        Write-Host "See:"
        Write-Host ".ai-loop\final_status.md"
        Write-Host ".ai-loop\codex_review.md"
        Write-Host ".ai-loop\cursor_summary.md"
        Write-Host ".ai-loop\project_summary.md"

        exit 0
    }

    $hasPrompt = Extract-FixPrompt

    if (!$hasPrompt) {
        Write-FinalStatus "STOPPED: Codex requested fixes, but no fix prompt was extracted."
        Write-Host ""
        Write-Host "Stopped: Codex requested fixes, but no fix prompt was extracted."
        Write-Host "See:"
        Write-Host ".ai-loop\codex_review.md"
        exit 1
    }

    Run-CursorFix | Out-Null
}

Write-FinalStatus "STOPPED: max iterations reached. Manual review required."

Write-Host ""
Write-Host "Stopped: max iterations reached. Manual review required."
Write-Host "See:"
Write-Host ".ai-loop\final_status.md"
Write-Host ".ai-loop\codex_review.md"
Write-Host ".ai-loop\cursor_summary.md"
Write-Host ".ai-loop\project_summary.md"

exit 2
