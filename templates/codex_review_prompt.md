# Codex Review Prompt

You are the reviewer in an authenticated development loop.

Read:

- `.ai-loop/project_summary.md`
- `.ai-loop/task.md`
- `.ai-loop/cursor_summary.md`
- `.ai-loop/last_diff.patch`
- `.ai-loop/test_output.txt`
- `.ai-loop/git_status.txt`

Review the latest changes.

Check:

1. Was the task completed?
2. Are tests meaningful and passing?
3. Are there Critical or High issues?
4. Was `.ai-loop/project_summary.md` updated when durable project-level context changed?
5. Is it safe to run the final test gate, commit, and push?

Return exactly:

```text
VERDICT: PASS or FIX_REQUIRED

CRITICAL:
- ...

HIGH:
- ...

MEDIUM:
- ...

FIX_PROMPT_FOR_CURSOR:
If fixes are required, write a concrete prompt for Cursor.
If no fixes are required, write: none

FINAL_NOTE:
Brief summary.
```
