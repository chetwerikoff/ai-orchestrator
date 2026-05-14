# C09 — Optional Codex review loop in planner (max 3 iterations, planner has final say)

**Project:** `ai-orchestrator`
**CWD:** `C:\Users\che\Documents\Projects\ai-orchestrator`
**Prerequisite:** **C07 merged** (`scripts/ai_loop_plan.ps1` must exist; this task extends it).
**Risk:** medium — new wrapper + new prompt + loop logic added to an existing entrypoint. Default OFF.

How to run:
```powershell
# Paste task spec below into .ai-loop\task.md, then:
powershell -ExecutionPolicy Bypass -File .\scripts\ai_loop_task_first.ps1 -NoPush
```

---

# Task: Add `-WithReview` to the planner (Codex reviews, planner decides)

## Project context

Required reading before starting:

1. `AGENTS.md` at repo root
2. `.ai-loop/task.md` — this task
3. `.ai-loop/project_summary.md`
4. `.ai-loop/repo_map.md`
5. `scripts/ai_loop_plan.ps1` (from C07) — file to extend
6. `scripts/run_claude_planner.ps1` (from C07) — planner wrapper to reuse
7. `templates/planner_prompt.md` (from C07) — planner role; revision behavior is added inline (no new planner template)
8. `scripts/ai_loop_auto.ps1` — `Run-CodexReview` (around line 326-413) for the
   `codex exec` invocation pattern and `ConvertTo-CrtSafeArg` (defined in
   `ai_loop_task_first.ps1`) to mirror in the new reviewer wrapper
9. `.ai-loop/implementer_summary.md` — only if iteration 2+

Do not read by default:
- `docs/archive/`
- `.ai-loop/_debug/`

## Goal

Add **optional** Codex review pass to the planner. Codex is **advisory** — it
finds logical errors and unnecessary complexity. The Claude planner remains
the **architect with final say**: it incorporates issues silently OR rejects
them with an `Architect note:` in `## Important`. Capped at 3 review iterations.
Early exit when Codex reports no blocking issues.

```
ai_loop_plan.ps1 -Ask "..." -WithReview
                            [-MaxReviewIterations 3]
                            [-ReviewerCommand .\scripts\run_codex_reviewer.ps1]
                            [-ReviewerModel "..."]
```

Default behavior of `ai_loop_plan.ps1` is unchanged (no review). The review
loop only runs when `-WithReview` is explicitly passed.

### Architectural principle (load-bearing)

**Simplicity of implementation wins.** The planner is biased toward minimal
implementations. Codex's job is to find logical errors and complexity, NOT to
propose architectural redesigns. The planner can — and should — reject
Codex suggestions that add engineering complexity beyond what the goal needs.

### Architectural symmetry

```
Initial draft (no review):        With -WithReview:
  USER ASK                          USER ASK
    ↓                                 ↓
  Planner (Claude)                  Planner (Claude) → draft #1
    ↓                                 ↓
  sanity check                      Loop up to 3 times:
    ↓                                 Codex reviews → issues OR NO_BLOCKING_ISSUES
  write task.md                       if NO_BLOCKING_ISSUES: break
                                      Planner revises (final say)
                                      sanity check on revision
                                    ↓
                                    write final task.md + trace
```

### Deliverables

1. `scripts/run_codex_reviewer.ps1` (new) — Codex wrapper, mirrors existing wrapper convention.
2. `templates/reviewer_prompt.md` (new) — reviewer role + output format.
3. `scripts/ai_loop_plan.ps1` (edit) — add `-WithReview` and review loop.
4. `scripts/install_into_project.ps1` (edit) — copy the two new files.
5. `.gitignore` (edit) — ignore the trace artifact + `planner_prompt.md` already covered by C07.
6. `tests/test_orchestrator_validation.py` (edit) — minimal tests.
7. `.ai-loop/project_summary.md` (edit) — note the review feature.

## Scope

