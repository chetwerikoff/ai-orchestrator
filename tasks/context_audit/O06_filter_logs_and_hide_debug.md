# O06 — Add log filtering (test_failures_summary, diff_summary) and hide debug artefacts under .ai-loop/_debug/

- **Target project:** `ai-git-orchestrator`
- **CWD:** `C:\Users\che\Documents\Projects\ai-git-orchestrator`
- **Invocation:** copy section below `---` into `.ai-loop\task.md`, then run

  ```powershell
  powershell -ExecutionPolicy Bypass -File .\scripts\ai_loop_task_first.ps1 -NoPush
  ```

- **Prerequisites:** O01..O05 completed. In particular, O05 already added
  conditional references to `test_failures_summary.md` and `diff_summary.txt`
  in `templates/codex_review_prompt.md`.
- **Risk:** medium. This is the first task in the queue that changes
  PowerShell script behavior. Existing 23 orchestrator-validation tests
  must keep passing, possibly with adjustments.
- **Estimated lines touched:** ~80 lines in `scripts/ai_loop_auto.ps1`,
  ~30 lines in `scripts/ai_loop_task_first.ps1`, ~20 lines new helper in
  `scripts/` (Python or PowerShell, see below), small tests/.gitignore
  updates.

---

# Task: Add filtered test failures + diff stat artefacts, and move raw agent stdout artefacts under .ai-loop/_debug/

## Project context

Before starting, read:

- `.ai-loop/task.md` (this task)
- `.ai-loop/project_summary.md`
- `AGENTS.md` at repo root
- `.ai-loop/cursor_summary.md` (if iteration ≥ 2)
- `scripts/ai_loop_auto.ps1` — the file you will edit most
- `scripts/ai_loop_task_first.ps1` — secondary edit
- `tests/test_orchestrator_validation.py` — to understand which behaviors
  are locked by tests
- `templates/codex_review_prompt.md` (already updated by O05) — confirms
  the artefacts this task creates are already referenced as "(if present)"

## Background

The audit found two raw-artefact problems:

1. **Test output filtering:** `python -m pytest -q` produces only a dot-line
   on pass (which is fine — already a form of filtering) and a thin failure
   list. But the **traceback / assertion content** is not preserved when
   running `-q`. The Codex reviewer needs structured failure context on
   FAIL, not just "5 failed, 260 passed". Currently `ai_loop_auto.ps1`
   pipes `test_output.txt` raw to Codex. We need to add a deterministic
   filtered summary when pytest fails.

2. **Debug artefact pollution:** `cursor_agent_output.txt`,
   `cursor_implementation_output.txt`, `cursor_implementation_prompt.md`,
   and `cursor_implementation_result.md` are raw stdout / scratch from
   agent invocations. They sit at the top level of `.ai-loop/` and clutter
   that namespace. Codex review template (post-O05) no longer references
   them. They are useful for human debugging but should not be loaded by
   any agent.

This task adds the filtered artefacts and hides the raw ones in
`.ai-loop/_debug/`.

## Goal

After this task:

- `ai_loop_auto.ps1` writes `diff_summary.txt` (always) and
  `test_failures_summary.md` (only when pytest fails) into `.ai-loop/`.
- `cursor_agent_output.txt`, `cursor_implementation_output.txt`,
  `cursor_implementation_prompt.md` are written into `.ai-loop/_debug/`
  instead of `.ai-loop/`.
- `cursor_implementation_result.md` stays at `.ai-loop/` root because it
  is part of the gated implementation contract (the
  `IMPLEMENTATION_STATUS: DONE_NO_CODE_CHANGES_REQUIRED` marker file).
  Hiding it would break `Test-CursorResultAllowsNoCodeChanges`.
- `Clear-AiLoopRuntimeState` cleans up the new paths correctly.
- `.gitignore` covers `.ai-loop/_debug/`.
- Orchestrator-validation tests adjusted to assert the new paths.

## Scope

### Allowed

