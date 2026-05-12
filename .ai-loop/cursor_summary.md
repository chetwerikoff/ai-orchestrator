# Cursor summary

- **Changed files (this iteration):** `.ai-loop/cursor_summary.md` — replaces incorrect rollup (pytest/native-argv/README stub story) with an accurate **O04** summary.
- **O04 scope summarized:** `docs/decisions.md` extended through **DD-021**, including **12** reserved placeholders (**DD-007..DD-010**, **DD-012..DD-019**) plus substantive entries for **DD-011**, **DD-020**, **DD-021**. `docs/workflow.md` — current-vs-target note (architecture §0 vs §1+) after `# Workflow`. `README.md` — `AGENTS.md` pointer present; OpenCode/Qwen Phase 0/1 note present; install-into-target list verified against `scripts/install_into_project.ps1`; optional `-SafeAddPaths` example includes **`AGENTS.md`** after **`README.md`**. `.ai-loop/project_summary.md` — durable context updated for companion-doc sync and current orchestrator/task-first behavior.
- **Tests:** `python -m pytest -q` — **24 passed** (~0.19s).
- **Task-specific CLI (`ai_loop_task_first.ps1 -NoPush`):** Skipped — orchestrator assumes interactive Cursor/Codex; not applicable for correcting this summary file.
- **Remaining risks:** Summary drift if future doc edits land without updating `.ai-loop/cursor_summary.md` at task close.