Allowed:
- Create `scripts/run_codex_reviewer.ps1`
- Create `templates/reviewer_prompt.md`
- Edit `scripts/ai_loop_plan.ps1` (add parameters + loop; do not restructure C07 flow)
- Edit `scripts/install_into_project.ps1`
- Edit `.gitignore`
- Edit `tests/test_orchestrator_validation.py`
- Edit `.ai-loop/project_summary.md`

Not allowed:
- Any changes to `scripts/ai_loop_auto.ps1`, `scripts/ai_loop_task_first.ps1`,
  `scripts/continue_ai_loop.ps1`
- Changes to existing wrappers (`run_cursor_agent.ps1`,
  `run_opencode_agent.ps1`, `run_opencode_scout.ps1`, `run_scout_pass.ps1`,
  `run_claude_planner.ps1`)
- Changes to `templates/codex_review_prompt.md` (existing reviewer for
  implementation, not for task.md), `templates/planner_prompt.md`,
  `templates/user_ask_template.md`, `templates/task.md`
- Edits to `AGENTS.md`, `src/`, `ai_loop.py`, `docs/`
- Adding a new planner template — revision instructions are inlined in `ai_loop_plan.ps1`
- Calling `claude` or `codex` CLIs from tests

## Files in scope

- `scripts/run_codex_reviewer.ps1` (new)
- `templates/reviewer_prompt.md` (new)
- `scripts/ai_loop_plan.ps1` (edit)
- `scripts/install_into_project.ps1` (edit)
- `.gitignore` (edit)
- `tests/test_orchestrator_validation.py` (edit)
- `.ai-loop/project_summary.md` (edit)

## Files out of scope

- `scripts/ai_loop_auto.ps1`
- `scripts/ai_loop_task_first.ps1`
- `scripts/continue_ai_loop.ps1`
- `scripts/run_cursor_agent.ps1`
- `scripts/run_opencode_agent.ps1`
- `scripts/run_opencode_scout.ps1`
- `scripts/run_scout_pass.ps1`
- `scripts/run_claude_planner.ps1`
- `templates/codex_review_prompt.md`
- `templates/planner_prompt.md`
- `templates/user_ask_template.md`
- `templates/task.md`
- `AGENTS.md`
- `docs/**`
- `docs/archive/**`
- `.ai-loop/_debug/**`
- `ai_loop.py`

## Required behavior

### scripts/run_codex_reviewer.ps1

Codex CLI takes the prompt as a positional argument to `codex exec`, not via
stdin. The wrapper bridges the project's stdin-pipe convention to that style:

- **No `param()` block** (preserves `$input` for caller-consistency).
- Parse `--workspace` and `--model` from `$args`; silently ignore unknown flags.
- Read prompt from `$input | Out-String` → trim. Empty → `Write-Error` + exit 1.
- `Push-Location` to workspace if provided; `Pop-Location` in `finally`.
- Duplicate `ConvertTo-CrtSafeArg` (5-line regex helper) locally — same body
  as in `ai_loop_task_first.ps1`. Do not import from another script.
- Build args:
  ```powershell
  $codexArgs = @("exec", (ConvertTo-CrtSafeArg -Value $promptText))
  ```
  Do NOT pass a `--model` flag unless `$model` is non-empty (mirror
  `Run-CodexReview` default behavior; Codex CLI decides default).
- Native-command error mode workaround (same as `run_claude_planner.ps1`
  from C07):
  ```powershell
  $prevEA = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  & codex @codexArgs
  $exitCode = $LASTEXITCODE
  $ErrorActionPreference = $prevEA
  exit $exitCode
  ```
- **No `2>&1`** — stdout-only is captured.

Keep under 60 lines.

### templates/reviewer_prompt.md

