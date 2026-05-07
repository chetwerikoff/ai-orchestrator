#!/usr/bin/env python3
"""
ai_loop.py - GitHub PR orchestrator for AI coding loops

Constraints:
- Standard library only
- Must work on native Windows PowerShell (no WSL)
- Does not invoke Cursor automatically
"""

from __future__ import annotations

import argparse
import datetime as _dt
import json
import re
import shlex
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable, Optional


APP_DIRNAME = ".ai-loop"


class CmdError(RuntimeError):
    pass


def eprint(*args: object) -> None:
    print(*args, file=sys.stderr)


def _format_cmd_for_print(cmd: list[str] | str) -> str:
    if isinstance(cmd, str):
        return cmd
    # PowerShell-friendly rendering; still just informational.
    return " ".join(shlex.quote(x) for x in cmd)


def run_cmd(
    cmd: list[str] | str,
    *,
    cwd: Optional[Path] = None,
    check: bool = True,
    capture: bool = False,
    shell: bool = False,
    env: Optional[dict[str, str]] = None,
) -> subprocess.CompletedProcess[str]:
    """
    Run a shell command with safety:
    - Always prints the command before running
    - Uses text mode
    - Raises CmdError on failure when check=True
    """
    printable = _format_cmd_for_print(cmd)
    print(f"$ {printable}")

    try:
        run_kwargs: dict[str, object] = dict(
            args=cmd,
            cwd=str(cwd) if cwd else None,
            check=False,
            text=True,
            capture_output=capture,
            shell=shell,
            env=env,
        )
        # Avoid locale decode errors when capturing on Windows (e.g. smart quotes in pytest output).
        if capture:
            run_kwargs["encoding"] = "utf-8"
            run_kwargs["errors"] = "replace"
        cp = subprocess.run(**run_kwargs)
    except FileNotFoundError as ex:
        raise CmdError(f"Command not found: {printable}") from ex
    except OSError as ex:
        raise CmdError(f"Failed to run command: {printable}\n{ex}") from ex

    if check and cp.returncode != 0:
        out = (cp.stdout or "") + (cp.stderr or "")
        raise CmdError(f"Command failed ({cp.returncode}): {printable}\n{out}".rstrip())
    return cp


def git_root(start_dir: Path) -> Optional[Path]:
    try:
        cp = run_cmd(["git", "rev-parse", "--show-toplevel"], cwd=start_dir, capture=True, check=True)
        root = (cp.stdout or "").strip()
        return Path(root) if root else None
    except CmdError:
        return None


def ensure_git_repo(start_dir: Path) -> Path:
    root = git_root(start_dir)
    if root:
        return root

    # Not a git repo (or git can't detect). Initialize in the current directory.
    run_cmd(["git", "init"], cwd=start_dir, check=True)
    root = git_root(start_dir)
    if not root:
        raise CmdError("git init ran but repo root could not be determined")
    return root


def require_git_repo(start_dir: Path) -> Path:
    root = git_root(start_dir)
    if not root:
        raise CmdError("Current directory is not inside a git repository. Run: ai_loop.py init")
    return root


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def write_text_safe(path: Path, content: str, *, force: bool) -> tuple[bool, str]:
    """
    Writes a file safely.
    Returns (written, reason).
    - Will not overwrite an existing non-empty file unless force=True.
    - Creates parent directories.
    """
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists():
        try:
            if path.is_file() and path.stat().st_size > 0 and not force:
                return (False, "exists and is non-empty (use --force to overwrite)")
        except OSError:
            # If we can't stat it, err on the safe side.
            if not force:
                return (False, "exists (unreadable metadata; use --force to overwrite)")
    path.write_text(content, encoding="utf-8")
    return (True, "written")


