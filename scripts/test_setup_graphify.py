#!/usr/bin/env python3
"""Regression tests for setup_graphify_apx.py using scratch-only fixtures."""

from __future__ import annotations

import importlib.util
import os
import shutil
import sys
import tempfile
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parent.parent
MODULE_PATH = REPO_ROOT / "setup_graphify_apx.py"
sys.dont_write_bytecode = True
SPEC = importlib.util.spec_from_file_location("setup_graphify_apx", MODULE_PATH)
assert SPEC and SPEC.loader
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class GraphifyPatchTests(unittest.TestCase):
    def setUp(self) -> None:
        scratch = REPO_ROOT / "scratch"
        scratch.mkdir(exist_ok=True)
        self.root = Path(tempfile.mkdtemp(prefix="graphify-test.", dir=scratch))

    def tearDown(self) -> None:
        shutil.rmtree(self.root)

    def test_missing_required_module_fails(self) -> None:
        (self.root / "detect.py").write_text("EXTENSIONS = {'.sql',}\n", encoding="utf-8")
        self.assertFalse(MODULE.patch_graphify_dir(self.root))

    def test_partial_extract_mapping_is_completed(self) -> None:
        (self.root / "detect.py").write_text("EXTENSIONS = {'.sql',}\n", encoding="utf-8")
        (self.root / "extract.py").write_text(
            'EXTRACTORS = {".sql": extract_sql, ".apx": extract_sql,}\n'
            'LANGUAGES = {".sql": "sql",}\n',
            encoding="utf-8",
        )
        self.assertTrue(MODULE.patch_graphify_dir(self.root))
        extract = (self.root / "extract.py").read_text(encoding="utf-8")
        self.assertIn('".apx": "sql",', extract)


if __name__ == "__main__":
    unittest.main()
