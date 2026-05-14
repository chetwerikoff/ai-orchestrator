# C07 — Claude task planner: plan_task.py + ai_loop_plan_with_claude.ps1

**Project:** `ai-orchestrator`
**CWD:** `C:\Users\che\Documents\Projects\ai-orchestrator`
**Risk:** medium — new scripts + API dependency + install contract change.

How to run:
```powershell
# Paste task spec below into .ai-loop\task.md, then:
powershell -ExecutionPolicy Bypass -File .\scripts\ai_loop_task_first.ps1 -NoPush
```

---

# Task: Claude task planner

## Project context

Required reading before starting (in order; stop when you have enough):

1. `AGENTS.md` at repo root — working rules and forbidden paths
2. `.ai-loop/task.md` — this task
3. `.ai-loop/project_summary.md` — durable project orientation
4. `.ai-loop/repo_map.md` — file index
5. `.ai-loop/implementer_summary.md` — only if this is iteration 2+

Do not read by default:

- `docs/archive/` — superseded design documents
- `.ai-loop/_debug/` — raw agent stdout, debug-only

## Goal

Create two new scripts that let a user describe a task in natural language and
get a properly formatted `.ai-loop/task.md` back from Claude:

1. `scripts/plan_task.py` — Python script that reads project context, calls
   the Claude API (claude-sonnet-4-6), and writes `.ai-loop/task.md`.
2. `scripts/ai_loop_plan_with_claude.ps1` — thin PowerShell wrapper that
   validates prerequisites and invokes `plan_task.py`.

Update `scripts/install_into_project.ps1` so both files are copied into target
projects. Add tests pinning the new scripts' existence and basic structure.

## Scope

Allowed:
- Create `scripts/plan_task.py`
- Create `scripts/ai_loop_plan_with_claude.ps1`
- Edit `scripts/install_into_project.ps1` (add two copy lines)
- Edit `tests/test_orchestrator_validation.py` (add tests)
- Edit `AGENTS.md` — add `scripts/plan_task.py` to Never-edit list

Not allowed:
- Any changes to `scripts/ai_loop_auto.ps1`, `scripts/ai_loop_task_first.ps1`,
  `scripts/continue_ai_loop.ps1`
- Changes to `templates/` or other docs
- Changes to `src/`, `ai_loop.py`

## Files in scope

- `scripts/plan_task.py` (new)
- `scripts/ai_loop_plan_with_claude.ps1` (new)
- `scripts/install_into_project.ps1` (edit — add copy lines)
- `tests/test_orchestrator_validation.py` (edit — add tests)
- `AGENTS.md` (edit — Never-edit list)

## Files out of scope

- `scripts/ai_loop_auto.ps1`
- `scripts/ai_loop_task_first.ps1`
- `scripts/continue_ai_loop.ps1`
- `docs/archive/**`
- `.ai-loop/_debug/**`
- `ai_loop.py`
- `templates/**`

## Required behavior

### scripts/plan_task.py

CLI interface:
```
python scripts/plan_task.py --ask "TEXT" [--out .ai-loop/task.md] [--force]
```

- `--ask TEXT` — user's natural language task description. Required unless
  `.ai-loop/user_ask.md` exists (fallback: read that file).
- `--out PATH` — output path (default: `.ai-loop/task.md`).
- `--force` — overwrite without backup. Without this flag, if the output file
  exists it is backed up to `<out>.bak` before overwriting.

Context Claude receives (in this order, with prompt caching on the context block):

1. Contents of `AGENTS.md` (working rules + scope).
2. Contents of `.ai-loop/project_summary.md` (project orientation).
3. First 120 lines of `.ai-loop/repo_map.md` if the file exists (file index).
4. Contents of `templates/task.md` stripped of the HTML comment header (output format reference).

Then the user ask is appended as the non-cached final message.

Claude's system prompt instructs it to:
- Output ONLY the filled task.md content (no preamble, no explanation).
- Follow the template format exactly: all required sections present.
- Keep the task to ≤80 lines of code change (per AGENTS.md task size policy).
- Use concrete file paths from repo_map where relevant.
- Not invent behavior not implied by the ask and context.

API call:
- Model: `claude-sonnet-4-6`
- API key: from `ANTHROPIC_API_KEY` environment variable. Exit with clear error
  if unset.
