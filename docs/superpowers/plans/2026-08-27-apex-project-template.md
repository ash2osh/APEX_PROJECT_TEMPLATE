# APEX_PROJECT_TEMPLATE Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the generic, agent-agnostic Oracle APEX + Oracle Database project template at `/home/ash/projects/APEX_PROJECT_TEMPLATE`, ready to be cloned/copied as the seed for any future project on this stack.

**Architecture:** A docs/config scaffold, not application code. Root bootstrap files (`CLAUDE.md`, `AGENTS.md`) route any coding agent through a client-agnostic `.agents/` instruction tree, a thin `.claude/` mirror, a lean `apps/`/`database/`/`ai_generate/`/`scripts/` skeleton, and repo-specific rules in `agents.md`. No general Oracle/APEX/PLSQL knowledge is duplicated here — that already lives in the machine's global `apex`/`db` skills, synced via SQLcl's native `skills sync` command.

**Tech Stack:** Markdown (instruction files), JSON (`.claude/settings.local.json`), Bash + PowerShell script pairs, SQL/SQLcl driver scripts, git.

**Spec:** [docs/superpowers/specs/2026-08-27-apex-project-template-design.md](../specs/2026-08-27-apex-project-template-design.md)

## Global Constraints

- Placeholder tokens use `{{UPPER_SNAKE}}` form (e.g. `{{SCHEMA}}`, `{{APP_ID}}`) — verbatim, no other bracket style, anywhere in the repo.
- No general Oracle APEX/PLSQL/SQL teaching content in any file in this repo — defer to the globally-installed `apex`/`db` skills.
- No vendored copies of third-party or Oracle-maintained skill content (`db`, `apex`, or `uc-apx`'s own skills) — only the sync commands that install them are documented.
- Every `uc-apx`-specific instruction must be gated behind an availability check; nothing may assume `uc-apx` is installed.
- `.apx` and `.sql` files must be forced to LF via `.gitattributes` (`*.apx text eol=lf`, `*.sql text eol=lf`).
- `ai_generate/` is tracked in git (never gitignored) — only `scratch/` and export-log/graphify-output paths are gitignored.
- Every task ends with a `git commit` — this repo's history should read as one coherent build-out, matching the convention of the three source repos it's modeled on.

---

### Task 1: Root bootstrap + shared safety rule

**Files:**
- Create: `CLAUDE.md`
- Create: `AGENTS.md`
- Create: `.agents/rules/agent-safety.md`

**Interfaces:**
- Produces: the reading-order contract (`AGENTS.md` → `agents.md` → `self_improve.md` → `.agents/rules/agent-safety.md` → `.agents/skills/sqlcl-mcp-r0/SKILL.md` → `.agents/workflows/uc-apx.md`) that every later task's files link into. Task 2 (`self_improve.md`), Task 3 (`sqlcl-mcp-r0`), Task 4 (`uc-apx.md`), and Task 5 (`agents.md`) all assume these three files already exist at these exact paths.

- [ ] **Step 1: Create `CLAUDE.md`**

```markdown
# Claude Code project bootstrap
@./AGENTS.md
```

- [ ] **Step 2: Create `AGENTS.md`**

```markdown
# Agent entry point

This is the portable project instruction entry point for agents that discover
`AGENTS.md` by convention.

Before non-trivial work, read these files in order:

1. [`agents.md`](agents.md) — project-specific Oracle APEX, database, and delivery rules.
2. [`self_improve.md`](self_improve.md) — durable, evidence-backed lessons.
3. [`.agents/rules/agent-safety.md`](.agents/rules/agent-safety.md) — shared safety and verification gates.

When a task uses SQLcl MCP with restriction level 0, also read
[`.agents/skills/sqlcl-mcp-r0/SKILL.md`](.agents/skills/sqlcl-mcp-r0/SKILL.md).

When a task edits files under `apps/`, also read
[`.agents/workflows/uc-apx.md`](.agents/workflows/uc-apx.md) — it explains
when the optional `uc-apx` CLI is available and how to fall back when it is
not.

The referenced files are authoritative together. Do not replace project
rules with this bootstrap file, and preserve unrelated working-tree changes.
```

- [ ] **Step 3: Create `.agents/rules/agent-safety.md`**

```markdown
---
trigger: always_on
description: Apply shared agent safety, target verification, portability, and delivery gates.
---

# Shared Agent Safety and Delivery Contract

Apply these gates in every repository workflow, regardless of client or model.

## Before non-trivial work

- Read `AGENTS.md`, `agents.md`, `self_improve.md`, and relevant application context.
- Run `git status --short --branch` and preserve unrelated user changes.
- Classify the requested action as read-only, reversible, destructive,
  secret-bearing, or externally visible.
- Resolve exact files, directories, database objects, environments, branches,
  remotes, URLs, and HTTP methods before acting.

## Database and SQLcl

- Use only a named saved connection; never infer or guess a production target.
- Before SQL, verify database name, service, session user, current schema, and
  environment with a read-only identity query.
- Inspect scripts before `@`, `@@`, `START`, `SCRIPT`, APEX import, or Liquibase
  execution. Stop if they contain an unexpected `CONNECT`/`CONN`.
- Preview affected rows and dependencies before changes.
- Require explicit approval immediately before `COMMIT`, bulk DML, destructive
  DDL, `TRUNCATE`, `DROP`, `PURGE`, or irreversible migrations unless the
  user's current request already authorizes the exact operation and target.
- Never change production databases or services unless the user explicitly
  authorizes the exact operation and target.
- For SQLcl/SQL*Plus scripts, use `SET DEFINE OFF;`; use UTF-8 session settings
  when localized text or generated source is involved.
- For APEX exports, normalize `.apx` files to LF and validate before delivery.
- Remember that SQLcl R0 expands SQLcl/OS capabilities; it does not grant
  Oracle privileges or make an action safe.

## Files, OS, network, and secrets

- Resolve exact paths; do not use broad recursive deletion or repository-wide
  overwrites.
- Review generated files and focused diffs before staging them.
- Do not print credentials, wallets, private keys, passwords, tokens, or full
  credential-bearing URLs; do not dump unrestricted environment variables.
- Confirm the exact URL, method, payload, and environment before external calls.
- `HOST` and shell commands run on the SQLcl MCP machine, not automatically on
  the Oracle database host.

## Git and completion

- Inspect status and diff before staging; stage only intended files.
- Do not commit or push unless the user explicitly authorizes delivery.
  Immediately before acting, verify the exact repository, branch, and remote.
- After changes, verify the result at its boundary: database validity and
  transaction state, expected files and diffs, generated APEX contents, HTTP
  response, or Git status as applicable.

## Learning loop

Record durable lessons in `self_improve.md` only when they contain Trigger,
Evidence, Preferred behavior, and Verification. Never record secrets, raw
credentials, private data, transient outages, speculation, or task-status notes.
```

- [ ] **Step 4: Verify all three files exist and the internal links resolve**

Run:
```bash
test -f CLAUDE.md && test -f AGENTS.md && test -f .agents/rules/agent-safety.md && echo OK
grep -c "agents.md\]" AGENTS.md
```
Expected: `OK` printed, and the grep prints a count of `1` or more (confirms `AGENTS.md` references `agents.md`).

- [ ] **Step 5: Commit**

```bash
git add CLAUDE.md AGENTS.md .agents/rules/agent-safety.md
git commit -m "Add root bootstrap files and shared agent safety rule"
```

---

### Task 2: Self-improvement lessons log

**Files:**
- Create: `self_improve.md`

**Interfaces:**
- Consumes: nothing new — referenced by `AGENTS.md` (Task 1) and will be referenced by `agents.md` (Task 5).
- Produces: the file `self_improve.md` with a "Durable Lessons" section that later real usage of this template appends entries to (no interface other tasks in this plan depend on).

- [ ] **Step 1: Create `self_improve.md`**

```markdown
# Self-Improvement Notes

This file is the durable learning log for this project. It supplements
`agents.md`; it does not override direct user, system, or project instructions.

## At the Start of Work

1. Read `agents.md` and this file before making a non-trivial change.
2. Inspect the current Git status and recent history so stale snapshots,
   generated output, or earlier assumptions are not mistaken for current
   behavior.
3. For `.apx` (APEXlang) work, verify syntax and line-ending assumptions with
   the actual parser/compiler. For SQLcl or database work, confirm the exact
   requested connection before executing anything.
4. Prefer the smallest complete correction and verify it with the narrowest
   relevant check before broader validation. Keep generated or modified SQL
   and PL/SQL output under `ai_generate/YYYY-MM-DD/` as required by
   `agents.md`; do not edit synchronized source-of-truth files under
   `database/` or `apps/` directly.

## Learning From Corrections

When a user correction, review finding, compiler failure, deployment issue, or
database investigation exposes a recurring risk:

1. Trace the issue to the active file, parser path, database object, or
   deployment step before changing behavior.
2. Fix the implementation and add or update the narrowest applicable check.
3. Record a lesson only when it is repository-specific, reusable, and supported
   by observed evidence. State the trigger, preferred behavior, and verification
   that prevents recurrence.
4. Merge overlapping lessons and remove stale guidance when the architecture or
   tooling changes.

## What Not to Record

- Secrets, credentials, tokens, connection details, personal data, or customer
  information.
- Temporary environment outages or one-off command failures with no durable
  workflow implication.
- Speculation, unverified diagnoses, generic programming advice, or large
  command outputs.
- Task-by-task status logs or rules already stated authoritatively in `agents.md`.

## Durable Lessons

Add lessons below only when the evidence supports them.

### Lesson Template

```text
### Short reusable lesson

- Trigger: what exposed the risk.
- Evidence: the observed behavior or verification result.
- Preferred behavior: what future agents should do.
- Verification: the check that proves the lesson is being followed.
```

No lessons recorded yet.
```

- [ ] **Step 2: Verify the lesson template is well-formed**

Run:
```bash
test -f self_improve.md && grep -c "^### Lesson Template" self_improve.md
```
Expected: file exists, grep prints `1`.

- [ ] **Step 3: Commit**

```bash
git add self_improve.md
git commit -m "Add empty self-improvement lessons log with lesson template"
```

---

### Task 3: sqlcl-mcp-r0 skill (canonical + thin Claude mirror)

**Files:**
- Create: `.agents/skills/sqlcl-mcp-r0/SKILL.md`
- Create: `.agents/skills/sqlcl-mcp-r0/references/r0-capabilities.md`
- Create: `.agents/skills/sqlcl-mcp-r0/references/client-configs.md`
- Create: `.claude/skills/sqlcl-mcp-r0/SKILL.md`
- Create: `.claude/settings.local.json`

**Interfaces:**
- Consumes: relative links back to `AGENTS.md`, `agents.md`, `self_improve.md`, `.agents/rules/agent-safety.md` (all created in Tasks 1–2, and `agents.md` in Task 5 — the links are forward-references that will resolve once Task 5 lands).
- Produces: the canonical skill at `.agents/skills/sqlcl-mcp-r0/SKILL.md`, pointed to by the thin `.claude/skills/sqlcl-mcp-r0/SKILL.md` mirror — the pattern every later client-specific mirror (if any are added later) should follow.

- [ ] **Step 1: Create `.agents/skills/sqlcl-mcp-r0/SKILL.md`**

```markdown
---
name: sqlcl-mcp-r0
description: Use when an AI agent operates Oracle SQLcl MCP with explicit -R 0, including SQL and PL/SQL, SQLcl commands, scripts, filesystem and OS commands, APEX, ORDS, Git, Liquibase, diagnostics, or client configuration.
---

# SQLcl MCP at Restriction Level 0

Use this skill for the project’s SQLcl MCP workflow. It is deliberately agent-neutral: Codex, Claude, Antigravity/Gemini, and other agents can follow the same Markdown instructions and adapt the tool names to their MCP client.

## Core contract

`-R 0` enables every SQLcl command category, including `HOST`, `!`, `$`, scripts, file output, JavaScript automation, and administrative SQLcl commands. It does not grant Oracle privileges, bypass the database account’s permissions, or make an external action safe.

Treat the system as two separate authorities:

1. **SQLcl/OS authority:** the operating-system identity and filesystem/network access of the machine running SQLcl MCP.
2. **Database authority:** the Oracle user, current schema, roles, grants, database, service, and transaction state.

`HOST` runs on the SQLcl MCP machine. It does not run on the Oracle database host unless those are the same machine.

## Mandatory preflight

Before changing a database, file, repository, service, or remote endpoint:

1. Read the project rules and inspect `git status --short --branch`.
2. Identify the SQLcl MCP client, SQLcl executable, SQLcl version, working directory, and effective restriction level.
3. Verify the OS context with read-only commands such as `HOST pwd`, `HOST whoami`, and `HOST git status --short --branch`.
4. Connect only to a named saved connection; verify database identity, service, current schema, and environment before SQL.
5. Inspect scripts and generated diffs before running them.
6. Classify each requested action as read-only, reversible, destructive, secret-bearing, or externally visible.
7. Resolve exact paths, schemas, object names, Git remotes/branches, HTTP methods, and target environments before acting.

Use a read-only effective-level probe when the launcher configuration is unknown:

```sql
version
@/tmp/sqlcl-r0-probe-file-that-does-not-exist.sql
spool off
host true
```

Interpret results from the first blocked capability upward. A successful `host true` indicates effective level 0; a missing-script error rather than a restriction error indicates scripts are enabled. The probe infers effective capability; inspect the client configuration to know the exact `-R` argument.

## Select the right surface

- Use the SQL MCP tool for ordinary SQL, PL/SQL, DML, DDL, transactions, and data dictionary queries.
- Use the SQLcl MCP tool for SQLcl-specific commands such as `APEX`, `DDL`, `LOAD`, `DIFF`, `FORMAT`, `SPOOL`, Liquibase, AWR, background jobs, and `SCRIPT`.
- Use SQLcl script commands (`@`, `@@`, `START`, `GET`) only after reading the referenced files and confirming their target connection.
- Use `HOST`/`!`/`$` for filesystem, Git, OS diagnostics, `curl`, ORDS checks, and project scripts; show the exact command before a destructive or external operation.
- Use JavaScript automation only when a SQL/PLSQL or ordinary shell workflow is insufficient; inspect the script because it can combine JDBC, file I/O, and OS-visible effects.

Read the detailed capability and workflow references only as needed:

- [R0 capabilities](references/r0-capabilities.md) — command categories, examples, risk classes, and detection.
- [Client configurations](references/client-configs.md) — exact locations and `-R 0` examples for Codex, Claude, and Antigravity/Gemini.

## Safety gates

R0 does not remove the following gates:

- **Database changes:** preview affected rows and object dependencies; verify database/schema; require approval immediately before destructive DDL, bulk DML, `COMMIT`, `TRUNCATE`, `DROP`, `PURGE`, or irreversible migration steps unless the user explicitly authorized that exact action and target.
- **Filesystem changes:** resolve the exact path; never use broad recursive deletion or overwrite a repository without confirmation. Prefer backups, diffs, and recoverable moves.
- **Secrets:** never print `~/.dbtools`, wallets, private keys, passwords, tokens, full credential-bearing URLs, or unrestricted environment dumps. Report aliases and redacted metadata only.
- **Network/API calls:** confirm exact URL, method, payload, and environment before `curl`, `ssh`, service changes, or other external calls. `localhost` refers to the SQLcl MCP host.
- **Git:** inspect status and diff first; stage only intended files; require explicit confirmation before `git push`, force operations, history rewrites, or remote deletion.
- **Services and privileges:** do not use `sudo`, restart services, create users, grant privileges, or change firewall/network state without explicit authorization and exact target verification.

Stop on an unexpected connection, schema, path, branch, remote, HTTP response, script error, or transaction state. Report what was observed and ask for direction.

## Self-improvement loop

Read the project’s [`AGENTS.md`](../../../AGENTS.md), [`agents.md`](../../../agents.md), [`self_improve.md`](../../../self_improve.md), [shared safety rules](../../../.agents/rules/agent-safety.md), and relevant application context before non-trivial SQLcl work. These instructions supplement, but never override, user, system, or project rules.

When a correction, failed deployment, wrong connection, hidden script action, compiler error, or repeated workflow failure reveals a durable risk:

1. Stop the unsafe operation and stabilize the immediate task.
2. Trace the evidence to the actual connection, file, parser, database object, command, or deployment step.
3. Fix the immediate behavior and add the narrowest verification that prevents recurrence.
4. Record only reusable, repository-specific knowledge in `self_improve.md` using **Trigger**, **Evidence**, **Preferred behavior**, and **Verification**.
5. Update this skill or a reference only when the lesson changes agent procedure; show the proposed patch and validate it before committing.
6. Merge overlapping lessons and remove stale guidance when the workflow changes.

Never record passwords, tokens, wallets, private data, connection strings, transient outages, speculation, raw logs, or task-status notes. Never silently rewrite client configuration or skill policy as “learning.”

Example durable SQLcl lesson:

```text
### Verify SQLcl target before scripts

- Trigger: A deployment used the wrong saved connection or an embedded CONNECT command.
- Evidence: The session identity did not match the requested DB/service/schema, or the script contained CONNECT/CONN.
- Preferred behavior: Stop; scan scripts before @/START; verify DB name, service, schema, session user, and host; use only the approved saved connection.
- Verification: Run the identity query and confirm the script contains no connection-changing command before execution.
```

## Standard completion checks

After an operation, verify the result at the same boundary where it changed:

- Database: object status, row counts, constraints, invalid objects, and transaction state.
- Filesystem: expected files, permissions, checksums or diff, and absence of accidental secrets.
- APEX: application ID/version, export layout, and generated diff.
- ORDS: HTTP status, response shape, and server-side database evidence.
- Git: status, focused diff, intended commit, and confirmed push target.
- SQLcl MCP: client logs/startup output and database audit records such as `DBTOOLS$MCP_LOG` when available.
```

- [ ] **Step 2: Create `.agents/skills/sqlcl-mcp-r0/references/r0-capabilities.md`**

```markdown
# SQLcl MCP R0 Capabilities

This reference describes what level 0 makes possible. It is a capability map, not permission to perform every operation. The SQLcl process, operating-system account, database account, and client sandbox still limit the result.

## Contents

- [Capability matrix](#capability-matrix)
- [Safe read-oriented examples](#safe-read-oriented-examples)
- [Script and file examples](#script-and-file-examples)
- [APEX, Liquibase, DDL, and data workflows](#apex-liquibase-ddl-and-data-workflows)
- [OS, ORDS, and Git workflows](#os-ords-and-git-workflows)
- [Effective-level detection](#effective-level-detection)
- [Boundaries that R0 does not remove](#boundaries-that-r0-does-not-remove)

## Capability matrix

| Area | Typical surface | Examples | Main risk |
|---|---|---|---|
| SQL and PL/SQL | SQL MCP tool | `SELECT`, `INSERT`, `UPDATE`, `DELETE`, `CREATE`, packages, `COMMIT` | Database data/object changes |
| Schema discovery | SQL MCP tool / schema tool | `USER_OBJECTS`, `ALL_TAB_COLUMNS`, schema metadata | Sensitive metadata disclosure |
| SQLcl formatting | SQLcl MCP tool | `SET SQLFORMAT JSON`, `CSV`, `XML`, `ANSICONSOLE` | Large output, local export |
| Scripts | SQLcl MCP tool | `@install.sql`, `@@child.sql`, `START deploy.sql`, `GET file.sql` | Hidden or chained changes |
| Files | SQLcl MCP tool | `SPOOL`, `SAVE`, `STORE`, `LOAD`, `UNLOAD` | Overwrite, leakage, path confusion |
| APEX | SQLcl MCP tool | `APEX EXPORT -APPLICATIONID {{APP_ID}} -EXPTYPE APEXLANG` | Generated repository changes |
| DDL extraction | SQLcl MCP tool | `DDL schema.table`, `DBMS_METADATA` | Environment-specific DDL |
| Liquibase | SQLcl MCP tool | `lb status`, `lb update`, `lb rollback` | Migration/destructive changes |
| JavaScript | SQLcl `SCRIPT` | JDBC calls, file I/O, SQLcl automation | Combined DB/filesystem effects |
| Performance | SQLcl/SQL tools | AWR, ASH, `V$SQL`, execution plans | Privileged data and report files |
| OS and filesystem | `HOST`, `!`, `$` | `pwd`, `find`, `rg`, `git diff`, `df -h` | Shell escape, deletion, credentials |
| Network and ORDS | `HOST` | `curl -i https://...`, `ss -lntp` | External side effects and data egress |
| Git | `HOST` | `git status`, `git diff`, `git commit`, `git push` | Repository/remote mutation |

## Safe read-oriented examples

```sql
host pwd
host whoami
host git status --short --branch
host rg --files database apps scripts
host git diff --stat

select
  sys_context('USERENV', 'DB_NAME') db_name,
  sys_context('USERENV', 'SERVICE_NAME') service_name,
  sys_context('USERENV', 'CURRENT_SCHEMA') current_schema,
  user database_user
from dual;

select owner, object_type, object_name, status
from all_objects
where owner = upper('{{SCHEMA}}')
order by object_type, object_name;
```

Use `HOST` only for commands whose output is needed. Do not replace a database query with shell parsing when Oracle metadata is authoritative.

## Script and file examples

Inspect before executing:

```sql
host sed -n '1,240p' /absolute/project/path/database/{{SCHEMA}}/deploy.sql
@/absolute/project/path/database/{{SCHEMA}}/deploy.sql
```

Use explicit, disposable output paths:

```sql
spool /tmp/{{SCHEMA}}-schema-report.txt
select owner, object_type, object_name from all_objects order by 1, 2, 3;
spool off
```

Never spool credentials, unrestricted environment output, wallet contents, or sensitive query results to a repository path.

## APEX, Liquibase, DDL, and data workflows

```sql
apex export -applicationid {{APP_ID}} -exptype APEXLANG
ddl {{SCHEMA}}.YOUR_TABLE_NAME
lb status -changelog-file /absolute/project/path/database/changelog.xml
set sqlformat csv
select * from {{SCHEMA}}.some_table fetch first 100 rows only;
```

For `LOAD`, verify the input path, target table, column mapping, row count, error log, and commit behavior before running. For `lb update`, `lb rollback`, imports with replace, or other destructive operations, inspect the changelog and obtain approval for the exact target.

## OS, ORDS, and Git workflows

```sql
host find /absolute/project/path -maxdepth 3 -type f -name '*.sql'
host rg 'YOUR_PACKAGE_NAME|YOUR_SEARCH_TERM' /absolute/project/path
host git diff -- database apps scripts
host curl -i https://example.invalid/ords/health
host df -h
host ps -ef | grep '[o]rds'
```

The `curl`, service, and remote Git examples require exact endpoint/remote confirmation. A read-only `git status` is not equivalent to `git push`; a `curl -i` GET is not equivalent to a POST or state-changing request.

## Effective-level detection

The launcher’s exact flag is authoritative. If it cannot be inspected, probe capabilities with harmless commands:

| Probe | Interpretation |
|---|---|
| `version` | Blocked at the most restrictive documented level; success means below level 4 |
| `@/tmp/nonexistent.sql` | A normal missing-file error means script execution is enabled; restriction error means level 3+ |
| `spool off` | A normal “not spooling” response means spool is enabled; restriction error means level 2+ |
| `host true` | Success means host commands are enabled; restriction error means level 1 |

A successful final probe demonstrates effective level 0 for that process. It does not prove another client’s configuration or reveal the parent process arguments. Restart the client after changing configuration; stale MCP child processes can preserve old flags.

## Boundaries that R0 does not remove

- SQLcl MCP uses stdio; R0 does not create an HTTP server or grant network access by itself.
- `HOST` uses the SQLcl MCP machine’s filesystem and OS identity.
- Oracle permissions still determine which SQL succeeds.
- One MCP process normally has one active database connection/session.
- Client context windows can truncate large outputs; use filters and bounded result sets.
- Interactive commands may hang; prefer non-interactive SQLcl arguments and scripts.
```

- [ ] **Step 3: Create `.agents/skills/sqlcl-mcp-r0/references/client-configs.md`**

```markdown
# SQLcl MCP R0 Client Configurations

Use an absolute SQLcl executable path and add `-R`, `0`, `-mcp` in that order. Preserve unrelated settings. Never place database passwords in these files; SQLcl uses saved connections from the SQLcl connection store.

## Contents

- [Project-local discovery](#project-local-discovery)
- [Codex](#codex)
- [Claude Desktop](#claude-desktop)
- [Claude Code](#claude-code)
- [Antigravity/Gemini](#antigravitygemini)
- [TNS and Java environment](#tns-and-java-environment)
- [Verification after every client change](#verification-after-every-client-change)

## Project-local discovery

Keep `.agents/skills/sqlcl-mcp-r0/` as the canonical project skill. Use thin
native entry points so each client discovers the same guidance without copying
the full skill:

| Client | Project instructions | Native skill wrapper |
|---|---|---|
| Codex and Agent Skills clients | `AGENTS.md` | `.agents/skills/sqlcl-mcp-r0/SKILL.md` |
| Claude Code | `CLAUDE.md` | `.claude/skills/sqlcl-mcp-r0/SKILL.md` |

The Codex and Claude Code project instructions import or point to `AGENTS.md`;
each skill entry point resolves to the canonical `.agents` skill. Restart or
reload an existing client session after changing discovery files.

Find your local SQLcl executable path with `which sql` (Linux/macOS) or
`where sql` (Windows) before editing any client config below.

## Codex

Linux/macOS: edit `~/.codex/config.toml`. Keep the existing server table and set:

```toml
[mcp_servers.sqlcl]
command = "/absolute/path/to/sql"
args = ["-R", "0", "-mcp"]
```

Restart the Codex app or MCP session after changing the file.

## Claude Desktop

Typical locations:

- Linux: `~/.config/Claude/claude_desktop_config.json`
- macOS: `~/Library/Application Support/Claude/claude_desktop_config.json`
- Windows: `%APPDATA%\Claude\claude_desktop_config.json`

Add or update only the `sqlcl` server:

```json
{
  "mcpServers": {
    "sqlcl": {
      "command": "/absolute/path/to/sql",
      "args": ["-R", "0", "-mcp"]
    }
  }
}
```

If TNS resolution is required, add only a non-secret environment path:

```json
"env": {
  "TNS_ADMIN": "/absolute/path/to/tns-admin"
}
```

Restart Claude Desktop and inspect its MCP log if the server does not appear.

## Claude Code

Preferred command-line registration:

```bash
claude mcp add sqlcl /absolute/path/to/sql -- -R 0 -mcp
claude mcp list
```

For a project-scoped configuration, use `.mcp.json` at the repository root:

```json
{
  "mcpServers": {
    "sqlcl": {
      "command": "/absolute/path/to/sql",
      "args": ["-R", "0", "-mcp"]
    }
  }
}
```

Some Claude Code installations store user-scoped servers in `~/.claude.json` with a different surrounding JSON shape. Preserve that shape and change only the existing SQLcl `args` array. Use `claude mcp list` to confirm the effective registration.

## Antigravity/Gemini

Typical Gemini CLI location:

- Linux/macOS: `~/.gemini/config/mcp_config.json`
- Windows: `%USERPROFILE%\.gemini\config\mcp_config.json`

Add the standard MCP registry if it is absent:

```json
{
  "mcpServers": {
    "sqlcl": {
      "command": "/absolute/path/to/sql",
      "args": ["-R", "0", "-mcp"]
    }
  }
}
```

## TNS and Java environment

MCP clients may not inherit interactive-shell variables. If required, add `TNS_ADMIN`, `JAVA_HOME`, or a UTF-8 JVM option in the client’s `env` block without putting credentials there:

```json
"env": {
  "TNS_ADMIN": "/absolute/path/to/network-admin",
  "JAVA_HOME": "/absolute/path/to/jre-17"
}
```

Prefer SQLcl’s saved connection store (`conn -save name -savepwd ...`). Never print or copy the connection store, wallet, password, token, or private key into an agent prompt, skill, or repository.

## Verification after every client change

1. Parse the configuration with its native parser.
2. Confirm the SQLcl command path exists and run `sql -V`.
3. Confirm the exact argument sequence is `-R`, `0`, `-mcp`.
4. Restart the client so stale child processes do not hide the change.
5. Run the harmless capability probe from the main skill and record the effective result.
```

- [ ] **Step 4: Create `.claude/skills/sqlcl-mcp-r0/SKILL.md`**

```markdown
---
name: sqlcl-mcp-r0
description: Use when an AI agent operates Oracle SQLcl MCP with explicit -R 0, including SQL and PL/SQL, SQLcl commands, scripts, filesystem and OS commands, APEX, ORDS, Git, Liquibase, diagnostics, or client configuration.
---

# SQLcl MCP R0

Read and follow the canonical project skill at
[`../../../.agents/skills/sqlcl-mcp-r0/SKILL.md`](../../../.agents/skills/sqlcl-mcp-r0/SKILL.md).
Load its referenced files only when relevant to the task.
```

- [ ] **Step 5: Create `.claude/settings.local.json`**

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

- [ ] **Step 6: Verify structure and JSON validity**

Run:
```bash
test -f .agents/skills/sqlcl-mcp-r0/SKILL.md
test -f .agents/skills/sqlcl-mcp-r0/references/r0-capabilities.md
test -f .agents/skills/sqlcl-mcp-r0/references/client-configs.md
test -f .claude/skills/sqlcl-mcp-r0/SKILL.md
python3 -m json.tool .claude/settings.local.json > /dev/null && echo "JSON OK"
diff <(tail -n +1 .claude/skills/sqlcl-mcp-r0/SKILL.md | grep -c "canonical project skill") <(echo 1)
```
Expected: all `test -f` checks pass silently (no output = success), `JSON OK` printed, and the `diff` prints nothing (both sides equal `1`).

- [ ] **Step 7: Commit**

```bash
git add .agents/skills/sqlcl-mcp-r0 .claude/skills/sqlcl-mcp-r0/SKILL.md .claude/settings.local.json
git commit -m "Add sqlcl-mcp-r0 skill (canonical + thin Claude mirror)"
```

---

### Task 4: uc-apx conditional workflow

**Files:**
- Create: `.agents/workflows/uc-apx.md`

**Interfaces:**
- Consumes: nothing new — referenced from `AGENTS.md` (Task 1, already written) and `agents.md` §7 (Task 5, forward-reference).
- Produces: the documented availability-check pattern (`command -v uc-apx >/dev/null 2>&1 && uc-apx version`) that `agents.md` §7 (Task 5) points to by name.

- [ ] **Step 1: Create `.agents/workflows/uc-apx.md`**

```markdown
---
trigger: manual
description: Conditional workflow for editing apexlang (.apx) files with the optional uc-apx CLI.
---

# uc-apx Workflow (Optional Tooling)

`uc-apx` is a third-party structural CLI for Oracle APEX apps stored in
apexlang (`.apx`) format (https://github.com/United-Codes/uc-apx). It is
**not** guaranteed to be installed. Never assume its presence in a fresh
clone of this template.

## Availability check (do this first)

```bash
command -v uc-apx >/dev/null 2>&1 && uc-apx version
```

- If this fails (no output / command not found): stop using this workflow.
  Fall back to plain SQLcl `apex export -exptype APEXLANG` / `apex import`
  and the general `apex` skill for reading and editing `.apx` files by hand.
- If it succeeds: continue below.

## Installing uc-apx (optional, once per machine)

Download a release for your platform from
https://github.com/United-Codes/uc-apx and place the binary on `PATH` as
`uc-apx`. Then, once per project, install its bundled coding-agent skills:

```bash
uc-apx skills sync --agent claude-code
```

(Use `--agent universal` for non-Claude clients, and add `--global` to
install into `~/.claude/skills` once for all projects instead of this repo's
`.claude/skills`.)

## Core commands (when installed)

Run from the application directory, e.g. `--app-dir apps/{{SCHEMA}}/{{APP_SLUG}}`:

- `uc-apx overview` — summary of the application.
- `uc-apx search <term>` — search names, SQL, and PL/SQL across the app.
- `uc-apx shape <kind>` — observed properties / a reference template for a
  component type. Use this before hand-writing a new component so the
  syntax matches what the app already uses, rather than guessing property
  names.
- `uc-apx create <kind> ...` / `uc-apx edit <kind> ...` / `uc-apx delete <kind> ...`
  — scaffold, modify, or remove components in place.
- `uc-apx deps <id>` / `uc-apx refs <id>` — dependency graph / reverse
  references for a component, before deleting or renaming it.
- `uc-apx schema` — the database objects (tables, views, packages, …) the
  app uses.

## Mandatory gate after any edit

```bash
uc-apx validate --app-dir apps/{{SCHEMA}}/{{APP_SLUG}}
```

Never hand off or import a `.apx` change without a clean `validate` run.
```

- [ ] **Step 2: Verify the availability-check pattern is present verbatim**

Run:
```bash
grep -F 'command -v uc-apx >/dev/null 2>&1 && uc-apx version' .agents/workflows/uc-apx.md
```
Expected: prints the matching line (exit 0).

- [ ] **Step 3: Commit**

```bash
git add .agents/workflows/uc-apx.md
git commit -m "Add conditional uc-apx workflow doc"
```

---

### Task 5: Project rulebook (agents.md)

**Files:**
- Create: `agents.md`

**Interfaces:**
- Consumes: file paths from Tasks 1–4 (`self_improve.md`, `.agents/rules/agent-safety.md`, `.agents/skills/sqlcl-mcp-r0/SKILL.md`, `.agents/workflows/uc-apx.md`) — all now exist, so every link in this file resolves.
- Produces: the placeholder-token table (`{{PROJECT_NAME}}`, `{{SCHEMA}}`, `{{APP_ID}}`, `{{APP_SLUG}}`, `{{CONN_PREFIX}}`) that `README.md` (Task 7) restates and cross-references.

- [ ] **Step 1: Create `agents.md`**

```markdown
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

Fill these in when instantiating this template (see `README.md` for the full
placeholder list):

| Token | Meaning | Example |
|---|---|---|
| `{{PROJECT_NAME}}` | Short project name | `epromhq` |
| `{{SCHEMA}}` | Primary application/data schema | `EPROMHQ` |
| `{{APP_ID}}` | Primary APEX application ID | `201` |
| `{{APP_SLUG}}` | Primary APEX application folder slug | `departments-center` |
| `{{CONN_PREFIX}}` | SQLcl saved-connection prefix | `42` |

## 2. Directory Layout

- `apps/{{SCHEMA}}/{{APP_SLUG}}/` — Oracle APEX applications, exported via
  SQLcl's APEXLANG export type (`apex export -exptype APEXLANG`), one
  directory per app, grouped by owning schema. One file per page under
  `pages/`. This is a **synchronized mirror of the live app** — see the
  output rule below before changing anything here.
- `database/{{SCHEMA}}/` — `DBMS_METADATA`-based schema snapshot (tables,
  views, packages, etc.), one file per object. Also a **synchronized
  mirror** — never hand-edited.
- `ai_generate/YYYY-MM-DD/` — the only place new or modified SQL/PLSQL/APEX
  output is written. Tracked in git (not gitignored) — it is the durable
  record of AI-generated changes, not scratch space.
- `scratch/` — local, gitignored throwaway space. Never put anything here
  that needs to survive the session.
- `scripts/` — export/backup automation (`.sh` and `.ps1` pairs for
  cross-platform use).

## 3. Output Rule (mandatory)

Never edit files under `apps/` or `database/` directly — they are
synchronized mirrors of live database/application state, regenerated by the
scripts in `scripts/`, and a direct edit is silently lost on the next sync.

All new or modified SQL, PL/SQL, or APEX output goes under
`ai_generate/YYYY-MM-DD/<same-filename-as-the-object-being-changed>.sql`.
For an existing object, include only the new or modified
procedures/functions/components — not the whole file — unless the object is
brand new. Deploy the change via SQLcl against the real target, then re-run
the relevant export script in `scripts/` to bring `apps/`/`database/` back
into sync with what was actually deployed.

## 4. SQLcl Deployment Conventions

- Always `SET DEFINE OFF;` before running an APEX import/validate or a
  PL/SQL deploy script — protects `&` substitution characters and any
  localized text in the source.
- Use a UTF-8 session/JDBC encoding when localized text or generated source
  is involved.
- Connect only by named saved connection, using the
  `{{CONN_PREFIX}}_{{SCHEMA}}` naming convention (e.g. `42_EPROMHQ`). Never
  infer, guess, or fall back to a different connection than the one
  requested or matching the target schema folder.
- Before any SQL, verify database name, service, session user, and current
  schema with a read-only identity query (see
  `.agents/rules/agent-safety.md`).

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
| `{{SCHEMA}}_DATA` (example) | Tables — anything that stores rows |
| `{{SCHEMA}}_CODE` (example) | Views and packages — compiled/query logic |
| `{{SCHEMA}}_API` (example) | ORDS REST metadata |
| `{{SCHEMA}}` (example) | APEX runtime schema — granted access only, owns nothing |

## 7. Optional Tooling

`uc-apx` (a structural CLI for `.apx` editing) may or may not be installed.
Its workflow, including the availability check to run before using it, is
documented in
[`.agents/workflows/uc-apx.md`](.agents/workflows/uc-apx.md). Never assume
it is present — check first, and fall back to plain SQLcl export/import
plus the `apex` skill when it is not.

## 8. Testing Convention

No formal test framework (e.g. utPLSQL) is assumed by this template. Until
one is adopted, write restartable, self-verifying SQLcl checkpoint scripts:
one numbered script per step of a workflow, each committing its own
transition and re-verifying database identity before acting, with any
destructive reset script given a `zz_` filename prefix plus an explicit
confirmation variable so it can never be reached by tab-completion or
accidental sequence execution.
```

- [ ] **Step 2: Verify all internal links resolve to files that now exist**

Run:
```bash
for f in .agents/rules/agent-safety.md .agents/skills/sqlcl-mcp-r0/SKILL.md self_improve.md .agents/workflows/uc-apx.md; do
  test -f "$f" && grep -qF "$f" agents.md && echo "OK: $f"
done
```
Expected: four lines, each `OK: <path>`.

- [ ] **Step 3: Commit**

```bash
git add agents.md
git commit -m "Add project rulebook with repo-specific conventions"
```

---

### Task 6: Git line-ending and ignore rules

**Files:**
- Create: `.gitattributes`
- Create: `.gitignore`

**Interfaces:**
- Produces: the LF-enforcement and ignore rules that Task 8's `ai_generate/.gitkeep` and `scratch/`-avoidance depend on (i.e. Task 8 must NOT create a `scratch/` placeholder, since this task gitignores it).

- [ ] **Step 1: Create `.gitattributes`**

```
# Enforce Unix line endings (LF) for APEXlang and SQL files
*.apx text eol=lf
*.sql text eol=lf
```

- [ ] **Step 2: Create `.gitignore`**

```
# Local, gitignored throwaway space
scratch/

# Export log files
**/export.log
**/export_err.log

# Graphify knowledge-graph output (if the graphify tool is used)
/graphify-out/
```

- [ ] **Step 3: Verify git recognizes the attributes**

Run:
```bash
mkdir -p /tmp/apex-template-gitattr-check
touch /tmp/apex-template-gitattr-check/probe.apx
cp /tmp/apex-template-gitattr-check/probe.apx ./probe.apx
git check-attr text eol -- probe.apx
rm -f probe.apx
rmdir /tmp/apex-template-gitattr-check 2>/dev/null || true
```
Expected: output includes `probe.apx: text: set` and `probe.apx: eol: lf`.

- [ ] **Step 4: Commit**

```bash
git add .gitattributes .gitignore
git commit -m "Add gitattributes (LF enforcement) and gitignore"
```

---

### Task 7: README

**Files:**
- Create: `README.md`

**Interfaces:**
- Consumes: the placeholder-token table defined in `agents.md` §1 (Task 5) — this file's own table must list the same six tokens with the same meanings.
- Consumes: the two verified-working prerequisite commands (`sql -S -noupdates /nolog -e "skills sync"` and `uc-apx skills sync --agent claude-code`) established during design.

- [ ] **Step 1: Create `README.md`**

```markdown
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
5. Run `scripts/export_apps.sh` / `scripts/backup_db.sh` (or the `.ps1`
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
```

- [ ] **Step 2: Verify the placeholder table matches agents.md's table**

Run:
```bash
for tok in PROJECT_NAME SCHEMA APP_ID APP_SLUG CONN_PREFIX; do
  grep -q "{{$tok}}" README.md && grep -q "{{$tok}}" agents.md && echo "OK: $tok"
done
```
Expected: five lines, each `OK: <TOKEN>`.

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "Add README with prerequisites and instantiation steps"
```

---

### Task 8: Scripts and directory scaffold

**Files:**
- Create: `scripts/export_apps.sql`
- Create: `scripts/export_apps.sh`
- Create: `scripts/export_apps.ps1`
- Create: `scripts/backup_db.sql`
- Create: `scripts/backup_db.sh`
- Create: `scripts/backup_db.ps1`
- Create: `scripts/normalize_apx.sh`
- Create: `scripts/normalize_apx.ps1`
- Create: `apps/.gitkeep`
- Create: `database/.gitkeep`
- Create: `ai_generate/.gitkeep`

**Interfaces:**
- Consumes: `{{CONN_NAME}}`, `{{SCHEMA}}`, `{{APP_ID}}` placeholder tokens as defined in Task 7's README table — must appear literally (unsubstituted) in these files, consistent with the "no init script, manual find-and-replace" decision.
- Produces: `scripts/normalize_apx.sh`/`.ps1`, invoked by `export_apps.sh`/`.ps1` in this same task — both files must exist together for the export scripts to run standalone.

- [ ] **Step 1: Create `scripts/export_apps.sql`**

```sql
-- Exports the APEX application {{APP_ID}} to apps/{{SCHEMA}}/ using SQLcl's
-- APEXLANG export type. Run via:
--   sql -S -noupdates -name {{CONN_NAME}} @scripts/export_apps.sql
SET DEFINE OFF
SET ENCODING UTF-8

apex export -applicationid {{APP_ID}} -exptype APEXLANG -overwrite-files -dir apps/{{SCHEMA}}

exit
```

- [ ] **Step 2: Create `scripts/export_apps.sh`**

```bash
#!/usr/bin/env bash
# Export the {{APP_ID}} APEX application to apps/{{SCHEMA}}/ (APEXLANG format).
# Requires a saved SQLcl connection named {{CONN_NAME}}.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p "apps/{{SCHEMA}}"
sql -S -noupdates -name "{{CONN_NAME}}" @scripts/export_apps.sql
./scripts/normalize_apx.sh "apps/{{SCHEMA}}"
```

- [ ] **Step 3: Create `scripts/export_apps.ps1`**

```powershell
# Export the {{APP_ID}} APEX application to apps/{{SCHEMA}}/ (APEXLANG format).
# Requires a saved SQLcl connection named {{CONN_NAME}}.
$ErrorActionPreference = "Stop"
Set-Location (Join-Path $PSScriptRoot "..")
New-Item -ItemType Directory -Force -Path "apps/{{SCHEMA}}" | Out-Null
sql -S -noupdates -name "{{CONN_NAME}}" "@scripts/export_apps.sql"
& (Join-Path $PSScriptRoot "normalize_apx.ps1") "apps/{{SCHEMA}}"
```

- [ ] **Step 4: Create `scripts/backup_db.sql`**

```sql
-- Exports every table, view, and package in {{SCHEMA}} to database/{{SCHEMA}}/,
-- one file per object, via DBMS_METADATA. Run via:
--   sql -S -noupdates -name {{CONN_NAME}} @scripts/backup_db.sql
SET DEFINE OFF
SET ENCODING UTF-8
SET PAGESIZE 0
SET LINESIZE 32767
SET LONG 100000000
SET LONGCHUNKSIZE 100000000
SET TRIMSPOOL ON
SET FEEDBACK OFF
SET ECHO OFF
SET VERIFY OFF

BEGIN
  DBMS_METADATA.SET_TRANSFORM_PARAM(DBMS_METADATA.SESSION_TRANSFORM, 'PRETTY', TRUE);
  DBMS_METADATA.SET_TRANSFORM_PARAM(DBMS_METADATA.SESSION_TRANSFORM, 'SQLTERMINATOR', TRUE);
  DBMS_METADATA.SET_TRANSFORM_PARAM(DBMS_METADATA.SESSION_TRANSFORM, 'SEGMENT_ATTRIBUTES', FALSE);
  DBMS_METADATA.SET_TRANSFORM_PARAM(DBMS_METADATA.SESSION_TRANSFORM, 'STORAGE', FALSE);
END;
/

-- Guard: fail loudly if connected to the wrong schema, instead of silently
-- exporting into the wrong directory.
DECLARE
  v_schema VARCHAR2(128) := SYS_CONTEXT('USERENV', 'CURRENT_SCHEMA');
BEGIN
  IF v_schema != '{{SCHEMA}}' THEN
    RAISE_APPLICATION_ERROR(-20001,
      'backup_db.sql expected schema {{SCHEMA}} but current schema is ' || v_schema);
  END IF;
END;
/

SPOOL scripts/_backup_db_driver.sql

SELECT 'SPOOL database/{{SCHEMA}}/tables/' || table_name || '.sql'
       || CHR(10) || 'SELECT DBMS_METADATA.GET_DDL(''TABLE'', ''' || table_name || ''', ''{{SCHEMA}}'') FROM DUAL;'
       || CHR(10) || 'SPOOL OFF'
FROM user_tables
ORDER BY table_name;

SELECT 'SPOOL database/{{SCHEMA}}/views/' || view_name || '.sql'
       || CHR(10) || 'SELECT DBMS_METADATA.GET_DDL(''VIEW'', ''' || view_name || ''', ''{{SCHEMA}}'') FROM DUAL;'
       || CHR(10) || 'SPOOL OFF'
FROM user_views
ORDER BY view_name;

SELECT 'SPOOL database/{{SCHEMA}}/packages/' || object_name || '_SPEC.sql'
       || CHR(10) || 'SELECT DBMS_METADATA.GET_DDL(''PACKAGE_SPEC'', ''' || object_name || ''', ''{{SCHEMA}}'') FROM DUAL;'
       || CHR(10) || 'SPOOL OFF'
       || CHR(10) || 'SPOOL database/{{SCHEMA}}/packages/' || object_name || '_BODY.sql'
       || CHR(10) || 'SELECT DBMS_METADATA.GET_DDL(''PACKAGE_BODY'', ''' || object_name || ''', ''{{SCHEMA}}'') FROM DUAL;'
       || CHR(10) || 'SPOOL OFF'
FROM user_objects
WHERE object_type = 'PACKAGE'
ORDER BY object_name;

SPOOL OFF

@scripts/_backup_db_driver.sql
```

- [ ] **Step 5: Create `scripts/backup_db.sh`**

```bash
#!/usr/bin/env bash
# Refresh database/{{SCHEMA}}/ from live DB state via DBMS_METADATA.
# Requires a saved SQLcl connection named {{CONN_NAME}}.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p "database/{{SCHEMA}}/tables" "database/{{SCHEMA}}/views" "database/{{SCHEMA}}/packages"
sql -S -noupdates -name "{{CONN_NAME}}" @scripts/backup_db.sql
rm -f scripts/_backup_db_driver.sql
```

- [ ] **Step 6: Create `scripts/backup_db.ps1`**

```powershell
# Refresh database/{{SCHEMA}}/ from live DB state via DBMS_METADATA.
# Requires a saved SQLcl connection named {{CONN_NAME}}.
$ErrorActionPreference = "Stop"
Set-Location (Join-Path $PSScriptRoot "..")
New-Item -ItemType Directory -Force -Path "database/{{SCHEMA}}/tables","database/{{SCHEMA}}/views","database/{{SCHEMA}}/packages" | Out-Null
sql -S -noupdates -name "{{CONN_NAME}}" "@scripts/backup_db.sql"
Remove-Item -Force -ErrorAction SilentlyContinue "scripts/_backup_db_driver.sql"
```

- [ ] **Step 7: Create `scripts/normalize_apx.sh`**

```bash
#!/usr/bin/env bash
# Normalize *.apx files under the given directory to LF line endings with
# exactly one trailing newline, and revert any file whose only change vs the
# last commit is whitespace/line-ending noise (prevents phantom diffs from
# SQLcl's export vs an editor's line-ending handling).
set -euo pipefail

TARGET_DIR="${1:?usage: normalize_apx.sh <dir>}"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

find "$TARGET_DIR" -type f -name '*.apx' -print0 2>/dev/null | while IFS= read -r -d '' f; do
  perl -pi -e 's/\r\n/\n/g' "$f"
  perl -0pi -e 's/\n*\z/\n/' "$f"
  if git -C "$REPO_ROOT" diff --quiet -- "$f" 2>/dev/null; then
    :
  elif git -C "$REPO_ROOT" diff --ignore-space-at-eol --ignore-blank-lines --quiet -- "$f" 2>/dev/null; then
    git -C "$REPO_ROOT" checkout -- "$f"
  fi
done
```

- [ ] **Step 8: Create `scripts/normalize_apx.ps1`**

```powershell
# Normalize *.apx files under the given directory to LF line endings with
# exactly one trailing newline, and revert any file whose only change vs the
# last commit is whitespace/line-ending noise.
param(
  [Parameter(Mandatory = $true)][string]$TargetDir
)
$ErrorActionPreference = "Stop"
$repoRoot = Join-Path $PSScriptRoot ".."

if (Test-Path $TargetDir) {
  Get-ChildItem -Path $TargetDir -Filter *.apx -Recurse | ForEach-Object {
    $path = $_.FullName
    $text = [System.IO.File]::ReadAllText($path) -replace "`r`n", "`n"
    $text = $text.TrimEnd("`n") + "`n"
    [System.IO.File]::WriteAllText($path, $text)

    Push-Location $repoRoot
    try {
      $realDiff = git diff --ignore-space-at-eol --ignore-blank-lines -- $path
      $anyDiff = git diff -- $path
      if ([string]::IsNullOrWhiteSpace($realDiff) -and -not [string]::IsNullOrWhiteSpace($anyDiff)) {
        git checkout -- $path
      }
    } finally {
      Pop-Location
    }
  }
}
```

- [ ] **Step 9: Make the `.sh` scripts executable**

```bash
chmod +x scripts/export_apps.sh scripts/backup_db.sh scripts/normalize_apx.sh
```

- [ ] **Step 10: Create the scaffold directories**

```bash
mkdir -p apps database ai_generate
touch apps/.gitkeep database/.gitkeep ai_generate/.gitkeep
```

- [ ] **Step 11: Verify shell scripts are syntactically valid**

Run:
```bash
bash -n scripts/export_apps.sh && echo "export_apps.sh OK"
bash -n scripts/backup_db.sh && echo "backup_db.sh OK"
bash -n scripts/normalize_apx.sh && echo "normalize_apx.sh OK"
ls -l scripts/*.sh | awk '{print $1, $NF}'
```
Expected: three `OK` lines, and the `ls -l` output shows `x` in the permission bits for all three `.sh` files (e.g. `-rwxr-xr-x ... scripts/export_apps.sh`).

- [ ] **Step 12: Verify scaffold directories exist**

Run:
```bash
test -f apps/.gitkeep && test -f database/.gitkeep && test -f ai_generate/.gitkeep && echo OK
```
Expected: `OK`.

- [ ] **Step 13: Commit**

```bash
git add scripts apps/.gitkeep database/.gitkeep ai_generate/.gitkeep
git commit -m "Add export/backup scripts and apps/database/ai_generate scaffold"
```

---

### Task 9: Final structural verification

**Files:**
- None created — verification only.

**Interfaces:**
- Consumes: every file produced in Tasks 1–8.

- [ ] **Step 1: Confirm the full expected file tree is present**

Run:
```bash
for f in \
  CLAUDE.md AGENTS.md agents.md self_improve.md README.md \
  .gitattributes .gitignore \
  .agents/rules/agent-safety.md \
  .agents/workflows/uc-apx.md \
  .agents/skills/sqlcl-mcp-r0/SKILL.md \
  .agents/skills/sqlcl-mcp-r0/references/r0-capabilities.md \
  .agents/skills/sqlcl-mcp-r0/references/client-configs.md \
  .claude/skills/sqlcl-mcp-r0/SKILL.md \
  .claude/settings.local.json \
  scripts/export_apps.sql scripts/export_apps.sh scripts/export_apps.ps1 \
  scripts/backup_db.sql scripts/backup_db.sh scripts/backup_db.ps1 \
  scripts/normalize_apx.sh scripts/normalize_apx.ps1 \
  apps/.gitkeep database/.gitkeep ai_generate/.gitkeep \
  docs/superpowers/specs/2026-08-27-apex-project-template-design.md \
  docs/superpowers/plans/2026-08-27-apex-project-template.md
do
  test -f "$f" || echo "MISSING: $f"
done
echo "structural check complete"
```
Expected: no `MISSING:` lines, ends with `structural check complete`.

- [ ] **Step 2: Confirm no unintended placeholder styles crept in**

Run:
```bash
grep -rEn '\{[A-Z_]+\}|<<[A-Z_]+>>|__[A-Z_]+__' --include='*.md' --include='*.sh' --include='*.ps1' --include='*.sql' . | grep -v '{{' || echo "no stray placeholder styles"
```
Expected: `no stray placeholder styles` (confirms every placeholder uses the `{{UPPER_SNAKE}}` convention from Global Constraints, not a mix of styles).

- [ ] **Step 3: Confirm git history is clean and complete**

Run:
```bash
git status --short
git log --oneline
```
Expected: `git status --short` prints nothing (clean tree); `git log --oneline` shows 9 commits, one per task, oldest-first ending with this task's commit.

- [ ] **Step 4: Commit (only if Step 2 required no fixes; otherwise fix first, then commit the fix)**

If Step 2 found stray placeholders, fix them in the offending file(s) with Edit, re-run Step 2 and Step 3, then:

```bash
git add -A
git commit -m "Fix stray placeholder styles found in final verification"
```

If Step 2 found nothing, there is nothing to commit for this task — Task 9 is verification-only.
