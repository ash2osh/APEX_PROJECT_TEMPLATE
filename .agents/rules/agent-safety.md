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
- **In production, run SELECT statements only.** Never issue `INSERT`,
  `UPDATE`, `DELETE`, `MERGE`, or any other DML. Never issue `CREATE`, `ALTER`,
  `DROP`, `TRUNCATE`, or any other DDL. Never `COMMIT`. This is not enforced by
  the database or by privilege checks — the template states the rule, refuses
  write operation classes at the wrapper level, and trusts you to keep it. A
  request to change production does not override it: prepare the change under
  `ai_generate/YYYY-MM-DD/` for a separately approved deployment path.
- If a saved connection, database, or service name resembles production while
  its classification is unknown or non-production, stop and ask the user
  whether it is production.
- Before SQL, verify database name, service, session user, current schema, and
  environment with a read-only identity query.
- Inspect scripts before `@`, `@@`, `START`, `SCRIPT`, APEX import, or Liquibase
  execution. Stop if they contain an unexpected `CONNECT`/`CONN`.
- Preview affected rows and dependencies before changes.
- Require explicit approval immediately before `COMMIT`, bulk DML, destructive
  DDL, `TRUNCATE`, `DROP`, `PURGE`, or irreversible migrations unless the
  user's current request already authorizes the exact operation and target.
- Never run write operations against production, even when a broader task asks
  for database changes; prepare the change for an approved non-production or
  human-controlled deployment path instead.
- Keep `SET DEFINE OFF;` while executing application or PL/SQL source. A
  controlled wrapper may briefly enable substitution for validated positional
  configuration, then must disable it before source payloads. Use UTF-8 session
  settings when localized text or generated source is involved.
- For APEX exports, normalize `.apx` files to LF. Export and replacement never
  invoke validation; validation is a separate explicit verification step for
  application edits.
- Remember that SQLcl R0 expands SQLcl/OS capabilities; it does not grant
  Oracle privileges or make an action safe.

## Files, OS, network, and secrets

- Resolve exact paths; do not use broad recursive deletion or repository-wide
  overwrites.
- Put temporary files, generated helper scripts, staging exports, and rollback
  copies only under the repository's `scratch/` directory, and clean them up
  when the operation finishes.
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
