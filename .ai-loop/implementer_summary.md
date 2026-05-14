# Implementer summary

## Changed files

- `scripts/install_into_project.ps1` — copies `scripts/run_scout_pass.ps1` into the target `scripts/` directory with the other orchestrator wrappers (enables `-WithScout` on installed projects).
- `tests/test_orchestrator_validation.py` — added `test_install_into_project_copies_run_scout_pass_script` asserting the installer references `run_scout_pass.ps1` and the source script exists.

## Tests

- `python -m pytest -q` — **66 passed**.

## Implementation (this fix pass)

- Ensures installs ship `run_scout_pass.ps1` beside `ai_loop_task_first.ps1` so relative `Join-Path $PSScriptRoot run_scout_pass.ps1` resolves in target repos using DD-022 scout.

## Task-specific outputs / skipped live run

- `.ai-loop/task.md` verification (`powershell … ai_loop_task_first.ps1 -NoPush`) **not run** — full implementer/agents invocation is out of scope for this installer-focused fix pass.

## Remaining risks

- Targets installed **before** this installer change lack `run_scout_pass.ps1` until reinstall or manual copy.
- Scout runtime risks unchanged (latency, malformed JSON, non-fatal warnings).
