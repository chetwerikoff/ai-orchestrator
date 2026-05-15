"""Token usage JSONL recorder + console report scripts."""

from __future__ import annotations

import base64
import json
import os
import shutil
import subprocess
from pathlib import Path

import pytest

_ROOT = Path(__file__).resolve().parent.parent
_SCRIPTS = _ROOT / "scripts"
_TOKEN_JSONL = _ROOT / ".ai-loop" / "token_usage.jsonl"
_TOKEN_SUMMARY_MD = _ROOT / ".ai-loop" / "token_usage_summary.md"


def _powershell_exe() -> str | None:
    return shutil.which("pwsh") or shutil.which("powershell")


def _run_ps_capture(cmd: str, *, cwd: Path | None = None) -> tuple[int, str, str]:
    ps = _powershell_exe()
    assert ps is not None
    proc = subprocess.run(
        [
            ps,
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-Command",
            cmd,
        ],
        cwd=str(cwd or _ROOT),
        capture_output=True,
        text=True,
        timeout=120,
        check=False,
    )
    stdout = proc.stdout or ""
    stderr = proc.stderr or ""
    return proc.returncode, stdout, stderr


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


def test_ai_loop_auto_ps1_parse_clean() -> None:
    ps = _powershell_exe()
    if not ps:
        pytest.skip("No pwsh or powershell on PATH")
    script = _SCRIPTS / "ai_loop_auto.ps1"
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
        code, stdout, stderr = _run_ps_capture(cmd)
        detail = stdout + stderr
        assert code == 0, detail
        assert _TOKEN_JSONL.is_file(), f"stdout={stdout!r} stderr={stderr!r}"
        lines = [ln for ln in _TOKEN_JSONL.read_text(encoding="utf-8").splitlines() if ln.strip()]
        assert len(lines) == 1
        data = json.loads(lines[0])
        assert data["task_name"] == "pytest_task"
        assert data["provider"] == "anthropic"
        assert data["source"] == "unknown"
        assert data["quality"] == "unknown"
    finally:
        _TOKEN_JSONL.unlink(missing_ok=True)


def test_convert_claude_api_format() -> None:
    ps = _powershell_exe()
    if not ps:
        pytest.skip("No pwsh or powershell on PATH")
    snippet = '{"input_tokens":100,"foo":1,"output_tokens":35}'
    cmd = (
        ". .\\scripts\\record_token_usage.ps1; "
        f"$r = ConvertFrom-CliTokenUsage -Text '{snippet}'; "
        "$r.InputTokens; $r.OutputTokens; $r.TotalTokens; $r.Source; $r.Quality"
    )
    code, stdout, stderr = _run_ps_capture(cmd)
    assert code == 0, stderr
    lines = [ln.strip() for ln in stdout.splitlines() if ln.strip()]
    assert lines[:5] == ["100", "35", "135", "api_response", "exact"]


def test_convert_openai_api_format() -> None:
    ps = _powershell_exe()
    if not ps:
        pytest.skip("No pwsh or powershell on PATH")
    snippet = '{"prompt_tokens":72,"completion_tokens":9}'
    cmd = (
        ". .\\scripts\\record_token_usage.ps1; "
        f"$r = ConvertFrom-CliTokenUsage -Text '{snippet}'; "
        "$r.InputTokens; $r.OutputTokens; $r.TotalTokens; $r.Source; $r.Quality"
    )
    code, stdout, stderr = _run_ps_capture(cmd)
    assert code == 0, stderr
    lines = [ln.strip() for ln in stdout.splitlines() if ln.strip()]
    assert lines[:5] == ["72", "9", "81", "api_response", "exact"]


def test_convert_cli_log_format() -> None:
    ps = _powershell_exe()
    if not ps:
        pytest.skip("No pwsh or powershell on PATH")
    snippet = "Input tokens: 42\r\nOutput tokens: 18\r\nNotes here"
    b64 = base64.b64encode(snippet.encode("utf-16le")).decode("ascii")
    cmd = (
        ". .\\scripts\\record_token_usage.ps1; "
        f"$t = [Text.Encoding]::Unicode.GetString([Convert]::FromBase64String('{b64}')); "
        "$r = ConvertFrom-CliTokenUsage -Text $t; "
        "$r.InputTokens; $r.OutputTokens; $r.Source"
    )
    code, stdout, stderr = _run_ps_capture(cmd)
    assert code == 0, stderr
    lines = [ln.strip() for ln in stdout.splitlines() if ln.strip()]
    assert lines[:3] == ["42", "18", "cli_log"]


def test_convert_no_match_returns_null() -> None:
    ps = _powershell_exe()
    if not ps:
        pytest.skip("No pwsh or powershell on PATH")
    cmd = (
        ". .\\scripts\\record_token_usage.ps1; "
        "$r = ConvertFrom-CliTokenUsage -Text 'no token metadata here'; "
        "if ($null -eq $r) { 'IS_NULL' } else { 'NOT_NULL' }"
    )
    code, stdout, stderr = _run_ps_capture(cmd)
    assert code == 0, stderr
    assert "IS_NULL" in stdout
    assert "NOT_NULL" not in stdout


def test_write_record_default_source_quality() -> None:
    ps = _powershell_exe()
    if not ps:
        pytest.skip("No pwsh or powershell on PATH")
    _TOKEN_JSONL.unlink(missing_ok=True)
    try:
        cmd = (
            ". .\\scripts\\record_token_usage.ps1; "
            "Write-TokenUsageRecord -TaskName x -ScriptName y -Iteration 1 -Provider p -Model m "
            "-InputTokens 1 -OutputTokens 2 -TotalTokens 3"
        )
        code, _, stderr = _run_ps_capture(cmd)
        assert code == 0, stderr
        data = json.loads(_TOKEN_JSONL.read_text(encoding="utf-8").strip().splitlines()[-1])
        assert data["source"] == "unknown"
        assert data["quality"] == "unknown"
    finally:
        _TOKEN_JSONL.unlink(missing_ok=True)


