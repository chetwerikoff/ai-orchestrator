# C07 — Task planner with deterministic validation + Codex validator

**Project:** `ai-orchestrator`
**CWD:** `C:\Users\che\Documents\Projects\ai-orchestrator`
**Risk:** medium-high — five new files, install contract change, exceeds ≤80-line task policy (flagged explicitly; see `## Important`).

How to run:
```powershell
# Paste task spec below into .ai-loop\task.md, then:
powershell -ExecutionPolicy Bypass -File .\scripts\ai_loop_task_first.ps1 -NoPush
```

---

# Task: Architect-agnostic task planner with deterministic + Codex validation

## Project context

Required reading before starting (in order; stop when you have enough):

1. `AGENTS.md` at repo root — working rules and forbidden paths
2. `.ai-loop/task.md` — this task
3. `.ai-loop/project_summary.md` — durable project orientation
4. `.ai-loop/repo_map.md` — file index
5. `scripts/ai_loop_task_first.ps1` — existing prompt-assembly pattern; also the
   repo_map auto-refresh pattern (~lines 321-332) to mirror
6. `scripts/run_cursor_agent.ps1`, `scripts/run_opencode_agent.ps1`,
   `scripts/run_opencode_scout.ps1` — wrapper convention
7. `scripts/ai_loop_auto.ps1` — Codex invocation pattern (`Run-CodexReview`,
   `codex exec`, single-quoted here-string for fenced JSON) to mirror in
   `run_codex_validator.ps1`
8. `templates/codex_review_prompt.md` — existing Codex prompt format to compare
   against (not to reuse — validator role is different)
9. `scripts/install_into_project.ps1` — installer pattern (target projects have
   no `templates/` dir; prompts land in `.ai-loop/`)
10. `.ai-loop/implementer_summary.md` — only if this is iteration 2+

Do not read by default:

- `docs/archive/`
- `.ai-loop/_debug/`

## Goal

Add a **manual** planner stage that produces `.ai-loop/task.md` from a
natural-language ask, with two-tier validation. Planner and validator are
pluggable wrappers — same pattern as implementer wrappers (`-CursorCommand`).

```
ai_loop_plan.ps1 -PlannerCommand .\scripts\run_claude_planner.ps1 `
                 [-WithValidator] [-ValidatorCommand .\scripts\run_codex_validator.ps1]
```

### Architectural symmetry

```
Implementer stage:                   Planner stage:
  Cursor (Anthropic-style impl)        Claude (Anthropic planner)
  pytest (deterministic)               file-exists (deterministic, mandatory)
  Codex review (independent gate)      Codex validator (independent gate, opt-in)
  commit/push                          write task.md
```

Codex is used at both stages because it is the existing independent reviewer
in this project (different model family from the Anthropic side).

### Deliverables

1. `scripts/ai_loop_plan.ps1` — main entrypoint. Architect-agnostic.
2. `scripts/run_claude_planner.ps1` — Claude planner wrapper.
3. `scripts/run_codex_validator.ps1` — Codex validator wrapper (default validator).
4. `templates/planner_prompt.md` — planner role + output format.
5. `templates/validator_prompt.md` — validator role + verdict format
   (architect-agnostic; reused by future validator wrappers).
6. `scripts/install_into_project.ps1` — copy new prompts to `.ai-loop/`, copy
   new wrappers to `scripts/`, add self-install guard.
7. `.gitignore` — ignore planner runtime artifacts.
8. `tests/test_orchestrator_validation.py` — new tests.

## Scope

Allowed:
- Create `scripts/ai_loop_plan.ps1`
- Create `scripts/run_claude_planner.ps1`
- Create `scripts/run_codex_validator.ps1`
- Create `templates/planner_prompt.md`
- Create `templates/validator_prompt.md`
- Edit `scripts/install_into_project.ps1`
- Edit `.gitignore`
- Edit `tests/test_orchestrator_validation.py`
- Edit `.ai-loop/project_summary.md` (required by `## Project summary update`)

