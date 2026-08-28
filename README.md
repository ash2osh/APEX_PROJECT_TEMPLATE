# Oracle APEX Project Template

Generic starting point for an Oracle APEX + Oracle Database project, built
to work with any coding agent (Claude Code, Codex, Gemini, Copilot, etc.) —
not just one client.

This repo is a template: clone or copy it as the seed for a new project,
then work through "Instantiating this template" below.

## What you get

The template ships no application code — `apps/`, `database/`, and
`ai_generate/` start empty. What it provides is export automation, database
targeting guards, and a portable agent instruction set.

| Feature | What it does |
|---|---|
| **Strict `.env` loader** | `scripts/load_env.*` parses configuration as literal data and never executes it. An allowlist of exactly 17 keys, no duplicates, no missing values, no inherited fallbacks, plus per-value format validation. |
| **Three database target profiles** | Table metadata, code metadata, and APEX each get their own schema, SQLcl saved connection, expected user, and role. They may point at one connection or three, but each is always stated, never inferred. Credentials stay in SQLcl's saved store. |
| **Two-stage database guards** | `scripts/check_db_target.*` classifies the target before connecting — refusing production writes and stopping when a connection name looks like production but isn't classified as such. `scripts/verify_db_access.sql` then confirms the real session user, schema, and database identity after connecting. Production is read-only **by instruction**, not by privilege audit. |
| **Atomic mirror replacement** | `scripts/replace_mirror.*` stages every export under `scratch/`, refuses a mirror with uncommitted local changes, validates the destination path twice, takes a per-destination lock, and rolls back on failure or interrupt. |
| **APEX application export** | `scripts/export_apps.*` exports one app as APEXLANG, normalizes it to LF, and installs it at `apps/<parsing-schema>/<app-id>/`. Runs no validation — that stays an explicit step. |
| **Database metadata mirror** | `scripts/backup_db.*` exports DDL for tables, views, packages, standalone procedures/functions, and triggers. Never exports table data. Both passes and their manifests must succeed before either schema mirror is replaced. |
| **`.apx` LF enforcement** | `.gitattributes`, a perl-based normalizer, and a test — because the APEXlang compiler breaks on CRLF. |
| **Portable agent instructions** | `.agents/` holds the canonical, client-agnostic rules and skills; `.claude/` holds thin pointers. Works with any agent that reads `AGENTS.md`. |
| **Vendored workflow skills** | 14 general software-engineering process skills (brainstorm → plan → TDD → review → ship) with no external dependency, available even where the plugin isn't installed. |
| **Self-checking template** | `scripts/test_template.sh` / `.ps1` exercise the guards, the loader's injection resistance, mirror replacement failure paths, and export/backup orchestration against a fake SQLcl. CI runs them on Linux and Windows. |
| **Optional tooling** | `uc-apx` (opt-in via `INSTALL_UC_APX`) and `graphify` knowledge graphs. Both are genuinely optional; nothing breaks when they're absent. |

Details for each are in `agents.md`; production specifics are in
[production database safety](docs/production-database-safety.md).

## Prerequisites

- **PowerShell 5.1 or newer** if you use the `scripts/*.ps1` half. Windows
  PowerShell 5.1 (preinstalled on Windows) is supported, as is PowerShell 7+
  on any platform. The scripts declare `#Requires -Version 5.1` so an older
  host fails with a clear message. On Linux/macOS, `snap install powershell
  --classic` (or the package for your distro) is enough to run and test them.
- `perl` — used by `scripts/normalize_apx.sh` to normalize `.apx` line
  endings. Bundled by default on macOS and most desktop Linux distros; on
  minimal Linux images (e.g. slim Docker bases) install it explicitly. The
  `scripts/*.sh` pair requires a Unix shell (macOS/Linux natively, or WSL /
  Git Bash on Windows) — Windows users without one of those should use the
  `scripts/*.ps1` equivalents instead, which have no `perl` dependency.

Run once per machine (idempotent — safe to re-run anytime to refresh):

```bash
# Pulls Oracle's official db + apex skill content into every AI client
# SQLcl detects on this machine (~/.claude, ~/.codex, ~/.gemini, ~/.copilot).
sql -S -noupdates /nolog -e "skills sync"
```

`uc-apx` is genuinely optional and is not bundled. To use it, set
`INSTALL_UC_APX=true` in `.env`, then ask an agent to follow the
[project installer skill](.agents/skills/install-uc-apx/SKILL.md). It verifies
the user-managed CLI installation and synchronizes upstream skills into this
project. With the default `false`, no installation or synchronization occurs.

Optional, only if you want a queryable knowledge graph of this codebase:

```bash
# Install graphify, then register .apx/SQL AST support (once per machine):
python3 setup_graphify_apx.py
```

Also optional — the rules in
[`.agents/rules/graphify.md`](.agents/rules/graphify.md) already gate on
`graphify-out/graph.json` existing, so nothing breaks if `graphify` is
never installed.

