# O03 — Actualize docs/architecture.md (current state + target state)

- **Target project:** `ai-git-orchestrator`
- **CWD:** `C:\Users\che\Documents\Projects\ai-git-orchestrator`
- **Invocation:** copy section below `---` into `.ai-loop\task.md`, then run

  ```powershell
  powershell -ExecutionPolicy Bypass -File .\scripts\ai_loop_task_first.ps1 -NoPush
  ```

- **Prerequisites:** O01 + O02 completed.
- **Risk:** medium. This is doc-only but the doc is large (~1215 lines) and
  central. A bad edit produces a confusing architectural source of truth.
- **Estimated lines touched:** ~150 lines edited / restructured (no
  deletions of substantive content — relabeling and adding a new top section).

---

# Task: Restructure docs/architecture.md to separate "Current state" from "Target state" and document the OpenCode proxy reality

## Project context

Before starting, read:

- `.ai-loop/project_summary.md`
- `.ai-loop/task.md`
- `.ai-loop/cursor_summary.md` if it exists
- `AGENTS.md` (created in O02 — required read per its own rules)
- `docs/architecture.md` — the file you will be editing
- `docs/archive/2026-05-11_qwen_opencode_problem.md` — only the §"Things
  Already Tried" and §"Current Diagnosis Hypothesis" sections, for context
- `..\..\H2N_parser\h2n-range-extractor\p0_ab_results.md` — actual P0 results

You do NOT need to read:

- `docs/archive/2026-05-11_architecture_review.md`
- `docs/archive/2026-05-11_opencode_harness_expert_review.md`
- The full `2026-05-11_qwen_opencode_problem.md` outside the two sections
  listed above

## Background (for the implementer)

`docs/architecture.md` currently describes a **target** multi-model
factory (Claude planner → OpenCode + Qwen coder → Codex review → Claude
business review) as if it were the design under active implementation. But:

1. The **actual current workflow** is Cursor (as implementer) + Codex (as
   reviewer) + manual business review in `H2N_parser/h2n-claude-review`.
   Claude is not in the auto loop yet. OpenCode + Qwen has only completed
   Phase 0.

2. **Phase 0 results invalidate part of the original plan:**
   - Baseline `Qwen2.5-Coder-14B-Instruct Q5_K_M` FAILED OpenCode tool calls
     (outputs `<tools>` as plain text, hangs on `tool_choice: required`).
   - Challenger A `Qwen3-Coder-30B-A3B-Instruct Q3_K_M` PASSED with native
     `tool_calls[]` at ~103 tok/s, ~14.5 GB VRAM.
   - A **proxy** `opencode_proxy.py` on port 8090 was added between OpenCode
     and `llama-server` to convert text-format tool calls into structured
     `tool_calls[]` for models that emit `<tool_call>` or `<function=name>`.
   - The proxy currently lives at `C:\AI\scripts\opencode_proxy.py`,
     **outside this repository**. This is a known risk (D01 deferred decision).

3. As a result, `docs/architecture.md` mixes two distinct concerns —
   "what the loop does today" and "what we are building toward" — without
   labeling them. Future agents reading it will be confused about which
   parts are reality and which are aspiration.

## Goal

Restructure `docs/architecture.md` so it has **two clearly separated top
sections** at the very top of the document:

1. **§0 Current state (as of 2026-05-12)** — short, factual description of
   what the loop actually does today.
2. **§1+ Target state** — existing content, mostly preserved, but with
   relabeling so it is clearly aspirational ("Target", "Future") and
   references the proxy as an interim component.

Add new decisions DD-020 (OpenCode proxy interim) and DD-021 (Cursor as
transitional implementer through Phase 1) to the in-file decision log
section (§12). The companion `docs/decisions.md` is updated in O04, not
here.

## Scope

### Allowed

