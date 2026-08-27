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
