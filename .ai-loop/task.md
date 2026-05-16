# Task: Token ledger v2 — chain accounting (planner_chain_id, phase, role, fix_iteration_index, prompt_bytes)

## Project context

Required reading before starting:

1. `AGENTS.md`
2. `.ai-loop/task.md`
3. `.ai-loop/project_summary.md` — token reporting status, known Cursor blind spot
4. `scripts/record_token_usage.ps1` — `ConvertFrom-CliTokenUsage`, `Write-CliCaptureTokenUsageIfParsed`, `Write-TokenUsageRecord`
5. `scripts/show_token_report.ps1` — current console report
6. `scripts/ai_loop_plan.ps1` — planner pass that should open a chain
7. `scripts/ai_loop_auto.ps1` — fix-loop counter, Codex review JSONL hook
8. `scripts/ai_loop_task_first.ps1` — task-first entry that hands off to auto-loop
9. `scripts/run_claude_planner.ps1`, `scripts/run_codex_reviewer.ps1`, `scripts/run_claude_reviewer.ps1`, `scripts/run_cursor_agent.ps1`, `scripts/run_opencode_agent.ps1` — wrappers that already call `Write-CliCaptureTokenUsageIfParsed`

## Goal

Extend `.ai-loop/token_usage.jsonl` with chain-level fields so that one
`task.md` lifecycle (planner → review/revision → implementer → Codex review →
fix iterations → PASS) can be reconstructed from JSONL alone. This enables
comparing planner forms (Claude CLI plan vs Cursor plan, with/without review,
Codex vs Claude Haiku reviewer) by their downstream `fix_iteration_index`
medians without manual log archaeology.

Recording must remain **non-blocking**: any failure in chain bookkeeping
warns and continues. No new failure mode in the loop.

## Background (do not re-derive)

- Planner model is always Sonnet in current usage. `planner_model` is recorded
  for drift detection, not as a comparison axis.
- Cursor CLI in default mode emits no parseable usage. `prompt_bytes` is the
  physical-load proxy for Cursor planner / implementer plumbing.
- Existing dedupe via `-DedupeId` (SHA256 of captured text per dedupe key in
  process memory) must keep working unchanged.
- `Write-TokenUsageRecord` already accepts `TaskName`, `Iteration`,
  `Provider`, `Model`. New fields extend that signature; old callers stay valid
  by passing defaults.

## Required behavior

### 1. Chain lifecycle file `.ai-loop/chain.json`

- Runtime-only, gitignored (add to `.gitignore` if not already covered by
  `.ai-loop/` glob).
- Created by `ai_loop_plan.ps1` at planner start, or by
  `ai_loop_task_first.ps1` when `task.md` is hand-authored (no plan pass) and
  no open chain exists.
- Fields:
  ```json
  {
    "planner_chain_id": "<8-hex>",
    "task_name": "<H1 of .ai-loop/task.md at chain open>",
    "started_at_utc": "<ISO-8601>",
    "planner_form": {
      "planner_command": "run_claude_planner.ps1 | run_cursor_agent.ps1 | manual | ...",
      "planner_model": "<best-effort string or empty>",
      "reviewer_command": "run_codex_reviewer.ps1 | run_claude_reviewer.ps1 | none",
      "reviewer_model": "<best-effort or empty>",
      "max_review_iters": 0,
      "no_revision": false
    }
  }
  ```
- `planner_chain_id` = 8 hex chars from a fresh GUID. Sufficient for grouping;
  not a security identifier.
- On chain open: if `.ai-loop/chain.json` already exists, **warn and keep the
  existing chain** (do not overwrite silently). New flag `-ForceNewChain` on
  `ai_loop_plan.ps1` and `ai_loop_task_first.ps1` overwrites with a fresh
  chain. This prevents data corruption when two passes race.
- On PASS in `ai_loop_auto.ps1` (after `Commit-And-Push` returns success) **or**
  on terminal failure, archive `.ai-loop/chain.json` to
  `.ai-loop/_debug/chains/<planner_chain_id>.json` (best-effort; non-fatal)
  and delete `chain.json`. Wrap-up (`wrap_up_session.ps1`) is unrelated and
  does not close the chain.
