# Safety

## Do not run two agents in one repository

Run only one orchestrator per target repository at a time.

It is safe to run agents in parallel only if they work in different git repositories.

## Safe staging

By default, the orchestrator stages only explicit safe paths:

```text
src/
tests/
README.md
AGENTS.md
scripts/
docs/
tasks/
templates/
ai_loop.py
pytest.ini
.gitignore
requirements.txt
pyproject.toml
setup.cfg
pyrightconfig.json
.ai-loop/task.md
.ai-loop/implementer_summary.md
.ai-loop/project_summary.md
.ai-loop/repo_map.md
.ai-loop/failures.md
.ai-loop/archive/rolls/
.ai-loop/_debug/session_draft.md
```

Runtime artifacts are not staged.

**Stage set (DD-024, `ai_loop_auto.ps1`):** `Stage-SafeProjectFiles` uses **DurableAlwaysCommit** (the `.ai-loop/` entries from the fenced list above: task, implementer_summary, project_summary, repo_map, failures, `archive/rolls/`, and `_debug/session_draft.md` under `.ai-loop/`) plus **ActiveScope ∩ SafeAddPaths**, where **ActiveScope** is the bullet list under `## Files in scope` in `.ai-loop/task.md` (missing section or no bullets → treated as empty). Unconditional directory staging of every `SafeAddPaths` blob no longer happens when scope is empty—only durable paths are staged, with a console warning—so unrelated working-tree paths stay out of the automated commit and out of the filtered **`git_status.txt`** sent to Codex (diff artifacts remain full-tree `git diff HEAD`).

`.ai-loop/implementer.json` records the last **effective** implementer wrapper and model used by the drivers (including OpenCode/Qwen selections) so `continue_ai_loop.ps1` / `ai_loop_auto.ps1 -Resume` can load them when you omit `-CursorCommand` / `-CursorModel`. It is **runtime-only** (gitignored): paths and model IDs may be machine-specific — do not rely on it for durable documentation.

## Private data

Before making a repository public, verify that it does not include:

- API keys
- credentials
- real user data
- private configs
- generated output
- `input/`
- `output/`
- `.ai-loop/*review.md`

## Recommended public repo check

```powershell
git status
git ls-files
git grep -n "api_key\|token\|password\|secret" .
```

## PowerShell execution policy

If Windows blocks scripts, run:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\ai_loop_auto.ps1
```

or unblock local scripts:

```powershell
Get-ChildItem .\scripts\*.ps1 | Unblock-File
```
