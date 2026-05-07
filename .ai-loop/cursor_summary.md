# Cursor Summary

## Changed files

- `scripts/ai_loop_task_first.ps1` — `Get-FilteredPorcelainLinesForImplementation` documents why `git status --porcelain --untracked-files=all` is used; `Get-ResultFileSnapshot` wraps file hashing in try/catch (`FILEHASH_UNREADABLE`), aggregates directory manifests as before, and **never** returns `Exists=true` with null/empty `Hash` (falls back to `SNAPSHOT_HASH_UNAVAILABLE`) so content-delta logic cannot treat two live snapshots as identical just because `Hash` was null on both sides.
- `docs/workflow.md` — documents the exact `Test-CursorResultAllowsNoCodeChanges` regex `(?im)^IMPLEMENTATION_STATUS:\s*DONE_NO_CODE_CHANGES_REQUIRED\s*$`, literal valid line, trailing-space rule, and `RESULT_ONLY_WITHOUT_DONE_NO_CODE_MARKER` outcome.
- `tests/test_orchestrator_validation.py` — `test_task_first_porcelain_uses_untracked_files_all` regression guard; existing stable `?? dir/` + fingerprint test unchanged.

## Test result

Command: `python -m pytest -q` from repo root (`C:\Users\che\Documents\Projects\ai-git-orchestrator`).

Result: **19 passed** (exit code 0).

## Implementation summary

Task-first porcelain continues to use `--untracked-files=all` so nested untracked paths participate in the filtered status line set together with directory manifest hashing when porcelain stays stable. Snapshot hardening removes the `Exists=true` + `Hash=null` blind spot for files (hash failures, odd empty-hash edge cases) so merged deltas stay trustworthy.

## Task-specific CLI / live run

`.ai-loop/task.md` references `scripts\ai_loop_task_first.ps1` / `ai_loop_auto.ps1`. **Skipped:** live PowerShell orchestrator and Cursor `agent` invocation (interactive / environment-specific; pytest covers parsing and delta semantics).

## Remaining risks

- Very large untracked directories remain potentially expensive to fingerprint when those paths appear in the porcelain-derived snapshot union.
- `FILEHASH_UNREADABLE` / `SNAPSHOT_HASH_UNAVAILABLE` stabilize comparisons but mark paths where byte-accurate hashing was not possible; unusual ACL or transient I/O errors could still surface as coarse sentinels rather than fine-grained content hashes.
