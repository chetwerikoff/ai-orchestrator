# C07b — Codex semantic validator on top of planner

**Project:** `ai-orchestrator`
**CWD:** `C:\Users\che\Documents\Projects\ai-orchestrator`
**Prerequisite:** **C07a merged** (planner + deterministic validation must exist).
**Risk:** medium — extends an existing entrypoint, adds two new files, adds verdict parsing.

How to run:
```powershell
# Paste task spec below into .ai-loop\task.md, then:
powershell -ExecutionPolicy Bypass -File .\scripts\ai_loop_task_first.ps1 -NoPush
```

---

# Task: Codex semantic validator on top of the planner

## Project context

Required reading before starting:

1. `AGENTS.md` at repo root
2. `.ai-loop/task.md` — this task
3. `.ai-loop/project_summary.md`
4. `.ai-loop/repo_map.md`
5. `scripts/ai_loop_plan.ps1` (from C07a) — entrypoint to extend
6. `scripts/ai_loop_auto.ps1` — `Run-CodexReview` (around line 326-413), shows
   `codex exec`, `ConvertTo-CrtSafeArg`, single-quoted here-string pattern
7. `scripts/ai_loop_task_first.ps1` — source of `ConvertTo-CrtSafeArg` to
   duplicate in the validator wrapper
8. `scripts/run_claude_planner.ps1` (from C07a) — wrapper convention to mirror
9. `templates/codex_review_prompt.md` — existing Codex prompt format
   (compare for style, do NOT reuse)
10. `.ai-loop/implementer_summary.md` — only if iteration 2+

Do not read by default:
- `docs/archive/`
- `.ai-loop/_debug/`
- `tasks/C07_risks_gpt_validator_review.md` — review notes used only to inform this spec

## Goal

Extend `scripts/ai_loop_plan.ps1` (from C07a) with an opt-in Codex validator
pass. Validator is a separate wrapper for genuine independence from the Claude
planner: Claude (Anthropic) plans → Codex (OpenAI-family) cross-checks.

```
ai_loop_plan.ps1 -WithValidator
                 [-ValidatorCommand .\scripts\run_codex_validator.ps1]
                 [-ValidatorModel "..."]
```

Verdict goes to `.ai-loop/planner_validation.md`. Stale-detection via SHA256
hashes of ASK and task.md so the user knows when a manual edit invalidated the
verdict.

### Deliverables

1. `scripts/run_codex_validator.ps1` — Codex validator wrapper.
2. `templates/validator_prompt.md` — validator role + adversarial verdict format.
3. `scripts/ai_loop_plan.ps1` — add `-WithValidator`, `$ValidatorCommand`,
   `$ValidatorModel` parameters and the validator path (steps after the write).
4. `scripts/install_into_project.ps1` — copy the two new files.
5. `tests/test_orchestrator_validation.py` — structural + verdict-parsing
   behavior tests.

## Scope

Allowed:
- Create `scripts/run_codex_validator.ps1`
- Create `templates/validator_prompt.md`
- Edit `scripts/ai_loop_plan.ps1` (add validator parameters and path; do NOT
  rewrite the planner flow from C07a)
- Edit `scripts/install_into_project.ps1`
- Edit `tests/test_orchestrator_validation.py`
- Edit `.ai-loop/project_summary.md` (Architecture, Stage, Next Steps)

Not allowed:
- Any changes to `scripts/ai_loop_auto.ps1`, `scripts/ai_loop_task_first.ps1`,
  `scripts/continue_ai_loop.ps1`
- Changes to existing wrappers (`run_cursor_agent.ps1`,
  `run_opencode_agent.ps1`, `run_opencode_scout.ps1`, `run_scout_pass.ps1`,
  `run_claude_planner.ps1`)
- Changes to `templates/codex_review_prompt.md`, `templates/planner_prompt.md`
- Edits to `AGENTS.md`, other templates, `src/`, `ai_loop.py`, docs
- Calling `codex` or `claude` CLIs from tests
- Reworking deterministic validation from C07a

