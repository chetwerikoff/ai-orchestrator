"""Orchestrator checks: PowerShell AST parse + porcelain delta semantics (task-first gate)."""

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
    """Regression: nested untracked paths must appear in porcelain; default mode can hide them."""
    text = (_SCRIPTS / "ai_loop_task_first.ps1").read_text(encoding="utf-8")
    assert "git status --porcelain --untracked-files=all" in text


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
    """Normalize paths from one `git status --porcelain` line (mirror of task-first script)."""
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
    """Paths whose porcelain line differs between snapshots (cursor pass delta)."""
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


RESULT_NORM = ".ai-loop/cursor_implementation_result.md"


def content_delta_paths_from_snapshots(
    before: dict[str, tuple[bool, str | None]],
    after: dict[str, tuple[bool, str | None]],
) -> set[str]:
    """Mirror task-first content snapshots: paths whose existence/hash changed between passes."""
    changed: set[str] = set()
    for path in set(before) | set(after):
        b_exists, b_hash = before.get(path, (False, None))
        a_exists, a_hash = after.get(path, (False, None))
        exist_diff = b_exists != a_exists
        hash_diff = b_exists and a_exists and b_hash != a_hash
        if exist_diff or hash_diff:
            changed.add(path)
    return changed


def merged_implementation_delta(
    before_lines: list[str],
    after_lines: list[str],
    *,
    result_changed_during_pass: bool,
    content_changed_paths: frozenset[str] | None = None,
) -> set[str]:
    """Mirror task-first gate: porcelain delta, content/hash delta, plus FS result when needed."""
    delta = set(cursor_produced_paths(before_lines, after_lines))
    if content_changed_paths:
        delta |= set(content_changed_paths)
    if result_changed_during_pass:
        delta.add(RESULT_NORM)
    return delta


def had_implementation_side_effects(
    before_lines: list[str],
    after_lines: list[str],
    *,
    result_changed_during_pass: bool,
    content_changed_paths: frozenset[str] | None = None,
) -> bool:
    """True if porcelain delta, content/hash delta, or result file changed on disk during the pass."""
    if result_changed_during_pass:
        return True
    if content_changed_paths:
        return True
    return bool(cursor_produced_paths(before_lines, after_lines))


def test_marker_enforcement_predicate_matches_sole_result_delta() -> None:
    result_norm = ".ai-loop/cursor_implementation_result.md"
    dirty_task = " M .ai-loop/task.md"
    delta = cursor_produced_paths(
        [dirty_task],
        [dirty_task, f" M {result_norm}"],
    )
    enforce_marker = len(delta) == 1 and result_norm in delta
    assert enforce_marker is True


def test_ignored_result_file_tracked_via_filesystem_merges_into_delta() -> None:
    """Ignored result does not appear in porcelain; filesystem snapshot still yields sole-result delta."""
    dirty_task = " M .ai-loop/task.md"
    before = [dirty_task]
    after = list(before)
    delta = merged_implementation_delta(
        before,
        after,
        result_changed_during_pass=True,
    )
    assert delta == {RESULT_NORM}


def test_ignored_or_untracked_result_without_other_deltas_triggers_marker_gate() -> None:
    """Sole merged delta is result path -> marker enforcement predicate is True."""
    dirty_readme = " M README.md"
    before = [dirty_readme]
    after = list(before)
    delta = merged_implementation_delta(
        before,
        after,
        result_changed_during_pass=True,
    )
    assert delta == {RESULT_NORM}
    assert len(delta) == 1 and RESULT_NORM in delta


def test_summary_only_changes_do_not_count_when_no_porcelain_delta_and_no_result_fs_change() -> None:
    """cursor_summary.md is filtered from porcelain lines: identical snapshots, no FS result -> no side effects."""
    stub = " M .ai-loop/cursor_summary.md"
    assert (
        had_implementation_side_effects(
            [stub],
            [stub],
            result_changed_during_pass=False,
        )
        is False
    )


def test_preexisting_dirty_task_does_not_hide_result_only_delta() -> None:
    """Pre-existing task.md line unchanged; ignored result merges from FS -> still only result in merged delta."""
    dirty_task = " M .ai-loop/task.md"
    before = [dirty_task]
    after = [dirty_task]
    delta = merged_implementation_delta(
        before,
        after,
        result_changed_during_pass=True,
    )
    enforce_marker = len(delta) == 1 and RESULT_NORM in delta
    assert enforce_marker is True


def test_real_project_delta_with_result_change_is_not_result_only_gate() -> None:
    delta = merged_implementation_delta(
        [],
        [" M README.md"],
        result_changed_during_pass=True,
    )
    only_result = len(delta) == 1 and RESULT_NORM in delta
    assert only_result is False
    assert "README.md" in delta and RESULT_NORM in delta


def test_untracked_directory_stable_porcelain_directory_fingerprint_detects_nested_edit() -> None:
    """Untracked dir may keep one ?? porcelain line while nested files change; snapshot must differ."""
    line = "?? vendor/widget/"
    before_snap = {"vendor/widget": (True, "dir-fingerprint-before")}
    after_snap = {"vendor/widget": (True, "dir-fingerprint-after")}
    content_paths = content_delta_paths_from_snapshots(before_snap, after_snap)
    assert content_paths == {"vendor/widget"}

    delta = merged_implementation_delta(
        [line],
        [line],
        result_changed_during_pass=False,
        content_changed_paths=frozenset(content_paths),
    )
    assert delta == {"vendor/widget"}
    assert (
        had_implementation_side_effects(
            [line],
            [line],
            result_changed_during_pass=False,
            content_changed_paths=frozenset(content_paths),
        )
        is True
    )


def test_readme_dirty_same_porcelain_line_but_content_hash_change_is_implementation_delta() -> None:
    """Porcelain line stable (` M README.md`) while disk content changes -> delta via FS snapshots."""
    dirty = " M README.md"
    before_snap = {"README.md": (True, "hash-before")}
    after_snap = {"README.md": (True, "hash-after")}
    content_paths = content_delta_paths_from_snapshots(before_snap, after_snap)
    assert content_paths == {"README.md"}

    delta = merged_implementation_delta(
        [dirty],
        [dirty],
        result_changed_during_pass=False,
        content_changed_paths=frozenset(content_paths),
    )
    assert delta == {"README.md"}

    assert (
        had_implementation_side_effects(
            [dirty],
            [dirty],
            result_changed_during_pass=False,
            content_changed_paths=frozenset(content_paths),
        )
        is True
    )


def test_preexisting_dirty_readme_without_content_change_still_allows_result_only_delta() -> None:
    """README stays dirty with identical hash; only ignored result changes -> merged delta is result-only."""
    dirty = " M README.md"
    delta = merged_implementation_delta(
        [dirty],
        [dirty],
        result_changed_during_pass=True,
        content_changed_paths=None,
    )
    enforce_marker = len(delta) == 1 and RESULT_NORM in delta
    assert enforce_marker is True
