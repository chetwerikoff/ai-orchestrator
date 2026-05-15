"""Orchestrator checks: PowerShell AST parse + path-set delta semantics (task-first gate)."""

from __future__ import annotations

import re
import shutil
import subprocess
import textwrap
import uuid
from collections.abc import Iterator
from pathlib import Path

import pytest

_ROOT = Path(__file__).resolve().parent.parent
_TESTS_DIR = Path(__file__).resolve().parent


def _orch_scratch(prefix: str) -> Path:
    """Unique work dir under tests/ — avoids Windows PermissionError on pytest tmp_path roots."""
    return _TESTS_DIR / f".orch_{prefix}_{uuid.uuid4().hex}"


@pytest.fixture
def orch_preflight_dir() -> Iterator[Path]:
    root = _orch_scratch("task_first_preflight")
    root.mkdir(parents=True, exist_ok=True)
    yield root
    shutil.rmtree(root, ignore_errors=True)


_SCRIPTS = _ROOT / "scripts"
_PS1_TARGETS = (
    "ai_loop_auto.ps1",
    "ai_loop_task_first.ps1",
    "continue_ai_loop.ps1",
    "build_repo_map.ps1",
    "run_scout_pass.ps1",
    "wrap_up_session.ps1",
    "promote_session.ps1",
)
_SAFEADD_DEFAULT_RE = re.compile(
    r"\[string\]\$SafeAddPaths\s*=\s*\"([^\"]+)\"",
    re.MULTILINE,
)
_AGENTS_SAFEADD_LITERAL_RE = re.compile(r"The default `SafeAddPaths` literal is `([^`]+)`")

RESULT_NORM = ".ai-loop/implementer_result.md"


def _extract_implementer_prompt_assembly_from_task_first(ps1_text: str) -> str:
    """Exact `Invoke-ImplementerImplementation` slice that builds `$prompt` (C02 contract)."""
    lines = ps1_text.splitlines()
    start = next(
        i
        for i, line in enumerate(lines)
        if "$scope = Get-TaskScopeBlocks -TaskFile $TaskFile" in line
    )
    end = next(
        i
        for i, line in enumerate(lines)
        if "$prompt = $STABLE_PREAMBLE +" in line and "$taskText" in line
    )
    return "\n".join(lines[start : end + 1])


# Mirrors `Extract-FixPromptFromFile` in scripts/ai_loop_auto.ps1 — keep alternation order in sync.
_FIX_PROMPT_LABEL_RE = re.compile(
    r"FIX_PROMPT_FOR_IMPLEMENTER:\s*"
    r"(?P<prompt>[\s\S]*?)FINAL_NOTE:",
    re.IGNORECASE,
)
_FIX_PROMPT_TAIL_RE = re.compile(
    r"FIX_PROMPT_FOR_IMPLEMENTER:\s*(?P<prompt>[\s\S]*)",
    re.IGNORECASE,
)


def _extract_fix_prompt_ps_functions_from_auto(ps1_text: str) -> str:
    """`Format-FixPromptFromObject` + `Extract-FixPromptFromFile` from ai_loop_auto.ps1 (C03 harness)."""
    start = ps1_text.index("function Format-FixPromptFromObject")
    end = ps1_text.index("function Write-NextImplementerPrompt", start)
    return ps1_text[start:end]


def extract_fix_prompt_from_review_text(review: str) -> str | None:
    """Same contract as PowerShell `Extract-FixPromptFromFile` (primary match then tail fallback)."""
    m = _FIX_PROMPT_LABEL_RE.search(review)
    if m:
        body = m.group("prompt").strip()
    else:
        tail = _FIX_PROMPT_TAIL_RE.search(review)
        if not tail:
            return None
        body = tail.group("prompt").strip()
    if not body or body.lower() == "none":
        return None
    return body


def _default_safe_add_paths_from_agents_md() -> str:
    text = (_ROOT / "AGENTS.md").read_text(encoding="utf-8")
    m = _AGENTS_SAFEADD_LITERAL_RE.search(text)
    assert m is not None, "AGENTS.md must document the default SafeAddPaths backtick literal"
    return m.group(1).strip()


def _default_safe_add_paths_from_safety_md() -> str:
    t = (_ROOT / "docs" / "safety.md").read_text(encoding="utf-8")
    m = re.search(r"```text\r?\n([\s\S]*?)\r?\n```", t)
    assert m is not None, "docs/safety.md must contain a ```text fenced safe paths block"
    lines = [ln.strip() for ln in m.group(1).splitlines() if ln.strip()]
    return ",".join(lines)


def _default_safe_add_paths_literal(script: Path) -> str:
    text = script.read_text(encoding="utf-8")
    m = _SAFEADD_DEFAULT_RE.search(text)
    assert m is not None, f"no [string]$SafeAddPaths default in {script}"
    return m.group(1).strip()


def test_default_safe_add_paths_parity_includes_docs_and_templates() -> None:
    """Orchestrator entrypoints must agree on SafeAddPaths defaults; AGENTS.md and docs/safety.md must match."""
    names = ("ai_loop_auto.ps1", "ai_loop_task_first.ps1", "continue_ai_loop.ps1")
    literals = [_default_safe_add_paths_literal(_SCRIPTS / n) for n in names]
    assert len(set(literals)) == 1, dict(zip(names, literals, strict=True))
    canonical = literals[0]
    assert _default_safe_add_paths_from_agents_md() == canonical
    assert _default_safe_add_paths_from_safety_md() == canonical
    segments = [s.strip() for s in canonical.split(",") if s.strip()]
    assert "tasks/" in segments
    assert "AGENTS.md" in segments
    assert "docs/" in segments
    assert "templates/" in segments


def test_task_first_porcelain_uses_untracked_files_all() -> None:
    """Nested untracked paths must appear in porcelain; default mode can hide them."""
    text = (_SCRIPTS / "ai_loop_task_first.ps1").read_text(encoding="utf-8")
    assert "git status --porcelain --untracked-files=all" in text


def test_completion_banner_separator_present() -> None:
    """ai_loop_task_first.ps1 must contain the banner separator string."""
    content = Path("scripts/ai_loop_task_first.ps1").read_text(encoding="utf-8")
    assert "==============================" in content, (
        "completion banner separator missing from ai_loop_task_first.ps1"
    )


def test_task_name_banners_present() -> None:
    """Both START and DONE banners must reference the task name variable."""
    content = Path("scripts/ai_loop_task_first.ps1").read_text(encoding="utf-8")
    assert "AI LOOP TASK:" in content and "START" in content, (
        "START banner with task name missing from ai_loop_task_first.ps1"
    )
    assert "AI LOOP TASK:" in content and "DONE" in content, (
        "DONE banner with task name missing from ai_loop_task_first.ps1"
    )


def test_auto_porcelain_uses_untracked_files_all_for_noop_guard() -> None:
    text = (_SCRIPTS / "ai_loop_auto.ps1").read_text(encoding="utf-8")
    assert "git status --porcelain --untracked-files=all" in text


def test_ai_loop_auto_has_clean_tree_noop_guard_reasons() -> None:
    text = (_SCRIPTS / "ai_loop_auto.ps1").read_text(encoding="utf-8")
    assert "REVIEW_STARTED_ON_CLEAN_TREE" in text
    assert "NO_CHANGES_AFTER_IMPLEMENTER_FIX" in text


def test_claude_final_review_prompt_template_removed() -> None:
    assert not (_ROOT / "templates" / "claude_final_review_prompt.md").exists()


def _powershell_exe() -> str | None:
    return shutil.which("pwsh") or shutil.which("powershell")


