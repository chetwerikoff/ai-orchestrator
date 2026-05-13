# A Git Orchestrator

See `AGENTS.md` for AI-agent working rules.

A local PowerShell-based AI development loop for coordinating:

- an **implementer** (Cursor Agent by default; override with `-CursorCommand`, e.g. `.\scripts\run_opencode_agent.ps1`)
- Codex as reviewer
- project tests
- safe git commit and push

The orchestrator is designed to be installed into any git project that uses a file-based task workflow under `.ai-loop/`.

## What it does

For a new task, `ai_loop_task_first.ps1` clears stale `.ai-loop` runtime artifacts (except `task.md`), runs the configured implementer, then hands off to `ai_loop_auto.ps1`.

Flow:

```text
task.md -> implementer pass -> if relevant git changes exist -> ai_loop_auto.ps1 (tests + Codex review/fix loop)
```

> Local OpenCode + Qwen integration is in Phase 0/1 (see
> `docs/architecture.md` §0.3); production implementer today is Cursor.

If the implementer produces no relevant working tree changes twice (excluding orchestrator scratch files), Codex is skipped, `.ai-loop/final_status.md` records `NO_CHANGES_AFTER_IMPLEMENTER`, and the script exits non-zero.

If the implementer only adds `.ai-loop/implementer_result.md` without editing code, that file must contain `IMPLEMENTATION_STATUS: DONE_NO_CODE_CHANGES_REQUIRED`, or the script exits before Codex. That check uses the git delta for the implementer pass (not unrelated pre-existing dirt), so a stale dirty `.ai-loop/task.md` alone does not bypass the marker requirement.

For already existing changes, `ai_loop_auto.ps1` starts directly from tests + Codex review (not for brand-new tasks with no implementation yet).

## Requirements

Install and authenticate:

```powershell
agent --version
codex --version
git --version
```

Expected CLIs:

- Cursor CLI: `agent`
- OpenAI Codex CLI: `codex`

## Project-level memory

The orchestrator uses:

```text
.ai-loop/project_summary.md
```

as durable project-level memory.

This file is not a detailed task log. It should contain durable context:

- project purpose;
- architecture;
- important design decisions;
- current stage;
- known risks;
- next likely steps.

The implementer updates it after each task when durable context changes. Codex reads it during review.

## Install into a target project

From this repository:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\install_into_project.ps1 `
  -TargetProject "C:\path\to\your\project"
```

This copies:

```text
scripts/ai_loop_auto.ps1
scripts/ai_loop_task_first.ps1
scripts/continue_ai_loop.ps1
scripts/run_cursor_agent.ps1
scripts/run_opencode_agent.ps1
scripts/filter_pytest_failures.py
.ai-loop/task.md
.ai-loop/project_summary.md
.ai-loop/codex_review_prompt.md
.ai-loop/implementer_summary_template.md
opencode.json   (Phase 1 direct llama-server wiring; see docs/architecture.md §5.3)
```

Existing `.ai-loop/task.md` and `.ai-loop/project_summary.md` are not overwritten unless you pass `-OverwriteTask` or `-OverwriteProjectSummary`. An existing root `opencode.json` is left unchanged unless you pass `-OverwriteOpencodeConfig`.

## Start a new task in the target project

From the target project root, use the task-first entrypoint:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\ai_loop_task_first.ps1 `
  -MaxIterations 10 `
  -CommitMessage "Implement feature"
```

This starts with an implementer pass before Codex review. Pass `-NoPush`, `-TestCommand`, `-PostFixCommand`, or `-SafeAddPaths` here the same way as for `ai_loop_auto.ps1` (see **Optional parameters** below).

## Review/fix already existing changes

Use `ai_loop_auto.ps1` only when implementation changes already exist and you want to start from tests + Codex review:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\ai_loop_auto.ps1 `
  -MaxIterations 10 `
  -CommitMessage "Review existing changes"
```

## Continue after stop

From the target project root, **`continue_ai_loop.ps1`** resumes with `ai_loop_auto.ps1 -Resume`.

**Default:** If you previously ran task-first or auto with a non-default implementer (for example OpenCode via `-CursorCommand`), the effective wrapper and model are stored in **`.ai-loop/implementer.json`** (runtime, gitignored). You can continue **without** repeating `-CursorCommand` / `-CursorModel`; the resume run reloads them.

**Override:** Pass `-CursorCommand` and/or `-CursorModel` again when you want to change the implementer for this session; those parameters always override the persisted file.

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\continue_ai_loop.ps1 `
  -CommitMessage "Continue feature"
```

or, if scripts are unblocked:

```powershell
.\scripts\continue_ai_loop.ps1 -CommitMessage "Continue feature"
```

Explicit OpenCode example:

```powershell
.\scripts\continue_ai_loop.ps1 -CommitMessage "Continue" `
  -CursorCommand ".\scripts\run_opencode_agent.ps1" `
  -CursorModel "local-qwen-35b/qwen3-6-35b-a3b"
```

## Optional parameters

`ai_loop_auto.ps1` accepts:

```powershell
-MaxIterations 10
-CommitMessage "Message"
-NoPush
-TestCommand "python -m pytest"
-PostFixCommand "python src/main.py some-command"
-SafeAddPaths "src/,tests/,README.md,AGENTS.md,scripts/,docs/,templates/,ai_loop.py,pytest.ini,.gitignore,requirements.txt,pyproject.toml,setup.cfg,.ai-loop/task.md,.ai-loop/implementer_summary.md,.ai-loop/project_summary.md"
```

`ai_loop_task_first.ps1` accepts the same implementer-related switches (`-CursorCommand`, `-CursorModel`) plus forwarding to the embedded auto loop: `-NoPush`, `-TestCommand`, `-PostFixCommand`, and `-SafeAddPaths` (same meanings as `ai_loop_auto.ps1`).

`continue_ai_loop.ps1` forwards `-CursorCommand` and `-CursorModel` when you pass them (they override **`.ai-loop/implementer.json`**). If you omit them, resume uses the persisted effective implementer when that file exists and is valid.

## Safety model

The orchestrator does **not** stage everything by default.

It stages only `SafeAddPaths`. Runtime artifacts are intentionally excluded:

```text
.ai-loop/implementer.json
.ai-loop/codex_review.md
.ai-loop/implementer_result.md
.ai-loop/_debug/implementer_prompt.md
.ai-loop/_debug/implementer_output.txt
.ai-loop/_debug/implementer_fix_output.txt
.ai-loop/claude_final_review.md
.ai-loop/last_diff.patch
.ai-loop/test_output.txt
.ai-loop/test_output_before_commit.txt
.ai-loop/next_implementer_prompt.md
.ai-loop/final_status.md
.ai-loop/git_status.txt
.ai-loop/post_fix_output.txt
.tmp/
input/
output/
```

You should still review `.gitignore` in every target project.

## Public repository warning

Before publishing this project publicly, make sure you have not committed:

- API keys
- credentials
- private project files
- real task outputs
- private `.ai-loop/*review.md` files
- generated `input/` or `output/` data

## Suggested workflow

1. Write a precise task into `.ai-loop/task.md`.
2. Make sure `.ai-loop/project_summary.md` describes the current project context.
3. Run `ai_loop_task_first.ps1` for a new task, or `ai_loop_auto.ps1` only for already existing changes.
4. Wait for `final_status.md`.
5. If stopped, inspect:
   - `.ai-loop/codex_review.md`
   - `.ai-loop/implementer_summary.md`
6. Continue with `continue_ai_loop.ps1`.