```markdown
# Reviewer role

You are the REVIEWER. You examine a GENERATED `task.md` (provided in the
prompt body) against the original USER ASK and the project context. Your
job is narrow: find logical errors or unnecessary complexity in the
proposed implementation. You are advisory only — the architect (planner)
has the final say and may reject your findings with a documented reason.

## Architectural principle: simplicity wins

The planner is biased toward minimal implementations. Your default is to
return `NO_BLOCKING_ISSUES`. Raise an issue only when you see something
concrete that hurts the plan — not because it could be "more polished".

## What you check

- **Logic**: contradictions in `## Required behavior`, references to files
  that contradict `## Files in scope`, acceptance criteria that cannot be
  verified by the listed tests, conflicting constraints in `## Important`.
- **Complexity**: scope materially broader than the user's ASK, new
  subsystems where a modification would suffice, parameters/modes that are
  not needed for the stated goal, premature abstractions.
- **Scope drift**: implementation expanded beyond what the ASK requested.
- **Missing**: a clear ASK requirement is absent from the task.md.

## What you do NOT do

- You are NOT an architect. Do NOT propose alternative architectures.
- You are NOT a co-planner. Do NOT write alternative task.md content.
- You are NOT a perfectionist. Minor stylistic issues are not blocking.
- Do NOT add features that were not in the ASK.

## Output format

Output ONLY one of these two forms. No preamble. No markdown fence
wrapping. No additional explanation after the format.

**Form 1 — no issues:**

```
NO_BLOCKING_ISSUES
```

**Form 2 — issues exist:**

```
ISSUES:
- [logic] <one-line description referencing a task.md section if applicable>
- [complexity] <one-line description>
- [scope] <one-line description>
- [missing] <one-line description>
```

Categories must be exactly one of: `logic`, `complexity`, `scope`, `missing`.
Each issue is one line — no nested bullets, no multi-line explanations.

## Hard rules

- Default to `NO_BLOCKING_ISSUES` when in doubt — the planner is the
  architect and the human is the final gate.
- Prefer fewer, sharper issues over many shallow ones. Three concrete
  issues beat ten vague ones.
- Reference specific task.md sections (e.g. `## Files in scope`,
  `## Required behavior step 3`) so the planner can find the issue fast.
- Never propose alternative implementations or new architecture.
- Never add features.
- Output is parsed mechanically by `ai_loop_plan.ps1` — strict adherence
  to the format above is mandatory.
```

### scripts/ai_loop_plan.ps1 — extension only

Add to the `param()` block (do NOT touch existing parameters from C07):

```powershell
[switch]$WithReview,
[int]$MaxReviewIterations = 3,
[string]$ReviewerCommand = ".\scripts\run_codex_reviewer.ps1",
[string]$ReviewerModel = ""
```

**Validate clamp** at the start of the script (right after parameter parsing):
- If `$MaxReviewIterations -lt 1`: clamp to 1, print warning.
- If `$MaxReviewIterations -gt 3`: clamp to 3, print warning. **The cap of 3
  is enforced regardless of user input** — this is a deliberate architectural
  constraint to bound cost and prevent runaway loops.

**Prerequisite check (only if `-WithReview`):**
- `$ReviewerCommand` exists
- `.ai-loop/reviewer_prompt.md` exists (with source-repo fallback to
  `templates/reviewer_prompt.md`, mirroring the planner-prompt fallback from C07)

**Review loop** — runs ONLY when `-WithReview` is set, AFTER C07's initial
draft + sanity check, BEFORE the final write to `$Out`:

```powershell
# Variables already in scope from C07:
#   $output        — current draft text (initial draft from planner)
#   $prompt        — initial planner prompt
#   $resolvedAsk   — the user's ASK text
#   $planPromptBody, $agentsBody, $summaryBody, $repoMapBody — context blocks
#
# After C07 builds $output and runs the sanity check, branch on $WithReview.