def _powershell_build_implementer_prompt_from_task_first_script(
    repo_root: Path, work_dir: Path, task_md_body: str
) -> str:
    """Load the real `$STABLE_PREAMBLE` / `Get-TaskScopeBlocks` and run the same assembly lines as the script."""
    ps = _powershell_exe()
    if not ps:
        pytest.skip("No pwsh or powershell on PATH")

    script_text = (_SCRIPTS / "ai_loop_task_first.ps1").read_text(encoding="utf-8")
    anchor = '$ResultPathRelative = ".ai-loop/implementer_result.md"'
    assert anchor in script_text, "ai_loop_task_first.ps1 must keep ResultPathRelative line for harness loading"
    assembly = _extract_implementer_prompt_assembly_from_task_first(script_text)

    work_dir.mkdir(parents=True, exist_ok=True)
    ai_loop = work_dir / ".ai-loop"
    ai_loop.mkdir(parents=True, exist_ok=True)
    task_file = ai_loop / "task.md"
    task_file.write_text(task_md_body, encoding="utf-8")

    assembly_path = work_dir / "_orch_prompt_assembly.ps1"
    assembly_path.write_text(assembly + "\n", encoding="utf-8")

    out_path = work_dir / "_orch_prompt_out.txt"
    harness_path = work_dir / "_orch_harness_build_prompt.ps1"
    harness_body = rf"""
$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath $PSScriptRoot
$src = [System.IO.File]::ReadAllText([System.IO.Path]::Combine($args[0], 'scripts', 'ai_loop_task_first.ps1'))
$anchor = '$ResultPathRelative = ".ai-loop/implementer_result.md"'
$idx = $src.IndexOf($anchor)
if ($idx -lt 0) {{ throw "Anchor not found: $anchor" }}
$head = $src.Substring(0, $idx + $anchor.Length)
. ([scriptblock]::Create($head))
$TaskFile = [System.IO.Path]::Combine($ProjectRoot, '.ai-loop', 'task.md')
$RelevantFiles = @()
. (Join-Path $PSScriptRoot '_orch_prompt_assembly.ps1')
$enc = New-Object System.Text.UTF8Encoding $false
[System.IO.File]::WriteAllText([System.IO.Path]::Combine($PSScriptRoot, '_orch_prompt_out.txt'), $prompt, $enc)
"""
    harness_path.write_text(harness_body.strip() + "\n", encoding="utf-8")

    proc = subprocess.run(
        [ps, "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", str(harness_path), str(repo_root.resolve())],
        cwd=str(work_dir),
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        timeout=120,
    )
    detail = (proc.stdout or "") + (proc.stderr or "")
    assert proc.returncode == 0, f"PowerShell harness failed ({proc.returncode}):\n{detail}"

    return out_path.read_text(encoding="utf-8")


def test_powershell_orchestrator_scripts_parse_cleanly() -> None:
    """PowerShell parser must accept both driver scripts (no syntax errors)."""
    ps = _powershell_exe()
    if not ps:
        pytest.skip("No pwsh or powershell on PATH")

    for name in _PS1_TARGETS:
        script = _SCRIPTS / name
        assert script.is_file(), f"missing {script}"
        escaped = str(script.resolve()).replace("'", "''")
        cmd = (
            f"$errs=$null;$tok=$null;"
            f"[void][System.Management.Automation.Language.Parser]::ParseFile('{escaped}',[ref]$tok,[ref]$errs);"
            "if ($errs.Count) { $errs | ForEach-Object { $_.ToString() } | Write-Output; exit 1 };"
            "exit 0"
        )
        proc = subprocess.run(
            [ps, "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", cmd],
            capture_output=True,
            text=True,
            timeout=120,
            check=False,
        )
        detail = proc.stdout.strip() + proc.stderr.strip()
        assert proc.returncode == 0, f"{name}: parser reported errors:\n{detail}"


def _paths_from_porcelain_line(line: str) -> list[str]:
    """Normalize paths from one `git status --porcelain` line."""
    stripped = line.rstrip()
    if len(stripped) < 4:
        return []
    rest = stripped[3:].strip()
    if " -> " in rest:
        parts = rest.split(" -> ")
        return [p.strip().replace("\\", "/") for p in parts]
    return [rest.replace("\\", "/")]


def _path_to_line_map(lines: list[str]) -> dict[str, str]:
    mapping: dict[str, str] = {}
    for line in lines:
        if not line.strip():
            continue
        trimmed = line.rstrip()
        for path in _paths_from_porcelain_line(trimmed):
            mapping[path] = trimmed
    return mapping


def implementer_produced_paths(before_lines: list[str], after_lines: list[str]) -> set[str]:
    """Paths whose porcelain line differs between snapshots (legacy line-level delta)."""
    before_map = _path_to_line_map(before_lines)
    after_map = _path_to_line_map(after_lines)
    changed: set[str] = set()
    for path in set(before_map) | set(after_map):
        b_line = before_map.get(path)
        a_line = after_map.get(path)
        missing_diff = (b_line is None) != (a_line is None)
        content_diff = b_line is not None and a_line is not None and b_line != a_line
        if missing_diff or content_diff:
            changed.add(path)
    return changed


def test_porcelain_delta_ignores_unchanged_preexisting_dirty_paths() -> None:
    dirty_task = " M .ai-loop/task.md"
    result_line = " M .ai-loop/implementer_result.md"
    before = [dirty_task]
    after = [dirty_task, result_line]
    assert implementer_produced_paths(before, after) == {".ai-loop/implementer_result.md"}


def test_porcelain_delta_empty_when_no_line_change() -> None:
    dirty = " M README.md"
    assert implementer_produced_paths([dirty], [dirty]) == set()


def test_porcelain_delta_detects_modified_file_status_change() -> None:
    assert implementer_produced_paths([" M README.md"], ["MM README.md"]) == {"README.md"}


def path_set_delta(before_paths: set[str], after_paths: set[str], *, result_changed_during_pass: bool) -> set[str]:
    """Mirror task-first gate: symmetric difference of implementation path sets plus optional result path."""
    delta = before_paths ^ after_paths
    if result_changed_during_pass:
        delta = set(delta) | {RESULT_NORM}
    return delta


def test_marker_enforcement_predicate_matches_sole_result_delta() -> None:
    before = {".ai-loop/task.md"}
    after = {".ai-loop/task.md", RESULT_NORM}
    delta = path_set_delta(before, after, result_changed_during_pass=False)
    assert delta == {RESULT_NORM}
    enforce_marker = len(delta) == 1 and RESULT_NORM in delta
    assert enforce_marker is True


def test_result_fs_change_merges_into_delta_when_porcelain_paths_unchanged() -> None:
    before = {".ai-loop/task.md"}
    after = set(before)
    delta = path_set_delta(before, after, result_changed_during_pass=True)
    assert delta == {RESULT_NORM}


def test_sole_result_delta_triggers_marker_gate() -> None:
    before = {"README.md"}
    after = set(before)
    delta = path_set_delta(before, after, result_changed_during_pass=True)
    assert delta == {RESULT_NORM}
    assert len(delta) == 1 and RESULT_NORM in delta


def test_summary_only_paths_filtered_no_side_effects_in_path_set_model() -> None:
    """Scratch paths are excluded from sets; identical before/after -> no xor delta."""
    before: set[str] = set()
    after: set[str] = set()
    delta = path_set_delta(before, after, result_changed_during_pass=False)
    assert delta == set()


def test_preexisting_dirty_task_does_not_hide_result_only_delta() -> None:
    before = {".ai-loop/task.md"}
    after = set(before)
    delta = path_set_delta(before, after, result_changed_during_pass=True)
    enforce_marker = len(delta) == 1 and RESULT_NORM in delta
    assert enforce_marker is True


def test_real_project_delta_with_result_change_is_not_result_only_gate() -> None:
    before: set[str] = set()
    after = {"README.md"}
    delta = path_set_delta(before, after, result_changed_during_pass=True)
    only_result = len(delta) == 1 and RESULT_NORM in delta
    assert only_result is False
    assert "README.md" in delta and RESULT_NORM in delta


def test_had_implementation_delta_from_path_sets_xor_or_result() -> None:
    assert path_set_delta({"a"}, {"a", "b"}, result_changed_during_pass=False) == {"b"}
    assert path_set_delta({"a"}, {"a"}, result_changed_during_pass=True) == {RESULT_NORM}
    assert path_set_delta({"a"}, {"a"}, result_changed_during_pass=False) == set()


def had_implementation_paths_delta(before: list[str], after: list[str]) -> bool:
    """Mirror Compare-Object @($beforePaths) @($afterPaths) on unique path strings (empty vs null-safe)."""
    return set(before) != set(after)


def test_empty_before_empty_after_path_sets_no_delta() -> None:
    """Regression: task-first must not treat two empty path sets as a Compare-Object edge case."""
    assert had_implementation_paths_delta([], []) is False


def test_empty_before_nonempty_after_path_sets_has_delta() -> None:
    """Regression: clean tree then one new path must register as a path delta."""
    assert had_implementation_paths_delta([], ["README.md"]) is True


