"""Token usage JSONL recorder + console report scripts."""

from __future__ import annotations

import base64
import json
import os
import re
import shutil
import subprocess
import uuid
from datetime import datetime, timezone
from pathlib import Path

import pytest

_ROOT = Path(__file__).resolve().parent.parent
_SCRIPTS = _ROOT / "scripts"
_TOKEN_JSONL = _ROOT / ".ai-loop" / "token_usage.jsonl"
_TOKEN_SUMMARY_MD = _ROOT / ".ai-loop" / "token_usage_summary.md"
_REPORTS_DIR = _ROOT / ".ai-loop" / "reports"


def _utc_ts_iso() -> str:
    """ISO-8601 timestamp accepted by PowerShell DateTime.Parse."""
    # e.g. 2026-05-16T12:34:56+00:00
    _dt = datetime.now(timezone.utc)
    return _dt.isoformat(timespec="seconds")


def parse_token_limits_providers_yaml(blob: str) -> dict[str, dict[str, str]]:
    """Mirror the constrained providers: block grammar used in show_token_report.ps1 (tests only)."""
    providers: dict[str, dict[str, str]] = {}
    in_providers = False
    prov_indent = -1
    cur = ""
    for segment in blob.splitlines():
        line = segment.split("#")[0].rstrip("\n\r")
        if line.strip() == "":
            continue
        lead = len(line) - len(line.lstrip(" "))
        rest = line.strip()
        if not in_providers:
            if rest.startswith("providers:"):
                in_providers = True
                prov_indent = lead
                cur = ""
            continue
        m = re.match(r"^([A-Za-z0-9_-]+):\s*(.*)$", rest)
        if not m:
            continue
        k, v_tail = m.group(1), m.group(2).strip()
        depth = lead - prov_indent
        if depth == 2 and v_tail == "":
            cur = k.lower()
            providers.setdefault(cur, {})
        elif depth == 4 and cur and k in {"daily", "weekly", "monthly"}:
            providers[cur][k] = v_tail
    return providers


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


def test_ai_loop_task_first_ps1_parse_clean() -> None:
    ps = _powershell_exe()
    if not ps:
        pytest.skip("No pwsh or powershell on PATH")
    script = _SCRIPTS / "ai_loop_task_first.ps1"
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


def test_convert_codex_tokens_used_single_line() -> None:
    ps = _powershell_exe()
    if not ps:
        pytest.skip("No pwsh or powershell on PATH")
    snippet = "Summary line before\r\ntokens used 32,372\r\nfooter"
    b64 = base64.b64encode(snippet.encode("utf-16le")).decode("ascii")
    cmd = (
        ". .\\scripts\\record_token_usage.ps1; "
        f"$t = [Text.Encoding]::Unicode.GetString([Convert]::FromBase64String('{b64}')); "
        "$r = ConvertFrom-CliTokenUsage -Text $t; "
        "if ($null -ne $r.InputTokens) { 'BAD_IN' }; "
        "if ($null -ne $r.OutputTokens) { 'BAD_OUT' }; "
        "$r.TotalTokens; $r.Source; $r.Quality"
    )
    code, stdout, stderr = _run_ps_capture(cmd)
    assert code == 0, stderr
    lines = [ln.strip() for ln in stdout.splitlines() if ln.strip()]
    assert "BAD_IN" not in stdout
    assert "BAD_OUT" not in stdout
    assert lines[:3] == ["32372", "cli_log", "exact"]


def test_convert_codex_tokens_used_multiline() -> None:
    ps = _powershell_exe()
    if not ps:
        pytest.skip("No pwsh or powershell on PATH")
    snippet = "start\r\ntokens used\r\n32,372\r\ndone"
    b64 = base64.b64encode(snippet.encode("utf-16le")).decode("ascii")
    cmd = (
        ". .\\scripts\\record_token_usage.ps1; "
        f"$t = [Text.Encoding]::Unicode.GetString([Convert]::FromBase64String('{b64}')); "
        "$r = ConvertFrom-CliTokenUsage -Text $t; "
        "if ($null -ne $r.InputTokens) { 'BAD_IN' }; "
        "if ($null -ne $r.OutputTokens) { 'BAD_OUT' }; "
        "$r.TotalTokens; $r.Source; $r.Quality"
    )
    code, stdout, stderr = _run_ps_capture(cmd)
    assert code == 0, stderr
    assert "BAD_IN" not in stdout
    assert "BAD_OUT" not in stdout
    lines = [ln.strip() for ln in stdout.splitlines() if ln.strip()]
    assert lines[:3] == ["32372", "cli_log", "exact"]


