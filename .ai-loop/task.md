# Task: Add order field and task queue save to planner

## Project context

- `AGENTS.md`
- `.ai-loop/task.md` (this file)
- `.ai-loop/project_summary.md`
- `.ai-loop/repo_map.md`

## Goal

Extend the planner output format with an optional `## Order` section. When `ai_loop_plan.ps1` writes `.ai-loop/task.md` and finds a positive integer in `## Order`, it copies the file to `tasks/NNN_slug.md` (zero-padded, slug derived from the `# Task:` line). When `## Order` is absent or blank the script behaves exactly as before. The planner prompt is updated so Claude knows when and how to emit the field, allowing a series of related tasks to be queued without altering the auto-loop runtime.

## Scope

Allowed:
- Add `## Order` section to the task template and planner prompt
- Add post-generation queue-save logic to `ai_loop_plan.ps1`
- Add tests for order parsing and slug derivation
- Create `tasks/` directory if it does not exist (non-fatal)

Not allowed:
- Changing any orchestrator runtime scripts (`ai_loop_auto.ps1`, `ai_loop_task_first.ps1`, `continue_ai_loop.ps1`)
- Changing `SafeAddPaths` in any script or `docs/safety.md`
- Generating automatic prerequisite lists
- Modifying `scripts/install_into_project.ps1` (it already copies both touched templates)
- Touching `ai_loop.py`

## Files in scope

- `templates/task.md`  add `## Order` section (optional, last section)
- `templates/planner_prompt.md`  add `## Order` to the Output format list with usage rules
- `scripts/ai_loop_plan.ps1`  add queue-save block after the final task write (Ôëñ 18 lines)
- `tests/test_orchestrator_validation.py`  add order-parsing and slug-derivation tests

## Files out of scope

- `docs/archive/**`
- `.ai-loop/_debug/**`
- `ai_loop.py`
- `scripts/ai_loop_auto.ps1`
- `scripts/ai_loop_task_first.ps1`
- `scripts/continue_ai_loop.ps1`
- `scripts/install_into_project.ps1`
- `docs/safety.md`

## Required behavior

1. **`templates/task.md`**: append a final `## Order` section with a one-line comment describing it as optional; default content is blank so existing tasks are unaffected.
2. **`templates/planner_prompt.md`**: in the `## Output format` bullet list, add `## Order` as the last item. Rules for the planner: omit or leave blank for standalone tasks; for a series, set consecutive integers starting at 1; lower numbers run first; each task in a series must be self-contained (no cross-task variable references).
3. **`scripts/ai_loop_plan.ps1`** ÔÇö after the line that writes the final `.ai-loop/task.md` (end of the review loop or direct write):
   - Read the written task file.
   - Match `(?m)^##\s+Order\s*\r?\n\s*(\d+)` against its content.
   - If matched and the captured integer `$N` is ÔëÑ 1:
     - Extract the short name from `# Task: <short name>` (first line of file).
     - Derive slug: lowercase, collapse any run of non-alphanumeric chars to a single underscore, strip leading/trailing underscores, truncate at 40 chars.
     - Compute `$dest = "tasks/{0:000}_{1}.md" -f $N, $slug` relative to the repo root (`Split-Path $PSScriptRoot -Parent`).
     - Create the `tasks/` directory if absent (non-fatal `New-Item -Force -ItemType Directory`).
     - If `$dest` already exists, emit `Write-Warning "Overwriting queue file: $dest"`.
     - Copy the task file to `$dest` with `-Force`.
     - Emit `Write-Host "Queue: $dest"`.
   - If match fails or capture is not a positive integer, skip silently.
   - Queue save errors must not set exit code; wrap in `try/catch` with `Write-Warning`.
4. Behavior when `## Order` is absent or blank: no `tasks/` write, no warning, identical to current behavior.
5. The `tasks/` path used is always relative to the repo root (the directory containing `scripts/`), not the caller's working directory.
6. The write to `.ai-loop/task.md` always occurs first (normal planner behavior, unchanged). The `tasks/NNN_slug.md` write is an additional copy made immediately after; both destinations receive identical content. The planner's primary output contract ÔÇö writing `.ai-loop/task.md` ÔÇö is not altered.

## Tests

Add to `tests/test_orchestrator_validation.py`:

- `test_order_regex_match`: verify the PS-equivalent Python regex `r'(?m)^##\s+Order\s*\r?\n\s*(\d+)'` matches a task string with `## Order\n2` and captures `"2"`; verify it does not match when the section is blank or absent.
- `test_order_slug_derivation`: verify slug logic (lowercase, non-alnumÔåÆunderscore, collapse, strip, truncate) for representative inputs: `"Fix Dashboard Generation"` ÔåÆ `"fix_dashboard_generation"`, `"Add order/queue support!"` ÔåÆ `"add_order_queue_support"`, a 60-char name truncates to Ôëñ 40 chars.
- `test_order_queue_filename_format`: verify `"{0:000}_{1}.md".format(3, "fix_x")` ÔåÆ `"003_fix_x.md"` (documents the naming contract).
- Do **not** add a subprocess integration test for the full `ai_loop_plan.ps1` queue-save path in this task (requires a live planner CLI mock; defer to a follow-up task if needed).

