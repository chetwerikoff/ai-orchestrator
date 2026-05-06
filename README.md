# A Git Orchestrator

A local PowerShell-based AI development loop for coordinating:

- Cursor Agent as implementer
- Codex as primary reviewer
- Claude as final reviewer
- project tests
- safe git commit and push

The orchestrator is designed to be installed into any git project that uses a file-based task workflow under `.ai-loop/`.

## What it does

1. Runs tests.
2. Saves `git diff` and `git status`.
3. Runs Codex review.
4. If Codex requests fixes, runs Cursor Agent.
5. Repeats until Codex passes or `MaxIterations` is reached.
6. Runs Claude as final reviewer.
7. If Claude passes, runs a final test gate.
8. Commits and optionally pushes safe project files.

## Requirements

Install and authenticate:

```powershell
agent --version
codex --version
claude --version
git --version
```

Expected CLIs:

- Cursor CLI: `agent`
- OpenAI Codex CLI: `codex`
- Claude Code CLI: `claude`

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
.ai-loop/codex_review_prompt.md
.ai-loop/claude_final_review_prompt.md
.ai-loop/cursor_summary_template.md
```

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
-NoClaudeFinalReview
-TestCommand "python -m pytest"
-PostFixCommand "python src/main.py some-command"
-SafeAddPaths "src/,tests/,README.md,scripts/,.gitignore,requirements.txt,pyproject.toml,.ai-loop/task.md,.ai-loop/cursor_summary.md"
```

## Safety model

The orchestrator does **not** stage everything by default.

It stages only `SafeAddPaths`. Runtime artifacts are intentionally excluded:

```text
.ai-loop/codex_review.md
.ai-loop/claude_final_review.md
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
2. Run `ai_loop_auto.ps1`.
3. Wait for `final_status.md`.
4. If stopped, inspect:
   - `.ai-loop/codex_review.md`
   - `.ai-loop/claude_final_review.md`
   - `.ai-loop/cursor_summary.md`
5. Continue with `continue_ai_loop.ps1`.
