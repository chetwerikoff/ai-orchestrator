# C07 — Minimal task planner (architect-agnostic, no LLM validator)

**Project:** `ai-orchestrator`
**CWD:** `C:\Users\che\Documents\Projects\ai-orchestrator`
**Risk:** low-medium — three new files, install contract change, tightly scoped to planner only.

How to run:
```powershell
# Paste task spec below into .ai-loop\task.md, then:
powershell -ExecutionPolicy Bypass -File .\scripts\ai_loop_task_first.ps1 -NoPush
```

C07 is intentionally minimal: planner + backup hygiene only. No LLM validator,
no file-existence parsing, no `-AllowIncomplete`/`-StrictFiles` flags. A
future task can add a validator wrapper if practice shows the planner produces
problematic output regularly.

---

# Task: Architect-agnostic task planner

## Project context

Required reading before starting (in order; stop when you have enough):

1. `AGENTS.md` at repo root — working rules and forbidden paths
2. `.ai-loop/task.md` — this task
3. `.ai-loop/project_summary.md` — durable project orientation
4. `.ai-loop/repo_map.md` — file index
5. `scripts/ai_loop_task_first.ps1` — `$STABLE_PREAMBLE` style + `ConvertTo-CrtSafeArg` precedent
6. `scripts/run_cursor_agent.ps1`, `scripts/run_opencode_agent.ps1` — wrapper convention (no `param()`, no `2>&1`)
7. `scripts/install_into_project.ps1` — installer pattern (target prompts land in `.ai-loop/`)
8. `.ai-loop/implementer_summary.md` — only if iteration 2+

Do not read by default:

- `docs/archive/`
- `.ai-loop/_debug/`
- `tasks/C07_risks_gpt_validator_review.md`, `tasks/C07a_C07b_critical_risks_review.md` —
  external review notes used only to inform this spec; not orientation material

## Goal

Add a **manual, opt-in** planner stage that converts a natural-language ASK
into `.ai-loop/task.md`. Architect-agnostic via wrapper pattern (mirrors
`-CursorCommand` for implementers).

```
ai_loop_plan.ps1 -Ask "..." [-PlannerCommand .\scripts\run_claude_planner.ps1] [-Force]
```

The planner is invoked **manually by the user** before
`ai_loop_task_first.ps1`. Not part of any automated loop. Human review of
`.ai-loop/task.md` remains the only quality gate.

### What is NOT in this task

Explicitly deferred to potential future tasks:
- LLM validator (Codex / GPT / etc.)
- Deterministic file-existence checks (markdown parsing is fragile)
- `-AllowIncomplete`, `-StrictFiles` mode flags
- `planner_validation.md` artifact
- SHA256 stale-detection
- Hash-based pre-run gate in `ai_loop_task_first.ps1`

If the planner proves unreliable in practice, those layers can be added with
real-world data driving the design.

### Deliverables

1. `scripts/ai_loop_plan.ps1` — main entrypoint, architect-agnostic.
2. `scripts/run_claude_planner.ps1` — Claude planner wrapper.
3. `templates/planner_prompt.md` — planner role + output format.
4. `scripts/install_into_project.ps1` — self-install guard + copy lines.
5. `.gitignore` — ignore planner runtime artifacts.
6. `tests/test_orchestrator_validation.py` — minimal test set.

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
- Edits to `AGENTS.md`, `templates/codex_review_prompt.md`,
  `templates/task.md`, other templates, `src/`, `ai_loop.py`, docs
- Any validator wrapper, validator prompt, or `-WithValidator` parameter
- Any file-existence parsing of `## Files in scope`
- Calling `claude` CLI from tests

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
- `templates/codex_review_prompt.md`
- `templates/task.md`

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
    [switch]$Force
)
```

Logic (use an explicit `$script:ExitCode` variable — see Hard rules):

1. **Resolve ask:** prefer `-Ask`; else if `$AskFile` exists, read it; else
   exit 1 with `No ask provided. Use -Ask "..." or create $AskFile.`

2. **Resolve planner prompt path (source-repo fallback):**
   ```powershell
   $planPrompt = ".ai-loop\planner_prompt.md"
   if (-not (Test-Path -LiteralPath $planPrompt)) {
       $planPrompt = "templates\planner_prompt.md"
   }
   if (-not (Test-Path -LiteralPath $planPrompt)) {
       Write-Error "Planner prompt not found at .ai-loop\planner_prompt.md or templates\planner_prompt.md."
       exit 1
   }
   ```
   This lets the planner run both from a target project (installed prompt) and
   from the orchestrator source repo (template prompt) without duplicating the
   file in git.

3. **Validate prerequisites:** exit 1 with explicit "missing X" if any of:
   - `AGENTS.md`
   - `.ai-loop/project_summary.md`
   - `$PlannerCommand` (path must exist)

4. **Build planner prompt** by concatenating in this exact order:
   - Contents of `$planPrompt`
   - `## AGENTS.md` + contents of `AGENTS.md`
   - `## project_summary.md` + contents of `.ai-loop/project_summary.md`
   - `## repo_map.md` + contents of `.ai-loop/repo_map.md` if it exists
     (otherwise omit this section; do NOT auto-run `build_repo_map.ps1`)
   - `## USER ASK` + resolved ask

