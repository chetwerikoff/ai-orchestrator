---
doc_type: architecture
status: living_document
as_of: 2026-05-13
---

# Architecture — AI Orchestrator

## Single-Page Summary

- **§0** is ground truth for what runs today (Cursor implementer, Codex reviewer, file-based `.ai-loop/` contract).
- **§1 onward** describe the *target* asymmetric multi-model factory: Claude planner → OpenCode + local Qwen coder → deterministic guards → Codex → Claude business gate. That pipeline is aspirational until phased rollout completes.
- **§9–§11** spell out deferred harness layouts, deterministic safety expectations, companion-doc roles, plus archive paths for verbatim expert critique (**§9 carries the substantive blueprint internally** — not summarized away).
- **Phase 0 (2026-05-11)** validated OpenCode + `llama-server` on Windows with a canonical trivial task. **Phase 1 A/B is IN PROGRESS (2026-05-13)** with three Qwen models at ports 8081/8082/8083 — direct connections, no proxy required (all emit native `tool_calls[]`). Proxy at **:8090** remains available as fallback — see **DD-020** and **§5.3**. **DD-022** adds an opt-in scout pre-pass (`-WithScout`) for OpenCode/Qwen; default Cursor path unchanged.
- Full numbered decisions live in **§12**; open questions in **§13**.

## §0 Current state (as of 2026-05-12)

This section describes what the orchestrator actually does today.
Sections §1 onwards describe the target design we are building toward.
Where current state and target diverge, current state is the ground
truth; target is aspirational.

### §0.1 Active workflow

```text
.ai-loop/task.md
  -> Implementer (Cursor Agent `agent` CLI by default, or `-CursorCommand`)
  -> .ai-loop/implementer_summary.md
  -> Save-TestAndDiff (pytest, git diff, git status)
  -> Codex CLI reviews
  -> if PASS: final test gate + git commit + push (unless -NoPush)
  -> if FIX_REQUIRED: extract FIX_PROMPT_FOR_IMPLEMENTER, re-run implementer
  -> cap: MaxIterations (default 5, per DD-011)
```

Manual / out-of-loop:

- Task creation: human writes `.ai-loop/task.md` directly.
- Business-logic review: human-driven, lives in
  `H2N_parser/h2n-claude-review/REVIEW_STATE.md` and
  `cursor_tasks/*.md`. Not invoked by the orchestrator.

### §0.2 Roles in production today

- **Implementer**: Cursor Agent (not local Qwen, not OpenCode).
- **Technical reviewer**: Codex CLI.
- **Planner**: human.
- **Business reviewer**: human, manually through Cursor in a separate
  repo.

### §0.3 Phase 0 outcome (OpenCode + local Qwen)

Phase 0 ran on 2026-05-11 against the same canonical trivial task
("create qwen_test.txt with one line of content"). Results recorded in
`H2N_parser/h2n-range-extractor/p0_ab_results.md`:

| Candidate | Result | Notes |
|---|---|---|
| Qwen2.5-Coder-14B Q5_K_M (baseline) | **FAIL** | Outputs `<tools>` as plain text; `tool_choice: required` causes infinite generation. Excluded from P1. |
| Qwen3-Coder-30B-A3B Q3_K_M (challenger A) | **PASS** | Native `tool_calls[]`, ~103 tok/s, ~14.5 GB VRAM peak. Selected as P1 default. |
| Qwen3.6-27B IQ4_XS (challenger B) | not run | VRAM headroom too tight on baseline +14B; deferred to P1 if challenger A shows quality issues. |

Integration stack chosen by P0 result:

```text
OpenCode (non-interactive)
  -> llama-server :8081  (Qwen3-Coder-30B-A3B)
       -ngl 999 --n-cpu-moe 999 -c 131072 --parallel 1
       --flash-attn on --cache-type-k q8_0 --cache-type-v q8_0
```

**Phase 1 A/B stack** (as of 2026-05-13) — three direct providers, no proxy:

```text
:8081  Qwen3-Coder-30B-A3B-Instruct-Q3_K_M  (MoE, -c 131072, --n-cpu-moe 999)
:8082  Qwen3.6-27B-IQ4_XS                   (dense, -c 32768, --cache-type-k/v q4_0)
:8083  Qwen3.6-35B-A3B-UD-Q4_K_M            (MoE, -c 131072, --n-cpu-moe 999)
```

