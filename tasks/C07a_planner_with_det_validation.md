# C07a — Planner + deterministic validation (no LLM validator)

**Project:** `ai-orchestrator`
**CWD:** `C:\Users\che\Documents\Projects\ai-orchestrator`
**Risk:** medium — three new files, install contract change. Exceeds ≤80-line policy (flagged in `## Important`).

How to run:
```powershell
# Paste task spec below into .ai-loop\task.md, then:
powershell -ExecutionPolicy Bypass -File .\scripts\ai_loop_task_first.ps1 -NoPush
```

C07a delivers the planner foundation. C07b (separate task) will add the Codex
validator on top by extending `ai_loop_plan.ps1` with `-WithValidator`.

---

# Task: Architect-agnostic task planner with deterministic validation

## Project context

Required reading before starting (in order; stop when you have enough):

1. `AGENTS.md` at repo root — working rules and forbidden paths
2. `.ai-loop/task.md` — this task
3. `.ai-loop/project_summary.md` — durable project orientation
4. `.ai-loop/repo_map.md` — file index
5. `scripts/ai_loop_task_first.ps1` — `$STABLE_PREAMBLE`, repo_map auto-refresh
   pattern (~lines 321-332), and `ConvertTo-CrtSafeArg` definition to mirror
6. `scripts/run_cursor_agent.ps1`, `scripts/run_opencode_agent.ps1`,
   `scripts/run_opencode_scout.ps1` — wrapper convention
7. `scripts/install_into_project.ps1` — installer pattern (target projects have
   no `templates/` dir; prompts land in `.ai-loop/`)
8. `.ai-loop/implementer_summary.md` — only if this is iteration 2+

Do not read by default:

- `docs/archive/`
- `.ai-loop/_debug/`
- `tasks/C07_risks_gpt_validator_review.md` — review notes used only to inform this spec

## Goal

Add a **manual** planner stage that produces `.ai-loop/task.md` from a
natural-language ask, with **deterministic** structural validation. The planner
is architect-agnostic via `-PlannerCommand`, mirroring `-CursorCommand` for
implementers.

C07a delivers planner-only path. No LLM validator in this task.

```
ai_loop_plan.ps1 -PlannerCommand .\scripts\run_claude_planner.ps1 [-StrictFiles]
```

### Deliverables

1. `scripts/ai_loop_plan.ps1` — main entrypoint. Architect-agnostic.
2. `scripts/run_claude_planner.ps1` — Claude planner wrapper.
3. `templates/planner_prompt.md` — planner role + output format.
4. `scripts/install_into_project.ps1` — self-install guard + copy new files.
5. `.gitignore` — ignore planner runtime artifacts.
6. `tests/test_orchestrator_validation.py` — structural + behavior tests.

## Scope

Allowed:
- Create `scripts/ai_loop_plan.ps1`
- Create `scripts/run_claude_planner.ps1`
- Create `templates/planner_prompt.md`
- Edit `scripts/install_into_project.ps1`
- Edit `.gitignore`
- Edit `tests/test_orchestrator_validation.py`
- Edit `.ai-loop/project_summary.md` (Architecture, Stage, Next Steps)

Not allowed:
- Any changes to `scripts/ai_loop_auto.ps1`, `scripts/ai_loop_task_first.ps1`,
  `scripts/continue_ai_loop.ps1`
- Changes to existing wrappers (`run_cursor_agent.ps1`,
  `run_opencode_agent.ps1`, `run_opencode_scout.ps1`, `run_scout_pass.ps1`)
- Edits to `AGENTS.md`, other templates, `src/`, `ai_loop.py`, docs
- Calling `claude` CLI from tests
- Implementing any LLM validator path (C07b)

## Files in scope

- `scripts/ai_loop_plan.ps1` (new)
- `scripts/run_claude_planner.ps1` (new)
- `templates/planner_prompt.md` (new)
- `scripts/install_into_project.ps1`
- `.gitignore`
- `tests/test_orchestrator_validation.py`
- `.ai-loop/project_summary.md`

## Files out of scope

- `scripts/ai_loop_auto.ps1`
- `scripts/ai_loop_task_first.ps1`
- `scripts/continue_ai_loop.ps1`
- `scripts/run_cursor_agent.ps1`
- `scripts/run_opencode_agent.ps1`
- `scripts/run_opencode_scout.ps1`
- `scripts/run_scout_pass.ps1`
- `AGENTS.md`
- `docs/**`
- `docs/archive/**`
- `.ai-loop/_debug/**`
- `ai_loop.py`
- `templates/codex_review_prompt.md` (not reused)
- `templates/validator_prompt.md` (deferred to C07b)

