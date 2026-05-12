"""Tests for scripts/filter_pytest_failures.py.

Uses unique-named scratch files under tests/ to avoid Windows
PermissionError on pytest's tmp_path / AppData/Local/Temp directories.
"""

from __future__ import annotations

import subprocess
import sys
import uuid
from pathlib import Path

_TESTS_DIR = Path(__file__).resolve().parent
SCRIPT = _TESTS_DIR.parent / "scripts" / "filter_pytest_failures.py"


def _scratch() -> tuple[Path, Path]:
    """Return (input_path, output_path) unique scratch files under tests/."""
    uid = uuid.uuid4().hex
    return (
        _TESTS_DIR / f".filter_pytest_in_{uid}.txt",
        _TESTS_DIR / f".filter_pytest_out_{uid}.md",
    )


def _run(src: Path, out: Path) -> str:
    subprocess.run(
        [sys.executable, str(SCRIPT), "--input", str(src), "--output", str(out)],
        check=True,
        capture_output=True,
        text=True,
    )
    return out.read_text(encoding="utf-8")


def test_filter_handles_no_failures() -> None:
    src, out = _scratch()
    try:
        src.write_text("262 passed, 3 skipped in 63.81s\n", encoding="utf-8")
        body = _run(src, out)
        assert "Failed: 0" in body
        assert "262 passed, 3 skipped" in body
    finally:
        src.unlink(missing_ok=True)
        out.unlink(missing_ok=True)


def test_filter_extracts_one_failure() -> None:
    src, out = _scratch()
    try:
        src.write_text(
            "\n".join(
                [
                    "FAILED tests/test_foo.py::test_bar - assert 1 == 2",
                    "  E   assert 1 == 2",
                    "  E   +  where 1 = some_fn()",
                    "",
                    "1 failed, 261 passed in 5.0s",
                ]
            )
            + "\n",
            encoding="utf-8",
        )
        body = _run(src, out)
        assert "Failed: 1" in body
        assert "tests/test_foo.py::test_bar" in body
        assert "assert 1 == 2" in body
        fence_chunks = body.split("```")
        assert len(fence_chunks) >= 4
        traceback_fence = fence_chunks[3]
        assert "1 failed, 261 passed in 5.0s" not in traceback_fence
    finally:
        src.unlink(missing_ok=True)
        out.unlink(missing_ok=True)


def test_filter_realistic_failures_section_and_summary() -> None:
    """pytest -q style: FAILURES blocks, short test summary, final session line."""
    src, out = _scratch()
    try:
        src.write_text(
            "\n".join(
                [
                    ".........................................F............ [ 87%]",
                    "........................................................ [100%]",
                    "",
                    "=================================== FAILURES ===================================",
                    "_____________________________ test_bar _____________________________",
                    "",
                    "    def test_bar():",
                    ">       assert 1 == 2",
                    "E       AssertionError: assert 1 == 2",
                    "E       +  where 1 = some_fn()",
                    "",
                    "tests/test_foo.py:42: AssertionError",
                    "=========================== short test summary info ============================",
                    "FAILED tests/test_foo.py::test_bar - AssertionError: assert 1 == 2",
                    "=================== 1 failed, 261 passed, 3 warnings in 5.01s ===================",
                ]
            )
            + "\n",
            encoding="utf-8",
        )
        body = _run(src, out)
        assert "Failed: 1" in body
        assert "### tests/test_foo.py::test_bar" in body
        assert ">       assert 1 == 2" in body
        assert "E       AssertionError" in body
        assert "tests/test_foo.py:42: AssertionError" in body
        assert "1 failed, 261 passed, 3 warnings in 5.01s" in body
        fence_chunks = body.split("```")
        assert len(fence_chunks) >= 4
        traceback_fence = fence_chunks[3]
        assert "short test summary info" not in traceback_fence
        assert "1 failed, 261 passed, 3 warnings in 5.01s" not in traceback_fence
    finally:
        src.unlink(missing_ok=True)
        out.unlink(missing_ok=True)