def test_convert_openai_json_wins_over_codex_tokens_used_text() -> None:
    ps = _powershell_exe()
    if not ps:
        pytest.skip("No pwsh or powershell on PATH")
    # Second line would parse as Codex total-only if JSON branches did not run first.
    snippet = '{"prompt_tokens":72,"completion_tokens":9}\r\ntokens used 999999\r\n'
    b64 = base64.b64encode(snippet.encode("utf-16le")).decode("ascii")
    cmd = (
        ". .\\scripts\\record_token_usage.ps1; "
        f"$t = [Text.Encoding]::Unicode.GetString([Convert]::FromBase64String('{b64}')); "
        "$r = ConvertFrom-CliTokenUsage -Text $t; "
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


def test_cli_capture_dedupe_skips_second_identical_capture() -> None:
    ps = _powershell_exe()
    if not ps:
        pytest.skip("No pwsh or powershell on PATH")
    snippet = "VERDICT: PASS\r\ntokens used 55\r\n"
    b64 = base64.b64encode(snippet.encode("utf-16le")).decode("ascii")
    _TOKEN_JSONL.unlink(missing_ok=True)
    try:
        cmd = (
            ". .\\scripts\\record_token_usage.ps1; "
            f"$t=[Text.Encoding]::Unicode.GetString([Convert]::FromBase64String('{b64}')); "
            "Write-CliCaptureTokenUsageIfParsed -CapturedText $t -ScriptName ai_loop_auto.codex_review "
            "-Provider codex -Model codex -Iteration 1 -DedupeId 'pytest:dedupe_a'; "
            "Write-CliCaptureTokenUsageIfParsed -CapturedText $t -ScriptName ai_loop_auto.codex_review "
            "-Provider codex -Model codex -Iteration 1 -DedupeId 'pytest:dedupe_a'"
        )
        code, _, stderr = _run_ps_capture(cmd)
        assert code == 0, stderr
        lines = [ln for ln in _TOKEN_JSONL.read_text(encoding="utf-8").splitlines() if ln.strip()]
        assert len(lines) == 1
        data = json.loads(lines[0])
        assert data["script_name"] == "ai_loop_auto.codex_review"
        assert data["total_tokens"] == 55
    finally:
        _TOKEN_JSONL.unlink(missing_ok=True)


def test_cli_capture_codex_auto_review_script_name() -> None:
    ps = _powershell_exe()
    if not ps:
        pytest.skip("No pwsh or powershell on PATH")
    snippet = '{"prompt_tokens":10,"completion_tokens":5}\r\nVERDICT: PASS\r\n'
    b64 = base64.b64encode(snippet.encode("utf-16le")).decode("ascii")
    _TOKEN_JSONL.unlink(missing_ok=True)
    try:
        root_esc = str(_ROOT.resolve()).replace("'", "''")
        cmd = (
            ". .\\scripts\\record_token_usage.ps1; "
            f"$t=[Text.Encoding]::Unicode.GetString([Convert]::FromBase64String('{b64}')); "
            "Write-CliCaptureTokenUsageIfParsed -CapturedText $t -ScriptName ai_loop_auto.codex_review "
            "-Provider codex -Model codex -Iteration 2 -DedupeId 'pytest:codex_cap' "
            f"-ProjectRootHint '{root_esc}'"
        )
        code, _, stderr = _run_ps_capture(cmd)
        assert code == 0, stderr
        data = json.loads(_TOKEN_JSONL.read_text(encoding="utf-8").strip().splitlines()[-1])
        assert data["script_name"] == "ai_loop_auto.codex_review"
        assert data["provider"] == "codex"
        assert data["iteration"] == 2
        assert data["total_tokens"] == 15
    finally:
        _TOKEN_JSONL.unlink(missing_ok=True)


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
            "Write-TokenUsageRecord -TaskName pytest_chain -ScriptName ai_loop_auto.codex_review -Iteration 2 "
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
        assert data["script_name"] == "ai_loop_auto.codex_review"
    finally:
        _TOKEN_JSONL.unlink(missing_ok=True)


def test_joined_codex_review_capture_writes_jsonl_iteration_3() -> None:
    """Fixture matches Run-CodexReview merged transcript (assistant body + CLI footer tokens used)."""
    ps = _powershell_exe()
    if not ps:
        pytest.skip("No pwsh or powershell on PATH")
    snippet = "VERDICT: PASS\n\ntokens used 777\n"
    b64 = base64.b64encode(snippet.encode("utf-16le")).decode("ascii")
    root_esc = str(_ROOT.resolve()).replace("'", "''")
    _TOKEN_JSONL.unlink(missing_ok=True)
    try:
        cmd = (
            ". .\\scripts\\record_token_usage.ps1; "
            f"$t=[Text.Encoding]::Unicode.GetString([Convert]::FromBase64String('{b64}')); "
            "Write-CliCaptureTokenUsageIfParsed -CapturedText $t -ScriptName ai_loop_auto.codex_review "
            "-Provider codex -Model codex -Iteration 3 -DedupeId 'pytest:joined_cap' "
            f"-ProjectRootHint '{root_esc}'"
        )
        code, _, stderr = _run_ps_capture(cmd)
        assert code == 0, stderr
        data = json.loads(_TOKEN_JSONL.read_text(encoding="utf-8").strip().splitlines()[-1])
        assert data["script_name"] == "ai_loop_auto.codex_review"
        assert data["iteration"] == 3
        assert data["total_tokens"] == 777
    finally:
        _TOKEN_JSONL.unlink(missing_ok=True)


def test_parse_limits_yaml_known_unknown_na() -> None:
    blob = """
providers:
  anthropic:
    daily: 1000000
    weekly: unknown
    monthly: not_applicable
"""
    p = parse_token_limits_providers_yaml(blob)
    assert p["anthropic"]["daily"] == "1000000"
    assert p["anthropic"]["weekly"] == "unknown"
    assert p["anthropic"]["monthly"] == "not_applicable"


def _limits_scratch_file(name: str) -> Path:
    d = _ROOT / "tests" / ".token_limits_scratch"
    d.mkdir(parents=True, exist_ok=True)
    return d / f"{name}_{uuid.uuid4().hex}.yaml"


def test_show_limits_percent_when_numeric() -> None:
    ps = _powershell_exe()
    if not ps:
        pytest.skip("No pwsh or powershell on PATH")
    lim = _limits_scratch_file("tlim")
    lim.write_text(
        "providers:\n"
        "  anthropic:\n"
        "    daily: 1000\n"
        "    weekly: unknown\n"
        "    monthly: unknown\n",
        encoding="utf-8",
    )
    ts = _utc_ts_iso()
    rec = {
        "task_name": "pytest",
        "script_name": "run_claude_planner.ps1",
        "iteration": 0,
        "provider": "anthropic",
        "model": "claude",
        "input_tokens": 250,
        "output_tokens": 0,
        "total_tokens": 250,
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
                "-LimitsYamlPath",
                str(lim.resolve()),
            ],
            cwd=str(_ROOT),
            capture_output=True,
            text=True,
            timeout=120,
            check=False,
        )
        combined = ((proc.stdout or "") + (proc.stderr or "")).replace("\r\n", "\n")
        assert proc.returncode == 0, combined
        assert "(25%)" in combined or "(25.0%)" in combined
        assert "calendar utc day" in combined.lower()
    finally:
        _TOKEN_JSONL.unlink(missing_ok=True)
        _TOKEN_SUMMARY_MD.unlink(missing_ok=True)
        try:
            lim.unlink(missing_ok=True)
        except OSError:
            pass


