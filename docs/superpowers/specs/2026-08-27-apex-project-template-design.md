# APEX_PROJECT_TEMPLATE — Design Spec

Date: 2026-08-27
Status: Approved for implementation

## Purpose

A generic, reusable starting point for any future project built on Oracle
APEX + Oracle Database, meant to be cloned/copied as the seed for a new
project repo. It must work with any coding agent (Claude Code, Codex,
Gemini, Copilot, etc.) — not just Claude.

## Background / research basis

This design was derived by studying three real, actively-worked Oracle
APEX + Oracle DB repos on this machine: `epromhq_all`,
`natrec_abshry_backup`, and `natrec_workflow115` (plus a brief look at
`apex_trainer_admin`/`apex_trainer_flutter`, which turned out to be
Firebase-based and contributed only agent-instruction-file conventions,
not Oracle patterns).

All three Oracle projects had independently converged on the same
instruction-file skeleton (`CLAUDE.md` → `AGENTS.md` → `agents.md` →
`self_improve.md` → `.agents/rules/agent-safety.md` →
`.agents/skills/*`), and two files — `agent-safety.md` and
`sqlcl-mcp-r0/SKILL.md` — were found **byte-identical across all three**,
confirming they'd been hand-copied project to project with no single
source of truth. That drift-by-copy-paste is the core problem this
template exists to solve.

Two other environment facts shaped scope:

- This machine already has **user-level** `apex` and `db` skills
  installed globally for every AI client (`~/.claude/skills/apex`,
  `~/.claude/skills/db`, mirrored under `~/.gemini`, `~/.codex`,
  `~/.copilot`), populated by SQLcl's native `skills sync` command
  (confirmed working: `sql -S -noupdates /nolog -e "skills sync"`).
  These already cover general Oracle APEX/PL-SQL/SQL knowledge in
  depth, so the template must not re-teach it — only repo-specific
  conventions belong in this template's own instruction files.
- `uc-apx` (a third-party structural CLI for editing `.apx`/apexlang
  files, from United Codes) is installed globally on this machine
  (`/usr/local/bin/uc-apx`) but is **not guaranteed to exist** on a
  future machine or for a future collaborator. It ships its own skill
  sync (`uc-apx skills sync --agent claude-code`, confirmed working via
  `--dry-run`), which installs into `<cwd>/.claude/skills` by default.
  Template content that assumes uc-apx must be explicitly conditional
  on its presence.

## Scope decision

Of the three scoping options discussed (full scaffold + init script;
docs-only skeleton; instructions-first minimal scaffold), **instructions-
first, minimal scaffold** was chosen: the agent-instruction layer is the
main deliverable, plus a lean `apps/` / `database/` / `ai_generate/` /
`scripts/` skeleton. No `TESTS/` scaffolding, no `theme_agent`, no
`rest_api_folder` — those get built out on the first real project that
needs them, not invented speculatively here.

Neither the Oracle-maintained `db`/`apex` skills nor uc-apx's own skills
are vendored into this repo. Both are live-synced tools with their own
update mechanisms; committing a snapshot would just go stale. The
template documents the sync commands as setup steps instead.

## Directory layout

```
CLAUDE.md                       # one-line pointer: @./AGENTS.md
AGENTS.md                       # portable router (read order for any agent)
agents.md                       # project-specific rules (placeholder tokens)
self_improve.md                 # empty lessons log, pre-formatted template
README.md                       # what this is + how to start a new project from it
.gitattributes                   # LF enforcement for *.apx and *.sql
.gitignore                       # scratch/, ai_generate/ war-story case fix, graphify-out/

.agents/
  rules/
    agent-safety.md             # cross-client safety contract (verbatim from the 3 real projects)
  workflows/
    uc-apx.md                   # conditional — only relevant if uc-apx is installed
  skills/
    sqlcl-mcp-r0/
      SKILL.md                  # canonical R0-restriction-level contract
      references/
        r0-capabilities.md
        client-configs.md

.claude/
  skills/sqlcl-mcp-r0/SKILL.md  # thin pointer -> ../../.agents/skills/sqlcl-mcp-r0/SKILL.md
  settings.local.json            # minimal allowlist: connections_list, connect

apps/{{SCHEMA}}/{{APP_SLUG}}/    # placeholder — apex export -exptype APEXLANG output goes here
database/{{SCHEMA}}/             # placeholder — DBMS_METADATA read-only mirror, one file per object
ai_generate/.gitkeep             # mandatory dated staging area for all AI-generated DB code
scripts/
  export_apps.sh / .ps1          # apex export -exptype APEXLANG, templated with {{CONN_NAME}}
  backup_db.sh / .ps1            # DBMS_METADATA package/table export, templated
  normalize_apx.sh / .ps1        # LF + trailing-newline cleanup post-export
```

