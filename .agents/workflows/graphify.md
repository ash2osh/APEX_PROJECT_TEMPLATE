---
name: graphify
description: Turn any folder of files into a navigable knowledge graph
---

# Workflow: graphify

Use the graphify skill exposed by the current agent client when available. If
the client does not expose that skill, use the repository's `setup_graphify_apx.py`
and `graphify` CLI commands directly; do not assume a provider-specific home
directory or invent an unavailable tool.

Before extraction, review `.graphifyignore`: exclude generated aggregates,
release snapshots, logs, scratch output, and static/BLOB payload exports when
canonical source exists elsewhere. Retain canonical source, tests, and small
deployment or `_run_all.sql` orchestration scripts.

If no path argument is given, use `.`. When `graphify-out/graph.json` exists,
run `graphify update <path>` after modifying code. Otherwise run
`python3 setup_graphify_apx.py`, followed by
`graphify extract <path> --force --code-only`.
After changing `.graphifyignore`, rebuild with `graphify update <path> --force`
and verify excluded paths are absent while retained source remains queryable.

`setup_graphify_apx.py` works by patching `.apx` support directly into the
installed `graphify` package's `detect.py`/`extract.py` files, not through a
supported extension point. Re-run it after every `graphify` upgrade — a new
version can change those files' internals enough that the patch strings no
longer match, silently dropping `.apx` support until the script is updated
for the new version. The script now warns (rather than falsely reporting
success) when a patch string isn't found; treat that warning as a signal
that the patching logic needs updating for the installed `graphify` version.
