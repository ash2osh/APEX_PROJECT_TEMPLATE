# Interactive Initialization and Database Target Profiles Design

## Goal

After cloning the template, a user can type `/init`, `/init <project-name>`,
or ask naturally to initialize the project. The agent conducts an interactive
conversation, creates a validated `.env`, and configures independent targets
for table metadata, code metadata, and the APEX parsing schema. All three
targets may reuse the same SQLcl connection and account or use different ones.

## Scope

This change adds a portable initialization skill, a Claude slash-command
entry point, the new three-profile environment contract, and complete routing
through the Bash, PowerShell, SQLcl, documentation, tests, and CI workflows.

It does not store credentials, create SQLcl saved connections, connect to a
database during initialization, create database users or roles, or install
`uc-apx` unless the user opts in and the existing installer skill obtains any
required external-install approval.

## Invocation and discovery

The canonical workflow lives at
`.agents/skills/initialize-project/SKILL.md`. It activates for:

- `/init`
- `/init <project-name>` such as `/init ash`
- `$initialize-project`
- Natural-language requests to initialize, instantiate, or configure the
  cloned template

`AGENTS.md` routes those requests to the canonical skill for portable agent
clients. `.claude/skills/initialize-project/SKILL.md` provides flat skill
discovery, and `.claude/commands/init.md` provides Claude's `/init` command.
The optional argument is treated as the proposed project name, not as shell
input.

## Interactive conversation

The agent asks compact questions in this order:

1. Project name, using the `/init` argument as the default when supplied.
2. Environment: development, test, staging, or production.
3. APEX application ID and filesystem-safe application slug.
4. Tables schema, SQLcl saved connection, expected session user, and—only for
   production—the required read-only role.
5. Code schema, followed by whether to reuse the tables connection/account/
   role. If not reused, ask for independent values.
6. APEX parsing schema, followed by whether to reuse either the code or tables
   connection/account/role. If not reused, ask for independent values.
7. Whether to opt into `uc-apx`, and which skill target (`universal` by
   default or `claude-code`).
8. A redacted summary and explicit confirmation before writing `.env`.

The agent never asks for or writes passwords, tokens, wallets, private keys,
or credential-bearing URLs. SQLcl remains the credential store.

If `.env` already exists, the agent safely reads only recognized literal
`KEY=VALUE` settings, summarizes the proposed changes, and asks before
overwriting. Existing single-profile settings can be proposed as defaults for
all three new profiles, but are not silently migrated.

After writing, the agent validates `.env` through the strict loader and runs
the pre-connect read guard for all three profiles. It does not establish a
database connection. If `INSTALL_UC_APX=true`, it then follows the existing
`install-uc-apx` skill.

## Environment contract

The committed `.env.example` contains no secrets and defines:

```dotenv
PROJECT_NAME=example
DB_ENVIRONMENT=development
APEX_APP_ID=100
APEX_APP_SLUG=example-app

TABLES_SCHEMA=EXAMPLE_DATA
TABLES_SQLCL_CONNECTION=dev1_EXAMPLE_DATA
TABLES_EXPECTED_USER=EXAMPLE_DATA
TABLES_REQUIRED_ROLE=NONE

CODE_SCHEMA=EXAMPLE_CODE
CODE_SQLCL_CONNECTION=dev1_EXAMPLE_CODE
CODE_EXPECTED_USER=EXAMPLE_CODE
CODE_REQUIRED_ROLE=NONE

APEX_PARSING_SCHEMA=EXAMPLE
APEX_SQLCL_CONNECTION=dev1_EXAMPLE
APEX_EXPECTED_USER=EXAMPLE
APEX_REQUIRED_ROLE=NONE

INSTALL_UC_APX=false
UC_APX_SKILLS_AGENT=universal
```

For a single-schema project, the schema, connection, expected-user, and role
values may be identical across all profiles. `NONE` is allowed only outside
production. Every profile is explicit—loaders never fill missing values from
the process environment or silently inherit another profile.