`apps/` uses SQLcl's native **APEXLANG** export type (one file per page,
git-diffable text) rather than classic `f<id>.sql`, since that's the
format the most mature of the three real projects converged on and it's
what actually makes a repo agent-editable.

## Instruction-file content plan

- **`agents.md`** stays deliberately thin. It does not duplicate Oracle
  APEX/PLSQL/SQL knowledge (the global `apex`/`db` skills already cover
  that in depth). It covers only what's repo-specific: folder purposes;
  the `ai_generate/YYYY-MM-DD/<same-filename>.sql` staging rule (never
  edit `database/` or `apps/` mirrors directly); `SET DEFINE OFF` + UTF-8
  convention; named-connection-only rule with a
  `{{CONN_PREFIX}}_{{SCHEMA}}` naming convention; a schema-ownership
  placeholder table (data schema / code schema / API schema / runtime
  schema, filled in per project); the `.apx` LF rule; and an "Optional
  Tooling" section stating uc-apx workflows are conditional on the
  binary being present — check before using, never assume it's
  installed in a fresh clone of this template.
- **`self_improve.md`** ships empty but with the header/process text and
  the Trigger/Evidence/Preferred-behavior/Verification lesson template
  pre-written, so the discipline exists from day one instead of being
  invented ad hoc per project (as happened across the three source
  repos).
- **`.agents/rules/agent-safety.md`** is copied in verbatim — it was
  already converged-on, battle-tested, and identical across all three
  source repos.
- **`.agents/workflows/uc-apx.md`** opens with an availability check
  (`command -v uc-apx` / `uc-apx version`) — if absent, stop and defer to
  plain SQLcl `apex export/import -exptype APEXLANG` plus the general
  `apex` skill for `.apx` editing. If present, documents the core
  command set (`overview`, `search`, `shape`, `create`, `edit`, `delete`,
  `deps`, `refs`, `validate`) and the mandatory `uc-apx validate` gate
  after any edit.
- **`README.md`** documents every `{{PLACEHOLDER}}` token and the manual
  find-and-replace steps for starting a new project (no init script,
  per the minimal-scaffold decision), plus a **Prerequisites** section:

  ```bash
  # Required once per machine (idempotent, refresh anytime):
  # pulls Oracle's official db + apex skill content into every AI
  # client SQLcl detects.
  sql -S -noupdates /nolog -e "skills sync"

  # Optional: install uc-apx (structural apexlang CLI) from
  # https://github.com/United-Codes/uc-apx, then sync its own agent
  # skills for this project:
  uc-apx skills sync --agent claude-code
  ```

  Both commands were tested and confirmed working during design
  (SQLcl sync: `SUCCESS: Installed 27 entries...`; uc-apx sync
  `--dry-run`: confirmed it targets `<cwd>/.claude/skills`).

## Placeholder convention

Tokens use `{{UPPER_SNAKE}}` form: `{{SCHEMA}}`, `{{APP_SLUG}}`,
`{{APP_ID}}`, `{{PROJECT_NAME}}`, `{{CONN_PREFIX}}`. `README.md` lists
every token, which file(s) it appears in, and an example value. No
substitution script — manual find-and-replace when starting a new
project, consistent with the minimal-scaffold decision.

## Explicit non-goals

- No CI configuration (none of the three source repos use CI; deploys
  are agent/human-driven via SQLcl).
- No formal migration framework (Liquibase is mentioned as available
  tooling in `db` skill content but not adopted as a required workflow
  — the `ai_generate/` + numbered-release-folder pattern is what's
  actually used).
- No utPLSQL scaffold — testing convention is documented as a note in
  `agents.md` (restartable, self-verifying SQLcl checkpoint scripts) but
  no test files are pre-built, per the minimal-scaffold decision.
- No vendored copies of the `db`/`apex` or uc-apx skill content.

## Open items for implementation

None — scope, file list, and content plan are settled. Implementation
is a matter of writing each file per the content plan above.
