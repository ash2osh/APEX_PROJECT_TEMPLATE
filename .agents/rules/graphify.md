---
trigger: always_on
description: Consult the graphify knowledge graph at graphify-out/ for codebase and architecture questions.
---

## graphify

This project can use a graphify knowledge graph at graphify-out/, if the
`graphify` CLI is installed (https://github.com/ash2osh — see `agents.md`
"Optional Tooling"). It is not guaranteed to be present; if `graphify-out/`
does not exist, none of the rules below apply — fall back to normal
file reads and grep.

Setup on new machines / devices:
- Run `python3 setup_graphify_apx.py` to ensure `tree-sitter-sql` is installed and `.apx` AST support is registered in Graphify.

Rules:
- For codebase or architecture questions, when `graphify-out/graph.json` exists, first run `graphify query "<question>"` (CLI) or `query_graph` (MCP). Use `graphify path "<A>" "<B>"` / `shortest_path` for relationships and `graphify explain "<concept>"` / `get_node` for focused concepts. These return a scoped subgraph, usually much smaller than `GRAPH_REPORT.md` or raw grep output.
- If graphify-out/wiki/index.md exists, navigate it instead of reading raw files
- Read graphify-out/GRAPH_REPORT.md only for broad architecture review or when query/path/explain do not surface enough context
- Before extracting or updating, review `.graphifyignore`. Exclude generated full-schema aggregates, release snapshots, logs, scratch output, and embedded static/BLOB exports only when canonical source exists elsewhere. Keep canonical source, tests, and small deployment or `_run_all.sql` orchestration scripts.
- After modifying code files in this session, run `graphify update .` to keep the graph current (AST-only, no API cost)
- After changing `.graphifyignore`, run `graphify update . --force`, then verify ignored paths are absent and retained source paths are still queryable.