def append_gitignore_lines(root: Path, lines: Iterable[str]) -> None:
    gi = root / ".gitignore"
    existing = ""
    if gi.exists():
        try:
            existing = read_text(gi)
        except OSError:
            existing = ""
    to_add: list[str] = []
    for ln in lines:
        if not ln.endswith("\n"):
            ln2 = ln + "\n"
        else:
            ln2 = ln
        if ln.strip() and ln.strip() not in existing:
            to_add.append(ln2)
    if to_add:
        gi.parent.mkdir(parents=True, exist_ok=True)
        with gi.open("a", encoding="utf-8", newline="") as f:
            # Ensure spacing for readability.
            if existing and not existing.endswith("\n"):
                f.write("\n")
            f.write("\n# ai-loop artifacts\n")
            for ln2 in to_add:
                f.write(ln2)


def slugify(s: str, *, max_len: int = 32) -> str:
    s = s.strip().lower()
    s = re.sub(r"[^a-z0-9]+", "-", s)
    s = re.sub(r"-{2,}", "-", s).strip("-")
    if not s:
        s = "task"
    return s[:max_len].rstrip("-")


def current_branch(root: Path) -> str:
    cp = run_cmd(["git", "rev-parse", "--abbrev-ref", "HEAD"], cwd=root, capture=True)
    return (cp.stdout or "").strip()


def ensure_origin_remote(root: Path) -> bool:
    cp = run_cmd(["git", "remote"], cwd=root, capture=True)
    remotes = {r.strip() for r in (cp.stdout or "").splitlines() if r.strip()}
    return "origin" in remotes


def git_status_porcelain(root: Path) -> str:
    cp = run_cmd(["git", "status", "--porcelain"], cwd=root, capture=True)
    return cp.stdout or ""


def git_status_short(root: Path) -> str:
    """Same as `git status --short` (matches PowerShell orchestrator artifact)."""
    cp = run_cmd(["git", "status", "--short"], cwd=root, capture=True)
    return cp.stdout or ""


def git_diff_stat(root: Path) -> str:
    cp = run_cmd(["git", "diff", "--stat"], cwd=root, capture=True)
    return cp.stdout or ""


def git_diff_patch(root: Path) -> str:
    cp = run_cmd(["git", "diff"], cwd=root, capture=True)
    return cp.stdout or ""


def git_diff_staged_patch(root: Path) -> str:
    cp = run_cmd(["git", "diff", "--staged"], cwd=root, capture=True)
    return cp.stdout or ""


def git_untracked_files(root: Path) -> list[str]:
    cp = run_cmd(["git", "ls-files", "--others", "--exclude-standard"], cwd=root, capture=True)
    return [ln.strip() for ln in (cp.stdout or "").splitlines() if ln.strip()]


def is_dirty_worktree(root: Path) -> bool:
    return bool(git_status_porcelain(root).strip())


def ensure_gh_ready(root: Path) -> None:
    try:
        run_cmd(["gh", "--version"], cwd=root, check=True, capture=True)
    except CmdError as ex:
        raise CmdError("GitHub CLI (`gh`) is not installed or not on PATH.") from ex

    auth = run_cmd(["gh", "auth", "status"], cwd=root, check=False, capture=True)
    if auth.returncode != 0:
        raise CmdError("GitHub CLI is not authenticated. Run: gh auth login")


def ensure_no_force_push_guard(cmd: list[str] | str) -> None:
    txt = cmd if isinstance(cmd, str) else " ".join(cmd)
    if "--force" in txt or "-f" in txt.split():
        raise CmdError("Safety: refusing to run a force push command")


def make_ai_loop_paths(root: Path) -> dict[str, Path]:
    base = root / APP_DIRNAME
    return {
        "base": base,
        "task": base / "task.md",
        "cursor_prompt": base / "cursor_prompt.md",
        "cursor_summary": base / "cursor_summary.md",
        "codex_review": base / "codex_review.md",
        "pr_body": base / "pr_body.md",
        "test_output": base / "test_output.txt",
        "git_status": base / "git_status.txt",
        "last_diff": base / "last_diff.patch",
        "pr_url": base / "pr_url.txt",
    }


def require_file(path: Path, *, hint: str) -> str:
    if not path.exists():
        raise CmdError(f"Missing required file: {path}\n{hint}")
    try:
        return read_text(path)
    except OSError as ex:
        raise CmdError(f"Failed to read: {path}\n{ex}") from ex


