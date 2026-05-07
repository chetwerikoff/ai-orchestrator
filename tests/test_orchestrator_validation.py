"""Orchestrator checks: PowerShell AST parse + path-set delta semantics (task-first gate)."""

from __future__ import annotations

import re
import shutil
import subprocess
from pathlib import Path

import pytest

_ROOT = Path(__file__).resolve().parent.parent
_SCRIPTS = _ROOT / "scripts"
_PS1_TARGETS = ("ai_loop_auto.ps1", "ai_loop_task_first.ps1")
_SAFEADD_DEFAULT_RE = re.compile(
    r"\[string\]\$SafeAddPaths\s*=\s*\"([^\"]+)\"",
    re.MULTILINE,
)

RESULT_NORM = ".ai-loop/cursor_implementation_result.md"


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
    """PS 5.1 native-arg quoting workaround: prompts sent to agent/codex must go through ConvertTo-CrtSafeArg."""
    expected_helper = "function ConvertTo-CrtSafeArg"
    expected_call = "ConvertTo-CrtSafeArg -Value"
    for name in ("ai_loop_task_first.ps1", "ai_loop_auto.ps1"):
        text = (_SCRIPTS / name).read_text(encoding="utf-8")
        assert expected_helper in text, f"{name} missing ConvertTo-CrtSafeArg definition"
        assert expected_call in text, f"{name} does not invoke ConvertTo-CrtSafeArg"
    auto = (_SCRIPTS / "ai_loop_auto.ps1").read_text(encoding="utf-8")
    assert auto.count("ConvertTo-CrtSafeArg -Value") >= 2, "auto must escape both Cursor and Codex prompts"
