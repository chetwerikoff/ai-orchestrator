# C08 — Preflight scope check in ai_loop_task_first.ps1

**Project:** `ai-orchestrator`
**CWD:** `C:\Users\che\Documents\Projects\ai-orchestrator`
**Prerequisite:** C07 merged (optional — preflight works on any `task.md`, planner-generated or hand-written; but C07 documents the spec in `## Important` referencing C08).
**Risk:** low — single function added to one entrypoint, behind a default-on flag that can be disabled.

How to run:
```powershell
# Paste task spec below into .ai-loop\task.md, then:
powershell -ExecutionPolicy Bypass -File .\scripts\ai_loop_task_first.ps1 -NoPush
```

---

# Task: Preflight scope check — refuse to start the loop on invented paths

## Project context

Required reading before starting (in order; stop when you have enough):

1. `AGENTS.md` at repo root
2. `.ai-loop/task.md` — this task
3. `.ai-loop/project_summary.md`
4. `.ai-loop/repo_map.md`
5. `scripts/ai_loop_task_first.ps1` — file to extend. Look at the existing
   `Get-TaskScopeBlocks` / `$STABLE_PREAMBLE` parsing for the
   `## Files in scope` / `## Files out of scope` sections (already implemented
   for the implementer-prompt assembly). Reuse that helper if possible.
6. `tests/test_orchestrator_validation.py` — test patterns to mirror
7. `tasks/C07_claude_task_planner.md` — context for why this exists (planner
   can produce invented paths; this preflight catches them before the loop)
8. `.ai-loop/implementer_summary.md` — only if iteration 2+

Do not read by default:
- `docs/archive/`
- `.ai-loop/_debug/`

## Goal

Add a preflight gate to `scripts/ai_loop_task_first.ps1` that parses
`## Files in scope` in `.ai-loop/task.md` and refuses to start the implementer
pass when any path:

- does NOT exist in the working tree, AND
- is NOT marked with the trailing ` (new)` suffix, AND
- does NOT look like a glob/directory (`*`, `?`, `**`, ends with `/`)

When the check fails, the script prints each invented path with a clear
remediation message and exits non-zero **without invoking the implementer**.

The check is **on by default**. A new `-SkipScopeCheck` switch lets the user
opt out (for hand-crafted task.md cases where parsing fails or the user
intentionally references something not yet on disk).

This catches:
- Planner-invented paths (the main risk from C07)
- Manual typos in hand-written task.md
- Stale references after file moves

It does NOT catch: wrong scope semantics, weak tests, business-logic errors.

## Scope

Allowed:
- Edit `scripts/ai_loop_task_first.ps1` (add preflight function + invocation)
- Edit `tests/test_orchestrator_validation.py` (add tests)
- Edit `.ai-loop/project_summary.md` (Architecture / Stage / Next Steps)

Not allowed:
- Any changes to `scripts/ai_loop_auto.ps1`,
  `scripts/continue_ai_loop.ps1`, any wrapper script, any template,
  `scripts/install_into_project.ps1`, `AGENTS.md`, `src/`, `ai_loop.py`,
  `docs/`
- Changes to `scripts/ai_loop_plan.ps1` (it is a separate manual stage)
- Adding any LLM-based check; this is deterministic only
- Touching `## Files out of scope` parsing — only `## Files in scope`

## Files in scope

- `scripts/ai_loop_task_first.ps1`
- `tests/test_orchestrator_validation.py`
- `.ai-loop/project_summary.md`

## Files out of scope

- `scripts/ai_loop_auto.ps1`
- `scripts/ai_loop_plan.ps1`
- `scripts/continue_ai_loop.ps1`
- `scripts/run_*.ps1` (all wrappers)
- `scripts/install_into_project.ps1`
- `templates/**`
- `AGENTS.md`
- `docs/**`
- `docs/archive/**`
- `.ai-loop/_debug/**`
- `ai_loop.py`

## Required behavior

### scripts/ai_loop_task_first.ps1

1. **Add `[switch]$SkipScopeCheck`** to the `param()` block. Default off
   means preflight runs unless user opts out.

