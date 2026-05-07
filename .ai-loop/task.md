# Task: Remove Claude final review from the default AI loop

## Context

The user now wants Claude to be used as a separate independent reviewer with its own review workspace, not as a mandatory final reviewer inside the automated Cursor/Codex loop.

Current architecture:

- Cursor implements fixes.
- Codex reviews the diff/tests.
- Claude was previously called as a final reviewer inside `scripts/ai_loop_auto.ps1`.

New desired architecture:

- Automated loop:
  - Cursor implements.
  - Tests run.
  - Codex reviews.
  - If Codex passes, final test gate runs.
  - Git commit/push happens.
- Claude is NOT called by the loop.
- Claude is used manually/separately through the `h2n-claude-review` workspace.

## Goal

Remove Claude final review from the default AI loop and documentation.

Do not remove the separate Claude review workspace.
Do not delete existing Claude review memory files.
Do not break resume mode.

## Files likely to change

In `ai-git-orchestrator`:

- `scripts/ai_loop_auto.ps1`
- `scripts/continue_ai_loop.ps1`
- `scripts/install_into_project.ps1` if it references Claude final review templates
- `README.md`
- `docs/workflow.md`
- `docs/safety.md` if needed
- `docs/decisions.md`
- `templates/task.md` if needed
- remove or deprecate:
  - `templates/claude_final_review_prompt.md`

In target project `h2n-range-extractor`, after reinstalling orchestrator:

- `scripts/ai_loop_auto.ps1`
- `scripts/continue_ai_loop.ps1`
- `.ai-loop/project_summary.md` only if durable context needs a short note

## Required behavior

### 1. `scripts/ai_loop_auto.ps1`

Remove Claude from the loop.

After Codex returns `PASS`, the script should:

1. print `Codex verdict: PASS`;
2. run final test gate;
3. commit safe files;
4. push unless `-NoPush` is set;
5. write final status.

There should be no call to:

```powershell
claude -p ...
```

There should be no `Run-ClaudeFinalReview` requirement in the default path.

Remove or ignore these concepts:

- `-NoClaudeFinalReview`
- `Run-ClaudeFinalReview`
- `Get-ClaudeVerdict`
- `claude_final_review.md`
- Claude `FIX_REQUIRED` loop
- `PASS_WITH_CAVEATS` handling inside the automated loop

The final status should look like:

```text
PASS after iteration N. Codex=PASS. Changes committed and pushed if NoPush was not enabled.
```

### 2. Resume mode

Resume mode should work like this:

- If `.ai-loop/next_cursor_prompt.md` exists:
  - run Cursor fix;
  - continue loop.
- If existing `.ai-loop/codex_review.md` says `VERDICT: PASS`:
  - commit/push after final test gate.
- If existing `.ai-loop/codex_review.md` says `FIX_REQUIRED`:
  - extract `FIX_PROMPT_FOR_CURSOR`;
  - run Cursor fix;
  - continue loop.

No Claude path.

### 3. `scripts/continue_ai_loop.ps1`

Remove `-NoClaudeFinalReview`.

Supported parameters should be:

```powershell
param(
    [string]$CommitMessage = "Continue AI loop",
    [int]$MaxIterations = 10,
    [switch]$NoPush,
    [string]$TestCommand = "python -m pytest",
    [string]$PostFixCommand = "",
    [string]$SafeAddPaths = "src/,tests/,README.md,scripts/,.gitignore,requirements.txt,pyproject.toml,setup.cfg,.ai-loop/task.md,.ai-loop/cursor_summary.md,.ai-loop/project_summary.md"
)
```

It should call:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\ai_loop_auto.ps1 `
    -Resume `
    -MaxIterations $MaxIterations `
    -CommitMessage $CommitMessage `
    -TestCommand $TestCommand `
    -SafeAddPaths $SafeAddPaths
```

and pass `-NoPush` / `-PostFixCommand` only when provided.

### 4. Templates and install script

Do not install `claude_final_review_prompt.md` into target projects anymore.

`install_into_project.ps1` should copy:

- `scripts/ai_loop_auto.ps1`
- `scripts/continue_ai_loop.ps1`
- `templates/task.md` to `.ai-loop/task.md` if missing or `-OverwriteTask`
- `templates/project_summary.md` to `.ai-loop/project_summary.md` if missing or `-OverwriteProjectSummary`
- `templates/codex_review_prompt.md`
- `templates/cursor_summary_template.md`

Do not copy:

- `templates/claude_final_review_prompt.md`

It is okay to leave the file in the repository as deprecated documentation, but README should not describe it as part of the active loop. Prefer removing it if no longer needed.

### 5. Documentation update

Update `README.md` and `docs/workflow.md`:

New default workflow:

```text
Cursor fix
→ tests
→ git diff
→ Codex review
→ if FIX_REQUIRED: Cursor fix again
→ if PASS: final test gate
→ git commit
→ git push
```

Claude should be documented as a separate optional/manual review workspace, for example:

```text
Claude is not part of the automated loop.
Use a separate Claude review workspace such as `h2n-claude-review` for deep investigations.
```

Update `docs/decisions.md`:

- Replace old decision "Codex is primary reviewer, Claude is final reviewer"
- New decision:
  - Codex is the automated loop reviewer.
  - Claude is a separate manual/deep reviewer with its own review-memory workspace.

### 6. `.gitignore` / runtime artifacts

Keep ignoring old Claude runtime artifact if present:

```gitignore
.ai-loop/claude_final_review.md
```

This is okay for backward compatibility.

## Tests / validation

This is mostly PowerShell/documentation work.

Run:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\ai_loop_auto.ps1 -MaxIterations 1 -NoPush -CommitMessage "Dry run without Claude"
```

If running the loop on the orchestrator repo itself is not appropriate, at least run PowerShell syntax checks:

```powershell
powershell -NoProfile -Command "& { . .\scripts\ai_loop_auto.ps1 }"
```

or use:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\continue_ai_loop.ps1 -NoPush -MaxIterations 1
```

If syntax-only execution is not feasible because the script starts the loop immediately, document the limitation in `cursor_summary.md`.

## Update `.ai-loop/cursor_summary.md`

Include:

- changed files;
- confirmation that Claude is no longer called by the automated loop;
- confirmation that `continue_ai_loop.ps1` no longer accepts/passes `-NoClaudeFinalReview`;
- documentation updates;
- validation performed;
- remaining risks.

## Important constraints

- Do not delete the separate `h2n-claude-review` project.
- Do not remove references explaining Claude can be used manually/separately.
- Do not leave the script trying to read or parse `claude_final_review.md`.
- Do not leave `claude -p` in the automated loop.
- Do not break `-NoPush`.
- Do not break resume mode.
