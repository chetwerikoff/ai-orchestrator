"""Unit tests for ai_loop.py pure helpers (stdlib-only module)."""

from __future__ import annotations

import sys
import uuid
from pathlib import Path

# Import module under test from repo root when running pytest from project root.
_TESTS_DIR = Path(__file__).resolve().parent
_ROOT = _TESTS_DIR.parent
if str(_ROOT) not in sys.path:
    sys.path.insert(0, str(_ROOT))

import ai_loop as al  # noqa: E402


def test_slugify_basic() -> None:
    assert al.slugify("Hello World!") == "hello-world"


def test_slugify_empty_fallback() -> None:
    assert al.slugify("   @@@   ") == "task"


def test_slugify_max_len() -> None:
    assert al.slugify("abcdefghijklmnopqrstuvwxyz0123456789", max_len=10) == "abcdefghij"


def test_write_text_safe_writes_and_skips() -> None:
    # Unique file under tests/ only; avoids tmp_path, .tmp/pytest-of-*, and repo-root temp dirs.
    target = _TESTS_DIR / f".write_text_safe_scratch_{uuid.uuid4().hex}.txt"
    try:
        written, reason = al.write_text_safe(target, "x", force=False)
        assert written is True
        assert "written" in reason
        assert target.read_text(encoding="utf-8") == "x"

        written2, reason2 = al.write_text_safe(target, "y", force=False)
        assert written2 is False
        assert "exists" in reason2
        assert target.read_text(encoding="utf-8") == "x"

        written3, _ = al.write_text_safe(target, "y", force=True)
        assert written3 is True
        assert target.read_text(encoding="utf-8") == "y"
    finally:
        try:
            target.unlink(missing_ok=True)
        except OSError:
            pass