- Use the `anthropic` Python SDK.
- Apply `cache_control={"type": "ephemeral"}` to the project context block
  (the combined AGENTS.md + project_summary + repo_map + template content)
  so repeated planner calls within a session hit the cache.
- `max_tokens`: 2048.

Error handling:
- Missing `ANTHROPIC_API_KEY` → print actionable message and exit 1.
- Missing `AGENTS.md` or `project_summary.md` → print which file is missing and exit 1.
- API error → print error and exit 1.
- On success → print the output path.

### scripts/ai_loop_plan_with_claude.ps1

```
.\scripts\ai_loop_plan_with_claude.ps1 [-Ask "TEXT"] [-Out ".ai-loop\task.md"] [-Force]
```

- Checks that `ANTHROPIC_API_KEY` env var is set; exits with message if not.
- Checks that `scripts/plan_task.py` exists; exits if not.
- Invokes `python scripts\plan_task.py` forwarding `-Ask`, `-Out`, `-Force`.
- On exit code 0: prints path of the written file and reminder to review before
  running `ai_loop_task_first.ps1`.
- On non-zero exit: prints the error and exits with the same code.

### scripts/install_into_project.ps1

Add copy lines for `scripts/plan_task.py` and
`scripts/ai_loop_plan_with_claude.ps1` alongside the existing script copies.
Follow the existing pattern (Copy-Item with `-Force`, same destination layout).

### AGENTS.md

Add `scripts/plan_task.py` to the "Never edit" list (managed by ai-orchestrator;
reinstall via `install_into_project.ps1`).

## Tests

Run:

```bash
python -m pytest -q
```

Add to `tests/test_orchestrator_validation.py`:

1. `test_plan_task_script_exists` — assert `scripts/plan_task.py` is a file.
2. `test_plan_task_has_required_args` — read `plan_task.py` text; assert it
   contains `--ask`, `--out`, `--force`, `ANTHROPIC_API_KEY`,
   `claude-sonnet-4-6`, `cache_control`.
3. `test_ai_loop_plan_ps1_parses_cleanly` — PowerShell `Parser::ParseFile`
   check for `ai_loop_plan_with_claude.ps1` (same pattern as existing parse tests).
4. `test_install_copies_plan_task_scripts` — read `install_into_project.ps1`
   text; assert it contains `plan_task.py` and `ai_loop_plan_with_claude.ps1`.

Do NOT call the Claude API in tests.

## Verification

```bash
python -m pytest -q
```

```powershell
powershell -NoProfile -Command "[void][System.Management.Automation.Language.Parser]::ParseFile('scripts\ai_loop_plan_with_claude.ps1', [ref]$null, [ref]$null)"
```

Manual smoke (requires `ANTHROPIC_API_KEY` set):
```bash
python scripts/plan_task.py --ask "Add a hello-world smoke test that prints OK" --out .ai-loop/task_smoke.md
```
Verify `.ai-loop/task_smoke.md` contains all required template sections and
delete it after inspection.

## Implementer summary requirements

Update `.ai-loop/implementer_summary.md` with:

1. Changed files.
2. Test result (count only).
3. What was implemented (3–5 lines).
4. What was skipped and why.
5. Remaining risks.

## Project summary update

Update `.ai-loop/project_summary.md`:

- Add `scripts/plan_task.py` and `scripts/ai_loop_plan_with_claude.ps1` to the
  Architecture section (one line each).
- Update Current Stage to reflect that the Claude planner is available.
- Update Next Likely Steps.

## Output hygiene

The implementer must not:

- duplicate this task description into `.ai-loop/implementer_summary.md`
- include earlier task narrative in `.ai-loop/project_summary.md`
- write to `.ai-loop/_debug/` or `docs/archive/`
- commit or push (the orchestrator handles git)

## Important

- Do not call the Claude API in tests — test only structure and arguments.
- `plan_task.py` is a new script installed into target projects; it must work
  from the target project's CWD (paths relative to CWD, not to script location).
- The backup (`task.md.bak`) must not be staged by the orchestrator — it is not
  in `SafeAddPaths`.
- Keep `plan_task.py` under 120 lines total (including imports and docstring).
