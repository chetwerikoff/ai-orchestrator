# C04 — Optional Qwen scout pre-pass behind `-WithScout`

- **Target project:** `ai-orchestrator`
- **CWD:** `C:\Users\che\Documents\Projects\ai-orchestrator`
- **Invocation:** copy section below `---` into `.ai-loop\task.md`, then run

  ```powershell
  powershell -ExecutionPolicy Bypass -File .\scripts\ai_loop_task_first.ps1 -NoPush
  ```

- **Prerequisites:** C01, C02, C03 merged AND at least one real OpenCode/Qwen run on top of C02 has exercised the new prompt path. If no Qwen run has occurred yet, **skip this task** and revisit after Phase 1 OpenCode A/B data is in.
- **Audience:** primarily the **OpenCode/Qwen** implementer path. The default Cursor production path **does not need scout** — Cursor has frontier-class context (200k+) and its own discovery tooling; adding scout there roughly doubles latency for no measurable quality win. The flag is therefore opt-in and defaults to off; C02 prompt ordering remains the baseline for Cursor.
- **Why not also use scout for Cursor?** Cursor handles file discovery with its native tools at low cost. Scout's value comes from compressing the implementer's attention budget — a concern that does not bind on Cursor. You *can* still pass `-WithScout` with Cursor (e.g., on very large H2N target repos to save tokens), but that is an opportunistic use, not the design target.
- **Risk:** higher — adds a new pre-stage. Default behavior must stay unchanged (flag is opt-in); when `-WithScout` is omitted the prompt bytes must match the C02 baseline.
- **Estimated lines touched:** +1 new script (~80 lines), ~30 lines edited in `ai_loop_task_first.ps1`, +1 new test.

---

# Task: Add `-WithScout` flag that runs a Qwen scout pre-pass to extract relevant_files[] into the implementer prompt

## Project context

Required reading before starting (in order; stop when you have enough):

1. `AGENTS.md`
2. `.ai-loop/task.md` — this task
3. `.ai-loop/project_summary.md`
4. `.ai-loop/repo_map.md`
5. `.ai-loop/implementer_summary.md` — only if iteration ≥ 2
6. `docs/architecture.md` §0.3, §9.3 — multi-stage target (read only if useful)

Background: the context-plan report (§9 Phase 3, §10) prescribes an opt-in scout pre-pass for the OpenCode/Qwen path. The scout consumes `task.md` + `repo_map.md` + `AGENTS.md`, emits a small JSON of `relevant_files[]` + notes, and the implementer prompt then includes `RELEVANT FILES:` after the scope blocks. Default behavior (no flag) must remain unchanged: Cursor path stays identical, OpenCode-without-scout stays identical.

## Goal

1. Add `scripts/run_scout_pass.ps1` — a thin wrapper that runs the configured implementer wrapper (or `agent` Cursor by default) with a short scout-only prompt and writes `.ai-loop/_debug/scout.json` (+ `.ai-loop/_debug/scout_prompt.md` for debugging).
2. Add a `-WithScout` switch to `scripts/ai_loop_task_first.ps1`. When set:
   - Run `run_scout_pass.ps1` after the runtime cleanup step but before `Invoke-ImplementerImplementation`.
   - Parse `scout.json`; if valid, pass `relevant_files[]` to `Invoke-ImplementerImplementation` as a new `-RelevantFiles` parameter.
   - On scout failure, emit `Write-Warning` and continue without scout (do not abort the run).
3. Modify `Invoke-ImplementerImplementation` so when `-RelevantFiles` is non-empty, the prompt includes a `RELEVANT FILES:` block immediately after `FILES OUT OF SCOPE:` and before `TASK:`.
4. Document the flag in `docs/workflow.md` (one short paragraph) and add `DD-022` to `docs/architecture.md` §12 + `docs/decisions.md`.
5. Add one test asserting that omitting `-WithScout` produces a prompt **without** `RELEVANT FILES:`.

## Scope

**Allowed:**
- `scripts/run_scout_pass.ps1` — new file.
- `scripts/ai_loop_task_first.ps1` — add `-WithScout` switch + glue.
- `docs/workflow.md` — one paragraph.
- `docs/architecture.md` — add DD-022 entry under §12.
- `docs/decisions.md` — add DD-022 entry.
- `tests/test_orchestrator_validation.py` — one new test.
- `.ai-loop/project_summary.md` — one-line note.

