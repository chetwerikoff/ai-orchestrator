# Task: Fix run_codex_reviewer.ps1 — prompt via temp file + exit-code + em-dash

## Project context
- `AGENTS.md`
- `.ai-loop/project_summary.md`
- `.ai-loop/repo_map.md`

## Goal

Fix three bugs in `run_codex_reviewer.ps1` introduced in C09:

1. **Command-line-too-long**: The reviewer passes the full prompt text as a positional CLI argument to `codex exec`. Windows limits command-line length to ~32 767 chars; a prompt that includes `task.md` context easily exceeds this, causing node.exe to refuse to start with *"The filename or extension is too long"*. Fix: write the prompt to a temp file and pass it via stdin or a supported file flag instead.

2. **`$exitCode` not initialized**: `$exitCode` was already fixed in the current file (line 29: `$exitCode = 1` before `try`). Verify this is present; if not, add it.

3. **Em-dash encoding (`?` corruption)**: Literal U+2014 characters in `.ps1` string literals and `.md` templates corrupt to `?` under Windows-1252 defaults. Replace per project convention.

## Scope

Allowed:
- Rewrite the codex invocation in `run_codex_reviewer.ps1` to use a temp file
- Fix `$exitCode` init if missing
- Replace literal em-dashes in `.ps1` files with `[char]0x2014`
- Replace literal em-dashes in `.md` templates with ` -- `
- Add `-Encoding UTF8` to `Get-Content` calls that read `.md` files in `ai_loop_plan.ps1`
- Add targeted pytest coverage

Not allowed:
- Changing function/parameter signatures
- Modifying scripts not listed in Files in scope
- Altering `ai_loop_auto.ps1`, `ai_loop_task_first.ps1`, `continue_ai_loop.ps1`

## Files in scope
- `scripts/run_codex_reviewer.ps1`        — temp-file fix + $exitCode + em-dash
- `scripts/run_claude_planner.ps1`        — em-dash (verify; fix if present)
- `scripts/ai_loop_plan.ps1`              — em-dash in string literals + Get-Content -Encoding UTF8
- `templates/reviewer_prompt.md`          — em-dash → ` -- `
- `templates/planner_prompt.md`           — em-dash → ` -- `
- `tests/test_orchestrator_validation.py` — add tests

## Files out of scope
- `docs/archive/**`
- `.ai-loop/_debug/**`
- `ai_loop.py`
- `scripts/ai_loop_auto.ps1`
- `scripts/ai_loop_task_first.ps1`
- `scripts/continue_ai_loop.ps1`
- All scripts not listed above

## Required behavior

### Fix 1 — prompt via temp file (run_codex_reviewer.ps1)

Replace the direct `& codex @codexArgs` invocation pattern with a temp-file approach:

```powershell
# Write prompt to temp file
$tempFile = Join-Path $env:TEMP "codex_review_$([System.IO.Path]::GetRandomFileName()).md"
[System.IO.File]::WriteAllText($tempFile, $promptText, [System.Text.Encoding]::UTF8)

try {
    # ... Push-Location etc ...

    # Check if codex exec supports --file/-f flag first:
    #   codex exec --help
    # If supported:
    #   & codex @modelArgs exec --file $tempFile
    # Otherwise fall back to stdin piping:
    #   Get-Content $tempFile | & codex @modelArgs exec
    # Use whichever form avoids passing the prompt as a positional arg.

    $exitCode = $LASTEXITCODE
}
finally {
    if ($pushed) { Pop-Location }
    Remove-Item $tempFile -ErrorAction SilentlyContinue
}
```

The `ConvertTo-CrtSafeArg` helper becomes unnecessary once the prompt is no longer a positional arg. Remove it if it has no other callers (check the file); otherwise leave it.

**How to determine the correct codex invocation**: run `codex exec --help` in the terminal and look for a `--file` or `-f` flag. If present, use it. If not, pipe the file content to stdin: `Get-Content $tempFile -Raw | codex @modelArgs exec`.

### Fix 2 — $exitCode initialization

Open `scripts/run_codex_reviewer.ps1`. Confirm `$exitCode = 1` appears before the outermost `try {`. If already present (check line ~29), no change needed — document "already present" in your summary.

### Fix 3 — em-dash encoding

- In `.ps1` files: replace each literal em-dash byte (UTF-8: `E2 80 94`) in string literals with `$([char]0x2014)`. Example: `"advisory only $([char]0x2014) the Architect"`.
- In `.md` templates: replace each `—` with ` -- `.
- In `ai_loop_plan.ps1`: add `-Encoding UTF8` to any `Get-Content` call reading a `.md` file.

## Tests

Add to `tests/test_orchestrator_validation.py`:

```python
def test_codex_reviewer_no_inline_prompt_arg():
    """Prompt must be passed via file or stdin, not as a positional CLI arg."""
    src = Path("scripts/run_codex_reviewer.ps1").read_text(encoding="utf-8")
    # ConvertTo-CrtSafeArg was the escaping helper for inline args — its presence
    # is a signal that the old approach is still in use.
    assert "ConvertTo-CrtSafeArg" not in src, (
        "run_codex_reviewer.ps1 still uses ConvertTo-CrtSafeArg; "
        "prompt must be passed via temp file, not as a positional arg"
    )

def test_codex_reviewer_exitcode_initialized():
    src = Path("scripts/run_codex_reviewer.ps1").read_text(encoding="utf-8")
    idx_init = src.find("$exitCode = 1")
    idx_try  = src.find("try {")
    assert idx_init != -1, "$exitCode = 1 not found"
    assert idx_init < idx_try, "$exitCode = 1 must appear before try {"

def test_no_emdash_bytes_in_ps1_scripts():
    for name in [
        "scripts/run_codex_reviewer.ps1",
        "scripts/run_claude_planner.ps1",
        "scripts/ai_loop_plan.ps1",
    ]:
        data = Path(name).read_bytes()
        assert b'\xe2\x80\x94' not in data, f"Literal em-dash found in {name}"
```

Run: `python -m pytest -q`

## Verification

```powershell
powershell -NoProfile -Command "[void][System.Management.Automation.Language.Parser]::ParseFile('scripts\run_codex_reviewer.ps1', [ref]`$null, [ref]`$null)"
powershell -NoProfile -Command "[void][System.Management.Automation.Language.Parser]::ParseFile('scripts\ai_loop_plan.ps1', [ref]`$null, [ref]`$null)"
python -m pytest -q
python -c "import sys; d=open('scripts/run_codex_reviewer.ps1','rb').read(); sys.exit(0 if b'\xe2\x80\x94' not in d else 1)"
```

Then run a live end-to-end smoke test:
```powershell
.\scripts\ai_loop_plan.ps1 -AskFile tasks\task_add_order_queue_support.md -WithReview
```
Confirm no *"filename or extension is too long"* error appears.

## Implementer summary requirements
1. List each file changed and the specific change (one line per file).
2. State which codex invocation form was used (file flag or stdin pipe) and why.
3. Confirm whether `$exitCode = 1` was already present or was added.
4. State which `.ps1` files had literal em-dashes and how many were replaced.
5. Test result: pass/fail count only.
6. Any remaining risks.

## Output hygiene
- Do not duplicate task content into `.ai-loop/project_summary.md`.
- Do not write debug output to `.ai-loop/_debug/`.
- Do not commit — the orchestrator handles git.
- Do not write to `docs/archive/`.