- Edit `docs/architecture.md`:
  - Insert a new "§0 Current state" section at the top, after the YAML
    front-matter / title / TL;DR area (whichever exists first).
  - Add labels to existing sections so it is clear they describe the
    target. Rename "§3 Model Roles" to "§3 Model Roles (target)" if it
    is not already labeled. Do the same for any other section that is
    purely about the target.
  - In "§5.3 OpenCode invocation contract" (or equivalent OpenCode
    section), insert a "Phase 0 reality: llama.cpp proxy" subsection
    documenting the proxy.
  - In "§8 Phase 0" section, update the P0 results subsection to reflect
    actual `p0_ab_results.md` content (baseline failed, challenger_a
    selected as P1 default, proxy required).
  - In "§12 Decision Log" section, add DD-020 and DD-021 entries.
  - In "§13 Open Questions", add Q-10 about proxy ownership / relocation.

### Not allowed

- Do **not** delete any existing substantive content of `docs/architecture.md`.
  This is restructuring, not pruning.
- Do **not** modify `docs/decisions.md`, `docs/workflow.md`, `docs/safety.md`,
  or `README.md` — those are O04.
- Do **not** modify any file in `scripts/`, `tests/`, `templates/`,
  `.ai-loop/`.
- Do **not** create a new `docs/current_state.md` separate file — keep
  everything inside `docs/architecture.md` so there is one source of truth.
- Do **not** move target content out of `docs/architecture.md` into
  `docs/archive/`. The target is still active design.
- Do **not** rewrite the entire architecture from scratch. Preserve voice
  and structure of the existing target sections.

## Files likely to change

- `docs/architecture.md` — single file edit

## Required behavior

### Section 1: insert "§0 Current state (as of 2026-05-12)"

Place this section at the top of the document body, **after** the title and
any YAML front-matter or "Single-Page Summary" subsection (so the summary
remains the absolute top), but **before** the first numbered target section
(currently §1 Vision / §2 / §3).

If a "Single-Page Summary" subsection is at the top, the new §0 goes after
it. If not, §0 is the first numbered section after the title.

Content (adapt phrasing to match the existing document's voice; keep within
~50 lines):

```markdown
## §0 Current state (as of 2026-05-12)

This section describes what the orchestrator actually does today.
Sections §1 onwards describe the target design we are building toward.
Where current state and target diverge, current state is the ground
truth; target is aspirational.

### §0.1 Active workflow

```text
.ai-loop/task.md
  -> Cursor Agent (`agent` CLI) implements
  -> .ai-loop/cursor_summary.md
  -> Save-TestAndDiff (pytest, git diff, git status)
  -> Codex CLI reviews
  -> if PASS: final test gate + git commit + push (unless -NoPush)
  -> if FIX_REQUIRED: extract FIX_PROMPT_FOR_CURSOR, re-run Cursor
  -> cap: MaxIterations (default 10; DD-011 calls for 3 — pending
     separate task)
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
  -> proxy :8090   (C:\AI\scripts\opencode_proxy.py — see DD-020)
       converts <tool_call> / <function=name> text -> tool_calls[]
       forces stream=False
  -> llama-server :8081
       Qwen3-Coder-30B-A3B-Instruct-Q3_K_M.gguf
       -ngl 999 -c 16384 --flash-attn on --cache-type-k q8_0 --cache-type-v q8_0
       --jinja enabled (default; do NOT use --no-jinja)
```

In `opencode.json` in the target project:

```json
"baseURL": "http://127.0.0.1:8090/v1"
```

(Currently the file points at `:8080` for some experiments; see DD-020
on canonical setup.)

### §0.4 Gap between current state and target

- Claude is not in the loop yet (planner / business gate).
- OpenCode + Qwen has completed P0 but is not yet the default
  implementer; Cursor remains the production implementer.
- `domain_gate.py`, `diff_guard.py` from the target design do not exist
  yet in `scripts/`.
- `MaxIterations` is 10 in the scripts; DD-011 says 3. Pending change.
- `opencode_proxy.py` is a critical new component not yet in this repo
  (lives in `C:\AI\scripts\`). See DD-020, Q-10.

The phase plan in §8 is the path from "current state" to "target state".
```