def cmd_init(args: argparse.Namespace) -> None:
    root = ensure_git_repo(Path.cwd())
    paths = make_ai_loop_paths(root)
    force: bool = bool(args.force)

    # Create scaffold files.
    agents_md = root / "AGENTS.md"
    cursor_rule = root / ".cursor" / "rules" / "ai-loop.mdc"
    task_md = paths["task"]
    cursor_prompt = paths["cursor_prompt"]
    cursor_summary = paths["cursor_summary"]
    codex_review = paths["codex_review"]
    pr_body = paths["pr_body"]

    (paths["base"]).mkdir(parents=True, exist_ok=True)
    (root / ".cursor" / "rules").mkdir(parents=True, exist_ok=True)

    created: list[tuple[Path, bool, str]] = []

    created.append(
        (
            agents_md,
            *write_text_safe(
                agents_md,
                "# AGENTS\n\nThis repository uses `ai_loop.py` to orchestrate AI coding loops.\n",
                force=force,
            ),
        )
    )

    created.append(
        (
            cursor_rule,
            *write_text_safe(
                cursor_rule,
                "---\n"
                "description: AI Loop orchestration guardrails\n"
                "globs:\n"
                "  - '**/*'\n"
                "---\n\n"
                "You are assisting via an AI coding loop orchestrated by `ai_loop.py`.\n"
                "- Follow instructions in `.ai-loop/cursor_prompt.md`.\n"
                "- Update `.ai-loop/cursor_summary.md` when done.\n"
                "- Do not run destructive commands.\n",
                force=force,
            ),
        )
    )

    created.append(
        (
            task_md,
            *write_text_safe(
                task_md,
                "# Task\n\nDescribe the change you want the AI to implement.\n",
                force=force,
            ),
        )
    )

    created.append(
        (
            cursor_prompt,
            *write_text_safe(
                cursor_prompt,
                "# Cursor Prompt\n\nRun `ai_loop.py start` to regenerate this file.\n",
                force=force,
            ),
        )
    )

    created.append(
        (
            cursor_summary,
            *write_text_safe(
                cursor_summary,
                "# Cursor Summary\n\n(Cursor Agent will write a summary here.)\n",
                force=force,
            ),
        )
    )

    created.append(
        (
            codex_review,
            *write_text_safe(
                codex_review,
                "# Review Notes\n\n(Collected PR review comments will be written here.)\n",
                force=force,
            ),
        )
    )

    created.append(
        (
            pr_body,
            *write_text_safe(
                pr_body,
                "# PR Body\n\n(Generated by `ai_loop.py open-pr`.)\n",
                force=force,
            ),
        )
    )

    # Ensure gitignore has required entries.
    append_gitignore_lines(
        root,
        [
            f"{APP_DIRNAME}/test_output.txt",
            f"{APP_DIRNAME}/git_status.txt",
            f"{APP_DIRNAME}/last_diff.patch",
        ],
    )

    print(f"Repo root: {root}")
    for path, written, reason in created:
        status = "OK" if written else "SKIP"
        print(f"[{status}] {path.relative_to(root)} - {reason}")


def cmd_create_github(args: argparse.Namespace) -> None:
    root = ensure_git_repo(Path.cwd())
    ensure_gh_ready(root)

    repo_name: Optional[str] = args.name
    visibility_flags: list[str] = []
    if args.public and args.private:
        raise CmdError("Choose only one of --public or --private")
    if args.public:
        visibility_flags.append("--public")
    elif args.private:
        visibility_flags.append("--private")
    else:
        visibility_flags.append("--private")  # default

    has_origin = ensure_origin_remote(root)
    if has_origin:
        print("origin remote already exists; skipping GitHub repo creation.")
    else:
        cmd = ["gh", "repo", "create"]
        if repo_name:
            cmd.append(repo_name)
        cmd += visibility_flags
        cmd += ["--source", ".", "--remote", "origin"]
        run_cmd(cmd, cwd=root, check=True)

        if not ensure_origin_remote(root):
            cp = run_cmd(["gh", "repo", "view", "--json", "sshUrl,httpsUrl"], cwd=root, capture=True)
            data = json.loads(cp.stdout or "{}")
            url = data.get("sshUrl") or data.get("httpsUrl")
            if not url:
                raise CmdError("Could not determine repo URL from gh")
            run_cmd(["git", "remote", "add", "origin", url], cwd=root, check=True)

    # Exactly one push command in normal flow (never force).
    ensure_no_force_push_guard(["git", "push", "-u", "origin", "HEAD"])
    run_cmd(["git", "push", "-u", "origin", "HEAD"], cwd=root, check=True)