**Not allowed:**
- Do not change default behavior of `ai_loop_task_first.ps1` (`-WithScout` is opt-in).
- Do not modify `scripts/ai_loop_auto.ps1`.
- Do not modify `scripts/continue_ai_loop.ps1` (resume does not need scout state in this iteration; `implementer.json` does not store scout config).
- Do not add scout output to `SafeAddPaths` (scout artifacts stay under `.ai-loop/_debug/`, gitignored).
- Do not add any embedding/vector logic.
- Do not edit `ai_loop.py`.

## Files likely to change

- `scripts/run_scout_pass.ps1` (new, ~80 lines)
- `scripts/ai_loop_task_first.ps1` (~30 lines)
- `docs/workflow.md` (~10 lines)
- `docs/architecture.md` (~20 lines, new DD-022)
- `docs/decisions.md` (~5 lines)
- `tests/test_orchestrator_validation.py` (~20 lines, 1 new test)
- `.ai-loop/project_summary.md` (1 line)

## Required behavior

### 1. `scripts/run_scout_pass.ps1`

Inputs:
- `-ProjectRoot <path>` — required.
- `-CommandName <path>` — implementer wrapper to invoke (same convention as `Invoke-ImplementerImplementation`). Default: `.\scripts\run_cursor_agent.ps1`.
- `-Model <string>` — optional, forwarded as `--model`.

Behavior:
- Composes a short scout prompt (cap ~30 lines):

  ```
  You are the SCOUT in a local AI development loop.

  Job:
  - Read .ai-loop/task.md, .ai-loop/repo_map.md, AGENTS.md.
  - Identify the smallest set of files relevant to the task.
  - Do NOT edit any file.
  - Do NOT call any non-read tool.

  Output ONLY a single fenced JSON block, no prose:

  ```json
  {
    "relevant_files": ["src/foo.py", "tests/test_foo.py"],
    "notes": "one-line summary of why these files"
  }
  ```
  ```

- Writes the prompt to `.ai-loop/_debug/scout_prompt.md` (UTF-8, no BOM).
- Invokes the implementer wrapper with `--print --trust --workspace $ProjectRoot` and `--model $Model` if non-empty. Captures stdout to `.ai-loop/_debug/scout_output.txt`.
- Extracts the first ```` ```json … ``` ```` block from the output, parses it with `ConvertFrom-Json`, and writes the parsed object back as `.ai-loop/_debug/scout.json` (canonical UTF-8).
- On any failure (no JSON block, parse error, scout exit non-zero), emits `Write-Warning` and exits with code 0 (non-fatal); does **not** create `scout.json`.

### 2. `-WithScout` switch in `ai_loop_task_first.ps1`

- Add `[switch]$WithScout` to the `param(...)` block.
- After the runtime cleanup step and before `Invoke-ImplementerImplementation`:

  ```powershell
  $relevantFiles = @()
  if ($WithScout) {
      $scoutScript = Join-Path $PSScriptRoot "run_scout_pass.ps1"
      if (Test-Path -LiteralPath $scoutScript) {
          & powershell -NoProfile -ExecutionPolicy Bypass -File $scoutScript `
              -ProjectRoot $ProjectRoot `
              -CommandName $CursorCommand `
              -Model $CursorModel
          $scoutJson = Join-Path $ProjectRoot ".ai-loop\_debug\scout.json"
          if (Test-Path -LiteralPath $scoutJson) {
              try {
                  $obj = Get-Content $scoutJson -Raw | ConvertFrom-Json -ErrorAction Stop
                  $relevantFiles = @($obj.relevant_files)
              } catch {
                  Write-Warning "Scout JSON parse failed: $($_.Exception.Message). Continuing without scout."
              }
          } else {
              Write-Warning "Scout did not produce scout.json. Continuing without scout."
          }
      }
  }
  ```

- Pass `$relevantFiles` to `Invoke-ImplementerImplementation` as a new optional parameter `-RelevantFiles`. Default empty array — no behavior change when omitted.

### 3. `Invoke-ImplementerImplementation` change

- Add parameter `[string[]]$RelevantFiles = @()`.
- When non-empty, insert a block in the prompt **after** the `FILES OUT OF SCOPE:` block and **before** `TASK:`:

  ```
  RELEVANT FILES (from scout):
  - src/foo.py
  - tests/test_foo.py

  ```

- Ordering rule: `STABLE_PREAMBLE` (C02) → `FILES IN SCOPE:` (C02) → `FILES OUT OF SCOPE:` (C02) → `RELEVANT FILES:` (C04, only if non-empty) → `TASK:`.

### 4. Documentation

- `docs/workflow.md`: append a short paragraph under an existing section (e.g., near "Start a new task"):

  > **Optional scout pre-pass:** pass `-WithScout` to `ai_loop_task_first.ps1` to run a read-only scout that writes `.ai-loop/_debug/scout.json` (`relevant_files[]` + `notes`). The implementer prompt then includes a `RELEVANT FILES:` block. Scout output is gitignored. Failures are non-fatal — the loop continues without scout context.

- `docs/architecture.md` §12: add `DD-022 — Optional Qwen scout pre-pass` entry. Status: active. Rationale: bounds context cost for the OpenCode/Qwen path without affecting the Cursor default.
- `docs/decisions.md`: add a one-line DD-022 entry pointing to architecture.md §12.

### 5. Test

```python
def test_implementer_prompt_omits_relevant_files_when_scout_off() -> None:
    """C04: default run (no -WithScout) must not produce a 'RELEVANT FILES:' block
    in .ai-loop/_debug/implementer_prompt.md."""
    debug = _REPO_ROOT / ".ai-loop" / "_debug" / "implementer_prompt.md"
    if debug.is_file():
        text = debug.read_text(encoding="utf-8")
        assert "RELEVANT FILES" not in text