if (-not $WithReview) {
    # C07 path: write $output via temp file + Move-Item, success message, exit.
    # (No change here.)
}
else {
    # Resolve reviewer prompt path (source-repo fallback, like planner prompt).
    $reviewerPrompt = ".ai-loop\reviewer_prompt.md"
    if (-not (Test-Path -LiteralPath $reviewerPrompt)) {
        $reviewerPrompt = "templates\reviewer_prompt.md"
    }
    if (-not (Test-Path -LiteralPath $reviewerPrompt)) {
        $script:ExitCode = 1
        throw "Reviewer prompt not found at .ai-loop\reviewer_prompt.md or templates\reviewer_prompt.md."
    }
    Write-Host "Using reviewer prompt: $reviewerPrompt"

    $reviewerBody = Get-Content -LiteralPath $reviewerPrompt -Raw
    $traceLines = New-Object System.Collections.Generic.List[string]
    $traceLines.Add("# Planner review trace")
    $traceLines.Add("")
    $traceLines.Add("Iterations max: $MaxReviewIterations")
    $traceLines.Add("")

    $current = $output
    $exitedEarly = $false
    for ($i = 1; $i -le $MaxReviewIterations; $i++) {
        Write-Host "Review iteration $i / $MaxReviewIterations ..."
        # Build reviewer prompt: reviewer template + context + USER ASK + GENERATED task.md
        $reviewPrompt = @(
            $reviewerBody,
            "## AGENTS.md", $agentsBody,
            "## project_summary.md", $summaryBody,
            "## repo_map.md", $repoMapBody,
            "## USER ASK", $resolvedAsk,
            "## GENERATED task.md", $current
        ) -join "`n`n"

        $issues = $reviewPrompt | & $ReviewerCommand --workspace $ProjectRoot --model $ReviewerModel
        if ($LASTEXITCODE -ne 0) {
            $traceLines.Add("## Iteration $i — reviewer failed (exit $LASTEXITCODE)")
            $traceLines.Add("Continuing with current draft; reviewer error is non-fatal.")
            Write-Warning "Reviewer wrapper exited non-zero ($LASTEXITCODE) on iteration $i. Keeping current draft."
            break
        }
        $traceLines.Add("## Iteration $i — reviewer output")
        $traceLines.Add($issues)
        $traceLines.Add("")

        if ($issues -match '(?m)^\s*NO_BLOCKING_ISSUES\s*$') {
            $traceLines.Add("Exit: NO_BLOCKING_ISSUES at iteration $i.")
            $exitedEarly = $true
            break
        }

        # Planner revision. Inline revision instructions — no separate template.
        $revisionInstructions = @"
# Revision request

You are the PLANNER and ARCHITECT (same role as in the initial draft).
A reviewer has examined your previous task.md draft and produced the
ISSUES list below. The reviewer is advisory; you have the final say.

For each issue:
- If you agree, incorporate the fix into the revised task.md silently
  (no Architect note required for accepted fixes — the change is the
  evidence).
- If you disagree, reject it and add an 'Architect note: rejected
  <category>:<short ref> because <one-line reason>' under ## Important.
  Architectural principle: simplicity of implementation wins. Reject
  suggestions that add complexity without clear benefit.

Output the FULL revised task.md (not a diff, not a summary). All
hard rules from the planner prompt still apply: first line is # Task:,
no preamble, no fenced wrap, no HTML comments. Keep implementation
under ~80 lines.

If you believe the previous draft was already correct and reject all
issues, you may output the previous draft verbatim plus the Architect
notes in ## Important.
"@
        $revisionPrompt = @(
            $planPromptBody,
            "## AGENTS.md", $agentsBody,
            "## project_summary.md", $summaryBody,
            "## repo_map.md", $repoMapBody,
            "## USER ASK", $resolvedAsk,
            "## CURRENT DRAFT", $current,
            "## REVIEWER ISSUES", $issues,
            $revisionInstructions
        ) -join "`n`n"

        $revised = $revisionPrompt | & $PlannerCommand --workspace $ProjectRoot --model $PlannerModel
        if ($LASTEXITCODE -ne 0) {
            $traceLines.Add("Iteration $i — planner revision failed (exit $LASTEXITCODE). Keeping previous draft.")
            Write-Warning "Planner wrapper exited non-zero on revision iteration $i. Keeping previous draft."
            break
        }

        # Sanity check on revision (reuse the same check from C07 — extract to a
        # helper function Test-PlannerOutputSanity to avoid duplication).
        $sanity = Test-PlannerOutputSanity -Output $revised
        if (-not $sanity.Ok) {
            $traceLines.Add("Iteration $i — revision failed sanity check: $($sanity.Reason). Keeping previous draft.")
            Write-Warning "Revision iteration $i failed sanity check: $($sanity.Reason). Keeping previous draft."
            break
        }

        $current = $revised
    }

    if (-not $exitedEarly) {
        $traceLines.Add("Exit: MaxReviewIterations ($MaxReviewIterations) reached.")
    }

    # Write trace BEFORE writing task.md so user can debug even if write fails.
    $tracePath = ".ai-loop\planner_review_trace.md"
    Set-Content -LiteralPath $tracePath -Value ($traceLines -join "`n") -Encoding UTF8
    Write-Host "Wrote review trace: $tracePath"

    # $current is now the final draft — write it via the same temp-file +
    # Move-Item pattern as C07 (so backup-restore behavior is preserved).
    $output = $current
    # Fall through to the existing C07 write block.
}
```

**Refactor note:** the initial-draft sanity check from C07 becomes
`Test-PlannerOutputSanity -Output <text>` returning `@{ Ok = $bool; Reason = $string }`.
Both the initial draft (C07's path) and the revision loop call this helper.
This is the only structural refactor of C07 code; it keeps the existing
exit-code semantics (exit 2 on initial-draft sanity failure).

**Console messages** must say:
- `Review iteration N / M ...` per iteration
- `Reviewer: NO_BLOCKING_ISSUES — exited at iteration N.` on early exit
- `Reviewer: M iterations completed.` on cap hit
- Never `task is correct`, `validated`, or `safe to run`.

Updated exit codes (no new codes added):
- 0: success (with or without `-WithReview`)
- 1: missing prerequisites, planner OR reviewer wrapper invocation error (backup restored)
- 2: initial draft failed sanity check (backup restored)

**Reviewer or revision failure is non-fatal** mid-loop: keep the previous
draft, append a note to trace, break out of the loop, and write the current
draft. This means `-WithReview` can degrade gracefully to "draft as-is" if
Codex is unavailable.

Keep total `ai_loop_plan.ps1` under 270 lines after this extension.

### scripts/install_into_project.ps1

Add `Copy-Item -Force` lines:
- `scripts/run_codex_reviewer.ps1` → target `scripts/`
- `templates/reviewer_prompt.md` → target `.ai-loop/reviewer_prompt.md`

### .gitignore

Add under the existing `# planner runtime artifacts` section:

```
.ai-loop/planner_review_trace.md
.ai-loop/reviewer_prompt.md
```

`reviewer_prompt.md` is gitignored in this source repo for the same reason
as `planner_prompt.md` (C07): so a stale runtime copy can never shadow
`templates/reviewer_prompt.md`.

## Tests

Run:
```bash
python -m pytest -q
```

Add to `tests/test_orchestrator_validation.py` (six tests total — no more):

1. `test_run_codex_reviewer_script_exists`
2. `test_reviewer_prompt_template_exists_and_has_format` — assert
   `templates/reviewer_prompt.md` exists AND contains literals
   `# Reviewer role`, `NO_BLOCKING_ISSUES`, `ISSUES:`, `[logic]`,
   `[complexity]`, `simplicity wins`, AND `NOT an architect`.
3. `test_run_codex_reviewer_invariants` — read `run_codex_reviewer.ps1`;
   assert ALL of:
   - does NOT contain `param(`
   - contains `codex` and `exec`
   - contains a `ConvertTo-CrtSafeArg` function definition
   - does NOT contain `2>&1`
4. `test_ai_loop_plan_review_invariants` — read `ai_loop_plan.ps1`; assert
   ALL of:
   - declares `$WithReview`, `$MaxReviewIterations`, `$ReviewerCommand`, `$ReviewerModel`
   - contains literal `Test-PlannerOutputSanity` (sanity check extracted as helper)
   - contains literal `MaxReviewIterations = 3` (default)
   - contains clamp logic — pin via literal `clamp to 3`
   - contains literal `NO_BLOCKING_ISSUES` (early-exit check)
   - contains literal `Architect note:` (revision instruction text)
   - contains literal `simplicity of implementation wins` (revision instruction text)
