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

## Prerequisites

Do this first, before the conversation, and never let it block initialization.

Detect what is already present; never reinstall something that answers:

| Requirement | Detect with |
|---|---|
| Python 3.10+ | `python3 --version` |
| Node.js | `node --version` |
| uv | `uv --version` |
| Graphify | `graphify --version` |
| SQLcl | `sql -v` |
| Git | `git --version` |
| perl | `perl --version` |

Report exactly what is missing, then ask for approval before installing
anything. Install only what the user approves, into user-controlled locations
on `PATH`, never into this repository.

Graphify is the one case with a known-good command, because its distribution
name (`graphifyy`) differs from its command name (`graphify`) and its SQL
parser is a separate package:

```bash
uv tool install graphifyy --with tree-sitter-sql
python3 setup_graphify_apx.py
```

If `graphify` already answers but `.sql` sources are not being indexed, its
SQL parser is missing; reinstall with `uv tool install graphifyy --with
tree-sitter-sql --force`. Do not run `graphify extract` during initialization —
`apps/` and `database/` are still empty, and extraction belongs after the first
export.

For Python, Node.js, uv, SQLcl, and perl, ask which platform package manager
the user wants to use and follow that tool's own documented command. Do not
invent package-manager commands, guess a download URL, or select a release
asset on the user's behalf.

If the user declines an installation, record it, continue, and list what is
still missing in the final report. A missing prerequisite never prevents
writing `.env`.

## Existing configuration

If `.env` exists, read it only as text. Never source it, dot-source it, execute
it, or interpolate its contents. Accept proposed defaults only from recognized
literal `KEY=VALUE` lines with no duplicate keys. Summarize the current values
and ask whether the user wants to replace the file before continuing.

The legacy keys `DB_TARGET_SCHEMA`, `SQLCL_CONNECTION`, and `DB_EXPECTED_USER`
may be offered as defaults for all three profiles, but never silently migrate
them and never write them to the new file. `DB_REQUIRED_ROLE`,
`TABLES_REQUIRED_ROLE`, `CODE_REQUIRED_ROLE`, and `APEX_REQUIRED_ROLE` are
obsolete unsupported settings; point them out and do not copy them forward.

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
3. One or more positive numeric APEX application IDs as strict CSV. There is
   no separate directory name to collect: each export mirror is named by its id.
4. Tables schema, object-name prefixes, SQLcl saved-connection name, and
   expected session user.
5. Code schema and prefixes, then whether its connection/account should reuse
   the tables values. Ask for independent values when it should not.
6. APEX parsing schema, then whether its connection/account should reuse the
   code or tables values. Ask for independent values when it should not.
7. Whether to install optional `uc-apx`; if yes, choose `universal` (default) or
   `claude-code` as its skill target.

Schemas and users are uppercase Oracle identifiers matching
`[A-Z][A-Z0-9_$#]{0,127}`. Saved-connection names match
`[A-Za-z0-9][A-Za-z0-9._-]*`. Application IDs match strict CSV of
`[1-9][0-9]*`; prefixes match strict CSV of uppercase Oracle identifier
prefixes, or `*` alone for all supported objects. CSV values have no spaces,
blank entries, or duplicates, and `*` cannot be combined with prefixes.
Project names must be one line.

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
APEX_APP_ID=<positive-id-csv>

TABLES_SCHEMA=<schema>
TABLES_PREFIXES=<prefix-csv-or-*>
TABLES_SQLCL_CONNECTION=<saved-connection>
TABLES_EXPECTED_USER=<session-user>

CODE_SCHEMA=<schema>
CODE_PREFIXES=<prefix-csv-or-*>
CODE_SQLCL_CONNECTION=<saved-connection>
CODE_EXPECTED_USER=<session-user>

APEX_PARSING_SCHEMA=<schema>
APEX_SQLCL_CONNECTION=<saved-connection>
APEX_EXPECTED_USER=<session-user>

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
| Initialization succeeds | Report validation results and any prerequisite the user declined; do not commit or push unless separately authorized. |
| A prerequisite is missing | Report it and ask before installing; never install without approval, and never block `.env` on it. |