## Required behavior

### scripts/ai_loop_plan.ps1

Parameters:
```powershell
param(
    [string]$Ask = "",
    [string]$AskFile = ".ai-loop\user_ask.md",
    [string]$PlannerCommand = ".\scripts\run_claude_planner.ps1",
    [string]$PlannerModel = "",
    [string]$Out = ".ai-loop\task.md",
    [switch]$AllowIncomplete,
    [switch]$StrictFiles,
    [switch]$Force
)
```

Logic (in order):

1. **Resolve ask:** prefer `-Ask`; else read `$AskFile`; else exit 1 with a
   clear message.

2. **Validate prerequisites:** exit 1 with explicit "missing X" if any of:
   - `AGENTS.md`
   - `.ai-loop/project_summary.md`
   - `.ai-loop/planner_prompt.md`
   - `$PlannerCommand`

3. **Auto-refresh repo_map.md** (mirror `ai_loop_task_first.ps1` ~lines 321-332):
   - If `.ai-loop/repo_map.md` does not exist OR `LastWriteTime` is older than 1 hour:
     run `scripts/build_repo_map.ps1` if present.
   - Failure of `build_repo_map.ps1` is non-fatal; warn and continue.
   - If `.ai-loop/repo_map.md` still does not exist, proceed without it (warn).

4. **Build planner prompt** by concatenating in this exact order:
   - Contents of `.ai-loop/planner_prompt.md`
   - `## AGENTS.md` + contents of `AGENTS.md`
   - `## project_summary.md` + contents of `.ai-loop/project_summary.md`
   - `## repo_map.md` + entire contents of `.ai-loop/repo_map.md` if present
   - `## USER ASK` + resolved ask

5. **Backup existing output:** if `$Out` exists and `-Force` is not set, rename
   it to `$Out.bak` (overwriting any prior `.bak`). Remember whether the
   backup was created.

6. **Wrap steps 7-10 in `try { … } catch { … }`:** on any throw or non-zero
   wrapper exit inside the try, if a backup was created in step 5 and `$Out`
   no longer exists, rename `$Out.bak` back to `$Out` to restore the previous
   state, then rethrow / propagate the exit code.

7. **Invoke planner wrapper** (inside try):
   ```powershell
   $output = $prompt | & $PlannerCommand --workspace $ProjectRoot --model $PlannerModel
   ```
   Capture stdout. Do NOT use `2>&1`. On non-zero `$LASTEXITCODE` from the
   wrapper: throw a clear error (caught above, backup restored, exit 1).

8. **Deterministic validation** — call `Test-TaskValidity` (defined below) on
   `$output`. Returns:
   ```powershell
   @{ Errors = @(<string>...); Warnings = @(<string>...) }
   ```

   On `Errors.Count -gt 0` and not `-AllowIncomplete`:
   - Ensure `.ai-loop/_debug/` exists.
   - Write `$output` to `.ai-loop/_debug/planner_output_invalid.md` (overwrite).
   - Write `.ai-loop/planner_validation.md` with the list of errors/warnings
     (this file is gitignored).
   - Restore backup (via catch by throwing), exit 2.

   On `Warnings.Count -gt 0`: log each warning to console; proceed.

   With `-AllowIncomplete`: print errors as warnings, proceed.

9. **Write output** (inside try): `$output` to `$Out`, UTF-8 no BOM.

10. **Success message:**
    `Wrote $Out. Review before running ai_loop_task_first.ps1.`
    If a backup was created and the write succeeded, print:
    `Previous task.md kept at $Out.bak.`

#### `Test-TaskValidity` checks

Returns `@{ Errors=@(); Warnings=@() }`.

Errors (mandatory):
- Missing any of these literal headings: `# Task:`, `## Goal`, `## Scope`,
  `## Files in scope`, `## Files out of scope`, `## Required behavior`,
  `## Tests`, `## Verification`, `## Implementer summary requirements`,
  `## Important`.
- HTML comment present (`<!--` … `-->`).
- Fenced code wrapping the whole document: leading line is exactly ```` ``` ```` (with optional language tag) AND the last non-empty line is exactly ```` ``` ````.
- `## Files out of scope` body does NOT contain literal substrings
  `docs/archive/`, `.ai-loop/_debug/`, or `ai_loop.py`.

Warnings (default; promoted to Errors only with `-StrictFiles`):
- For each path under `## Files in scope`: if the line is parsed as a path
  (see Path Parsing below), if the path does NOT contain `(new)`, `*`, `?`,
  `**`, and does NOT end with `/`: `Test-Path -LiteralPath` against the path
  resolved relative to `$ProjectRoot`. If missing: emit warning
  `Files in scope: '$path' does not exist (mark with (new) if intentional).`