5. `test_install_copies_reviewer_files` — assert
   `install_into_project.ps1` copies `run_codex_reviewer.ps1` and
   `reviewer_prompt.md` (target path `.ai-loop/reviewer_prompt.md`).
6. `test_gitignore_excludes_review_artifacts` — assert `.gitignore` contains
   `.ai-loop/planner_review_trace.md` AND `.ai-loop/reviewer_prompt.md`.

Do NOT call `claude` or `codex` CLIs in tests.

## Verification

```bash
python -m pytest -q
```

```powershell
powershell -NoProfile -Command "[void][System.Management.Automation.Language.Parser]::ParseFile('scripts\run_codex_reviewer.ps1', [ref]$null, [ref]$null)"
powershell -NoProfile -Command "[void][System.Management.Automation.Language.Parser]::ParseFile('scripts\ai_loop_plan.ps1', [ref]$null, [ref]$null)"
```

Manual smoke (requires authenticated `claude` and `codex` CLIs), in a fresh
temp dir:
```powershell
$tmp = Join-Path $env:TEMP "ai_orch_smoke_$(Get-Random)"
New-Item -ItemType Directory -Path $tmp | Out-Null
git -C $tmp init | Out-Null
.\scripts\install_into_project.ps1 -TargetProject $tmp
Set-Location $tmp
.\scripts\ai_loop_plan.ps1 -Ask "Add a smoke test that prints OK" -WithReview -Out .ai-loop\task_smoke.md
Get-Content .ai-loop\planner_review_trace.md
Get-Content .ai-loop\task_smoke.md | Select-Object -First 30
Set-Location -; Remove-Item -Recurse -Force $tmp
```

Smoke success criteria:
- `planner_review_trace.md` exists and shows N ≤ 3 iterations.
- If `NO_BLOCKING_ISSUES` appears in the trace, exit was early.
- If `Architect note: rejected` appears in `task_smoke.md ## Important`, the
  planner exercised final say.

## Implementer summary requirements

Update `.ai-loop/implementer_summary.md`:

1. Changed files.
2. Test result (count only).
3. What was implemented (3–5 lines).
4. What was skipped and why.
5. Remaining risks.

## Project summary update

Update `.ai-loop/project_summary.md`:

- Architecture section: add one line each for `scripts/run_codex_reviewer.ps1`
  and `templates/reviewer_prompt.md`.
- Note: `-WithReview` is OFF by default; Codex is advisory, planner has final say.
- Note: hard cap of 3 iterations (clamped regardless of user input).
- Note: planner revision instructions are inlined in `ai_loop_plan.ps1` (no
  separate revision template).
- Update Current Stage. Add to Next Likely Steps: "validate review-loop
  quality on real ASKs before promoting `-WithReview` toward default".

## Output hygiene

The implementer must not:

- duplicate this task description into `.ai-loop/implementer_summary.md`
- include earlier task narrative in `.ai-loop/project_summary.md`
- write to `.ai-loop/_debug/` or `docs/archive/`
- commit or push (the orchestrator handles git)

## Important

**C07 must be merged first.** This task adds review on top of an existing
planner. If `scripts/ai_loop_plan.ps1` does not exist or has a different
shape than C07 specifies, stop and request a follow-up review of the
divergence before implementing C09.