5. **Backup existing output:** if `$Out` exists and `-Force` is not set,
   `Move-Item -Force $Out "$Out.bak"`. Remember `$backupMade = $true`.

6. **Invoke planner wrapper inside try/catch with explicit exit-code variable:**
   ```powershell
   $script:ExitCode = 0
   try {
       $output = $prompt | & $PlannerCommand --workspace $ProjectRoot --model $PlannerModel
       if ($LASTEXITCODE -ne 0) {
           $script:ExitCode = 1
           throw "Planner wrapper exited with code $LASTEXITCODE."
       }

       # Minimal sanity check: output must start with '# Task:' and contain '## Goal'
       $first = ($output -split "`r?`n", 2)[0].TrimStart()
       if (-not $first.StartsWith("# Task:")) {
           $script:ExitCode = 2
           throw "Planner output does not start with '# Task:' — looks like a preamble or refusal."
       }
       if ($output -notmatch '(?m)^##\s+Goal\b') {
           $script:ExitCode = 2
           throw "Planner output is missing '## Goal' section."
       }

       Set-Content -LiteralPath $Out -Value $output -Encoding UTF8
   }
   catch {
       Write-Error $_.Exception.Message
       if ($backupMade -and -not (Test-Path -LiteralPath $Out)) {
           Move-Item -Force "$Out.bak" $Out
           Write-Host "Restored previous $Out from backup."
       }
   }
   finally {
       exit $script:ExitCode
   }
   ```

7. **Success message** (printed before the `finally` block exits):
   ```
   Wrote $Out (no obvious structural issues found).
   This is a DRAFT. Review it manually before running ai_loop_task_first.ps1.
   ```
   If a backup was made and write succeeded, also print:
   `Previous task.md kept at $Out.bak.`

Console messages must say `no obvious structural issues found` — never `task is
correct`. The point is to avoid false confidence.

Exit codes:
- 0: success
- 1: missing prerequisites or planner wrapper invocation error (backup restored)
- 2: planner output failed the minimal sanity check (backup restored)

Keep `ai_loop_plan.ps1` under 130 lines including comments.

### scripts/run_claude_planner.ps1

Mirrors `run_opencode_agent.ps1` line-for-line on the wrapper convention:

- **No `param()` block** (preserves `$input` from the pipeline).
- Parse `--workspace` and `--model` from `$args`; silently ignore unknown flags.
- Default model: `claude-sonnet-4-6`.
- Read prompt from `$input`. Empty → `Write-Error "run_claude_planner: no prompt received on stdin."` + exit 1.
- `Push-Location` to workspace if provided; `Pop-Location` in `finally`.
- Invoke `claude --print --model $model` with the prompt piped via stdin.
- **No `2>&1`** — stdout-only is captured by the caller; stderr flows to console.
- `exit $LASTEXITCODE`.

Keep under 50 lines.

### templates/planner_prompt.md

```markdown
# Planner role

You are the PLANNER for the ai-orchestrator file-based workflow. Convert the
USER ASK at the end of this prompt into a fully-formed `.ai-loop/task.md`.

## Hierarchy of authority

- `AGENTS.md` (provided below) — common rules for all agents.
- `CLAUDE.md` (target project, if present) — Claude-specific context; not your concern here.
- This prompt — your role: planner.
- Output `task.md` — concrete contract for the implementer.

## Output format

Produce a markdown document with these headings, in order:

- `# Task: <short name>`
- `## Project context` — required reading list (AGENTS.md, `.ai-loop/task.md`,
  `.ai-loop/project_summary.md`, `.ai-loop/implementer_summary.md` for iter 2+).
- `## Goal` — one paragraph, concrete.
- `## Scope` — `Allowed:` / `Not allowed:` bullet lists.
- `## Files in scope` — concrete relative paths only, one per bullet. Mark new
  files with trailing ` (new)`. Optional explanation only after whitespace on
  the same line.