def test_show_limits_missing_config_shows_explicit_unknown() -> None:
    ps = _powershell_exe()
    if not ps:
        pytest.skip("No pwsh or powershell on PATH")
    ghost = _limits_scratch_file("nonexistent")
    ts = _utc_ts_iso()
    rec = {
        "task_name": "pytest",
        "script_name": "s",
        "iteration": 1,
        "provider": "codex",
        "model": "codex",
        "input_tokens": 0,
        "output_tokens": 0,
        "total_tokens": 50,
        "timestamp": ts,
    }
    _TOKEN_JSONL.unlink(missing_ok=True)
    _TOKEN_SUMMARY_MD.unlink(missing_ok=True)
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
                "-LimitsYamlPath",
                str(ghost),
            ],
            cwd=str(_ROOT),
            capture_output=True,
            text=True,
            timeout=120,
            check=False,
        )
        combined = ((proc.stdout or "") + (proc.stderr or "")).replace("\r\n", "\n")
        assert proc.returncode == 0, combined
        lo = combined.lower()
        assert "config missing" in lo or "missing" in lo
        assert "limits" in lo
    finally:
        _TOKEN_JSONL.unlink(missing_ok=True)
        _TOKEN_SUMMARY_MD.unlink(missing_ok=True)


def test_export_report_creates_timestamped_file() -> None:
    ps = _powershell_exe()
    if not ps:
        pytest.skip("No pwsh or powershell on PATH")
    ts = _utc_ts_iso()
    rec = {
        "task_name": "pytest",
        "script_name": "s",
        "iteration": 1,
        "provider": "p",
        "model": "m",
        "total_tokens": 3,
        "timestamp": ts,
    }
    _TOKEN_JSONL.unlink(missing_ok=True)
    _TOKEN_SUMMARY_MD.unlink(missing_ok=True)
    _REPORTS_DIR.mkdir(parents=True, exist_ok=True)
    before = {p.name for p in _REPORTS_DIR.glob("token_usage_*.md")}
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
                "-ExportReport",
            ],
            cwd=str(_ROOT),
            capture_output=True,
            text=True,
            timeout=120,
            check=False,
        )
        assert proc.returncode == 0, proc.stdout + proc.stderr
        after = {p.name for p in _REPORTS_DIR.glob("token_usage_*.md")}
        new_names = after - before
        assert new_names, "expected a new token_usage_*.md export"
        newbie = _REPORTS_DIR / next(iter(new_names))
        assert newbie.read_text(encoding="utf-8")
    finally:
        _TOKEN_JSONL.unlink(missing_ok=True)
        _TOKEN_SUMMARY_MD.unlink(missing_ok=True)
        for p in _REPORTS_DIR.glob("token_usage_*.md"):
            try:
                p.unlink()
            except OSError:
                pass


