#!/usr/bin/env python3
"""
Ensures tree-sitter-sql is installed and patches the local Graphify package
to natively recognize .apx (Oracle APEX export) files as AST code files.
"""
import os, glob, subprocess, sys, shutil

def find_graphify_dirs():
    dirs = []
    # 1. Try importing graphify in current python
    try:
        import graphify
        dirs.append(os.path.dirname(graphify.__file__))
    except Exception:
        pass

    # 2. Search common uv / virtualenv locations
    user_home = os.path.expanduser("~")
    uv_paths = glob.glob(os.path.join(user_home, ".local/share/uv/tools/graphify*/lib/python*/site-packages/graphify"))
    dirs.extend(uv_paths)

    pip_paths = glob.glob(os.path.join(user_home, ".local/lib/python*/site-packages/graphify"))
    dirs.extend(pip_paths)

    return list(set(dirs))

def setup_graphify_apx():
    print("Checking Graphify & tree-sitter-sql setup...")

    # Attempt uv pip install first
    graphify_bin = shutil.which("graphify")
    if graphify_bin and os.path.exists(graphify_bin):
        with open(graphify_bin, "r") as f:
            first_line = f.readline()
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
        print("Warning: Graphify installation not found. Please install Graphify first (e.g. uv tool install graphifyy).")
        return

    for base in g_dirs:
        d = os.path.join(base, "detect.py")
        e = os.path.join(base, "extract.py")

        if os.path.exists(d):
            with open(d, "r") as f:
                content = f.read()
            if "'.apx'" not in content:
                content = content.replace("'.sql',", "'.sql', '.apx',")
                with open(d, "w") as f:
                    f.write(content)

        if os.path.exists(e):
            with open(e, "r") as f:
                content = f.read()
            if '".apx":' not in content:
                content = content.replace('".sql": extract_sql,', '".sql": extract_sql,\n    ".apx": extract_sql,').replace('".sql": "sql",', '".sql": "sql",\n    ".apx": "sql",')
                with open(e, "w") as f:
                    f.write(content)

        print(f"✅ Graphify at '{base}' successfully configured for SQL & .apx support!")

if __name__ == "__main__":
    setup_graphify_apx()
