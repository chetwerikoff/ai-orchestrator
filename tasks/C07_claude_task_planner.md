# C07 — Task planner with swappable architect wrappers

**Project:** `ai-orchestrator`
**CWD:** `C:\Users\che\Documents\Projects\ai-orchestrator`
**Risk:** medium — three new scripts + install contract change.

How to run:
```powershell
# Paste task spec below into .ai-loop\task.md, then:
powershell -ExecutionPolicy Bypass -File .\scripts\ai_loop_task_first.ps1 -NoPush
```

---

# Task: Architect-agnostic task planner

## Project context

Required reading before starting (in order; stop when you have enough):

1. `AGENTS.md` at repo root — working rules and forbidden paths
2. `.ai-loop/task.md` — this task
3. `.ai-loop/project_summary.md` — durable project orientation
4. `.ai-loop/repo_map.md` — file index
5. `scripts/ai_loop_task_first.ps1` — existing implementer-prompt assembly pattern to mirror
6. `scripts/run_cursor_agent.ps1`, `scripts/run_opencode_agent.ps1` — existing wrapper convention
7. `.ai-loop/implementer_summary.md` — only if this is iteration 2+

Do not read by default:

- `docs/archive/` — superseded design documents
- `.ai-loop/_debug/` — raw agent stdout, debug-only

## Goal

Add a planner stage that produces `.ai-loop/task.md` from a natural-language ask,
using the **same wrapper pattern already used for implementers**:

```
ai_loop_plan.ps1 -PlannerCommand .\scripts\run_claude_planner.ps1
```

Architect can be swapped by writing a new wrapper (`run_gpt_planner.ps1`, etc.).
The main entrypoint is architect-agnostic.

Deliverables:

1. `scripts/ai_loop_plan.ps1` — main entrypoint. Builds the planner prompt
   (context + format reference + user ask), pipes it to the wrapper, captures
   stdout, writes `.ai-loop/task.md`.
2. `scripts/run_claude_planner.ps1` — Claude wrapper. Reads prompt from stdin,
   invokes `claude --print` non-interactively, returns stdout.
3. `templates/planner_prompt.md` — system instructions for the planner role
   (architect-agnostic). Read once by `ai_loop_plan.ps1` and embedded in the prompt.

Update `scripts/install_into_project.ps1` to copy all three files into target
projects. Update `AGENTS.md` Never-edit list. Add tests.

## Scope

Allowed:
- Create `scripts/ai_loop_plan.ps1`
- Create `scripts/run_claude_planner.ps1`
- Create `templates/planner_prompt.md`
- Edit `scripts/install_into_project.ps1` (add three copy lines)
- Edit `tests/test_orchestrator_validation.py` (add tests)
- Edit `AGENTS.md` (Never-edit list, safe-paths note if needed)

Not allowed:
- Any changes to `scripts/ai_loop_auto.ps1`, `scripts/ai_loop_task_first.ps1`,
  `scripts/continue_ai_loop.ps1`
- Changes to existing implementer wrappers (`run_cursor_agent.ps1`,
  `run_opencode_agent.ps1`, `run_opencode_scout.ps1`)
- Changes to other templates, `src/`, `ai_loop.py`, docs

## Files in scope

- `scripts/ai_loop_plan.ps1` (new)
- `scripts/run_claude_planner.ps1` (new)
- `templates/planner_prompt.md` (new)
- `scripts/install_into_project.ps1` (edit)
- `tests/test_orchestrator_validation.py` (edit)
- `AGENTS.md` (edit)

## Files out of scope

- `scripts/ai_loop_auto.ps1`
- `scripts/ai_loop_task_first.ps1`
- `scripts/continue_ai_loop.ps1`
- `scripts/run_cursor_agent.ps1`
- `scripts/run_opencode_agent.ps1`
- `scripts/run_opencode_scout.ps1`
- `scripts/run_scout_pass.ps1`
- `docs/archive/**`
- `.ai-loop/_debug/**`
- `ai_loop.py`

## Required behavior

### scripts/ai_loop_plan.ps1

Parameters:
```powershell
param(
    [string]$Ask = "",
    [string]$PlannerCommand = ".\scripts\run_claude_planner.ps1",
    [string]$PlannerModel = "",
    [string]$Out = ".ai-loop\task.md",
    [string]$AskFile = ".ai-loop\user_ask.md",
    [switch]$Force
)
```

Logic:

1. Resolve user ask: prefer `-Ask`; if empty, read `$AskFile`; if both empty/missing,
   exit 1 with clear message.
