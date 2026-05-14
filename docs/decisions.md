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

## DD-011: MaxIterations cap (pending alignment)

Orchestrator entrypoints default `-MaxIterations` to **10**; architecture review recommends **3** to limit reviewer thrash and cost. Alignment of scripts and docs is deferred to a dedicated change; scripts still use 10 today.

See `docs/architecture.md` §12 DD-011 for rationale and risk notes.

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

## DD-020: OpenCode↔llama text-tool normalization proxy (optional)

Use an optional local HTTP proxy (`opencode_proxy.py` on port **8090**) when a model emits **text-format** tool calls; it normalizes responses to structured `tool_calls[]`. **Phase 1 A/B** uses **direct** `llama-server` URLs in **`templates/opencode.json`** (ports **8081 / 8082 / 8083**) for Qwen3 stacks that already emit native tool calls; **8090** is not required for that path. The proxy script currently lives outside this repository pending relocation (Q-10).

See `docs/architecture.md` §12 DD-020 for rationale and risk notes.

## DD-021: Cursor as transitional implementer through Phase 1

Keep Cursor Agent as the production implementer until OpenCode + Qwen3-Coder-30B-A3B has demonstrated stable behavior across real H2N workloads using the **Phase 1 direct** OpenCode wiring (§5.3 / `templates/opencode.json`); use the **DD-020** proxy only when the active model needs normalization. Until then, OpenCode runs only on Phase-1 A/B comparison tasks.

See `docs/architecture.md` §12 DD-021 for rationale and risk notes.

## DD-022: Optional scout pre-pass (`-WithScout`)

Opt-in `scripts/run_scout_pass.ps1` before the implementer in task-first mode; adds `RELEVANT FILES (from scout):` to the prompt only when scout JSON is valid and non-empty. Default path unchanged (C02 ordering).

See `docs/architecture.md` §12 DD-022 for rationale and risk notes.

## DD-023: Opt-in wrap-up and failures log (C05)

Date: May 14, 2026
Status: accepted

Context: No cross-session memory for recurring failures existed. Options considered: `.ai-memory/` directory (rejected adds stale-index risk and maintenance burden), semantic search (rejected overkill for repos under roughly 100k LOC), external service (rejected adds dependency).

Decision: Minimal two-script approach. `scripts/wrap_up_session.ps1` drafts session output after a passing driver finish when `-WithWrapUp`. `scripts/promote_session.ps1` (manual) persists drafts into `.ai-loop/failures.md`. A rolling cap of 200 total lines moves overflow rows into `.ai-loop/archive/failures/` snapshots named by deterministic dates. No classifier, no outbound HTTP.

Consequences: Developers must invoke `promote_session.ps1` manually to anchor history ahead of truncation. `_debug/session_draft.md` stays ephemeral until promotion.