Path Parsing rules for the `## Files in scope` section:
- Read all bullet lines (lines matching `^\s*[-*]\s+`) under the heading until
  the next `##` heading.
- For each bullet, strip surrounding backticks if present; take the first
  whitespace-delimited token as the candidate path. The remainder of the line
  (after whitespace) is treated as comment/explanation and ignored.
- Skip lines whose first token does not look like a path (no `/` or `.`).
- Normalize `\` to `/` before existence check; pass to `Test-Path` as-is
  (PowerShell handles both separators on Windows).

Exit codes:
- 0: success
- 1: missing prerequisites or wrapper invocation error (backup restored)
- 2: deterministic validation failed (errors, not warnings); backup restored;
  invalid output preserved in `.ai-loop/_debug/planner_output_invalid.md`

Keep `ai_loop_plan.ps1` under 220 lines including the `Test-TaskValidity`
helper.

### scripts/run_claude_planner.ps1

Mirrors `run_opencode_agent.ps1` convention exactly:

- **No `param()` block** (preserves `$input` for stdin).
- Parse `--workspace` and `--model` from `$args`; silently ignore unknown flags.
- Default model: `claude-sonnet-4-6`.
- Read prompt from `$input`. Empty → `Write-Error` + exit 1.
- `Push-Location` to workspace if provided; `Pop-Location` in `finally`.
- Invoke `claude --print --model $model` with prompt piped via stdin.
- **No `2>&1`** — stdout-only is captured by caller.
- `exit $LASTEXITCODE`.

Keep under 50 lines.

### templates/planner_prompt.md

```markdown
# Planner role

You are the PLANNER for the ai-orchestrator file-based workflow. Convert the
USER ASK at the end of this prompt into a fully-formed `.ai-loop/task.md`.

## Hierarchy of authority

- `AGENTS.md` (provided below) — common rules for all agents.
- `CLAUDE.md` (target project, if any) — Claude-specific context; not your concern here.
- This prompt — your role: planner.
- Output `task.md` — concrete contract for the implementer.

## Output format

Produce a markdown document with these headings, in order:

- `# Task: <short name>`
- `## Project context` — required reading list (AGENTS.md, `.ai-loop/task.md`,
  `.ai-loop/project_summary.md`, `.ai-loop/implementer_summary.md` for iter 2+).
- `## Goal` — one paragraph, concrete.
- `## Scope` — `Allowed:` / `Not allowed:` bullet lists.
- `## Files in scope` — concrete relative paths only. Mark new files with
  trailing ` (new)`. Use only paths visible in the provided context. One path
  per bullet; optional short explanation after the path on the same line.
- `## Files out of scope` — must include `docs/archive/**`, `.ai-loop/_debug/**`,
  `ai_loop.py`, plus task-specific exclusions.
- `## Required behavior` — numbered steps.
- `## Tests` — what to add or update; include `python -m pytest -q`.
- `## Verification` — concrete commands.
- `## Implementer summary requirements` — five-point list.
- `## Project summary update` — what durable info to record, or "no update needed".
- `## Output hygiene` — four standard bullets (no task duplication into summary,
  no debug writes, no commit, no archive writes).
- `## Important` — task-specific gotchas. **If the ASK was ambiguous, list the
  concrete assumptions you made here** so the human reviewer can spot them.
  Do not silently choose a "reasonable default" — name it.

## Hard rules

- Output ONLY the task.md content — no preamble, no explanation, no fenced
  code block wrapping the whole document, no HTML comments.
- Do not invent file paths. Use only paths visible in `AGENTS.md`,
  `project_summary.md`, or `repo_map.md`. Marking a path as ` (new)` is allowed
  for files the task creates.
- Keep implementation under ~80 lines of code change. If the ask is larger,
  split into ordered subtasks under `## Important` rather than growing one task.
- Do not ask the user questions. Choose the conservative interpretation of
  ambiguous asks and surface the assumption under `## Important`.
- Validation downstream is mechanical (sections present, no HTML comments, no
  fenced wrap). It does not check business logic. The human reviewer is the
  business-logic gate.
