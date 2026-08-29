# Domain-Focused APEX Knowledge Graph Design

**Date:** 2026-08-29  
**Status:** Approved design  
**Scope:** Portable Graphify configuration and APEXlang extraction for this
project template

## Problem

The current graph scans the repository as a generic codebase. Vendored agent
skills and template-maintenance scripts therefore dominate its architecture:
80 of the current 360 nodes come from `.agents/`, 69 come from `scripts/`, and
a vendored brainstorming web server is reported as the primary hub. At the
same time, all 111 indexed `.apx` files produce zero relationships because the
setup script routes APEXlang through Graphify's SQL extractor. The durable
Markdown under `app_context/` is absent because the graph was built with
`--code-only`.

The graph must instead represent the application domain: Oracle APEX
applications, their database dependencies, and their maintained application
context. The result must be reproducible for every clone of this template and
must survive Graphify upgrades through an explicit, repeatable setup step.

## Goals

- Index source only from `apps/`, `database/`, and `app_context/`.
- Extract stable architectural nodes and deterministic relationships from
  APEXlang.
- Preserve Graphify's existing SQL/database extraction.
- Semantically index application context and keep it available across routine
  AST-only graph updates.
- Make installation idempotent, fail closed when Graphify changes
  incompatibly, and portable across supported Linux, macOS, and Windows
  Graphify installations.
- Keep generated graph output local and gitignored while tracking every input,
  installer, rule, test, and workflow needed to recreate it.

## Non-Goals

- Represent every APEX item, button, report column, template option, CSS rule,
  JavaScript symbol, or static asset as a graph node.
- Index template-maintenance automation, vendored agent skills, `ai_generate/`,
  or general repository documentation.
- Replace APEXlang validation or the Oracle APEX compiler.
- Infer database state or inspect a live database.
- Automatically install optional Graphify itself. A user who opts into
  Graphify still installs the CLI before running project setup.

## Chosen Architecture

The repository will own a dedicated APEXlang extractor. The canonical
extractor implementation is a tracked project file; it is never maintained
only as an edit inside a user's Graphify environment.

`setup_graphify_apx.py` will locate supported Graphify installations, ensure
the SQL parser dependency is present, copy the canonical extractor into each
Graphify package, register `.apx` with that extractor, and run a fixture-based
smoke test through the installed package. Repeated setup runs must be safe.
After a Graphify upgrade, rerunning setup refreshes the copied extractor and
registration. If expected integration points or the extractor output contract
are unavailable, setup exits unsuccessfully and explains which check failed.

This extends the template's existing explicit Graphify patch model while
removing the incorrect `.apx -> extract_sql` behavior. It keeps the normal
`graphify update .` command functional; a separate merge wrapper is not
required.

## Corpus Selection

`.graphifyignore` will act as a root allowlist:

- Retain `apps/`.
- Retain `database/`.
- Retain `app_context/`.
- Exclude every other root, including `ai_generate/`, `scripts/`, `.agents/`,
  `.claude/`, setup utilities, and general documentation.

Within `apps/`, exclude content that describes export tooling or embeds binary
and presentation payloads rather than application behavior:

- `.apex/` metadata.
- `deployments/` metadata.
- `workspace-components/`.
- Static-file directories and `static-files.apx` manifests.
- Theme static-file payloads.

Retain application declarations, pages, shared components, and supporting
objects. Supporting-object SQL remains in scope even when related database
objects also appear in `database/`, because it describes the application's
installation contract. Stable object IDs and Graphify's cross-file resolution
must prevent duplicated source files from becoming unrelated domain objects.

## APEXlang Parsing

The extractor will use a deterministic, line-oriented parser suited to the
APEXlang export format. It will track nested component parentheses, property
group braces, arrays, comments, and fenced multiline values. Fenced SQL and
PL/SQL content must not affect APEXlang delimiter tracking.

The parser is structural rather than a complete compiler. It recognizes the
architectural declaration families required by the graph and records unknown
properties as non-graph metadata. An unknown architectural declaration or
unbalanced structure produces a diagnostic. Malformed extraction must not be
cached as a successful empty result.

Every node and edge carries its source path and source line. IDs are normalized
and scoped by application, page, component kind, and component identifier so
same-named components in different applications or pages do not collide.

## Nodes

The extractor emits nodes for:

- Applications.
- Pages.
- Regions.
- Page processes.
- Dynamic actions.
- Shared lists and list-level navigation behavior.
- Shared LOVs.
- Authentication schemes.
- Authorization schemes.
- Application processes.
- Build options.
- Other shared components only when they can participate in an architectural
  relationship supported by this design.
- Referenced database objects and callable package/procedure/function symbols,
  using Graphify-compatible unresolved stubs when the defining object is in a
  separate source file.

Page items, buttons, columns, nested list entries, templates, CSS, JavaScript,
and static files do not become independent nodes. Their declarations may still
provide evidence for an edge owned by the nearest architectural node.

Semantic extraction of `app_context/*.md` supplies purpose, architecture,
pattern, and gotcha concepts. Context concepts should resolve to matching app,
page, component, and database-object nodes during Graphify's semantic merge.
The rebuilt graph is not accepted unless representative context queries return
the expected source-backed concepts.

## Relationships

The extractor emits these deterministic APEXlang relationships:

| Relationship | Source and target |
|---|---|
| `contains` | Application to page/shared component; page to region/process/dynamic action |
| `navigates_to` | Page, region, dynamic action, or shared list to target page |
| `references_component` | Architectural component to referenced shared component |
| `secured_by` | Application, page, region, or process to authorization scheme |
| `reads_from` | Region, process, or application process to queried database object |
| `writes_to` | Process or application process to inserted, updated, deleted, or merged database object |
| `calls` | Process or dynamic action to a package, procedure, or function |