def test_invoke_implementer_implementation_wraps_path_sets_for_compare_object() -> None:
    text = (_SCRIPTS / "ai_loop_task_first.ps1").read_text(encoding="utf-8")
    assert "$beforePaths = @(Get-ImplementationDeltaPaths)" in text
    assert "$afterPaths = @(Get-ImplementationDeltaPaths)" in text
    assert "Compare-Object @($beforePaths) @($afterPaths)" in text


def test_native_argv_escape_present_in_both_scripts() -> None:
    """PS 5.1 native-arg quoting workaround: ConvertTo-CrtSafeArg must be defined in both drivers.

    ai_loop_auto.ps1     — uses the helper for Codex prompts (codex exec argv).
    ai_loop_task_first.ps1 — defines the helper but Cursor prompt is now delivered via
                             stdin through run_cursor_agent.ps1 (avoids cmd.exe batch-line
                             limit), so no ConvertTo-CrtSafeArg -Value call is required there.
    """
    for name in ("ai_loop_task_first.ps1", "ai_loop_auto.ps1"):
        text = (_SCRIPTS / name).read_text(encoding="utf-8")
        assert "function ConvertTo-CrtSafeArg" in text, f"{name} missing ConvertTo-CrtSafeArg definition"
    auto = (_SCRIPTS / "ai_loop_auto.ps1").read_text(encoding="utf-8")
    assert "ConvertTo-CrtSafeArg -Value" in auto, "ai_loop_auto.ps1 must escape Codex prompt via ConvertTo-CrtSafeArg"


def test_ai_loop_auto_writes_diff_summary() -> None:
    script = (_SCRIPTS / "ai_loop_auto.ps1").read_text(encoding="utf-8")
    assert "diff_summary.txt" in script
    assert "git diff --stat" in script


def test_ai_loop_auto_invokes_pytest_failure_filter() -> None:
    script = (_SCRIPTS / "ai_loop_auto.ps1").read_text(encoding="utf-8")
    assert "filter_pytest_failures.py" in script


def test_default_safe_add_paths_includes_implementer_summary() -> None:
    lit = _default_safe_add_paths_literal(_SCRIPTS / "ai_loop_auto.ps1")
    assert ".ai-loop/implementer_summary.md" in lit
    assert ".ai-loop/cursor_summary.md" not in lit


def test_fix_prompt_label_is_implementer_only_in_ai_loop_auto() -> None:
    text = (_SCRIPTS / "ai_loop_auto.ps1").read_text(encoding="utf-8")
    assert "FIX_PROMPT_FOR_IMPLEMENTER" in text
    assert "FIX_PROMPT_FOR_CURSOR" not in text


def test_runtime_cleanup_uses_only_neutral_next_prompt() -> None:
    for name in ("ai_loop_auto.ps1", "ai_loop_task_first.ps1"):
        text = (_SCRIPTS / name).read_text(encoding="utf-8")
        assert ".ai-loop/next_implementer_prompt.md" in text
        assert ".ai-loop/next_cursor_prompt.md" not in text


def test_resume_uses_neutral_next_prompt_file_only() -> None:
    text = (_SCRIPTS / "ai_loop_auto.ps1").read_text(encoding="utf-8")
    start = text.index("function Try-ResumeFromExistingReview")
    chunk = text[start:]
    assert "Resuming from existing next_implementer_prompt.md" in chunk
    assert "next_cursor_prompt.md" not in chunk


def test_continue_ai_loop_forwards_implementer_parameters() -> None:
    text = (_SCRIPTS / "continue_ai_loop.ps1").read_text(encoding="utf-8")
    assert "$CursorCommand" in text
    assert '"-CursorCommand"' in text or "'-CursorCommand'" in text
    assert "-CursorModel" in text
    assert '"-WithWrapUp"' in text or "'-WithWrapUp'" in text


def test_wrap_up_session_script_exists() -> None:
    script = Path("scripts/wrap_up_session.ps1")
    assert script.exists(), "scripts/wrap_up_session.ps1 must exist"
    content = script.read_text(encoding="utf-8")
    assert "0x2014" in content, "session draft title must use Unicode em dash (U+2014)"
    assert "session_draft.md" in content
    assert "test_output.txt" in content
    assert "implementer_summary.md" in content
    assert "try" in content.lower(), "must have try/catch for non-fatal behavior"


def test_promote_session_script_exists() -> None:
    script = Path("scripts/promote_session.ps1")
    assert script.exists(), "scripts/promote_session.ps1 must exist"
    content = script.read_text(encoding="utf-8")
    assert "0x2014" in content and "promote_session.ps1" in content and "do not edit manually" in content
    assert "failures.md" in content
    assert "archive/rolls" in content
    assert "session_draft.md" in content


def test_failures_log_seed_header_matches_contract() -> None:
    text = (_ROOT / ".ai-loop" / "failures.md").read_text(encoding="utf-8")
    lines = text.strip().splitlines()
    assert lines[0] == "# Failures log"
    assert lines[1] == "# Appended by scripts/promote_session.ps1 \u2014 do not edit manually."
    assert lines[2].startswith("# Rotate:")


def test_gitignore_excludes_implementer_json_runtime_state() -> None:
    text = (_ROOT / ".gitignore").read_text(encoding="utf-8")
    assert ".ai-loop/implementer.json" in text


def test_task_first_writes_implementer_state_file() -> None:
    text = (_SCRIPTS / "ai_loop_task_first.ps1").read_text(encoding="utf-8")
    assert "Save-ImplementerStateAt" in text
    assert "implementer.json" in text
    assert "ai_loop_task_first.ps1" in text


def test_implementer_prompt_surfaces_scope_blocks() -> None:
    """C02: Real PowerShell prelude plus the same `$prompt` assembly as `Invoke-ImplementerImplementation`."""
    script_text = (_SCRIPTS / "ai_loop_task_first.ps1").read_text(encoding="utf-8")
    assert script_text.count("STABLE_PREAMBLE") + script_text.count("Get-TaskScopeBlocks") >= 4

    impl_start = script_text.index("function Invoke-ImplementerImplementation")
    impl_end = script_text.index("function Invoke-AutoReviewLoop")
    impl_body = script_text[impl_start:impl_end]
    assert "Set-Content -Path $promptPath -Value $prompt" in impl_body
    assert (
        '$prompt = $STABLE_PREAMBLE + "`n`n" + $scopeBlock + $relevantBlock + "TASK:`n" + $taskText'
        in impl_body
    )

    assembly_src = _extract_implementer_prompt_assembly_from_task_first(script_text)
    assert "$scope = Get-TaskScopeBlocks -TaskFile $TaskFile" in assembly_src
    assert "$prompt = $STABLE_PREAMBLE +" in assembly_src

    task_body = (
        "## Files in scope\n\n- `scripts/example.ps1`\n\n"
        "## Files out of scope\n\n- `docs/archive/**`\n\n"
        "## Goal\n\nExample.\n"
    )
    scratch = _orch_scratch("scope_blocks")
    scratch.mkdir(parents=True, exist_ok=True)
    try:
        prompt = _powershell_build_implementer_prompt_from_task_first_script(_ROOT, scratch / "synth", task_body)

        idx_in = prompt.index("FILES IN SCOPE:")
        idx_out = prompt.index("FILES OUT OF SCOPE:")
        idx_task = prompt.index("TASK:\n")
        assert idx_in < idx_out < idx_task

        m_pre = re.search(r"\$STABLE_PREAMBLE\s*=\s*@\"\r?\n([\s\S]*?)\r?\n\"@", script_text)
        assert m_pre is not None
        preamble_body = m_pre.group(1)
        assert prompt.lstrip("\ufeff").startswith(preamble_body + "\n\n")

        real_task = (_ROOT / ".ai-loop" / "task.md").read_text(encoding="utf-8")
        real_prompt = _powershell_build_implementer_prompt_from_task_first_script(_ROOT, scratch / "real", real_task)
        assert "FILES IN SCOPE:" in real_prompt and "FILES OUT OF SCOPE:" in real_prompt

        tmpl = (_ROOT / "templates" / "task.md").read_text(encoding="utf-8")
        tmpl_lines = tmpl.splitlines()
        assert "## Files in scope" in tmpl_lines
        assert "## Files out of scope" in tmpl_lines
    finally:
        shutil.rmtree(scratch, ignore_errors=True)