```

### scripts/install_into_project.ps1

1. **Self-install guard** after parameter parsing, before any `New-Item` /
   `Copy-Item`:
   ```powershell
   if ((Resolve-Path $Root).Path -eq (Resolve-Path $TargetProject).Path) {
       Write-Error "install_into_project: source and target are the same directory. Refusing to self-install."
       exit 1
   }
   ```

2. Add `Copy-Item -Force` lines (group with existing similar copies):
   - `scripts/ai_loop_plan.ps1` → target `scripts/`
   - `scripts/run_claude_planner.ps1` → target `scripts/`
   - `templates/planner_prompt.md` → target `.ai-loop/planner_prompt.md`

### .gitignore

Add under a section header `# planner runtime artifacts`:

```
.ai-loop/*.bak
.ai-loop/planner_validation.md
.ai-loop/user_ask.md
```

(`user_ask.md` is gitignored because asks may contain private intent; users
can force-add if they want to track it. Note: `.ai-loop/_debug/` is already
gitignored, which covers `planner_output_invalid.md`.)

## Tests

Run:
```bash
python -m pytest -q
```

Add to `tests/test_orchestrator_validation.py`:

**Structural tests:**

1. `test_ai_loop_plan_script_exists`
2. `test_run_claude_planner_script_exists`
3. `test_planner_prompt_template_exists`
4. `test_planner_scripts_parse_cleanly` — extend existing parse-check list
   with the two new `.ps1` files.
5. `test_ai_loop_plan_declares_required_parameters` — assert `ai_loop_plan.ps1`
   declares `$Ask`, `$AskFile`, `$PlannerCommand`, `$PlannerModel`, `$Out`,
   `$AllowIncomplete`, `$StrictFiles`, `$Force`.
6. `test_run_claude_planner_has_no_param_block` — assert `run_claude_planner.ps1`
   does NOT contain `param(` (wrapper convention).
7. `test_run_claude_planner_uses_claude_print` — assert it contains
   `claude --print` (or `claude -p`) and `--model`.
8. `test_run_claude_planner_no_stderr_redirect` — assert no `2>&1`.
9. `test_planner_prompt_has_required_sections` — `# Planner role`,
   `## Output format`, `## Hard rules`.
10. `test_install_copies_planner_files` — assert `install_into_project.ps1`
    copies the two scripts and one template (template targets `.ai-loop/`).
11. `test_install_has_self_install_guard` — assert `install_into_project.ps1`
    contains the literal "Refusing to self-install".
12. `test_gitignore_excludes_planner_artifacts` — assert `.gitignore`
    contains `.ai-loop/*.bak`, `.ai-loop/planner_validation.md`,
    `.ai-loop/user_ask.md`.
13. `test_ai_loop_plan_restores_backup_on_failure` — read `ai_loop_plan.ps1`;
    assert it contains a `try`/`catch` block AND a code path that renames
    `$Out.bak` back to `$Out` inside `catch` (structural smoke).

**Behavior tests for `Test-TaskValidity`** (run via PowerShell subprocess, no
network):

The implementer must extract `Test-TaskValidity` such that it can be
dot-sourced by a PowerShell harness in tests, OR provide an equivalent
in-script `-RunSelfTest` switch. The tests should:

14. `test_validity_fails_on_missing_section` — feed a task.md missing
    `## Goal`; assert PowerShell exits non-zero AND output mentions "Goal".
15. `test_validity_fails_on_html_comment` — feed a task.md with `<!-- x -->`;
    assert error contains "HTML comment".
16. `test_validity_fails_on_full_fence_wrap` — feed a task.md wrapped in
    ` ```markdown ... ``` `; assert error mentions "fenced".
17. `test_validity_fails_on_missing_required_out_of_scope` — feed a task.md
    where `## Files out of scope` omits `docs/archive/`; assert error
    mentions `docs/archive/`.
18. `test_validity_warns_on_nonexistent_file` — feed a task.md with
    `## Files in scope` containing `src/imaginary.py`; assert default mode
    (no `-StrictFiles`) produces a Warning, not an Error.
19. `test_validity_fails_strict_on_nonexistent_file` — same input with
    `-StrictFiles`; assert Error.
20. `test_validity_skips_new_marked_paths` — `src/foo.py (new)`; assert no
    error/warning for that path.

Do NOT call the `claude` CLI in tests.

## Verification

```bash
python -m pytest -q
```

```powershell
powershell -NoProfile -Command "[void][System.Management.Automation.Language.Parser]::ParseFile('scripts\ai_loop_plan.ps1', [ref]$null, [ref]$null)"
powershell -NoProfile -Command "[void][System.Management.Automation.Language.Parser]::ParseFile('scripts\run_claude_planner.ps1', [ref]$null, [ref]$null)"
```

Self-install guard:
```powershell
.\scripts\install_into_project.ps1 -TargetProject .  # must exit non-zero
```

