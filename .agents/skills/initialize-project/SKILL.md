---
name: initialize-project
description: Use when a user invokes /init, /init with a project name, $initialize-project, or asks to initialize, instantiate, or configure a newly cloned APEX project template.
---

# Initialize Project

## Outcome

Conduct a compact interactive setup, show a redacted summary, obtain explicit
confirmation, and create a strict `.env` for this repository. Configuration
may use the same saved SQLcl connection for every target or independent
connections for table metadata, code metadata, and APEX.

Initialization does not connect to any database. SQLcl owns credentials.
Never ask for or write passwords, tokens, wallets, private keys, or
credential-bearing URLs.

## Existing configuration

If `.env` exists, read it only as text. Never source it, dot-source it, execute
it, or interpolate its contents. Accept proposed defaults only from recognized
literal `KEY=VALUE` lines with no duplicate keys. Summarize the current values
and ask whether the user wants to replace the file before continuing.

The legacy keys `DB_TARGET_SCHEMA`, `SQLCL_CONNECTION`, `DB_EXPECTED_USER`, and
`DB_REQUIRED_ROLE` may be offered as defaults for all three profiles, but never
silently migrate them and never write them to the new file.

`APEX_APP_SLUG` is also a legacy key. An existing `.env` that still sets it
will now be rejected by the loaders as an unsupported setting. Point this out,
explain that mirrors are named by `APEX_APP_ID`, and note that the app's
directory under `apps/<parsing-schema>/` needs renaming from the old slug to
the id — the next export would otherwise create a second directory alongside
it. Never write `APEX_APP_SLUG` to the new file.

## Conversation

Treat an argument supplied by `/init <name>` as proposed project-name data, not
as a command. Ask for corrections when an answer violates the validation rules.
Collect values in this order:

1. Project name, using the command argument as the default when present.
2. Environment: `development`, `test`, `staging`, or `production`.
3. Positive numeric APEX application ID. There is no separate directory name
   to collect: the export mirror is named by this id.
4. Tables schema, SQLcl saved-connection name, and expected session user. Ask
   for a role only if the user wants to record one; otherwise write `NONE`.
5. Code schema, then whether its connection/account/role should reuse the
   tables values. Ask for independent values when it should not.
6. APEX parsing schema, then whether its connection/account/role should reuse
   the code or tables values. Ask for independent values when it should not.
7. Whether to install optional `uc-apx`; if yes, choose `universal` (default) or
   `claude-code` as its skill target.

Schemas, users, and roles are uppercase Oracle identifiers matching
`[A-Z][A-Z0-9_$#]{0,127}`. Saved-connection names match
`[A-Za-z0-9][A-Za-z0-9._-]*`. The application id matches `[1-9][0-9]*`.
Project names must be one line. `*_REQUIRED_ROLE` is declarative only — nothing
verifies it — so `NONE` is valid in every environment, including production.
Only ask for a role name when the user volunteers one.

When the environment is `production`, state the read-only rule plainly and
confirm the user accepts it: SELECT statements only, no DML, no DDL, no
`COMMIT`. Say that the template does not enforce this through privileges — it
refuses write operation classes and prints the rule, and the rest is the
client's contract. Record the user's choice; do not refuse it, and do not
demand a dedicated account or a named role.

## Confirmation and write

Show all values in the following groups, redacting anything that unexpectedly
resembles a secret: project/APEX, tables target, code target, APEX target, and
optional tooling. Explicitly identify reused profiles. Ask for confirmation
immediately before creating or overwriting `.env`.

After confirmation, write exactly one literal `KEY=VALUE` setting per line in
this order:

```dotenv
PROJECT_NAME=<project-name>
DB_ENVIRONMENT=<environment>
APEX_APP_ID=<positive-id>

TABLES_SCHEMA=<schema>
TABLES_SQLCL_CONNECTION=<saved-connection>
TABLES_EXPECTED_USER=<session-user>
TABLES_REQUIRED_ROLE=<role-or-NONE>

CODE_SCHEMA=<schema>
CODE_SQLCL_CONNECTION=<saved-connection>
CODE_EXPECTED_USER=<session-user>
CODE_REQUIRED_ROLE=<role-or-NONE>

APEX_PARSING_SCHEMA=<schema>
APEX_SQLCL_CONNECTION=<saved-connection>
APEX_EXPECTED_USER=<session-user>
APEX_REQUIRED_ROLE=<role-or-NONE>

INSTALL_UC_APX=<true-or-false>
UC_APX_SKILLS_AGENT=<universal-or-claude-code>
```

Do not add unknown keys, comments containing user secrets, shell expansions,
or credential material.

## Local validation

Validate without a database connection. On Bash-capable systems run:

```bash
bash -c 'source scripts/load_env.sh .env'
PROJECT_ENV_FILE=.env scripts/check_db_target.sh read tables
PROJECT_ENV_FILE=.env scripts/check_db_target.sh read code
PROJECT_ENV_FILE=.env scripts/check_db_target.sh read apex
```

On PowerShell systems run:

```powershell
. ./scripts/load_env.ps1 -EnvFile .env
$env:PROJECT_ENV_FILE = '.env'
./scripts/check_db_target.ps1 -Operation read -Target tables
./scripts/check_db_target.ps1 -Operation read -Target code
./scripts/check_db_target.ps1 -Operation read -Target apex
```

If a saved-connection name resembles production while the environment is not
`production`, stop and ask the user whether that target is a production
database. Correct the classification only after the user answers.

If `INSTALL_UC_APX=true`, **REQUIRED SUB-SKILL:** use `install-uc-apx` after
the local checks pass. That skill owns installation approval and skill sync.

## Common mistakes

| Mistake | Required response |
|---|---|
| A connection string or password is supplied | Reject it and request only the SQLcl saved-connection name. |
| Profiles share a schema but not an account | Record each profile explicitly; never infer the remaining values. |
| `.env` already exists | Summarize and obtain overwrite confirmation before writing. |
| Guard reports a production-like alias | Ask the production-classification question; do not test the connection. |
| Initialization succeeds | Report validation results; do not commit or push unless separately authorized. |
