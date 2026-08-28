# Project Agent Guidelines (agents.md)

This file holds repository-specific conventions only — folder layout, the
generated-code staging rule, connection and schema-naming conventions, and
`.apx` delivery rules. It intentionally does not re-explain Oracle APEX,
PL/SQL, or SQL — that knowledge lives in the globally-installed `apex` and
`db` skills (see "Prerequisites" in `README.md`). Read those skills for
anything about APEX component syntax, PL/SQL patterns, ORDS, or general SQL.

## Shared Agent Contract

Before non-trivial work, also read [`.agents/rules/agent-safety.md`](.agents/rules/agent-safety.md)
and, when SQLcl MCP is involved, [`.agents/skills/sqlcl-mcp-r0/SKILL.md`](.agents/skills/sqlcl-mcp-r0/SKILL.md).
These files provide the cross-client target, secrets, production, filesystem,
network, Git, and verification gates that apply to every task in this repo.

## Self-Improvement Notes

Before non-trivial work, read [`self_improve.md`](self_improve.md) together
with this file. Append only reusable lessons that include the trigger,
preferred behavior, and verification that prevents recurrence. Keep this file
supplemental to the rules below; do not copy existing invariants into it.

---

## 1. Project Identity

Use `/init`, `/init <project-name>`, or the `initialize-project` skill to create
the gitignored `.env`; manual setup may copy `.env.example`. Configure explicit
tables, code, and APEX parsing-schema profiles. Their schema, SQLcl saved
connection, expected user, and role values may be identical or independent.
Load `.env` only through `scripts/load_env.sh` or `scripts/load_env.ps1`; it is
parsed as literal data and must never be executed as shell code. Keep
credentials in SQLcl's saved connection store, not in `.env`.

One `.env` describes exactly one APEX application, because it holds a single
`APEX_APP_ID`. The `apps/<parsing-schema>/<app-id>/` layout still holds many
apps: give each one its own configuration file and select it per invocation
with `PROJECT_ENV_FILE`, which every script and guard already honors.

```bash
PROJECT_ENV_FILE=.env.app100 scripts/export_apps.sh
PROJECT_ENV_FILE=.env.app200 scripts/export_apps.sh
```

Add each extra configuration file to `.gitignore` alongside `.env`; they are
per-clone local state for the same reason `.env` is.

## 2. Directory Layout

- `apps/<parsing-schema>/<app-id>/` — Oracle APEX applications, exported via
  SQLcl's APEXLANG export type (`apex export -exptype APEXLANG`), one
  directory per app, grouped by owning schema. One file per page under
  `pages/`. This is editable project source and is changed in place.
  Directories are named by the numeric `APEX_APP_ID`, which never changes,
  rather than by the application alias, which SQLcl picks for the export and
  which can be renamed in APEX at any time. `scripts/export_apps.*` detects
  whatever directory SQLcl created and renames it to the id before staging.
- `database/<schema>/` — `DBMS_METADATA`-based schema snapshot (tables,
  views, packages, etc.), one file per object. Also a **synchronized
  mirror** — never hand-edited. It covers tables, views, packages, standalone
  procedures/functions, and triggers only; sequences, types, synonyms,
  materialized views, standalone indexes, and scheduler jobs are not
  exported, and the manifests count only the exported types.
- `app_context/<app-id>/` — durable, per-app knowledge base
  (purpose, architecture notes, known patterns, known bugs/gotchas). Check
  it before touching an app, update it after resolving a non-trivial issue.
  See [`app_context/README.md`](app_context/README.md) for the convention
  and `context.md` template.
- `ai_generate/YYYY-MM-DD/` — deployable AI-generated SQL and PL/SQL scripts.
  It is tracked in Git and is not temporary space. APEX source changes belong
  directly under `apps/`, not here.
- `scratch/` — local, gitignored throwaway space. All temporary files,
  generated helper scripts, staging exports, and rollback copies go here;
  never put anything here that needs to survive the session.
- `scripts/` — export/backup automation (`.sh` and `.ps1` pairs for
  cross-platform use).

## 3. Output Rule (mandatory)

Edit APEXlang files in place under `apps/`. Before replacing an application
from a fresh export, the synchronization scripts check Git for local changes
under that exact application directory and refuse to overwrite a dirty tree.

Never hand-edit `database/`; it is a generated, metadata-only mirror. Put new
or modified SQL and PL/SQL deployment scripts under
`ai_generate/YYYY-MM-DD/`, deploy them through an explicitly approved database
workflow, then refresh `database/` from the database.

The export and database-mirror scripts stage their complete output under
`scratch/`, normalize only staged files, and replace the exact generated
mirror only after SQLcl exits successfully. They refuse to replace a dirty
mirror and do not run `uc-apx validate`; validation remains an explicit
developer or CI action for application changes.

## 4. SQLcl Deployment Conventions

- Use `SET DEFINE OFF;` while running an APEX import/validation source file or
  PL/SQL deployment payload. Export/backup wrappers may enable substitution
  only for their validated positional configuration and disable it afterward.
- Use a UTF-8 session/JDBC encoding when localized text or generated source
  is involved.
- Connect only through the exact named saved connection in `.env`. Never
  infer, guess, or fall back to another connection. Select the explicit
  tables, code, or APEX profile for the operation.
- Before any SQL, verify database name, service, session user, and current
  schema with a read-only identity query (see
  `.agents/rules/agent-safety.md`).
