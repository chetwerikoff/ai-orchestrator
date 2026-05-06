# Design Decisions

## DD-001: File-based memory instead of chat memory

Agents do not rely on shared chat context. They exchange durable state through `.ai-loop/`.

## DD-002: Project summary as durable context

`.ai-loop/project_summary.md` stores durable project-level memory:
purpose, architecture, decisions, current stage, risks, and next steps.

It is not a detailed task log.

## DD-003: Codex is primary reviewer, Claude is final reviewer

Codex reviews the implementation against the task.
Claude performs final independent review before commit/push.

## DD-004: Safe staging only

The orchestrator does not use `git add -A`.
Only configured safe paths are staged.

## DD-005: Runtime artifacts are not committed

Review logs, diffs, test outputs, final status, temp files, input data, and output data are not staged by default.
