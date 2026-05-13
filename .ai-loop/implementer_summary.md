# Implementer summary

## Changed files

- `scripts/ai_loop_task_first.ps1` - active result/debug paths renamed to `implementer_*`; task-first now resets only `implementer_summary.md`.
- `scripts/ai_loop_auto.ps1` - fix prompt extraction uses only `FIX_PROMPT_FOR_IMPLEMENTER`; resume uses only `next_implementer_prompt.md`; fix output writes to `_debug/implementer_fix_output.txt`.
- `scripts/continue_ai_loop.ps1`, `scripts/install_into_project.ps1`, `.gitignore`, templates, docs, README, AGENTS, and tests - safe paths and public contract updated to implementer-neutral artifact names.
- Removed the tracked legacy summary alias and replaced the legacy summary template with `templates/implementer_summary_template.md`.

## Tests

- `python -m pytest -q` -> 57 passed, 1 pytest cache warning.
- PowerShell parser checks passed for `ai_loop_auto.ps1`, `ai_loop_task_first.ps1`, `continue_ai_loop.ps1`, and `run_opencode_agent.ps1`.

## Implementation summary

- Removed legacy Cursor alias files from the active PowerShell loop contract: summary alias, next-prompt alias, legacy fix label, result marker path, and debug capture paths.
- Kept real Cursor support through `run_cursor_agent.ps1` and compatibility parameters `-CursorCommand` / `-CursorModel`.
- Added/updated tests to reject legacy active artifact names in scripts/templates/docs and to validate the new neutral contract.

## Remaining risks

- `ai_loop.py` still contains older experimental Cursor-centric terminology; it was intentionally left unchanged because this task targets the active PowerShell loop and AGENTS requires explicit authorization for `ai_loop.py`.
- Historical queued specs under `tasks/context_audit/` and ignored `.ai-loop/_debug/` may still mention old names; they are not part of the active contract.