2. **Add a helper function** `Test-TaskFilesInScopeExist` (or equivalent
   name following project convention):

   - Input: path to `task.md` and project root.
   - Output: a result object with two array properties — `Invented`
     (list of paths that failed the check) and `Checked` (count of paths
     considered).
   - Logic:
     ```powershell
     function Test-TaskFilesInScopeExist {
         param([string]$TaskPath, [string]$ProjectRoot)
         $text = Get-Content -LiteralPath $TaskPath -Raw -ErrorAction Stop
         # Find "## Files in scope" heading body until next "## " heading.
         $m = [regex]::Match($text, '(?ms)^##\s+Files in scope\s*$(.*?)(?=^##\s+|\z)')
         if (-not $m.Success) { return @{ Invented = @(); Checked = 0; SectionFound = $false } }
         $body = $m.Groups[1].Value
         $invented = New-Object System.Collections.Generic.List[string]
         $checked = 0
         foreach ($line in ($body -split "`r?`n")) {
             if ($line -notmatch '^\s*[-*]\s+') { continue }
             $bullet = $line -replace '^\s*[-*]\s+', ''
             # Strip surrounding backticks on the first token.
             $bullet = $bullet -replace '^`([^`]+)`', '$1'
             # First whitespace-delimited token is the candidate path.
             $token = ($bullet -split '\s+', 2)[0]
             if ([string]::IsNullOrWhiteSpace($token)) { continue }
             # Skip globs / directory-ish entries.
             if ($token -match '[\*\?]' -or $token.EndsWith('/') -or $token.EndsWith('\')) { continue }
             # Skip if marked (new) as a TRAILING marker on the line.
             # Trailing-only avoids bypasses where '(new)' appears inside a
             # description like 'existing.ps1 keep old behavior; add (new) mode'.
             if ($bullet -match '\s+\(new\)\s*$') { continue }
             $checked++
             # Normalize separators; Test-Path handles both on Windows but be explicit.
             $resolved = Join-Path $ProjectRoot ($token -replace '\\', '/')
             if (-not (Test-Path -LiteralPath $resolved)) {
                 $invented.Add($token)
             }
         }
         return @{ Invented = @($invented); Checked = $checked; SectionFound = $true }
     }
     ```

3. **Invoke the check** in `ai_loop_task_first.ps1` after the existing
   prerequisite assertions (and after the repo_map auto-refresh block) but
   **before** the implementer pass:

   ```powershell
   if (-not $SkipScopeCheck) {
       $scopeResult = Test-TaskFilesInScopeExist -TaskPath $TaskPath -ProjectRoot $ProjectRoot
       if (-not $scopeResult.SectionFound) {
           Write-Warning "Preflight: '## Files in scope' section not found in $TaskPath. Skipping path-existence check."
       }
       elseif ($scopeResult.Invented.Count -gt 0) {
           Write-Host ""
           Write-Host "PREFLIGHT FAILED: invented or missing paths in ## Files in scope:" -ForegroundColor Red
           foreach ($p in $scopeResult.Invented) {
               Write-Host "  - $p" -ForegroundColor Red
           }
           Write-Host ""
           Write-Host "Fix: either correct the path in $TaskPath, mark it with trailing ' (new)' if intentional," -ForegroundColor Yellow
           Write-Host "     or re-run with -SkipScopeCheck to bypass this check."
           exit 1
       }
       else {
           Write-Host "Preflight: $($scopeResult.Checked) path(s) in scope all exist or marked (new)." -ForegroundColor Green
       }
   }
   ```

   The check must run BEFORE the implementer is invoked. It must NOT run
   in the resume / auto path (only in task-first mode), so place it inside
   the task-first entrypoint, not in `ai_loop_auto.ps1`.

4. **Console banner placement:** the success line ("Preflight: N path(s) ...")
   goes BEFORE the existing "STEP 1: $step1Label IMPLEMENTATION" banner so
   the user sees preflight result first.

5. **Dot-source guard for testability.** `ai_loop_task_first.ps1` is an
   executable script: its main flow runs at the bottom. Tests that need to
   call `Test-TaskFilesInScopeExist` in isolation cannot simply dot-source
   the file — doing so would execute the entire task-first flow (repo_map
   refresh, prerequisite checks, implementer pass, auto-loop chain) and
   pollute test state.

   Add the guard **after all function definitions** and **before the main
   task-first flow** (the line that begins with `Assert-FileExists` /
   `Write-Section "STEP 1..."` / the first non-function executable
   statement in the existing script — whichever comes first). PowerShell
   sets `$MyInvocation.InvocationName` to `.` when the script is
   dot-sourced.

   **Wrong placement** (guard above function definitions): dot-sourced
   tests would `return` before functions are defined and would not see
   `Test-TaskFilesInScopeExist`.

   **Correct skeleton:**

   ```powershell
   param(...)
   $ErrorActionPreference = "Stop"

   function Save-ImplementerStateAt { ... }
   function Invoke-AutoReviewLoop { ... }
   function Test-TaskFilesInScopeExist { ... }
   # ... all other helpers ...

   # Dot-source guard: when invoked as `. .\scripts\ai_loop_task_first.ps1`,
   # load helper definitions only — do not execute the main flow.
   if ($MyInvocation.InvocationName -eq '.') { return }

   # MAIN FLOW BELOW
   $ProjectRoot = (Resolve-Path ".").Path
   Assert-FileExists -Path $AutoLoopScript -Message "..."
   # ...
   ```

   This keeps the main behavior unchanged for normal invocation and makes
   helper functions cleanly callable from a test harness.

Keep the helper function under 40 lines. Total addition to
`ai_loop_task_first.ps1` should be under 75 lines including param, helper,
invocation, and the dot-source guard.

## Tests

Run:
```bash
python -m pytest -q
```

Add to `tests/test_orchestrator_validation.py` (use the existing
PowerShell-via-subprocess pattern used for parser checks; helper-function
tests can dot-source the script into a temp harness):

1. `test_ai_loop_task_first_declares_skip_scope_check` — read
   `ai_loop_task_first.ps1`; assert it contains `[switch]$SkipScopeCheck`.
2. `test_ai_loop_task_first_has_files_in_scope_helper` — assert it contains
   the helper function definition (`function Test-TaskFilesInScopeExist`
   or matching name from the implementation).
3. `test_ai_loop_task_first_invokes_preflight_before_step1` — read the
   script body; assert the `SkipScopeCheck` invocation block appears
   **before** the literal `STEP 1: ` in the file (textual order check).
**Test isolation requirement (critical).** `-SkipInitialCursor` skips only
the implementer pass; the script still proceeds to `Invoke-AutoReviewLoop`,
which would invoke `codex` and exercise the full auto loop. Behavior tests
must isolate to the preflight stage only by passing **both** of:

- `-SkipInitialCursor` (skip implementer)
- `-AutoLoopScript <fakeAutoLoop>` (replace the auto-loop script with a fake
  that just `exit 0`)

Create the fake script in the test fixture, e.g.:
```python
fake_autoloop = tmp_path / "fake_auto_loop.ps1"
fake_autoloop.write_text("exit 0\n", encoding="utf-8")
# pass to subprocess as: -AutoLoopScript $fake_autoloop
```

Without this isolation tests could call real `codex` or interact with git
state — making them flaky and slow. Treat the AutoLoopScript override as
mandatory for any test that runs `ai_loop_task_first.ps1` end-to-end.

4. `test_preflight_fails_on_invented_path` — write a temp task.md with
   `## Files in scope` containing `nonexistent/path.py` (no `(new)`); run
   the script via PowerShell subprocess in a temp project; assert exit
   code is non-zero AND stdout contains the invented path. **Use
   `-SkipInitialCursor -AutoLoopScript <fake>`.**
5. `test_preflight_passes_when_paths_exist` — same harness; task.md
   references real files from the temp project; assert exit code 0 and
   "Preflight:" success line in output. **Use `-SkipInitialCursor
   -AutoLoopScript <fake>`.**
6. `test_preflight_skips_paths_marked_new` — same harness; task.md
   references `not_yet_there.py (new)` as a TRAILING marker; assert
   preflight passes without error.
7. `test_preflight_blocks_when_new_is_not_trailing` — task.md contains
   `existing.ps1 keep old behavior with (new) mode` — `(new)` is NOT
   trailing, so the path must still be subject to the existence check;
   assert preflight enforces existence normally.
8. `test_preflight_skips_globs_and_dirs` — `src/**`, `tests/test_*.py`,
   `docs/`; assert preflight passes (these are not checked for existence).
9. `test_preflight_warns_on_missing_section` — task.md lacks
   `## Files in scope`; assert preflight emits a warning (not an error)
   and continues.

Use real `Test-Path` against a temp directory created in `tmp_path` (pytest
fixture) for the behavior tests. Do NOT call any LLM CLI.

## Verification

```bash
python -m pytest -q
```

```powershell
powershell -NoProfile -Command "[void][System.Management.Automation.Language.Parser]::ParseFile('scripts\ai_loop_task_first.ps1', [ref]$null, [ref]$null)"
```

Manual smoke (no LLM required — uses `-SkipInitialCursor`):
```powershell
$tmp = Join-Path $env:TEMP "preflight_smoke_$(Get-Random)"
New-Item -ItemType Directory -Path $tmp | Out-Null
git -C $tmp init | Out-Null
.\scripts\install_into_project.ps1 -TargetProject $tmp
Set-Location $tmp

# Invented path → should fail with preflight error
@"
# Task: Test
## Goal
test
## Scope
Allowed: -
Not allowed: -
## Files in scope
- nonexistent_file.py
## Files out of scope
- docs/archive/**
- .ai-loop/_debug/**
- ai_loop.py
## Required behavior
1. -
## Tests
pytest
## Verification
pytest
## Implementer summary requirements
1. - 2. - 3. - 4. - 5. -
## Important
test
"@ | Set-Content .ai-loop\task.md
.\scripts\ai_loop_task_first.ps1 -SkipInitialCursor -NoPush
# Expect non-zero exit, "PREFLIGHT FAILED: invented or missing paths" in output

# Same task.md with -SkipScopeCheck → should bypass preflight
.\scripts\ai_loop_task_first.ps1 -SkipInitialCursor -NoPush -SkipScopeCheck
# Expect preflight skipped (continues past preflight)

Set-Location -; Remove-Item -Recurse -Force $tmp
```

## Implementer summary requirements

Update `.ai-loop/implementer_summary.md` with:

1. Changed files.
2. Test result (count only).
3. What was implemented (3–5 lines).
4. What was skipped and why.
5. Remaining risks.

## Project summary update

Update `.ai-loop/project_summary.md`:

- Architecture section: add one line about the preflight check in
  `ai_loop_task_first.ps1` — refuses to start when `## Files in scope`
  contains invented paths.
- Note: `-SkipScopeCheck` switch bypasses; default is ON.
- Note: this complements C07's structural sanity check in the planner with a
  deterministic gate at the launch point, catching invented paths regardless
  of how `task.md` was produced.
- Update Current Stage and Next Likely Steps.

## Output hygiene

The implementer must not:

- duplicate this task description into `.ai-loop/implementer_summary.md`
- include earlier task narrative in `.ai-loop/project_summary.md`
- write to `.ai-loop/_debug/` or `docs/archive/`
- commit or push (the orchestrator handles git)

## Important

**Default-on with opt-out:** the preflight is enabled by default. Users who
hit a parsing edge case (markdown weirdness, intentional reference to a path
not yet on disk that is NOT marked `(new)`) can bypass with
`-SkipScopeCheck`. Do NOT make this default-off — the whole point is to
catch errors before they waste an implementer pass.

**Post-merge action (reinstall in target projects):** target projects use
their own installed copy of `scripts/ai_loop_task_first.ps1`. After C08
merges in this repo, the preflight check is **not** automatically active in
target projects. Each target project must run:

```powershell
# from this orchestrator repo
.\scripts\install_into_project.ps1 -TargetProject <path-to-target>
```

to pick up the updated `ai_loop_task_first.ps1`. The implementer of C08
should mention this in the project-summary `Next Likely Steps` so the next
session knows to reinstall before relying on preflight in target projects.

To verify after reinstall:
```powershell
rg -n "SkipScopeCheck|Test-TaskFilesInScopeExist" <target>\scripts\ai_loop_task_first.ps1
```

**Task-first only, not auto/resume:** the check belongs in
`ai_loop_task_first.ps1` only. `ai_loop_auto.ps1` (review/fix existing
changes) and `continue_ai_loop.ps1` (resume) operate on already-modified
trees where `## Files in scope` paths may now exist (because implementer
just created them) — running the check there would be a false negative
generator. Keep the check in the task-first entrypoint only.

**Markdown parsing is best-effort:** if `## Files in scope` is missing
entirely, emit a warning and continue (do not block). If the section exists
but the body is malformed, the parser will simply skip lines it does not
recognize — net effect is "fewer paths checked", which is safer than
failing on every weird input. Do not over-engineer the parser.

**Path normalization:** convert `\` to `/` before `Test-Path` to handle
Windows-style paths the user may have typed. PowerShell `Test-Path` accepts
both, but explicit normalization avoids edge cases.

**Glob/directory detection:** entries containing `*`, `?`, or ending with
`/` or `\` are skipped. They are not checked for existence — they represent
patterns, not literal paths.

**`(new)` marker (trailing only):** only a **trailing** ` (new)` marker
(regex `\s+\(new\)\s*$`) skips the existence check. Mid-line occurrences
(e.g. `scripts/existing.ps1 add support for (new) mode`) do NOT bypass —
this prevents accidental skip via descriptive text. The Required behavior
code block and this Important note must use the same regex pattern.

**Console messages:** use `Write-Host -ForegroundColor Red` for failures and
`Green` for success — mirrors the existing color convention in
`ai_loop_task_first.ps1`.

**No LLM:** this check is deterministic by design. No `claude`, `codex`, or
any other model is invoked. The check is fast (millisecond-scale) and runs
on every task-first invocation.

**Test harness for behavior tests:** the existing test file has examples
of running `ai_loop_task_first.ps1` in a temp project via subprocess. Mirror
that pattern. Use `-SkipInitialCursor` so the implementer is not invoked
in tests — we only verify preflight behavior. If there is no existing
`-SkipInitialCursor`-style test, reuse the parser-check subprocess pattern
and limit assertions to exit code + stdout content.
