"""Orchestrator checks: PowerShell AST parse + path-set delta semantics (task-first gate)."""

from __future__ import annotations

import re
import shutil
import subprocess
from pathlib import Path

import pytest

_ROOT = Path(__file__).resolve().parent.parent
_SCRIPTS = _ROOT / "scripts"
_PS1_TARGETS = ("ai_loop_auto.ps1", "ai_loop_task_first.ps1", "continue_ai_loop.ps1")
_SAFEADD_DEFAULT_RE = re.compile(
    r"\[string\]\$SafeAddPaths\s*=\s*\"([^\"]+)\"",
    re.MULTILINE,
)

RESULT_NORM = ".ai-loop/cursor_implementation_result.md"

# Mirrors `Extract-FixPromptFromFile` in scripts/ai_loop_auto.ps1 — keep alternation order in sync.
_FIX_PROMPT_LABEL_RE = re.compile(
    r"(?:FIX_PROMPT_FOR_IMPLEMENTER|FIX_PROMPT_FOR_CURSOR):\s*"
    r"(?P<prompt>[\s\S]*?)FINAL_NOTE:",
    re.IGNORECASE,
)
_FIX_PROMPT_TAIL_RE = re.compile(
    r"(?:FIX_PROMPT_FOR_IMPLEMENTER|FIX_PROMPT_FOR_CURSOR):\s*(?P<prompt>[\s\S]*)",
    re.IGNORECASE,
)


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


def _default_safe_add_paths_literal(script: Path) -> str:
    text = script.read_text(encoding="utf-8")
    m = _SAFEADD_DEFAULT_RE.search(text)
    assert m is not None, f"no [string]$SafeAddPaths default in {script}"
    return m.group(1).strip()


def test_default_safe_add_paths_parity_includes_docs_and_templates() -> None:
    """Orchestrator entrypoints must agree on SafeAddPaths defaults; docs/templates must stage."""
    names = ("ai_loop_auto.ps1", "ai_loop_task_first.ps1", "continue_ai_loop.ps1")
    literals = [_default_safe_add_paths_literal(_SCRIPTS / n) for n in names]
    assert len(set(literals)) == 1, dict(zip(names, literals, strict=True))
    segments = [s.strip() for s in literals[0].split(",") if s.strip()]
    assert "AGENTS.md" in segments
    assert "docs/" in segments
    assert "templates/" in segments


def test_task_first_porcelain_uses_untracked_files_all() -> None:
    """Nested untracked paths must appear in porcelain; default mode can hide them."""
    text = (_SCRIPTS / "ai_loop_task_first.ps1").read_text(encoding="utf-8")
    assert "git status --porcelain --untracked-files=all" in text


def test_auto_porcelain_uses_untracked_files_all_for_noop_guard() -> None:
    text = (_SCRIPTS / "ai_loop_auto.ps1").read_text(encoding="utf-8")
    assert "git status --porcelain --untracked-files=all" in text


def test_ai_loop_auto_has_clean_tree_noop_guard_reasons() -> None:
    text = (_SCRIPTS / "ai_loop_auto.ps1").read_text(encoding="utf-8")
    assert "REVIEW_STARTED_ON_CLEAN_TREE" in text
    assert "NO_CHANGES_AFTER_CURSOR_FIX" in text


def test_claude_final_review_prompt_template_removed() -> None:
    assert not (_ROOT / "templates" / "claude_final_review_prompt.md").exists()


def _powershell_exe() -> str | None:
    return shutil.which("pwsh") or shutil.which("powershell")


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


def cursor_produced_paths(before_lines: list[str], after_lines: list[str]) -> set[str]:
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
    result_line = " M .ai-loop/cursor_implementation_result.md"
    before = [dirty_task]
    after = [dirty_task, result_line]
    assert cursor_produced_paths(before, after) == {".ai-loop/cursor_implementation_result.md"}


def test_porcelain_delta_empty_when_no_line_change() -> None:
    dirty = " M README.md"
    assert cursor_produced_paths([dirty], [dirty]) == set()


def test_porcelain_delta_detects_modified_file_status_change() -> None:
    assert cursor_produced_paths([" M README.md"], ["MM README.md"]) == {"README.md"}


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


def test_invoke_cursor_implementation_wraps_path_sets_for_compare_object() -> None:
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
    assert ".ai-loop/cursor_summary.md" in lit


def test_fix_prompt_labels_supported_in_ai_loop_auto() -> None:
    text = (_SCRIPTS / "ai_loop_auto.ps1").read_text(encoding="utf-8")
    assert "FIX_PROMPT_FOR_IMPLEMENTER" in text
    assert "FIX_PROMPT_FOR_CURSOR" in text
    assert "FIX_PROMPT_FOR_IMPLEMENTER|FIX_PROMPT_FOR_CURSOR" in text


