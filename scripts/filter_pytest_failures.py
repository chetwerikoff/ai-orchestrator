"""Filter pytest -q output into a structured failures summary.

Deterministic: reads stdin/file, writes Markdown. No network, no LLM.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

FAILED_LINE_RE = re.compile(r"^FAILED\s+(\S+)(?:\s+-\s+(.*))?$")
FAILURES_HEADER_RE = re.compile(r"^=+\s*FAILURES\s*=+$")
SHORT_SUMMARY_HEADER_RE = re.compile(r"^=+\s*short test summary info\s*=+$", re.IGNORECASE)
FAILURE_BLOCK_TITLE_RE = re.compile(r"^_{5,}\s*(.+?)\s*_{5,}$")


def _is_session_summary_banner(line: str) -> bool:
    """True for pytest's final '=== N failed in Xs ===' style line."""
    s = line.strip()
    if len(s) < 8 or "=" not in s:
        return False
    return bool(re.search(r"\d+\s+(?:failed|passed|error|skipped|warnings?)\b", s, re.I))


def _is_plain_pytest_summary_line(line: str) -> bool:
    """True for pytest's trailing count line without === banners, e.g. '1 failed, 261 passed in 5.0s'."""
    s = line.strip()
    if not s:
        return False
    if not re.search(r"\d+\s+(?:failed|passed|errors?|skipped|warnings?)\b", s, re.I):
        return False
    return bool(re.search(r"\b in \s*[\d.]+\s*s\s*$", s, re.I))


def _find_failures_header(lines: list[str]) -> int | None:
    for i, ln in enumerate(lines):
        if FAILURES_HEADER_RE.match(ln.strip()) or FAILURES_HEADER_RE.match(ln):
            return i
    return None


def _find_short_summary_header(lines: list[str]) -> int | None:
    for i, ln in enumerate(lines):
        if SHORT_SUMMARY_HEADER_RE.match(ln.strip()) or SHORT_SUMMARY_HEADER_RE.match(ln):
            return i
    return None


def _parse_short_summary_failed_lines(lines: list[str], start: int) -> list[tuple[str, str | None]]:
    """Collect FAILED node lines after 'short test summary info' until a session banner or bare ===."""
    out: list[tuple[str, str | None]] = []
    for j in range(start, len(lines)):
        ln = lines[j]
        if _is_session_summary_banner(ln):
            break
        m = FAILED_LINE_RE.match(ln)
        if m:
            msg = m.group(2)
            out.append((m.group(1), msg.strip() if msg else None))
    return out


def _split_failures_blocks(
    section_lines: list[str],
) -> list[tuple[str | None, list[str]]]:
    """Split FAILURES body into (underscore-banner title, traceback lines)."""
    blocks: list[tuple[str | None, list[str]]] = []
    i = 0
    while i < len(section_lines):
        ln = section_lines[i]
        tm = FAILURE_BLOCK_TITLE_RE.match(ln.strip()) or FAILURE_BLOCK_TITLE_RE.match(ln)
        if tm:
            title = tm.group(1).strip()
            i += 1
            chunk: list[str] = []
            while i < len(section_lines):
                nxt = section_lines[i]
                s = nxt.strip()
                if FAILURE_BLOCK_TITLE_RE.match(s) or FAILURE_BLOCK_TITLE_RE.match(nxt):
                    break
                chunk.append(nxt)
                i += 1
            while chunk and not chunk[-1].strip():
                chunk.pop()
            if chunk:
                blocks.append((title, chunk))
        else:
            i += 1
    if not blocks and section_lines:
        tail = [x for x in section_lines if x.strip()]
        if tail:
            blocks.append((None, tail))
    return blocks