Run: `python -m pytest -q`

## Verification

```powershell
# 1. Parse check for the modified script
powershell -NoProfile -Command "[void][System.Management.Automation.Language.Parser]::ParseFile('scripts\ai_loop_plan.ps1', [ref]`$null, [ref]`$null)"

# 2. Unit tests
python -m pytest -q

# 3. Manual smoke: confirm ## Order section appears in templates/task.md
Select-String -Path templates\task.md -Pattern '^## Order'

# 4. Manual smoke: confirm planner prompt mentions ## Order
Select-String -Path templates\planner_prompt.md -Pattern 'Order'
```

## Implementer summary requirements

1. List every file changed with one-line description of what changed.
2. State regex used for order parsing and slug derivation.
3. Report test count and pass/fail result.
4. Note any edge cases handled beyond the spec (or "none").
5. List any remaining risks (e.g., `tasks/` not in `SafeAddPaths` ÔÇö queue files not auto-committed).

## Project summary update

Record: "C10: `## Order` section added to task template and planner prompt. `ai_loop_plan.ps1` saves numbered queue copies to `tasks/NNN_slug.md` when order is set. Non-fatal; auto-loop unaffected. `tasks/` is not currently in `SafeAddPaths` ÔÇö queue files are written but not auto-committed; a follow-up task is needed to extend `SafeAddPaths` if auto-commit of queue files is desired."

## Output hygiene

- Do not duplicate task content into `implementer_summary.md` (summary only).
- Do not write to `.ai-loop/_debug/` unless debugging raw output.
- Do not `git commit` or `git push`.
- Do not write to `docs/archive/`.

## Important

**Architect notes ÔÇö divergences from user's proposed implementation and reviewer rejections:**

1. **No automatic prerequisites list.** The user proposed: "if order > 1, list prerequisite tasks in the file." Dropped. Generating a correct prerequisites list requires tracking what the NÔêÆ1 task was named after slug derivation, which couples tasks at write time and adds ~30 lines with fragile state. The ordering itself (001 before 002) is the prerequisite signal; human operators read `ls tasks/`. A future task can add a `## Prerequisites` section if the need becomes concrete.

2. **`## Order` is a markdown section, not a frontmatter key.** The user wrote `order=3` style. Using a section header is consistent with every other section in `task.md` and requires no YAML/TOML parser. The regex `(?m)^## Order\n\s*(\d+)` is unambiguous.

3. **Order 1 also saves to `tasks/`.** Any task with `## Order` set (including 1) is a "series" task and gets queued. Omitting the section entirely is the signal for a standalone task. This is simpler than a special-case for N=1.

4. **`tasks/` is not in `SafeAddPaths`.** Confirmed by reading the literal in `AGENTS.md`: `src/,tests/,README.md,AGENTS.md,scripts/,docs/,templates/,ai_loop.py,pytest.ini,.gitignore,requirements.txt,pyproject.toml,setup.cfg,pyrightconfig.json,.ai-loop/task.md,.ai-loop/implementer_summary.md,.ai-loop/project_summary.md,.ai-loop/repo_map.md,.ai-loop/failures.md,.ai-loop/archive/rolls/,.ai-loop/_debug/session_draft.md` ÔÇö `tasks/` does not appear. Adding it requires updating three PS1 scripts and `docs/safety.md` in sync ÔÇö a separate ~80-line task per the AGENTS.md templates contract. Queue files written to `tasks/` will exist on disk but will not be auto-committed by the orchestrator until `SafeAddPaths` is extended.

5. **Assumption: repo root is `(Split-Path $PSScriptRoot -Parent)` from within `scripts/ai_loop_plan.ps1`.** The existing script already uses `$PSScriptRoot` for relative paths, so this is consistent with the current pattern.

6. **`install_into_project.ps1` needs no changes** because it already copies `templates/task.md` and `templates/planner_prompt.md` verbatim; the template edits propagate on next reinstall automatically.

7. **Architect note: rejected logic:step-3-contradiction** ÔÇö The reviewer claims steps 3 and 6 contradict the ASK by writing `.ai-loop/task.md` before the queue save. There is no contradiction: `.ai-loop/task.md` is the planner's normal primary output (unchanged behavior); `tasks/NNN_slug.md` is an additional copy made immediately after. Both destinations receive identical content. Step 6 in `## Required behavior` was added explicitly to document this dual-write and eliminate ambiguity. The USER ASK does not say the task should *only* go to `tasks/` ÔÇö it says the planner should "save to `tasks/`"; writing to both locations fulfils that requirement while preserving the existing contract.

8. **Architect note: rejected logic:safepath-claim** ÔÇö The reviewer asserts "`tasks/` is in the default `SafeAddPaths` literal." This is factually incorrect. The literal in `AGENTS.md` does not include `tasks/`. The project summary update statement is therefore accurate as written.

9. **Architect note: rejected missing:prerequisites** ÔÇö The reviewer re-raises the prerequisite list requirement already deliberated in note #1. The decision stands: generating prerequisites at write time requires fragile cross-task state tracking and contradicts the simplicity policy (AGENTS.md). The numeric filename prefix is the ordering signal.