def test_implementer_prompt_omits_relevant_files_when_scout_off() -> None:
    """C04: default run (no -WithScout) must not produce a scout block in the
    prompt prefix (the injected header only appears before ``TASK:``)."""
    debug = _ROOT / ".ai-loop" / "_debug" / "implementer_prompt.md"
    if debug.is_file():
        text = debug.read_text(encoding="utf-8")
        head, _, _ = text.partition("TASK:\n")
        assert "RELEVANT FILES (from scout):" not in head


def test_ai_loop_auto_resume_merges_persisted_implementer_state() -> None:
    text = (_SCRIPTS / "ai_loop_auto.ps1").read_text(encoding="utf-8")
    assert "Apply-ResumeImplementerState" in text
    assert "Save-ImplementerState" in text
    assert "implementer.json" in text
    assert "PSBoundParameters" in text
    assert "ContainsKey" in text
    assert "implementer_command" in text
    assert "cursor_command" not in text


def test_ai_loop_auto_persisted_command_resolution_matches_invocation() -> None:
    """Resume accepts rooted paths, project-relative paths, and Get-Command-discoverable names."""
    text = (_SCRIPTS / "ai_loop_auto.ps1").read_text(encoding="utf-8")
    assert "function Test-ImplementerCommandResolvable" in text
    assert "IsPathRooted" in text
    assert "Join-Path $ProjectRoot $rel" in text
    assert "Get-Command -Name $t -ErrorAction SilentlyContinue" in text


def test_ai_loop_auto_resume_warns_on_missing_or_unusable_persisted_state() -> None:
    """Resume must surface clear fallbacks when implementer.json is missing or unusable."""
    text = (_SCRIPTS / "ai_loop_auto.ps1").read_text(encoding="utf-8")
    assert "Implementer state not found at $jsonPath" in text
    assert "has no non-empty command" in text
    assert "persisted model will not be applied" in text
    assert "not discoverable via Get-Command" in text


def test_ai_loop_auto_resume_cli_override_precedence_documented_in_state_logic() -> None:
    """Explicit -CursorCommand / -CursorModel must win; PSBoundParameters gates loads."""
    text = (_SCRIPTS / "ai_loop_auto.ps1").read_text(encoding="utf-8")
    start = text.index("function Apply-ResumeImplementerState")
    end = text.index("$script:defaultImplementerWrapper", start)
    chunk = text[start:end]
    assert 'ContainsKey("CursorCommand")' in chunk
    assert 'ContainsKey("CursorModel")' in chunk
    assert "$persistedCommandRejected" in chunk


def test_ai_loop_auto_resume_explicit_cursor_command_skips_persisted_implementer_json() -> None:
    """Explicit -CursorCommand must not read implementer.json or merge a stale persisted model (OpenCode resume)."""
    text = (_SCRIPTS / "ai_loop_auto.ps1").read_text(encoding="utf-8")
    start = text.index("function Apply-ResumeImplementerState")
    end = text.index("$script:defaultImplementerWrapper", start)
    chunk = text[start:end]
    cmd_gate = chunk.index('ContainsKey("CursorCommand")')
    assert cmd_gate < chunk.index("Implementer state not found at $jsonPath")
    assert cmd_gate < chunk.index("Read-ImplementerStateObject")


def test_safety_doc_documents_implementer_json_runtime_policy() -> None:
    t = (_ROOT / "docs" / "safety.md").read_text(encoding="utf-8")
    assert "implementer.json" in t


def test_codex_template_uses_implementer_summary_only() -> None:
    t = (_ROOT / "templates" / "codex_review_prompt.md").read_text(encoding="utf-8")
    assert "implementer_summary.md" in t
    assert "cursor_summary.md" not in t


def _extract_run_codex_review_prompt_literal(ai_loop_auto_text: str) -> str:
    """Exact Codex `$prompt` body inside `Run-CodexReview` single-quote here-string."""
    anchor = ai_loop_auto_text.index("function Run-CodexReview")
    open_idx = ai_loop_auto_text.index("$prompt = @'", anchor) + len("$prompt = @'")
    close_idx = ai_loop_auto_text.index("\n'@", open_idx)
    return ai_loop_auto_text[open_idx:close_idx]


def test_run_codex_review_prompt_preserves_literal_json_fence() -> None:
    """Run-CodexReview prompt must retain ```json fences (expandable `"@` strips/alters backticks)."""
    text = (_SCRIPTS / "ai_loop_auto.ps1").read_text(encoding="utf-8")
    anchor = text.index("function Run-CodexReview")
    snippet = text[anchor : text.index("function Get-ReviewVerdict", anchor)]
    assert '$prompt = @"' not in snippet
    assert "$prompt = @'" in snippet
    literal = _extract_run_codex_review_prompt_literal(text)
    assert "```json\n" in literal
    assert "\n```\n\nRules:" in literal


def test_codex_review_template_shows_nested_json_fence() -> None:
    """Target template must visibly include ```json fences (nested under a deeper outer fence)."""
    t = (_ROOT / "templates" / "codex_review_prompt.md").read_text(encoding="utf-8")
    assert "```json\n{" in t
    assert "`" * 4 in t


def test_extract_fix_prompt_parses_json() -> None:
    """C03: Extract-FixPromptFromFile must parse the JSON schema."""
    ps = _powershell_exe()
    if not ps:
        pytest.skip("No pwsh or powershell on PATH")

    scratch = _orch_scratch("extract_json")
    scratch.mkdir(parents=True, exist_ok=True)
    try:
        funcs = _extract_fix_prompt_ps_functions_from_auto((_SCRIPTS / "ai_loop_auto.ps1").read_text(encoding="utf-8"))
        harness = scratch / "_orch_extract_fix_json.ps1"
        harness.write_text(
            """param(
    [Parameter(Mandatory)][string]$ReviewPath,
    [Parameter(Mandatory)][string]$OutPath
)

"""
            + funcs
            + """
$r = Extract-FixPromptFromFile -ReviewFile $ReviewPath -OutputPromptFile $OutPath
exit ($(if ($r) { 0 } else { 1 }))
""",
            encoding="utf-8",
        )

        review_path = scratch / "codex_review.md"
        out_path = scratch / "next_implementer_prompt.md"
        review_path.write_text(
            textwrap.dedent(
                """
                VERDICT: FIX_REQUIRED

                FIX_PROMPT_FOR_IMPLEMENTER:
                ```json
                {
                  "fix_required": true,
                  "files": ["src/foo.py"],
                  "changes": [
                    { "path": "src/foo.py", "kind": "edit", "what": "Fix widget." }
                  ],
                  "acceptance": "pytest -q passes."
                }
                ```

                FINAL_NOTE:
                ok
                """
            ).strip(),
            encoding="utf-8",
        )

        proc = subprocess.run(
            [
                ps,
                "-NoProfile",
                "-ExecutionPolicy",
                "Bypass",
                "-File",
                str(harness),
                str(review_path),
                str(out_path),
            ],
            cwd=str(scratch),
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=120,
            check=False,
        )
        detail = (proc.stdout or "") + (proc.stderr or "")
        assert proc.returncode == 0, f"harness failed ({proc.returncode}):\n{detail}"

        body = out_path.read_text(encoding="utf-8")
        assert "## Files to change" in body
        assert "## Changes" in body
        assert "## Acceptance" in body
        assert "src/foo.py" in body
        assert "Fix widget." in body
    finally:
        shutil.rmtree(scratch, ignore_errors=True)


