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