**Simplicity is load-bearing.** The whole point of the review loop is to
catch unnecessary complexity introduced by the planner. The reviewer prompt,
revision instructions, and architect framing all push toward simpler
implementations. Do NOT add features that work against this — no
"sophistication score", no per-issue voting, no diff visualization, no
multiple reviewer wrappers. One reviewer wrapper, one prompt, one loop.

**Hard cap is 3 iterations, no override.** Even if user passes
`-MaxReviewIterations 10`, the script clamps to 3 with a warning. This is
intentional: bounded cost, bounded latency, bounded LLM churn. Document
this clearly in the clamp warning message.

**Codex is advisory, NOT a gate.** Default to `NO_BLOCKING_ISSUES` when in
doubt is in the reviewer prompt. Reviewer or revision failure is non-fatal —
the loop breaks and the current draft is written. The planner is the
architect; the human is the final gate.

**Architect note convention:** when the planner rejects a reviewer issue,
the revision instructions require an `Architect note: rejected
<category>:<ref> because <reason>` line in `## Important`. This is the user's
audit trail to see what the reviewer flagged and why the architect kept
their decision. Tests pin the `Architect note:` literal (#4).

**Wrapper convention (critical):**
- `run_codex_reviewer.ps1` MUST have no `param()` block.
- No `2>&1`.
- Mirror `run_claude_planner.ps1` line-for-line on the NativeCommandError
  workaround (save/restore `$ErrorActionPreference`).
- Codex CLI uses positional prompt arg with `ConvertTo-CrtSafeArg` (duplicate
  the 5-line helper locally; do NOT import).

**Sanity check on revision drafts.** Each revised draft must pass the same
sanity check as the initial draft (required headings, no HTML comments, no
fenced wrap, starts with `# Task:`). If a revision fails sanity, keep the
PREVIOUS draft and break the loop. This prevents Codex feedback from
degrading the draft into something invalid.

**Trace artifact (`.ai-loop/planner_review_trace.md`):**
- Gitignored (added to `.gitignore` in this task).
- Overwritten on each run; not durable history.
- Useful for debugging "why did Codex change task.md between iterations".
- Written BEFORE the final task.md so it survives even if the final write
  fails.

**Sanity-check helper extraction is the only refactor of C07 code allowed.**
Extract the initial-draft sanity check into `Test-PlannerOutputSanity` so
both the C07 path and the C09 revision loop call it. Do NOT change the
existing C07 behavior, exit codes, error messages, or test expectations.
C07 tests must still pass unchanged.

**Source-repo fallback for reviewer prompt** mirrors the planner-prompt
fallback from C07: try `.ai-loop/reviewer_prompt.md` first, then
`templates/reviewer_prompt.md`. Console trace ("Using reviewer prompt: ...")
makes the chosen path visible.

**Future LLM-call cost is bounded:** worst case per planning with
`-WithReview`: 1 initial Claude call + 3 Codex calls + 3 Claude revisions = 7
LLM calls. Document this so users understand the cost when enabling the flag.

**Do NOT pre-commit to making `-WithReview` default.** Real-world data
should drive that decision. Project summary's "Next Likely Steps" calls for
validation on real ASKs first.

**Spec size:** This task adds ~150 lines to `ai_loop_plan.ps1` plus a ~60
line wrapper plus a markdown template. It exceeds the ≤80-line policy for
the same reason C07 did — foundational addition. Suggested implementation
order:
1. `templates/reviewer_prompt.md` (data first).
2. `scripts/run_codex_reviewer.ps1` (mirror existing wrapper convention).
3. Extract `Test-PlannerOutputSanity` from C07's inline sanity check.
4. Add the four new parameters + clamp to `ai_loop_plan.ps1`.
5. Add the review loop + trace writing.
6. Installer + `.gitignore` + tests.
