# Workflow

## Overview

The orchestrator uses a file-based protocol:

```text
.ai-loop/project_summary.md
.ai-loop/task.md
  -> Cursor implements
  -> .ai-loop/cursor_summary.md
  -> tests + diff
  -> Codex review
  -> Cursor fixes if needed
  -> Claude final review
  -> final test gate
  -> git commit/push
```

## File roles

- `.ai-loop/project_summary.md` — durable project-level context.
- `.ai-loop/task.md` — current task contract.
- `.ai-loop/cursor_summary.md` — latest implementation summary.
- `.ai-loop/codex_review.md` — primary review output.
- `.ai-loop/claude_final_review.md` — final review output.
- `.ai-loop/last_diff.patch` — current diff.
- `.ai-loop/test_output.txt` — current test output.

## Start

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\ai_loop_auto.ps1 `
  -MaxIterations 10 `
  -CommitMessage "Implement feature"
```

## Continue

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\continue_ai_loop.ps1 `
  -CommitMessage "Continue feature"
```

## Disable push

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\ai_loop_auto.ps1 `
  -CommitMessage "Implement feature" `
  -NoPush
```

## Disable Claude final review

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\ai_loop_auto.ps1 `
  -CommitMessage "Implement feature" `
  -NoClaudeFinalReview
```

## Custom test command

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\ai_loop_auto.ps1 `
  -TestCommand "npm test" `
  -CommitMessage "Implement feature"
```

## Project-specific post-fix command

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\ai_loop_auto.ps1 `
  -PostFixCommand "python src/main.py smoke-test" `
  -CommitMessage "Implement feature"
```