Not allowed:
- Any changes to `scripts/ai_loop_auto.ps1`, `scripts/ai_loop_task_first.ps1`,
  `scripts/continue_ai_loop.ps1`
- Changes to existing implementer wrappers (`run_cursor_agent.ps1`,
  `run_opencode_agent.ps1`, `run_opencode_scout.ps1`, `run_scout_pass.ps1`)
- Edits to `AGENTS.md`, other templates, `src/`, `ai_loop.py`, docs
- Calling `claude` or `codex` CLIs from tests

## Files in scope

- `scripts/ai_loop_plan.ps1` (new)
- `scripts/run_claude_planner.ps1` (new)
- `scripts/run_codex_validator.ps1` (new)
- `templates/planner_prompt.md` (new)
- `templates/validator_prompt.md` (new)
- `scripts/install_into_project.ps1` (edit)
- `.gitignore` (edit)
- `tests/test_orchestrator_validation.py` (edit)
- `.ai-loop/project_summary.md` (edit — Architecture, Stage, Next Steps)

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
- `templates/codex_review_prompt.md` (existing, not reused)

## Required behavior

### scripts/ai_loop_plan.ps1

Parameters:
```powershell
param(
    [string]$Ask = "",
    [string]$AskFile = ".ai-loop\user_ask.md",
    [string]$PlannerCommand = ".\scripts\run_claude_planner.ps1",
    [string]$PlannerModel = "",
    [string]$ValidatorCommand = ".\scripts\run_codex_validator.ps1",
    [string]$ValidatorModel = "",
    [string]$Out = ".ai-loop\task.md",
    [switch]$WithValidator,
    [switch]$AllowIncomplete,
    [switch]$Force
)
```

Logic (in order):

1. **Resolve ask:** prefer `-Ask`; else read `$AskFile`; else exit 1.

2. **Validate prerequisites:** exit 1 with explicit "missing X" if any of:
   - `AGENTS.md`
   - `.ai-loop/project_summary.md`
   - `.ai-loop/planner_prompt.md`
   - `$PlannerCommand`
   - `$ValidatorCommand` and `.ai-loop/validator_prompt.md` only if `-WithValidator`

3. **Auto-refresh repo_map.md** (mirror `ai_loop_task_first.ps1` pattern):
   - If `.ai-loop/repo_map.md` does not exist OR its `LastWriteTime` is older
     than 1 hour: run `scripts/build_repo_map.ps1` if present.
   - Failure of `build_repo_map.ps1` is non-fatal — log a warning and continue.
   - If after the refresh attempt `.ai-loop/repo_map.md` still does not exist,
     proceed without it (warn that planner context will be reduced).

4. **Build planner prompt** by concatenating in this exact order:
   - Contents of `.ai-loop/planner_prompt.md`
   - `## AGENTS.md` + contents of `AGENTS.md`
   - `## project_summary.md` + contents of `.ai-loop/project_summary.md`
   - `## repo_map.md` + entire contents of `.ai-loop/repo_map.md` if present
     (capped at 250 lines by builder; read the whole file)
   - `## USER ASK` + resolved ask

5. **Backup existing output:** if `$Out` exists and `-Force` is not set, rename
   it to `$Out.bak` (overwriting any prior `.bak`). Remember the path.

6. **Wrap steps 7-10 in `try { … } catch { … } finally { … }`:**
   - In `catch`: if a backup was created in step 5 and `$Out` does not exist
     (or has been written), restore the backup to `$Out` BEFORE rethrowing.
   - In `finally`: leave the `.bak` in place if write succeeded (caller can
     `Remove-Item` after review).

7. **Invoke planner wrapper:**
   ```powershell
   $output = $prompt | & $PlannerCommand --workspace $ProjectRoot --model $PlannerModel
   ```
   Capture stdout. Do NOT use `2>&1` — stderr must reach the console without
   polluting `$output`. On non-zero exit: restore backup (via catch) and exit 1.