Graphify's semantic extraction supplies context relationships. A context
concept connects to matching domain nodes with Graphify's semantic relations
such as `references`, `conceptually_related_to`, or `rationale_for`. These
edges are semantic rather than AST-derived and must retain the context Markdown
source.

Navigation targets include structured `target` blocks and recognizable APEX
URL targets. Component references include `@...` values that resolve to one of
the retained architectural shared-component families. Authorization properties
create `secured_by` edges even when the scheme name is unqualified.

SQL and PL/SQL fenced blocks are scanned without treating literals or comments
as object references. `FROM` and `JOIN` create reads, DML targets create writes,
and qualified callable expressions create calls. Resolution is
case-insensitive for unquoted Oracle identifiers while labels retain source
spelling.

## Installation and Persistence

The tracked setup process is the persistence boundary:

1. Locate Graphify package directories using the active CLI interpreter and
   supported user-install locations.
2. Install or verify `tree-sitter-sql` in the Graphify environment.
3. Copy the tracked APEXlang extractor into the Graphify package.
4. Register `.apx` as code and route it to the new extractor.
5. Verify the installed file content against the canonical source.
6. Run an installed-package smoke extraction against a small APEXlang fixture.
7. Exit nonzero if any Graphify installation is only partially configured.

The setup must support compiled Windows launcher shims as well as shebang-based
launchers. Tests simulate installation layouts under `scratch/`; they do not
modify a developer's actual Graphify installation.

Project documentation will state:

- Fresh setup: run `python3 setup_graphify_apx.py`, then perform a full semantic
  extraction.
- APEX/SQL-only changes: run `graphify update .`.
- Changed `app_context` Markdown: run incremental `graphify extract .` with a
  configured semantic backend.
- Changed ignore rules or a large deletion: use the documented forced rebuild.
- Graphify upgrade: rerun `python3 setup_graphify_apx.py` before updating the
  graph.

`graphify-out/` remains gitignored. No generated graph, semantic cache, API
credential, or user-specific Graphify path is committed.

## Error Handling

- Missing Graphify remains an optional-tooling warning with a non-success setup
  result; the project itself remains usable without Graphify.
- Missing package integration points, partial registration, copy failure, or a
  failed smoke extraction cause setup to fail with the exact installation path
  and failed gate.
- The setup never reports success after only some required files were changed.
- An APEXlang file with unbalanced component delimiters or multiline fences
  returns an extraction error and is not cached as a valid empty graph.
- Unknown properties and declarations remain available to the nesting parser
  but do not become topology until their architectural meaning is explicitly
  added with regression coverage.
- A reference that cannot resolve locally becomes a source-backed or
  Graphify-compatible unresolved stub; it is not discarded.

## Testing

### Unit tests

Parser fixtures will cover:

- Application, page, region, process, dynamic-action, and shared-component
  containment.
- Structured and URL navigation targets.
- Shared-component and authorization references.
- SQL reads and DML writes.
- PL/SQL package/procedure/function calls.
- Comments, arrays, braces, nested components, and fenced multiline content.
- Duplicate component names across pages and applications.
- Malformed fences and delimiters.
- Stable output over repeated extraction.

Installer tests will cover:

- Missing Graphify modules.
- A clean installation.
- Idempotent repeated setup.
- Replacement of an outdated copied extractor.
- A simulated Graphify layout with changed or missing registration points.
- Prevention of a partially installed state being reported as success.

### Corpus tests

Tests will assert that the allowlist retains representative `.apx`, database
SQL, and context Markdown files while excluding:

- `.agents/` and `.claude/`.
- `scripts/` and root setup code.
- `ai_generate/`.
- `scratch/` and `graphify-out/`.
- APEX static files and `static-files.apx`.
- `.apex/`, `deployments/`, and `workspace-components/`.

### End-to-end verification

Rebuild the current demo graph and assert:

- Every nonempty `source_file` is under `apps/`, `database/`, or
  `app_context/`.
- Excluded paths produce no nodes or edges.
- `.apx` sources produce nonzero edges.
- A representative page-to-table query returns an extracted `reads_from`
  relationship.
- A representative navigation query reaches its target page.
- A representative process query reaches its database call or write target.
- A representative application-context query returns a purpose, pattern, or
  gotcha from the correct `app_context` file.
- Vendored server symbols and template-maintenance scripts are absent from hub
  and report output.

Run the focused parser/installer tests first, then the repository's existing
template test suite. Review the final graph report and focused queries rather
than accepting only a successful Graphify exit code.

## Files Expected to Change

- `.graphifyignore`.
- `setup_graphify_apx.py`.
- A new tracked APEXlang extractor module.
- `scripts/test_setup_graphify.py` and focused extractor/corpus tests.
- `.agents/rules/graphify.md`.
- `.agents/workflows/graphify.md`.
- `AGENTS.md` and/or `README.md` where the portable setup commands are exposed.
- `self_improve.md` only if implementation or verification exposes a reusable,
  evidence-backed repository lesson not already stated by project rules.

Generated `graphify-out/` files may change locally during verification but are
not tracked deliverables.

## Acceptance Criteria

The work is complete when a fresh compatible Graphify installation can be
configured from tracked repository files, the focused and existing tests pass,
the demo graph contains only the three domain roots, APEXlang contributes real
architectural relationships, context is queryable, and rerunning setup plus
graph updates does not require manual edits inside Graphify.