def test_extract_fix_prompt_falls_back_on_invalid_json() -> None:
    """C03: malformed JSON must fall back to free-text regex extraction."""
    ps = _powershell_exe()
    if not ps:
        pytest.skip("No pwsh or powershell on PATH")

    scratch = _orch_scratch("extract_fallback")
    scratch.mkdir(parents=True, exist_ok=True)
    try:
        funcs = _extract_fix_prompt_ps_functions_from_auto((_SCRIPTS / "ai_loop_auto.ps1").read_text(encoding="utf-8"))
        harness = scratch / "_orch_extract_fix_fallback.ps1"
        harness.write_text(
            """param(
    [Parameter(Mandatory)][string]$ReviewPath,
    [Parameter(Mandatory)][string]$OutPath
)

"""
            + funcs
            + """
$r = Extract-FixPromptFromFile -ReviewFile $ReviewPath -OutputPromptFile $OutPath
exit ($(if ($r) { 0 } else { 1 }))
""",
            encoding="utf-8",
        )

        review_path = scratch / "codex_review_bad_json.md"
        out_path = scratch / "next_implementer_prompt_legacy.md"
        review_path.write_text(
            textwrap.dedent(
                """
                VERDICT: FIX_REQUIRED

                FIX_PROMPT_FOR_IMPLEMENTER:
                ```json
                { NOT VALID JSON
                ```

                Legacy fallback body line one.

                FINAL_NOTE:
                done
                """
            ).strip(),
            encoding="utf-8",
        )

        proc = subprocess.run(
            [
                ps,
                "-NoProfile",
                "-ExecutionPolicy",
                "Bypass",
                "-File",
                str(harness),
                str(review_path),
                str(out_path),
            ],
            cwd=str(scratch),
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=120,
            check=False,
        )
        detail = (proc.stdout or "") + (proc.stderr or "")
        assert proc.returncode == 0, f"harness failed ({proc.returncode}):\n{detail}"
        assert "WARNING" in detail.upper(), detail

        body = out_path.read_text(encoding="utf-8").strip()
        assert body
        assert "Legacy fallback body line one." in body
    finally:
        shutil.rmtree(scratch, ignore_errors=True)


def test_codex_template_reads_test_failures_before_raw_pytest_output() -> None:
    """Filtered failures are denser signal; template must list them before test_output.txt."""
    t = (_ROOT / "templates" / "codex_review_prompt.md").read_text(encoding="utf-8")
    assert t.index("test_failures_summary.md") < t.index("test_output.txt")


def test_extract_fix_prompt_for_implementer_label() -> None:
    review = (
        "VERDICT: FIX_REQUIRED\n\n"
        "FIX_PROMPT_FOR_IMPLEMENTER:\n"
        "Patch the widget.\n\n"
        "FINAL_NOTE:\n"
        "ok\n"
    )
    assert extract_fix_prompt_from_review_text(review) == "Patch the widget."


def test_extract_fix_prompt_rejects_cursor_legacy_label() -> None:
    review = "FIX_PROMPT_FOR_CURSOR:\nLegacy-labelled fix body.\n\nFINAL_NOTE:\n"
    assert extract_fix_prompt_from_review_text(review) is None


def test_extract_fix_prompt_tail_match_without_final_note() -> None:
    """PowerShell falls back to greedy tail capture when FINAL_NOTE is absent."""
    review = "FIX_PROMPT_FOR_IMPLEMENTER:\nStop after newline follows here\n"
    assert extract_fix_prompt_from_review_text(review) == "Stop after newline follows here"


def test_extract_fix_prompt_returns_none_for_none_sentinel() -> None:
    review = "FIX_PROMPT_FOR_IMPLEMENTER:\nnone\n\nFINAL_NOTE:\n"
    assert extract_fix_prompt_from_review_text(review) is None


def test_resume_branch_checks_neutral_next_prompt() -> None:
    text = (_SCRIPTS / "ai_loop_auto.ps1").read_text(encoding="utf-8")
    assert "if (Test-Path $nextNeutral)" in text
    assert "$nextLegacy" not in text


def test_implementer_fix_output_goes_to_debug_dir() -> None:
    script = (_SCRIPTS / "ai_loop_auto.ps1").read_text(encoding="utf-8")
    assert ".ai-loop/cursor_agent_output.txt" not in script
    assert ".ai-loop\\cursor_agent_output.txt" not in script
    assert "_debug" in script and "implementer_fix_output.txt" in script


def test_install_into_project_copies_opencode_json_without_clobber() -> None:
    """Installer seeds opencode.json only when missing, unless -OverwriteOpencodeConfig."""
    text = (_SCRIPTS / "install_into_project.ps1").read_text(encoding="utf-8")
    assert "templates\\opencode.json" in text or "templates/opencode.json" in text
    assert "$OverwriteOpencodeConfig" in text
    assert "$opencodeExisted" in text
    assert "Left existing opencode.json unchanged" in text


def test_install_into_project_copies_implementer_summary_template() -> None:
    text = (_SCRIPTS / "install_into_project.ps1").read_text(encoding="utf-8")
    assert "implementer_summary_template.md" in text
    assert "cursor_summary_template.md" not in text
    assert (_ROOT / "templates" / "implementer_summary_template.md").is_file()
    assert not (_ROOT / "templates" / "cursor_summary_template.md").exists()


def test_run_opencode_scout_has_scout_role_message() -> None:
    script = Path("scripts/run_opencode_scout.ps1")
    assert script.exists(), "scripts/run_opencode_scout.ps1 must exist"
    content = script.read_text(encoding="utf-8")
    assert "SCOUT" in content, "must contain SCOUT role message"
    assert "IMPLEMENTER" not in content, "must not reuse IMPLEMENTER message"


def test_run_scout_pass_has_auto_substitute_and_short_output_guard() -> None:
    content = Path("scripts/run_scout_pass.ps1").read_text(encoding="utf-8")
    assert "run_opencode_scout" in content, "missing auto-substitute for opencode_agent"
    assert "200" in content, "missing short-output guard (< 200 bytes)"


def test_install_into_project_copies_run_scout_pass_script() -> None:
    """Installer must ship run_scout_pass.ps1 so target projects can use -WithScout (DD-022)."""
    text = (_SCRIPTS / "install_into_project.ps1").read_text(encoding="utf-8")
    assert "run_scout_pass.ps1" in text
    assert (_SCRIPTS / "run_scout_pass.ps1").is_file()


def test_install_into_project_copies_wrap_up_and_promote_scripts() -> None:
    """Installer must ship wrap-up and promote helpers for -WithWrapUp / failures log (DD-023)."""
    text = (_SCRIPTS / "install_into_project.ps1").read_text(encoding="utf-8")
    assert "wrap_up_session.ps1" in text
    assert "promote_session.ps1" in text
    assert (_SCRIPTS / "wrap_up_session.ps1").is_file()
    assert (_SCRIPTS / "promote_session.ps1").is_file()


def test_active_power_shell_contract_has_no_legacy_cursor_artifact_aliases() -> None:
    legacy = (
        "cursor_summary.md",
        "next_cursor_prompt.md",
        "FIX_PROMPT_FOR_CURSOR",
        "cursor_implementation_result.md",
        "cursor_implementation_prompt.md",
        "cursor_implementation_output.txt",
        "cursor_agent_output.txt",
    )
    active_files = [
        *(_SCRIPTS.glob("*.ps1")),
        _ROOT / "templates" / "codex_review_prompt.md",
        _ROOT / "templates" / "task.md",
        _ROOT / ".gitignore",
        _ROOT / "AGENTS.md",
        _ROOT / "docs" / "workflow.md",
        _ROOT / "docs" / "safety.md",
        _ROOT / "README.md",
    ]
    for path in active_files:
        text = path.read_text(encoding="utf-8")
        for item in legacy:
            assert item not in text, f"{item} found in {path}"


def test_task_first_has_implementer_step_display_label_helper() -> None:
    text = (_SCRIPTS / "ai_loop_task_first.ps1").read_text(encoding="utf-8")
    assert "function Get-ImplementerStepDisplayLabel" in text


def test_task_first_implementer_label_prefers_qwen_when_opencode_or_model() -> None:
    """Qwen cues must precede generic 'agent' substring on wrappers like run_opencode_agent.ps1."""
    text = (_SCRIPTS / "ai_loop_task_first.ps1").read_text(encoding="utf-8")
    fn = text.index("function Get-ImplementerStepDisplayLabel")
    end = text.index("function ", fn + 1)
    blob = text[fn:end]
    assert "run_opencode_agent.ps1" in blob
    assert '.Contains("opencode")' in blob
    assert "qwen" in blob.lower()
    q_sig = blob.index("return \"QWEN\"")
    c_sig = blob.index("return \"CURSOR\"")
    assert q_sig < c_sig


def test_task_first_implementer_label_maps_cursor_wrapper_cues() -> None:
    text = (_SCRIPTS / "ai_loop_task_first.ps1").read_text(encoding="utf-8")
    fn = text.index("function Get-ImplementerStepDisplayLabel")
    end = text.index("function ", fn + 1)
    blob = text[fn:end]
    assert "run_cursor_agent.ps1" in blob
    assert "cursor" in blob.lower()