2. Validate prerequisites (`AGENTS.md`, `.ai-loop/project_summary.md`,
   `templates/planner_prompt.md` exist; exit 1 with which is missing if not).
3. Validate `$PlannerCommand` exists (mirror `Assert-CommandExists` pattern from
   `ai_loop_task_first.ps1`).
4. Build the planner prompt by concatenating, in order:
   - Contents of `templates/planner_prompt.md` (system instructions + format).
   - Header line `## AGENTS.md` followed by contents of `AGENTS.md`.
   - Header line `## project_summary.md` followed by contents of
     `.ai-loop/project_summary.md`.
   - Header line `## repo_map.md (excerpt)` followed by first 120 lines of
     `.ai-loop/repo_map.md` if it exists.
   - Header line `## USER ASK` followed by the resolved ask.
5. If `$Out` exists and `-Force` is not set: rename it to `$Out.bak` (overwriting
   any prior `.bak`).
6. Pipe the prompt to the wrapper:
   `$prompt | & $PlannerCommand --workspace $ProjectRoot --model $PlannerModel`
   Capture stdout.
7. Validate response: must contain at least the headings `## Goal`,
   `## Files in scope`, `## Files out of scope` (warn if missing, do not fail).
8. Write captured stdout to `$Out` (UTF-8 no BOM).
9. Print: `Wrote $Out. Review before running ai_loop_task_first.ps1.`

Exit codes: 0 on success; 1 on missing prerequisites or wrapper error.

### scripts/run_claude_planner.ps1

Mirrors `run_opencode_agent.ps1` structure: no `param()` block; reads piped
prompt from `$input`; parses `--workspace` and `--model` from `$args`; silently
ignores other flags.

Logic:

1. Read prompt from `$input` into a single string. Empty → `Write-Error` + exit 1.
2. Resolve `--workspace` (optional, used as cwd) and `--model` (default
   `claude-sonnet-4-6`).
3. Push-Location to workspace if given.
4. Invoke `claude --print --model $model` (non-interactive). Pass the prompt via
   stdin. Capture stdout (returned as-is to caller). `2>&1` so stderr surfaces.
5. Pop-Location in `finally`.
6. `exit $LASTEXITCODE`.

Exit codes: forwarded from `claude` CLI.

### templates/planner_prompt.md

A markdown file with these sections (no HTML comments at top — those belong to
the task template, not the planner instructions):

```markdown
# Planner role

You are the PLANNER. Output **only** the contents of `.ai-loop/task.md` for the
user ask below — no preamble, no explanation, no code fences around the whole
output.

## Output format (mandatory)

Produce a markdown document with these headings, in order:

- `# Task: <short name>`
- `## Project context` — required reading list (point to AGENTS.md, task.md,
  project_summary.md; iteration-2+ note for implementer_summary.md)
- `## Goal` — one paragraph, concrete
- `## Scope` — Allowed / Not allowed bullets
- `## Files in scope` — concrete relative paths only
- `## Files out of scope` — concrete paths (include `docs/archive/**`,
  `.ai-loop/_debug/**`, `ai_loop.py`)
- `## Required behavior` — numbered steps
- `## Tests` — what to add/update; the command `python -m pytest -q`
- `## Verification` — concrete commands
- `## Implementer summary requirements` — five-point list
- `## Project summary update` — what durable info to add, if any
- `## Output hygiene` — standard four bullets (no duplication, no debug, no
  commit, no archive writes)
- `## Important` — task-specific gotchas

## Hard rules

- Keep the implementation under 80 lines of code change (per AGENTS.md task
  size policy). If the ask is larger, split into ordered subtasks in `## Important`.
- Do not invent file paths. Use only paths visible in the provided project
  context (AGENTS.md scope, repo_map excerpt).
- Do not ask the user questions. Make reasonable choices and call them out in
  `## Important`.
