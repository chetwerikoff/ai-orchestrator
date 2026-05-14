# Design Decisions

Full rationale, risks, and supersession status for each decision are in
`docs/architecture.md` §12 Decision Log. This file is a numbered index;
treat the architecture-doc version as authoritative when they diverge.

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

## DD-006: Task-first mode skips Codex on implementer no-op

`scripts/ai_loop_task_first.ps1` clears stale `.ai-loop` runtime files (except `task.md`), runs the configured implementer first, and calls `ai_loop_auto.ps1` only after detecting meaningful git changes (or an explicit `IMPLEMENTATION_STATUS: DONE_NO_CODE_CHANGES_REQUIRED` in `implementer_result.md` when only that file changed). Two implementer passes with no detectable changes skips Codex and exits non-zero with `NO_CHANGES_AFTER_IMPLEMENTER`.

## DD-007: (reserved / not yet defined)

Placeholder; see `docs/architecture.md` §12 for current decision numbering.

## DD-008: (reserved / not yet defined)

Placeholder; see `docs/architecture.md` §12 for current decision numbering.

## DD-009: (reserved / not yet defined)

Placeholder; see `docs/architecture.md` §12 for current decision numbering.

## DD-010: (reserved / not yet defined)

Placeholder; see `docs/architecture.md` §12 for current decision numbering.

## DD-011: MaxIterations cap

Orchestrator entrypoints default `-MaxIterations` to **5**. Override at call time with `-MaxIterations N` for exceptional cases.

See `docs/architecture.md` §12 DD-011 for rationale.

## DD-012: (reserved / not yet defined)

Placeholder; see `docs/architecture.md` §12 for current decision numbering.

## DD-013: (reserved / not yet defined)

Placeholder; see `docs/architecture.md` §12 for current decision numbering.

## DD-014: (reserved / not yet defined)

Placeholder; see `docs/architecture.md` §12 for current decision numbering.

## DD-015: (reserved / not yet defined)

Placeholder; see `docs/architecture.md` §12 for current decision numbering.

## DD-016: (reserved / not yet defined)

Placeholder; see `docs/architecture.md` §12 for current decision numbering.

## DD-017: (reserved / not yet defined)

Placeholder; see `docs/architecture.md` §12 for current decision numbering.

## DD-018: (reserved / not yet defined)

Placeholder; see `docs/architecture.md` §12 for current decision numbering.

## DD-019: (reserved / not yet defined)

Placeholder; see `docs/architecture.md` §12 for current decision numbering.

## DD-020: OpenCode↔llama text-tool normalization proxy (retired)

Proxy retired 2026-05-14. Phase 1 A/B closed; Cursor confirmed as permanent default implementer; no active workflow depends on the proxy.

## DD-021: Cursor as permanent default implementer

Cursor Agent is the confirmed production implementer (Phase 1 A/B closed 2026-05-14). OpenCode + Qwen available opt-in via `-CursorCommand`.

## DD-022: Optional scout pre-pass (`-WithScout`)

Opt-in `scripts/run_scout_pass.ps1` before the implementer in task-first mode; adds `RELEVANT FILES (from scout):` to the prompt only when scout JSON is valid and non-empty. Default path unchanged (C02 ordering).

See `docs/architecture.md` §12 DD-022 for rationale and risk notes.

## DD-023: Opt-in wrap-up and failures log (C05)

Date: May 14, 2026
Status: accepted

Context: No cross-session memory for recurring failures existed. Options considered: `.ai-memory/` directory (rejected adds stale-index risk and maintenance burden), semantic search (rejected overkill for repos under roughly 100k LOC), external service (rejected adds dependency).

Decision: Minimal two-script approach. `scripts/wrap_up_session.ps1` drafts session output after a passing driver finish when `-WithWrapUp`. `scripts/promote_session.ps1` (manual) persists drafts into `.ai-loop/failures.md`. A rolling cap of 200 total lines moves overflow rows into `.ai-loop/archive/failures/` snapshots named by deterministic dates. No classifier, no outbound HTTP.

Consequences: Developers must invoke `promote_session.ps1` manually to anchor history ahead of truncation. `_debug/session_draft.md` stays ephemeral until promotion.
