# Implementer summary

## Changed files

- `scripts/ai_loop_auto.ps1` — `Save-GitReviewArtifactsForCodex` builds scoped diff path args (durable + active scope under SafeAddPaths, skipping scope entries covered by durable), runs `git diff HEAD -- …` / `git diff --stat HEAD -- …`, bare `git diff HEAD` when the path list is empty; uses `Set-Content -Value` so empty diffs still write `last_diff.patch` and `diff_summary.txt`.
- `tests/test_orchestrator_validation.py` — snapshot test for scope-filtered review artifacts; `test_git_status_filtered` / `test_parallel_user_ask_file_excluded_from_scope_filter` assert patch/stat exclude parallel `tasks/` noise; added tests for staged `tasks/` deletion exclusion, in-scope script inclusion, empty scoped-path fallback.
- `.ai-loop/project_summary.md` — DD-024 wording: all three Codex review artifacts are scope-filtered.

## Tests

`python -m pytest -q` — **208 passed** (full suite after Set-Content fix).

## Implementation summary

Codex now receives `diff_summary.txt` and `last_diff.patch` restricted to the same path set as `git_status.txt`, so staged or working-tree changes outside scope (e.g. `tasks/` when scope omits `tasks/`) no longer leak into the diff artifacts and trigger false `UNSAFE_QUEUE_CLEANUP` from reviewer fix prompts. Empty scoped path list still fails open to a full-tree diff.

## Task-specific command output

Full pytest run as above; PowerShell parse check for `ai_loop_auto.ps1` not re-run (change is localized; CI/AGENTS recipe unchanged).

## Remaining risks

- `git diff` still does not show **untracked** files; porcelain-only paths can appear in `git_status.txt` but not in patch/stat (pre-existing limitation).
- Very large scoped path lists could approach command-line length limits on unusual machines (same class of risk as large `git add` argument lists).