def _generate_cursor_prompt(task_text: str, *, mode: str) -> str:
    # mode: "implement" or "fix"
    if mode == "implement":
        header = "Implement the task below."
    else:
        header = "Fix ONLY the issues listed in Codex review below."

    return (
        "# Cursor Agent Instructions\n\n"
        f"## Objective\n\n{header}\n\n"
        "## Rules\n\n"
        "- Make minimal, high-quality changes.\n"
        "- Do not delete files unless explicitly required by the task.\n"
        "- Do not run git push --force.\n"
        "- Keep changes focused; avoid drive-by refactors.\n\n"
        "## Task\n\n"
        f"{task_text.strip()}\n\n"
        "## Output\n\n"
        "When finished, update `.ai-loop/cursor_summary.md` with:\n"
        "- What changed (high level)\n"
        "- Files touched\n"
        "- How to test\n"
        "- Any follow-ups / risks\n"
    )


def cmd_start(args: argparse.Namespace) -> None:
    root = require_git_repo(Path.cwd())
    paths = make_ai_loop_paths(root)
    task_text = require_file(paths["task"], hint="Run: ai_loop.py init")
    if is_dirty_worktree(root):
        raise CmdError("Working tree is dirty. Commit or stash changes before running start.")

    now = _dt.datetime.now()
    slug_source = ""
    for line in task_text.splitlines():
        if line.strip().startswith("#"):
            slug_source = line.lstrip("#").strip()
            break
    if not slug_source:
        # fallback: first non-empty line
        for line in task_text.splitlines():
            if line.strip():
                slug_source = line.strip()
                break
    short = slugify(slug_source or "task")
    branch = f"ai/{now:%Y%m%d-%H%M}-{short}"

    # Create and switch to branch.
    run_cmd(["git", "checkout", "-b", branch], cwd=root, check=True)

    prompt_text = _generate_cursor_prompt(task_text, mode="implement")
    written, reason = write_text_safe(paths["cursor_prompt"], prompt_text, force=True)
    _ = written

    print(f"Generated: {paths['cursor_prompt'].relative_to(root)} ({reason})")
    print()
    print("Next step (do NOT run Cursor automatically):")
    print('Open Cursor Agent and send:')
    print('"Read and execute .ai-loop/cursor_prompt.md. After finishing, update .ai-loop/cursor_summary.md."')


def _run_optional_test(root: Path, test_cmd: Optional[str], out_path: Path) -> tuple[bool, Optional[int]]:
    if not test_cmd:
        return (True, None)

    ps_cmd = ["powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", test_cmd]
    cp = run_cmd(ps_cmd, cwd=root, capture=True, check=False)
    combined = ""
    if cp.stdout:
        combined += cp.stdout
    if cp.stderr:
        combined += ("\n" if combined and not combined.endswith("\n") else "") + cp.stderr
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(combined, encoding="utf-8")
    return (cp.returncode == 0, cp.returncode)