- **Production is read-only by instruction: run SELECT statements only.** No
  DML (`INSERT`, `UPDATE`, `DELETE`, `MERGE`), no DDL (`CREATE`, `ALTER`,
  `DROP`, `TRUNCATE`), no `COMMIT`. The template does not audit privileges,
  require a dedicated account, or verify roles — it refuses write operation
  classes at the wrapper level and prints the rule before and after
  connecting. Keeping it is the client's responsibility. Scripts still verify
  the session user matches the configured `*_EXPECTED_USER`. If any selected
  connection, database, or service name resembles production but `.env` does
  not classify it as production, stop and ask the user to classify it.
- Before any write (DML, DDL, or a deployment script) against any environment,
  run the guard for that operation class explicitly — nothing else calls it:
  `scripts/check_db_target.sh write <tables|code|apex>`, or
  `scripts/check_db_target.ps1 -Operation write -Target <tables|code|apex>`.

## 5. `.apx` (APEXlang) Delivery Rule

`.apx` files must use Unix line endings (LF) — the APEXlang compiler
crashes or silently drops a file on Windows CRLF endings. This is enforced
at the git level by `.gitattributes` (`*.apx text eol=lf`), but always
re-verify after any tool or OS step that might reintroduce CRLF (editing on
Windows, a PowerShell text cmdlet, a chat-pasted diff). For the full
`.apx` syntax and component reference, use the `apex` skill.

## 6. Schema Ownership (fill in for this project)

Adjust this table to match how this project actually splits schemas. Many
Oracle APEX projects separate data, compiled code, REST/API metadata, and
the APEX runtime schema so that grants stay narrow and objects are
referenced through public synonyms rather than schema-qualified names
outside their own `CREATE [OR REPLACE]` line.

| Schema | Owns |
|---|---|
| `<PROJECT>_DATA` (example) | Tables — anything that stores rows |
| `<PROJECT>_CODE` (example) | Views and packages — compiled/query logic |
| `<PROJECT>_API` (example) | ORDS REST metadata |
| `<PROJECT>` (example) | APEX runtime schema — granted access only, owns nothing |

Map these choices into `TABLES_SCHEMA`, `CODE_SCHEMA`, and
`APEX_PARSING_SCHEMA`. `scripts/backup_db.*` obtains tables through the tables
profile and views/packages/standalone procedures/functions/triggers through
the code profile. `scripts/export_apps.*` uses only the APEX profile.

## 7. Optional Tooling

`uc-apx` and its task-routed skills are not bundled. To opt in, set
`INSTALL_UC_APX=true` in `.env` and follow
[`.agents/skills/install-uc-apx/SKILL.md`](.agents/skills/install-uc-apx/SKILL.md).
The skill verifies or helps the user install the binary and synchronizes its
skills project-locally. With the default `false`, agents must not install or
synchronize it. See [`.agents/workflows/uc-apx.md`](.agents/workflows/uc-apx.md)
for the edit and fallback workflow.

`graphify` (a knowledge-graph indexer for the codebase, exposed via
`graphify-out/`) is also optional. Its rules live in
[`.agents/rules/graphify.md`](.agents/rules/graphify.md) (auto-applies, but
every rule is gated on `graphify-out/graph.json` existing) and
[`.agents/workflows/graphify.md`](.agents/workflows/graphify.md). On a new
machine, run `python3 setup_graphify_apx.py` before first use — see
`.graphifyignore` for what's excluded from the graph.

## 8. Testing Convention

No formal test framework (e.g. utPLSQL) is assumed by this template. Until
one is adopted, write restartable, self-verifying SQLcl checkpoint scripts:
one numbered script per step of a workflow, each committing its own
transition and re-verifying database identity before acting, with any
destructive reset script given a `zz_` filename prefix plus an explicit
confirmation variable so it can never be reached by tab-completion or
accidental sequence execution.

## 9. Vendored Workflow Skills (superpowers)

This repo carries a local copy of the [superpowers](https://github.com/obra/superpowers)
skill library (MIT License, © Jesse Vincent — see
[`.agents/skills/superpowers/LICENSE`](.agents/skills/superpowers/LICENSE))
under [`.agents/skills/superpowers/`](.agents/skills/superpowers/)
(canonical) with thin pointers under `.claude/skills/`, following the same
pattern as every other skill in this repo — see
[`.agents/skills/SKILLS.md`](.agents/skills/SKILLS.md) for the full list
with descriptions, or just: `brainstorming`, `writing-plans`,
`executing-plans`, `subagent-driven-development`,
`dispatching-parallel-agents`, `systematic-debugging`,
`test-driven-development`, `using-git-worktrees`, `requesting-code-review`,
`receiving-code-review`, `finishing-a-development-branch`,
`verification-before-completion`, `writing-skills`, and `using-superpowers`
(the entry point — start there).

Unlike `uc-apx` or `graphify`, these are pure-content process skills with no
external binary dependency — they work on any machine, for any coding
agent, without installing anything. They are general software-engineering
workflow skills (brainstorming → plan → implement → review → ship), not
APEX/Oracle-specific; use them the same way on this project as on any other.
If the `superpowers` plugin is also installed and enabled for a given agent
client, that plugin's own versioned skills take precedence — this vendored
copy exists so the same methodology is available even on a client or
machine where the plugin isn't installed.
