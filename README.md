# A Git Orchestrator

A local PowerShell-based AI development loop for coordinating:

- Cursor Agent as implementer
- Codex as reviewer
- project tests
- safe git commit and push

The orchestrator is designed to be installed into any git project that uses a file-based task workflow under `.ai-loop/`.

## What it does

1. Reads durable project context from `.ai-loop/project_summary.md`.
2. Runs tests.
3. Saves `git diff` and `git status`.
4. Runs Codex review.
5. If Codex requests fixes, runs Cursor Agent.
6. Repeats until Codex passes or `MaxIterations` is reached.
7. Runs a final test gate.
8. Commits and optionally pushes safe project files.

## Requirements

Install and authenticate:

```powershell
agent --version
codex --version
git --version
```

Expected CLIs:

- Cursor CLI: `agent`
- OpenAI Codex CLI: `codex`

## Project-level memory

The orchestrator uses:

```text
.ai-loop/project_summary.md
```

as durable project-level memory.

This file is not a detailed task log. It should contain durable context:

- project purpose;
- architecture;
- important design decisions;
- current stage;
- known risks;
- next likely steps.

Cursor updates it after each task. Codex reads it during review.

## Install into a target project

From this repository:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\install_into_project.ps1 `
  -TargetProject "C:\path\to\your\project"
```

This copies:

```text
scripts/ai_loop_auto.ps1
scripts/continue_ai_loop.ps1
.ai-loop/task.md
.ai-loop/project_summary.md
.ai-loop/codex_review_prompt.md
.ai-loop/claude_final_review_prompt.md
.ai-loop/cursor_summary_template.md
```

Existing `.ai-loop/task.md` and `.ai-loop/project_summary.md` are not overwritten unless you pass `-OverwriteTask` or `-OverwriteProjectSummary`.

## Start a new loop in the target project

From the target project root:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\ai_loop_auto.ps1 `
  -MaxIterations 10 `
  -CommitMessage "Implement feature"
```

## Continue after stop

From the target project root:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\continue_ai_loop.ps1 `
  -CommitMessage "Continue feature"
```

or, if scripts are unblocked:

```powershell
.\scripts\continue_ai_loop.ps1 -CommitMessage "Continue feature"
```

## Optional parameters

```powershell
-MaxIterations 10
-CommitMessage "Message"
-NoPush
-TestCommand "python -m pytest"
-PostFixCommand "python src/main.py some-command"
-SafeAddPaths "src/,tests/,README.md,scripts/,ai_loop.py,pytest.ini,.gitignore,requirements.txt,pyproject.toml,setup.cfg,.ai-loop/task.md,.ai-loop/cursor_summary.md,.ai-loop/project_summary.md"
```

## Safety model

The orchestrator does **not** stage everything by default.

It stages only `SafeAddPaths`. Runtime artifacts are intentionally excluded:

```text
.ai-loop/codex_review.md
.ai-loop/last_diff.patch
.ai-loop/test_output.txt
.ai-loop/test_output_before_commit.txt
.ai-loop/next_cursor_prompt.md
.ai-loop/final_status.md
.tmp/
input/
output/
```

You should still review `.gitignore` in every target project.

## Public repository warning

Before publishing this project publicly, make sure you have not committed:

- API keys
- credentials
- private project files
- real task outputs
- private `.ai-loop/*review.md` files
- generated `input/` or `output/` data

## Suggested workflow

1. Write a precise task into `.ai-loop/task.md`.
2. Make sure `.ai-loop/project_summary.md` describes the current project context.
3. Run `ai_loop_auto.ps1`.
4. Wait for `final_status.md`.
5. If stopped, inspect:
   - `.ai-loop/codex_review.md`
   - `.ai-loop/cursor_summary.md`
6. Continue with `continue_ai_loop.ps1`.