def _save_diff_and_summaries(root: Path, paths: dict[str, Path]) -> tuple[str, str, list[str]]:
    status_porcelain = git_status_porcelain(root)
    status_full = run_cmd(["git", "status"], cwd=root, capture=True, check=True).stdout or ""
    diff = git_diff_patch(root)
    staged_diff = git_diff_staged_patch(root)
    untracked = git_untracked_files(root)
    stat = git_diff_stat(root)

    composite = [
        "# git status --porcelain",
        status_porcelain.rstrip(),
        "",
        "# git status",
        status_full.rstrip(),
        "",
        "# git diff",
        diff.rstrip(),
        "",
        "# git diff --staged",
        staged_diff.rstrip(),
        "",
        "# Untracked files",
        "\n".join(untracked) if untracked else "(none)",
        "",
        "# git diff --stat",
        stat.rstrip() or "(no diff stat output)",
        "",
    ]
    paths["last_diff"].parent.mkdir(parents=True, exist_ok=True)
    paths["last_diff"].write_text("\n".join(composite), encoding="utf-8")

    status_short = git_status_short(root)
    paths["git_status"].parent.mkdir(parents=True, exist_ok=True)
    paths["git_status"].write_text(status_short, encoding="utf-8")

    # Print status and diff summary, explicitly including untracked files.
    print(status_full.rstrip())
    if stat.strip():
        print("\nDiff summary:\n" + stat.rstrip())
    else:
        print("\nDiff summary: (no changes)")
    if untracked:
        print("\nUntracked files:")
        for f in untracked:
            print(f"- {f}")
    else:
        print("\nUntracked files: (none)")
    return (status_porcelain, stat, untracked)


def _commit_all(root: Path, message: str) -> None:
    run_cmd(["git", "add", "-A"], cwd=root, check=True)
    # Only commit if there is something staged.
    cp = run_cmd(["git", "diff", "--cached", "--quiet"], cwd=root, check=False)
    if cp.returncode == 0:
        print("Nothing to commit.")
        return
    run_cmd(["git", "commit", "-m", message], cwd=root, check=True)


def cmd_after_cursor(args: argparse.Namespace, *, default_message: str) -> None:
    root = require_git_repo(Path.cwd())
    paths = make_ai_loop_paths(root)

    # Optional tests.
    tests_ok, test_code = _run_optional_test(root, args.test_cmd, paths["test_output"])

    # Save artifacts even when tests fail.
    _save_diff_and_summaries(root, paths)

    if args.commit:
        if not tests_ok:
            print("Skipping commit because tests failed.")
        else:
            msg = args.message or default_message
            _commit_all(root, msg)

    if not tests_ok:
        raise CmdError(
            f"Test command failed ({test_code}). Artifacts were still written: "
            f"{paths['test_output']} and {paths['last_diff']}."
        )


def cmd_open_pr(args: argparse.Namespace) -> None:
    root = require_git_repo(Path.cwd())
    paths = make_ai_loop_paths(root)
    if is_dirty_worktree(root):
        raise CmdError(
            "There are uncommitted changes. Run after-cursor --commit, after-fix --commit, "
            "or safe-commit before open-pr."
        )
    ensure_gh_ready(root)

    # Push current branch (never force).
    ensure_no_force_push_guard(["git", "push", "-u", "origin", "HEAD"])
    run_cmd(["git", "push", "-u", "origin", "HEAD"], cwd=root, check=True)

    task_text = require_file(paths["task"], hint="Run: ai_loop.py init")
    cursor_summary = ""
    if paths["cursor_summary"].exists():
        cursor_summary = read_text(paths["cursor_summary"])
    test_output = ""
    if paths["test_output"].exists():
        test_output = read_text(paths["test_output"])

    body = (
        "## Task\n\n"
        f"{task_text.strip()}\n\n"
        "## Cursor summary\n\n"
        f"{(cursor_summary.strip() or '_No cursor summary yet._')}\n\n"
        "## Test output\n\n"
        "```text\n"
        f"{(test_output.strip() or 'No test output captured.')}\n"
        "```\n"
    )

    paths["pr_body"].parent.mkdir(parents=True, exist_ok=True)
    paths["pr_body"].write_text(body, encoding="utf-8")

    # Detect existing PR for current branch first.
    existing_pr = run_cmd(["gh", "pr", "view", "--json", "url"], cwd=root, capture=True, check=False)
    pr_url = ""
    if existing_pr.returncode == 0:
        data = json.loads(existing_pr.stdout or "{}")
        pr_url = (data.get("url") or "").strip()
        if pr_url:
            print(f"PR already exists for this branch: {pr_url}")
    else:
        title = args.title or "AI: implement task"
        cp2 = run_cmd(
            ["gh", "pr", "create", "--title", title, "--body-file", str(paths["pr_body"])],
            cwd=root,
            capture=True,
            check=True,
        )
        pr_url = (cp2.stdout or "").strip().splitlines()[-1].strip() if (cp2.stdout or "").strip() else ""

    if pr_url:
        paths["pr_url"].write_text(pr_url + "\n", encoding="utf-8")
        print(f"PR URL saved to {paths['pr_url']}")
    else:
        print("PR operation completed, but URL was not captured from gh output.")

    # Default review comment unless opted out.
    review_comment = None if args.no_review_comment else (args.review_comment or "@codex review")
    if review_comment and pr_url:
        run_cmd(["gh", "pr", "comment", pr_url, "--body", review_comment], cwd=root, check=True)


