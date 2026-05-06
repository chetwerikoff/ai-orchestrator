# Workflow

## Overview

The orchestrator uses a file-based protocol:

```text
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