- `## Files out of scope` — must include `docs/archive/**`, `.ai-loop/_debug/**`,
  `ai_loop.py`, plus task-specific exclusions.
- `## Required behavior` — numbered steps.
- `## Tests` — what to add or update; include `python -m pytest -q`.
- `## Verification` — concrete commands.
- `## Implementer summary requirements` — five-point list.
- `## Project summary update` — what durable info to record, or "no update needed".
- `## Output hygiene` — four standard bullets (no task duplication into summary,
  no debug writes, no commit, no archive writes).
- `## Important` — task-specific gotchas. If the ASK was ambiguous, list the
  concrete assumptions you made here so the human reviewer can spot them. Do
  not silently pick "reasonable defaults".

## Hard rules

- Output ONLY the task.md content. The very first line of your output must be
  `# Task: <short name>`. No preamble (no "Here is the task...", no
  explanation), no fenced code block wrapping the whole document, no HTML
  comments.
- Do not invent file paths. Use only paths visible in `AGENTS.md`,
  `project_summary.md`, or `repo_map.md`. Marking a path with ` (new)` is
  allowed for files the task creates.
- Keep implementation under ~80 lines of code change. If the ask is larger,
  split into ordered subtasks under `## Important`.
- Do not ask the user questions. Choose the conservative interpretation and
  surface the assumption under `## Important`.
- Downstream validation is minimal (first line must be `# Task:`; `## Goal`
  must exist). It does NOT check business logic. The human reviewer is the
  business-logic gate. Do not assume mechanical validation will catch errors.
```

### scripts/install_into_project.ps1

1. **Self-install guard** after parameter parsing, before any `New-Item` /
   `Copy-Item`:
   ```powershell
   if ((Resolve-Path $Root).Path -eq (Resolve-Path $TargetProject).Path) {
       Write-Error "install_into_project: source and target are the same directory. Refusing to self-install. Use a fresh temp directory for smoke tests."
       exit 1
   }
   ```

2. Add `Copy-Item -Force` lines (group with similar existing copies):
   - `scripts/ai_loop_plan.ps1` → target `scripts/`
   - `scripts/run_claude_planner.ps1` → target `scripts/`
   - `templates/planner_prompt.md` → target `.ai-loop/planner_prompt.md`

### .gitignore

Add under a section header `# planner runtime artifacts`:

```
.ai-loop/*.bak
.ai-loop/user_ask.md
```

(`user_ask.md` is gitignored because asks may contain private intent; users
can force-add if they want to track it.)

## Tests

Run:
```bash
python -m pytest -q
```

Add to `tests/test_orchestrator_validation.py` (eight tests total — no more):

1. `test_ai_loop_plan_script_exists` — assert `scripts/ai_loop_plan.ps1` exists.
2. `test_run_claude_planner_script_exists` — assert `scripts/run_claude_planner.ps1` exists.
3. `test_planner_prompt_template_exists` — assert `templates/planner_prompt.md` exists.
4. `test_planner_scripts_parse_cleanly` — extend the existing PowerShell
   `Parser::ParseFile` test list with the two new `.ps1` files.
5. `test_run_claude_planner_has_no_param_block_and_no_stderr_redirect` — read
   `run_claude_planner.ps1`; assert it does NOT contain `param(` and does NOT
   contain `2>&1`.
6. `test_install_copies_planner_files_and_has_self_install_guard` — read
   `install_into_project.ps1`; assert it copies `ai_loop_plan.ps1`,
   `run_claude_planner.ps1`, `planner_prompt.md` (target path
   `.ai-loop/planner_prompt.md`), AND contains the literal
   `Refusing to self-install`.
7. `test_gitignore_excludes_planner_artifacts` — assert `.gitignore` contains
   `.ai-loop/*.bak` AND `.ai-loop/user_ask.md`.
8. `test_ai_loop_plan_uses_explicit_exit_code_and_prompt_fallback` — read
   `ai_loop_plan.ps1`; assert it contains both:
   - `$script:ExitCode` literal (explicit exit-code variable, per Hard rules)
   - `templates\planner_prompt.md` literal (source-repo fallback path)

Do NOT call the `claude` CLI in tests. Do NOT add behavior tests for the
minimal sanity check — its logic is two `if` statements, structural tests are
sufficient.

## Verification

```bash
python -m pytest -q
```

