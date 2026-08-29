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

    def write_package(self) -> None:
        (self.root / "extractors").mkdir()
        (self.root / "detect.py").write_text(
            "CODE_EXTENSIONS = {'.sql',}\n",
            encoding="utf-8",
        )
        (self.root / "extract.py").write_text(
            "from graphify.extractors.sql import extract_sql  # noqa: F401\n"
            '_DISPATCH = {\n    ".sql": extract_sql,\n}\n'
            '_EXTRA_FOR_EXTENSION = {\n    ".sql": "sql",\n}\n',
            encoding="utf-8",
        )

    def test_missing_required_module_fails(self) -> None:
        (self.root / "detect.py").write_text("EXTENSIONS = {'.sql',}\n", encoding="utf-8")
        self.assertFalse(MODULE.patch_graphify_dir(self.root))

    def test_installs_canonical_extractor_and_routes_apx_to_it(self) -> None:
        self.write_package()

        self.assertTrue(MODULE.patch_graphify_dir(self.root))

        installed = self.root / "extractors" / "apexlang.py"
        canonical = REPO_ROOT / "scripts" / "graphify_apexlang_extractor.py"
        self.assertEqual(installed.read_bytes(), canonical.read_bytes())
        extract = (self.root / "extract.py").read_text(encoding="utf-8")
        detect = (self.root / "detect.py").read_text(encoding="utf-8")
        self.assertIn("from graphify.extractors.apexlang import extract_apexlang", extract)
        self.assertIn('".apx": extract_apexlang,', extract)
        self.assertNotIn('".apx": extract_sql,', extract)
        self.assertIn("'.apx'", detect)

    def test_repeated_install_is_byte_for_byte_idempotent(self) -> None:
        self.write_package()
        self.assertTrue(MODULE.patch_graphify_dir(self.root))
        paths = [
            self.root / "detect.py",
            self.root / "extract.py",
            self.root / "extractors" / "apexlang.py",
        ]
        first = {path: path.read_bytes() for path in paths}

        self.assertTrue(MODULE.patch_graphify_dir(self.root))
        self.assertEqual(first, {path: path.read_bytes() for path in paths})

    def test_repairs_outdated_installed_extractor(self) -> None:
        self.write_package()
        self.assertTrue(MODULE.patch_graphify_dir(self.root))
        installed = self.root / "extractors" / "apexlang.py"
        installed.write_text("# stale extractor\n", encoding="utf-8")

        self.assertTrue(MODULE.patch_graphify_dir(self.root))
        canonical = REPO_ROOT / "scripts" / "graphify_apexlang_extractor.py"
        self.assertEqual(installed.read_bytes(), canonical.read_bytes())

    def test_incompatible_dispatch_fails_without_partial_install(self) -> None:
        (self.root / "extractors").mkdir()
        (self.root / "detect.py").write_text("CODE_EXTENSIONS = {'.sql',}\n", encoding="utf-8")
        (self.root / "extract.py").write_text("DISPATCH_CHANGED = {}\n", encoding="utf-8")
        before = (self.root / "detect.py").read_bytes()

        self.assertFalse(MODULE.patch_graphify_dir(self.root))
        self.assertEqual((self.root / "detect.py").read_bytes(), before)
        self.assertFalse((self.root / "extractors" / "apexlang.py").exists())

    def test_replaces_legacy_apx_sql_route(self) -> None:
        self.write_package()
        extract_path = self.root / "extract.py"
        extract_path.write_text(
            extract_path.read_text(encoding="utf-8").replace(
                '".sql": extract_sql,',
                '".sql": extract_sql,\n    ".apx": extract_sql,',
            ),
            encoding="utf-8",
        )

        self.assertTrue(MODULE.patch_graphify_dir(self.root))
        extract = extract_path.read_text(encoding="utf-8")
        self.assertIn('".apx": extract_apexlang,', extract)
        self.assertNotIn('".apx": extract_sql,', extract)

    def test_exposes_apx_cache_invalidation(self) -> None:
        self.assertTrue(
            hasattr(MODULE, "invalidate_apx_cache"),
            "invalidate_apx_cache(cache_root) is missing",
        )

    def test_invalidates_only_cached_apx_extractions(self) -> None:
        cache_root = self.root / "cache" / "ast" / "v0.9.35"
        cache_root.mkdir(parents=True)
        apx_cache = cache_root / "apx.json"
        sql_cache = cache_root / "sql.json"
        apx_cache.write_text(
            '{"nodes":[{"source_file":"apps/DEMO/102/pages/p00004-home.apx"}],"edges":[]}',
            encoding="utf-8",
        )
        sql_cache.write_text(
            '{"nodes":[{"source_file":"database/DEMO/tables/ORDERS.sql"}],"edges":[]}',
            encoding="utf-8",
        )

        removed = MODULE.invalidate_apx_cache(self.root / "cache" / "ast")

        self.assertEqual(removed, 1)
        self.assertFalse(apx_cache.exists())
        self.assertTrue(sql_cache.exists())


if __name__ == "__main__":
    unittest.main()
