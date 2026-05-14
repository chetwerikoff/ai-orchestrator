# C03 — Structured JSON FIX_PROMPT_FOR_IMPLEMENTER + Codex diff-size budget + Codex test-execution policy

- **Target project:** `ai-orchestrator`
- **CWD:** `C:\Users\che\Documents\Projects\ai-orchestrator`
- **Invocation:** copy section below `---` into `.ai-loop\task.md`, then run

  ```powershell
  powershell -ExecutionPolicy Bypass -File .\scripts\ai_loop_task_first.ps1 -NoPush
  ```

- **Prerequisites:** C02 merged.
- **Risk:** medium — changes the Codex contract; regression risk on fix-loop extraction. Keep regex fallback path.
- **Estimated lines touched:** ~60 lines edited, +2 new tests.

---

# Task: Codex fix prompt becomes structured JSON (with regex fallback); Codex prompt instructs diff-size budget and a tightened test-execution policy

## Project context

Required reading before starting (in order; stop when you have enough):

1. `AGENTS.md`
2. `.ai-loop/task.md` — this task
3. `.ai-loop/project_summary.md`
4. `.ai-loop/repo_map.md`
5. `.ai-loop/implementer_summary.md` — only if iteration ≥ 2

Background: `Run-CodexReview` (`scripts/ai_loop_auto.ps1` ~line 328) currently asks Codex to write a free-text `FIX_PROMPT_FOR_IMPLEMENTER:` block between two regex delimiters. `Extract-FixPromptFromFile` then regex-extracts whatever Codex wrote and pipes it back to the implementer. The format works but is unstructured — fix prompts vary wildly in length and specificity, which hurts local Qwen quality on fix iterations. The same review function also includes `.ai-loop/last_diff.patch` in the read list with no size budget, even though `diff_summary.txt` is already produced (O06). On top of that, the Codex prompt today is silent about test execution: the orchestrator already runs `pytest` before Codex and captures the result, yet Codex sometimes re-runs the full suite anyway — wasting 30–120 s per iteration without adding signal. The context-plan report (§9 Phase 1 step 1.3 + Phase 2 step 2.4, §10) prescribes the JSON + diff-budget pair; this task also adds a tightened test-execution policy to the same prompt.

## Goal

1. Change the Codex prompt in `Run-CodexReview` to require `FIX_PROMPT_FOR_IMPLEMENTER` as a JSON block (with the schema below). Keep `VERDICT:` / `CRITICAL:` / `HIGH:` / `MEDIUM:` / `FINAL_NOTE:` sections unchanged.
2. Update `Extract-FixPromptFromFile` to:
   - Try JSON parse first (preferred path).
   - On parse failure, fall back to the existing free-text regex extractor and log `Write-Warning`.
   - When JSON is parsed, render a deterministic human-readable `next_implementer_prompt.md` from the schema (one section per field).
3. Add a `## Diff size budget` instruction inside the Codex prompt: if `diff_summary.txt` reports >300 changed lines OR >8 changed files, Codex should read `diff_summary.txt` first and ask before reading `last_diff.patch`.
4. Add a `## Test execution policy` instruction inside the Codex prompt: forbid full-suite re-runs (the orchestrator pre-captures pytest output); allow targeted runs (single file / single test) only when a specific finding requires direct verification; require Codex to state the reason for any targeted run in `FINAL_NOTE`.
5. Mirror both the JSON schema **and** the test-execution policy in `templates/codex_review_prompt.md` so target projects stay in sync.
6. Add two tests: one for the JSON parse path, one for the regex fallback path.

## Scope

**Allowed:**
- `scripts/ai_loop_auto.ps1` — `Run-CodexReview` + `Extract-FixPromptFromFile`.
- `templates/codex_review_prompt.md` — mirror schema.
- `tests/test_orchestrator_validation.py` — two new tests.
- `.ai-loop/project_summary.md` — one-line note.

**Not allowed:**
- Do not modify the rest of `ai_loop_auto.ps1` (state machine, safe staging, post-fix command, resume).
- Do not modify `scripts/ai_loop_task_first.ps1` (owned by C02).
- Do not modify `MaxIterations`.
- Do not change `SafeAddPaths`.
- Do not edit `ai_loop.py`.

