# C07 — Task planner with deterministic validation + optional LLM validator

**Project:** `ai-orchestrator`
**CWD:** `C:\Users\che\Documents\Projects\ai-orchestrator`
**Risk:** medium-high — five new files, install contract change, exceeds ≤80-line task policy (flagged explicitly; see `## Important`).

How to run:
```powershell
# Paste task spec below into .ai-loop\task.md, then:
powershell -ExecutionPolicy Bypass -File .\scripts\ai_loop_task_first.ps1 -NoPush
```

---

# Task: Architect-agnostic task planner with two-tier validation

## Project context

Required reading before starting (in order; stop when you have enough):

1. `AGENTS.md` at repo root — working rules and forbidden paths
2. `.ai-loop/task.md` — this task
3. `.ai-loop/project_summary.md` — durable project orientation
4. `.ai-loop/repo_map.md` — file index
5. `scripts/ai_loop_task_first.ps1` — existing prompt-assembly pattern to mirror
6. `scripts/run_cursor_agent.ps1`, `scripts/run_opencode_agent.ps1`, `scripts/run_opencode_scout.ps1` — existing wrapper convention
7. `scripts/install_into_project.ps1` — installer pattern (templates land in `.ai-loop/`, not `templates/`)
8. `.ai-loop/implementer_summary.md` — only if this is iteration 2+

Do not read by default:

- `docs/archive/`
- `.ai-loop/_debug/`

## Goal

Add a **manual** planner stage that produces `.ai-loop/task.md` from a natural-language
ask, with two-tier validation. Both planner and validator are pluggable wrappers — same
pattern as implementer wrappers (`-CursorCommand`).

```
ai_loop_plan.ps1 -PlannerCommand .\scripts\run_claude_planner.ps1 `
                 [-WithValidator] [-ValidatorCommand .\scripts\run_claude_validator.ps1]
```

### Architectural symmetry

```
Implementer stage:                   Planner stage:
  implementer wrapper                  planner wrapper
  pytest (deterministic)               file-exists check (deterministic, mandatory)
  Codex review (LLM)                   validator (LLM, optional via -WithValidator)
  commit/push                          write task.md
