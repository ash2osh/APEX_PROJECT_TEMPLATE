#!/usr/bin/env python3
"""
Ensures tree-sitter-sql is installed and patches the local Graphify package
to natively recognize .apx (Oracle APEX export) files as AST code files.
"""
import glob
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile


REPO_ROOT = Path(__file__).resolve().parent
CANONICAL_EXTRACTOR = REPO_ROOT / "scripts" / "graphify_apexlang_extractor.py"
# The exact text this installer writes; the only proof that .apx is ours.
DETECT_MARKER = "'.sql', '.apx',"

def find_graphify_dirs():
    dirs = []
    # 1. Try importing graphify in current python
    try:
        import graphify
        dirs.append(os.path.dirname(graphify.__file__))
    except Exception:
        pass

    # 2. Search common uv / virtualenv locations (Linux/macOS)
    user_home = os.path.expanduser("~")
    uv_paths = glob.glob(os.path.join(user_home, ".local/share/uv/tools/graphify*/lib/python*/site-packages/graphify"))
    dirs.extend(uv_paths)

    pip_paths = glob.glob(os.path.join(user_home, ".local/lib/python*/site-packages/graphify"))
    dirs.extend(pip_paths)

    # 3. Search common uv / pip user-install locations (Windows)
    appdata = os.environ.get("APPDATA")
    localappdata = os.environ.get("LOCALAPPDATA")
    if appdata:
        dirs.extend(glob.glob(os.path.join(appdata, "uv", "tools", "graphify*", "Lib", "site-packages", "graphify")))
        dirs.extend(glob.glob(os.path.join(appdata, "Python", "Python3*", "site-packages", "graphify")))
    if localappdata:
        dirs.extend(glob.glob(os.path.join(localappdata, "uv", "tools", "graphify*", "Lib", "site-packages", "graphify")))

    return sorted(set(dirs))


def _patched_detector(text: str) -> tuple[str | None, str]:
    """Register .apx beside .sql, failing closed on unrecognized handling.

    A bare ".apx" presence check is not proof of our patch: a future Graphify
    could mention the extension for its own reasons and we would report
    success without having registered anything.
    """
    if DETECT_MARKER in text:
        return text, "already registered"
    if "'.apx'" in text or '".apx"' in text:
        return None, "unrecognized pre-existing .apx handling; refusing to patch"
    anchor = "'.sql',"
    if anchor not in text:
        return None, "SQL extension anchor not found"
    return text.replace(anchor, DETECT_MARKER, 1), "registered"


def _patched_dispatch(text: str) -> str | None:
    import_line = "from graphify.extractors.apexlang import extract_apexlang  # noqa: F401"
    if import_line not in text:
        sql_import = "from graphify.extractors.sql import extract_sql  # noqa: F401"
        if sql_import not in text:
            return None
        text = text.replace(sql_import, f"{sql_import}\n{import_line}", 1)

    if '".apx": extract_sql,' in text:
        text = text.replace('".apx": extract_sql,', '".apx": extract_apexlang,', 1)
    elif '".apx": extract_apexlang,' not in text:
        sql_route = '".sql": extract_sql,'
        if sql_route not in text:
            return None
        text = text.replace(
            sql_route,
            f'{sql_route}\n    ".apx": extract_apexlang,',
            1,
        )

    # The project-owned APEXlang parser is standard-library-only. A legacy
    # setup mapped .apx to the optional SQL dependency; remove that false gate.
    text = text.replace('    ".apx": "sql",\n', "")
    return text


def _smoke_test_extractor(extractor_path: Path) -> tuple[bool, str]:
    scratch = REPO_ROOT / "scratch"
    scratch.mkdir(exist_ok=True)
    smoke_root = Path(tempfile.mkdtemp(prefix="graphify-apexlang-smoke.", dir=scratch))
    module_name = f"graphify_apexlang_smoke_{os.getpid()}_{id(extractor_path)}"
    try:
        fixture = smoke_root / "apps" / "DEMO" / "102" / "pages" / "p00004-home.apx"
        fixture.parent.mkdir(parents=True)
        fixture.write_text(
            "page 4 (\n"
            "    name: Home\n"
            "    region orders (\n"
            "        source {\n"
            "            sqlQuery: select id from sample_restaurant_orders\n"
            "        }\n"
            "    )\n"
            ")\n",
            encoding="utf-8",
        )
        spec = importlib.util.spec_from_file_location(module_name, extractor_path)
        if spec is None or spec.loader is None:
            return False, "could not create an import specification"
        module = importlib.util.module_from_spec(spec)
        sys.modules[module_name] = module
        spec.loader.exec_module(module)
        result = module.extract_apexlang(fixture)
        if result.get("error"):
            return False, f"smoke extraction failed: {result['error']}"
        relations = {edge.get("relation") for edge in result.get("edges", [])}
        if not {"contains", "reads_from"}.issubset(relations):
            return False, "smoke extraction did not emit containment and database edges"
        return True, "ok"
    except Exception as exc:
        return False, f"smoke extraction raised {type(exc).__name__}: {exc}"
    finally:
        sys.modules.pop(module_name, None)
        shutil.rmtree(smoke_root, ignore_errors=True)