## Files likely to change

- `scripts/ai_loop_auto.ps1` (~40 lines edited in 2 functions)
- `templates/codex_review_prompt.md` (~15 lines)
- `tests/test_orchestrator_validation.py` (~30 lines, 2 new tests)
- `.ai-loop/project_summary.md` (1 line)

## Required behavior

### 1. JSON schema for `FIX_PROMPT_FOR_IMPLEMENTER`

The Codex prompt in `Run-CodexReview` instructs Codex to emit, between `FIX_PROMPT_FOR_IMPLEMENTER:` and `FINAL_NOTE:`, **either** the literal `none` (no fixes) **or** a single fenced JSON block with this schema:

```json
{
  "fix_required": true,
  "files": ["src/foo.py", "tests/test_foo.py"],
  "changes": [
    { "path": "src/foo.py", "kind": "edit|add|delete", "what": "one-line directive" }
  ],
  "acceptance": "pytest -q passes; <other concrete criteria>"
}
```

Rules:
- `fix_required` is `true` whenever Codex's verdict is `FIX_REQUIRED`.
- `files` is the deduplicated union of `changes[].path`.
- `changes[].kind` is one of `edit`, `add`, `delete`.
- `acceptance` is a single concrete sentence.
- The whole block must be valid JSON, parseable by `ConvertFrom-Json`.

### 2. `Extract-FixPromptFromFile` rewrite

```powershell
function Extract-FixPromptFromFile {
    param([string]$ReviewFile, [string]$OutputPromptFile)
    if (!(Test-Path $ReviewFile)) { return $false }
    $review = Get-Content $ReviewFile -Raw

    # 1) Try JSON path first.
    $jsonMatch = [regex]::Match(
        $review,
        '(?ms)FIX_PROMPT_FOR_IMPLEMENTER:\s*```json\s*(?<json>\{.*?\})\s*```',
        [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
    )
    if ($jsonMatch.Success) {
        try {
            $obj = $jsonMatch.Groups['json'].Value | ConvertFrom-Json -ErrorAction Stop
            if ($obj.fix_required) {
                $rendered = Format-FixPromptFromObject -FixObject $obj
                $rendered | Set-Content -Path $OutputPromptFile -Encoding UTF8
                return $true
            }
            return $false
        } catch {
            Write-Warning "FIX_PROMPT JSON parse failed: $($_.Exception.Message). Falling back to free-text extractor."
        }
    }

    # 2) Fallback: existing regex behavior (verbatim) for backward compatibility.
    # … (keep current code path unchanged) …
}

function Format-FixPromptFromObject {
    param($FixObject)
    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.AppendLine("# Fix prompt")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("## Files to change")
    foreach ($f in $FixObject.files) { [void]$sb.AppendLine("- $f") }
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("## Changes")
    foreach ($c in $FixObject.changes) {
        [void]$sb.AppendLine("- ($($c.kind)) `$($c.path)` — $($c.what)")
    }
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("## Acceptance")
    [void]$sb.AppendLine($FixObject.acceptance)
    return $sb.ToString()
}
```

The fallback path **must remain bit-compatible** with current behavior so existing Codex runs that still emit free text continue to work. Emit `Write-Warning` on every fallback so the operator can spot it.

### 3. Codex prompt updates inside `Run-CodexReview`

- Add a new line to the read-priority list:
  > `.ai-loop/diff_summary.txt` — short `git diff --stat`; read this first if it reports >300 lines or >8 files.
- Add a `## Diff size budget` paragraph:
  > If `diff_summary.txt` reports more than 300 changed lines OR more than 8 changed files, read `diff_summary.txt` first. Do not load `last_diff.patch` unless a specific finding requires it; if you need to load it, justify briefly in `FINAL_NOTE`.
- Add a `## Test execution policy` paragraph:
  > The orchestrator already ran `pytest` before this review; results are in `.ai-loop/test_output.txt` (and, on failure, `.ai-loop/test_failures_summary.md`). Do not re-run the full test suite. A targeted run of a single test file or a single test (`python -m pytest -q path/to/test_file.py::test_name`) is allowed only when a specific finding in this review requires direct verification. If you run any tests, state in one line in `FINAL_NOTE` exactly what you ran and why.
