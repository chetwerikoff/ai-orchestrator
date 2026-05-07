# Design Decisions

## DD-001: File-based memory instead of chat memory

Agents do not rely on shared chat context. They exchange durable state through `.ai-loop/`.

## DD-002: Project summary as durable context

`.ai-loop/project_summary.md` stores durable project-level memory:
purpose, architecture, decisions, current stage, risks, and next steps.

It is not a detailed task log.

## DD-003: Codex gates commit/push

Codex reviews the implementation against the task.
After `VERDICT: PASS`, the orchestrator runs the final test gate, then commit/push (unless `-NoPush`).

## DD-004: Safe staging only

The orchestrator does not use `git add -A`.
Only configured safe paths are staged.

## DD-005: Runtime artifacts are not committed

Review logs, diffs, test outputs, final status, temp files, input data, and output data are not staged by default.

## DD-006: Task-first mode skips Codex on Cursor no-op

`scripts/ai_loop_task_first.ps1` clears stale `.ai-loop` runtime files (except `task.md`), runs Cursor first, and calls `ai_loop_auto.ps1` only after detecting meaningful git changes (or an explicit `IMPLEMENTATION_STATUS: DONE_NO_CODE_CHANGES_REQUIRED` in `cursor_implementation_result.md` when only that file changed). Two Cursor passes with no detectable changes skips Codex and exits non-zero with `NO_CHANGES_AFTER_CURSOR`.