def test_task_first_step_one_heading_derives_label_not_implementer_pass() -> None:
    text = (_SCRIPTS / "ai_loop_task_first.ps1").read_text(encoding="utf-8")
    assert "STEP 1: IMPLEMENTER PASS" not in text
    assert "Get-ImplementerStepDisplayLabel" in text
    assert 'Write-Section "STEP 1: $step1Label IMPLEMENTATION"' in text


def test_build_repo_map_is_deterministic() -> None:
    """C01: build_repo_map.ps1 must produce byte-identical output on a fixed tree."""
    ps = _powershell_exe()
    if not ps:
        pytest.skip("No pwsh or powershell on PATH")

    script = _SCRIPTS / "build_repo_map.ps1"
    assert script.is_file()
    out = _ROOT / ".ai-loop" / "repo_map.md"

    def _run() -> int:
        return subprocess.run(
            [ps, "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", str(script.resolve())],
            cwd=str(_ROOT),
            capture_output=True,
            text=True,
            timeout=120,
            check=False,
        ).returncode

    assert _run() == 0, "build_repo_map.ps1 failed on first run"
    first = out.read_bytes()
    assert _run() == 0, "build_repo_map.ps1 failed on second run"
    second = out.read_bytes()
    assert first == second


def test_repo_map_excludes_archive_and_debug() -> None:
    """C01: generated repo_map.md must not list docs/archive/, .ai-loop/_debug/, or CLAUDE.md."""
    text = (_ROOT / ".ai-loop" / "repo_map.md").read_text(encoding="utf-8")
    assert "docs/archive/" not in text
    assert ".ai-loop/_debug/" not in text
    assert "CLAUDE.md" not in text


def test_ai_loop_auto_default_max_iterations_is_5() -> None:
    """DD-011: default MaxIterations must be 5 in all three driver scripts."""
    import re
    pattern = re.compile(r"\[int\]\$MaxIterations\s*=\s*5\b")
    for name in ("ai_loop_auto.ps1", "ai_loop_task_first.ps1", "continue_ai_loop.ps1"):
        text = (_SCRIPTS / name).read_text(encoding="utf-8")
        assert pattern.search(text), f"{name}: default MaxIterations must be 5 (DD-011)"


def test_ai_loop_plan_script_exists() -> None:
    assert (_SCRIPTS / "ai_loop_plan.ps1").is_file()


def test_run_claude_planner_script_exists() -> None:
    assert (_SCRIPTS / "run_claude_planner.ps1").is_file()


def test_planner_prompt_has_architect_framing() -> None:
    path = _ROOT / "templates" / "planner_prompt.md"
    assert path.is_file()
    text = path.read_text(encoding="utf-8")
    for needle in (
        "Architect with final say",
        "final say",
        "critically evaluate",
        "Architect note:",
        "optimal architecture for the project",
        "Cursor Draft Brief",
    ):
        assert needle in text, f"missing {needle!r} in {path}"


def test_planner_scripts_parse_cleanly() -> None:
    ps = _powershell_exe()
    if not ps:
        pytest.skip("No pwsh or powershell on PATH")
    for name in ("ai_loop_plan.ps1", "run_claude_planner.ps1", "run_codex_reviewer.ps1"):
        script = _SCRIPTS / name
        assert script.is_file(), f"missing {script}"
        escaped = str(script.resolve()).replace("'", "''")
        cmd = (
            f"$errs=$null;$tok=$null;"
            f"[void][System.Management.Automation.Language.Parser]::ParseFile('{escaped}',[ref]$tok,[ref]$errs);"
            "if ($errs.Count) { $errs | ForEach-Object { $_.ToString() } | Write-Output; exit 1 };"
            "exit 0"
        )
        proc = subprocess.run(
            [ps, "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", cmd],
            capture_output=True,
            text=True,
            timeout=120,
            check=False,
        )
        detail = proc.stdout.strip() + proc.stderr.strip()
        assert proc.returncode == 0, f"{name}: parser reported errors:\n{detail}"


def test_run_claude_planner_has_no_param_block_and_no_stderr_redirect() -> None:
    text = (_SCRIPTS / "run_claude_planner.ps1").read_text(encoding="utf-8")
    assert "param(" not in text
    assert "2>&1" not in text
    assert "cmd /c claude --print" in text
    assert '--tools \'""\'' in text
    assert "--system-prompt $systemPrompt" in text
    assert "Do not include analysis, status text, preambles" in text


def test_install_copies_planner_files_and_has_self_install_guard() -> None:
    text = (_SCRIPTS / "install_into_project.ps1").read_text(encoding="utf-8")
    assert "ai_loop_plan.ps1" in text
    assert "run_claude_planner.ps1" in text
    assert "planner_prompt.md" in text
    assert "draft_brief_prompt.md" in text
    assert '.ai-loop' in text and "planner_prompt.md" in text
    assert "Refusing to self-install" in text


def test_gitignore_excludes_planner_artifacts() -> None:
    text = (_ROOT / ".gitignore").read_text(encoding="utf-8")
    assert ".ai-loop/*.bak" in text
    assert ".ai-loop/user_ask.md" in text
    assert ".ai-loop/task_draft_brief.md" in text


def test_run_codex_reviewer_script_exists() -> None:
    assert (_SCRIPTS / "run_codex_reviewer.ps1").is_file()


def test_reviewer_prompt_template_exists_and_has_format() -> None:
    path = _ROOT / "templates" / "reviewer_prompt.md"
    assert path.is_file()
    text = path.read_text(encoding="utf-8")
    for needle in (
        "# Reviewer role",
        "NO_BLOCKING_ISSUES",
        "ISSUES:",
        "[logic]",
        "[complexity]",
        "simplicity wins",
        "NOT an architect",
    ):
        assert needle in text, needle


def test_run_codex_reviewer_invariants() -> None:
    text = (_SCRIPTS / "run_codex_reviewer.ps1").read_text(encoding="utf-8")
    assert "param(" not in text
    assert "codex" in text and "exec" in text
    assert "ConvertTo-CrtSafeArg" not in text
    assert "GetRandomFileName" in text and "WriteAllText" in text
    assert "2>&1" not in text


def test_run_codex_reviewer_initializes_exit_code_before_try() -> None:
    text = (_SCRIPTS / "run_codex_reviewer.ps1").read_text(encoding="utf-8")
    assert "$exitCode = 1" in text
    assert text.index("$exitCode = 1") < text.index("try {")


def test_planner_related_ps1_has_no_utf8_em_dash_literal_bytes() -> None:
    """Planner/reviewer wrappers must not embed UTF-8 U+2014 bytes (PS 5.1 source corruption)."""
    em = b"\xe2\x80\x94"
    for name in ("run_codex_reviewer.ps1", "run_claude_planner.ps1", "ai_loop_plan.ps1"):
        data = (_SCRIPTS / name).read_bytes()
        assert em not in data, f"{name} must not contain literal UTF-8 em dash; use $([char]0x2014)"


def test_codex_reviewer_no_inline_prompt_arg() -> None:
    """Prompt must be passed via file or stdin, not as a positional CLI arg."""
    src = Path("scripts/run_codex_reviewer.ps1").read_text(encoding="utf-8")
    assert "ConvertTo-CrtSafeArg" not in src, (
        "run_codex_reviewer.ps1 still uses ConvertTo-CrtSafeArg; "
        "prompt must be passed via temp file, not as a positional arg"
    )


def test_codex_reviewer_exitcode_initialized() -> None:
    src = Path("scripts/run_codex_reviewer.ps1").read_text(encoding="utf-8")
    idx_init = src.find("$exitCode = 1")
    idx_try = src.find("try {")
    assert idx_init != -1, "$exitCode = 1 not found"
    assert idx_init < idx_try, "$exitCode = 1 must appear before try {"


def test_no_emdash_bytes_in_ps1_scripts() -> None:
    for name in [
        "scripts/run_codex_reviewer.ps1",
        "scripts/run_claude_planner.ps1",
        "scripts/ai_loop_plan.ps1",
    ]:
        data = Path(name).read_bytes()
        assert b"\xe2\x80\x94" not in data, f"Literal em-dash found in {name}"


