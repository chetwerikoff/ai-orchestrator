"""Token usage JSONL recorder + console report scripts."""

from __future__ import annotations

import json
import shutil
import subprocess
from pathlib import Path

import pytest

_ROOT = Path(__file__).resolve().parent.parent
_SCRIPTS = _ROOT / "scripts"
_TOKEN_JSONL = _ROOT / ".ai-loop" / "token_usage.jsonl"


def _powershell_exe() -> str | None:
    return shutil.which("pwsh") or shutil.which("powershell")


def _parse_file_via_ast(script: Path, *, ps: str) -> None:
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
    assert proc.returncode == 0, f"{script.name}: parser reported errors:\n{detail}"


def test_record_token_usage_ps1_parse_clean() -> None:
    ps = _powershell_exe()
    if not ps:
        pytest.skip("No pwsh or powershell on PATH")
    script = _SCRIPTS / "record_token_usage.ps1"
    assert script.is_file(), f"missing {script}"
    _parse_file_via_ast(script, ps=ps)


def test_show_token_report_ps1_parse_clean() -> None:
    ps = _powershell_exe()
    if not ps:
        pytest.skip("No pwsh or powershell on PATH")
    script = _SCRIPTS / "show_token_report.ps1"
    assert script.is_file(), f"missing {script}"
    _parse_file_via_ast(script, ps=ps)


def test_write_token_usage_record_integration() -> None:
    ps = _powershell_exe()
    if not ps:
        pytest.skip("No pwsh or powershell on PATH")

    _TOKEN_JSONL.unlink(missing_ok=True)
    try:
        cmd = (
            ". .\\scripts\\record_token_usage.ps1; "
            "Write-TokenUsageRecord -TaskName 'pytest_task' -Provider 'anthropic' -Confidence 'unknown'"
        )
        proc = subprocess.run(
            [ps, "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", cmd],
            cwd=str(_ROOT),
            capture_output=True,
            text=True,
            timeout=120,
            check=False,
        )
        detail = (proc.stdout or "") + (proc.stderr or "")
        assert proc.returncode == 0, detail
        assert _TOKEN_JSONL.is_file(), f"stdout={proc.stdout!r} stderr={proc.stderr!r}"
        lines = [ln for ln in _TOKEN_JSONL.read_text(encoding="utf-8").splitlines() if ln.strip()]
        assert len(lines) == 1
        data = json.loads(lines[0])
        assert data["task_name"] == "pytest_task"
        assert data["provider"] == "anthropic"
    finally:
        _TOKEN_JSONL.unlink(missing_ok=True)


def test_show_token_report_no_jsonl_integration() -> None:
    ps = _powershell_exe()
    if not ps:
        pytest.skip("No pwsh or powershell on PATH")

    _TOKEN_JSONL.unlink(missing_ok=True)
    assert not _TOKEN_JSONL.exists()
    proc = subprocess.run(
        [
            ps,
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            str(_SCRIPTS / "show_token_report.ps1"),
        ],
        cwd=str(_ROOT),
        capture_output=True,
        text=True,
        timeout=120,
        check=False,
    )
    assert proc.returncode == 0, (proc.stdout or "") + (proc.stderr or "")
    stderr = proc.stderr or ""
    assert "exception" not in stderr.lower()