- Manual chain (no planner pass): when `ai_loop_task_first.ps1` opens the
  chain, set `planner_command = "manual"`, leave reviewer fields empty,
  `max_review_iters = 0`, `no_revision = true`.

### 2. New JSONL fields

Extend `Write-TokenUsageRecord` and the JSONL row schema with:

```text
planner_chain_id      string  — empty if no chain.json found at write time
phase                 string  — "planning" | "implementation" | "wrap_up"
role                  string  — "planner" | "planner_review" | "planner_revision"
                              | "implementer" | "codex_review" | "wrap_up"
fix_iteration_index   int     — 0 for first implementer pass; 1+ after FIX_REQUIRED;
                                null/empty for planning + wrap_up rows
prompt_bytes          int     — UTF-8 byte length of the stdin actually fed to the
                                CLI (0 if not measurable in the wrapper)
planner_command       string  — only in role="planner*" rows (read from chain.json)
reviewer_command      string  — only in role="planner_review" rows
max_review_iters      int     — only in role="planner*" rows
no_revision           bool    — only in role="planner*" rows
```

Backward compatibility: all new fields are optional in the row schema. Rows
written before this task are valid and must continue to parse in
`show_token_report.ps1`. Treat missing fields as empty/null on read.

### 3. Wiring per wrapper

Each wrapper that already calls `Write-CliCaptureTokenUsageIfParsed` must:

- Read `.ai-loop/chain.json` (best-effort; absent → leave fields empty).
- Pass `-PlannerChainId`, `-Phase`, `-Role`, `-FixIterationIndex` (when known),
  `-PromptBytes` (computed from the stdin string just before invoking the CLI).
- `run_claude_planner.ps1` / `run_cursor_agent.ps1` when called from
  `ai_loop_plan.ps1`: `phase="planning"`, `role="planner"` initial,
  `role="planner_revision"` on revision passes.
- `run_codex_reviewer.ps1` / `run_claude_reviewer.ps1` when called from
  `ai_loop_plan.ps1`: `phase="planning"`, `role="planner_review"`.
- `run_cursor_agent.ps1` / `run_opencode_agent.ps1` when called from
  `ai_loop_auto.ps1` (implementer): `phase="implementation"`,
  `role="implementer"`, `FixIterationIndex` from the auto-loop counter.
- `Run-CodexReview` in `ai_loop_auto.ps1`: `phase="implementation"`,
  `role="codex_review"`, `FixIterationIndex` matches the implementer pass it
  reviewed.
- `wrap_up_session.ps1`: `phase="wrap_up"`, `role="wrap_up"`.

The split planner vs planner_revision is decided by `ai_loop_plan.ps1`: it
tracks the revision counter already and passes a flag/env to the wrapper
(simplest: env var `AI_LOOP_PLANNER_ROLE` set per call to `planner` or
`planner_revision`).

### 4. `prompt_bytes` measurement

In each wrapper, compute `[System.Text.Encoding]::UTF8.GetByteCount($stdinText)`
on the exact string that becomes stdin. Pass through to
`Write-CliCaptureTokenUsageIfParsed`. If the wrapper does not currently
materialize stdin as one variable, do **not** restructure it — set
`PromptBytes = 0` and document in `implementer_summary.md` which wrappers
were not instrumented.

### 5. `show_token_report.ps1 -ByChain`

New optional switch. When set:

- Group rows by `planner_chain_id` (rows with empty chain_id grouped as
  `"<no chain>"`).
- For each chain print: `task_name`, `planner_form` summary (from first
  `role=planner` row in the group), one line per role with totals
  (`input/output`, `prompt_bytes`), final `fix_iters` count (max
  `fix_iteration_index` seen for implementer rows).
- Default report (no flag) keeps its current shape.

No automatic decisions, no warning thresholds. The point is visibility.

### 6. Documentation

