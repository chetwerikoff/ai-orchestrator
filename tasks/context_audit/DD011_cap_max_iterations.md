# DD-011 — Cap default MaxIterations: 10 → 3

**Project:** `ai-git-orchestrator`
**CWD:** `C:\Users\che\Documents\Projects\ai-git-orchestrator`
**Prerequisite:** O01–O06 merged.
**Risk:** low — one-line default change + one new test.

How to run:
```powershell
cd C:\Users\che\Documents\Projects\ai-git-orchestrator
# Paste task spec below into .ai-loop\task.md, then:
powershell -ExecutionPolicy Bypass -File .\scripts\ai_loop_task_first.ps1 -NoPush
```

---

## Project context

`scripts/ai_loop_auto.ps1` declares `[int]$MaxIterations = 10` (line 2). The architecture document (`docs/architecture.md`, DD-011) specifies 3 as the correct cap — beyond 3 iterations the agent is unlikely to converge and the cost/time cost is disproportionate. This is a documented pending alignment.

The parameter can still be overridden at call time: `-MaxIterations 5` remains valid for exceptional cases.

## Goal

Change the default value of `$MaxIterations` in `scripts/ai_loop_auto.ps1` from `10` to `3`, and add a test that pins the default.

## Scope

**Allowed:**
- `scripts/ai_loop_auto.ps1` — change default value only.
- `tests/test_orchestrator_validation.py` — add one test.

**Not allowed:**
- Any other script or source file.
- Changing the parameter type, name, or any other logic.

## Required behavior

### Change in `ai_loop_auto.ps1`

```powershell
# Before
[int]$MaxIterations = 10,

# After
[int]$MaxIterations = 3,
```

### New test in `test_orchestrator_validation.py`

Add after the existing tests (e.g. after `test_cursor_agent_output_goes_to_debug_dir`):

```python
def test_ai_loop_auto_default_max_iterations_is_3() -> None:
    """DD-011: default retry cap must be 3, not 10."""
    text = (_SCRIPTS / "ai_loop_auto.ps1").read_text(encoding="utf-8")
    assert re.search(r"\[int\]\$MaxIterations\s*=\s*3\b", text), (
        "ai_loop_auto.ps1 default MaxIterations must be 3 (DD-011)"
    )
```

## Files likely to change

- `scripts/ai_loop_auto.ps1` (1 line)
- `tests/test_orchestrator_validation.py` (add ~6 lines)

## Tests

`python -m pytest -q` — must pass. Expected: 31 passed (30 current + 1 new).

## Verification

1. `Select-String -Path scripts\ai_loop_auto.ps1 -Pattern "MaxIterations"` shows `= 3`.
2. `python -m pytest tests/test_orchestrator_validation.py::test_ai_loop_auto_default_max_iterations_is_3 -v` passes.
3. `python -m pytest -q` — 31 passed, 0 errors.

## Cursor summary requirements

- Changed files: `scripts/ai_loop_auto.ps1`, `tests/test_orchestrator_validation.py`
- Before/after value
- Test result (31 passed)

## Project summary update

Add to `.ai-loop/project_summary.md` under key invariants:
> `MaxIterations` default is **3** (DD-011); override at call time with `-MaxIterations N` for exceptional cases.