@dataclass
class RepoIdent:
    owner: str
    name: str

    @property
    def name_with_owner(self) -> str:
        return f"{self.owner}/{self.name}"


def _gh_repo_ident(root: Path) -> RepoIdent:
    cp = run_cmd(["gh", "repo", "view", "--json", "nameWithOwner"], cwd=root, capture=True, check=True)
    data = json.loads(cp.stdout or "{}")
    nwo = data.get("nameWithOwner")
    if not nwo or "/" not in nwo:
        raise CmdError("Unable to determine owner/name via gh repo view")
    owner, name = nwo.split("/", 1)
    return RepoIdent(owner=owner, name=name)


def _gh_pr_number(root: Path) -> int:
    cp = run_cmd(["gh", "pr", "view", "--json", "number"], cwd=root, capture=True, check=True)
    data = json.loads(cp.stdout or "{}")
    num = data.get("number")
    if not isinstance(num, int):
        raise CmdError("Unable to determine PR number via gh pr view")
    return num


def cmd_collect_review(args: argparse.Namespace) -> None:
    root = require_git_repo(Path.cwd())
    paths = make_ai_loop_paths(root)
    ensure_gh_ready(root)

    repo = _gh_repo_ident(root)
    try:
        pr_number = _gh_pr_number(root)
    except CmdError as ex:
        raise CmdError("No current PR found for this branch. Run open-pr first.") from ex

    # PR "issue" comments (top-level conversation)
    issue_comments = run_cmd(
        ["gh", "api", f"repos/{repo.name_with_owner}/issues/{pr_number}/comments"],
        cwd=root,
        capture=True,
        check=True,
    ).stdout or "[]"

    # Reviews (including body comments)
    reviews = run_cmd(
        ["gh", "api", f"repos/{repo.name_with_owner}/pulls/{pr_number}/reviews"],
        cwd=root,
        capture=True,
        check=True,
    ).stdout or "[]"

    # Inline review comments
    inline_comments = run_cmd(
        ["gh", "api", f"repos/{repo.name_with_owner}/pulls/{pr_number}/comments"],
        cwd=root,
        capture=True,
        check=True,
    ).stdout or "[]"

    try:
        issue_comments_j = json.loads(issue_comments)
        reviews_j = json.loads(reviews)
        inline_j = json.loads(inline_comments)
    except json.JSONDecodeError as ex:
        raise CmdError(f"Failed to parse gh api JSON: {ex}") from ex

    sections: list[str] = ["# Codex review\n"]
    found_any = False

    def add_comment_block(kind: str, who: str, when: str, body: str, extra: str = "") -> None:
        nonlocal found_any
        found_any = True
        sections.append(f"## {kind}\n")
        sections.append(f"- **Author**: {who}\n- **When**: {when}\n")
        if extra:
            sections.append(extra.rstrip() + "\n")
        sections.append("\n")
        sections.append(body.strip() + "\n\n")

    for c in issue_comments_j if isinstance(issue_comments_j, list) else []:
        body = (c.get("body") or "").strip()
        if not body:
            continue
        add_comment_block(
            "PR comment",
            (c.get("user") or {}).get("login") or "unknown",
            c.get("created_at") or "unknown",
            body,
        )

    for r in reviews_j if isinstance(reviews_j, list) else []:
        body = (r.get("body") or "").strip()
        state = (r.get("state") or "").strip()
        if not body and not state:
            continue
        extra = f"- **State**: {state}\n" if state else ""
        add_comment_block(
            "Review",
            (r.get("user") or {}).get("login") or "unknown",
            r.get("submitted_at") or (r.get("created_at") or "unknown"),
            body or "_(no body)_",
            extra=extra,
        )

    for c in inline_j if isinstance(inline_j, list) else []:
        body = (c.get("body") or "").strip()
        if not body:
            continue
        path = c.get("path") or ""
        line = c.get("line") or c.get("original_line") or ""
        extra = ""
        if path:
            extra += f"- **File**: `{path}`\n"
        if line:
            extra += f"- **Line**: {line}\n"
        add_comment_block(
            "Inline review comment",
            (c.get("user") or {}).get("login") or "unknown",
            c.get("created_at") or "unknown",
            body,
            extra=extra,
        )

    if not found_any:
        out = "No review comments found yet\n"
    else:
        out = "\n".join(sections).rstrip() + "\n"

    paths["codex_review"].parent.mkdir(parents=True, exist_ok=True)
    paths["codex_review"].write_text(out, encoding="utf-8")
    print(f"Wrote {paths['codex_review']}")