def test_claude_reviewer_cli_capture_writes_jsonl() -> None:
    ps = _powershell_exe()
    if not ps:
        pytest.skip("No pwsh or powershell on PATH")
    snippet = "Input tokens: 9\r\nOutput tokens: 11\r\nNO_BLOCKING_ISSUES"
    b64 = base64.b64encode(snippet.encode("utf-16le")).decode("ascii")
    _TOKEN_JSONL.unlink(missing_ok=True)
    try:
        cmd = (
            ". .\\scripts\\record_token_usage.ps1; "
            f"$t=[Text.Encoding]::Unicode.GetString([Convert]::FromBase64String('{b64}')); "
            "Write-CliCaptureTokenUsageIfParsed -CapturedText $t "
            "-ScriptName run_claude_reviewer.ps1 -Provider anthropic -Model "
            "claude-haiku-4-5-20251001 -Iteration 0"
        )
        code, _, stderr = _run_ps_capture(cmd)
        assert code == 0, stderr
        data = json.loads(_TOKEN_JSONL.read_text(encoding="utf-8").strip().splitlines()[-1])
        assert data["script_name"] == "run_claude_reviewer.ps1"
        assert data["total_tokens"] == 20
        assert data["model"] == "claude-haiku-4-5-20251001"
        assert data["provider"] == "anthropic"
    finally:
        _TOKEN_JSONL.unlink(missing_ok=True)


def test_wrapper_cli_capture_writes_jsonl() -> None:
    ps = _powershell_exe()
    if not ps:
        pytest.skip("No pwsh or powershell on PATH")
    snippet = "Input tokens: 12\r\nOutput tokens: 34\r\nFooter"
    b64 = base64.b64encode(snippet.encode("utf-16le")).decode("ascii")
    _TOKEN_JSONL.unlink(missing_ok=True)
    try:
        cmd = (
            ". .\\scripts\\record_token_usage.ps1; "
            f"$t=[Text.Encoding]::Unicode.GetString([Convert]::FromBase64String('{b64}')); "
            "Write-CliCaptureTokenUsageIfParsed -CapturedText $t -ScriptName pytest_wrap.ps1 "
            "-Provider anthropic -Model m -Iteration 0"
        )
        code, _, stderr = _run_ps_capture(cmd)
        assert code == 0, stderr
        data = json.loads(_TOKEN_JSONL.read_text(encoding="utf-8").strip().splitlines()[-1])
        assert data["script_name"] == "pytest_wrap.ps1"
        assert data["total_tokens"] == 46
        assert data["provider"] == "anthropic"
        assert data["quality"] == "exact"
    finally:
        _TOKEN_JSONL.unlink(missing_ok=True)


def test_parse_jsonl_skips_malformed_lines_exits_zero() -> None:
    ps = _powershell_exe()
    if not ps:
        pytest.skip("No pwsh or powershell on PATH")
    ts = "2026-05-15T12:05:00.0000000Z"
    rec = {
        "task_name": "t1",
        "script_name": "s1",
        "iteration": 1,
        "provider": "p",
        "model": "good-model",
        "input_tokens": 1,
        "output_tokens": 1,
        "total_tokens": 2,
        "timestamp": ts,
    }
    _TOKEN_SUMMARY_MD.unlink(missing_ok=True)
    _TOKEN_JSONL.unlink(missing_ok=True)
    try:
        _TOKEN_JSONL.parent.mkdir(parents=True, exist_ok=True)
        lines = ["{not json!!!", json.dumps(rec)]
        _TOKEN_JSONL.write_text("\n".join(lines), encoding="utf-8")
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
        combined = (proc.stdout or "") + (proc.stderr or "")
        assert proc.returncode == 0, combined
        assert "good-model" in combined
    finally:
        _TOKEN_JSONL.unlink(missing_ok=True)
        _TOKEN_SUMMARY_MD.unlink(missing_ok=True)


def test_run_claude_planner_ps1_parse_clean() -> None:
    ps = _powershell_exe()
    if not ps:
        pytest.skip("No pwsh or powershell on PATH")
    _parse_file_via_ast(_SCRIPTS / "run_claude_planner.ps1", ps=ps)


def test_run_claude_reviewer_ps1_parse_clean() -> None:
    ps = _powershell_exe()
    if not ps:
        pytest.skip("No pwsh or powershell on PATH")
    _parse_file_via_ast(_SCRIPTS / "run_claude_reviewer.ps1", ps=ps)


def test_run_codex_reviewer_ps1_parse_clean() -> None:
    ps = _powershell_exe()
    if not ps:
        pytest.skip("No pwsh or powershell on PATH")
    _parse_file_via_ast(_SCRIPTS / "run_codex_reviewer.ps1", ps=ps)


def test_run_cursor_agent_ps1_parse_clean() -> None:
    ps = _powershell_exe()
    if not ps:
        pytest.skip("No pwsh or powershell on PATH")
    _parse_file_via_ast(_SCRIPTS / "run_cursor_agent.ps1", ps=ps)


def test_run_opencode_agent_ps1_parse_clean() -> None:
    ps = _powershell_exe()
    if not ps:
        pytest.skip("No pwsh or powershell on PATH")
    _parse_file_via_ast(_SCRIPTS / "run_opencode_agent.ps1", ps=ps)


