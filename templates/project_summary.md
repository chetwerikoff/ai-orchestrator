# Project Summary

<!--
HARD RULES for project_summary.md:

1. This file is DURABLE orientation, not a per-task changelog.
2. Target length: under 80 lines. If the file exceeds 100 lines, compact it: move "Earlier roll" / "Last completed task" content into .ai-loop/archive/rolls/<date>_<topic>.md.
3. Do NOT accumulate "Earlier roll" sections in this file. The "Last completed task" section holds ONLY the most recent task.
4. Do NOT copy code, function signatures, or backtick-heavy API surfaces. Use prose pointers to source files.
5. Active design constraints stay here. Historical decisions go to docs/decisions.md.

When in doubt: ask, does this help an agent orient on the NEXT task?
If no, it belongs in archive/.
-->

See `AGENTS.md` at repo root for agent working scope, read priority, and paths to avoid.

## Project purpose

Describe the purpose of this project in 5–10 lines.

## Current architecture

List the main modules/components and what they do.

Example:

- `src/...` — ...
- `tests/...` — ...
- `scripts/...` — ...

## Current pipeline / workflow

Describe the current project workflow.

Example:

```text
task.md
→ implementer pass (default: Cursor Agent; alternate wrappers e.g. OpenCode via project scripts)
→ Codex review
→ final test gate (after Codex PASS)
→ commit/push
```

If this repo uses the shipped PowerShell drivers, **`.ai-loop/implementer.json`** (runtime; should stay gitignored) holds the last effective implementer wrapper and model so **`continue_ai_loop.ps1`** can resume OpenCode/Qwen runs without repeating `-CursorCommand` / `-CursorModel`. Explicit switches still override that file.

## Important design decisions

- ...

## Known risks / constraints

- ...

## Current stage

Describe the current development stage.

## Last completed task

Most recent task only. Older tasks belong in `.ai-loop/archive/rolls/`.

Commit:
`<commit hash> <commit message>`

Summary:
- ...

## Next likely steps

1. ...
2. ...
3. ...

## Notes for future AI sessions

Things the **implementer** and **Codex** should remember before making changes (your install may use Cursor Agent, OpenCode/Qwen, or another wrapper for the implementer step):

- ...