def cmd_prepare_fix(args: argparse.Namespace) -> None:
    root = require_git_repo(Path.cwd())
    paths = make_ai_loop_paths(root)

    task_text = require_file(paths["task"], hint="Run: ai_loop.py init")
    review_text = require_file(paths["codex_review"], hint="Run: ai_loop.py collect-review")
    cursor_summary = paths["cursor_summary"].read_text(encoding="utf-8") if paths["cursor_summary"].exists() else ""
    test_output = paths["test_output"].read_text(encoding="utf-8") if paths["test_output"].exists() else ""

    prompt = (
        "# Cursor Agent Instructions (Fix)\n\n"
        "## Objective\n\n"
        "Fix ONLY the issues described in **Codex review** below.\n\n"
        "## Constraints\n\n"
        "- Do not broaden scope beyond review feedback.\n"
        "- Keep changes minimal and targeted.\n"
        "- After finishing, update `.ai-loop/cursor_summary.md` with what you changed.\n\n"
        "## Task\n\n"
        f"{task_text.strip()}\n\n"
        "## Codex review\n\n"
        f"{review_text.strip()}\n\n"
        "## Current Cursor summary (for context)\n\n"
        f"{(cursor_summary.strip() or '_No cursor summary yet._')}\n\n"
        "## Latest test output (for context)\n\n"
        "```text\n"
        f"{(test_output.strip() or 'No test output captured.')}\n"
        "```\n"
    )

    write_text_safe(paths["cursor_prompt"], prompt, force=True)

    msg = "Read and execute .ai-loop/cursor_prompt.md. After finishing, update .ai-loop/cursor_summary.md."
    print("Paste this into Cursor Agent:")
    print(f"\"{msg}\"")


def cmd_status(args: argparse.Namespace) -> None:
    root = require_git_repo(Path.cwd())
    paths = make_ai_loop_paths(root)
    branch = current_branch(root)

    print(f"Directory: {Path.cwd()}")
    print(f"Repo root:  {root}")
    print(f"Branch:     {branch}")
    print()
    run_cmd(["git", "status"], cwd=root, check=True)
    print()

    pr_url = paths["pr_url"].read_text(encoding="utf-8").strip() if paths["pr_url"].exists() else ""
    print(f"PR URL:     {pr_url or '(unknown)'}")
    print()
    keys = [
        paths["task"],
        paths["cursor_prompt"],
        paths["cursor_summary"],
        paths["codex_review"],
        paths["pr_body"],
        paths["test_output"],
        paths["git_status"],
        paths["last_diff"],
        paths["pr_url"],
    ]
    for p in keys:
        rel = p.relative_to(root)
        print(f"{'OK ' if p.exists() else 'MISSING'} {rel}")