```

### Deliverables

1. `scripts/ai_loop_plan.ps1` — main entrypoint. Architect-agnostic.
2. `scripts/run_claude_planner.ps1` — Claude planner wrapper.
3. `scripts/run_claude_validator.ps1` — Claude validator wrapper.
4. `templates/planner_prompt.md` — planner role + output format.
5. `templates/validator_prompt.md` — validator role + verdict format.
6. `scripts/install_into_project.ps1` — copy new prompts to `.ai-loop/`, copy new wrappers to `scripts/`.
7. `.gitignore` — ignore `.ai-loop/*.bak`.
8. `tests/test_orchestrator_validation.py` — new tests.

## Scope

Allowed:
- Create `scripts/ai_loop_plan.ps1`
- Create `scripts/run_claude_planner.ps1`
- Create `scripts/run_claude_validator.ps1`
- Create `templates/planner_prompt.md`
- Create `templates/validator_prompt.md`
- Edit `scripts/install_into_project.ps1`
- Edit `.gitignore`
- Edit `tests/test_orchestrator_validation.py`

Not allowed:
- Any changes to `scripts/ai_loop_auto.ps1`, `scripts/ai_loop_task_first.ps1`,
  `scripts/continue_ai_loop.ps1`
- Changes to existing implementer wrappers (`run_cursor_agent.ps1`,
  `run_opencode_agent.ps1`, `run_opencode_scout.ps1`, `run_scout_pass.ps1`)
- Edits to `AGENTS.md`, other templates, `src/`, `ai_loop.py`, docs
- Calling `claude` CLI from tests

## Files in scope

- `scripts/ai_loop_plan.ps1` (new)
- `scripts/run_claude_planner.ps1` (new)
- `scripts/run_claude_validator.ps1` (new)
- `templates/planner_prompt.md` (new)
- `templates/validator_prompt.md` (new)
- `scripts/install_into_project.ps1` (edit, +6 lines)
- `.gitignore` (edit, +1 line)
- `tests/test_orchestrator_validation.py` (edit, +~60 lines)

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

## Required behavior

### scripts/ai_loop_plan.ps1

Parameters:
```powershell
param(
    [string]$Ask = "",
    [string]$AskFile = ".ai-loop\user_ask.md",
    [string]$PlannerCommand = ".\scripts\run_claude_planner.ps1",
    [string]$PlannerModel = "",
    [string]$ValidatorCommand = ".\scripts\run_claude_validator.ps1",
    [string]$ValidatorModel = "",
    [string]$Out = ".ai-loop\task.md",
    [switch]$WithValidator,
    [switch]$AllowIncomplete,
    [switch]$Force
)
```

Logic:

1. **Resolve ask:** prefer `-Ask`; else read `$AskFile`; else exit 1 with
   `No ask provided. Use -Ask "..." or create $AskFile.`

2. **Validate prerequisites:** exit 1 with a clear "missing X" message if any of
   the following do not exist:
   - `AGENTS.md`
   - `.ai-loop/project_summary.md`
   - `.ai-loop/planner_prompt.md` (installed by `install_into_project.ps1`)
   - `$PlannerCommand`
   - `$ValidatorCommand` only if `-WithValidator` is set

3. **Build planner prompt** by concatenating, in this exact order:
   - Contents of `.ai-loop/planner_prompt.md`
   - `## AGENTS.md` + contents of `AGENTS.md`
   - `## project_summary.md` + contents of `.ai-loop/project_summary.md`
   - `## repo_map.md` + entire contents of `.ai-loop/repo_map.md` (capped at
     250 lines by builder; read the whole file)
   - `## USER ASK` + resolved ask

4. **Backup existing output:** if `$Out` exists and `-Force` is not set, rename
   it to `$Out.bak` (overwriting any prior `.bak`).

5. **Invoke planner wrapper:**
   ```powershell
   $output = $prompt | & $PlannerCommand --workspace $ProjectRoot --model $PlannerModel
   ```
   Capture only stdout. Do NOT use `2>&1` — stderr must surface to console for
   debugging, not pollute `$output`. Exit 1 with wrapper's exit code on non-zero.

6. **Deterministic validation (mandatory, unless `-AllowIncomplete`):**
   Call `Test-TaskValidity` on `$output`. Checks:
   - Required headings present (`# Task:`, `## Goal`, `## Scope`,
     `## Files in scope`, `## Files out of scope`, `## Required behavior`,
     `## Tests`, `## Verification`, `## Implementer summary requirements`,
     `## Important`).
   - No `<!-- ... -->` HTML comments anywhere.
   - No leading/trailing code fence wrapping the whole document
     (no `^```` at start, no terminal `` ``` `` immediately before EOF).
   - `## Files out of scope` body contains `docs/archive/`, `.ai-loop/_debug/`,
     and `ai_loop.py`.
   - For each path under `## Files in scope` that does NOT contain `(new)`,
     `*`, `?`, `**`, or end with `/`: assert path exists in the current
     working tree (use `Test-Path -LiteralPath`). Globs/new files are skipped.

   On failure: write the captured output to `$Out.invalid` for inspection,
   write a `.ai-loop/planner_validation.md` listing failed checks, exit 2
   without overwriting `$Out`. Restore `$Out.bak` if it was created in step 4.

   With `-AllowIncomplete`: log warnings, proceed to write.

7. **Write output:** UTF-8 no BOM to `$Out`.

8. **Optional LLM validation:** if `-WithValidator` is set, build validator prompt
   (see below) and invoke `$ValidatorCommand`. Write captured stdout to
   `.ai-loop/planner_validation.md`. Parse first non-empty line for verdict:
   - `VERDICT: PASS` → exit 0
   - `VERDICT: WARN` → exit 0 (file still written), print summary
   - `VERDICT: FAIL` → exit 3 (file still written so user can fix manually),
     print summary

9. **Success message:**
   `Wrote $Out. Review before running ai_loop_task_first.ps1.`

Exit codes:
- 0: success (with or without validator PASS/WARN)
- 1: missing prerequisites or wrapper invocation error
- 2: deterministic validation failed (file NOT written)
- 3: LLM validator returned FAIL (file written, see planner_validation.md)

Keep `ai_loop_plan.ps1` under 200 lines including comments and helpers.

### scripts/run_claude_planner.ps1

Mirrors `run_opencode_agent.ps1` convention:

- **No `param()` block** (so `$input` receives piped stdin without
  pipeline-parameter binding errors).
- Parse `--workspace` and `--model` from `$args`; silently ignore unknown flags.
- Default model: `claude-sonnet-4-6`.
- Read prompt from `$input`. Empty → `Write-Error` + exit 1.
- `Push-Location` to workspace if provided; `Pop-Location` in `finally`.
- Invoke `claude --print --model $model` with the prompt on stdin.
- **No `2>&1`** — let stderr flow to console; only stdout is captured.
- `exit $LASTEXITCODE`.

Keep under 50 lines.

### scripts/run_claude_validator.ps1

Identical structure to `run_claude_planner.ps1` (same wrapper convention,
parses `--workspace` and `--model`, no `param()`, no `2>&1`). Only the role
label differs — invokes `claude --print --model $model` with the validator
prompt piped via stdin.

Keep under 50 lines.

### templates/planner_prompt.md

Markdown content (no HTML comments at top). Required sections:

```markdown
# Planner role

You are the PLANNER for the ai-orchestrator file-based workflow. Convert the
USER ASK at the end of this prompt into a fully-formed `.ai-loop/task.md`.

## Hierarchy of authority

- `AGENTS.md` (provided below) — common rules for all agents.
- `CLAUDE.md` (target project) — Claude-specific architect context, not your concern here.
- This prompt — your role: planner.
- Output `task.md` — concrete contract for the implementer.

## Output format

Produce a markdown document with these headings, in order:

- `# Task: <short name>`
- `## Project context` — required reading list pointing at AGENTS.md,
  `.ai-loop/task.md`, `.ai-loop/project_summary.md`, and
  `.ai-loop/implementer_summary.md` (iteration-2+ only).
- `## Goal` — one paragraph, concrete.
- `## Scope` — `Allowed:` / `Not allowed:` bullet lists.
- `## Files in scope` — concrete relative paths only. Mark new files with
  ` (new)` after the path. Use only paths visible in the provided context.
- `## Files out of scope` — must include `docs/archive/**`, `.ai-loop/_debug/**`,
  `ai_loop.py`, plus task-specific exclusions.
- `## Required behavior` — numbered steps.
- `## Tests` — what to add or update; include `python -m pytest -q`.
- `## Verification` — concrete commands.
- `## Implementer summary requirements` — five-point list.
- `## Project summary update` — what durable info to record, or "no update needed".
- `## Output hygiene` — four standard bullets (no task duplication into summary,
  no debug writes, no commit, no archive writes).
- `## Important` — task-specific gotchas; if ASK was ambiguous, list assumptions
  here explicitly so the human reviewer can spot them.

## Hard rules

- Output ONLY the task.md content — no preamble, no explanation, no code fence
  wrapping the whole document, no HTML comments.
- Do not invent file paths. Use only paths visible in `AGENTS.md`,
  `project_summary.md`, or `repo_map.md`.
- Keep implementation under ~80 lines of code change. If the ask is larger,
  split into ordered subtasks under `## Important`.
- Do not ask the user questions. Choose the conservative interpretation of
  ambiguous asks and surface the assumption under `## Important`.
- Mark new files with ` (new)` suffix in `## Files in scope` so validation
  knows not to require their existence.
```

### templates/validator_prompt.md

Markdown content. Validator receives: original ASK, generated task.md, and
project context. Required sections:

```markdown
# Validator role

You are the VALIDATOR. Compare the generated `task.md` against the original
USER ASK and the project context. Decide if the planner produced a faithful,
implementable contract.

## What to check

- Does the task.md address the user's ask, or does it solve a different problem?
- Are referenced files plausible given the project context (AGENTS.md,
  project_summary.md, repo_map.md)?
- Is `## Files in scope` reasonable (not too broad, not missing obviously
  needed files)?
- Are acceptance criteria concrete and testable?
- Are there assumptions in `## Important` that look wrong?
- Is the scope realistically within ~80 lines of change?

## Output format

Output ONLY these lines, nothing else:

```
VERDICT: PASS | WARN | FAIL
SUMMARY: <one sentence>
ISSUES:
- <issue 1>
- <issue 2>
```

- `PASS`: task.md is a faithful implementation of the ask; no issues.
- `WARN`: task.md is acceptable but has minor concerns the reviewer should
  notice (broad scope, vague acceptance, etc.).
- `FAIL`: task.md misunderstands the ask, invents files, or has critical scope
  issues. The user must regenerate.

If `PASS`, the `ISSUES:` list may be empty or omitted.
```

### scripts/install_into_project.ps1

Add `Copy-Item -Force` lines (alphabetical or grouped with similar items):
- `scripts/ai_loop_plan.ps1` → target `scripts/`
- `scripts/run_claude_planner.ps1` → target `scripts/`
- `scripts/run_claude_validator.ps1` → target `scripts/`
- `templates/planner_prompt.md` → target `.ai-loop/planner_prompt.md`
- `templates/validator_prompt.md` → target `.ai-loop/validator_prompt.md`

### .gitignore

Add one line: `.ai-loop/*.bak`

## Tests

Run:
```bash
python -m pytest -q
```

Add to `tests/test_orchestrator_validation.py`:

1. `test_ai_loop_plan_script_exists`
2. `test_run_claude_planner_script_exists`
3. `test_run_claude_validator_script_exists`
4. `test_planner_prompt_template_exists`
5. `test_validator_prompt_template_exists`
6. `test_planner_scripts_parse_cleanly` — extend the existing parse-check list
   with the three new `.ps1` files.
7. `test_ai_loop_plan_declares_required_parameters` — assert `ai_loop_plan.ps1`
   declares `$Ask`, `$AskFile`, `$PlannerCommand`, `$PlannerModel`,
   `$ValidatorCommand`, `$ValidatorModel`, `$Out`, `$WithValidator`,
   `$AllowIncomplete`, `$Force`.
8. `test_planner_wrappers_have_no_param_block` — assert
   `run_claude_planner.ps1` and `run_claude_validator.ps1` do NOT contain a
   `param(` declaration (wrapper convention to preserve `$input`).
9. `test_planner_wrappers_use_claude_print` — assert both wrappers contain
   `claude --print` (or `claude -p`) and `--model`.
10. `test_planner_wrappers_have_no_stderr_redirect` — assert neither wrapper
    contains `2>&1` (would pollute captured stdout).
11. `test_planner_prompt_has_required_sections` — `# Planner role`,
    `## Output format`, `## Hard rules`.
12. `test_validator_prompt_has_required_sections` — `# Validator role`,
    `## What to check`, `## Output format`, and the `VERDICT:` literal.
13. `test_install_copies_planner_files` — assert `install_into_project.ps1`
    copies the three scripts and two templates (templates go to `.ai-loop/`).
14. `test_gitignore_excludes_bak_backups` — assert `.gitignore` contains
    `.ai-loop/*.bak`.

Do NOT call the `claude` CLI in tests.

## Verification

```bash
python -m pytest -q
```

```powershell
powershell -NoProfile -Command "[void][System.Management.Automation.Language.Parser]::ParseFile('scripts\ai_loop_plan.ps1', [ref]$null, [ref]$null)"
powershell -NoProfile -Command "[void][System.Management.Automation.Language.Parser]::ParseFile('scripts\run_claude_planner.ps1', [ref]$null, [ref]$null)"
powershell -NoProfile -Command "[void][System.Management.Automation.Language.Parser]::ParseFile('scripts\run_claude_validator.ps1', [ref]$null, [ref]$null)"
```

Manual smoke (requires authenticated `claude` CLI):
```powershell
# Install into self to test the installed layout
.\scripts\install_into_project.ps1 -TargetProject "C:\Users\che\Documents\Projects\ai-orchestrator"
# Run planner only
.\scripts\ai_loop_plan.ps1 -Ask "Add a hello-world smoke test that prints OK" -Out .ai-loop\task_smoke.md
# Run planner with validator
.\scripts\ai_loop_plan.ps1 -Ask "Add a smoke test" -WithValidator -Out .ai-loop\task_smoke.md
```
Verify outputs, then delete both `.ai-loop\task_smoke.md` and
`.ai-loop\planner_validation.md`.

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
  `run_claude_planner.ps1`, `run_claude_validator.ps1`,
  `templates/planner_prompt.md`, `templates/validator_prompt.md`.
- Note: planner is manual, NOT part of the automated loop.
- Note: planner is architect-agnostic via `-PlannerCommand` /
  `-ValidatorCommand` (mirrors `-CursorCommand`).
- Update Current Stage and Next Likely Steps.

## Output hygiene

The implementer must not:

- duplicate this task description into `.ai-loop/implementer_summary.md`
- include earlier task narrative in `.ai-loop/project_summary.md`
- write to `.ai-loop/_debug/` or `docs/archive/`
- commit or push (the orchestrator handles git)

## Important

**Spec size:** This task exceeds the AGENTS.md ≤80-line-of-change policy. It is
allowed as a foundational stage. Suggested implementation order so the work can
be tested incrementally:
1. `templates/planner_prompt.md` + `scripts/run_claude_planner.ps1` (minimal pair).
2. `scripts/ai_loop_plan.ps1` without validator path, with deterministic
   `Test-TaskValidity`.
3. `templates/validator_prompt.md` + `scripts/run_claude_validator.ps1`.
4. Wire `-WithValidator` into `ai_loop_plan.ps1`.
5. Installer + `.gitignore` + tests.

**Manual stage, not in loop:** `ai_loop_plan.ps1` is invoked **by the user**
before `ai_loop_task_first.ps1`. Do NOT add a call to it from
`ai_loop_task_first.ps1`.

**Architect swappability:** `ai_loop_plan.ps1` MUST never call `claude` directly
— only through `$PlannerCommand` / `$ValidatorCommand`. A future
`run_gpt_planner.ps1` or `run_local_validator.ps1` must drop in without main
entrypoint changes.

**Wrapper convention:** `run_claude_planner.ps1` and `run_claude_validator.ps1`
MUST have no `param()` block (PowerShell pipeline binding would swallow
`$input`). Mirror `run_opencode_agent.ps1` line-for-line on this.

**Stream separation:** Wrappers MUST NOT use `2>&1`. Stdout is captured for
content; stderr must reach the console so warnings don't pollute `task.md`.

**Mandatory review:** The planner output is a DRAFT. The user MUST manually
review `.ai-loop/task.md` before running `ai_loop_task_first.ps1`. LLM
validation (when enabled) catches mechanical issues; it does not replace human
judgment for business logic.

**Backup hygiene:** `.ai-loop/task.md.bak` is gitignored via `.ai-loop/*.bak`
and is NOT in `SafeAddPaths`. Confirm both after the run.

**Installer note:** The installer copies prompts to `.ai-loop/`, not to a
`templates/` directory in target projects. Target projects do not have a
`templates/` directory. `ai_loop_plan.ps1` reads from
`.ai-loop/planner_prompt.md`, not `templates/planner_prompt.md`.