- Update `.ai-loop/project_summary.md` token-reporting paragraph: note new
  fields, the chain.json lifecycle, `-ByChain` flag, and that Cursor planner
  remains blind in `input/output` but now captured in `prompt_bytes`.
- No edits to `docs/architecture.md`, `docs/decisions.md`, or `AGENTS.md` in
  this task. If a DD entry is appropriate, architect will add it separately.

## Scope

Allowed:

- `scripts/record_token_usage.ps1`
- `scripts/show_token_report.ps1`
- `scripts/ai_loop_plan.ps1`
- `scripts/ai_loop_task_first.ps1`
- `scripts/ai_loop_auto.ps1` — only the `Run-CodexReview` JSONL hook and
  fix-iteration counter pass-through; no changes to verdict logic, scope
  filtering, staging, or commit gates.
- `scripts/run_claude_planner.ps1`
- `scripts/run_claude_reviewer.ps1`
- `scripts/run_codex_reviewer.ps1`
- `scripts/run_cursor_agent.ps1`
- `scripts/run_opencode_agent.ps1`
- `scripts/wrap_up_session.ps1`
- `tests/test_token_usage.py`
- `tests/test_orchestrator_validation.py` — only if subprocess coverage for
  chain.json lifecycle / `-ForceNewChain` is needed
- `.ai-loop/project_summary.md`
- `.ai-loop/implementer_summary.md`
- `.gitignore` — only if `.ai-loop/chain.json` is not already covered

Not allowed:

- Changing Codex verdict parsing, FIX_PROMPT extraction, scope filtering,
  staging, commit/push gates, queue protection
- Changing dedupe semantics of `Write-CliCaptureTokenUsageIfParsed`
- Estimating tokens from prompt length or storing them in JSONL as token
  counts (prompt_bytes is bytes, not tokens — keep separate)
- Estimating cost from prompt_bytes
- Storing account identifiers, prompt text, or any secret material
- Auto-decisions based on chain data (warnings, throttling, policy)
- `docs/archive/**`, `.ai-loop/_debug/**` (except chain archive write path),
  `ai_loop.py`
- `tasks/**` (queue protection), `templates/**` unless installer parity
  requires it
- Git commit or push during implementation

## Files in scope

- `scripts/record_token_usage.ps1`
- `scripts/show_token_report.ps1`
- `scripts/ai_loop_plan.ps1`
- `scripts/ai_loop_task_first.ps1`
- `scripts/ai_loop_auto.ps1`
- `scripts/run_claude_planner.ps1`
- `scripts/run_claude_reviewer.ps1`
- `scripts/run_codex_reviewer.ps1`
- `scripts/run_cursor_agent.ps1`
- `scripts/run_opencode_agent.ps1`
- `scripts/wrap_up_session.ps1`
- `tests/test_token_usage.py`
- `tests/test_orchestrator_validation.py`
- `.ai-loop/project_summary.md`
- `.ai-loop/implementer_summary.md`
- `.gitignore`

## Files out of scope

- `docs/architecture.md`, `docs/decisions.md`, `docs/workflow.md`,
  `docs/safety.md`
- `AGENTS.md`, `CLAUDE.md`
- `docs/archive/**`, `.ai-loop/_debug/**` (chain archive write is the one
  exception)
- `ai_loop.py`
- `tasks/**`
- `templates/**`
- `config/token_limits.yaml`

## Tests

Extend `tests/test_token_usage.py` with:

1. `Write-TokenUsageRecord` accepts new fields and they round-trip through
   JSONL parse.
2. Old-format JSONL rows (without new fields) parse without error in
   `show_token_report.ps1` (use a fixture line missing the new keys).
3. `chain.json` create / read / archive cycle: opening a chain when one
   exists warns and preserves the existing chain; `-ForceNewChain` overwrites.
4. `-ByChain` report aggregates two synthetic rows from the same chain into
   one group and computes `fix_iters` from the max `fix_iteration_index`.
5. `prompt_bytes` is recorded as UTF-8 byte length, not character count
   (fixture with multi-byte characters).