def test_write_token_usage_record_chain_fields_roundtrip() -> None:
    ps = _powershell_exe()
    if not ps:
        pytest.skip("No pwsh or powershell on PATH")
    _TOKEN_JSONL.unlink(missing_ok=True)
    try:
        cmd = (
            ". .\\scripts\\record_token_usage.ps1; "
            "Write-TokenUsageRecord -TaskName trt -ScriptName s -Iteration 0 -Provider p -Model m "
            "-InputTokens 1 -OutputTokens 2 -TotalTokens 3 -PlannerChainId ab12cd34 -Phase planning "
            "-Role planner -FixIterationIndex -1 -PromptBytes 99 -PlannerCommandRow run_x.ps1 "
            "-MaxReviewItersRow 2 -NoRevisionRow $false"
        )
        code, _, stderr = _run_ps_capture(cmd)
        assert code == 0, stderr
        data = json.loads(_TOKEN_JSONL.read_text(encoding="utf-8").strip().splitlines()[-1])
        assert data["planner_chain_id"] == "ab12cd34"
        assert data["phase"] == "planning"
        assert data["role"] == "planner"
        assert "fix_iteration_index" not in data
        assert data["prompt_bytes"] == 99
        assert data["planner_command"] == "run_x.ps1"
        assert data["max_review_iters"] == 2
        assert data["no_revision"] is False
    finally:
        _TOKEN_JSONL.unlink(missing_ok=True)


def test_show_report_old_row_without_chain_fields() -> None:
    ps = _powershell_exe()
    if not ps:
        pytest.skip("No pwsh or powershell on PATH")
    ts = "2026-05-15T12:00:00.0000000Z"
    old_row = (
        '{"task_name":"legacy","script_name":"s","iteration":0,'
        '"provider":"p","model":"m","input_tokens":1,"output_tokens":2,"total_tokens":3,"timestamp":"'
        + ts
        + '"}'
    )
    _TOKEN_SUMMARY_MD.unlink(missing_ok=True)
    _TOKEN_JSONL.unlink(missing_ok=True)
    try:
        _TOKEN_JSONL.parent.mkdir(parents=True, exist_ok=True)
        _TOKEN_JSONL.write_text(old_row + "\n", encoding="utf-8")
        proc = subprocess.run(
            [ps, "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", str(_SCRIPTS / "show_token_report.ps1")],
            cwd=str(_ROOT),
            capture_output=True,
            text=True,
            timeout=120,
            check=False,
        )
        out = (proc.stdout or "") + (proc.stderr or "")
        assert proc.returncode == 0, out
        assert "legacy" in out
    finally:
        _TOKEN_JSONL.unlink(missing_ok=True)
        _TOKEN_SUMMARY_MD.unlink(missing_ok=True)


def test_chain_json_warn_preserve_and_force_new() -> None:
    """If chain exists without -ForceNewChain, id is preserved; -ForceNewChain replaces."""
    ps = _powershell_exe()
    if not ps:
        pytest.skip("No pwsh or powershell on PATH")
    chain_path = _ROOT / ".ai-loop" / "chain.json"
    chain_path.parent.mkdir(parents=True, exist_ok=True)
    orig = {
        "planner_chain_id": "aaaaaaaa",
        "task_name": "",
        "started_at_utc": "2026-01-01T00:00:00Z",
        "planner_form": {
            "planner_command": "x",
            "planner_model": "",
            "reviewer_command": "none",
            "reviewer_model": "",
            "max_review_iters": 0,
            "no_revision": True,
        },
    }
    chain_path.write_text(json.dumps(orig) + "\n", encoding="utf-8")
    try:
        cmd = (
            ". .\\scripts\\record_token_usage.ps1; "
            "$r = Initialize-AiLoopPlannerChain -ProjectRoot (Resolve-Path .).Path -TaskFileRelative '.ai-loop/task.md' "
            "-PlannerCommand 'p.ps1' -PlannerModel '' -ReviewerCommand 'none' -ReviewerModel '' -MaxReviewIters 0 -NoRevision $true; "
            "$o = Get-Content -LiteralPath '.ai-loop/chain.json' -Raw | ConvertFrom-Json; "
            "$o.planner_chain_id"
        )
        code, stdout, stderr = _run_ps_capture(cmd)
        assert code == 0, stderr + stdout
        line = stdout.strip().splitlines()[-1].strip()
        assert line == "aaaaaaaa"
        cmd_force = (
            ". .\\scripts\\record_token_usage.ps1; "
            "$r = Initialize-AiLoopPlannerChain -ProjectRoot (Resolve-Path .).Path -ForceNewChain -TaskFileRelative '.ai-loop/task.md' "
            "-PlannerCommand 'p.ps1' -PlannerModel '' -ReviewerCommand 'none' -ReviewerModel '' -MaxReviewIters 0 -NoRevision $true; "
            "$o = Get-Content -LiteralPath '.ai-loop/chain.json' -Raw | ConvertFrom-Json; "
            "$o.planner_chain_id; $r.Wrote"
        )
        code2, stdout2, stderr2 = _run_ps_capture(cmd_force)
        assert code2 == 0, stderr2 + stdout2
        lines2 = [x.strip() for x in stdout2.strip().splitlines() if x.strip()]
        new_id = lines2[-2]
        wrote = lines2[-1].lower()
        assert len(new_id) == 8
        assert new_id != "aaaaaaaa"
        assert wrote == "true"
    finally:
        chain_path.unlink(missing_ok=True)


