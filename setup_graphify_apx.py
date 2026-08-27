#!/usr/bin/env python3
"""
Ensures tree-sitter-sql is installed and patches the local Graphify package
to natively recognize .apx (Oracle APEX export) files as AST code files.
"""
import glob
import os
from pathlib import Path
import shutil
import subprocess
import sys

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

    return list(set(dirs))

def patch_graphify_dir(base: Path) -> bool:
    """Patch one Graphify package, returning false unless support is complete."""
    detect_path = base / "detect.py"
    extract_path = base / "extract.py"
    missing = [path for path in (detect_path, extract_path) if not path.is_file()]
    if missing:
        print(f"Warning: Graphify at '{base}' is missing required module(s): "
              + ", ".join(path.name for path in missing))
        return False

    detect = detect_path.read_text(encoding="utf-8")
    extract = extract_path.read_text(encoding="utf-8")
    patched_detect = detect
    patched_extract = extract

    if "'.apx'" not in patched_detect:
        patched_detect = patched_detect.replace("'.sql',", "'.sql', '.apx',", 1)
        if patched_detect == detect:
            print(f"Warning: could not patch {detect_path}; expected \"'.sql',\" pattern not found")
            return False

    if '".apx": extract_sql,' not in patched_extract:
        before = patched_extract
        patched_extract = patched_extract.replace(
            '".sql": extract_sql,',
            '".sql": extract_sql,\n    ".apx": extract_sql,',
            1,
        )
        if patched_extract == before:
            print(f"Warning: could not patch {extract_path}; SQL extractor mapping not found")
            return False

    if '".apx": "sql",' not in patched_extract:
        before = patched_extract
        patched_extract = patched_extract.replace(
            '".sql": "sql",',
            '".sql": "sql",\n    ".apx": "sql",',
            1,
        )
        if patched_extract == before:
            print(f"Warning: could not patch {extract_path}; SQL language mapping not found")
            return False

    # Do not leave a package partially patched because one later pattern failed.
    if patched_detect != detect:
        detect_path.write_text(patched_detect, encoding="utf-8")
    if patched_extract != extract:
        extract_path.write_text(patched_extract, encoding="utf-8")
    print(f"Graphify at '{base}' is configured for SQL and .apx support")
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
    return all(results)

if __name__ == "__main__":
    raise SystemExit(0 if setup_graphify_apx() else 1)
