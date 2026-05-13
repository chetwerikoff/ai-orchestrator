# Workflow

> **Current state vs target.** This document describes the workflow that
> runs in production today (Cursor Agent as the default implementer, Codex as reviewer).
> See `docs/architecture.md` §0 for a structured statement of current
> state, and §1 onwards for the target multi-model design we are
> building toward.

## Overview

The orchestrator uses a file-based protocol:

```text
.ai-loop/project_summary.md
.ai-loop/task.md
  -> Implementer implements (Cursor Agent by default, or `-CursorCommand` e.g. OpenCode wrapper)
  -> .ai-loop/implementer_summary.md
  -> tests + diff
  -> Codex review
  -> Implementer fixes if needed
  -> final test gate (after Codex PASS)
  -> git commit/push
```

## File roles

- `.ai-loop/project_summary.md` — durable project-level context.
- `.ai-loop/task.md` — current task contract.
- `.ai-loop/implementer_summary.md` — latest implementation summary.
- `.ai-loop/codex_review.md` — primary review output.
- `.ai-loop/last_diff.patch` — current diff.
- `.ai-loop/test_output.txt` — current test output.

## Start a new task

Use this when `.ai-loop/task.md` contains a new implementation task:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\ai_loop_task_first.ps1 `
  -MaxIterations 10 `
  -CommitMessage "Implement feature" `
  -NoPush `
  -TestCommand "python -m pytest -q"
```

This clears stale `.ai-loop` runtime files (except `task.md`), runs the configured implementer first (Cursor Agent by default; override with `-CursorCommand`), resets `.ai-loop/implementer_summary.md` to a fresh stub (the implementer must fill it), then hands off to `ai_loop_auto.ps1` only if the implementer produced relevant git changes (or a documented no-code completion via `implementer_result.md`). If the implementer makes no effective changes twice, Codex is skipped and the script fails with `NO_CHANGES_AFTER_IMPLEMENTER`.

### `IMPLEMENTATION_STATUS: DONE_NO_CODE_CHANGES_REQUIRED`

Task-first mode may treat **only** `.ai-loop/implementer_result.md` as the implementation delta (for example when git ignores that file or it alone changed vs filtered porcelain). In that situation the orchestrator allows proceeding **only if** `implementer_result.md` contains this marker as its **own line**.

Exact marker behavior in `scripts/ai_loop_task_first.ps1` (`Test-ImplementerResultAllowsNoCodeChanges`): the file must match this regular expression (case-insensitive, multiline):

```text
(?im)^IMPLEMENTATION_STATUS:\s*DONE_NO_CODE_CHANGES_REQUIRED\s*$
```

Literal line that satisfies the regex (trimmed for readability):

```text
IMPLEMENTATION_STATUS: DONE_NO_CODE_CHANGES_REQUIRED
```

Rules enforced:

- There must be **nothing else on that line** except optional whitespace after the colon before `DONE_NO_CODE_CHANGES_REQUIRED`.
- The label must be exactly `DONE_NO_CODE_CHANGES_REQUIRED` (not a synonym); extra text on the same line causes the match to fail.
- Trailing spaces after `DONE_NO_CODE_CHANGES_REQUIRED` are allowed (they are consumed by `\s*` before end-of-line).
- If the sole delta is that result file and this line is missing (or does not match), the script exits with `RESULT_ONLY_WITHOUT_DONE_NO_CODE_MARKER` (details written to `.ai-loop/final_status.md`).

If there are other implementation deltas (other paths changed), this marker is not required.

Omit `-NoPush` / `-TestCommand` lines you do not need; `ai_loop_task_first.ps1` forwards `-NoPush`, `-TestCommand`, `-PostFixCommand`, and `-SafeAddPaths` to `ai_loop_auto.ps1` with the same meaning as when you call `ai_loop_auto.ps1` directly.

## Review/fix existing changes

Use this only when implementation changes already exist and you want to start from tests + Codex review:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\ai_loop_auto.ps1 `
  -MaxIterations 10 `
  -CommitMessage "Review existing changes"
```

## Continue

Resume forwarding uses `scripts/continue_ai_loop.ps1`, which calls `ai_loop_auto.ps1 -Resume`.

**Persisted implementer:** After task-first or any auto loop run, the drivers write **`.ai-loop/implementer.json`** (runtime; gitignored) with the effective wrapper path and model. On resume, if you **omit** `-CursorCommand` / `-CursorModel`, `ai_loop_auto.ps1 -Resume` reloads those values so an OpenCode/Qwen task does not silently fall back to the default Cursor wrapper.

**Explicit overrides:** Optional `-CursorCommand` / `-CursorModel` on `continue_ai_loop.ps1` are forwarded and always win over the persisted file; the file is then updated to match the effective selection.

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\continue_ai_loop.ps1 `
  -CommitMessage "Continue feature"
```

Override example (same as task-first):

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\continue_ai_loop.ps1 `
  -CommitMessage "Continue feature" `
  -CursorCommand ".\scripts\run_opencode_agent.ps1" `
  -CursorModel "local-qwen-35b/qwen3-6-35b-a3b"
```

## Disable push

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\ai_loop_auto.ps1 `
  -CommitMessage "Implement feature" `
  -NoPush
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