def test_show_report_by_chain_planner_form_decomposed() -> None:
    """-ByChain prints decomposed planner_form from planner + planner_review JSONL rows."""
    ps = _powershell_exe()
    if not ps:
        pytest.skip("No pwsh or powershell on PATH")
    ts = "2026-05-15T12:00:00.0000000Z"
    rows = [
        {
            "task_name": "decomp_task",
            "script_name": "run_cursor_agent.ps1",
            "iteration": 0,
            "provider": "cursor",
            "model": "plan-model-x",
            "input_tokens": 1,
            "output_tokens": 0,
            "total_tokens": 1,
            "timestamp": ts,
            "planner_chain_id": "feedface",
            "phase": "planning",
            "role": "planner",
            "planner_command": "run_cursor_agent.ps1",
            "max_review_iters": 3,
            "no_revision": False,
            "prompt_bytes": 50,
        },
        {
            "task_name": "decomp_task",
            "script_name": "run_codex_reviewer.ps1",
            "iteration": 0,
            "provider": "openai",
            "model": "codex-rev-y",
            "input_tokens": 2,
            "output_tokens": 0,
            "total_tokens": 2,
            "timestamp": ts,
            "planner_chain_id": "feedface",
            "phase": "planning",
            "role": "planner_review",
            "reviewer_command": "run_codex_reviewer.ps1",
            "prompt_bytes": 10,
        },
        {
            "task_name": "decomp_task",
            "script_name": "s3",
            "iteration": 1,
            "provider": "p",
            "model": "m",
            "input_tokens": 0,
            "output_tokens": 0,
            "total_tokens": 0,
            "timestamp": ts,
            "planner_chain_id": "feedface",
            "role": "implementer",
            "fix_iteration_index": 0,
            "prompt_bytes": 1,
        },
    ]
    _TOKEN_SUMMARY_MD.unlink(missing_ok=True)
    _TOKEN_JSONL.unlink(missing_ok=True)
    try:
        _write_records_jsonl(rows)
        proc = subprocess.run(
            [
                ps,
                "-NoProfile",
                "-ExecutionPolicy",
                "Bypass",
                "-File",
                str(_SCRIPTS / "show_token_report.ps1"),
                "-ByChain",
            ],
            cwd=str(_ROOT),
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=120,
            check=False,
        )
        combined = ((proc.stdout or "") + (proc.stderr or "")).replace("\r\n", "\n")
        assert proc.returncode == 0, combined
        assert "planner_form (decomposed)" in combined
        assert "planner_command: run_cursor_agent.ps1" in combined
        assert "reviewer_command: run_codex_reviewer.ps1" in combined
        assert "max_review_iters: 3" in combined
        assert "no_revision: False" in combined
        assert "cursor / plan-model-x" in combined
        assert "openai / codex-rev-y" in combined
    finally:
        _TOKEN_JSONL.unlink(missing_ok=True)
        _TOKEN_SUMMARY_MD.unlink(missing_ok=True)