- Edit `scripts/ai_loop_auto.ps1`:
  - In `Save-TestAndDiff`: add `git diff --stat` output to
    `.ai-loop/diff_summary.txt`.
  - In `Save-TestAndDiff`: after pytest, if exit code is non-zero, invoke
    a deterministic Python or PowerShell helper to write
    `.ai-loop/test_failures_summary.md`. Keep the helper inline as a
    here-string Python `-c "..."` invocation OR add a separate
    `scripts/filter_pytest_failures.py` (preferred — testable).
  - In `Run-CursorFix`: redirect raw output from `*> .ai-loop/cursor_agent_output.txt`
    to `*> .ai-loop/_debug/cursor_agent_output.txt`. Ensure the `_debug`
    directory exists (`New-Item -ItemType Directory -Force`).
  - In `Clear-AiLoopRuntimeState`: update the file list to remove
    `.ai-loop/cursor_agent_output.txt`,
    `.ai-loop/cursor_implementation_output.txt`,
    `.ai-loop/cursor_implementation_prompt.md` and add their `_debug/`
    counterparts. Also include `.ai-loop/test_failures_summary.md` and
    `.ai-loop/diff_summary.txt` in the cleanup list.

- Edit `scripts/ai_loop_task_first.ps1`:
  - In `Clear-AiLoopRuntimeState`: same update as in `ai_loop_auto.ps1`
    above.
  - In `Invoke-CursorImplementation`: redirect raw output from
    `*> $outputPath` (currently `.ai-loop/cursor_implementation_output.txt`)
    to `.ai-loop/_debug/cursor_implementation_output.txt`. Also move
    `cursor_implementation_prompt.md` save target to
    `.ai-loop/_debug/cursor_implementation_prompt.md`.
  - **Do NOT move** `cursor_implementation_result.md` — it stays at
    `.ai-loop/` root.