def test_runtime_cleanup_includes_both_next_prompt_variants() -> None:
    for name in ("ai_loop_auto.ps1", "ai_loop_task_first.ps1"):
        text = (_SCRIPTS / name).read_text(encoding="utf-8")
        assert ".ai-loop/next_implementer_prompt.md" in text
        assert ".ai-loop/next_cursor_prompt.md" in text


def test_resume_prefers_neutral_next_prompt_file() -> None:
    text = (_SCRIPTS / "ai_loop_auto.ps1").read_text(encoding="utf-8")
    start = text.index("function Try-ResumeFromExistingReview")
    chunk = text[start:]
    imp = chunk.index("Resuming from existing next_implementer_prompt.md")
    leg = chunk.index("Resuming from existing next_cursor_prompt.md")
    assert imp < leg


def test_continue_ai_loop_forwards_implementer_parameters() -> None:
    text = (_SCRIPTS / "continue_ai_loop.ps1").read_text(encoding="utf-8")
    assert "$CursorCommand" in text
    assert '"-CursorCommand"' in text or "'-CursorCommand'" in text
    assert "-CursorModel" in text


def test_gitignore_excludes_implementer_json_runtime_state() -> None:
    text = (_ROOT / ".gitignore").read_text(encoding="utf-8")
    assert ".ai-loop/implementer.json" in text


def test_task_first_writes_implementer_state_file() -> None:
    text = (_SCRIPTS / "ai_loop_task_first.ps1").read_text(encoding="utf-8")
    assert "Save-ImplementerStateAt" in text
    assert "implementer.json" in text
    assert "ai_loop_task_first.ps1" in text


def test_ai_loop_auto_resume_merges_persisted_implementer_state() -> None:
    text = (_SCRIPTS / "ai_loop_auto.ps1").read_text(encoding="utf-8")
    assert "Apply-ResumeImplementerState" in text
    assert "Save-ImplementerState" in text
    assert "implementer.json" in text
    assert "PSBoundParameters" in text
    assert "ContainsKey" in text
    assert "implementer_command" in text and "cursor_command" in text


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


def test_codex_template_prioritizes_implementer_summary() -> None:
    t = (_ROOT / "templates" / "codex_review_prompt.md").read_text(encoding="utf-8")
    assert t.index("implementer_summary.md") < t.index("cursor_summary.md")


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


def test_extract_fix_prompt_for_cursor_legacy_label() -> None:
    review = (
        "VERDICT: FIX_REQUIRED\n\n"
        "FIX_PROMPT_FOR_CURSOR:\n"
        "Legacy-labelled fix body.\n\n"
        "FINAL_NOTE:\n"
        "done\n"
    )
    assert extract_fix_prompt_from_review_text(review) == "Legacy-labelled fix body."


def test_extract_fix_prompt_tail_match_without_final_note() -> None:
    """PowerShell falls back to greedy tail capture when FINAL_NOTE is absent."""
    review = "FIX_PROMPT_FOR_IMPLEMENTER:\nStop after newline follows here\n"
    assert extract_fix_prompt_from_review_text(review) == "Stop after newline follows here"


def test_extract_fix_prompt_returns_none_for_none_sentinel() -> None:
    review = "FIX_PROMPT_FOR_IMPLEMENTER:\nnone\n\nFINAL_NOTE:\n"
    assert extract_fix_prompt_from_review_text(review) is None


def test_resume_branch_tests_neutral_next_prompt_before_legacy() -> None:
    """Structural guard: Try-ResumeFromExistingReview must check next_implementer first."""
    text = (_SCRIPTS / "ai_loop_auto.ps1").read_text(encoding="utf-8")
    neutral_if = text.index("if (Test-Path $nextNeutral)")
    legacy_if = text.index("if (Test-Path $nextLegacy)")
    assert neutral_if < legacy_if


def test_cursor_agent_output_goes_to_debug_dir() -> None:
    script = (_SCRIPTS / "ai_loop_auto.ps1").read_text(encoding="utf-8")
    assert ".ai-loop/cursor_agent_output.txt" not in script
    assert ".ai-loop\\cursor_agent_output.txt" not in script
    assert "_debug" in script and "cursor_agent_output.txt" in script


def test_install_into_project_copies_opencode_json_without_clobber() -> None:
    """Installer seeds opencode.json only when missing, unless -OverwriteOpencodeConfig."""
    text = (_SCRIPTS / "install_into_project.ps1").read_text(encoding="utf-8")
    assert "templates\\opencode.json" in text or "templates/opencode.json" in text
    assert "$OverwriteOpencodeConfig" in text
    assert "$opencodeExisted" in text
    assert "Left existing opencode.json unchanged" in text