- Do not output `<!-- ... -->` HTML comments.
- Do not write anything before `# Task:` or after `## Important`.
```

### scripts/install_into_project.ps1

Add `Copy-Item -Force` lines for `scripts/ai_loop_plan.ps1`,
`scripts/run_claude_planner.ps1`, `templates/planner_prompt.md`. Place them
near the existing script/template copies, in alphabetical order if the file
already groups by directory.

### AGENTS.md

Add to "Never edit" list:
- `scripts/run_claude_planner.ps1`
- (`scripts/ai_loop_plan.ps1` is editable from this repo — it is one of the
  orchestrator scripts; only add the wrapper to Never-edit so target projects
  do not modify it.)

Add a one-line note under "## Commands" or near it pointing at the new entrypoint:
`Plan: powershell -File .\scripts\ai_loop_plan.ps1 -Ask "..."`

## Tests

Run:

```bash
python -m pytest -q
```

Add to `tests/test_orchestrator_validation.py`:

1. `test_ai_loop_plan_script_exists` — assert `scripts/ai_loop_plan.ps1` exists.
2. `test_run_claude_planner_script_exists` — assert
   `scripts/run_claude_planner.ps1` exists.
3. `test_planner_prompt_template_exists` — assert
   `templates/planner_prompt.md` exists.
4. `test_planner_scripts_parse_cleanly` — extend the existing PowerShell
   `Parser::ParseFile` test list with the two new `.ps1` files.
5. `test_ai_loop_plan_accepts_required_parameters` — read
   `ai_loop_plan.ps1` text; assert it declares `$Ask`, `$PlannerCommand`,
   `$PlannerModel`, `$Out`, `$AskFile`, `$Force`.
6. `test_run_claude_planner_uses_claude_print` — read
   `run_claude_planner.ps1`; assert it contains the `claude` invocation with
   `--print` and `--model` handling, and has no `param()` block (matches
   wrapper convention).
7. `test_planner_prompt_has_required_sections` — read
   `templates/planner_prompt.md`; assert it contains `# Planner role`,
   `## Output format`, `## Hard rules`.
8. `test_install_copies_planner_files` — read `install_into_project.ps1`;
   assert it copies `ai_loop_plan.ps1`, `run_claude_planner.ps1`,
   `planner_prompt.md`.

Do NOT call the `claude` CLI in tests.

## Verification

```bash
python -m pytest -q
```

```powershell
powershell -NoProfile -Command "[void][System.Management.Automation.Language.Parser]::ParseFile('scripts\ai_loop_plan.ps1', [ref]$null, [ref]$null)"
powershell -NoProfile -Command "[void][System.Management.Automation.Language.Parser]::ParseFile('scripts\run_claude_planner.ps1', [ref]$null, [ref]$null)"
```

Manual smoke (requires `claude` CLI authenticated):
```powershell
.\scripts\ai_loop_plan.ps1 -Ask "Add a hello-world smoke test that prints OK" -Out .ai-loop\task_smoke.md
```
Verify `.ai-loop\task_smoke.md` contains the required sections, then delete it.

## Implementer summary requirements

Update `.ai-loop/implementer_summary.md` with:

1. Changed files.
2. Test result (count only).
3. What was implemented (3–5 lines).
4. What was skipped and why.
5. Remaining risks.

## Project summary update

Update `.ai-loop/project_summary.md`:

- Add `scripts/ai_loop_plan.ps1` and `scripts/run_claude_planner.ps1` and
  `templates/planner_prompt.md` to the Architecture section (one line each).
- Mention the wrapper pattern: planner is swappable via `-PlannerCommand`,
  mirroring `-CursorCommand` for implementers.
- Update Current Stage.
- Update Next Likely Steps (e.g. add wrappers for other architects later).

## Output hygiene

The implementer must not:

- duplicate this task description into `.ai-loop/implementer_summary.md`
- include earlier task narrative in `.ai-loop/project_summary.md`
- write to `.ai-loop/_debug/` or `docs/archive/`
- commit or push (the orchestrator handles git)

## Important

- `ai_loop_plan.ps1` is invoked **manually by the user** before
  `ai_loop_task_first.ps1`. It is NOT part of the automated loop. Do not
  add a call to it from `ai_loop_task_first.ps1`.
- The planner is **architect-agnostic**. `ai_loop_plan.ps1` must never call
  `claude` directly — only through `$PlannerCommand`. A future
  `run_gpt_planner.ps1` or `run_local_planner.ps1` must work as a drop-in
  replacement without changes to the main entrypoint.
- The wrapper convention requires **no `param()` block** in
  `run_claude_planner.ps1` so PowerShell pipeline binding does not consume
  `$input`. Mirror `run_opencode_agent.ps1` exactly on this point.
- `.bak` file from the backup step must not be staged. Verify after the run
  that `SafeAddPaths` does not include `*.bak` (it should not — no change needed).
- `task.md` written by the planner replaces `.ai-loop/task.md`. The user is
  expected to review it before running `ai_loop_task_first.ps1`.
- Keep `ai_loop_plan.ps1` under 120 lines, `run_claude_planner.ps1` under 50.
