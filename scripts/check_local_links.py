#!/usr/bin/env python3
"""Check Markdown links that resolve to files or directories in this repo."""

from __future__ import annotations

import re
import sys
from pathlib import Path
from urllib.parse import unquote


LINK_RE = re.compile(r"(?<!!)\[[^\]]*\]\(([^)]+)\)")


def markdown_files(paths: list[Path]):
    for path in paths:
        if path.is_dir():
            yield from sorted(path.rglob("*.md"))
        elif path.is_file() and path.suffix.lower() == ".md":
            yield path
        else:
            raise ValueError(f"not a Markdown file or directory: {path}")


def missing_links(files):
    for source in files:
        text = source.read_text(encoding="utf-8")
        for match in LINK_RE.finditer(text):
            target = match.group(1).strip()
            if target.startswith("<") and target.endswith(">"):
                target = target[1:-1]
            if not target or target.startswith("#") or "://" in target or target.startswith("mailto:"):
                continue
            target = unquote(target.split("#", 1)[0])
            if not target:
                continue
            resolved = (source.parent / target).resolve()
            if not resolved.exists():
                line = text.count("\n", 0, match.start()) + 1
                yield source, line, target


def main(argv: list[str]) -> int:
    if not argv:
        print("usage: check_local_links.py <markdown-file-or-directory> [...]", file=sys.stderr)
        return 2
    try:
        files = markdown_files([Path(arg) for arg in argv])
        errors = list(missing_links(files))
    except (OSError, ValueError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2
    for source, line, target in errors:
        print(f"{source}:{line}: missing local link: {target}", file=sys.stderr)
    if errors:
        print(f"{len(errors)} broken local link(s)", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