```powershell
powershell -NoProfile -Command "[void][System.Management.Automation.Language.Parser]::ParseFile('scripts\ai_loop_plan.ps1', [ref]$null, [ref]$null)"
powershell -NoProfile -Command "[void][System.Management.Automation.Language.Parser]::ParseFile('scripts\run_claude_planner.ps1', [ref]$null, [ref]$null)"
```

Self-install guard check:
```powershell
.\scripts\install_into_project.ps1 -TargetProject .  # must exit non-zero
```

Manual smoke (requires authenticated `claude` CLI). Two scenarios — both must work:

**From source repo (uses templates/ fallback):**
```powershell
.\scripts\ai_loop_plan.ps1 -Ask "Add a hello-world smoke test that prints OK" -Out .ai-loop\task_smoke.md
Get-Content .ai-loop\task_smoke.md | Select-Object -First 20
Remove-Item .ai-loop\task_smoke.md
```

**Installed into temp target (uses .ai-loop/planner_prompt.md):**
```powershell
$tmp = Join-Path $env:TEMP "ai_orch_smoke_$(Get-Random)"
New-Item -ItemType Directory -Path $tmp | Out-Null
git -C $tmp init | Out-Null
.\scripts\install_into_project.ps1 -TargetProject $tmp
Set-Location $tmp
.\scripts\ai_loop_plan.ps1 -Ask "Add a smoke test" -Out .ai-loop\task_smoke.md
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
- Note: planner is **manual**, NOT part of the automated loop.
- Note: planner is architect-agnostic via `-PlannerCommand` (mirrors
  `-CursorCommand`).
- Note: minimal validation only; human review of `task.md` is the quality gate.
- Update Current Stage. Add to Next Likely Steps: "if planner proves
  unreliable in practice, add an LLM validator wrapper as a separate task".

## Output hygiene

The implementer must not:

- duplicate this task description into `.ai-loop/implementer_summary.md`
- include earlier task narrative in `.ai-loop/project_summary.md`
- write to `.ai-loop/_debug/` or `docs/archive/`
- commit or push (the orchestrator handles git)

## Important

**Scope discipline:** This task is intentionally minimal. Do NOT add an LLM
validator, file-existence parsing, `-AllowIncomplete`/`-StrictFiles` flags,
SHA256 hashes, `planner_validation.md`, or `repo_map.md` auto-refresh —
those were considered and explicitly deferred. If you think one of them is
critical, write a separate follow-up task spec rather than expanding C07.

**Manual stage, not in loop:** `ai_loop_plan.ps1` is invoked **by the user**
before `ai_loop_task_first.ps1`. Do NOT add a call to it from
`ai_loop_task_first.ps1`.

**Architect swappability:** `ai_loop_plan.ps1` MUST NEVER call `claude`
directly — only through `$PlannerCommand`. A future `run_gpt_planner.ps1` or
`run_local_planner.ps1` must drop in without main entrypoint changes.

**Wrapper convention (critical):**
- `run_claude_planner.ps1` MUST have no `param()` block. PowerShell pipeline
  binding would swallow `$input` otherwise. Mirror `run_opencode_agent.ps1`
  line-for-line.
- No `2>&1` — stdout is captured for content; stderr must reach the console.

**Explicit exit-code variable (critical):** use `$script:ExitCode` set
explicitly before each `throw`, with `finally { exit $script:ExitCode }`.
Do NOT rely on `throw` alone to differentiate exit 1 vs exit 2 — a generic
`catch` block would collapse them to 1.

**Source-repo prompt fallback:** `ai_loop_plan.ps1` MUST check
`.ai-loop/planner_prompt.md` first, then fall back to
`templates/planner_prompt.md`. This lets the planner run from the orchestrator
source repo (where the self-install guard refuses to install into self) without
committing a duplicated prompt to git.

**Backup restore on ANY non-success path:** after `Move-Item $Out → $Out.bak`,
any throw inside the try block must result in restoring the backup if `$Out`
no longer exists. Enforced via `catch` + `Move-Item -Force "$Out.bak" $Out`.

**Backup is left in place on success.** User can `Remove-Item .ai-loop/task.md.bak`
after review. The `.bak` is gitignored.

**Self-install guard:** `install_into_project.ps1` MUST refuse when
`$Target == $Root` with a clear message. Smoke tests use a temp directory
(see Verification).

**Messaging discipline:** console output and the planner prompt MUST use
"no obvious structural issues found" / "draft" / "review before running" — never
"task is correct" or "validation passed". The point of this minimal design is
to avoid false confidence; the human is the quality gate.

**Installer note:** the installer copies the planner prompt to
`.ai-loop/planner_prompt.md` in target projects (target projects have no
`templates/` directory).
