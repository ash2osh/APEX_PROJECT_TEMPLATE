---
trigger: always_on
description: Consult the domain-focused graphify knowledge graph for APEX application, database, and context questions.
---

## graphify

This project can use a domain-focused graphify knowledge graph at graphify-out/, if the
`graphify` CLI is installed (https://github.com/ash2osh — see `AGENTS.md`
"Optional Tooling"). It is not guaranteed to be present; if `graphify-out/`
does not exist, none of the rules below apply — fall back to normal
file reads and grep.

Setup on new machines / devices:
- Run `python3 setup_graphify_apx.py` to install the repository-owned APEXlang extractor into Graphify and verify it with a smoke extraction.
- Configure a supported semantic backend, then run `graphify extract . --force`. The initial full extraction is required so `app_context/*.md` is indexed; do not use `--code-only`.

Rules:
- For codebase or architecture questions, when `graphify-out/graph.json` exists, first run `graphify query "<question>"` (CLI) or `query_graph` (MCP). Use `graphify path "<A>" "<B>"` / `shortest_path` for relationships and `graphify explain "<concept>"` / `get_node` for focused concepts. These return a scoped subgraph, usually much smaller than `GRAPH_REPORT.md` or raw grep output.
- If graphify-out/wiki/index.md exists, navigate it instead of reading raw files
- Read graphify-out/GRAPH_REPORT.md only for broad architecture review or when query/path/explain do not surface enough context
- `.graphifyignore` is a domain allowlist. Graph sources must come only from `apps/`, `database/`, or `app_context/`; agent skills, project automation, `ai_generate/`, workspace metadata, and static payloads stay excluded.
- After modifying APEXlang or database source, run `graphify update .` to refresh deterministic AST relationships without semantic API cost.
- After modifying `app_context/*.md`, run `graphify extract .` so the semantic hash and context concepts refresh.
- After changing `.graphifyignore` or deliberately deleting substantial source, run `graphify extract . --force`, then verify excluded paths are absent and all three retained domain roots remain queryable.
- After any Graphify upgrade, rerun `python3 setup_graphify_apx.py` before updating. A changed integration contract must fail setup rather than silently falling back to SQL or file-only `.apx` nodes.
