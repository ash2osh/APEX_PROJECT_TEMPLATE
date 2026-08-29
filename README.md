# Oracle APEX Project Template

A portable starting point for Oracle APEX and Oracle Database projects. It
provides strict local configuration, guarded SQLcl connections, atomic APEX
and metadata exports, and coding-agent guidance. Application code and database
mirrors start empty.

**Author:** [Ahmed Sherif](https://www.linkedin.com/in/ahmed-d-sherif)

## Prerequisites

Install these before running anything in this repository:

| Requirement | Needed for |
|---|---|
| **Python 3.10+** | Graphify, `setup_graphify_apx.py`, and the repository's own scripts and test suite |
| **Node.js** | The `apex` skill's APEXlang tooling — `node tools/apexctl.mjs` drives `apexlang format`, grammar validation, and `runtime validate` for `.apx` sources |
| **[uv](https://docs.astral.sh/uv/)** | Installing Graphify and its SQL parser as an isolated tool |
| **Graphify** | Required. The knowledge graph this template is built around; see [Knowledge graph](#knowledge-graph) below |
| **tree-sitter-sql** | Graphify's SQL parser. Without it the `database/` mirror and `apps/**/supporting-objects/*.sql` cannot be indexed at all |
| **SQLcl** | Every database and APEX export, backup, and deployment command |
| **Git** | The export and backup scripts refuse to overwrite a dirty mirror |
| **perl** | The Bash APEX line-ending normalizer (bundled with Git Bash on Windows) |

Oracle's official `apex` and `db` agent skills supply the APEX, PL/SQL, SQL,
and ORDS knowledge this repository deliberately does not restate. Install or
refresh them once per machine:

```text
sql -S -noupdates /nolog -e "skills sync"
```

## Setup

1. Clone or copy the repository.
2. Run `/init` with a coding agent, or copy `.env.example` to `.env` and edit
   all 16 settings. `.env` is gitignored and must not contain credentials.
3. Create the SQLcl saved-connection aliases named by the three
   `*_SQLCL_CONNECTION` settings. Aliases may all point to the same saved
   connection; credentials remain in SQLcl's store.
4. Record the real schema ownership in `AGENTS.md` §6.
5. Run the export and backup commands for your operating system.

### Knowledge graph

Graphify is required for this project. It indexes a domain-only corpus
(`apps/`, `database/`, and `app_context/`) through a repository-owned APEXlang
extractor, so `.apx` files are read as APEX architecture — application and page
containment, navigation, authorization, database reads and writes, and PL/SQL
calls — rather than as generic SQL.

**This is what keeps agent token usage low.** A coding agent that has to answer
"what reads this table?" or "what happens at checkout?" without a graph falls
back on broad `grep` sweeps and reading whole files into its context, repeatedly
and across many turns. `graphify query`, `graphify path`, and `graphify explain`
return a scoped subgraph instead — the handful of related nodes and edges the
question actually needs. Answering from that subgraph pulls a fraction of the
context that reading the underlying sources would, which is why the corpus is
restricted to project domain source and excludes tooling, agent files,
generated output, and static assets.

Install Graphify and its SQL parser — note the distribution is `graphifyy`
while the command it installs is `graphify`:

```bash
uv tool install graphifyy --with tree-sitter-sql
```

Then configure a supported semantic backend and initialize the graph:

```bash
python3 setup_graphify_apx.py
graphify extract . --force
```

`setup_graphify_apx.py` also attempts to install `tree-sitter-sql` into
Graphify's interpreter, but that is a best-effort fallback: install it with
Graphify as shown above rather than relying on it.

The first extraction must be a full one so `app_context/*.md` is indexed as
durable architectural knowledge rather than bare Markdown headings. Afterwards:

- `graphify update .` after APEXlang or database changes (local AST only, no
  API cost).
- `graphify extract .` after changing `app_context`, to refresh semantic
  concepts.
- `graphify extract . --force` after changing `.graphifyignore`.
- `python3 setup_graphify_apx.py` again after **every Graphify upgrade**, so the
  tracked extractor is reinstalled and verified rather than silently falling
  back to the SQL parser.

### What this template adds to Graphify

Graphify has no native understanding of Oracle APEX: left alone it parses
`.apx` exports as generic SQL, which yields file-level nodes and almost no
architecture. This repository closes that gap and ships the integration as
tracked, tested source.

- **An APEXlang extractor** (`scripts/graphify_apexlang_extractor.py`) that
  reads `.apx` as APEX structure — applications, pages, regions, processes,
  dynamic actions, LOVs, lists, authentication and authorization schemes,
  application processes, and build options — and emits `contains`,
  `navigates_to`, `references_component`, `secured_by`, `reads_from`,
  `writes_to`, and `calls` relationships. It is deterministic and needs no LLM.
- **Oracle-aware SQL and PL/SQL analysis**: `#OWNER#` substitution prefixes,
  quoted identifiers, `sys.dual`, `FOR UPDATE` row-lock clauses, `DELETE FROM`
  targets, DML column lists, `EXTRACT(...)` operands, PL/SQL record fields, and
  CTE names are each handled so they neither invent nor lose dependencies.
- **A joined APEX-and-database graph**: because `database/<schema>/` is indexed
  through `tree-sitter-sql` in the same corpus, a region's `reads_from` edge
  resolves onto the real table's DDL, so an APEX page connects to the Oracle
  object it actually queries.
- **A verified, fail-closed installer** (`setup_graphify_apx.py`) that copies
  the extractor into Graphify, reroutes `.apx` away from the SQL parser, smoke
  tests the result, rolls back on any failure, and invalidates only stale
  `.apx` cache entries — so the integration survives Graphify upgrades instead
  of silently regressing.
- **36 regression tests** covering the extractor, the installer, and the
  corpus boundaries, wired into `scripts/test_template.sh`.

See the [Graphify workflow](.agents/workflows/graphify.md) for exclusions and
verification queries.

### Windows

Use Windows PowerShell 5.1 or PowerShell 7 with the native wrappers:

```powershell
./scripts/export_apps.ps1
./scripts/backup_db.ps1
./scripts/test_template.ps1
```

Git Bash is also supported for the `.sh` scripts and includes the `perl`
needed by the Bash APEX line-ending normalizer.

### Linux and macOS

Use Bash, with the prerequisites above available on `PATH`:

```bash
scripts/export_apps.sh
scripts/backup_db.sh
scripts/test_template.sh
```

## Configuration

The Bash and PowerShell loaders accept exactly these settings, require every
one, reject duplicates and unknown keys, and parse values literally. See
`.env.example` for a purpose statement and usage example above every setting.

| Setting | Meaning |
|---|---|
| `PROJECT_NAME` | Human-readable project name. |
| `DB_ENVIRONMENT` | `development`, `test`, `staging`, or `production`; used by safety guards. |
| `APEX_APP_ID` | One or more positive application IDs as strict comma-separated values. |
| `TABLES_SCHEMA` | Schema that owns tables considered for metadata export. |
| `TABLES_PREFIXES` | Table-name prefixes to include, or `*` for all supported tables. |
| `TABLES_SQLCL_CONNECTION` | SQLcl saved-connection alias used for table metadata reads. |
| `TABLES_EXPECTED_USER` | Required Oracle `SESSION_USER` after connecting to the tables profile. |
| `CODE_SCHEMA` | Schema that owns supported code objects considered for export. |
| `CODE_PREFIXES` | Code-object prefixes to include, or `*` for all supported code objects. |
| `CODE_SQLCL_CONNECTION` | SQLcl saved-connection alias used for code metadata reads. |
| `CODE_EXPECTED_USER` | Required Oracle `SESSION_USER` after connecting to the code profile. |
| `APEX_PARSING_SCHEMA` | Parsing schema that owns the configured APEX applications. |
| `APEX_SQLCL_CONNECTION` | SQLcl saved-connection alias used for APEX exports. |
| `APEX_EXPECTED_USER` | Required Oracle `SESSION_USER` after connecting to the APEX profile. |
| `INSTALL_UC_APX` | Whether the optional project installer may configure `uc-apx`: `true` or `false`. |
| `UC_APX_SKILLS_AGENT` | Optional `uc-apx` skill target: `universal` or `claude-code`. |

Schemas identify Oracle owners. Prefixes filter object names within the table
or code schema. Saved-connection settings are SQLcl aliases, never connection
strings or credentials. Expected-user settings are post-connect identity
assertions: for example, `TABLES_EXPECTED_USER` detects the wrong saved
connection or account by checking `SESSION_USER`; it does not select tables,
store credentials, grant privileges, or change the connected user.

CSV is strict: no spaces, blank entries, leading/trailing commas, or
duplicates. Prefixes are uppercase Oracle identifier prefixes; `*` must be the
only value. Application IDs are positive integers.

```dotenv
TABLES_PREFIXES=APP_,COMMON_
CODE_PREFIXES=APP_,COMMON_
APEX_APP_ID=100,200
```

All listed applications must use `APEX_PARSING_SCHEMA`. Use a separate
gitignored configuration selected with `PROJECT_ENV_FILE` when another parsing
schema or environment needs different settings.

```bash
PROJECT_ENV_FILE=.env.other scripts/export_apps.sh
```

```powershell
$env:PROJECT_ENV_FILE = '.env.other'
./scripts/export_apps.ps1
```

The removed `TABLES_REQUIRED_ROLE`, `CODE_REQUIRED_ROLE`, and
`APEX_REQUIRED_ROLE` settings are unsupported and cause the loaders to fail.

## Commands and safety

`scripts/export_apps.*` exports every configured application as APEXlang,
normalizes `.apx` files to LF, verifies all staged exports, and only then
replaces the numeric mirrors under `apps/<parsing-schema>/<app-id>/`.

`scripts/backup_db.*` exports metadata only: tables for the tables profile and
views, packages, standalone procedures/functions, and triggers for the code
profile. Prefix filters apply to export selection and manifest counts. Table
data, sequences, types, synonyms, materialized views, standalone indexes, and
scheduler jobs are not exported.

Both workflows refuse dirty destination mirrors and stage under `scratch/`
before replacement. APEX validation remains a separate explicit action.

Production is read-only by instruction. When `DB_ENVIRONMENT=production`, run
only `SELECT`: no DML, DDL, or `COMMIT`. The wrappers reject production write
operation classes and verify session identity, but they do not audit database
privileges. See [production database safety](docs/production-database-safety.md).

## Directory layout

```text
apps/<parsing-schema>/<app-id>/  Editable APEXlang application source
database/<schema>/               Generated DBMS_METADATA mirror, no table data
app_context/<app-id>/            Durable per-app knowledge base
ai_generate/YYYY-MM-DD/          Deployable generated SQL and PL/SQL
docs/                            Project documentation
scratch/                         Gitignored staging and throwaway files
scripts/                         Bash and PowerShell automation
.agents/                         Canonical agent rules, workflows, and skills
.github/                         CI workflows
```

## Authoritative guidance

- [Project conventions and agent entry point](AGENTS.md)
- [Database and filesystem safety rules](.agents/rules/agent-safety.md)
- [Production database safety](docs/production-database-safety.md)
- [Application context convention](app_context/README.md)
- [Optional uc-apx installer](.agents/skills/install-uc-apx/SKILL.md)
- [Graphify workflow](.agents/workflows/graphify.md)
