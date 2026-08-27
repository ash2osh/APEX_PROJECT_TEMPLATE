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

def setup_graphify_apx():
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
        return

    for base in g_dirs:
        d = os.path.join(base, "detect.py")
        e = os.path.join(base, "extract.py")
        patched_ok = True

        if os.path.exists(d):
            with open(d, "r") as f:
                content = f.read()
            if "'.apx'" not in content:
                patched = content.replace("'.sql',", "'.sql', '.apx',")
                if patched == content:
                    print(f"Warning: could not patch {d} — expected \"'.sql',\" pattern not found; .apx files will not be detected as code")
                    patched_ok = False
                else:
                    with open(d, "w") as f:
                        f.write(patched)

        if os.path.exists(e):
            with open(e, "r") as f:
                content = f.read()
            if '".apx":' not in content:
                patched = content.replace('".sql": extract_sql,', '".sql": extract_sql,\n    ".apx": extract_sql,')
                if patched == content:
                    print(f"Warning: could not patch {e} — expected '\".sql\": extract_sql,' pattern not found")
                    patched_ok = False
                patched2 = patched.replace('".sql": "sql",', '".sql": "sql",\n    ".apx": "sql",')
                if patched2 == patched:
                    print(f"Warning: could not patch {e} — expected '\".sql\": \"sql\",' pattern not found")
                    patched_ok = False
                if patched2 != content:
                    with open(e, "w") as f:
                        f.write(patched2)

        if patched_ok:
            print(f"✅ Graphify at '{base}' successfully configured for SQL & .apx support!")
        else:
            print(f"⚠️  Graphify at '{base}' was only partially configured — see warnings above; .apx support may not work until this script is updated for the installed Graphify version.")

if __name__ == "__main__":
    setup_graphify_apx()