def test_ai_loop_plan_review_invariants() -> None:
    text = (_SCRIPTS / "ai_loop_plan.ps1").read_text(encoding="utf-8")
    assert "[switch]$WithReview" in text
    assert "[switch]$WithDraft" in text
    assert "[string]$DraftCommand" in text
    assert "[int]$MaxReviewIterations = 3" in text
    assert "[string]$ReviewerCommand" in text
    assert "[string]$ReviewerModel" in text
    assert "Test-PlannerOutputSanity" in text
    assert "function Normalize-PlannerOutput" in text
    assert "Normalize-PlannerOutput -Output $output" in text
    assert "Normalize-PlannerOutput -Output $revised" in text
    assert "function Test-ReviewerOutputStrict" in text
    assert "$reviewLoopExitKind" in text
    assert 'if ($reviewLoopExitKind -eq "max_iterations")' in text
    assert "-gt 3)" in text
    assert re.search(r"-gt 3\) \{[\s\S]*?\$MaxReviewIterations = 3", text), "clamp to 3 after -gt 3 guard"
    for needle in (
        "NO_BLOCKING_ISSUES",
        "REVIEWER_OUTPUT_MALFORMED",
        "REVIEW_STATUS:",
        "REVIEW_STATUS: FAILED",
        "REVIEW_STATUS: PLANNER_REVISION_FAILED",
        "REVIEW_STATUS: REVISION_SANITY_FAILED",
        "Architect note:",
        "simplicity of implementation wins",
    ):
        assert needle in text, needle


def _normalize_planner_output(output: str) -> str:
    """Mirrors scripts/ai_loop_plan.ps1 Normalize-PlannerOutput."""
    lines = output.splitlines()
    for i, line in enumerate(lines):
        candidate = line.lstrip("\ufeff").lstrip()
        if candidate.startswith("# Task:"):
            lines[i] = candidate
            return "\n".join(lines[i:]).rstrip()
    return output


_ORDER_SECTION_RE = re.compile(r"(?m)^##\s+Order\s*\r?\n\s*(\d+)")


def _derive_task_slug_for_queue(name: str) -> str:
    """Mirrors queue-save slug logic in scripts/ai_loop_plan.ps1."""
    slug = re.sub(r"[^a-z0-9]+", "_", name.strip().lower())
    slug = slug.strip("_")
    if len(slug) > 40:
        slug = slug[:40].rstrip("_")
    return slug


def test_order_regex_match() -> None:
    """PS-equivalent order capture for ai_loop_plan.ps1 queue-save."""
    body_ok = "# Task: Example\n\n## Order\n2\n"
    m = _ORDER_SECTION_RE.search(body_ok)
    assert m is not None
    assert m.group(1) == "2"
    assert _ORDER_SECTION_RE.search("# Task: Example\n\n## Order\n\n") is None
    assert _ORDER_SECTION_RE.search("# Task: Example\n\n## Goal\nOnly.\n") is None


def test_order_slug_derivation() -> None:
    assert _derive_task_slug_for_queue("Fix Dashboard Generation") == "fix_dashboard_generation"
    assert _derive_task_slug_for_queue("Add order/queue support!") == "add_order_queue_support"
    long_alnum = "a" * 60
    assert len(_derive_task_slug_for_queue(long_alnum)) == 40


def test_order_queue_filename_format() -> None:
    """Zero-padded width-3 index + underscore + slug; mirrors PS ``tasks/{0:000}_{1}.md`` (-f)."""
    assert "{0:03d}_{1}.md".format(3, "fix_x") == "003_fix_x.md"


@pytest.mark.parametrize(
    ("body", "expected"),
    [
        ("# Task: Clean\n\n## Goal\nx", "# Task: Clean\n\n## Goal\nx"),
        ("Now writing.\n\n# Task: Clean\n\n## Goal\nx\n", "# Task: Clean\n\n## Goal\nx"),
        ("Refusal without task", "Refusal without task"),
    ],
)
def test_planner_output_normalization_strips_preamble_only_when_task_exists(body: str, expected: str) -> None:
    assert _normalize_planner_output(body) == expected


_ISSUE_BULLET_RE = re.compile(r"^\s*-\s*\[(logic|complexity|scope|missing)\]\s+\S")


def _reviewer_output_strict_ok(output: str) -> bool:
    """Mirrors scripts/ai_loop_plan.ps1 Test-ReviewerOutputStrict (structural pinning, no Codex)."""
    t = output.strip()
    if not t:
        return False
    if t == "NO_BLOCKING_ISSUES":
        return True
    hit_issues = False
    bullets = 0
    for raw_line in t.splitlines():
        if not raw_line.strip():
            continue
        if not hit_issues:
            if re.fullmatch(r"\s*ISSUES:\s*", raw_line):
                hit_issues = True
                continue
            return False
        if _ISSUE_BULLET_RE.match(raw_line) is None:
            return False
        bullets += 1
    return hit_issues and bullets >= 1


@pytest.mark.parametrize(
    ("body", "expected_ok"),
    [
        ("NO_BLOCKING_ISSUES", True),
        ("  NO_BLOCKING_ISSUES  \n", True),
        ("Preamble\nNO_BLOCKING_ISSUES", False),
        ("NO_BLOCKING_ISSUES\nExtra line", False),
        ("ISSUES:\n- [logic] contradicts scope", True),
        ("ISSUES:\n- [complexity] too big", True),
        ("ISSUES:\n- [scope] drift", True),
        ("ISSUES:\n- [missing] nothing", True),
        ("ISSUES:\n- [logic]x", False),
        ('ISSUES:\n- [Logic] case', False),
        ("ISSUES:\n- [logic] ok\njunk after", False),
        ("ISSUES:\n(no bullets)", False),
        ("ISSUES:\nNO_BLOCKING_ISSUES", False),
    ],
)
def test_reviewer_output_strict_matches_planner_contract(body: str, expected_ok: bool) -> None:
    assert _reviewer_output_strict_ok(body) is expected_ok


def test_install_copies_reviewer_files() -> None:
    text = (_SCRIPTS / "install_into_project.ps1").read_text(encoding="utf-8")
    assert "run_codex_reviewer.ps1" in text
    assert (
        'Copy-Item (Join-Path $Root "templates\\reviewer_prompt.md") (Join-Path $TargetAiLoop "reviewer_prompt.md")'
        in text
    )


def test_gitignore_excludes_review_artifacts() -> None:
    text = (_ROOT / ".gitignore").read_text(encoding="utf-8")
    assert ".ai-loop/planner_review_trace.md" in text
    assert ".ai-loop/reviewer_prompt.md" in text


def test_ai_loop_plan_structural_invariants() -> None:
    text = (_SCRIPTS / "ai_loop_plan.ps1").read_text(encoding="utf-8")
    assert "$script:ExitCode" in text
    assert r"templates\planner_prompt.md" in text
    assert "[regex]::Match($diskText, '(?m)^##\\s+Order\\s*\\r?\\n\\s*(\\d+)')" in text
    assert "Split-Path -Parent $PSScriptRoot" in text
    assert "Queue: $dest" in text
    for h in (
        "## Goal",
        "## Scope",
        "## Files in scope",
        "## Files out of scope",
        "## Tests",
        "## Important",
    ):
        assert h in text
    assert ".tmp" in text
    assert "repo_map.md is missing" in text
    assert "Get-FilesInScopeSummary" in text or "Files in scope (extracted" in text


def test_draft_brief_template_exists_nonempty() -> None:
    path = _ROOT / "templates" / "draft_brief_prompt.md"
    assert path.is_file()
    assert path.read_text(encoding="utf-8").strip()


def test_ai_loop_plan_with_draft_source_contract() -> None:
    text = (_SCRIPTS / "ai_loop_plan.ps1").read_text(encoding="utf-8")
    assert "[switch]$WithDraft" in text
    assert '[string]$DraftCommand = "run_cursor_agent.ps1"' in text
    assert "task_draft_brief.md" in text
    assert "proceeding without brief" in text
    assert "Cursor Draft Brief" in text
    assert "draft_brief_prompt.md" in text


def test_ai_loop_plan_draft_command_resolves_bare_wrapper_beside_script() -> None:
    """Bare -DraftCommand names resolve next to ai_loop_plan.ps1 ($PSScriptRoot); explicit paths unchanged."""
    text = (_SCRIPTS / "ai_loop_plan.ps1").read_text(encoding="utf-8")
    assert '$draftBesidePlan = Join-Path $PSScriptRoot $DraftCommand' in text
    assert "$DraftCommand -notmatch" in text and "$PSScriptRoot $DraftCommand" in text