```

A positive-path test (with `-WithScout`) requires a working OpenCode/Cursor invocation and is out of scope for this unit-test layer; verify it manually via the verification steps below.

## Tests

```powershell
python -m pytest -q
```

Expected: baseline-after-C03 + 1 new test, no regressions.

PowerShell parser checks:

```powershell
powershell -NoProfile -Command "[void][System.Management.Automation.Language.Parser]::ParseFile('scripts\ai_loop_task_first.ps1', [ref]$null, [ref]$null)"
powershell -NoProfile -Command "[void][System.Management.Automation.Language.Parser]::ParseFile('scripts\run_scout_pass.ps1', [ref]$null, [ref]$null)"
```

## Verification

1. `Test-Path .\scripts\run_scout_pass.ps1` returns `True`.
2. `Select-String -Path scripts\ai_loop_task_first.ps1 -Pattern "WithScout|run_scout_pass\.ps1|RelevantFiles"` returns ≥3 matches.
3. Running `ai_loop_task_first.ps1 -NoPush` **without** `-WithScout` produces an `.ai-loop\_debug\implementer_prompt.md` that does **not** contain the string `RELEVANT FILES`.
4. Manual smoke (post-merge, not gating verification): running with `-WithScout -CursorCommand .\scripts\run_opencode_agent.ps1 -CursorModel local-qwen/qwen3-coder-30b-a3b` produces `.ai-loop\_debug\scout.json` and a prompt containing `RELEVANT FILES:`.
5. `python -m pytest -q` shows baseline + 1 new test, no regressions.

## Implementer summary requirements

Update `.ai-loop/implementer_summary.md` (target <50 lines):

- Changed files.
- Test result (baseline + 1 new test, no regressions).
- Confirmation that default behavior is unchanged (no `RELEVANT FILES` in default prompt).
- Remaining risks (especially: scout failure modes — empty JSON, slow models, prompt-size on `repo_map.md`).

## Project summary update

Add one line under "Current architecture" or "Important design decisions" in `.ai-loop/project_summary.md`:

> Optional `-WithScout` flag (DD-022) runs `scripts/run_scout_pass.ps1` before the implementer pass and prepends `RELEVANT FILES:` to the prompt. Off by default; failures are non-fatal.

## Files in scope

- `scripts/run_scout_pass.ps1`
- `scripts/ai_loop_task_first.ps1`
- `docs/workflow.md`
- `docs/architecture.md`
- `docs/decisions.md`
- `tests/test_orchestrator_validation.py`
- `.ai-loop/project_summary.md`
- `.ai-loop/implementer_summary.md`

## Files out of scope

- `scripts/ai_loop_auto.ps1`
- `scripts/continue_ai_loop.ps1`
- `scripts/run_cursor_agent.ps1`
- `scripts/run_opencode_agent.ps1`
- `scripts/build_repo_map.ps1`
- `templates/**`
- `ai_loop.py`
- `docs/archive/**`
- `.ai-loop/repo_map.md`
- `.ai-loop/_debug/**` (read-only for verification; scout writes to it at runtime)

## Important

- Do not commit or push manually.
- `-WithScout` must remain **opt-in**. The default code path through `ai_loop_task_first.ps1` must produce a byte-identical prompt prefix to the C02 baseline when the flag is omitted.
- Do not add scout output to `SafeAddPaths`. Do not commit `.ai-loop/_debug/scout*` files.
- Do not introduce a new top-level directory.
- Do not add embedding/vector logic.
