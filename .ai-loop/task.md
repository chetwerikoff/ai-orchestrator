# Task: Remove Cursor-Named Legacy Artifacts From Active Loop

## Goal

Remove the legacy Cursor-named alias files and labels from the active PowerShell orchestration contract, while keeping Cursor Agent available as a real implementer wrapper.

This is a two-level cleanup:

1. Public loop contract:
   - use `.ai-loop/implementer_summary.md`;
   - use `.ai-loop/next_implementer_prompt.md`;
   - use `FIX_PROMPT_FOR_IMPLEMENTER`;
   - remove the old summary/fix-prompt aliases.

2. Runtime/debug contract:
   - use `.ai-loop/implementer_result.md`;
   - use `.ai-loop/_debug/implementer_prompt.md`;
   - use `.ai-loop/_debug/implementer_output.txt`;
   - use `.ai-loop/_debug/implementer_fix_output.txt`;
   - remove Cursor-named result/debug paths from the active scripts and docs.

## Scope

Allowed:

- Update `scripts/`, `templates/`, `tests/`, docs, README, AGENTS, `.gitignore`, and `.ai-loop/project_summary.md`.
- Delete tracked legacy template/summary files that are no longer part of the contract.

Not allowed:

- Do not remove `run_cursor_agent.ps1`; it is the actual Cursor wrapper.
- Do not remove `-CursorCommand` / `-CursorModel` yet; they remain compatibility parameter names.
- Do not edit `docs/archive/` or `.ai-loop/_debug/`.
- Do not edit `ai_loop.py` in this task; it is the separate experimental orchestrator.

## Required Behavior

1. New task-first runs reset only `.ai-loop/implementer_summary.md`.
2. Codex review reads `.ai-loop/implementer_summary.md` only.
3. Codex fixes are extracted only from `FIX_PROMPT_FOR_IMPLEMENTER`.
4. Resume/fix uses `.ai-loop/next_implementer_prompt.md` only.
5. The no-code marker gate uses `.ai-loop/implementer_result.md`.
6. Debug captures use implementer-neutral filenames under `.ai-loop/_debug/`.
7. Safe paths include `.ai-loop/implementer_summary.md` but not removed legacy summary aliases.
8. Documentation and tests describe the new contract.

## Tests

Run:

```powershell
python -m pytest -q
```

Run parser checks for:

```powershell
scripts\ai_loop_auto.ps1
scripts\ai_loop_task_first.ps1
scripts\continue_ai_loop.ps1
scripts\run_opencode_agent.ps1
```

## Implementer Summary Requirements

Update `.ai-loop/implementer_summary.md` with changed files, tests, implementation summary, and remaining risks.
