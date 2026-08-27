# Oracle APEX Project Template

Generic starting point for an Oracle APEX + Oracle Database project, built
to work with any coding agent (Claude Code, Codex, Gemini, Copilot, etc.) —
not just one client.

This repo is a template: clone or copy it as the seed for a new project,
then work through "Instantiating this template" below.

## Prerequisites

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
2. Copy `.env.example` to `.env` and set the project, schema, application,
   named SQLcl connection, environment, expected user, production role, and
   optional-tool values. `.env` is ignored and must not contain credentials.
3. Fill in `agents.md` §6 (Schema Ownership) with how this project actually
   splits schemas.
4. Create the exact SQLcl saved connection named by `SQLCL_CONNECTION`.
5. Recreate `.claude/settings.local.json` locally (it is intentionally not
   tracked in this repo — Claude Code treats `settings.local.json` as a
   personal, per-machine file, not something to commit and share). A
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
6. Run `scripts/export_apps.sh` / `scripts/backup_db.sh` (or the `.ps1`
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

Production requires `DB_ENVIRONMENT=production`, a dedicated non-owner
`DB_EXPECTED_USER`, and `DB_REQUIRED_ROLE` naming the enabled read-only role.
The pre-connect guard blocks writes and suspicious connection-name
misclassification; the SQL scripts verify the real session identity and
privileges after connecting. See
[production database safety](docs/production-database-safety.md).
The policy intentionally does not grant a parsing-schema or APEX administrator
login merely to export an app; use the reviewed APEX artifact from
development/staging as described in that document.

## Directory layout

```
apps/<schema>/<app-slug>/       Editable Oracle APEX source, APEXLANG format
database/<schema>/              Generated DBMS_METADATA mirror, no table data
app_context/<app-slug>_<id>/    Durable per-app knowledge base
ai_generate/YYYY-MM-DD/         AI-generated SQL/PLSQL deployment scripts
scratch/                        Local throwaway space (gitignored)
scripts/                        Export/backup automation (.sh + .ps1 pairs)
.agents/                        Canonical, client-agnostic agent instructions
.claude/                        Thin Claude-Code-specific pointers into .agents/
```

`.agents/skills/` contains the small `install-uc-apx` opt-in skill,
`sqlcl-mcp-r0`, and the vendored `superpowers/` workflow skills. The
[skills index](.agents/skills/SKILLS.md) describes them. `superpowers/` is a
vendored, local copy of the [superpowers](https://github.com/obra/superpowers)
workflow skill library (brainstorming, writing-plans, TDD, code review, etc.
— see `agents.md` §9) so those skills are available on any machine or agent
client, whether or not the superpowers plugin itself is installed.

See `agents.md` for the full set of repository conventions, and `AGENTS.md`
for the read order any coding agent should follow at the start of a task.