The proxy at `:8090` is **not used** in the Phase 1 A/B setup — all three models
emit native `tool_calls[]` with llama.cpp `--jinja` (default). `opencode.json`
in the target project defines each model as a separate provider pointing directly
to its port. Proxy remains available as a fallback for text-format tool emitters
(see DD-020 / §5.3).

Orchestrator integration: pass `-CursorCommand .\scripts\run_opencode_agent.ps1
-CursorModel <provider/model-id>` to `ai_loop_task_first.ps1` to substitute
OpenCode for Cursor as the implementer in the loop. The effective wrapper and
model are written to **`.ai-loop/implementer.json`** (runtime, gitignored) so
`continue_ai_loop.ps1` or `ai_loop_auto.ps1 -Resume` can reload them without
repeating those switches; explicit `-CursorCommand` / `-CursorModel` still
override the file.

### §0.4 Gap between current state and target

- Claude is not in the loop yet (planner / business gate).
- OpenCode + Qwen has completed P0 but is not yet the default
  implementer; Cursor remains the production implementer (see **DD-021**).
- `domain_gate.py`, `diff_guard.py` from the target design do not exist
  yet in `scripts/`.
- `opencode_proxy.py` is a critical new component not yet in this repo
  (lives in `C:\AI\scripts\`). See DD-020, Q-10.
- `scripts/run_opencode_agent.ps1` **exists** — PowerShell wrapper that
  bridges `ai_loop_auto.ps1` to `opencode run`; activated via
  `-CursorCommand` flag. Also copied to target projects' `scripts/`.

The phase plan in §8 is the path from "current state" to "target state".

## §1 Vision (target)

*This section describes the target design (see §0 for current state).*

Build a **local-first** development loop that combines:

1. A **planning** stage (Claude-class) producing a durable `task.md` contract.
2. A **coding agent** executing against a real repo (target: **OpenCode** driving **local Qwen** via `llama-server` — **direct** `/v1` per provider for Phase 1 when models emit native `tool_calls[]`; optional **proxy** normalization per **DD-020** when a model emits text-format tool blocks).
3. **Deterministic guards** (forbidden paths, tests, optional domain checks) so LLM output cannot violate repo policy silently.
4. **Independent technical review** (Codex — different model family from the coder).
5. An optional **business / product** review pass (Claude) before merge.

The orchestrator in this repository implements the **file protocol**, **task-first vs review-first** entrypoints, **safe git staging**, and the **Cursor + Codex** production path today (§0). Target sections describe how the same contract extends to the full factory.

## §2 Architectural principles (target)

- **File-based memory**: agents do not depend on hidden chat state; durable artifacts live under `.ai-loop/` (aligns with **DD-001**, **DD-002**).
- **Safe staging only**: never `git add -A` — only allowlisted paths (**DD-004**).
- **Independent review signal**: the technical reviewer must not share the same blind spots as the primary implementer for pass/fail gates — Codex vs Cursor today; Codex vs local Qwen in the target (**DD-003**).
- **Evidence over narrative**: tests, diffs, and structured logs beat prose summaries for gate conditions.
- **Phased rollout**: prove local tool-calling integration under a trivial task (Phase 0), then expand task complexity (Phase 1+) before switching the default implementer (**DD-021**).

## §3 Model Roles (target)

| Role | Target model / runtime | Notes |
|------|-------------------------|--------|
| Planner | Claude Sonnet (API) | Writes / refines `task.md`, scope, acceptance criteria. Not in the automated loop yet (§0). |
| Implementer (target) | OpenCode + **Qwen3-Coder-30B-A3B** via `llama-server` :8081 | Phase 0 validated **challenger A**; baseline **14B FAIL**. Phase 1 also tests **Qwen3.6-27B** (:8082) and **Qwen3.6-35B-A3B** (:8083, MoE). Production today: **Cursor** (**DD-021**). |
| Technical reviewer | Codex CLI | Gates commit/push after **VERDICT: PASS** (**DD-003**). |
| Business reviewer (target) | Claude (manual / separate repo today) | Human-in-the-loop in `h2n-claude-review`; future automation TBD. |

## §4 Reference pipeline (target)

High-level data flow (aspirational — not all stages automated today):

```text
Claude planner
  -> .ai-loop/task.md
OpenCode + local Qwen (direct llama-server :8081..:8083, or proxy :8090 -> :8081 when needed)
  -> branch / diff
Deterministic guards (pytest, path policy, optional domain scripts)
  -> Codex technical review -> codex_review.md
  -> (target) Claude business review
  -> final test gate -> commit / push (safe paths only)
```

Compare **§0.1** for the pipeline that actually runs in this repo (Cursor-centered).

## §5 Integration contracts (target)

### §5.1 Orchestrator file contract

The PowerShell drivers (`ai_loop_task_first.ps1`, `ai_loop_auto.ps1`, `continue_ai_loop.ps1`) consume and emit the same durable files described in `docs/workflow.md`: `task.md`, `implementer_summary.md`, `codex_review.md`, patches, and test logs. **`.ai-loop/implementer.json`** (not committed by default) stores the last effective implementer wrapper and model for resume.

### §5.2 External CLIs

- **Cursor**: `agent` CLI as implementer in production.
- **Codex**: `codex` CLI as reviewer gate.
- **OpenCode**: non-interactive `opencode run` for Phase 0/1 experiments on the H2N sample project.

### §5.3 OpenCode invocation contract

Target projects carry **`opencode.json`** with one or more providers pointing at local OpenAI-compatible endpoints. The adapter must expose `/v1/chat/completions` with tool schemas so OpenCode can schedule read/edit/bash style tools.

**Phase 1 (current A/B) — direct providers:** The canonical wiring matches the
installer-shipped template `templates/opencode.json`: each Qwen stack is a
separate provider whose `options.baseURL` is **`http://127.0.0.1:8081/v1`**,
**`…8082/v1`**, or **`…8083/v1`** (one port per running `llama-server`). No
proxy is required while every model in use emits native `tool_calls[]` — see
**§0.3**.

**Proxy path (optional):** When a model emits tool invocations as plain text
instead of structured `tool_calls[]`, point the relevant provider at
**`http://127.0.0.1:8090/v1`** and run **`opencode_proxy.py`** (DD-020) so
OpenCode still sees a normalized response. This is the integration path used
for the Phase 0 baseline failure (14B); it remains a **fallback**, not a
mandatory hop for Qwen3-native models.

Minimal expectations:

- Model / provider ID matches the configured GGUF stack and `-CursorModel` passed to the loop.
- `baseURL` is either **`http://127.0.0.1:808x/v1`** (direct) or **`http://127.0.0.1:8090/v1`** (proxy front-end) — never both for the same logical model without a reason documented in the target project.
- Permissions blocks should allow the tool surface required for the canonical task harness (subject to project policy).

Example — **direct** provider (Phase 1 default; same order of ideas as `templates/opencode.json`):

```json
{
  "provider": {
    "local-qwen": {
      "options": {
        "baseURL": "http://127.0.0.1:8081/v1"
      }
    }
  }
}
```

Example — **proxy** provider (when DD-020 normalization is required):

```json
{
  "provider": {
    "local-qwen": {
      "options": {
        "baseURL": "http://127.0.0.1:8090/v1"
      }
    }
  }
}
```

#### Phase 0 reality: llama.cpp proxy

Phase 0 found that `Qwen2.5-Coder-14B-Instruct Q5_K_M` does not emit
structured `tool_calls[]` over the llama.cpp `/v1/chat/completions` endpoint —
it prints a `<tools>` wrapper in the assistant message content, which
OpenCode does not interpret as a tool call. `Qwen3-Coder-30B-A3B Q3_K_M`
emits proper `tool_calls[]` natively when llama.cpp's `--jinja` is enabled
(default).

To keep a single OpenCode contract across both model families and to absorb
future text-format tool emitters, an HTTP proxy sits between OpenCode and
`llama-server`:

```text
OpenCode -> http://127.0.0.1:8090/v1  (opencode_proxy.py)
            -> http://127.0.0.1:8081/v1  (llama-server)
```

Proxy responsibilities:

- Force `stream=False` (OpenCode tolerates non-streaming responses; this
  simplifies tool-call conversion).
- Inspect assistant message content for `<tool_call>`, `<function=name>`,
  or `<tools>` blocks; convert each match into a structured
  `tool_calls[]` entry on the response.
- Pass through unchanged otherwise.

Proxy location (as of 2026-05-12): `C:\AI\scripts\opencode_proxy.py`.
This is outside this repository. Relocation into `scripts/` here is
tracked as Q-10 / DD-020.

When this proxy is in use, the provider in `opencode.json` for that model must
set **`baseURL`** to **`http://127.0.0.1:8090/v1`**. For Phase 1 Qwen3 stacks
that already emit structured `tool_calls[]`, **`baseURL`** should point
**directly** at the matching `llama-server` port (§0.3 / `templates/opencode.json`).

## §6 Deterministic gates (target)

Future / partial today:

- **Tests**: pytest (or project-specific command) as an objective gate before Codex-final commit.
- **Path policy**: forbidden paths, template of safe stage lists (see `SafeAddPaths` in scripts and `docs/safety.md`).
- **Domain scripts** (target): `domain_gate.py`, `diff_guard.py` — *not yet present* in `scripts/` (§0.4).

## §7 Observability and artifacts (target)

Standard artifacts under `.ai-loop/` (diffs, test output, reviews) support both humans and downstream automation. Runtime scratch must not be committed by default (**DD-005**).

## §8 Phased rollout (target)

### §8.1 Phase 0 — OpenCode↔Qwen integration prototype + 3-way model A/B

**Original plan (historical — pre-2026-05-11 run):**

```yaml
phase: P0
intent: Prove OpenCode can drive a real file edit via local llama.cpp on Windows.
deliverables:
  - cuda llama-server operational with candidate GGUFs
  - opencode.json wiring to local OpenAI-compatible endpoint
  - trivial file-creation task automated end-to-end
exit_artifacts:
  - raw timing + VRAM notes per candidate model
  - PASS/FAIL matrix for tool execution vs plain-text tool dumps
acceptance_integration: OpenCode non-interactive run produces committed file change
acceptance_ab_preliminary: baseline + at least one challenger measured
```

**As-run outcome (2026-05-11):**

```yaml
status: COMPLETE (2026-05-11)
outcome_summary: see p0_ab_results.md in target repo

actual_deliverables:
  - llama-server CUDA build confirmed working on Windows 11
  - 2 of 3 candidate GGUFs downloaded and tested (baseline, challenger A)
  - challenger B (Qwen3.6-27B) deferred per VRAM headroom concern
  - opencode.json template in this repo (`templates/opencode.json`) documents
    Phase 1 direct ports :8081/:8082/:8083; optional :8090 proxy path retained
    per DD-020 for text-format tool emitters
  - proxy `opencode_proxy.py` developed at C:\AI\scripts\ (outside repo;
    DD-020)
  - Canonical task ("create qwen_test.txt") run end-to-end:
      baseline: FAIL
      challenger A: PASS, file created at correct path

acceptance_integration: MET (challenger A)
acceptance_ab_preliminary: MET (data captured in p0_ab_results.md)

p1_default_coder: Qwen3-Coder-30B-A3B-Instruct Q3_K_M
p1_integration_stack: see §0.3 above
```

### §8.2 Phase 1 — IN PROGRESS (started 2026-05-13)

Run A/B harness tasks comparing **Cursor** vs **OpenCode+Qwen** on real H2N-sized workloads (**DD-021**) before switching the default implementer.

```yaml
status: IN PROGRESS
started: 2026-05-13
models_under_test:
  run_A: Cursor (baseline)
  run_B: Qwen3-Coder-30B-A3B Q3_K_M  (:8081, -c 131072, MoE)
  run_C: Qwen3.6-27B IQ4_XS          (:8082, -c 32768, dense, q4_0 KV)
  run_D: Qwen3.6-35B-A3B Q4_K_M      (:8083, -c 131072, MoE, --n-cpu-moe)
preliminary_notes:
  - run_D: hit context overflow on first task (partial stash saved); second model run started
  - proxy :8090 not used — all three Qwen3 models emit native tool_calls[]
  - loop activated via: ai_loop_task_first.ps1 -CursorCommand .\scripts\run_opencode_agent.ps1 -CursorModel <provider/id>
```

## §9 Target component map and deferred factory layout (target)

The committed tree today ships the consolidated PowerShell drivers named in **`§5.1`** plus the **`§0`** production path (**`agent`** Cursor → Codex). **This section inlines the full target factory blueprint** (per-stage scripts, Python `orchestrator/` package, prompt/rule trees, `.ai-loop` artifacts, and stage flow) that phased rollout is meant to realize. **§0.4** lists what is still missing in `scripts/` / `src/` today.

Principle (unchanged):

```text
OpenCode + local Qwen  = tool-using coding harness inside the target coding repo
ai-orchestrator        = outer workflow (task contract, tests, safe git, Codex gate)
```

Until Phase 1 evidence satisfies **DD-021**, **Cursor Agent** remains the production implementer for tasks driven from this repository.

Expert review verbatim (findings IDs, MVP debate, critique lists) stays in **`docs/archive/2026-05-11_opencode_harness_expert_review.md`** for traceability — **not** as a substitute for the numbered contracts above and below.

### §9.1 Target layout — `ai-orchestrator` repository

Beyond the consolidated drivers already shipped, the endorsed target adds per-stage wrappers, a packaged Python core, prompts, rules, and config:

```text
ai-orchestrator/
  README.md
  pyproject.toml

  scripts/
    ai_loop_auto.ps1
    ai_loop_context.ps1
    ai_loop_plan_with_claude.ps1
    ai_loop_build_prompt.ps1
    ai_loop_opencode_qwen.ps1
    ai_loop_qwen_review.ps1
    ai_loop_qwen_fix.ps1
    ai_loop_codex_review.ps1
    ai_loop_claude_business_review.ps1
    ai_loop_domain_check.ps1
    ai_loop_finalize.ps1

  src/
    orchestrator/
      __init__.py
      loop_controller.py
      context_builder.py
      prompt_builder.py
      opencode_runner.py
      test_runner.py
      diff_guard.py
      domain_gate.py
      review_router.py
      status_writer.py
      config.py
      paths.py

  prompts/
    claude_task_planner_template.md
    opencode_qwen_coder_template.md
    opencode_qwen_fixer_template.md
    qwen_cheap_review_template.md
    codex_code_review_template.md
    claude_business_review_template.md
    failure_analysis_template.md

  rules/
    global_coding_rules.md
    python_project_rules.md
    h2n_domain_rules.md
    diff_safety_rules.md
    opencode_agent_rules.md
    review_policy.md

  configs/
    h2n_range_extractor.yaml
    agent_models.yaml
    check_commands.yaml

  docs/
    architecture.md
    workflow.md
    opencode_integration.md
    failure_modes.md
```

Naming is indicative: PowerShell may remain consolidated longer than Python; **what matters is duplicated responsibility**, not literal file proliferation on day one.

### §9.2 Target `.ai-loop` artifact bundle inside coding projects

Example target project (`H2N_parser/h2n-range-extractor`); orchestrator emits/consumes the same durable file protocol across stages:

```text
h2n-range-extractor/
  .ai-loop/
    task.md
    agent_brief.md
    domain_risks.md
    context_bundle.md

    opencode_qwen_prompt.md
    opencode_qwen_result.md
    opencode_session_log.md

    qwen_review_prompt.md
    qwen_review.md

    qwen_fix_prompt.md
    qwen_fix_result.md

    codex_review_prompt.md
    codex_review.md

    claude_business_review_prompt.md
    claude_business_review.md

    test_output.txt
    targeted_test_output.txt
    domain_check_report.md

    git_status_before.txt
    git_status_after.txt
    changed_files.txt
    last_diff.patch
    diff_guard_report.md

    final_status.md
    next_implementer_prompt.md
    next_opencode_prompt.md
    failure_report.md
    implementer.json
    loop_state.json
```

The live PowerShell loop keeps a narrower subset (**`task.md`**, **`implementer_summary.md`**, **`codex_review.md`**, diffs/logs per **`docs/workflow.md`**); the table above is the **expanded** symmetric factory target.

### §9.3 Artifact roles (contract summary)

Shared **planning** inputs (from Claude planner in the target design): **`context_bundle.md`** aggregates user ask, git state, diff snippets, tree summary, snippets, failures; **`task.md`** is the structured, model-independent contract (goal, background, acceptance, constraints); **`agent_brief.md`** bridges planners to implementers with practical entry points / risks; **`domain_risks.md`** pins H2N semantic risks so downstream agents honor them.

**OpenCode coder path:** **`opencode_qwen_prompt.md`** built from task + brief + risks + rules; outputs **`opencode_qwen_result.md`** and **`opencode_session_log.md`**.

**Cheap local review / fix loop:** **`qwen_review*.md`** and **`qwen_fix*.md`** gate obvious problems before expensive reviews; fix scope must stay tight (no broad refactors, cap files touched).

**Reviews:** **`codex_review*.md`** targets implementation correctness; **`claude_business_review*.md`** targets domain semantics after Codex (PASS/FAIL formats as in the harness spec).

**Verification:** **`test_output.txt`**, **`targeted_test_output.txt`**, **`domain_check_report.md`** (deterministic, no LLM judgment for core signals).

**Diff safety:** **`git_status_*`**, **`changed_files.txt`**, **`last_diff.patch`**, **`diff_guard_report.md`** (PASS/WARN/BLOCK semantics for too many files, deleted tests, schema drift, etc.).

**Control / resume:** **`implementer.json`** (narrow, shipping today in the PowerShell drivers — runtime, gitignored) stores the effective implementer wrapper and model for `ai_loop_auto.ps1 -Resume`; target **`loop_state.json`** records iteration, last stage, verdict flags, next action; **`final_status.md`**, **`failure_report.md`**, **`next_opencode_prompt.md`**, **`next_implementer_prompt.md`** close or branch the loop.

### §9.4 Target `src/orchestrator/` module responsibilities

| Module | Responsibility |
|--------|----------------|
| `loop_controller.py` | State machine — next stage, max iterations, **`loop_state.json`**, retries vs escalate vs success |
| `context_builder.py` | Build **`context_bundle.md`** — task ask, git/diff/tree, snippets, failures (H2N keyword hooks such as **`color_ranges`**, **`catalog`**, **`school`**) |
| `prompt_builder.py` | Materialize planner/coder/fix/reviewer prompts from templates + task bundles |
| `opencode_runner.py` | Invoke OpenCode CLI/client with WD, provider/model, logs, failure detection (`stream`/`tool` behavior per **`§5.3`**: direct llama-server or proxy when needed) |
| `test_runner.py` | Full + targeted pytest, capture **`test_output*.txt`** |
| `diff_guard.py` | Enforce diff budgets and forbidden edit classes into **`diff_guard_report.md`** |
| `domain_gate.py` | Run deterministic project checks → **`domain_check_report.md`** |
| `review_router.py` | Sequence cheap Qwen vs Codex vs Claude stages; parse verdicts |
| `status_writer.py` | Emit **`final_status.md`**, **`failure_report.md`**, **`next_*_prompt.md`** |
| `config.py` / `paths.py` | Central config + filesystem roots (avoid sprinkled literals) |

### §9.5 Example domain adjuncts (`h2n-range-extractor`)

Goal: deterministic behavior checks that do not rely on LLM verdict alone:

```text
scripts/
  domain_check.py
  validate_color_ranges.py
  validate_output_schema.py
  compare_school_stats.py

tests/
  test_color_ranges.py
  test_school_stats_grouping.py
  test_output_schema.py
```

### §9.6 Target multi-stage workflow (design sequence)

Full factory sequence (endorsed harness design — not fully automated yet):

```text
 1. User describes desired change.
 2. context_builder.py -> .ai-loop/context_bundle.md
 3. Claude planner writes task.md / agent_brief.md / domain_risks.md
 4. prompt_builder.py -> opencode_qwen_prompt.md
 5. opencode_runner.py runs OpenCode + local Qwen (direct endpoint or proxy per §5.3 / DD-020)
        -> repo edits + opencode_qwen_result.md + opencode_session_log.md
 6. Capture git status / changed files / diff snapshots
 7. test_runner.py -> test_output*.txt
 8. domain_gate.py -> domain_check_report.md
 9. diff_guard.py -> diff_guard_report.md
10. Qwen cheap review -> qwen_review.md (optional tightening pass)
11. Optional Qwen-led fix iterations via OpenCode (bounded)
12. Codex correctness review -> codex_review.md
13. Claude business/domain review -> claude_business_review.md
14. On full PASS -> final_status.md
15. On bounded retry -> next_opencode_prompt.md
16. On local model exhaustion -> next_implementer_prompt.md (escalate to Cursor / richer stack)
```

### §9.7 Expert-suggested MVP subset (still target, not today's default)

Minimal artifact footprint to prove the asymmetric factory before widening:

```text
.ai-loop/
  context_bundle.md
  task.md
  agent_brief.md
  opencode_qwen_prompt.md
  test_output.txt
  last_diff.patch
  diff_guard_report.md
  domain_check_report.md
  codex_review.md
  claude_business_review.md
  final_status.md
  failure_report.md
  loop_state.json
```

Supporting code slice:

```text
src/orchestrator/
  context_builder.py
  prompt_builder.py
  opencode_runner.py
  test_runner.py
  diff_guard.py
  loop_controller.py

scripts/
  ai_loop_context.ps1
  ai_loop_build_prompt.ps1
  ai_loop_opencode_qwen.ps1
  ai_loop_auto.ps1
```

First hardened integration milestone in that sketch: **`Claude task → OpenCode/Qwen implements → pytest → diff_guard → Codex → Claude domain review`**.

## §10 Safety and repository hygiene (target)

Operational rules enforced by the drivers today remain non-negotiable for the wider factory:

- **Single loop per repo**: never run two orchestrators against one working tree simultaneously (`docs/safety.md`).
- **Safe staging only**: aligns with **DD-004** — explicit allowlists; never **`git add -A`**. Default literals stay synchronized with **`docs/safety.md`** and script **`SafeAddPaths`**.
- **Runtime artifacts off commits**: scratch prompts, agent transcripts, raw logs, ephemeral dumps unstaged by default (**DD-005**).
- **Publication hygiene**: run the secret scan playbook in **`docs/safety.md`** before publishing.
- **Deterministic escalation triggers** from the harness review — examples the target controller should encode, not bury in prose:

```text
- too many touched files vs configured budget
- test files deleted
- schema / generated-output drift without approval
- patch too large vs qwen/fix budgets
- pytest still failing after max retries / fix attempts
- domain_check regressions after repeated passes elsewhere
```

Illustrative starting thresholds from the harness spec (tune later in config):

```text
max_changed_files_for_qwen = 5
max_patch_lines_for_qwen = 500
max_iterations = 5
max_qwen_fix_attempts = 2
```

Future deterministic gates (**§6**) augment — they do not replace — safe staging and `.gitignore` hygiene.

## §11 References (target / companion docs)

| Document | Role |
|----------|------|
| `docs/workflow.md` | Entrypoints, file protocol, task-first markers for live Cursor + Codex path. |
| `docs/safety.md` | Safe path list, runtime exclusions, execution-policy notes. |
| `docs/decisions.md` | Compact DD index (may lag **`§12`** — this doc wins conflicts). |
| `docs/archive/2026-05-11_qwen_opencode_problem.md` | Phase 0 troubleshooting diary for llama.cpp + OpenCode tool calling (`Things Already Tried`, diagnosis). |
| `docs/archive/2026-05-11_opencode_harness_expert_review.md` | Verbatim harness review (questions §10, critiques, alternative MVPs — **supports §9**, does not replace it). |
| `docs/archive/2026-05-11_architecture_review.md` | External review framing early 18-stage factory assumptions. |

Readers should rely on **`§0`** for ground truth versus **`§1+`** aspiration; **`§9`** holds the inlined deferred-layout contracts; archives preserve narrative provenance beyond what this living doc summarizes.

## §12 Decision Log

Authoritative numbered log for this architecture. Companion index: `docs/decisions.md` (may lag — this section wins — **O04** sync).

### DD-001 — File-based memory instead of chat memory

Agents do not rely on shared chat context. They exchange durable state through `.ai-loop/`.

### DD-002 — Project summary as durable context

`.ai-loop/project_summary.md` stores durable orientation: purpose, decisions, stage, and risks — not a per-task changelog.

### DD-003 — Codex gates commit/push

Codex reviews the implementation against the task. After `VERDICT: PASS`, the orchestrator runs the final test gate, then commit/push (unless `-NoPush`).

### DD-004 — Safe staging only

The orchestrator does not use `git add -A`. Only configured safe paths are staged.

### DD-005 — Runtime artifacts are not committed

Review logs, diffs, test outputs, final status, temp files, input data, and output data are not staged by default.

### DD-006 — Task-first mode skips Codex on Cursor no-op

`ai_loop_task_first.ps1` clears stale `.ai-loop` runtime files (except `task.md`), runs Cursor first, and calls `ai_loop_auto.ps1` only after detecting meaningful git changes or explicit no-code completion per marker rules.

### DD-011 — MaxIterations cap

Decision: Orchestrator entrypoints default `-MaxIterations` to **5**. Beyond 5 iterations the agent is unlikely to converge and cost/time overhead is disproportionate. Override at call time with `-MaxIterations N` for exceptional cases.

Status: resolved (2026-05-14).

### DD-020 — OpenCode↔llama text-tool normalization proxy (optional)

Decision: Maintain a local HTTP proxy (`opencode_proxy.py` on port **8090**)
that can sit between OpenCode and `llama-server` to convert **text-format** tool
calls (`<tool_call>`, `<function=name>`, `<tools>`) into structured
`tool_calls[]` on the wire response. **Phase 1 A/B** uses **direct**
connections from `opencode.json` to `llama-server` ports **8081 / 8082 / 8083**
(see **`templates/opencode.json`**, **§0.3**, **§5.3**) because the Qwen3
candidates emit native `tool_calls[]`; the proxy remains the supported path
for models that do not.

Status: proxy script outside VCS; Phase 1 default wiring does not require it.
Date: 2026-05-11 (clarified 2026-05-13).

Rationale: Phase 0 showed baseline **14B** could not satisfy OpenCode without
normalization; Qwen3 stacks used in Phase 1 do not need the hop. Keeping the
proxy as an **optional** component preserves one integration contract for
future text-format emitters without contradicting direct `baseURL` in
production A/B.

Risk: proxy currently lives outside this repository at
`C:\AI\scripts\opencode_proxy.py`. Workflows that still depend on **8090**
break if that script is lost; direct-port Phase 1 runs are unaffected.
Mitigation: relocate to `scripts/` (Q-10).

### DD-021 — Cursor as transitional implementer through Phase 1

Decision: keep Cursor Agent as the production implementer until OpenCode +
Qwen3-Coder-30B-A3B has demonstrated stable behavior across at least 5
real-world H2N tasks under the **Phase 1 OpenCode wiring** (direct
`llama-server` per **§5.3** / **`templates/opencode.json`**; proxy **DD-020**
only when a chosen model requires normalization). Until then, OpenCode runs
only on Phase-1 A/B comparison tasks against Cursor.

Status: active.
Date: 2026-05-12.

Rationale: P0 PASS was for a trivial single-step file creation task. Real
H2N tasks involve 3-10+ tool calls, file reads, conditional logic. Cursor's
behavior at that scale is known; Qwen3-Coder-30B-A3B's is not.

Risk: prolonged dual-implementer setup creates maintenance burden. Mitigation:
DD-021 is explicitly transitional; A/B data collected in Phase 1 determines
the cutover.

### DD-022 — Optional Qwen scout pre-pass (`-WithScout`)

Decision: `ai_loop_task_first.ps1` accepts an opt-in `-WithScout` switch that runs
`scripts/run_scout_pass.ps1` before the implementer pass. The scout uses the same
implementer wrapper (`-CursorCommand` / `-CursorModel`) with a read-only prompt;
it writes `.ai-loop/_debug/scout.json` with `relevant_files[]` (and optional
`notes`). When that list is non-empty, the implementer prompt gains a
`RELEVANT FILES (from scout):` block after `FILES OUT OF SCOPE:` and before
`TASK:`. Omitting `-WithScout` leaves the C02 prompt prefix unchanged.

Status: active.
Date: 2026-05-14.

Rationale: OpenCode + Qwen benefit from a compressed file hint to bound context
cost; Cursor’s default path keeps frontier-scale context and native discovery, so
scout stays off by default. The flag targets the Qwen path without slowing the
production Cursor loop.

Risk: extra latency when enabled; scout may return empty or invalid JSON (handled
with warnings; run continues). Mitigation: non-fatal failures; scout artifacts
stay under `_debug/` and are not staged.

## §13 Open Questions

### Q-10 — Where should `opencode_proxy.py` live and who owns it?

Currently `C:\AI\scripts\opencode_proxy.py`. Options:

- A: relocate into this repo `scripts/opencode_proxy.py` (preferred — under
  VCS, reviewable, testable).
- B: keep outside repo but add a known-installation check at orchestrator
  startup (poll `http://127.0.0.1:8090/health` before running OpenCode).
- C: extract to a separate dedicated `opencode-llama-proxy` repository.

Pending user decision (see audit Q3). Blocks DD-020 relocation; **8090**-dependent
workflows remain tied to out-of-VCS code until then. Phase 1 **direct** `llama-server`
configs (§0.3, `templates/opencode.json`) do not require the proxy.