Manual smoke (requires authenticated `claude` CLI), into a fresh temp dir:
```powershell
$tmp = Join-Path $env:TEMP "ai_orch_smoke_$(Get-Random)"
New-Item -ItemType Directory -Path $tmp | Out-Null
git -C $tmp init | Out-Null
.\scripts\install_into_project.ps1 -TargetProject $tmp
Set-Location $tmp
.\scripts\ai_loop_plan.ps1 -Ask "Add a hello-world smoke test that prints OK" -Out .ai-loop\task_smoke.md
Get-Content .ai-loop\task_smoke.md | Select-Object -First 30
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

- Architecture section: add one line each for `ai_loop_plan.ps1`,
  `run_claude_planner.ps1`, `templates/planner_prompt.md`.
- Note planner is **manual**, NOT part of the automated loop.
- Note planner is architect-agnostic via `-PlannerCommand` (mirrors
  `-CursorCommand`).
- Current Stage: C07a complete; C07b (Codex validator) is the next planned task.
- Next Likely Steps: C07b for semantic validation; alternative planner
  wrappers (GPT, local) as needed.

## Output hygiene

The implementer must not:

- duplicate this task description into `.ai-loop/implementer_summary.md`
- include earlier task narrative in `.ai-loop/project_summary.md`
- write to `.ai-loop/_debug/` or `docs/archive/`
- commit or push (the orchestrator handles git)

## Important

**Spec size:** Exceeds the ≤80-line policy. Allowed as foundational stage.
Suggested implementation order:
1. `templates/planner_prompt.md` first (data, no logic).
2. `scripts/run_claude_planner.ps1` (mirror existing wrapper line-for-line).
3. `scripts/ai_loop_plan.ps1` skeleton: prereq checks, prompt build, wrapper
   invocation, backup/restore via try/catch.
4. `Test-TaskValidity` helper inside `ai_loop_plan.ps1` returning
   `@{ Errors=@(); Warnings=@() }`.
5. Installer + `.gitignore` + structural tests.
6. Behavior tests for `Test-TaskValidity` (use a fixture string approach;
   no API calls).

**Manual stage, not in loop:** `ai_loop_plan.ps1` is invoked **by the user**
before `ai_loop_task_first.ps1`. Do NOT add a call to it from
`ai_loop_task_first.ps1`.

**Architect swappability:** `ai_loop_plan.ps1` MUST NEVER call `claude`
directly — only through `$PlannerCommand`. A future `run_gpt_planner.ps1` or
`run_local_planner.ps1` must drop in without main entrypoint changes.

**Wrapper convention:** `run_claude_planner.ps1` MUST have no `param()` block
(PowerShell pipeline binding would swallow `$input`). Mirror
`run_opencode_agent.ps1` line-for-line.

**Stream separation:** wrapper MUST NOT use `2>&1`. Stdout is captured for
content; stderr must reach the console.

**Backup restore on ANY failure:** after `$Out → $Out.bak`, all failure paths
(wrapper non-zero, exception, deterministic validation Error in non-permissive
mode) must restore the backup so the current `task.md` is never silently lost.
Structurally enforced via `try { … } catch { restore-backup; throw }`.

**File-existence is WARNING by default**, not FAIL. This is intentional:
markdown parsing of `## Files in scope` is fragile, so we err on the side of
not blocking valid plans. Users who want hard failure pass `-StrictFiles`.
Section/comment/fence checks remain Errors because they are robust.

**`.invalid` is hidden:** failed planner output goes to
`.ai-loop/_debug/planner_output_invalid.md`, not to `.ai-loop/`, to avoid the
user mistaking it for the current task.

**repo_map auto-refresh is non-fatal:** if `build_repo_map.ps1` is absent or
fails, planner proceeds with whatever `repo_map.md` exists, or none — with a
warning. Mirror `ai_loop_task_first.ps1` behavior.

**Validation messages must say** "no obvious issues found", not "task is
correct" — even when all checks pass. The human reviewer is still the
business-logic gate.

**Mandatory human review:** planner output is a DRAFT. The user MUST manually
review `.ai-loop/task.md` before running `ai_loop_task_first.ps1`.

**Self-install guard:** `install_into_project.ps1` MUST refuse when
`$Target == $Root`.

**Installer note:** the installer copies the planner prompt to
`.ai-loop/planner_prompt.md`, not to a `templates/` directory in target
projects. `ai_loop_plan.ps1` reads from `.ai-loop/planner_prompt.md`.

**C07b dependency:** the parameter list (`$ValidatorCommand`, `$WithValidator`)
and validator behavior are explicitly OUT of scope here and will be added in
C07b. Do not add stubs.
