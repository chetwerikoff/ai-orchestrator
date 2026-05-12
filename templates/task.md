# Task: <task name>

## Project context

Required reading before starting (in order; stop when you have enough):

1. `AGENTS.md` at repo root — working rules and forbidden paths
2. `.ai-loop/task.md` — this task
3. `.ai-loop/project_summary.md` — durable project orientation
4. `.ai-loop/cursor_summary.md` — only if this is iteration 2+

Do not read by default:

- `docs/archive/` — superseded design documents
- `.ai-loop/archive/` — historical task rolls
- `.ai-loop/_debug/` — raw agent stdout, debug-only

## Goal

Describe the exact task.

## Scope

Allowed:
- ...

Not allowed:
- ...

## Files likely to change

- `src/...`
- `tests/...`
- `README.md`

## Required behavior

1. ...
2. ...
3. ...

## Tests

Run:

```bash
python -m pytest
```

Add or update tests for:

1. ...
2. ...

## Verification

Run:

```bash
python -m pytest
```

Optional project-specific command:

```bash
<command>
```

## Cursor summary requirements

Update `.ai-loop/cursor_summary.md` with:

1. Changed files.
2. Test result.
3. What was implemented.
4. What was skipped and why.
5. Remaining risks.

## Project summary update

After completing the task, update:

- `.ai-loop/project_summary.md`

Update it only with durable project-level information:

- new architecture decisions;
- new modules/components;
- changed pipeline;
- important risks;
- current stage;
- next likely steps.

Do not turn it into a verbose task log.

## Output hygiene

The implementer must not:

- duplicate this task description into `.ai-loop/cursor_summary.md`
- include earlier task narrative in `.ai-loop/project_summary.md`
- write to `.ai-loop/_debug/` or `docs/archive/`
- commit or push (the orchestrator handles git)

## Important

Do not commit or push manually. The orchestrator handles git after Codex passes and the final test gate.