def test_cursor_planner_roles_via_env_match_run_cursor_agent_resolution() -> None:
    """Planning rows use planner / planner_revision when TOKEN_ROLE is empty but PLANNER_ROLE is set (Cursor wrapper parity)."""
    ps = _powershell_exe()
    if not ps:
        pytest.skip("No pwsh or powershell on PATH")

    scratch_parent = _ROOT / "tests" / f".cursor_role_env_{uuid.uuid4().hex}"
    proj = scratch_parent / "token_role_proj"
    ai_loop = proj / ".ai-loop"
    ai_loop.mkdir(parents=True)
    chain_path = ai_loop / "chain.json"
    task_path = ai_loop / "task.md"
    chain_path.write_text(
        json.dumps(
            {
                "planner_chain_id": "cafef00d",
                "task_name": "Role probe",
                "started_at_utc": "2026-05-16T00:00:00Z",
                "planner_form": {
                    "planner_command": "run_cursor_agent.ps1",
                    "planner_model": "m-plan",
                    "reviewer_command": "run_codex_reviewer.ps1",
                    "reviewer_model": "",
                    "max_review_iters": 2,
                    "no_revision": False,
                },
            }
        ),
        encoding="utf-8",
    )
    task_path.write_text("# Task: Role probe\n\nbody\n", encoding="utf-8")
    _TOKEN_JSONL.unlink(missing_ok=True)

    record_dot = str((_SCRIPTS / "record_token_usage.ps1").resolve()).replace("'", "''")
    hint_dot = str(proj.resolve()).replace("'", "''")

    # Mirrors scripts/run_cursor_agent.ps1 phase/role resolution before Write-CliCaptureTokenUsageIfParsed.
    ps_snippet = (
        f". '{record_dot}'; "
        "$cap = '{\"prompt_tokens\":3,\"completion_tokens\":1}'; "
        f"$hint = '{hint_dot}'; "
        "$env:AI_LOOP_TOKEN_PHASE = 'planning'; "
        "Remove-Item Env:\\AI_LOOP_TOKEN_ROLE -ErrorAction SilentlyContinue; "
        "$env:AI_LOOP_PLANNER_ROLE = 'planner'; "
        "$phaseCa = ''; "
        "if ($null -ne $env:AI_LOOP_TOKEN_PHASE -and -not [string]::IsNullOrWhiteSpace([string]$env:AI_LOOP_TOKEN_PHASE)) "
        "{ $phaseCa = [string]$env:AI_LOOP_TOKEN_PHASE }; "
        "$roleCa = ''; "
        "if ($null -ne $env:AI_LOOP_TOKEN_ROLE -and -not [string]::IsNullOrWhiteSpace([string]$env:AI_LOOP_TOKEN_ROLE)) "
        "{ $roleCa = [string]$env:AI_LOOP_TOKEN_ROLE } "
        "elseif ($phaseCa -eq 'planning' -and $null -ne $env:AI_LOOP_PLANNER_ROLE "
        "-and -not [string]::IsNullOrWhiteSpace([string]$env:AI_LOOP_PLANNER_ROLE)) "
        "{ $roleCa = [string]$env:AI_LOOP_PLANNER_ROLE }; "
        "Write-CliCaptureTokenUsageIfParsed -CapturedText $cap -ScriptName 'run_cursor_agent.ps1' "
        "-Provider cursor -Model m -Iteration 0 -ProjectRootHint $hint -Phase $phaseCa -Role $roleCa "
        "-FixIterationIndex -1 -PromptBytes 7; "
        "Remove-Item Env:\\AI_LOOP_TOKEN_ROLE -ErrorAction SilentlyContinue; "
        "$env:AI_LOOP_PLANNER_ROLE = 'planner_revision'; "
        "$phaseCa = [string]$env:AI_LOOP_TOKEN_PHASE; "
        "$roleCa = ''; "
        "if ($null -ne $env:AI_LOOP_TOKEN_ROLE -and -not [string]::IsNullOrWhiteSpace([string]$env:AI_LOOP_TOKEN_ROLE)) "
        "{ $roleCa = [string]$env:AI_LOOP_TOKEN_ROLE } "
        "elseif ($phaseCa -eq 'planning' -and $null -ne $env:AI_LOOP_PLANNER_ROLE "
        "-and -not [string]::IsNullOrWhiteSpace([string]$env:AI_LOOP_PLANNER_ROLE)) "
        "{ $roleCa = [string]$env:AI_LOOP_PLANNER_ROLE }; "
        "Write-CliCaptureTokenUsageIfParsed -CapturedText $cap -ScriptName 'run_cursor_agent.ps1' "
        "-Provider cursor -Model m -Iteration 0 -ProjectRootHint $hint -Phase $phaseCa -Role $roleCa "
        "-FixIterationIndex -1 -PromptBytes 9"
    )

    try:
        code, stdout, stderr = _run_ps_capture(ps_snippet)
        assert code == 0, stderr + stdout
        lines = [ln for ln in _TOKEN_JSONL.read_text(encoding="utf-8").splitlines() if ln.strip()]
        assert len(lines) == 2
        row_planner = json.loads(lines[0])
        row_revision = json.loads(lines[1])
        assert row_planner["role"] == "planner"
        assert row_planner["phase"] == "planning"
        assert row_planner["script_name"] == "run_cursor_agent.ps1"
        assert row_planner["planner_chain_id"] == "cafef00d"
        assert row_planner["planner_command"] == "run_cursor_agent.ps1"
        assert row_planner["max_review_iters"] == 2
        assert row_planner["no_revision"] is False
        assert row_revision["role"] == "planner_revision"
        assert row_revision["phase"] == "planning"
        assert row_revision["planner_command"] == "run_cursor_agent.ps1"
        report = subprocess.run(
            [ps, "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", str(_SCRIPTS / "show_token_report.ps1"), "-ByChain"],
            cwd=str(_ROOT),
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=120,
            check=False,
        )
        combined = ((report.stdout or "") + (report.stderr or "")).replace("\r\n", "\n")
        assert report.returncode == 0, combined
        assert "planner_command: run_cursor_agent.ps1" in combined
    finally:
        _TOKEN_JSONL.unlink(missing_ok=True)
        shutil.rmtree(scratch_parent, ignore_errors=True)


