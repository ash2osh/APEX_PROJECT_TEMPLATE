---
name: graphify
description: Turn any folder of files into a navigable knowledge graph
---

# Workflow: graphify

Use the graphify skill exposed by the current agent client when available. If
the client does not expose that skill, use the repository's
`setup_graphify_apx.py` and `graphify` CLI commands directly; do not assume a
provider-specific home directory or invent an unavailable tool.

## Domain corpus

`.graphifyignore` is intentionally an allowlist. Index only:

- `apps/` — application declarations, pages, shared components, and supporting
  source, excluding static files and workspace/deployment metadata.
- `database/` — synchronized database object source.
- `app_context/` — durable purpose, architecture, pattern, and gotcha context.

Do not re-include agent skills, project scripts, general documentation,
`ai_generate/`, scratch data, generated graph output, or embedded static/BLOB
payloads. This graph describes the APEX application domain, not maintenance of
the repository template.

## Fresh setup and full rebuild

After installing the optional Graphify CLI, configure a supported semantic
backend and run:

```bash
python3 setup_graphify_apx.py
graphify extract . --force
```

The setup copies the tracked `scripts/graphify_apexlang_extractor.py` into the
isolated Graphify package, registers `.apx`, verifies the installed bytes, and
runs a smoke extraction. The full extraction indexes Markdown context as well
as deterministic APEXlang and SQL structure. Do not add `--code-only`: that
would omit `app_context`.

## Incremental updates

- After changing `.apx` or database `.sql` source, run `graphify update .`.
  This refreshes AST relationships without an LLM call and preserves unchanged
  semantic context nodes.
- After changing `app_context/*.md`, run `graphify extract .`. Semantic hashes
  make this incremental; only changed semantic sources should be redispatched.
- After changing `.graphifyignore` or intentionally deleting substantial
  source, run `graphify extract . --force` and repeat the source-root checks.

## Upgrade gate

After every Graphify upgrade, rerun `python3 setup_graphify_apx.py` before any
update. Graphify has no supported APEXlang extension point, so setup validates
the current package anchors and fails closed if an upgrade is incompatible.
Never repair the installed copy by hand; update the tracked extractor/setup and
their tests so the fix persists for every template user.

## Verification and queries

Verify that every nonempty graph `source_file` begins with `apps/`,
`database/`, or `app_context/`; `.apx` sources emit nonzero edges; and context
nodes exist. Then start with `graphify query`, using `graphify path` and
`graphify explain` for focused follow-up. Representative acceptance questions
must cover page-to-table dependencies, navigation-to-page targets, process
calls/writes, and a known application gotcha from `app_context`.