All tests must run without live CLIs (no `codex`, `claude`, `cursor-agent`,
`opencode` invocations). Use fixture strings and PowerShell subprocess for
chain.json behavior, matching the style of existing tests.

Run: `python -m pytest -q`.

## Verification

```powershell
python -m pytest -q
pyright
powershell -NoProfile -Command "[void][System.Management.Automation.Language.Parser]::ParseFile('scripts\record_token_usage.ps1', [ref]$null, [ref]$null)"
powershell -NoProfile -Command "[void][System.Management.Automation.Language.Parser]::ParseFile('scripts\show_token_report.ps1', [ref]$null, [ref]$null)"
powershell -NoProfile -Command "[void][System.Management.Automation.Language.Parser]::ParseFile('scripts\ai_loop_plan.ps1', [ref]$null, [ref]$null)"
powershell -NoProfile -Command "[void][System.Management.Automation.Language.Parser]::ParseFile('scripts\ai_loop_task_first.ps1', [ref]$null, [ref]$null)"
powershell -NoProfile -Command "[void][System.Management.Automation.Language.Parser]::ParseFile('scripts\ai_loop_auto.ps1', [ref]$null, [ref]$null)"
powershell -NoProfile -Command "[void][System.Management.Automation.Language.Parser]::ParseFile('scripts\run_claude_planner.ps1', [ref]$null, [ref]$null)"
powershell -NoProfile -Command "[void][System.Management.Automation.Language.Parser]::ParseFile('scripts\run_claude_reviewer.ps1', [ref]$null, [ref]$null)"
powershell -NoProfile -Command "[void][System.Management.Automation.Language.Parser]::ParseFile('scripts\run_codex_reviewer.ps1', [ref]$null, [ref]$null)"
powershell -NoProfile -Command "[void][System.Management.Automation.Language.Parser]::ParseFile('scripts\run_cursor_agent.ps1', [ref]$null, [ref]$null)"
powershell -NoProfile -Command "[void][System.Management.Automation.Language.Parser]::ParseFile('scripts\run_opencode_agent.ps1', [ref]$null, [ref]$null)"
powershell -NoProfile -Command "[void][System.Management.Automation.Language.Parser]::ParseFile('scripts\wrap_up_session.ps1', [ref]$null, [ref]$null)"
```

## Implementer summary requirements

1. Changed files (brief list).
2. `python -m pytest -q` result (counts only).
3. What was implemented (5–8 lines): schema delta, chain.json lifecycle,
   wrappers wired, `-ByChain` report, `-ForceNewChain` behavior.
4. Wrappers **not** instrumented for `prompt_bytes` and why (e.g. stdin not
   materialized as one variable in a given wrapper).
5. Remaining risks (1–3 bullets).

## Important

- Keep recording non-blocking everywhere. A failed `chain.json` read must
  warn and proceed with empty chain fields, never throw out of the wrapper.
- Do not introduce a new dependency on `ConvertFrom-Json -AsHashtable`
  (Windows PowerShell 5.1 lacks it). Use PSCustomObject access.
- Do not change the on-disk path of `.ai-loop/token_usage.jsonl` or
  `config/token_limits.yaml`.
- `prompt_bytes` is **bytes**, not tokens, and not a cost estimate. Do not
  let it leak into cost columns. The whole point is to have a measurable
  proxy that does not pretend to be a token count.
- Target diff size: ~200 lines PowerShell + ~80 lines Python tests. If the
  diff balloons past 400 lines total, split the planner-side instrumentation
  into a follow-up task and ship the schema + auto-loop side first.
- Architect note: this task is data collection only. No decisions, no auto-
  trimming, no warnings on chain cost. Those follow only if 2–3 weeks of
  collected data justify them.
- Architect note: the four planner forms currently in use (Claude CLI +
  Codex; Cursor + Haiku; Cursor + Sonnet + Codex; Cursor + Sonnet no review)
  must all produce distinguishable `planner_form` records via the
  decomposed fields. Do not collapse them into a string enum.

## Order

19
