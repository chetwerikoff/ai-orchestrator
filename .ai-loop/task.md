# D01 — Compact h2n-range-extractor project_summary.md

**Project:** `H2N_parser/h2n-range-extractor`
**CWD:** `C:\Users\che\Documents\Projects\H2N_parser\h2n-range-extractor`
**Prerequisite:** O01–O06 merged in `ai-git-orchestrator`.
**Risk:** low — orientation file only, no code changes.

How to run:
```powershell
cd C:\Users\che\Documents\Projects\H2N_parser\h2n-range-extractor
# Paste task spec below into .ai-loop\task.md, then:
powershell -ExecutionPolicy Bypass -File .\scripts\ai_loop_task_first.ps1 -NoPush
```

---

## Project context

`h2n-range-extractor` is a Python research tool that reverse-engineers Hand2Note 4 config exports. It is currently using the `ai-git-orchestrator` PowerShell loop with Cursor + Codex review.

The file `.ai-loop/project_summary.md` contains **202 lines** of durable context. Most of it is inline parameter documentation, implementation detail, and accumulated "Earlier roll" history entries — all of which violate the compaction rules now mandated by `templates/project_summary.md` (updated in O05).

## Goal

Rewrite `.ai-loop/project_summary.md` to **≤ 60 lines** following the updated template rules (`templates/project_summary.md`).

## Scope

**Allowed:**
- Edit `.ai-loop/project_summary.md` only.

**Not allowed:**
- Any code or test changes.
- Removing information that qualifies as durable orientation (see below).

## Required behavior

After the rewrite, `project_summary.md` must contain:

1. **Project purpose** (3–5 lines): what the tool does, what it is NOT (research heuristics, not validated offsets).
2. **Architecture** (≤ 15 lines): one line per module in `src/`, listing only the subcommand name and its responsibility. No inline parameter docs, no byte-level protocol details.
3. **Data / artifact pipeline** (≤ 8 lines): the standard CLI invocation sequence and key output files.
4. **Test / smoke commands** (3 lines): `python -m pytest -q`, smoke example, current passing count (read from `.ai-loop/cursor_summary.md` or `test_output.txt` for the latest number).
5. **Key invariants / gotchas** (≤ 8 lines): things that have caused bugs before and are worth remembering across sessions. Examples: `.ai-loop/` mirror flags, XML sanitization for openpyxl, `link_radius`/`stat_id_window` default, `--allow-content-source` flag semantics.
6. **Safe paths** (3 lines): what the orchestrator commits (`src/`, `tests/`, `scripts/`, `README.md`, `AGENTS.md`, `requirements.txt`, `.ai-loop/task.md`, `.ai-loop/cursor_summary.md`, `.ai-loop/project_summary.md`).

**Must omit:**
- "Earlier roll" history sections — those belong in `cursor_summary.md` (ephemeral) or git log.
- Inline parameter lists, byte offsets, regex patterns — those belong in source code.
- Smoke test result tables, full JSON schema descriptions.
- Any content repeated elsewhere (README, source docstrings).

## Files likely to change

- `.ai-loop/project_summary.md` (rewrite, 202 → ≤ 60 lines)

## Tests

No code changes → no test run required. Run `python -m pytest -q` only to confirm no accidental breakage from file writes.

Expected: same pass count as current (read from `.ai-loop/test_output.txt`).

## Verification

1. `(Get-Content .ai-loop\project_summary.md | Measure-Object -Line).Lines` — must be ≤ 60.
2. File contains sections: Project purpose, Architecture, Data pipeline, Test/smoke commands, Key invariants, Safe paths.
3. File contains NO "Earlier roll" heading.
4. File contains NO inline parameter lists (no backtick-heavy single lines > 200 chars).
5. `python -m pytest -q` — same pass count as before.

## Cursor summary requirements

- Changed files: `.ai-loop/project_summary.md`
- Before/after line count
- Sections present in the new file
- Test result (count only)

## Project summary update

Not applicable — this task IS the project summary update.

## Important

- Do NOT read the full content of `.ai-loop/color_range_matches.json`, `.ai-loop/school_stats_report.md`, or other large mirror files — they are gitignored analysis artifacts, not orientation content.
- Read `templates/project_summary.md` (from `ai-git-orchestrator`) for the target format.
- The "Key invariants / gotchas" section is the most valuable part — preserve any hard-won facts from the current file that would prevent bugs.