The old `DB_TARGET_SCHEMA`, `SQLCL_CONNECTION`, `DB_EXPECTED_USER`, and
`DB_REQUIRED_ROLE` variables are removed from the active contract and rejected
by the strict loaders.

## Validation and target selection

`scripts/load_env.sh` and `scripts/load_env.ps1` allowlist and require every
new key, reject duplicates, preserve literal values, and apply the existing
identifier/path/enum validation to each profile.

The pre-connect guard becomes target-aware:

```text
check_db_target.sh  <read|write> <tables|code|apex>
check_db_target.ps1 -Operation <read|write> -Target <tables|code|apex>
```

It maps the selected profile into the generic schema, connection, expected
user, and role checks. Production-like connection-name detection and the
always-read-only production policy apply independently to all three targets.

The post-connect `verify_db_access.sql` remains generic and receives the
selected profile values as validated positional arguments.

## Application export

`export_apps.sh` and `export_apps.ps1` use only the APEX profile:

- `APEX_PARSING_SCHEMA`
- `APEX_SQLCL_CONNECTION`
- `APEX_EXPECTED_USER`
- `APEX_REQUIRED_ROLE`

The app mirror remains
`apps/<APEX_PARSING_SCHEMA>/<APEX_APP_SLUG>`. Export continues to stage under
`scratch/`, require `application.apx` and `.apex/apexlang.json`, normalize only
staged files, refuse dirty destinations, replace the exact mirror, and invoke
no validation.

## Database metadata backup

`backup_db.sh` and `backup_db.ps1` perform both metadata passes before any
mirror replacement:

- Tables pass: connect through the tables profile and export `TABLE` metadata
  from `TABLES_SCHEMA`.
- Code pass: connect through the code profile and export `VIEW`, `PACKAGE`,
  `PACKAGE BODY`, `PROCEDURE`, `FUNCTION`, and `TRIGGER` metadata from
  `CODE_SCHEMA`.

`backup_db.sql` receives an additional validated scope argument (`tables` or
`code`), generates a scope-specific driver, and writes
`manifest-tables.txt` or `manifest-code.txt`.

If both profiles use the same schema, both passes write into one staged
`database/<schema>` tree and that tree is replaced once. If schemas differ,
each staged schema tree is replaced independently after both SQLcl passes and
all manifests succeed. A preflight Git-status check rejects any dirty target
before the first database connection, while `replace_mirror` retains its own
double dirty check and rollback protection.

No table data, sequences, grants, synonyms, materialized views, or other new
object classes are added by this change.

## Documentation

`README.md`, `agents.md`, `app_context/README.md`, the production safety
guide, the skill index, and optional-tool guidance describe the three target
profiles and `/init` flow. Documentation explicitly states that profiles may
share values, credentials do not belong in `.env`, production remains
read-only, and app export validation is separate.

## Error handling and safety

- Invalid or incomplete answers are corrected conversationally before write.
- Existing `.env` is never overwritten without confirmation.
- Values are serialized literally as one allowlisted `KEY=VALUE` per line.
- Connection names are never guessed or tested by connecting during init.
- A production profile requires a non-owner expected user and named role.
- Production-like aliases with non-production classification stop and require
  user clarification.
- Initialization never commits or pushes unless the user separately asks;
  this implementation task already has explicit commit-and-push approval.

## Testing

Regression coverage will prove:

- New variables are required and old variables are rejected.
- All three profiles may contain identical values.
- All three profiles may contain different values.
- Literal `.env` values are not executed.
- Target-aware production detection, role requirements, and write blocking
  work independently for tables, code, and APEX.
- App export statically routes only through the APEX profile.
- Database backup statically routes table and code scopes correctly.
- Same-schema backup replacement is deduplicated by implementation-level unit
  or fixture testing where practical.
- `/init` discovery files and canonical skill exist and contain valid skill
  frontmatter.
- No empty legacy Claude skill directories remain.
- Linux repository checks, Python checks, link checks, skill validation,
  PowerShell parsing, and native Windows tests remain in CI.

Live Oracle export is outside local verification and must be identified as a
boundary in the final handoff.