## Files in scope

- `scripts/run_codex_validator.ps1` (new)
- `templates/validator_prompt.md` (new)
- `scripts/ai_loop_plan.ps1` (edit — add validator parameters + path)
- `scripts/install_into_project.ps1` (edit — two new copy lines)
- `tests/test_orchestrator_validation.py` (edit)
- `.ai-loop/project_summary.md` (edit)

## Files out of scope

- `scripts/ai_loop_auto.ps1`
- `scripts/ai_loop_task_first.ps1`
- `scripts/continue_ai_loop.ps1`
- `scripts/run_cursor_agent.ps1`
- `scripts/run_opencode_agent.ps1`
- `scripts/run_opencode_scout.ps1`
- `scripts/run_claude_planner.ps1`
- `templates/codex_review_prompt.md`
- `templates/planner_prompt.md`
- `AGENTS.md`
- `docs/**`
- `docs/archive/**`
- `.ai-loop/_debug/**`
- `ai_loop.py`

## Required behavior

### scripts/run_codex_validator.ps1

Codex's CLI takes the prompt as a positional argument to `codex exec`, not via
stdin. The wrapper bridges the project's stdin-pipe wrapper convention to that
calling style:

- **No `param()` block** (preserves `$input` for stdin compatibility with the
  way `ai_loop_plan.ps1` invokes wrappers).
- Parse `--workspace` and `--model` from `$args`; silently ignore unknown flags.
- Read prompt from `$input` into a single string (`$input | Out-String` then
  `.TrimEnd()`). Empty → `Write-Error` + exit 1.
- `Push-Location` to workspace if provided; `Pop-Location` in `finally`.
- Duplicate `ConvertTo-CrtSafeArg` (5-line regex helper) locally — same body
  as in `ai_loop_task_first.ps1`. Do not import from another script.
- Build `$codexArgs`:
  - If `$model` is non-empty, prepend a model flag in the form Codex CLI
    expects (mirror `Run-CodexReview` behavior; if `Run-CodexReview` does not
    pass a model flag, neither should this wrapper — model defaults are set
    by the Codex CLI/config).
  - Append `"exec"` and `(ConvertTo-CrtSafeArg -Value $promptText)`.
- Invoke `& codex @codexArgs` — output goes to stdout (captured by caller).
- **No `2>&1`** — stdout-only is captured.
- `exit $LASTEXITCODE`.

Keep under 70 lines (slightly larger than other wrappers because of the
ConvertTo-CrtSafeArg helper and the Codex-specific arg assembly).

### templates/validator_prompt.md

Adversarial role framing — the validator MUST resist agreement bias on
well-formatted output.

```markdown
# Validator role

You are the VALIDATOR. Compare a generated `task.md` against the ORIGINAL USER
ASK and the project context provided below. Decide whether the planner
produced a faithful, implementable contract.

## What you are NOT

- You are NOT a co-architect.
- You are NOT allowed to rewrite, improve, or restructure the task.
- You do NOT propose alternative implementations or architectures.
- "Well-formatted" does NOT mean "correct". Resist agreement bias.

## What to check

1. **Faithfulness to ASK.** Does the task.md solve the problem in the ASK, or
   has it drifted to a different problem?
2. **Required ASK details preserved.** Does the task.md omit any concrete
   requirement, constraint, or acceptance criterion from the ASK?
3. **Plausible files.** Are paths under `## Files in scope` and
   `## Files out of scope` consistent with `AGENTS.md`, `project_summary.md`,
   and `repo_map.md`? Are any paths obviously invented?
4. **Scope reasonable.** Is `## Files in scope` neither too broad nor missing
   files the task obviously needs? Is the change realistically ≤80 lines?
5. **Acceptance testable.** Are `## Verification` commands concrete and
   directly tied to `## Goal`?
