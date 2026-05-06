# Task: <task name>

## Project context

Before starting, read:

- `.ai-loop/project_summary.md`
- `.ai-loop/task.md`
- `.ai-loop/cursor_summary.md` if it exists

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

## Important

Do not commit or push manually. The orchestrator handles git after Codex and Claude reviews.
