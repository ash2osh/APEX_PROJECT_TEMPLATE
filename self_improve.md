# Self-Improvement Notes

This file is the durable learning log for this project. It supplements
`AGENTS.md`; it does not override direct user, system, or project instructions.

## At the Start of Work

1. Read `AGENTS.md` and this file before making a non-trivial change.
2. Inspect the current Git status and recent history so stale snapshots,
   generated output, or earlier assumptions are not mistaken for current
   behavior.
3. For `.apx` (APEXlang) work, verify syntax and line-ending assumptions with
   the actual parser/compiler. For SQLcl or database work, confirm the exact
   requested connection before executing anything.
4. Prefer the smallest complete correction and verify it with the narrowest
   relevant check before broader validation. Edit APEX source in place under
   `apps/`; keep generated or modified SQL and PL/SQL deployment scripts under
   `ai_generate/YYYY-MM-DD/`; never hand-edit the generated `database/` mirror.

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
- Task-by-task status logs or rules already stated authoritatively in `AGENTS.md`.

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

### Never write a literal `;` inside a string literal that SQLcl must return

- Trigger: generating a SQL driver script by spooling query output, where each
  generated statement has to end in a semicolon.
- Evidence: `scripts/backup_db.sql` built its terminator as `... FROM DUAL;'`.
  Against Oracle 23ai Free with SQLcl 26.1 every one of those seven SELECTs
  returned no rows, printed no error, and SQLcl exited 0 — the generated
  driver was empty, the mirror was empty, and the backup reported success.
  Rebuilding the terminator as `... FROM DUAL' || CHR(59)` returned all rows.
  SQLcl's client-side statement splitter finds the `;` before it knows the
  character is inside a quoted literal.
- Preferred behavior: build any semicolon that has to survive into generated
  SQL with `CHR(59)`. Treat "query returned nothing and SQLcl exited 0" as a
  parsing problem, not an empty schema.
- Verification: `scripts/test_template.sh` asserts all seven terminators use
  `CHR(59)` and that no `FROM DUAL;'` remains in `scripts/backup_db.sql`.

### Give SQLcl an empty file as standard input, never a pipe or `/dev/null`

- Trigger: running `scripts/export_apps.*` or `scripts/backup_db.*` from any
  non-interactive caller on Windows.
- Evidence: SQLcl 26.1 builds a JLine console over stdin at startup. Given a
  descriptor it cannot probe — a pipe, or the Windows `NUL` device that Git
  Bash maps `/dev/null` to — it aborts with
  `java.io.IOException: Incorrect function` before running the script, and
  still exits 0. Redirecting stdin from an empty regular file works on every
  platform tested.
- Preferred behavior: keep the `SQLCL_STDIN` empty-file redirect in the shell
  wrappers and the `Invoke-Sqlcl` helper (`scripts/invoke_sqlcl.ps1`) in the
  PowerShell wrappers. Windows PowerShell 5.1 has no `<` operator for native
  commands, which is why that helper uses `Start-Process`.
- Verification: `scripts/test_template.sh` asserts both shell wrappers define
  and use `SQLCL_STDIN`.

### A completeness guard must fail closed, and must tolerate CRLF

- Trigger: comparing a spooled manifest's object counts against files written.
- Evidence: SQLcl spools with the platform's line terminator, so on Windows
  every manifest line arrived with a trailing CR. The numeric test rejected
  every count, `expected` stayed 0, and the guard compared 0 against 0 —
  waving an empty mirror through and replacing a good one.
- Preferred behavior: strip CR before parsing spooled output, and refuse to
  proceed when a manifest yields no parsable counts at all.
- Verification: `scripts/test_backup_orchestration.sh` runs the complete and
  incomplete cases with both LF and CRLF manifests, plus a manifest with no
  readable counts.

### Avoid dynamic reads through the Windows PowerShell environment provider

- Trigger: the native Windows PowerShell 5.1 suite ran in a process whose
  environment block contained both `Path` and `PATH`.
- Evidence: `Get-Item Env:PROJECT_NAME` threw `An item with the same key has
  already been added`, even though `PROJECT_NAME` itself was unique; the .NET
  process environment API returned the value normally.
- Preferred behavior: use `[Environment]::GetEnvironmentVariable(...,
  "Process")` for dynamic environment-variable reads in PowerShell loaders.
- Verification: `scripts/test_template.ps1` shadows environment-provider
  `Get-Item` reads with the observed failure and confirms the real loader still
  loads and validates the file under PowerShell 7 and Windows PowerShell 5.1.

### Do not add a second file whose name differs only in case

- Trigger: `AGENTS.md` (entry point) and `agents.md` (full conventions) were
  both tracked.
- Evidence: on Windows and default macOS only one can exist on disk, so a
  fresh clone reports the other as modified before any work starts, and an
  agent reading one silently gets the other.
- Preferred behavior: keep one `AGENTS.md`. Check `git ls-files | sort -f` for
  case collisions before adding a file whose name resembles an existing one.
- Verification: `scripts/test_template.sh` reads the production instruction
  from `AGENTS.md`; `scripts/check_local_links.py` resolves every local link.

### Use case-sensitive PowerShell regex operators for uppercase contracts

- Trigger: validating `.env` setting names, Oracle identifiers, and object
  prefixes that must be uppercase.
- Evidence: PowerShell's `-match` and `-notmatch` operators are case-insensitive
  by default, so the loader accepted lowercase keys, schemas, users, and
  prefixes while the Bash loader rejected them.
- Preferred behavior: use `-cmatch` or `-cnotmatch` whenever letter case is part
  of a cross-platform input contract; keep case-insensitive matching explicit
  only where both cases are intentionally allowed.
- Verification: `scripts/test_template.ps1` and `scripts/test_template.sh`
  reject lowercase setting names, Oracle identifiers, and prefixes.