6. **Assumptions surfaced.** If the ASK was ambiguous, does `## Important`
   list the assumptions the planner made, or does it silently choose defaults?

## Verdict rules

- Output `PASS` only when **all six checks** pass cleanly.
- Output `WARN` when checks pass but assumptions are unclear, scope is at
  the edge, or acceptance criteria are vague.
- Output `FAIL` when the task.md solves a different problem, invents files,
  expands scope materially, drops a required ASK detail, or has uninstall
  paths in scope.
- **Prefer WARN over PASS** when in doubt.
- **Prefer FAIL over WARN** when a hard rule is broken (invented files,
  omitted ASK requirement, missing required out-of-scope path).

## Output format

Output ONLY these lines, nothing else. No preamble. No markdown fence around
the output. No additional explanation after `ISSUES:`.

```
VERDICT: PASS | WARN | FAIL
SUMMARY: <one sentence>
ISSUES:
- <issue 1>
- <issue 2>
```

If `VERDICT: PASS`, the `ISSUES:` list may be empty or omitted entirely.
```

### scripts/ai_loop_plan.ps1 — extension only

Add three parameters to the `param()` block from C07a (do NOT touch the others):

```powershell
[string]$ValidatorCommand = ".\scripts\run_codex_validator.ps1",
[string]$ValidatorModel = "",
[switch]$WithValidator
```

**Prerequisite check:** if `-WithValidator`, also require:
- `$ValidatorCommand` exists
- `.ai-loop/validator_prompt.md` exists

(Both checked alongside the existing C07a prereq block; exit 1 with explicit
"missing X" otherwise.)

**Validator path** — append after step 10 (the success message) from C07a.
The planner has already written `$Out` and printed success. Validator runs
**post-write**:

11. Compute hashes:
    ```powershell
    $askSha = SHA256 of resolved ask string
    $taskSha = SHA256 of file contents at $Out
    ```
    Use `Get-FileHash -Algorithm SHA256` for the file; for the ask string,
    write to a temp file or convert via `[System.Security.Cryptography.SHA256]`.

12. Build the validator prompt by concatenating:
    - Contents of `.ai-loop/validator_prompt.md`
    - `## USER ASK` + resolved ask
    - `## GENERATED task.md` + contents of `$Out`
    - `## AGENTS.md` + contents of `AGENTS.md`
    - `## project_summary.md` + contents of `.ai-loop/project_summary.md`
    - `## repo_map.md` + contents of `.ai-loop/repo_map.md` if present

13. Invoke validator wrapper:
    ```powershell
    $validatorOutput = $validatorPrompt | & $ValidatorCommand --workspace $ProjectRoot --model $ValidatorModel
    ```
    No `2>&1`. If `$LASTEXITCODE -ne 0`: print warning and exit 0 (validator
    failure is non-fatal — task.md is already written; user proceeds with
    plain deterministic validation result). Skip steps 14-16.

14. Write `.ai-loop/planner_validation.md`:
    ```
    # Planner validation report
    
    ASK_SHA256: <hash>
    TASK_SHA256: <hash>
    GENERATED_AT: <ISO 8601 UTC>
    VALIDATOR: <full path of $ValidatorCommand>
    
    <captured $validatorOutput>
    ```
    Note the warning at the top:
    `> Re-run validation after manual edits to task.md (hashes will differ).`

15. Parse verdict from `$validatorOutput`:
    - Find the first non-blank line matching the pattern
      `^VERDICT:\s*(PASS|WARN|FAIL)\b` (case-sensitive). If no match: treat as
      WARN (validator output malformed; better not to silently PASS).

16. Map verdict → exit code:
    - `PASS` → print `Validator: PASS — no obvious issues found.`, exit 0
    - `WARN` → print `Validator: WARN — see .ai-loop/planner_validation.md.`,
      exit 0
    - `FAIL` → print `Validator: FAIL — see .ai-loop/planner_validation.md.
      task.md was written; review carefully or regenerate.`, exit 3