8. **Deterministic validation (mandatory unless `-AllowIncomplete`):**
   Call `Test-TaskValidity` on `$output`. Checks:
   - Required headings present: `# Task:`, `## Goal`, `## Scope`,
     `## Files in scope`, `## Files out of scope`, `## Required behavior`,
     `## Tests`, `## Verification`, `## Implementer summary requirements`,
     `## Important`.
   - No `<!-- ... -->` HTML comments anywhere.
   - No fenced-code wrapping the whole document (no leading ```` ``` ```` then
     trailing ```` ``` ```` on the last non-blank line).
   - `## Files out of scope` body contains `docs/archive/`, `.ai-loop/_debug/`,
     and `ai_loop.py`.
   - Each path under `## Files in scope` that does NOT contain `(new)`, `*`,
     `?`, `**`, and does NOT end with `/`: must exist (`Test-Path -LiteralPath`).
     Globs and `(new)` items are skipped.

   On failure: write `$output` to `$Out.invalid` (overwriting), write a
   `.ai-loop/planner_validation.md` listing failed checks, restore backup (via
   catch) to keep current `$Out` intact, exit 2. `-AllowIncomplete` downgrades
   failures to warnings; proceed to write.

9. **Write output:** UTF-8 no BOM to `$Out`.

10. **Optional LLM validation:** if `-WithValidator`, build validator prompt
    (`.ai-loop/validator_prompt.md` + USER ASK + GENERATED task.md + project
    context) and invoke `$ValidatorCommand`. Write captured stdout to
    `.ai-loop/planner_validation.md`. Parse first non-empty matching line for
    `VERDICT: PASS|WARN|FAIL`:
    - `PASS` → continue, exit 0
    - `WARN` → print summary, exit 0
    - `FAIL` → print summary, exit 3 (file IS written so user can fix manually)

11. **Success message:**
    `Wrote $Out. Review before running ai_loop_task_first.ps1.`

Exit codes:
- 0: success (with or without validator PASS/WARN)
- 1: missing prerequisites or wrapper invocation error (backup restored if any)
- 2: deterministic validation failed; `$Out.invalid` written; backup restored
- 3: LLM validator returned FAIL; `$Out` written, see `planner_validation.md`

Keep `ai_loop_plan.ps1` under 220 lines including helpers.

### scripts/run_claude_planner.ps1

Mirrors `run_opencode_agent.ps1` convention exactly:

- **No `param()` block**.
- Parse `--workspace` and `--model` from `$args`; silently ignore unknown flags.
- Default model: `claude-sonnet-4-6`.
- Read prompt from `$input`. Empty → `Write-Error` + exit 1.
- `Push-Location` to workspace if provided; `Pop-Location` in `finally`.
- Invoke `claude --print --model $model` with prompt piped via stdin.
- **No `2>&1`** — stdout-only is captured.
- `exit $LASTEXITCODE`.

Keep under 50 lines.

### scripts/run_codex_validator.ps1

Mirrors the wrapper convention (no `param()` block, `--workspace`/`--model`
parsing, no `2>&1`). Default model: leave unset and let Codex CLI decide
(matches existing `Run-CodexReview` pattern). Invokes the Codex CLI
non-interactively with the validator prompt piped via stdin OR via a temp
prompt file (mirror whichever pattern `Run-CodexReview` in `ai_loop_auto.ps1`
uses for `codex exec`).

Important Codex specifics to mirror from `Run-CodexReview`:
- Single-quoted PowerShell here-strings for any embedded fenced JSON.
- Codex receives the WHOLE prompt body (validator template + ask + task.md +
  context) — the wrapper itself does not embed role text.

Keep under 60 lines.

### templates/planner_prompt.md

Markdown content (no HTML comments at top).

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
- `## Output hygiene` — four standard bullets.
- `## Important` — task-specific gotchas; if the ASK was ambiguous, list
  assumptions here explicitly so the reviewer can spot them.

