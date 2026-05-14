# Implementer summary — C02

## Changed files (C02)

- `scripts/ai_loop_task_first.ps1` — `$STABLE_PREAMBLE`, `Get-TaskScopeBlocks`, prompt = preamble + `FILES IN SCOPE:` / `FILES OUT OF SCOPE:` + full `task.md` after `TASK:`.
- `templates/task.md` — required `## Files in scope` / `## Files out of scope` sections and hard-rules note.
- `tests/test_orchestrator_validation.py` — C02 coverage (scope blocks in implementer prompt; existing harness dot-sources task-first helpers / ParseFile checks).
- `.ai-loop/project_summary.md` — design note for implementer prompt assembly.
- `.ai-loop/task.md` — working task spec under the C02 contract.

## This pass (next-implementer prompt)

- `.ai-loop/implementer_summary.md` — replaced stale cleanup/repo_map narrative with this C02-focused summary.
- `.ai-loop/repo_map.md` — `git restore --source=HEAD --staged --worktree` so it is no longer dirty; **no** committed change to map content.

## Tests

- `python -m pytest -q` → **60 passed** (~1.4s).

## PowerShell parser check (`scripts\ai_loop_task_first.ps1`)

- Covered by `tests/test_orchestrator_validation.py` (ParseFile / parse-cleanly tests); passes with the suite above. Manual check per `AGENTS.md`:

  `powershell -NoProfile -Command "[void][System.Management.Automation.Language.Parser]::ParseFile('scripts\ai_loop_task_first.ps1', [ref]$null, [ref]$null)"`

## Implementer prompt ordering

- As built in `Invoke-ImplementerImplementation`: **`$STABLE_PREAMBLE`**, then **`FILES IN SCOPE:`** (when present in `task.md`), then **`FILES OUT OF SCOPE:`**, then **`TASK:`** plus full `task.md` body; written to `.ai-loop/_debug/implementer_prompt.md` when task-first runs the implementer.

## Task-specific command

- `powershell -ExecutionPolicy Bypass -File .\scripts\ai_loop_task_first.ps1 -NoPush` — **not run** on this pass (would invoke the live implementer/review chain; scope here was documentation + repo_map hygiene only). Behavior is exercised by unit tests.

## Skipped

- Live task-first / implementer run — see above.
- Regenerating `.ai-loop/repo_map.md` — out of scope for C02; file reset to `HEAD` only.

## Remaining risks

- Legacy `task.md` files without scope sections still run with `Write-Warning` only (soft contract).
- Prompt byte-stability for KV-cache applies to the static preamble; the scope blocks and full `task.md` body still vary per task.
