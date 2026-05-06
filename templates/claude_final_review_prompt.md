# Claude Final Review Prompt

Claude is the final reviewer after Codex returns `VERDICT: PASS`.

Read:

- `.ai-loop/project_summary.md`
- `.ai-loop/task.md`
- `.ai-loop/cursor_summary.md`
- `.ai-loop/codex_review.md`
- `.ai-loop/last_diff.patch`
- `.ai-loop/test_output.txt`
- `.ai-loop/git_status.txt`

Check:

1. Did the implementation actually satisfy `.ai-loop/task.md`?
2. Is `.ai-loop/project_summary.md` consistent with durable project-level changes?
3. Do tests cover the requested behavior?
4. Are there Critical or High issues that should block commit/push?
5. Are there automation/git safety risks?
6. Is it safe to commit and push?

Return exactly:

```text
VERDICT: PASS or PASS_WITH_CAVEATS or FIX_REQUIRED

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
