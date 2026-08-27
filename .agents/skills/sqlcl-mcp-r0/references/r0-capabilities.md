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
