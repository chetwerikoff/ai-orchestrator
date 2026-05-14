# C02 — Required scope blocks in task template + stable implementer preamble

- **Target project:** `ai-orchestrator`
- **CWD:** `C:\Users\che\Documents\Projects\ai-orchestrator`
- **Invocation:** copy section below `---` into `.ai-loop\task.md`, then run

  ```powershell
  powershell -ExecutionPolicy Bypass -File .\scripts\ai_loop_task_first.ps1 -NoPush
  ```

- **Prerequisites:** C01 (`C01_repo_map_and_agents_policy.md`) merged.
- **Risk:** medium — touches the implementer-prompt construction in `ai_loop_task_first.ps1` and the public `templates/task.md`.
- **Estimated lines touched:** ~40 lines edited, +1 new test.

---

# Task: Require Files-in-scope / Files-out-of-scope blocks in task.md and surface them in the implementer prompt; factor the preamble into a byte-stable constant

## Project context

Required reading before starting (in order; stop when you have enough):

1. `AGENTS.md` — working rules
2. `.ai-loop/task.md` — this task
3. `.ai-loop/project_summary.md`
4. `.ai-loop/repo_map.md` (added by C01)
5. `.ai-loop/implementer_summary.md` — only if iteration ≥ 2

Background: the implementer prompt today (`scripts/ai_loop_task_first.ps1`, function `Invoke-ImplementerImplementation`, ~line 180) is `<preamble> + "TASK:" + <task.md body>`. There is no explicit file-scope contract; `SafeAddPaths` enforces staging but never reaches the model. The context-plan report (§4 step 3, §9 Phase 1, §10) prescribes making `## Files in scope` / `## Files out of scope` required in `templates/task.md` and prepending them above `TASK:` in the implementer prompt. It also prescribes factoring the preamble into a single named constant so it is byte-stable across iterations (free `llama-server` KV-cache reuse).

## Goal

1. Update `templates/task.md` so `## Files in scope` and `## Files out of scope` are required sections (with hard-rules note).
2. Update `.ai-loop/task.md` for **this task** — it already follows the new contract (see "Files in scope" / "Not allowed" below), so this serves as the working example.
3. Modify `Invoke-ImplementerImplementation` in `scripts/ai_loop_task_first.ps1`:
   - Extract the static preamble into a single `$STABLE_PREAMBLE` script-scope constant declared once at the top of the function (or top of the file). Its bytes must not vary across runs for a given orchestrator version.
   - Parse the two scope sections from `.ai-loop/task.md` and inject them as `FILES IN SCOPE:` / `FILES OUT OF SCOPE:` blocks **between** the preamble and `TASK:`.
   - If either section is missing, emit a `Write-Warning` and continue (do not block — the contract is enforced softly so legacy task.md files still run).
4. Add a unit test that verifies the implementer prompt (the file written to `.ai-loop/_debug/implementer_prompt.md`) contains both scope blocks above `TASK:` when present in `task.md`.

## Scope

**Allowed:**
- `scripts/ai_loop_task_first.ps1` — refactor `Invoke-ImplementerImplementation` + add a helper `Get-TaskScopeBlocks`.
- `templates/task.md` — make the two sections required; refresh hard-rules comment.
- `tests/test_orchestrator_validation.py` — one new test.
- `.ai-loop/project_summary.md` — one-line note.

**Not allowed:**
- Do not modify `scripts/ai_loop_auto.ps1` in this task.
- Do not modify `scripts/run_cursor_agent.ps1` or `scripts/run_opencode_agent.ps1`.
- Do not modify `ai_loop.py`.
- Do not change `SafeAddPaths` defaults (already done by C01).
- Do not add the optional Qwen scout (separate task C04).
- Do not modify the Codex review prompt (separate task C03).

## Required behavior

### 1. `templates/task.md` updates

Inside the HARD RULES comment (top), add a line:

```
6. ## Files in scope and ## Files out of scope are REQUIRED sections.
   List concrete relative paths or directory globs. Do not leave them empty
   and do not write "the whole repo".
```

Replace the existing `## Files likely to change` section with `## Files in scope`. Add a new `## Files out of scope` section immediately after it:

```markdown
### Files in scope

Paths the implementer MAY edit. List concrete relative paths or directory globs.

- `src/...`
- `tests/...`

### Files out of scope

Paths the implementer MUST NOT edit (in addition to AGENTS.md "Never edit").

- `docs/archive/**`
- `.ai-loop/_debug/**`
- `ai_loop.py` (unless task explicitly authorizes)
```

### 2. `scripts/ai_loop_task_first.ps1` changes

**Add helper `Get-TaskScopeBlocks`** above `Invoke-ImplementerImplementation`:

```powershell
function Get-TaskScopeBlocks {
    param([string]$TaskFile)
    $text = Get-Content -LiteralPath $TaskFile -Raw -Encoding UTF8
    function _section($name) {
        $pattern = "(?ms)^##\s+$([regex]::Escape($name))\s*$\r?\n(.*?)(?=^##\s+|\z)"
        $m = [regex]::Match($text, $pattern)
        if ($m.Success) { return $m.Groups[1].Value.Trim() }
        return $null
    }
    return [PSCustomObject]@{
        InScope    = _section "Files in scope"
        OutOfScope = _section "Files out of scope"
    }
}
```

**Declare a script-scope constant `$STABLE_PREAMBLE`** at the top of the script (right after `param(...)` and any `Set-StrictMode`/`$ErrorActionPreference`). Move the existing 20-line "You are the IMPLEMENTER…" header verbatim into this constant. Its bytes must be identical across runs.

**Rewrite the prompt assembly** inside `Invoke-ImplementerImplementation`:

```powershell
$scope = Get-TaskScopeBlocks -TaskFile $TaskFile
$taskText = Get-Content -LiteralPath $TaskFile -Raw -Encoding UTF8

$scopeBlock = ""
if ($scope.InScope) {
    $scopeBlock += "FILES IN SCOPE:`n$($scope.InScope)`n`n"
} else {
    Write-Warning "task.md is missing '## Files in scope' section. Continuing without scope contract."
}
if ($scope.OutOfScope) {
    $scopeBlock += "FILES OUT OF SCOPE:`n$($scope.OutOfScope)`n`n"
} else {
    Write-Warning "task.md is missing '## Files out of scope' section. Continuing without scope contract."
}

$prompt = $STABLE_PREAMBLE + "`n`n" + $scopeBlock + "TASK:`n" + $taskText
if (-not [string]::IsNullOrWhiteSpace($ExtraInstructions)) {
    $prompt += "`n`n$($ExtraInstructions.Trim())`n"
}
```

The result written to `.ai-loop/_debug/implementer_prompt.md` must contain the scope blocks **above** `TASK:` when both are present in `task.md`.

### 3. Update `.ai-loop/task.md` for this very task

This task spec already contains `## Files in scope` and `## Files out of scope` (verify them above the "Files likely to change" section). Make sure the running task.md is the spec from this file (after the `---` separator) so the new code path is exercised on the very first run.

### 4. New test in `tests/test_orchestrator_validation.py`

```python
def test_implementer_prompt_surfaces_scope_blocks(tmp_path, monkeypatch) -> None:
    """C02: Files in scope / out of scope from task.md must appear above TASK: in
    the implementer prompt written to .ai-loop/_debug/implementer_prompt.md."""
    # Strategy: invoke Get-TaskScopeBlocks via pwsh on a synthetic task.md, or
    # parse the existing _debug/implementer_prompt.md from this run; pick whichever
    # is more deterministic in the existing test harness.
    ...
```

If a full PowerShell subprocess test is too heavy, accept a regex test against `.ai-loop/_debug/implementer_prompt.md` generated by *this* task's run.

## Tests

```powershell
python -m pytest -q
```

Expected: baseline-after-C01 + 1 new test, no regressions.

PowerShell parser check:

```powershell
powershell -NoProfile -Command "[void][System.Management.Automation.Language.Parser]::ParseFile('scripts\ai_loop_task_first.ps1', [ref]$null, [ref]$null)"
```

## Verification

1. After this task runs, `.ai-loop\_debug\implementer_prompt.md` contains, in order: the `STABLE_PREAMBLE`, then `FILES IN SCOPE:` block, then `FILES OUT OF SCOPE:` block, then `TASK:`.
2. `Select-String -Path templates\task.md -Pattern "^## Files in scope$|^## Files out of scope$"` returns 2 matches.
3. `Select-String -Path scripts\ai_loop_task_first.ps1 -Pattern "STABLE_PREAMBLE|Get-TaskScopeBlocks"` returns ≥3 matches.
4. `python -m pytest -q` shows baseline + 1 new test, no regressions.
5. Re-running the implementer with an unchanged `task.md` produces a byte-identical prompt prefix (capture two consecutive `_debug/implementer_prompt.md` and compare with `fc /b` up to the first dynamic byte — should match through the end of the preamble).

## Implementer summary requirements

Update `.ai-loop/implementer_summary.md` (target <50 lines):

- Changed files.
- Test result (baseline + 1 new test, no regressions).
- Confirmation that `.ai-loop/_debug/implementer_prompt.md` shows the new ordering.
- Remaining risks.

## Project summary update

Add one line under "Current architecture" or "Important design decisions" in `.ai-loop/project_summary.md`:

> Implementer prompt = `$STABLE_PREAMBLE` + `FILES IN SCOPE:` / `FILES OUT OF SCOPE:` blocks parsed from `task.md` + `TASK:` body. Required sections in `templates/task.md`; missing sections produce a warning, not a failure.

## Files in scope

- `scripts/ai_loop_task_first.ps1`
- `templates/task.md`
- `tests/test_orchestrator_validation.py`
- `.ai-loop/project_summary.md`
- `.ai-loop/implementer_summary.md`

## Files out of scope

- `scripts/ai_loop_auto.ps1`
- `scripts/run_cursor_agent.ps1`
- `scripts/run_opencode_agent.ps1`
- `scripts/continue_ai_loop.ps1`
- `scripts/build_repo_map.ps1` (owned by C01)
- `ai_loop.py`
- `docs/archive/**`
- `.ai-loop/_debug/**`
- `.ai-loop/repo_map.md` (do not regenerate as part of this task)

## Important

- Do not commit or push manually.
- Do not change `MaxIterations`, Codex prompt, or scout logic — those are other tasks.
- The `STABLE_PREAMBLE` constant must be byte-identical to the current 20-line header content (only the *placement* changes, not the *wording*).
- If a `Write-Warning` fires on the very first run because legacy `task.md` exists, that is expected — the task spec above defines both sections so the warning should not appear on this task itself.
