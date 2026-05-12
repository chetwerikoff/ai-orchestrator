from pathlib import Path
import subprocess
import sys

REPO = Path(__file__).resolve().parents[1]
SCRIPT = REPO / "scripts" / "filter_pytest_failures.py"


def test_filter_handles_no_failures(tmp_path: Path) -> None:
    src = tmp_path / "in.txt"
    src.write_text("262 passed, 3 skipped in 63.81s\n", encoding="utf-8")
    out = tmp_path / "out.md"
    subprocess.run(
        [sys.executable, str(SCRIPT), "--input", str(src), "--output", str(out)],
        check=True,
        capture_output=True,
        text=True,
    )
    assert out.exists()
    body = out.read_text(encoding="utf-8")
    assert "Failed: 0" in body
    assert "262 passed, 3 skipped" in body


def test_filter_extracts_one_failure(tmp_path: Path) -> None:
    src = tmp_path / "in.txt"
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
    out = tmp_path / "out.md"
    subprocess.run(
        [sys.executable, str(SCRIPT), "--input", str(src), "--output", str(out)],
        check=True,
    )
    body = out.read_text(encoding="utf-8")
    assert "Failed: 1" in body
    assert "tests/test_foo.py::test_bar" in body
    assert "assert 1 == 2" in body
    fence_chunks = body.split("```")
    assert len(fence_chunks) >= 4
    traceback_fence = fence_chunks[3]
    assert "1 failed, 261 passed in 5.0s" not in traceback_fence


def test_filter_realistic_failures_section_and_summary(tmp_path: Path) -> None:
    """pytest -q style: FAILURES blocks, short test summary, final session line."""
    src = tmp_path / "in.txt"
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
    out = tmp_path / "out.md"
    subprocess.run(
        [sys.executable, str(SCRIPT), "--input", str(src), "--output", str(out)],
        check=True,
    )
    body = out.read_text(encoding="utf-8")
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
    # Final session count line belongs in Summary only, not in traceback
    assert "1 failed, 261 passed, 3 warnings in 5.01s" not in traceback_fence