## Hard rules

- Output ONLY the task.md content — no preamble, no explanation, no fenced
  code wrapping the whole document, no HTML comments.
- Do not invent file paths. Use only paths visible in `AGENTS.md`,
  `project_summary.md`, or `repo_map.md`.
- Mark new files with ` (new)` so deterministic validation skips existence checks.
- Keep implementation under ~80 lines of code change. If the ask is larger,
  split into ordered subtasks under `## Important`.
- Do not ask the user questions. Choose the conservative interpretation of
  ambiguous asks and surface the assumption under `## Important`.
```

### templates/validator_prompt.md

Architect-agnostic (Codex today, possibly Claude/other later).

```markdown
# Validator role

You are the VALIDATOR. Compare the generated `task.md` against the original
USER ASK and the project context. Decide if the planner produced a faithful,
implementable contract.

## What to check

- Does `task.md` address the user's ask, or does it solve a different problem?
- Are referenced files plausible given the project context (`AGENTS.md`,
  `project_summary.md`, `repo_map.md`)?
- Is `## Files in scope` reasonable — not too broad, not missing obviously
  needed files?
- Are acceptance criteria concrete and testable?
- Are the assumptions in `## Important` reasonable?
- Is the scope realistically within ~80 lines of change?

## Output format

Output ONLY these lines, nothing else (no markdown code fence wrapping):

VERDICT: PASS | WARN | FAIL
SUMMARY: <one sentence>
ISSUES:
- <issue 1>
- <issue 2>

- `PASS`: faithful contract; no issues.
- `WARN`: acceptable but minor concerns the human reviewer should notice.
- `FAIL`: misunderstands the ask, invents files, or has critical scope issues —
  user must regenerate or rewrite manually.

