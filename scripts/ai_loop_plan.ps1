param(
    [string]$Ask = "",
    [string]$AskFile = ".ai-loop\user_ask.md",
    [string]$PlannerCommand = ".\scripts\run_claude_planner.ps1",
    [string]$PlannerModel = "",
    [string]$Out = ".ai-loop\task.md",
    [switch]$Force,
    [switch]$WithReview,
    [int]$MaxReviewIterations = 3,
    [string]$ReviewerCommand = ".\scripts\run_codex_reviewer.ps1",
    [string]$ReviewerModel = ""
)
$ErrorActionPreference = "Stop"
$ProjectRoot = (Resolve-Path ".").Path
if ($MaxReviewIterations -lt 1) { Write-Warning "MaxReviewIterations ($MaxReviewIterations) is below minimum; clamping to 1."; $MaxReviewIterations = 1 }
if ($MaxReviewIterations -gt 3) {
    Write-Warning "MaxReviewIterations ($MaxReviewIterations) exceeds hard cap of 3; clamping to 3 to bound reviewer/planner churn (hard cap cannot be overridden)."
    $MaxReviewIterations = 3
}
$resolvedAsk = ""
if (-not [string]::IsNullOrWhiteSpace($Ask)) { $resolvedAsk = $Ask }
elseif (Test-Path -LiteralPath $AskFile) { $resolvedAsk = [System.IO.File]::ReadAllText((Resolve-Path -LiteralPath $AskFile).Path) }
else {
    Write-Warning "No ask provided. Use -Ask `"...`" or create $AskFile."
    exit 1
}
$planPromptPath = Join-Path $ProjectRoot ".ai-loop\planner_prompt.md"
if (-not (Test-Path -LiteralPath $planPromptPath)) { $planPromptPath = Join-Path $ProjectRoot "templates\planner_prompt.md" }
if (-not (Test-Path -LiteralPath $planPromptPath)) {
    Write-Warning "Planner prompt not found at .ai-loop\planner_prompt.md or templates\planner_prompt.md."
    exit 1
}
Write-Host "Using planner prompt: $planPromptPath"
$agentsPath = Join-Path $ProjectRoot "AGENTS.md"
$summaryPath = Join-Path $ProjectRoot ".ai-loop\project_summary.md"
$cmdPath = $PlannerCommand
if (-not (Test-Path -LiteralPath $cmdPath)) {
    $rel = $PlannerCommand -replace '^\.\\', ''
    $alt = Join-Path $ProjectRoot $rel
    if (Test-Path -LiteralPath $alt) { $cmdPath = $alt }
}
$reviewerCmdPath = $null
if ($WithReview) {
    $reviewerCmdPath = $ReviewerCommand
    if (-not (Test-Path -LiteralPath $reviewerCmdPath)) {
        $relr = $ReviewerCommand -replace '^\.\\', ''
        $altr = Join-Path $ProjectRoot $relr
        if (Test-Path -LiteralPath $altr) { $reviewerCmdPath = $altr }
    }
    $revHere = Join-Path $ProjectRoot ".ai-loop\reviewer_prompt.md"
    $revTmpl = Join-Path $ProjectRoot "templates\reviewer_prompt.md"
    if (-not (Test-Path -LiteralPath $reviewerCmdPath)) { Write-Warning "missing $ReviewerCommand Path: $reviewerCmdPath"; exit 1 }
    if (-not ((Test-Path -LiteralPath $revHere) -or (Test-Path -LiteralPath $revTmpl))) {
        Write-Warning "Reviewer prompt not found at .ai-loop\reviewer_prompt.md or templates\reviewer_prompt.md."
        exit 1
    }
}
if (-not (Test-Path -LiteralPath $agentsPath)) { Write-Warning "missing AGENTS.md Path: $agentsPath"; exit 1 }
if (-not (Test-Path -LiteralPath $summaryPath)) { Write-Warning "missing .ai-loop/project_summary.md Path: $summaryPath"; exit 1 }
if (-not (Test-Path -LiteralPath $cmdPath)) { Write-Warning "missing $PlannerCommand Path: $cmdPath"; exit 1 }

function Test-PlannerOutputSanity {
    param([Parameter(Mandatory)][string]$Output)
    $first = ($Output -split "`r?`n", 2)[0].TrimStart()
    if (-not $first.StartsWith("# Task:")) {
        return @{ Ok = $false; Reason = "Planner output does not start with '# Task:' (looks like a preamble or refusal)." }
    }
    foreach ($h in @('## Goal', '## Scope', '## Files in scope', '## Files out of scope', '## Tests', '## Important')) {
        if ($Output -notmatch ('(?m)^' + [regex]::Escape($h) + '\b')) {
            return @{ Ok = $false; Reason = "Planner output is missing required heading '$h'." }
        }
    }
    return @{ Ok = $true; Reason = "" }
}
function Normalize-PlannerOutput {
    param([Parameter(Mandatory)][string]$Output)
    $lines = @($Output -split "`r?`n")
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $candidate = $lines[$i].TrimStart([char]0xFEFF).TrimStart()
        if ($candidate.StartsWith("# Task:")) {
            $lines[$i] = $candidate
            return (@($lines[$i..($lines.Count - 1)]) -join "`n").TrimEnd()
        }
    }
    return $Output
}
function Test-ReviewerOutputStrict {
    param([Parameter(Mandatory)][string]$Output)
    $t = $Output.Trim()
    if ([string]::IsNullOrWhiteSpace($t)) { return @{ Ok = $false } }
    if ($t -eq "NO_BLOCKING_ISSUES") { return @{ Ok = $true } }
    $lines = @($t -split "`r?`n")
    $hitIssues = $false
    $bullets = 0
    foreach ($ln in $lines) {
        if ([string]::IsNullOrWhiteSpace($ln)) { continue }
        if (-not $hitIssues) {
            if ($ln -match '^\s*ISSUES:\s*$') {
                $hitIssues = $true
                continue
            }
            return @{ Ok = $false }
        }
        if (-not ($ln -match '^\s*-\s*\[(logic|complexity|scope|missing)\]\s+\S')) {
            return @{ Ok = $false }
        }
        $bullets++
    }
    if (-not ($hitIssues -and $bullets -ge 1)) { return @{ Ok = $false } }
    return @{ Ok = $true }
}
function Get-FilesInScopeSummary {
    param([Parameter(Mandatory)][string]$Text)
    $lines = $Text -split "`r?`n"
    $in = $false
    $items = @()
    foreach ($ln in $lines) {
        if ($ln -match '^\s*##\s+Files in scope\s*$') { $in = $true; continue }
        if ($in -and $ln -match '^\s*##\s+') { break }
        if (-not $in) { continue }
        if ($ln -notmatch '^\s*[-*]\s+(.+)$') { continue }
        $raw = $Matches[1].Trim()
        $new = $raw -match '\(new\)'
        $tok = if ($raw -match '^`([^`]+)`') { $Matches[1] } elseif ($raw -match '^(\S+)') { $Matches[1].Trim('`') } else { "" }
        if (-not $tok) { continue }
        $items += $(if ($new) { "$tok (new)" } else { $tok })
    }
    return $items
}
$planPromptBody = [System.IO.File]::ReadAllText($planPromptPath)
$agentsBody = [System.IO.File]::ReadAllText($agentsPath)
$summaryBody = [System.IO.File]::ReadAllText($summaryPath)
$repoPath = Join-Path $ProjectRoot ".ai-loop\repo_map.md"
$repoMapBody = ""
$repoBlock = ""
if (Test-Path -LiteralPath $repoPath) {
    $repoMapBody = [System.IO.File]::ReadAllText($repoPath)
    $repoBlock = "`n`n## repo_map.md`n" + $repoMapBody
} else {
    Write-Warning "repo_map.md is missing ? planner context will be limited. Run scripts/build_repo_map.ps1 first for better results."
}
$prompt = $planPromptBody + "`n`n## AGENTS.md`n" + $agentsBody + "`n`n## project_summary.md`n" + $summaryBody + $repoBlock + "`n`n## USER ASK`n" + $resolvedAsk
$backupMade = $false
if ((Test-Path -LiteralPath $Out) -and -not $Force) {
    Move-Item -Force -LiteralPath $Out -Destination "$Out.bak"
    $backupMade = $true
}
$tmpOut = "$Out.tmp"
$script:ExitCode = 0
try {
    $pwArgs = @("--workspace", $ProjectRoot)
    if (-not [string]::IsNullOrWhiteSpace($PlannerModel)) { $pwArgs += @("--model", $PlannerModel) }
    $rawLines = @($prompt | & $cmdPath @pwArgs)
    $output = ($rawLines | ForEach-Object { "$_" }) -join "`n"
    if ($LASTEXITCODE -ne 0) { $script:ExitCode = 1; throw "Planner wrapper exited with code $LASTEXITCODE." }
    $output = Normalize-PlannerOutput -Output $output
    $sanityInit = Test-PlannerOutputSanity -Output $output
    if (-not $sanityInit.Ok) { $script:ExitCode = 2; throw $sanityInit.Reason }
    $writeText = $output
    if ($WithReview) {
        $reviewerPromptPath = Join-Path $ProjectRoot ".ai-loop\reviewer_prompt.md"
        if (-not (Test-Path -LiteralPath $reviewerPromptPath)) { $reviewerPromptPath = Join-Path $ProjectRoot "templates\reviewer_prompt.md" }
        Write-Host "Using reviewer prompt: $reviewerPromptPath"
        $reviewerTemplateBody = [System.IO.File]::ReadAllText($reviewerPromptPath)
        $traceLines = New-Object System.Collections.Generic.List[string]
        foreach ($tl in "# Planner review trace", "", "Iterations max: $MaxReviewIterations", "") { [void]$traceLines.Add($tl) }
        $current = $output
        $reviewLoopExitKind = "max_iterations"
        $revPw = @("--workspace", $ProjectRoot)
        if (-not [string]::IsNullOrWhiteSpace($ReviewerModel)) { $revPw += @("--model", $ReviewerModel) }
        for ($i = 1; $i -le $MaxReviewIterations; $i++) {
            Write-Host "Review iteration $i / $MaxReviewIterations ..."
            $reviewPrompt = @($reviewerTemplateBody, "## AGENTS.md", $agentsBody, "## project_summary.md", $summaryBody, "## repo_map.md", $repoMapBody, "## USER ASK", $resolvedAsk, "## GENERATED task.md", $current) -join "`n`n"
            $issuesLines = @($reviewPrompt | & $reviewerCmdPath @revPw)
            $issues = ($issuesLines | ForEach-Object { "$_" }) -join "`n"
            if ($LASTEXITCODE -ne 0) {
                [void]$traceLines.Add("## Iteration $i - REVIEW_STATUS: FAILED (reviewer exit $LASTEXITCODE)")
                [void]$traceLines.Add("task.md was written WITHOUT successful Codex review.")
                Write-Warning "REVIEWER FAILED on iteration $i (exit $LASTEXITCODE). task.md will be written but Codex did NOT successfully review it. Treat -WithReview as if not set for this run."
                $reviewLoopExitKind = "degraded"
                break
            }
            foreach ($seg in "## Iteration $i - reviewer output", $issues, "") { [void]$traceLines.Add($seg) }
            $revFmt = Test-ReviewerOutputStrict -Output $issues
            if (-not $revFmt.Ok) {
                [void]$traceLines.Add("## Iteration $i - REVIEW_STATUS: REVIEWER_OUTPUT_MALFORMED")
                [void]$traceLines.Add("Reviewer output was not exactly NO_BLOCKING_ISSUES nor a strict ISSUES: list (each non-blank issue line must be '- [logic|complexity|scope|missing] <text>'). Keeping current draft. task.md was written WITHOUT a successful Codex verdict.")
                Write-Warning "Reviewer output on iteration $i is MALFORMED (strict format: NO_BLOCKING_ISSUES only, or ISSUES: with only '- [logic|complexity|scope|missing] ...' lines). Keeping current draft, breaking loop. Treat as if review did not happen."
                $reviewLoopExitKind = "degraded"
                break
            }
            if (($issues.Trim()) -eq "NO_BLOCKING_ISSUES") {
                [void]$traceLines.Add("Exit: NO_BLOCKING_ISSUES at iteration $i.")
                $reviewLoopExitKind = "no_issues"
                Write-Host "Reviewer: NO_BLOCKING_ISSUES ? exited at iteration $i."
                break
            }
            $revisionInstructions = (@(
"# Revision request", "",
"You are the PLANNER and ARCHITECT (same role as in the initial draft).",
"A reviewer has examined your previous task.md draft and produced the",
"ISSUES list below. The reviewer is advisory; you have the final say.", "",
"For each issue:",
"- If you agree, incorporate the fix into the revised task.md silently",
"  (no Architect note required for accepted fixes ? the change is the",
"  evidence).",
"- If you disagree, reject it and add an 'Architect note: rejected",
"  <category>:<short ref> because <one-line reason>' under ## Important.",
"  Architectural principle: simplicity of implementation wins. Reject",
"  suggestions that add complexity without clear benefit.", "",
"Output the FULL revised task.md (not a diff, not a summary). All",
"hard rules from the planner prompt still apply: first line is # Task:,",
"no preamble, no fenced wrap, no HTML comments. Keep implementation under ~80 lines.", "",
"If you believe the previous draft was already correct and reject all issues, you may output the previous draft verbatim plus the Architect",
"notes in ## Important." )) -join "`n"
            $revisionPrompt = @($planPromptBody, "## AGENTS.md", $agentsBody, "## project_summary.md", $summaryBody, "## repo_map.md", $repoMapBody, "## USER ASK", $resolvedAsk, "## CURRENT DRAFT", $current, "## REVIEWER ISSUES", $issues, $revisionInstructions) -join "`n`n"
            $revLines = @($revisionPrompt | & $cmdPath @pwArgs)
            $revised = ($revLines | ForEach-Object { "$_" }) -join "`n"
            if ($LASTEXITCODE -ne 0) {
                [void]$traceLines.Add("## Iteration $i - REVIEW_STATUS: PLANNER_REVISION_FAILED (exit $LASTEXITCODE)")
                [void]$traceLines.Add("Iteration $i - planner revision failed (exit $LASTEXITCODE). Keeping previous draft.")
                Write-Warning "Planner wrapper exited non-zero on revision iteration $i. Keeping previous draft."
                $reviewLoopExitKind = "degraded"
                break
            }
            $revised = Normalize-PlannerOutput -Output $revised
            $sanityRev = Test-PlannerOutputSanity -Output $revised
            if (-not $sanityRev.Ok) {
                [void]$traceLines.Add("## Iteration $i - REVIEW_STATUS: REVISION_SANITY_FAILED")
                [void]$traceLines.Add("Iteration $i - revision failed sanity check: $($sanityRev.Reason). Keeping previous draft.")
                Write-Warning "Revision iteration $i failed sanity check: $($sanityRev.Reason). Keeping previous draft."
                $reviewLoopExitKind = "degraded"
                break
            }
            $current = $revised
        }
        if ($reviewLoopExitKind -eq "max_iterations") {
            [void]$traceLines.Add("Exit: MaxReviewIterations ($MaxReviewIterations) reached.")
            Write-Host "Reviewer: $MaxReviewIterations iterations completed."
        }
        $tracePath = Join-Path $ProjectRoot ".ai-loop\planner_review_trace.md"
        Set-Content -LiteralPath $tracePath -Value ($traceLines -join "`n") -Encoding UTF8
        Write-Host "Wrote review trace: $tracePath"
        $writeText = $current
    }
    $outParent = Split-Path -Parent $Out
    if ($outParent -and -not (Test-Path -LiteralPath $outParent)) { New-Item -ItemType Directory -Force -Path $outParent | Out-Null }
    Set-Content -LiteralPath $tmpOut -Value $writeText -Encoding UTF8
    Move-Item -Force -LiteralPath $tmpOut -Destination $Out
    Write-Host "Wrote $Out (no obvious structural issues found).`n`nFiles in scope (extracted from task.md ? verify before running):"
    $paths = Get-FilesInScopeSummary -Text $writeText
    if ($paths.Count -eq 0) {
        Write-Host "  (Could not parse Files in scope ? review task.md manually.)"
    } else {
        $n = [Math]::Min(10, $paths.Count)
        for ($j = 0; $j -lt $n; $j++) { Write-Host "  $($paths[$j])" }
        if ($paths.Count -gt 10) { Write-Host "  ... ($($paths.Count - 10) more total)" }
    }
    Write-Host "`nThis is a DRAFT. Review $Out manually before running ai_loop_task_first.ps1."
    if ($backupMade) { Write-Host "Previous task.md kept at $Out.bak." }
}
catch {
    if ($script:ExitCode -eq 0) { $script:ExitCode = 1 }
    if ($backupMade -and -not (Test-Path -LiteralPath $Out)) { Move-Item -Force -LiteralPath "$Out.bak" -Destination $Out }
    if (Test-Path -LiteralPath $tmpOut) { Remove-Item -LiteralPath $tmpOut -Force -ErrorAction SilentlyContinue }
    Write-Warning $_.Exception.Message
    if ($backupMade) { Write-Warning "Restored previous $Out from backup." }
}
finally {
    exit $script:ExitCode
}