## Instantiating this template

1. Copy or clone this repo to the new project's location.
2. Ask your coding agent to run `/init` or `/init ash` (replace `ash` with
   your proposed project name). The agent asks for the application and three
   database target profiles, shows a redacted summary, and creates `.env`
   only after confirmation. If slash commands are unavailable, ask it to
   “initialize this project.”
3. Alternatively, copy `.env.example` to `.env` and set every value manually.
   `.env` is ignored and must not contain credentials.
4. Fill in `agents.md` §6 (Schema Ownership) with how this project actually
   splits schemas.
5. Create the exact SQLcl saved connections named by
   `TABLES_SQLCL_CONNECTION`, `CODE_SQLCL_CONNECTION`, and
   `APEX_SQLCL_CONNECTION`. The names may all identify the same saved
   connection or three different ones.
6. Create `.claude/settings.local.json` locally if you use Claude Code. It is
   listed in `.gitignore`, because Claude Code treats `settings.local.json` as
   a personal, per-machine file rather than something to commit and share. A
   reasonable starting point:
   ```json
   {
     "permissions": {
       "allow": [
         "mcp__sqlcl__connections_list",
         "mcp__sqlcl__connect"
       ]
     }
   }
   ```
7. Run `scripts/export_apps.sh` / `scripts/backup_db.sh` (or the `.ps1`
   equivalents) once you have a real app/schema to export, to populate
   `apps/` and `database/`.

The export scripts write to `scratch/` first. After SQLcl succeeds, they
replace the corresponding generated mirror, so files removed from the live
application or schema do not remain stale in Git. A dirty mirror is refused
instead of being overwritten. Export does not run APEX validation; run
`uc-apx validate --app-dir <app>` separately when validating application
changes.

## Configuration

The strict loaders accept only the documented settings, reject missing or
duplicate keys, and treat every value literally. They never evaluate `.env` as
code. Credentials stay in SQLcl's saved connection store.

The tables profile exports only table metadata. The code profile exports
views, packages, standalone procedures/functions, and triggers. The APEX
profile selects the parsing schema and application export connection. Profiles
are always explicit but may repeat the same schema, connection, user, and role.

Production is **read-only by instruction**: with `DB_ENVIRONMENT=production`,
run SELECT statements only — no DML, no DDL, no `COMMIT`. The template does not
audit privileges, require a dedicated account, or verify roles. It refuses
`write` operation classes at the wrapper level, stops when a connection name
looks like production but isn't classified as such, verifies the session user
matches `*_EXPECTED_USER`, and prints the rule to the operator before and after
connecting. Keeping the rule is the client's responsibility. See
[production database safety](docs/production-database-safety.md).

## Directory layout

```
apps/<parsing-schema>/<app-id>/ Editable Oracle APEX source, APEXLANG format
database/<schema>/              Generated DBMS_METADATA mirror, no table data
app_context/<app-id>/           Durable per-app knowledge base
ai_generate/YYYY-MM-DD/         AI-generated SQL/PLSQL deployment scripts
docs/                           Project documentation and design records
scratch/                        Local throwaway space (gitignored)
scripts/                        Export/backup automation (.sh + .ps1 pairs)
.agents/                        Canonical, client-agnostic agent instructions
.claude/                        Thin Claude-Code-specific pointers into .agents/
.github/                        CI workflow running the template self-checks
```

Application directories are named by the numeric `APEX_APP_ID`, not by the
application alias. SQLcl names its export directory after the alias, which can
be renamed in APEX at any time; `scripts/export_apps.*` detects whatever
directory SQLcl produced and renames it to the id, so an alias change never
forks the mirror into a second directory.

One `.env` describes one application, since it holds a single `APEX_APP_ID`.
For a repo with several apps, give each its own configuration file and select
it per run — every script and guard honors `PROJECT_ENV_FILE`:

```bash
PROJECT_ENV_FILE=.env.app100 scripts/export_apps.sh
PROJECT_ENV_FILE=.env.app200 scripts/export_apps.sh
```

The `database/` mirror covers tables, views, packages, standalone
procedures/functions, and triggers. Sequences, types, synonyms, materialized
views, standalone indexes, and scheduler jobs are **not** exported, and the
manifests count only the exported types — so a mirror can look complete while
omitting those objects.

`.agents/skills/` contains the interactive `initialize-project` skill, the
small `install-uc-apx` opt-in skill, `sqlcl-mcp-r0`, and the vendored
`superpowers/` workflow skills. The
[skills index](.agents/skills/SKILLS.md) describes them. `superpowers/` is a
vendored, local copy of the [superpowers](https://github.com/obra/superpowers)
workflow skill library (brainstorming, writing-plans, TDD, code review, etc.
— see `agents.md` §9) so those skills are available on any machine or agent
client, whether or not the superpowers plugin itself is installed.

See `agents.md` for the full set of repository conventions, and `AGENTS.md`
for the read order any coding agent should follow at the start of a task.