def test_wrap_up_session_appends_wrap_up_ledger_row() -> None:
    ps = _powershell_exe()
    if not ps:
        pytest.skip("No pwsh or powershell on PATH")
    ai_loop = _ROOT / ".ai-loop"
    summary = ai_loop / "implementer_summary.md"
    chain_path = ai_loop / "chain.json"
    draft = ai_loop / "_debug" / "session_draft.md"
    _TOKEN_JSONL.unlink(missing_ok=True)
    ai_loop.mkdir(parents=True, exist_ok=True)
    summary.write_text(
        "## Changed files\n- `scripts/x.ps1`\n\n## Other\n",
        encoding="utf-8",
    )
    chain_path.write_text(
        json.dumps(
            {
                "planner_chain_id": "deadbeef",
                "task_name": "wrap ledger probe",
                "started_at_utc": "2026-05-16T00:00:00Z",
                "planner_form": {},
            }
        ),
        encoding="utf-8",
    )
    try:
        proc = subprocess.run(
            [
                ps,
                "-NoProfile",
                "-ExecutionPolicy",
                "Bypass",
                "-File",
                str(_SCRIPTS / "wrap_up_session.ps1"),
            ],
            cwd=str(_ROOT),
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=120,
            check=False,
        )
        detail = (proc.stdout or "") + (proc.stderr or "")
        assert proc.returncode == 0, detail
        assert _TOKEN_JSONL.is_file(), detail
        lines = [ln for ln in _TOKEN_JSONL.read_text(encoding="utf-8").splitlines() if ln.strip()]
        assert len(lines) == 1
        data = json.loads(lines[0])
        assert data["phase"] == "wrap_up"
        assert data["role"] == "wrap_up"
        assert data["script_name"] == "wrap_up_session.ps1"
        assert "fix_iteration_index" not in data
        assert data.get("prompt_bytes", 0) == 0
        assert data.get("planner_chain_id") == "deadbeef"
        assert data.get("task_name") == "wrap ledger probe"
    finally:
        _TOKEN_JSONL.unlink(missing_ok=True)
        summary.unlink(missing_ok=True)
        chain_path.unlink(missing_ok=True)
        draft.unlink(missing_ok=True)


def test_wrap_up_session_ps1_parse_clean() -> None:
    ps = _powershell_exe()
    if not ps:
        pytest.skip("No pwsh or powershell on PATH")
    _parse_file_via_ast(_SCRIPTS / "wrap_up_session.ps1", ps=ps)


def test_show_report_by_chain_aggregation() -> None:
    ps = _powershell_exe()
    if not ps:
        pytest.skip("No pwsh or powershell on PATH")
    ts = "2026-05-15T12:00:00.0000000Z"
    rows = [
        {
            "task_name": "t",
            "script_name": "s",
            "iteration": 0,
            "provider": "p",
            "model": "m",
            "input_tokens": 10,
            "output_tokens": 0,
            "total_tokens": 10,
            "timestamp": ts,
            "planner_chain_id": "abc12345",
            "role": "implementer",
            "fix_iteration_index": 2,
            "prompt_bytes": 5,
        },
        {
            "task_name": "t",
            "script_name": "s2",
            "iteration": 1,
            "provider": "p",
            "model": "m",
            "input_tokens": 3,
            "output_tokens": 1,
            "total_tokens": 4,
            "timestamp": ts,
            "planner_chain_id": "abc12345",
            "role": "implementer",
            "fix_iteration_index": 1,
            "prompt_bytes": 7,
        },
    ]
    _TOKEN_SUMMARY_MD.unlink(missing_ok=True)
    _TOKEN_JSONL.unlink(missing_ok=True)
    try:
        _write_records_jsonl(rows)
        proc = subprocess.run(
            [
                ps,
                "-NoProfile",
                "-ExecutionPolicy",
                "Bypass",
                "-File",
                str(_SCRIPTS / "show_token_report.ps1"),
                "-ByChain",
            ],
            cwd=str(_ROOT),
            capture_output=True,
            text=True,
            timeout=120,
            check=False,
        )
        combined = ((proc.stdout or "") + (proc.stderr or "")).replace("\r\n", "\n")
        assert proc.returncode == 0, combined
        assert "abc12345" in combined
        assert "fix_iters" in combined.lower()
        assert "2" in combined
    finally:
        _TOKEN_JSONL.unlink(missing_ok=True)
        _TOKEN_SUMMARY_MD.unlink(missing_ok=True)


def test_prompt_bytes_utf8_not_char_count() -> None:
    ps = _powershell_exe()
    if not ps:
        pytest.skip("No pwsh or powershell on PATH")
    _TOKEN_JSONL.unlink(missing_ok=True)
    try:
        cmd = (
            ". .\\scripts\\record_token_usage.ps1; "
            "$s = \"x$([char]0x20AC)\"; "
            "$n = [System.Text.Encoding]::UTF8.GetByteCount($s); "
            "Write-TokenUsageRecord -TaskName pb -ScriptName s -Iteration 0 -Provider p -Model m "
            "-InputTokens $null -OutputTokens $null -TotalTokens $null -Source cli_capture_unparsed "
            "-Confidence unknown -Quality unknown -Phase implementation -Role implementer "
            "-FixIterationIndex 0 -PromptBytes $n; "
            "($s).Length; $n"
        )
        code, stdout, stderr = _run_ps_capture(cmd)
        assert code == 0, stderr
        lines = [x.strip() for x in stdout.splitlines() if x.strip()]
        char_len, byte_hint = int(lines[0]), int(lines[1])
        assert char_len != byte_hint
        data = json.loads(_TOKEN_JSONL.read_text(encoding="utf-8").strip().splitlines()[-1])
        assert data["prompt_bytes"] == byte_hint
    finally:
        _TOKEN_JSONL.unlink(missing_ok=True)


def test_run_opencode_scout_ps1_parse_clean() -> None:
    ps = _powershell_exe()
    if not ps:
        pytest.skip("No pwsh or powershell on PATH")
    _parse_file_via_ast(_SCRIPTS / "run_opencode_scout.ps1", ps=ps)
