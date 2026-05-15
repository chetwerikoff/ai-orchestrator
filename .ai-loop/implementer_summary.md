# Implementer summary

## Changed files

- `scripts/run_claude_reviewer.ps1` — created (stdin prompt, `--model` parse, default `claude-haiku-4-5-20251001`, `claude --print`).
- `templates/claude_task_reviewer_prompt.md` — created (architecture reviewer strict output rules).
- `scripts/ai_loop_plan.ps1` — `-NoRevision`, Claude reviewer prompt resolution, lighter reviewer bundle when `-NoRevision`, blocking path `exit 2`, dot-source early return for tests, extended strict categories.
- `scripts/install_into_project.ps1` — copies `claude_task_reviewer_prompt.md` into `.ai-loop/`.
- `tests/test_claude_reviewer.py` — created.
- `tests/test_orchestrator_validation.py` — strict-format mirror + parse smoke list + install assert + review invariants (collateral for green full suite).
- `docs/workflow.md` — variant A usage note.
- `.ai-loop/project_summary.md` — current architecture / templates / installer line updates.

## Test-ReviewerOutputStrict regex (one-liners)

- **Before:** `'^\s*-\s*\[(logic|complexity|scope|missing)\]\s+\S'`
- **After:** `'^\s*-\s*\[(logic|complexity|scope|missing|architecture|safety)\]\s+\S'`

## Lighter reviewer context (`-NoRevision`)

In `scripts/ai_loop_plan.ps1`, inside the `for` review loop (~lines 248–259): `if ($NoRevision)` builds `$reviewPrompt` from reviewer template + `## AGENTS.md` + body + `## Project Summary` + summary body + `## Raw User ASK` + ask + `## Draft task.md` + draft; the `else` branch keeps the existing bundle including `## repo_map.md` and `## GENERATED task.md`.

## `run_claude_reviewer.ps1` default model

Confirmed: `claude-haiku-4-5-20251001`.

## `install_into_project.ps1`

Confirmed: `Copy-Item` from `templates\claude_task_reviewer_prompt.md` to `(Join-Path $TargetAiLoop "claude_task_reviewer_prompt.md")`.

## Tests

- `python -m pytest -q tests/test_claude_reviewer.py` — **5 passed**.
- `python -m pytest -q` — **151 passed** (1 PytestCacheWarning on Windows nodeids path).

Task verification parses: covered via `Parser::ParseFile` in tests; direct `powershell -NoProfile -Command ParseFile(...)` not re-run here (environment rejected that invocation); parse errors would have failed the new smoke test.

## Remaining risks (variant B: auto-revision)

- A future revision loop with Claude reviewer must decide whether blocking semantics stay human-only or merge with planner revision prompts without contradicting variant A’s `exit 2` contract.
- Sharing one strict output schema across Codex and Claude remains necessary; new categories should stay additive to avoid breaking saved traces.