- Add new file `scripts/filter_pytest_failures.py` (if going the helper
  route — preferred):
  - Takes `--input <pytest_output.txt> --output <summary.md>` flags.
  - Reads pytest -q output.
  - Extracts the FAILED lines and any traceback lines (lines after a
    `FAILED ...::test_name` until next blank line or next `FAILED` /
    test summary).
  - Writes a structured `.md` file: a `## Failed: N / M` header, then per
    failure a `### tests/path.py::test_name` block with the captured
    traceback indented.
  - Deterministic (no LLM, no network).
  - Exit code 0 always (it's diagnostic).

- Add new file `tests/test_filter_pytest_failures.py` if you went the
  helper route, with at least one input/output fixture.

- Edit `.gitignore`:
  - Add `.ai-loop/_debug/` line (the directory should not be committed).
  - Add `.ai-loop/test_failures_summary.md` and `.ai-loop/diff_summary.txt`
    if `.ai-loop/*.md` is not already covered (likely it is via
    existing rules; verify before adding).

- Edit `tests/test_orchestrator_validation.py`:
  - Adjust any assertions that grep for `cursor_agent_output.txt` /
    `cursor_implementation_*` paths to match the new `_debug/` paths.
  - Add one new test: `ai_loop_auto.ps1` writes `diff_summary.txt`
    (presence check via grep for the literal in the script).
  - Add one new test: `ai_loop_auto.ps1` invokes
    `filter_pytest_failures.py` (or equivalent inline Python) on test
    failure (grep for `filter_pytest_failures` literal in script).

### Not allowed

- Do **not** change `Get-ImplementationDeltaPaths` or
  `Test-CursorResultAllowsNoCodeChanges` logic. They still consider
  `.ai-loop/cursor_implementation_result.md` (which stays at root).
- Do **not** move `codex_review.md`, `next_cursor_prompt.md`,
  `final_status.md`, `last_diff.patch`, `test_output.txt`,
  `git_status.txt`, `test_output_before_commit.txt`, or `post_fix_output.txt`
  into `_debug/`. Those are not raw stdout dumps; they are part of the
  agent file contract.
- Do **not** change the `MaxIterations` default (still 10 — DD-011 is a
  separate task).
- Do **not** modify `templates/` (O05 already updated them).
- Do **not** modify `docs/` (O03/O04 already updated them).
- Do **not** introduce streaming, async, or background process behavior.
  All filtering must be synchronous after pytest finishes.

## Files likely to change

- `scripts/ai_loop_auto.ps1`
- `scripts/ai_loop_task_first.ps1`
- `scripts/filter_pytest_failures.py` (new)
- `tests/test_orchestrator_validation.py` (adjusted + 2 new tests)
- `tests/test_filter_pytest_failures.py` (new)
- `.gitignore` (one new pattern)
- `.ai-loop/_debug/` (new directory, gitignored)

## Required behavior

### Part 1: `Save-TestAndDiff` — diff_summary.txt + test_failures_summary.md

Current implementation in `ai_loop_auto.ps1` (around line 138):

```powershell
function Save-TestAndDiff {
    Ensure-AiLoopFiles

    Write-Host "Running tests..."
    Invoke-CommandToFile $TestCommand (Join-Path $AiLoop "test_output.txt") | Out-Null
    $testExit = $LASTEXITCODE

    Write-Host "Saving git status and diff..."
    git status --short > (Join-Path $AiLoop "git_status.txt")

    Add-IntentToAddForReview
    git diff > (Join-Path $AiLoop "last_diff.patch")

    return $testExit
}
```

New behavior:

```powershell
function Save-TestAndDiff {
    Ensure-AiLoopFiles

    Write-Host "Running tests..."
    Invoke-CommandToFile $TestCommand (Join-Path $AiLoop "test_output.txt") | Out-Null
    $testExit = $LASTEXITCODE

    Write-Host "Saving git status and diff..."
    git status --short > (Join-Path $AiLoop "git_status.txt")

    Add-IntentToAddForReview
    git diff > (Join-Path $AiLoop "last_diff.patch")
    git diff --stat > (Join-Path $AiLoop "diff_summary.txt")

    if ($testExit -ne 0) {
        Write-Host "Tests failed; generating filtered failures summary..."
        $filterScript = Join-Path $ProjectRoot "scripts\filter_pytest_failures.py"
        if (Test-Path $filterScript) {
            python $filterScript `
                --input  (Join-Path $AiLoop "test_output.txt") `
                --output (Join-Path $AiLoop "test_failures_summary.md")
        }
        # If filter script is missing, skip silently — test_output.txt remains
        # available for the reviewer as fallback.
    }

    return $testExit
}
```

### Part 2: `scripts/filter_pytest_failures.py`

Create a small (~80 line) Python script:

```python
"""Filter pytest -q output into a structured failures summary.

Deterministic: reads stdin/file, writes Markdown. No network, no LLM.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


FAILED_LINE_RE = re.compile(r"^FAILED\s+([^\s]+)")


def parse_failures(text: str) -> list[dict]:
    """Return list of {'name': str, 'traceback': list[str]}."""
    failures: list[dict] = []
    lines = text.splitlines()
    i = 0
    while i < len(lines):
        m = FAILED_LINE_RE.match(lines[i])
        if m:
            name = m.group(1)
            trace: list[str] = []
            j = i + 1
            while j < len(lines):
                ln = lines[j]
                if FAILED_LINE_RE.match(ln):
                    break
                if ln.strip().startswith(("passed", "failed", "skipped")) and "=" in ln:
                    break
                trace.append(ln)
                j += 1
            failures.append({"name": name, "traceback": trace})
            i = j
        else:
            i += 1
    return failures


def parse_summary_line(text: str) -> str:
    """Return last non-empty line that looks like pytest summary."""
    for line in reversed(text.splitlines()):
        if "passed" in line or "failed" in line or "error" in line:
            return line.strip()
    return ""


def render(failures: list[dict], summary_line: str) -> str:
    parts = [f"# Test failures summary", ""]
    parts.append(f"## Summary line")
    parts.append("")
    parts.append("```")
    parts.append(summary_line or "(no summary line found)")
    parts.append("```")
    parts.append("")
    parts.append(f"## Failed: {len(failures)}")
    parts.append("")
    for f in failures:
        parts.append(f"### {f['name']}")
        parts.append("")
        parts.append("```")
        # Drop trailing blank lines
        trace = f["traceback"]
        while trace and not trace[-1].strip():
            trace.pop()
        parts.extend(trace if trace else ["(no traceback captured)"])
        parts.append("```")
        parts.append("")
    return "\n".join(parts).rstrip() + "\n"


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--input", required=True)
    p.add_argument("--output", required=True)
    args = p.parse_args()
    text = Path(args.input).read_text(encoding="utf-8", errors="replace")
    failures = parse_failures(text)
    summary_line = parse_summary_line(text)
    Path(args.output).write_text(render(failures, summary_line), encoding="utf-8")
    return 0


if __name__ == "__main__":
    sys.exit(main())
```

Key properties:

- Pure stdlib, no third-party imports.
- Deterministic.
- Tolerates UTF-8 decode errors with `errors="replace"` (pytest emits
  mixed encodings on Windows occasionally).
- Always exits 0; missing failures are not an error.

### Part 3: `tests/test_filter_pytest_failures.py`

```python
from pathlib import Path
import subprocess
import sys


REPO = Path(__file__).resolve().parents[1]
SCRIPT = REPO / "scripts" / "filter_pytest_failures.py"


def test_filter_handles_no_failures(tmp_path: Path) -> None:
    src = tmp_path / "in.txt"
    src.write_text("262 passed, 3 skipped in 63.81s\n", encoding="utf-8")
    out = tmp_path / "out.md"
    result = subprocess.run(
        [sys.executable, str(SCRIPT), "--input", str(src), "--output", str(out)],
        check=True,
        capture_output=True,
        text=True,
    )
    assert out.exists()
    body = out.read_text(encoding="utf-8")
    assert "Failed: 0" in body
    assert "262 passed, 3 skipped" in body


def test_filter_extracts_one_failure(tmp_path: Path) -> None:
    src = tmp_path / "in.txt"
    src.write_text(
        "\n".join(
            [
                "FAILED tests/test_foo.py::test_bar - assert 1 == 2",
                "  E   assert 1 == 2",
                "  E   +  where 1 = some_fn()",
                "",
                "1 failed, 261 passed in 5.0s",
            ]
        )
        + "\n",
        encoding="utf-8",
    )
    out = tmp_path / "out.md"
    subprocess.run(
        [sys.executable, str(SCRIPT), "--input", str(src), "--output", str(out)],
        check=True,
    )
    body = out.read_text(encoding="utf-8")
    assert "Failed: 1" in body
    assert "tests/test_foo.py::test_bar" in body
    assert "assert 1 == 2" in body
```

### Part 4: Move raw stdout artefacts to `.ai-loop/_debug/`

In `scripts/ai_loop_auto.ps1`, `Run-CursorFix` function. Current:

```powershell
$cursorArgs = @("--print", "--trust", "--workspace", $ProjectRoot, (ConvertTo-CrtSafeArg -Value $cursorPrompt))
& agent @cursorArgs *> (Join-Path $AiLoop "cursor_agent_output.txt")
```

New:

```powershell
$debugDir = Join-Path $AiLoop "_debug"
New-Item -ItemType Directory -Force -Path $debugDir | Out-Null
$cursorArgs = @("--print", "--trust", "--workspace", $ProjectRoot, (ConvertTo-CrtSafeArg -Value $cursorPrompt))
& agent @cursorArgs *> (Join-Path $debugDir "cursor_agent_output.txt")
```

In `scripts/ai_loop_task_first.ps1`, `Invoke-CursorImplementation` function:

```powershell
$promptPath = Join-Path $AiLoop "cursor_implementation_prompt.md"
$outputPath = Join-Path $AiLoop "cursor_implementation_output.txt"
```

Becomes:

```powershell
$debugDir = Join-Path $AiLoop "_debug"
New-Item -ItemType Directory -Force -Path $debugDir | Out-Null
$promptPath = Join-Path $debugDir "cursor_implementation_prompt.md"
$outputPath = Join-Path $debugDir "cursor_implementation_output.txt"
```

The `cursor_implementation_result.md` path stays unchanged:

```powershell
$resultFull = Join-Path $ProjectRoot ".ai-loop\cursor_implementation_result.md"
```

### Part 5: `Clear-AiLoopRuntimeState`

Both `ai_loop_auto.ps1` and `ai_loop_task_first.ps1` have a copy of this
function. Update both to match. The new file list:

```powershell
$files = @(
    ".ai-loop/codex_review.md",
    ".ai-loop/next_cursor_prompt.md",
    ".ai-loop/test_output.txt",
    ".ai-loop/test_output_before_commit.txt",
    ".ai-loop/test_failures_summary.md",
    ".ai-loop/last_diff.patch",
    ".ai-loop/diff_summary.txt",
    ".ai-loop/final_status.md",
    ".ai-loop/git_status.txt",
    ".ai-loop/post_fix_output.txt",
    ".ai-loop/claude_final_review.md",
    ".ai-loop/cursor_implementation_result.md",
    ".ai-loop/_debug/cursor_agent_output.txt",
    ".ai-loop/_debug/cursor_implementation_prompt.md",
    ".ai-loop/_debug/cursor_implementation_output.txt"
)
```

Keep the existing conditional that skips `cursor_implementation_result.md`
when `$env:AI_LOOP_CHAIN_FROM_TASK_FIRST -eq "1"`.

Both copies of `Clear-AiLoopRuntimeState` must be byte-identical except
where intentionally different (the chain handoff condition).

### Part 6: `.gitignore`

Add at end of `.gitignore`:

```
# Debug artefacts (raw agent stdout, prompts)
.ai-loop/_debug/

# Filtered review artefacts (regenerated each iteration)
.ai-loop/test_failures_summary.md
.ai-loop/diff_summary.txt
```

If existing `.gitignore` already covers `.ai-loop/*.md` or similar broad
patterns, the new individual rules are redundant but harmless. Verify
first; add only what is missing.

### Part 7: `tests/test_orchestrator_validation.py`

Find any test that asserts on the literal `cursor_agent_output.txt` or
`cursor_implementation_output.txt` and update the expected path. If a test
greps for `.ai-loop/cursor_agent_output.txt` in `ai_loop_auto.ps1`, the
new expectation is `.ai-loop\_debug\cursor_agent_output.txt` or
`_debug\cursor_agent_output.txt` depending on how the script writes the
path.

Add two new tests:

```python
def test_ai_loop_auto_writes_diff_summary():
    script = Path("scripts/ai_loop_auto.ps1").read_text(encoding="utf-8")
    assert "diff_summary.txt" in script
    assert "git diff --stat" in script


def test_ai_loop_auto_invokes_pytest_failure_filter():
    script = Path("scripts/ai_loop_auto.ps1").read_text(encoding="utf-8")
    assert "filter_pytest_failures.py" in script
```

Add a third test for the `_debug` directory convention:

```python
def test_cursor_agent_output_goes_to_debug_dir():
    script = Path("scripts/ai_loop_auto.ps1").read_text(encoding="utf-8")
    # Old location must not be present
    assert ".ai-loop/cursor_agent_output.txt" not in script
    assert ".ai-loop\\cursor_agent_output.txt" not in script
    # New location must be present
    assert "_debug" in script and "cursor_agent_output.txt" in script
```

Adjust path normalization (forward vs back slashes) to match how
PowerShell composes paths in the actual script — use the path-handling
helper if one exists, otherwise inspect the script for literal style.

## Tests

Run:

```powershell
python -m pytest -q
```

Expected:

- All 23 existing orchestrator-validation tests pass (after path
  adjustments).
- 2 new tests for filter_pytest_failures pass.
- 3 new tests in test_orchestrator_validation.py pass.
- Total around 28 passing tests.

If the count diverges significantly, investigate before adjusting target.

## Verification

1. `diff_summary.txt` and `test_failures_summary.md` references exist in
   `ai_loop_auto.ps1`:

   ```powershell
   Select-String -Path .\scripts\ai_loop_auto.ps1 -Pattern "diff_summary\.txt|test_failures_summary\.md" |
     Measure-Object | Select-Object -ExpandProperty Count
   ```

   Returns at least 4 (2 file mentions × at least 2 contexts each).

2. `filter_pytest_failures.py` exists and is referenced:

   ```powershell
   Test-Path .\scripts\filter_pytest_failures.py
   Select-String -Path .\scripts\ai_loop_auto.ps1 -Pattern "filter_pytest_failures\.py" |
     Measure-Object | Select-Object -ExpandProperty Count
   ```

   First returns `True`, second returns at least 1.

3. Old debug paths absent from scripts (except in
   `Clear-AiLoopRuntimeState` lists, which keep them for backward
   cleanup):

   ```powershell
   Select-String -Path .\scripts\ai_loop_auto.ps1 -Pattern '\.ai-loop[/\\]cursor_agent_output\.txt"' |
     Measure-Object | Select-Object -ExpandProperty Count
   ```

   Returns 0 outside the cleanup arrays. (The cleanup array correctly
   targets the new `_debug/` paths.)

4. `Clear-AiLoopRuntimeState` lists in both scripts are byte-identical
   (excepting the chain-handoff condition):

   ```powershell
   $a = (Get-Content .\scripts\ai_loop_auto.ps1 -Raw) -match 'Clear-AiLoopRuntimeState'
   $b = (Get-Content .\scripts\ai_loop_task_first.ps1 -Raw) -match 'Clear-AiLoopRuntimeState'
   $a -and $b
   ```

   Manual diff of both function bodies should show identical file arrays.

5. `.gitignore` covers `.ai-loop/_debug/`:

   ```powershell
   Select-String -Path .\.gitignore -Pattern "_debug" |
     Measure-Object | Select-Object -ExpandProperty Count
   ```

   Returns at least 1.

6. `pytest -q` passes with the expected new test count.

7. (Manual) Simulate the failure path: artificially break a test, run
   `ai_loop_auto.ps1` (or just `Save-TestAndDiff` interactively),
   confirm `test_failures_summary.md` appears with structured content.
   Not required by automated verification, but recommended once.

## Cursor summary requirements

Update `.ai-loop/cursor_summary.md` with:

1. `Save-TestAndDiff` now emits `diff_summary.txt` always and
   `test_failures_summary.md` on test failure.
2. `filter_pytest_failures.py` added (line count, with 2 tests).
3. Raw stdout artefacts moved to `.ai-loop/_debug/` in both scripts.
4. `Clear-AiLoopRuntimeState` updated in both scripts (byte-identical
   beyond chain-handoff condition).
5. `.gitignore` updated.
6. `tests/test_orchestrator_validation.py`: N existing tests adjusted,
   3 new tests added.
7. `pytest -q` result.

Target length: 20–30 lines (this task touches more files than previous
ones).

## Project summary update

Update `.ai-loop/project_summary.md` durable changes:

- Under "Current architecture" or "Important design decisions":
  "Test failure context for Codex review is provided by
  `filter_pytest_failures.py` (deterministic, no LLM) writing
  `.ai-loop/test_failures_summary.md`."
- Under same section:
  "Raw agent stdout / scratch lives in `.ai-loop/_debug/` (gitignored).
  Reviewer agents must not read that directory."

Total update: 2–3 lines.

## Important

- This is the first task in the queue that changes script behavior. After
  this task, the loop runs differently. Verify by running one trivial task
  end-to-end (your choice — even running this task itself through Cursor
  exercises most of the new code).
- The PowerShell `*>` redirection captures all streams (stdout + stderr +
  warning + verbose + debug + information). Keep it; do not switch to
  `>` (stdout-only) — the agent CLIs occasionally write errors to stderr
  and we want full capture in `_debug/`.
- The two copies of `Clear-AiLoopRuntimeState` are intentionally
  duplicated (DD per project_summary.md: "no shared module"). When you
  update one, update the other.
- Do not commit. The orchestrator handles commit after Codex PASS.
- If `python` is not in `PATH` for the orchestrator run, the
  `filter_pytest_failures.py` invocation will silently fail; we catch
  this with `if (Test-Path $filterScript)` only, not with `Get-Command
  python`. That's acceptable for now — the failure mode is "Codex reads
  raw test_output.txt as fallback". Flag in cursor_summary risks.
