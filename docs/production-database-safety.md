# Production database safety

Production access for coding agents is always read-only. A request to change
production does not override this policy; prepare scripts for a separately
controlled deployment instead.

## Required identity model

Use a dedicated login that does not own application objects. Set these values
in the local `.env`:

```dotenv
DB_ENVIRONMENT=production
DB_TARGET_SCHEMA=APP_OWNER
DB_EXPECTED_USER=APP_AGENT_RO
DB_REQUIRED_ROLE=APP_AGENT_PROD_RO
SQLCL_CONNECTION=primary-prod-APP_AGENT_RO
```

`DB_REQUIRED_ROLE` is the project's production role contract. A database
administrator creates and audits it; this template never creates users,
roles, or grants. The role may contain only the read privileges needed for
database metadata export, such as narrowly scoped `SELECT` grants and the
minimum catalog-read privileges required by the installed Oracle version.
It must not confer DML, DDL, grant, job, file, network, or administration
capabilities. Grant the role and privileges without `ADMIN OPTION` or
`GRANT OPTION`. Avoid broad privileges when direct object grants are practical.

Keep passwords and wallet details in SQLcl's saved connection store. Never put
them in `.env`.

## Two-stage enforcement

The shell and PowerShell wrappers run `check_db_target` before connecting. It
blocks every production write operation, requires a non-owner account and
role, and stops when a connection name resembles production but is classified
otherwise. In that ambiguous case, the agent must ask the user whether the
database is production.

After connecting, `verify_db_access.sql` checks the actual session user,
database/service identity, enabled role, object ownership, system privileges,
and direct or role-based object grants. Export stops before reading metadata if
the session has write-capable privileges.

Run the read-only audit periodically and after any grant change:

```bash
sql -S -noupdates -name primary-prod-APP_AGENT_RO \
  @scripts/audit_production_access.sql APP_OWNER APP_AGENT_RO APP_AGENT_PROD_RO
```

Review its identity, enabled roles, system privileges, and any findings. Zero
write-capability findings is required.

## Export behavior

Application and database exports stage under `scratch/`. They read metadata,
never export table data, and replace only the exact target after the export
succeeds and Git confirms that target has no local changes. Application export
does not invoke validation; validation is a separate operation.

Oracle documents SQLcl APEX application export using the workspace parsing
schema. That conflicts with this template's production requirement for a
dedicated non-owner account. Do not grant owner access,
`APEX_ADMINISTRATOR_ROLE`, or DBA access to an agent to work around the
conflict. Keep the reviewed APEX artifact exported from development/staging as
the source of truth, or use a separately approved read-only export mechanism
provided by your platform. The production database metadata backup can still
run through the dedicated read-only account.