- Replace the free-text `FIX_PROMPT_FOR_IMPLEMENTER` instruction with the JSON schema (verbatim from §1) wrapped in a `json` fenced block.
- Keep `VERDICT:`, `CRITICAL:`, `HIGH:`, `MEDIUM:`, `FINAL_NOTE:` sections unchanged.

### 4. `templates/codex_review_prompt.md` mirror

Update the read-priority list, replace the free-text fix block with the same JSON schema, and add the same `## Diff size budget` and `## Test execution policy` paragraphs. Keep the rest of the template's structure intact.

### 5. Tests

Add to `tests/test_orchestrator_validation.py`:

```python
def test_extract_fix_prompt_parses_json(tmp_path) -> None:
    """C03: Extract-FixPromptFromFile must parse the JSON schema."""
    # Write a synthetic codex_review.md with VERDICT: FIX_REQUIRED + a JSON FIX_PROMPT.
    # Invoke the function via pwsh subprocess; assert OutputPromptFile contains
    # rendered sections (## Files to change, ## Changes, ## Acceptance).
    ...

def test_extract_fix_prompt_falls_back_on_invalid_json(tmp_path) -> None:
    """C03: malformed JSON must fall back to free-text regex extraction."""
    # Same as above but emit a broken JSON block; assert the extractor still
    # produces a non-empty OutputPromptFile via the legacy regex path.
    ...
```

## Tests

```powershell
python -m pytest -q
```

Expected: baseline-after-C02 + 2 new tests, no regressions.

PowerShell parser check:

```powershell
powershell -NoProfile -Command "[void][System.Management.Automation.Language.Parser]::ParseFile('scripts\ai_loop_auto.ps1', [ref]$null, [ref]$null)"
```

## Verification

1. `Select-String -Path scripts\ai_loop_auto.ps1 -Pattern "Format-FixPromptFromObject|diff_summary\.txt|Diff size budget|Test execution policy"` returns ≥4 matches.
2. `Select-String -Path templates\codex_review_prompt.md -Pattern "fix_required|acceptance|Test execution policy"` returns ≥3 matches.
3. `python -m pytest -q` shows baseline + 2 new tests, no regressions.
4. Synthetic `codex_review.md` with valid JSON FIX_PROMPT round-trips into a humanized `.ai-loop\next_implementer_prompt.md` with the three sections above.
5. Synthetic `codex_review.md` with malformed JSON still produces a non-empty `.ai-loop\next_implementer_prompt.md` and triggers a warning.

## Implementer summary requirements

Update `.ai-loop/implementer_summary.md` (target <50 lines):

- Changed files.
- Test result (baseline + 2 new tests, no regressions).
- Confirmation that JSON path and regex fallback both work.
- Remaining risks (especially: any first run where Codex still emits the legacy free-text format will trigger the warning; this is expected for one cycle).

## Project summary update

Add one line under "Current architecture" or "Important design decisions" in `.ai-loop/project_summary.md`:

> Codex emits `FIX_PROMPT_FOR_IMPLEMENTER` as JSON (`fix_required`, `files`, `changes[]`, `acceptance`); `Extract-FixPromptFromFile` prefers JSON and falls back to the legacy free-text regex with a warning. Codex prompt forbids full-suite re-runs (orchestrator pre-captures pytest output); targeted single-test runs are allowed with a one-line reason in `FINAL_NOTE`.

## Files in scope

- `scripts/ai_loop_auto.ps1`
- `templates/codex_review_prompt.md`
- `tests/test_orchestrator_validation.py`
- `.ai-loop/project_summary.md`
- `.ai-loop/implementer_summary.md`

## Files out of scope

- `scripts/ai_loop_task_first.ps1`
- `scripts/continue_ai_loop.ps1`
- `scripts/build_repo_map.ps1`
- `scripts/run_cursor_agent.ps1`
- `scripts/run_opencode_agent.ps1`
- `ai_loop.py`
- `docs/archive/**`
- `.ai-loop/_debug/**`
- `.ai-loop/repo_map.md`

## Important

- Do not commit or push manually.
- Keep the regex fallback path intact — removing it breaks any Codex run that still emits the legacy format.
- Do not increase `MaxIterations`. Do not introduce new top-level directories. Do not add any embedding / vector logic.
