"""Claude task reviewer (variant A) smoke tests."""

from __future__ import annotations

import shutil
import subprocess
from pathlib import Path

import pytest

_ROOT = Path(__file__).resolve().parent.parent
_SCRIPTS = _ROOT / "scripts"


def _powershell_exe() -> str | None:
    return shutil.which("pwsh") or shutil.which("powershell")


def test_run_claude_reviewer_parse_check() -> None:
    ps = _powershell_exe()
    if not ps:
        pytest.skip("No pwsh or powershell on PATH")
    script = _SCRIPTS / "run_claude_reviewer.ps1"
    assert script.is_file()
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
    detail = (proc.stdout or "").strip() + (proc.stderr or "").strip()
    assert proc.returncode == 0, detail


def test_claude_task_reviewer_prompt_exists() -> None:
    assert (_ROOT / "templates" / "claude_task_reviewer_prompt.md").is_file()


def _reviewer_strict_verdict(plan_escaped: str, issues_ps_literal: str) -> str:
    ps = _powershell_exe()
    if not ps:
        pytest.skip("No pwsh or powershell on PATH")
    inner = f"""
$plan = '{plan_escaped}'
. $plan
$o = {issues_ps_literal}
$r = Test-ReviewerOutputStrict -Output $o
if (-not $r.Ok) {{ 'MALFORMED'; exit 0 }}
if (($o.Trim()) -eq 'NO_BLOCKING_ISSUES') {{ 'NO_BLOCKING'; exit 0 }}
'ISSUES'
""".strip()
    proc = subprocess.run(
        [ps, "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", inner],
        cwd=str(_ROOT),
        capture_output=True,
        text=True,
        timeout=120,
        check=False,
    )
    out = (proc.stdout or "").strip()
    detail = out + (proc.stderr or "").strip()
    assert proc.returncode == 0, detail
    return out


def test_reviewer_strict_accepts_architecture_and_safety() -> None:
    plan = _SCRIPTS / "ai_loop_plan.ps1"
    plan_escaped = str(plan.resolve()).replace("'", "''")
    lit = '"ISSUES:`n- [architecture] bad scope`n- [safety] missing guard"'
    assert _reviewer_strict_verdict(plan_escaped, lit) == "ISSUES"


def test_reviewer_strict_rejects_unknown_category() -> None:
    plan = _SCRIPTS / "ai_loop_plan.ps1"
    plan_escaped = str(plan.resolve()).replace("'", "''")
    lit = '"ISSUES:`n- [unknown] something"'
    assert _reviewer_strict_verdict(plan_escaped, lit) == "MALFORMED"


def test_claude_reviewer_default_model_is_haiku() -> None:
    text = (_SCRIPTS / "run_claude_reviewer.ps1").read_text(encoding="utf-8")
    assert "haiku" in text.lower()
