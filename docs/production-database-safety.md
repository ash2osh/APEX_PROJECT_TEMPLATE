# Production database safety

Production access for coding agents is **read-only by instruction**.

This template does not audit privileges, require a dedicated account, or
verify roles and grants. It states the rule, refuses write operation classes
at the wrapper level, and prints the rule to the operator before and after
connecting. Everything past that point is your contract with the client.

## The rule

When `DB_ENVIRONMENT=production`:

- Run **SELECT statements only**.
- Never run `INSERT`, `UPDATE`, `DELETE`, `MERGE`, or any other DML.
- Never run `CREATE`, `ALTER`, `DROP`, `TRUNCATE`, or any other DDL.
- Never `COMMIT`.
- A request to change production does not override this. Prepare the change
  under `ai_generate/YYYY-MM-DD/` and deploy it through a separately approved,
  human-controlled path.

## Configuration

```dotenv
DB_ENVIRONMENT=production

TABLES_SCHEMA=APP_DATA
TABLES_PREFIXES=APP_,COMMON_
TABLES_EXPECTED_USER=APP_DATA
TABLES_SQLCL_CONNECTION=primary-prod-APP_DATA

CODE_SCHEMA=APP_CODE
CODE_PREFIXES=APP_,COMMON_
CODE_EXPECTED_USER=APP_CODE
CODE_SQLCL_CONNECTION=primary-prod-APP_CODE

APEX_PARSING_SCHEMA=APP
APEX_EXPECTED_USER=APP
APEX_SQLCL_CONNECTION=primary-prod-APP
```

The obsolete `TABLES_REQUIRED_ROLE`, `CODE_REQUIRED_ROLE`, and
`APEX_REQUIRED_ROLE` settings are unsupported. Expected-user values are
post-connect `SESSION_USER` assertions, not privilege or role declarations.

Using a dedicated read-only database account is still the strongest thing you
can do, and it is entirely compatible with this template — the difference is
that the scripts no longer require or check one. If you want the database
itself to enforce read-only rather than trusting the client, have a DBA grant
the agent account only `SELECT`, and nothing else.

Keep passwords and wallet details in SQLcl's saved connection store. Never put
them in `.env`.

## What the template still does

Before connecting, `scripts/check_db_target.*`:

- refuses any `write` operation class when `DB_ENVIRONMENT=production`
- prints the read-only instruction to stderr
- stops when a saved-connection name looks like production
  (`prod`, `prd`, `production`, `live`) but `.env` classifies it otherwise, so
  a mislabeled target cannot be used by accident

After connecting, `scripts/verify_db_access.sql`:

- prints the real session user, current schema, database name, and service
- fails when the session user is not the configured `*_EXPECTED_USER`
  (`ORA-20001`)
- fails when the target schema does not exist or is not visible (`ORA-20014`)
- fails when the database or service name resembles production but the
  environment is not classified as production (`ORA-20002`)
- fails when the current schema is not the target schema for an owner login
  (`ORA-20009`)
- prints the production read-only banner

That is the whole of it. There is no privilege allowlist, no role check, no
ownership check, and no grant audit.

## Export behavior

Application and database exports stage under `scratch/`. They read metadata,
never export table data, and replace only exact targets after every required
export succeeds and Git confirms those targets have no local changes. Database
backup completes its table and code passes before replacing either schema
mirror. Application export does not invoke validation; validation is a
separate operation.

Because there is no non-owner requirement, an APEX application can be exported
in production through its parsing schema, which is the account Oracle documents
for `apex export`. Where you can, prefer keeping the reviewed APEX artifact
exported from development or staging as the source of truth, so production
application export is not needed at all.

Do not grant `APEX_ADMINISTRATOR_ROLE` or DBA access to an agent. That has
nothing to do with the checks removed here — an application export never needs
it.