def verify_installation(base: Path) -> tuple[bool, str]:
    installed = base / "extractors" / "apexlang.py"
    detect_path = base / "detect.py"
    extract_path = base / "extract.py"
    if not installed.is_file():
        return False, "installed extractor is missing"
    if installed.read_bytes() != CANONICAL_EXTRACTOR.read_bytes():
        return False, "installed extractor differs from canonical source"
    detect = detect_path.read_text(encoding="utf-8")
    extract = extract_path.read_text(encoding="utf-8")
    if DETECT_MARKER not in detect:
        return False, ".apx is not registered beside .sql as a code extension"
    if "from graphify.extractors.apexlang import extract_apexlang" not in extract:
        return False, "APEXlang extractor import is missing"
    if '".apx": extract_apexlang,' not in extract:
        return False, ".apx is not routed to extract_apexlang"
    if '".apx": extract_sql,' in extract:
        return False, "legacy .apx SQL route is still present"
    return _smoke_test_extractor(installed)


def invalidate_apx_cache(cache_root: Path) -> int:
    """Remove only AST cache records produced from .apx source files."""
    if not cache_root.is_dir():
        return 0
    removed = 0
    for cache_file in cache_root.rglob("*.json"):
        try:
            payload = json.loads(cache_file.read_text(encoding="utf-8"))
        except (OSError, UnicodeError, json.JSONDecodeError):
            continue
        source_files = {
            str(node.get("source_file", ""))
            for node in payload.get("nodes", [])
            if isinstance(node, dict)
        }
        if any(source.casefold().endswith(".apx") for source in source_files):
            try:
                cache_file.unlink()
                removed += 1
            except OSError as exc:
                print(f"Warning: could not invalidate APEXlang cache '{cache_file}': {exc}")
    return removed

def patch_graphify_dir(base: Path) -> bool:
    """Install APEXlang support into one Graphify package, failing closed."""
    detect_path = base / "detect.py"
    extract_path = base / "extract.py"
    extractor_dir = base / "extractors"
    installed_path = extractor_dir / "apexlang.py"
    missing = [
        path
        for path in (CANONICAL_EXTRACTOR, detect_path, extract_path, extractor_dir)
        if not (path.is_dir() if path == extractor_dir else path.is_file())
    ]
    if missing:
        print(f"Warning: Graphify at '{base}' is missing required module(s): "
              + ", ".join(path.name for path in missing))
        return False

    detect_bytes = detect_path.read_bytes()
    extract_bytes = extract_path.read_bytes()
    old_installed = installed_path.read_bytes() if installed_path.exists() else None
    try:
        patched_detect, detect_reason = _patched_detector(detect_bytes.decode("utf-8"))
        patched_extract = _patched_dispatch(extract_bytes.decode("utf-8"))
    except UnicodeError as exc:
        print(f"Warning: could not decode Graphify package at '{base}': {exc}")
        return False
    if patched_detect is None:
        print(f"Warning: could not patch {detect_path}; {detect_reason}")
        return False
    if patched_extract is None:
        print(f"Warning: could not patch {extract_path}; extractor routing anchors not found")
        return False

    try:
        detect_path.write_text(patched_detect, encoding="utf-8")
        extract_path.write_text(patched_extract, encoding="utf-8")
        shutil.copyfile(CANONICAL_EXTRACTOR, installed_path)
        verified, reason = verify_installation(base)
        if not verified:
            raise RuntimeError(reason)
    except Exception as exc:
        try:
            detect_path.write_bytes(detect_bytes)
            extract_path.write_bytes(extract_bytes)
            if old_installed is None:
                installed_path.unlink(missing_ok=True)
            else:
                installed_path.write_bytes(old_installed)
        except OSError as rollback_exc:
            print(f"Warning: rollback failed for Graphify at '{base}': {rollback_exc}")
        print(f"Warning: Graphify APEXlang setup failed at '{base}': {exc}")
        return False

    print(f"Graphify at '{base}' is configured with the project APEXlang extractor")
    return True


def setup_graphify_apx() -> bool:
    print("Checking Graphify & tree-sitter-sql setup...")

    # Attempt uv pip install first
    graphify_bin = shutil.which("graphify")
    if graphify_bin and os.path.exists(graphify_bin):
        try:
            with open(graphify_bin, "r") as f:
                first_line = f.readline()
        except (UnicodeDecodeError, OSError):
            # Windows pip/uv console-script shims are compiled .exe launchers,
            # not shebang scripts — nothing to sniff, just skip this step.
            first_line = ""
        if first_line.startswith("#!"):
            py_path = first_line.strip()[2:]
            if os.path.exists(py_path):
                subprocess.run([py_path, "-m", "pip", "install", "tree-sitter-sql"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                try:
                    subprocess.run(["uv", "pip", "install", "--python", py_path, "tree-sitter-sql"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                except Exception:
                    pass

    g_dirs = find_graphify_dirs()
    if not g_dirs:
        print("Warning: Graphify installation not found. Please install Graphify first (e.g. uv tool install graphify).")
        return False

    results = [patch_graphify_dir(Path(base)) for base in g_dirs]
    if not all(results):
        return False
    removed = invalidate_apx_cache(REPO_ROOT / "graphify-out" / "cache" / "ast")
    if removed:
        print(f"Invalidated {removed} stale APEXlang AST cache entr{'y' if removed == 1 else 'ies'}")
    return True

if __name__ == "__main__":
    raise SystemExit(0 if setup_graphify_apx() else 1)