If `PASS`, `ISSUES:` may be empty or omitted.
```

### scripts/install_into_project.ps1

1. **Self-install guard** at the top of the script (after parameter parsing,
   before `New-Item` calls):
   ```powershell
   if ((Resolve-Path $Root).Path -eq (Resolve-Path $TargetProject).Path) {
       Write-Error "install_into_project: source and target are the same directory. Refusing to self-install."
       exit 1
   }
   ```

2. Add `Copy-Item -Force` lines:
   - `scripts/ai_loop_plan.ps1` → target `scripts/`
   - `scripts/run_claude_planner.ps1` → target `scripts/`
   - `scripts/run_codex_validator.ps1` → target `scripts/`
   - `templates/planner_prompt.md` → target `.ai-loop/planner_prompt.md`
   - `templates/validator_prompt.md` → target `.ai-loop/validator_prompt.md`

### .gitignore

Add these lines (grouped under a single comment line "# planner runtime artifacts"):

```
.ai-loop/*.bak
.ai-loop/*.invalid
.ai-loop/planner_validation.md
.ai-loop/user_ask.md
```

`user_ask.md` is intentionally gitignored — it may contain private context the
user does not want committed; if the user wants to track it, they can force-add.

## Tests

Run:
```bash
python -m pytest -q
```

Add to `tests/test_orchestrator_validation.py`:

1. `test_ai_loop_plan_script_exists`
2. `test_run_claude_planner_script_exists`
3. `test_run_codex_validator_script_exists`
4. `test_planner_prompt_template_exists`
5. `test_validator_prompt_template_exists`
6. `test_planner_scripts_parse_cleanly` — extend the existing parse-check list
   with the three new `.ps1` files.
7. `test_ai_loop_plan_declares_required_parameters` — assert `ai_loop_plan.ps1`
   declares `$Ask`, `$AskFile`, `$PlannerCommand`, `$PlannerModel`,
   `$ValidatorCommand`, `$ValidatorModel`, `$Out`, `$WithValidator`,
   `$AllowIncomplete`, `$Force`.
8. `test_ai_loop_plan_default_validator_is_codex` — assert
   `$ValidatorCommand = ".\scripts\run_codex_validator.ps1"` literal is present.
9. `test_planner_wrappers_have_no_param_block` — both wrappers do NOT contain
   `param(`.
10. `test_planner_wrapper_uses_claude_print` — `run_claude_planner.ps1` contains
    `claude --print` (or `claude -p`) and `--model`.
11. `test_codex_validator_uses_codex_cli` — `run_codex_validator.ps1` invokes
    `codex` CLI (e.g. `codex exec` or compatible form mirroring existing
    `Run-CodexReview` in `ai_loop_auto.ps1`).
12. `test_planner_wrappers_have_no_stderr_redirect` — neither wrapper contains
    `2>&1`.
13. `test_planner_prompt_has_required_sections` — `# Planner role`,
    `## Output format`, `## Hard rules`.
14. `test_validator_prompt_has_required_sections` — `# Validator role`,
    `## What to check`, `## Output format`, the literal `VERDICT:`.
15. `test_install_copies_planner_files` — assert `install_into_project.ps1`
    copies the three scripts and two templates (templates target `.ai-loop/`).
16. `test_install_has_self_install_guard` — assert
    `install_into_project.ps1` contains `Refusing to self-install` (or
    equivalent guard message string used in the actual implementation).
17. `test_gitignore_excludes_planner_artifacts` — assert `.gitignore` contains
    `.ai-loop/*.bak`, `.ai-loop/*.invalid`, `.ai-loop/planner_validation.md`,
    `.ai-loop/user_ask.md`.
18. `test_ai_loop_plan_restores_backup_on_failure` — read `ai_loop_plan.ps1`;
    assert it contains a `try { … } catch { … }` block AND a backup-restore
    code path (e.g. references both `$Out.bak` and a rename/move back to `$Out`
    inside `catch`). This is a structural smoke test, not a behavioral one.

Do NOT call `claude` or `codex` CLIs in tests.

## Verification

```bash
python -m pytest -q
```

```powershell
powershell -NoProfile -Command "[void][System.Management.Automation.Language.Parser]::ParseFile('scripts\ai_loop_plan.ps1', [ref]$null, [ref]$null)"
powershell -NoProfile -Command "[void][System.Management.Automation.Language.Parser]::ParseFile('scripts\run_claude_planner.ps1', [ref]$null, [ref]$null)"
powershell -NoProfile -Command "[void][System.Management.Automation.Language.Parser]::ParseFile('scripts\run_codex_validator.ps1', [ref]$null, [ref]$null)"
```

Manual smoke (requires authenticated `claude` and `codex` CLIs). Install into
a **fresh temp target**, not into self:
```powershell
$tmp = Join-Path $env:TEMP "ai_orch_smoke_$(Get-Random)"
New-Item -ItemType Directory -Path $tmp | Out-Null
git -C $tmp init | Out-Null
.\scripts\install_into_project.ps1 -TargetProject $tmp
Set-Location $tmp
# Verify .ai-loop/planner_prompt.md and validator_prompt.md exist after install.
# Run planner (planner-only):
.\scripts\ai_loop_plan.ps1 -Ask "Add a hello-world smoke test that prints OK" -Out .ai-loop\task_smoke.md
# Run with validator:
.\scripts\ai_loop_plan.ps1 -Ask "Add a smoke test" -WithValidator -Out .ai-loop\task_smoke.md
Get-Content .ai-loop\task_smoke.md | Select-Object -First 30
Get-Content .ai-loop\planner_validation.md
Set-Location -; Remove-Item -Recurse -Force $tmp
```

Verify also: `.\scripts\install_into_project.ps1 -TargetProject .` exits with
the self-install guard message and non-zero exit code.

## Implementer summary requirements

Update `.ai-loop/implementer_summary.md` with:

1. Changed files.
2. Test result (count only).
3. What was implemented (3–5 lines).
4. What was skipped and why.
5. Remaining risks.

## Project summary update

Update `.ai-loop/project_summary.md`:

- Architecture section: one line each for `ai_loop_plan.ps1`,
  `run_claude_planner.ps1`, `run_codex_validator.ps1`,
  `templates/planner_prompt.md`, `templates/validator_prompt.md`.
- Note: planner is **manual**, NOT part of the automated loop.
- Note: planner is architect-agnostic via `-PlannerCommand` /
  `-ValidatorCommand` (mirrors `-CursorCommand`). Default validator is Codex
  for genuine independence from Claude planner.
- Update Current Stage and Next Likely Steps.

## Output hygiene

The implementer must not:

- duplicate this task description into `.ai-loop/implementer_summary.md`
- include earlier task narrative in `.ai-loop/project_summary.md`
- write to `.ai-loop/_debug/` or `docs/archive/`
- commit or push (the orchestrator handles git)

## Important

**Spec size:** Exceeds the AGENTS.md ≤80-line policy. Allowed as a foundational
stage. Suggested implementation order so the work can be tested incrementally:
1. `templates/planner_prompt.md` + `scripts/run_claude_planner.ps1`.
2. `scripts/ai_loop_plan.ps1` without validator path, with deterministic
   `Test-TaskValidity` and full backup/restore via try/finally.
3. `templates/validator_prompt.md` + `scripts/run_codex_validator.ps1`.
4. Wire `-WithValidator` into `ai_loop_plan.ps1`.
5. Installer (self-install guard + new copies) + `.gitignore` + tests.

**Manual stage, not in loop:** `ai_loop_plan.ps1` is invoked **by the user**
before `ai_loop_task_first.ps1`. Do NOT add a call to it from
`ai_loop_task_first.ps1`.

**Architect swappability:** `ai_loop_plan.ps1` MUST never call `claude` or
`codex` directly — only through `$PlannerCommand` / `$ValidatorCommand`. A
future `run_gpt_planner.ps1` or `run_claude_validator.ps1` must drop in
without main entrypoint changes.

**Default validator is Codex** for independence from the Claude planner.
Codex is already a project dependency. Other validator wrappers can be added
later as separate tasks.

**Wrapper convention:** wrappers MUST have no `param()` block (PowerShell
pipeline binding would swallow `$input`). Mirror `run_opencode_agent.ps1`
line-for-line on that point.

**Stream separation:** wrappers MUST NOT use `2>&1`. Stdout is captured for
content; stderr must reach the console so warnings don't pollute `task.md` or
`planner_validation.md`.

**Backup restore on ANY failure:** after the rename `$Out → $Out.bak`, all
failure paths — wrapper non-zero, exception, deterministic validation fail —
must restore the backup so the current `task.md` is never silently lost. This
is structurally enforced via `try { … } catch { restore-backup } finally { … }`.

**repo_map auto-refresh is non-fatal:** if `build_repo_map.ps1` is absent or
fails, the planner proceeds with whatever `repo_map.md` exists, or none — with
a warning. This mirrors `ai_loop_task_first.ps1` behavior.

**Mandatory human review:** the planner output is a DRAFT. The user MUST
manually review `.ai-loop/task.md` before running `ai_loop_task_first.ps1`.
Deterministic validation catches structural problems; Codex validation catches
mechanical issues. Neither replaces human judgment for business logic.

**Self-install guard:** `install_into_project.ps1` MUST refuse when
`$Target == $Root`. Self-install caused Copy-Item source==destination edge
cases in the past.

**Installer note:** the installer copies prompts to `.ai-loop/`, not to a
`templates/` directory in target projects. `ai_loop_plan.ps1` reads from
`.ai-loop/planner_prompt.md` and `.ai-loop/validator_prompt.md`.

**Gitignored artifacts:** `.ai-loop/*.bak`, `.ai-loop/*.invalid`,
`.ai-loop/planner_validation.md`, `.ai-loop/user_ask.md`. `user_ask.md` is
gitignored because asks may contain private intent — force-add only if the
user wants to track it.
