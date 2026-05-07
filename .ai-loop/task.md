# Task

The prior Cursor specification for P0 orchestrator fixes is **implemented**. Drive the loop from:

- **New task (Cursor first):** `scripts\ai_loop_task_first.ps1` — clears stale `.ai-loop` runtime files (except this file), runs Cursor, then `ai_loop_auto.ps1` only when there are meaningful working tree changes.
- **Review-first (existing changes):** `scripts\ai_loop_auto.ps1`

See `README.md` and `docs/workflow.md` for flags and behavior (including `NO_CHANGES_AFTER_CURSOR` and `IMPLEMENTATION_STATUS: DONE_NO_CODE_CHANGES_REQUIRED`).