def parse_failures(text: str) -> list[dict]:
    """Return list of {'name': str, 'traceback': list[str]}."""
    lines = text.splitlines()
    fh = _find_failures_header(lines)
    ssh = _find_short_summary_header(lines)

    # Preferred: FAILURES section + short test summary (realistic pytest -q)
    if fh is not None and ssh is not None and ssh > fh:
        section = lines[fh + 1 : ssh]
        while section and not section[0].strip():
            section.pop(0)
        block_meta = _split_failures_blocks(section)
        chunks = [b[1] for b in block_meta]
        titles = [b[0] for b in block_meta]
        failed_pairs = _parse_short_summary_failed_lines(lines, ssh + 1)
        names = [p[0] for p in failed_pairs]

        failures = []
        if chunks and names and len(chunks) == len(names):
            for name, chunk in zip(names, chunks):
                failures.append({"name": name, "traceback": list(chunk)})
        elif chunks and names:
            n_pair = min(len(chunks), len(names))
            for k in range(n_pair):
                failures.append({"name": names[k], "traceback": list(chunks[k])})
            for k in range(n_pair, len(names)):
                failures.append({"name": names[k], "traceback": []})
            for k in range(n_pair, len(chunks)):
                t = titles[k]
                label = t if t else f"(unmatched FAILURES block {k - n_pair + 1})"
                failures.append({"name": label, "traceback": list(chunks[k])})
        elif names:
            for nm, _msg in failed_pairs:
                failures.append({"name": nm, "traceback": []})
        elif chunks:
            for (t, chunk) in block_meta:
                label = t if t else "(unknown failure)"
                failures.append({"name": label, "traceback": list(chunk)})
        if failures:
            return failures

    # Fallback: scan FAILED lines and following lines (thin / old layouts)
    return _parse_failures_fallback(lines)


def _parse_failures_fallback(lines: list[str]) -> list[dict]:
    failures: list[dict] = []
    i = 0
    while i < len(lines):
        m = FAILED_LINE_RE.match(lines[i])
        if m:
            name = m.group(1)
            trace: list[str] = []
            j = i + 1
            while j < len(lines):
                ln = lines[j]
                if FAILED_LINE_RE.match(ln):
                    break
                if SHORT_SUMMARY_HEADER_RE.match(ln.strip()):
                    break
                if _is_session_summary_banner(ln):
                    break
                if FAILURES_HEADER_RE.match(ln.strip()):
                    break
                if _is_plain_pytest_summary_line(ln):
                    break
                st = ln.strip()
                if (
                    st.startswith(("passed", "failed", "skipped", "error"))
                    and "=" in ln
                    and ln.strip().startswith(("passed", "failed"))
                ):
                    break
                trace.append(ln)
                j += 1
            while trace and not trace[-1].strip():
                trace.pop()
            failures.append({"name": name, "traceback": trace})
            i = j
        else:
            i += 1
    return failures


def parse_summary_line(text: str) -> str:
    """Return the final pytest session summary line (durations / counts)."""
    for line in reversed(text.splitlines()):
        s = line.strip().strip("= ")
        if not s:
            continue
        if _is_session_summary_banner(line):
            return s
        # Fallback: last line with typical count wording
        if re.search(r"\d+\s+(?:failed|passed|error|skipped)\b", s, re.I) and (
            " in " in s or re.search(r"in\s+[\d.]+s\s*$", s)
        ):
            return s
    return ""


def render(failures: list[dict], summary_line: str) -> str:
    parts = ["# Test failures summary", ""]
    parts.append("## Summary line")
    parts.append("")
    parts.append("```")
    parts.append(summary_line or "(no summary line found)")
    parts.append("```")
    parts.append("")
    parts.append(f"## Failed: {len(failures)}")
    parts.append("")
    for f in failures:
        parts.append(f"### {f['name']}")
        parts.append("")
        parts.append("```")
        trace = list(f["traceback"])
        while trace and not trace[-1].strip():
            trace.pop()
        parts.extend(trace if trace else ["(no traceback captured)"])
        parts.append("```")
        parts.append("")
    return "\n".join(parts).rstrip() + "\n"


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--input", required=True)
    p.add_argument("--output", required=True)
    args = p.parse_args()
    text = Path(args.input).read_text(encoding="utf-8", errors="replace")
    failures = parse_failures(text)
    summary_line = parse_summary_line(text)
    Path(args.output).write_text(render(failures, summary_line), encoding="utf-8")
    return 0


if __name__ == "__main__":
    sys.exit(main())
