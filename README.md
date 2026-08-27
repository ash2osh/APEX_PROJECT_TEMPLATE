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
# Install uc-apx from https://github.com/United-Codes/uc-apx, then:
uc-apx skills sync --agent claude-code
```

`uc-apx` is genuinely optional — every workflow in this template that uses
it ([`.agents/workflows/uc-apx.md`](.agents/workflows/uc-apx.md)) checks for
it first and falls back to plain SQLcl `apex export/import` when it is
absent. Never assume it is installed on a machine you haven't checked.

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
| `{{PROJECT_NAME}}` | `README.md`, `agents.md` | Short project name | `epromhq` |
| `{{SCHEMA}}` | `agents.md`, `.agents/workflows/uc-apx.md`, `scripts/*` | Primary application/data schema | `EPROMHQ` |
| `{{APP_ID}}` | `agents.md`, `scripts/*` | Primary APEX application ID | `201` |
| `{{APP_SLUG}}` | `agents.md`, `.agents/workflows/uc-apx.md` | Primary APEX application folder slug | `departments-center` |
| `{{CONN_PREFIX}}` | `agents.md`, `scripts/*` | SQLcl saved-connection prefix | `42` |
| `{{CONN_NAME}}` | `scripts/export_apps.sql`, `scripts/backup_db.sql` | Full saved-connection name (`{{CONN_PREFIX}}_{{SCHEMA}}`) | `42_EPROMHQ` |

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

See `agents.md` for the full set of repository conventions, and `AGENTS.md`
for the read order any coding agent should follow at the start of a task.
