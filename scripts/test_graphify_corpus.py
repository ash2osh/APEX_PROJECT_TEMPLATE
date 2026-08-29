#!/usr/bin/env python3
"""Verify the Graphify corpus remains limited to APEX domain sources."""

from __future__ import annotations

import json
import shutil
import subprocess
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parent.parent
IGNORE_PATH = REPO_ROOT / ".graphifyignore"

INCLUDED_PATHS = (
    "apps/DEMO/102/pages/p00004-home.apx",
    "apps/DEMO/102/shared-components/lists.apx",
    "database/DEMO/tables/SAMPLE_RESTAURANT.sql",
    "app_context/102/context.md",
)

EXCLUDED_PATHS = (
    ".agents/skills/superpowers/brainstorming/scripts/server.cjs",
    ".claude/skills/example/SKILL.md",
    "scripts/backup_db.sh",
    "setup_graphify_apx.py",
    "README.md",
    "ai_generate/2026-08-29/change.sql",
    "scratch/helper.sql",
    "graphify-out/graph.json",
    "apps/.gitkeep",
    "database/.gitkeep",
    "database/DEMO/manifest-code.txt",
    "database/DEMO/manifest-tables.txt",
    "app_context/README.md",
    "apps/DEMO/102/.apex/apexlang.json",
    "apps/DEMO/102/deployments/default.json",
    "apps/DEMO/102/workspace-components/app-groups/sample-applications.apx",
    "apps/DEMO/102/shared-components/static-files.apx",
    "apps/DEMO/102/shared-components/static-files/logo.png",
    "apps/DEMO/102/shared-components/themes/universal-theme/static-files/theme.css",
)


def graphify_python() -> Path | None:
    executable = shutil.which("graphify")
    if not executable:
        return None
    launcher = Path(executable).resolve()
    try:
        first_line = launcher.read_text(encoding="utf-8").splitlines()[0]
    except (OSError, UnicodeError, IndexError):
        return None
    if not first_line.startswith("#!"):
        return None
    interpreter = Path(first_line[2:].strip())
    return interpreter if interpreter.is_file() else None


class GraphifyCorpusTests(unittest.TestCase):
    def test_ignore_file_is_a_domain_allowlist(self) -> None:
        lines = {
            line.strip()
            for line in IGNORE_PATH.read_text(encoding="utf-8").splitlines()
            if line.strip() and not line.lstrip().startswith("#")
        }
        required = {
            "/*",
            "!/apps/",
            "!/database/",
            "!/app_context/",
            "/apps/**/.apex/",
            "/apps/**/deployments/",
            "/apps/**/workspace-components/",
            "/apps/**/static-files.apx",
            "/apps/**/static-files/",
            "/apps/.gitkeep",
            "/database/.gitkeep",
            "/database/**/manifest-code.txt",
            "/database/**/manifest-tables.txt",
            "/app_context/README.md",
        }
        self.assertTrue(required.issubset(lines), sorted(required - lines))
        self.assertNotIn("!/ai_generate/", lines)

    def test_graphify_matcher_includes_only_domain_sources(self) -> None:
        interpreter = graphify_python()
        if interpreter is None:
            self.skipTest("Graphify Python launcher is unavailable")
        script = r'''
import json
import sys
from pathlib import Path
from graphify.detect import _is_ignored, _load_graphifyignore

root = Path(sys.argv[1]).resolve()
paths = json.loads(sys.argv[2])
patterns = _load_graphifyignore(root)
print(json.dumps({path: _is_ignored(root / path, root, patterns) for path in paths}))
'''
        paths = list(INCLUDED_PATHS + EXCLUDED_PATHS)
        completed = subprocess.run(
            [str(interpreter), "-c", script, str(REPO_ROOT), json.dumps(paths)],
            check=True,
            text=True,
            capture_output=True,
        )
        ignored = json.loads(completed.stdout)
        self.assertEqual(
            [path for path in INCLUDED_PATHS if ignored[path]],
            [],
            "approved domain sources were ignored",
        )
        self.assertEqual(
            [path for path in EXCLUDED_PATHS if not ignored[path]],
            [],
            "non-domain sources were included",
        )

    def test_documentation_exposes_persistent_domain_graph_workflow(self) -> None:
        rules = (REPO_ROOT / ".agents" / "rules" / "graphify.md").read_text(encoding="utf-8")
        workflow = (REPO_ROOT / ".agents" / "workflows" / "graphify.md").read_text(
            encoding="utf-8"
        )
        agents = (REPO_ROOT / "AGENTS.md").read_text(encoding="utf-8")
        readme = (REPO_ROOT / "README.md").read_text(encoding="utf-8")
        combined = "\n".join((rules, workflow, agents, readme))

        for command in (
            "python3 setup_graphify_apx.py",
            "graphify extract . --force",
            "graphify update .",
        ):
            self.assertIn(command, combined)
        for phrase in ("app_context", "Graphify upgrade", "domain"):
            self.assertIn(phrase, combined)
        self.assertNotIn("--force --code-only", combined)
        self.assertNotIn('".apx": extract_sql', combined)

        self.assertIn("graphify extract . --force", workflow)
        self.assertIn("app_context", workflow)
        self.assertIn("Graphify upgrade", workflow)
        self.assertIn("python3 setup_graphify_apx.py", readme)


if __name__ == "__main__":
    unittest.main()