### Section 2: label existing target sections

Find the first existing top-level "##" or "###" section after where you
inserted §0 (likely "§1 Vision" or "§2 Architecture"). If that section is
not already labeled as describing the target, add a single italic line
right under the section header:

```markdown
*This section describes the target design (see §0 for current state).*
```

You only need to do this for the **first** post-§0 section. Subsequent
sections inherit the label by convention.

### Section 3: update "§5.3 OpenCode invocation contract"

Locate the OpenCode invocation contract section (it may be §5.3, §6, or
similar — search for "opencode.json" or "OpenCode" near a code block). Add
a new subsection at the end of that section titled:

```markdown
#### Phase 0 reality: llama.cpp proxy

```

Content (~20 lines):

```markdown
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

`opencode.json` in the target project must set:

```json
"baseURL": "http://127.0.0.1:8090/v1"
```

even when only `Qwen3-Coder-30B-A3B` is in use, so the proxy remains the
single integration point.
```

### Section 4: update "§8 Phase 0" subsection

Locate the §8 Phase 0 subsection ("OpenCode↔Qwen integration prototype +
3-way model A/B"). It currently lists acceptance criteria as aspirational
("acceptance_integration", "acceptance_ab_preliminary"). Replace the
"deliverables" and "exit_artifacts" lists with the actual outcome:

```markdown
status: COMPLETE (2026-05-11)
outcome_summary: see p0_ab_results.md in target repo

actual_deliverables:
  - llama-server CUDA build confirmed working on Windows 11
  - 2 of 3 candidate GGUFs downloaded and tested (baseline, challenger A)
  - challenger B (Qwen3.6-27B) deferred per VRAM headroom concern
  - opencode.json template established (currently points :8080 for
    legacy tests, P1 will pin :8090 once proxy is in repo)
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

Do not delete the original Phase 0 plan content above this — keep it as the
original plan for historical context, then add the "status: COMPLETE" block
at the end of that subsection.

### Section 5: §12 Decision Log additions

Locate the §12 Decision Log section. Add two entries at the appropriate
numeric position (after the last existing DD-XXX entry):

```markdown
### DD-020 — OpenCode proxy as required Phase-0/Phase-1 integration component

Decision: Use a local HTTP proxy (`opencode_proxy.py` on port 8090) between
OpenCode and llama.cpp `llama-server` to convert text-format tool calls
(`<tool_call>`, `<function=name>`, `<tools>`) into structured `tool_calls[]`
responses. The proxy is part of the canonical local stack.

Status: in production for P0 / P1; relocation into VCS pending (see Q-10).
Date: 2026-05-11.

Rationale: Qwen2.5-Coder-14B does not emit structured tool calls; some
future local models may also emit text-format. A single proxy normalizes
the integration contract and absorbs that variance.

Risk: proxy currently lives outside this repository at
`C:\AI\scripts\opencode_proxy.py`. If that machine is rebuilt or the script
is lost, P0/P1 integration breaks. Mitigation: relocate to `scripts/` (Q-10).

### DD-021 — Cursor as transitional implementer through Phase 1

Decision: keep Cursor Agent as the production implementer until OpenCode +
Qwen3-Coder-30B-A3B has demonstrated stable behavior across at least 5
real-world H2N tasks under the canonical proxy stack from DD-020. Until
then, OpenCode runs only on Phase-1 A/B comparison tasks against Cursor.

Status: active.
Date: 2026-05-12.

Rationale: P0 PASS was for a trivial single-step file creation task. Real
H2N tasks involve 3-10+ tool calls, file reads, conditional logic. Cursor's
behavior at that scale is known; Qwen3-Coder-30B-A3B's is not.

Risk: prolonged dual-implementer setup creates maintenance burden. Mitigation:
DD-021 is explicitly transitional; A/B data collected in Phase 1 determines
the cutover.
```

### Section 6: §13 Open Questions

Add at the end of the §13 list:

```markdown
### Q-10 — Where should `opencode_proxy.py` live and who owns it?

Currently `C:\AI\scripts\opencode_proxy.py`. Options:

- A: relocate into this repo `scripts/opencode_proxy.py` (preferred — under
  VCS, reviewable, testable).
- B: keep outside repo but add a known-installation check at orchestrator
  startup (poll `http://127.0.0.1:8090/health` before running OpenCode).
- C: extract to a separate dedicated `opencode-llama-proxy` repository.

Pending user decision (see audit Q3). Blocks DD-020 relocation; until
resolved, P0/P1 integration depends on out-of-VCS code.
```

## Tests

Run:

```powershell
python -m pytest -q
```

Expected: same passing count as before. No new tests required (doc-only
change).

If a test in `tests/test_orchestrator_validation.py` parses or asserts on
`docs/architecture.md` content, expect it to keep working — none of the
existing tests should care about new headings or sections being added.
If one breaks, the test is over-specific and should be loosened to assert
on existence of key sections, not on specific section ordering.

## Verification

1. `docs/architecture.md` exists and is still parseable Markdown
   (`Get-Content -Raw` succeeds).

2. The new §0 section exists:

   ```powershell
   Select-String -Path .\docs\architecture.md -Pattern "^## §0 Current state" |
     Measure-Object | Select-Object -ExpandProperty Count
   ```

   Returns at least 1.

3. The four required §0 subsections exist:

   ```powershell
   Select-String -Path .\docs\architecture.md -Pattern "^### §0\.[1234]" |
     Measure-Object | Select-Object -ExpandProperty Count
   ```

   Returns at least 4.

4. New decisions DD-020 and DD-021 are referenced:

   ```powershell
   Select-String -Path .\docs\architecture.md -Pattern "DD-020|DD-021" |
     Measure-Object | Select-Object -ExpandProperty Count
   ```

   Returns at least 4 (each decision is mentioned in its definition plus at
   least one cross-reference in §0).

5. Q-10 exists:

   ```powershell
   Select-String -Path .\docs\architecture.md -Pattern "^### Q-10" |
     Measure-Object | Select-Object -ExpandProperty Count
   ```

   Returns 1.

6. The proxy is mentioned in the OpenCode contract section:

   ```powershell
   Select-String -Path .\docs\architecture.md -Pattern "opencode_proxy|:8090" |
     Measure-Object | Select-Object -ExpandProperty Count
   ```

   Returns at least 3.

7. `pytest -q` passes.

## Cursor summary requirements

Update `.ai-loop/cursor_summary.md` with:

1. New §0 inserted with subsections §0.1–§0.4.
2. §8 Phase 0 outcome subsection added (status: COMPLETE).
3. §5.3 (or equivalent) OpenCode contract: proxy subsection added.
4. DD-020, DD-021 added to §12.
5. Q-10 added to §13.
6. `pytest -q` result.

Do not include the new section contents in the summary. A short ledger of
what was added is enough.

Target length: 15–20 lines.

## Project summary update

Update `.ai-loop/project_summary.md` with one durable line, e.g. in "Current
stage" or "Important design decisions":

- "`docs/architecture.md` separates current state (§0) from target design
  (§1+); the OpenCode proxy is documented as DD-020."

## Important

- This task changes `docs/architecture.md` only. If you find yourself
  wanting to edit `docs/decisions.md` (to add DD-020 / DD-021 there), do
  NOT do it here — that is O04. The in-file decision log in
  `docs/architecture.md` §12 is authoritative; `docs/decisions.md` is a
  companion summary that will be synchronized in O04.
- Preserve all existing target-state content. Do not delete sections to
  "clean up". Architectural intent stays.
- Use existing voice and structure. The document is dense YAML-ish prose
  in some sections, narrative in others; match what's adjacent.
- Do not commit. The orchestrator handles commit after Codex PASS.