All `Validator:` console messages must explicitly include "no obvious issues
found" rather than "task is correct" — even on PASS. The point is to avoid
false confidence.

Updated exit codes (in addition to C07a's 0/1/2):
- 3: validator returned FAIL (file IS written so user can fix manually)

Keep total `ai_loop_plan.ps1` under 320 lines after this extension.

### scripts/install_into_project.ps1

Add `Copy-Item -Force` lines:
- `scripts/run_codex_validator.ps1` → target `scripts/`
- `templates/validator_prompt.md` → target `.ai-loop/validator_prompt.md`

## Tests

Run:
```bash
python -m pytest -q
```

Add to `tests/test_orchestrator_validation.py`:

**Structural tests:**

1. `test_run_codex_validator_script_exists`
2. `test_validator_prompt_template_exists`
3. `test_run_codex_validator_parses_cleanly` — add to existing parse-check list.
4. `test_run_codex_validator_has_no_param_block`
5. `test_run_codex_validator_uses_codex_exec` — assert the wrapper contains
   `codex` invocation AND the literal `"exec"`.
6. `test_run_codex_validator_has_convert_to_crt_safe_arg` — assert wrapper
   contains a `ConvertTo-CrtSafeArg` function definition (mirrors
   `ai_loop_task_first.ps1`).
7. `test_run_codex_validator_no_stderr_redirect` — no `2>&1`.
8. `test_ai_loop_plan_has_validator_parameters` — assert `ai_loop_plan.ps1`
   declares `$ValidatorCommand`, `$ValidatorModel`, `$WithValidator`.
9. `test_ai_loop_plan_default_validator_is_codex` — assert literal
   `$ValidatorCommand = ".\scripts\run_codex_validator.ps1"` present.
10. `test_validator_prompt_has_adversarial_framing` — assert
    `templates/validator_prompt.md` contains the literals
    `NOT a co-architect`, `Prefer WARN over PASS`, `Prefer FAIL over WARN`.
11. `test_validator_prompt_has_verdict_format` — contains `VERDICT: PASS`,
    `WARN`, `FAIL` literals AND `SUMMARY:` AND `ISSUES:`.
12. `test_install_copies_validator_files` — assert
    `install_into_project.ps1` copies `run_codex_validator.ps1` and
    `validator_prompt.md`.

**Behavior tests for verdict parsing** (no API calls):

The implementer must expose a parseable verdict-extraction helper inside
`ai_loop_plan.ps1` (e.g. `Get-ValidatorVerdict` function callable via dot-source
in a test harness), OR provide an equivalent `-RunVerdictTest` switch.

13. `test_verdict_parser_extracts_pass` — fixture string starting with
    `VERDICT: PASS\nSUMMARY: ...`; assert helper returns `PASS`.
14. `test_verdict_parser_extracts_warn` — same with `WARN`.
15. `test_verdict_parser_extracts_fail` — same with `FAIL`.
16. `test_verdict_parser_handles_leading_blank_lines` — fixture has 2 blank
    lines before `VERDICT:`; assert correct extraction.
17. `test_verdict_parser_defaults_to_warn_on_malformed` — fixture missing
    `VERDICT:` line entirely; assert helper returns `WARN`.
18. `test_planner_validation_report_includes_hashes` — write a fake validator
    output and run a unit harness that calls the report-writer helper; assert
    the produced `.ai-loop/planner_validation.md` contains `ASK_SHA256:` and
    `TASK_SHA256:` lines.

Do NOT call `codex` or `claude` CLIs in tests.

## Verification

```bash
python -m pytest -q
```

```powershell
powershell -NoProfile -Command "[void][System.Management.Automation.Language.Parser]::ParseFile('scripts\run_codex_validator.ps1', [ref]$null, [ref]$null)"
powershell -NoProfile -Command "[void][System.Management.Automation.Language.Parser]::ParseFile('scripts\ai_loop_plan.ps1', [ref]$null, [ref]$null)"
```

Manual smoke (requires authenticated `claude` and `codex` CLIs), in a fresh
temp dir:
```powershell
$tmp = Join-Path $env:TEMP "ai_orch_smoke_$(Get-Random)"
New-Item -ItemType Directory -Path $tmp | Out-Null
git -C $tmp init | Out-Null
.\scripts\install_into_project.ps1 -TargetProject $tmp
Set-Location $tmp
.\scripts\ai_loop_plan.ps1 -Ask "Add a smoke test that prints OK" -WithValidator -Out .ai-loop\task_smoke.md
Get-Content .ai-loop\planner_validation.md
Set-Location -; Remove-Item -Recurse -Force $tmp
```

## Implementer summary requirements

Update `.ai-loop/implementer_summary.md`:

1. Changed files.
2. Test result (count only).
3. What was implemented (3–5 lines).
4. What was skipped and why.
5. Remaining risks.

## Project summary update

Update `.ai-loop/project_summary.md`:

- Architecture section: add one line each for `run_codex_validator.ps1` and
  `templates/validator_prompt.md`.
- Architecture note: default validator is **Codex** for genuine independence
  from the Claude planner (different model family; already a project
  dependency). Wrappers are pluggable via `-ValidatorCommand`.
- Update Current Stage (C07b complete) and Next Likely Steps.

## Output hygiene

The implementer must not:

- duplicate this task description into `.ai-loop/implementer_summary.md`
- include earlier task narrative in `.ai-loop/project_summary.md`
- write to `.ai-loop/_debug/` or `docs/archive/`
- commit or push (the orchestrator handles git)

## Important

**C07a must be merged first.** This task ONLY adds the validator path. Do NOT
restructure the planner flow from C07a. If C07a's `ai_loop_plan.ps1` does not
exist, exit with an error rather than attempting both tasks.

**Codex calling style differs from Claude.** Codex CLI takes the prompt as a
**positional argument** to `codex exec`, not via stdin. The wrapper accepts
stdin (for caller consistency) but internally passes the prompt as an arg.
Use `ConvertTo-CrtSafeArg` to escape — copy the function from
`ai_loop_task_first.ps1`.

**Adversarial validator prompt.** The template MUST contain the literals
`NOT a co-architect`, `Prefer WARN over PASS`, `Prefer FAIL over WARN`. The
goal is to resist agreement bias on well-formatted task.md output.

**Validator failure is non-fatal.** If the Codex CLI returns non-zero, the
task.md is already written — print a warning and exit 0. Do not pretend the
validator succeeded.

**Malformed verdict → WARN, not PASS.** If the validator output does not
contain a parseable `VERDICT:` line, default to WARN. Silently treating a
malformed response as PASS would defeat the point of the validator.

**SHA256 hashes** of ASK and task.md go into `planner_validation.md` header
so the user can detect stale verdicts after manual edits. Include a one-line
notice: "Re-run validation after manual edits".

**Wrapper convention reminders:**
- No `param()` block.
- No `2>&1`.
- Mirror `run_opencode_agent.ps1` and `run_claude_planner.ps1` patterns.

**Verdict messaging.** Never say "task is correct" — only "no obvious issues
found". The human reviewer is still the business-logic gate.

**Path of the validator report.** `.ai-loop/planner_validation.md` is
gitignored (already added in C07a). If C07a did not add it, add it now —
otherwise leave `.gitignore` alone.

**Backup interaction.** Validator runs AFTER successful write of `$Out`.
Validator FAIL does NOT trigger backup restore — the user explicitly may want
to fix the written task.md manually. Backup restore only on planner/wrapper
errors or deterministic Errors (C07a paths).

**Future wrappers.** `run_gpt_validator.ps1`, `run_claude_validator.ps1`,
`run_local_validator.ps1` can be added later as separate tasks. They must
satisfy the same wrapper contract (stdin in, stdout out, no `2>&1`, no
`param()`).