def test_write_record_explicit_source_quality() -> None:
    ps = _powershell_exe()
    if not ps:
        pytest.skip("No pwsh or powershell on PATH")
    _TOKEN_JSONL.unlink(missing_ok=True)
    try:
        cmd = (
            ". .\\scripts\\record_token_usage.ps1; "
            "Write-TokenUsageRecord -TaskName x -ScriptName y -Iteration 1 -Provider p -Model m "
            "-InputTokens 1 -OutputTokens 2 -TotalTokens 3 -Source api_response -Quality exact"
        )
        code, _, stderr = _run_ps_capture(cmd)
        assert code == 0, stderr
        data = json.loads(_TOKEN_JSONL.read_text(encoding="utf-8").strip().splitlines()[-1])
        assert data["source"] == "api_response"
        assert data["quality"] == "exact"
    finally:
        _TOKEN_JSONL.unlink(missing_ok=True)


def _write_records_jsonl(records: list[dict[str, object]]) -> None:
    lines = "\n".join(json.dumps(rec, sort_keys=True) for rec in records)
    text = lines + ("\n" if lines else "")
    _TOKEN_JSONL.parent.mkdir(parents=True, exist_ok=True)
    _TOKEN_JSONL.write_text(text if text else "", encoding="utf-8")


def test_show_report_by_model() -> None:
    ps = _powershell_exe()
    if not ps:
        pytest.skip("No pwsh or powershell on PATH")
    ts = "2026-05-15T12:00:00.0000000Z"
    rec_a = {
        "task_name": "t1",
        "script_name": "s1",
        "iteration": 1,
        "provider": "p",
        "model": "model-a",
        "input_tokens": 10,
        "output_tokens": 5,
        "total_tokens": 15,
        "timestamp": ts,
    }
    rec_b = {
        "task_name": "t1",
        "script_name": "s1",
        "iteration": 2,
        "provider": "p",
        "model": "model-b",
        "input_tokens": 3,
        "output_tokens": 7,
        "total_tokens": 10,
        "timestamp": ts,
    }
    _TOKEN_SUMMARY_MD.unlink(missing_ok=True)
    _TOKEN_JSONL.unlink(missing_ok=True)
    try:
        _write_records_jsonl([rec_a, rec_b])
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
        combined = ((proc.stdout or "") + os.linesep + (proc.stderr or "")).replace("\r\n", "\n")
        assert proc.returncode == 0, combined
        assert "model-a" in combined
        assert "model-b" in combined
        assert "15" in combined
        assert "10" in combined
    finally:
        _TOKEN_JSONL.unlink(missing_ok=True)
        _TOKEN_SUMMARY_MD.unlink(missing_ok=True)


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
    text = proc.stdout + proc.stderr
    assert "No token usage records found." in text
    assert "exception" not in (proc.stderr or "").lower()


def test_show_report_writes_summary_md() -> None:
    ps = _powershell_exe()
    if not ps:
        pytest.skip("No pwsh or powershell on PATH")
    ts = "2026-05-15T12:05:00.0000000Z"
    rec = {
        "task_name": "one-task",
        "script_name": "ai_loop_auto.ps1",
        "iteration": 1,
        "provider": "codex",
        "model": "codex",
        "input_tokens": 5,
        "output_tokens": 4,
        "total_tokens": 9,
        "timestamp": ts,
    }
    _TOKEN_SUMMARY_MD.unlink(missing_ok=True)
    _TOKEN_JSONL.unlink(missing_ok=True)
    try:
        _write_records_jsonl([rec])
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
        assert proc.returncode == 0, proc.stdout + proc.stderr
        assert _TOKEN_SUMMARY_MD.is_file()
        body = _TOKEN_SUMMARY_MD.read_text(encoding="utf-8")
        assert "Total" in body
    finally:
        _TOKEN_JSONL.unlink(missing_ok=True)
        _TOKEN_SUMMARY_MD.unlink(missing_ok=True)


def test_codex_auto_record_chain() -> None:
    ps = _powershell_exe()
    if not ps:
        pytest.skip("No pwsh or powershell on PATH")
    _TOKEN_JSONL.unlink(missing_ok=True)
    snippet = '{"prompt_tokens":501,"completion_tokens":99}'
    try:
        cmd = (
            ". .\\scripts\\record_token_usage.ps1; "
            f"$parsed = ConvertFrom-CliTokenUsage -Text '{snippet}'; "
            "Write-TokenUsageRecord -TaskName pytest_chain -ScriptName ai_loop_auto.ps1 -Iteration 2 "
            "-Provider codex -Model codex -InputTokens $parsed.InputTokens "
            "-OutputTokens $parsed.OutputTokens -TotalTokens $parsed.TotalTokens "
            "-Confidence unknown -Source $parsed.Source -Quality $parsed.Quality"
        )
        code, _, stderr = _run_ps_capture(cmd)
        assert code == 0, stderr
        data = json.loads(_TOKEN_JSONL.read_text(encoding="utf-8").strip().splitlines()[-1])
        assert data["provider"] == "codex"
        assert data["source"] == "api_response"
        assert data["iteration"] == 2
        assert data["model"] == "codex"
    finally:
        _TOKEN_JSONL.unlink(missing_ok=True)