def test_ai_loop_plan_with_draft_nonfatal_when_draft_command_throws() -> None:
    """Terminating draft wrapper errors warn and planning continues (non-fatal)."""
    ps = _powershell_exe()
    if not ps:
        pytest.skip("No pwsh or powershell on PATH")
    root = _orch_scratch("ai_loop_plan_draft_throw")
    root.mkdir(parents=True, exist_ok=True)
    try:
        ai_loop = root / ".ai-loop"
        ai_loop.mkdir(parents=True, exist_ok=True)
        tmpl = root / "templates"
        tmpl.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(_ROOT / "AGENTS.md", root / "AGENTS.md")
        shutil.copyfile(_ROOT / ".ai-loop" / "project_summary.md", ai_loop / "project_summary.md")
        shutil.copyfile(_ROOT / "templates" / "planner_prompt.md", tmpl / "planner_prompt.md")
        shutil.copyfile(_ROOT / "templates" / "draft_brief_prompt.md", tmpl / "draft_brief_prompt.md")
        (root / "throw_draft.ps1").write_text(
            'throw "intentional draft terminating error for harness"\n',
            encoding="utf-8",
        )
        (root / "fake_planner.ps1").write_text(
            textwrap.dedent(
                r"""
                $null = @($input)
                @'
                # Task: harness draft throw

                ## Goal
                g

                ## Scope
                s

                ## Files in scope
                - `README.md`

                ## Files out of scope
                - n/a

                ## Tests
                - none

                ## Important
                ok
                '@
                """
            ).lstrip(),
            encoding="utf-8",
        )
        plan_script = _SCRIPTS / "ai_loop_plan.ps1"
        proc = subprocess.run(
            [
                ps,
                "-NoProfile",
                "-ExecutionPolicy",
                "Bypass",
                "-File",
                str(plan_script.resolve()),
                "-Ask",
                "harness ask",
                "-Out",
                ".ai-loop/task.md",
                "-Force",
                "-WithDraft",
                "-DraftCommand",
                str((root / "throw_draft.ps1").resolve()),
                "-PlannerCommand",
                str((root / "fake_planner.ps1").resolve()),
            ],
            cwd=str(root.resolve()),
            capture_output=True,
            text=True,
            encoding="utf-8",
        )
        assert proc.returncode == 0, proc.stdout + proc.stderr
        out_task = ai_loop / "task.md"
        assert out_task.is_file()
        body = out_task.read_text(encoding="utf-8-sig")
        assert body.lstrip().startswith("# Task:")
        combined = (proc.stdout or "") + (proc.stderr or "")
        assert "proceeding without brief" in combined
    finally:
        shutil.rmtree(root, ignore_errors=True)


def test_user_ask_template_exists_and_has_sections() -> None:
    path = _ROOT / "templates" / "user_ask_template.md"
    assert path.is_file()
    t = path.read_text(encoding="utf-8")
    for needle in ("## Goal", "## Affected files", "## Out-of-scope", "## Proposed approach"):
        assert needle in t


def test_install_copies_user_ask_template() -> None:
    text = (_SCRIPTS / "install_into_project.ps1").read_text(encoding="utf-8")
    assert (
        'Copy-Item (Join-Path $Root "templates\\user_ask_template.md") '
        '(Join-Path $TargetAiLoop "user_ask_template.md")' in text
    )
    assert (
        'Copy-Item (Join-Path $Root "templates\\user_ask_template.md") (Join-Path $TargetAiLoop "user_ask.md")'
        not in text
    )


def test_ai_loop_task_first_declares_skip_scope_check() -> None:
    text = (_SCRIPTS / "ai_loop_task_first.ps1").read_text(encoding="utf-8")
    assert "[switch]$SkipScopeCheck" in text


def test_ai_loop_task_first_has_files_in_scope_helper() -> None:
    text = (_SCRIPTS / "ai_loop_task_first.ps1").read_text(encoding="utf-8")
    assert "function Test-TaskFilesInScopeExist" in text


def test_ai_loop_task_first_invokes_preflight_before_step1() -> None:
    text = (_SCRIPTS / "ai_loop_task_first.ps1").read_text(encoding="utf-8")
    idx_pf = text.find("if (-not $SkipScopeCheck)")
    assert idx_pf >= 0
    idx_s1 = text.find("STEP 1: ")
    assert idx_s1 >= 0
    assert idx_pf < idx_s1


def _run_task_first_preflight_harness(
    tmp_project: Path,
    task_body: str,
    *,
    extra_args: list[str] | None = None,
) -> subprocess.CompletedProcess[str]:
    ps = _powershell_exe()
    if not ps:
        pytest.skip("No pwsh or powershell on PATH")
    ai_loop = tmp_project / ".ai-loop"
    ai_loop.mkdir(parents=True, exist_ok=True)
    (ai_loop / "task.md").write_text(task_body, encoding="utf-8")
    fake_auto = tmp_project / "fake_auto_loop.ps1"
    fake_auto.write_text("exit 0\n", encoding="utf-8")
    script = _SCRIPTS / "ai_loop_task_first.ps1"
    args = [
        ps,
        "-NoProfile",
        "-ExecutionPolicy",
        "Bypass",
        "-File",
        str(script.resolve()),
        "-SkipInitialCursor",
        "-NoPush",
        "-AutoLoopScript",
        str(fake_auto.resolve()),
        "-TaskPath",
        ".ai-loop\\task.md",
        "-CursorCommand",
        str((_SCRIPTS / "run_cursor_agent.ps1").resolve()),
    ]
    if extra_args:
        args.extend(extra_args)
    return subprocess.run(
        args,
        cwd=str(tmp_project.resolve()),
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        timeout=180,
        check=False,
    )


def test_preflight_fails_on_invented_path(orch_preflight_dir: Path) -> None:
    task = textwrap.dedent(
        """
        # Task
        ## Files in scope
        - nonexistent/path.py
        ## Files out of scope
        - docs/**
        """
    ).strip()
    proc = _run_task_first_preflight_harness(orch_preflight_dir, task)
    out = (proc.stdout or "") + (proc.stderr or "")
    assert proc.returncode != 0, out
    assert "nonexistent/path.py" in out
    assert "PREFLIGHT FAILED" in out


def test_preflight_passes_when_paths_exist(orch_preflight_dir: Path) -> None:
    (orch_preflight_dir / "real_asset.txt").write_text("x", encoding="utf-8")
    task = textwrap.dedent(
        """
        ## Files in scope
        - real_asset.txt
        """
    ).strip()
    proc = _run_task_first_preflight_harness(orch_preflight_dir, task)
    out = (proc.stdout or "") + (proc.stderr or "")
    assert proc.returncode == 0, out
    assert "Preflight:" in out and "path(s) in scope all exist or marked (new)." in out


def test_preflight_skips_paths_marked_new(orch_preflight_dir: Path) -> None:
    task = textwrap.dedent(
        """
        ## Files in scope
        - not_yet_there.py (new)
        """
    ).strip()
    proc = _run_task_first_preflight_harness(orch_preflight_dir, task)
    out = (proc.stdout or "") + (proc.stderr or "")
    assert proc.returncode == 0, out


def test_preflight_blocks_when_new_is_not_trailing(orch_preflight_dir: Path) -> None:
    task = textwrap.dedent(
        """
        ## Files in scope
        - scripts/existing.ps1 keep old behavior with (new) mode
        """
    ).strip()
    proc = _run_task_first_preflight_harness(orch_preflight_dir, task)
    out = (proc.stdout or "") + (proc.stderr or "")
    assert proc.returncode != 0, out
    assert "scripts/existing.ps1" in out


def test_preflight_skips_globs_and_dirs(orch_preflight_dir: Path) -> None:
    task = textwrap.dedent(
        """
        ## Files in scope
        - src/**
        - tests/test_*.py
        - docs/
        """
    ).strip()
    proc = _run_task_first_preflight_harness(orch_preflight_dir, task)
    out = (proc.stdout or "") + (proc.stderr or "")
    assert proc.returncode == 0, out


def test_preflight_warns_on_missing_section(orch_preflight_dir: Path) -> None:
    task = textwrap.dedent(
        """
        ## Goal
        No Files in scope heading here on purpose.
        """
    ).strip()
    proc = _run_task_first_preflight_harness(orch_preflight_dir, task)
    out = (proc.stdout or "") + (proc.stderr or "")
    assert proc.returncode == 0, out
    assert "Preflight: '## Files in scope' section not found in" in out