def cmd_safe_commit(args: argparse.Namespace) -> None:
    root = require_git_repo(Path.cwd())
    msg = args.message
    if not msg:
        raise CmdError("--message is required for safe-commit")

    run_cmd(["git", "status"], cwd=root, check=True)
    print()
    stat = git_diff_stat(root)
    print("git diff --stat")
    print(stat.rstrip() or "(no changes)")
    print()
    resp = input("Commit ALL changes with this message? [y/N] ").strip().lower()
    if resp != "y":
        print("Cancelled.")
        return
    _commit_all(root, msg)
    print("Committed. (Not pushing automatically.)")


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(prog="ai_loop.py", description="GitHub PR orchestrator for AI coding loops")
    sub = p.add_subparsers(dest="cmd", required=True)

    sp = sub.add_parser("init", help="Initialize ai-loop files in the current repo")
    sp.add_argument("--force", action="store_true", help="Overwrite existing non-empty scaffold files")
    sp.set_defaults(_fn=cmd_init)

    sp = sub.add_parser("create-github", help="Create GitHub repo via gh and push current branch")
    sp.add_argument("--name", help="Repo name (optional)")
    sp.add_argument("--public", action="store_true", help="Create as public")
    sp.add_argument("--private", action="store_true", help="Create as private (default)")
    sp.set_defaults(_fn=cmd_create_github)

    sp = sub.add_parser("start", help="Create ai/* branch and generate Cursor prompt")
    sp.set_defaults(_fn=cmd_start)

    sp = sub.add_parser("after-cursor", help="Run after Cursor implements the task")
    sp.add_argument("--test-cmd", help="Optional test command to run in PowerShell")
    sp.add_argument("--commit", action="store_true", help="Commit all changes after saving outputs")
    sp.add_argument("--message", help="Commit message (default: AI: implement task)")
    sp.set_defaults(_fn=lambda a: cmd_after_cursor(a, default_message="AI: implement task"))

    sp = sub.add_parser("open-pr", help="Push branch, generate PR body, create PR via gh")
    sp.add_argument("--title", help="PR title")
    rc_group = sp.add_mutually_exclusive_group()
    rc_group.add_argument("--no-review-comment", action="store_true", help="Do not post the default review comment")
    rc_group.add_argument("--review-comment", help="Custom PR review comment (default is @codex review)")
    sp.set_defaults(_fn=cmd_open_pr)

    sp = sub.add_parser("collect-review", help="Collect PR comments/reviews and write codex_review.md")
    sp.set_defaults(_fn=cmd_collect_review)

    sp = sub.add_parser("prepare-fix", help="Generate Cursor prompt to fix Codex review issues")
    sp.set_defaults(_fn=cmd_prepare_fix)

    sp = sub.add_parser("after-fix", help="Run after Cursor applies review fixes")
    sp.add_argument("--test-cmd", help="Optional test command to run in PowerShell")
    sp.add_argument("--commit", action="store_true", help="Commit all changes after saving outputs")
    sp.add_argument("--message", help="Commit message (default: AI: address review comments)")
    sp.set_defaults(_fn=lambda a: cmd_after_cursor(a, default_message="AI: address review comments"))

    sp = sub.add_parser("status", help="Show current state of the ai-loop run")
    sp.set_defaults(_fn=cmd_status)

    sp = sub.add_parser("safe-commit", help="Interactive confirm + commit all changes (never pushes)")
    sp.add_argument("--message", required=True, help="Commit message")
    sp.set_defaults(_fn=cmd_safe_commit)

    return p


def main(argv: list[str]) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        args._fn(args)
        return 0
    except CmdError as ex:
        eprint(f"ERROR: {ex}")
        return 2
    except KeyboardInterrupt:
        eprint("Cancelled.")
        return 130


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))

