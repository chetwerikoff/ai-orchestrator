# Task: Codex console reason region (post-verdict)

## Project context

- `AGENTS.md`
- `.ai-loop/task.md` (prior contract if superseding; otherwise omit if absent)
- `.ai-loop/project_summary.md`
- `.ai-loop/repo_map.md`
- `.ai-loop/implementer_summary.md` (iteration 2+)

## Goal

Codex writes a full transcript to `.ai-loop/codex_review.md`, which includes the review prompt text with example severity blocks (for example bullets shown as `- ...`). The host console summary in `scripts/ai_loop_auto.ps1` must derive the optional single-line `Codex reason:` **only from the Codex assistantÔÇÖs final answer**, after the authoritative verdict line(s), so the terminal never prints placeholder reasons echoed from earlier prompt sections.

## Scope

**Allowed:**

- Narrow change to console summary reason extraction (same verdict semantics as existing `Get-ReviewVerdict`; no change to verdict parsing contracts).
- Pytest subprocess/harness updates that exercise representative transcripts: prompt placeholders before the final verdict, real bullets after it, suppression of `- none`, `- ...`, ellipsis-only bullets, and omission of `Codex reason:` when nothing real remains.

**Not allowed:**

- Altering fix-loop semantics, JSON/markdown fix-prompt extraction, token usage parsing, safe staging/commit/push behavior, or `Get-ReviewVerdict` line matching rules beyond what this task specifies (verbatim last `VERDICT:` line semantics stay as-is for verdict; reason scanning only gains a bounded region).
- Live CLI runs (Codex/Cursor/Claude).
- Commits/pushes.

## Files in scope

- `scripts/ai_loop_auto.ps1`
- `tests/test_orchestrator_validation.py`
- `.ai-loop/project_summary.md`

## Files out of scope

- `docs/archive/**`
- `.ai-loop/_debug/**`
- `ai_loop.py`
- `templates/codex_review_prompt.md` (behavior fix is host-side transcript slicing; prompt shape stays unchanged unless a future task requires it)

## Required behavior

1. Keep **exact** last-line verdict resolution unchanged: trimmed line anchored `^VERDICT:\s*(PASS|FIX_REQUIRED)$`; last occurrence wins (`Get-ReviewVerdict` contract remains intact).
2. When selecting bullets for optional `Codex reason:`, analyze **only lines after** the transcript position of that **same last verdict line** chosen by verdict parsing (the final assistant answer tail, not headings/prompt preamble above it).
3. Within that suffix, locate `CRITICAL:`, `HIGH:`, `MEDIUM:` sections in document order **after** the verdict line only; severity labels match the existing extractorÔÇÖs casing/shape conventions.
4. Pick the console reason bullet with unchanged priority versus todayÔÇÖs intended behavior restricted to real content: first non-empty bullet under `CRITICAL`, else first under `HIGH`, else first under `MEDIUM`.
5. Treat as ignorable placeholders (never emitted as reasons): bullets whose body trims to `- none` (case-insensitive), `- ...`, or trims to ellipsis/dot-only placeholders (consistent with ignoring ÔÇ£meaningless fillerÔÇØ bullets from prompt examples).
6. If no qualifying bullet remains, **omit** the `Codex reason:` line entirely; still print `See: .ai-loop\\codex_review.md` (and other existing summary lines) per current behavior.

## Tests

- Extend `tests/test_orchestrator_validation.py` with substring/transcript fixtures that include a long leading prompt-like region containing example `CRITICAL:/HIGH:/MEDIUM:` placeholders **before** a final legitimate `VERDICT: FIX_REQUIRED` and real post-verdict bullets.
- Cover at minimum:

  - Placeholder bullets before final verdict ignored; console reason reflects post-verdict `HIGH:` content.
  `- none` suppressed.
  `- ...` suppressed.
  - No real bullets after verdict ÔçÆ no `Codex reason:` substring in simulated console output harness.

- Run `python -m pytest -q`.

## Verification

- `python -m pytest -q`
- Parse check (host script touched):

```powershell
powershell -NoProfile -Command "[void][System.Management.Automation.Language.Parser]::ParseFile('scripts\\ai_loop_auto.ps1', [ref]$null, [ref]$null)"
```

## Implementer summary requirements

- Brief list of changed files.
- Test result counts from `pytest -q` (not full logs).
- 3ÔÇô5 lines describing implemented behavior (post-verdict reason window + placeholder suppression).
- Skipped items with reasons (if any).
- 1ÔÇô3 remaining risks.

## Project summary update

Update **Current Pipeline / Workflow** or **Last Completed Task** notes to state briefly that **`Codex reason:` derives from severity bullets only after the final exact `VERDICT:` line** in `codex_review.md`, intentionally ignoring prompt/example placeholder sections earlier in the transcript.

## Output hygiene

- Do not duplicate the full task body into `.ai-loop/implementer_summary.md`.
- Do not write under `.ai-loop/_debug/`.
- Do not commit or push.
- Do not edit `docs/archive/**`.

## Important

- Verdict precedence and anchoring remain **byte-for-byte** with existing `Get-ReviewVerdict` behavior on the full file; this task slices *downstream reasoning* only.
- Prefer a small refactor inside the existing summary helper rather than spreading duplicate verdict-finding logic; do not regress non-`FIX_REQUIRED` paths.
- Boundary definition: severity sections strictly **below** the last verdict line avoids confusing rare prompts that reuse labels before the assistant answer; transcript order is deterministic for this file layout.
- If the extractor currently stops at headings/labels after severity scanning, preserve that safeguard **within** the post-verdict region so later markdown cannot vacuum unrelated bullets.

## Order

1
