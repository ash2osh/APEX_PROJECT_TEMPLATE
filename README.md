# Project Template ({{PROJECT_NAME}})

Generic starting point for an Oracle APEX + Oracle Database project, built
to work with any coding agent (Claude Code, Codex, Gemini, Copilot, etc.) —
not just one client.

This repo is a template: clone or copy it as the seed for a new project,
then work through "Instantiating this template" below.

## Prerequisites

Run once per machine (idempotent — safe to re-run anytime to refresh):

```bash
# Pulls Oracle's official db + apex skill content into every AI client
# SQLcl detects on this machine (~/.claude, ~/.codex, ~/.gemini, ~/.copilot).
sql -S -noupdates /nolog -e "skills sync"
```

Optional, only if you want the structural `.apx` editing CLI:

```bash
# Install uc-apx from https://github.com/United-Codes/uc-apx, then, to
# refresh the skills already vendored in this repo (.agents/skills/,
# mirrored under .claude/skills/):
uc-apx skills sync --agent claude-code
```

`uc-apx` is genuinely optional — every workflow and skill in this template
that uses it ([`.agents/workflows/uc-apx.md`](.agents/workflows/uc-apx.md)
and the skills listed in `agents.md` §7) checks for it first and falls back
to plain SQLcl `apex export/import` when it is absent. Never assume it is
installed on a machine you haven't checked.

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

1. Copy/clone this repo to your new project's location and rename the
   directory.
2. Find and replace every placeholder token below across all files (there
   is no substitution script by design — do this by hand so you actually
   see every file that mentions your project).
3. Fill in `agents.md` §6 (Schema Ownership) with how this project actually
   splits schemas.
4. Set up your SQLcl saved connection(s) using the
   `{{CONN_PREFIX}}_{{SCHEMA}}` naming convention documented in `agents.md`.
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

## Placeholder tokens

| Token | Appears in | Meaning | Example |
|---|---|---|---|
| `{{PROJECT_NAME}}` | `README.md`, `agents.md` | Short project name | `acme` |
| `{{SCHEMA}}` | `agents.md`, `.agents/workflows/uc-apx.md`, `scripts/*` | Primary application/data schema | `ACME` |
| `{{APP_ID}}` | `agents.md`, `scripts/*` | Primary APEX application ID | `100` |
| `{{APP_SLUG}}` | `agents.md`, `.agents/workflows/uc-apx.md` | Primary APEX application folder slug | `example-app` |
| `{{CONN_PREFIX}}` | `agents.md`, `scripts/*` | SQLcl saved-connection prefix | `dev1` |
| `{{CONN_NAME}}` | `scripts/export_apps.sql`, `scripts/backup_db.sql` | Full saved-connection name (`{{CONN_PREFIX}}_{{SCHEMA}}`) | `dev1_ACME` |

## Directory layout

```
apps/{{SCHEMA}}/{{APP_SLUG}}/   Oracle APEX apps, APEXLANG export format
database/{{SCHEMA}}/            DBMS_METADATA schema mirror, one file per object
ai_generate/YYYY-MM-DD/         All AI-generated SQL/PLSQL/APEX output (tracked in git)
scratch/                        Local throwaway space (gitignored)
scripts/                        Export/backup automation (.sh + .ps1 pairs)
.agents/                        Canonical, client-agnostic agent instructions
.claude/                        Thin Claude-Code-specific pointers into .agents/
```

`.agents/skills/` also carries a vendored, local copy of the
[superpowers](https://github.com/obra/superpowers) workflow skill library
(brainstorming, writing-plans, TDD, code review, etc. — see `agents.md` §9)
so those skills are available on any machine or agent client, whether or
not the superpowers plugin itself is installed.

See `agents.md` for the full set of repository conventions, and `AGENTS.md`
for the read order any coding agent should follow at the start of a task.
