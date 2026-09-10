# Template Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close all 28 verified defects from the 2026-09-09 template review, restoring the three promises the template makes — Bash/PowerShell parity, all-or-nothing mirror replacement, and guards that fail closed.

**Architecture:** Six independent phases, each shippable on its own. Phases 1–3 touch the shell/SQL automation and need no Graphify. Phases 4–5 touch the Python knowledge-graph integration. Phase 6 is documentation and hygiene. No new runtime dependencies; no change to the production read-only model.

**Tech Stack:** Bash 4+, Windows PowerShell 5.1 / PowerShell 7, Oracle SQLcl scripts (SQL\*Plus-compatible), Python 3.10+ standard library, GitHub Actions.

**Spec:** [`../specs/2026-09-09-template-hardening-design.md`](../specs/2026-09-09-template-hardening-design.md)

> **Scope note.** This is one plan covering six subsystems because that is what was asked for. Each phase produces working, testable software on its own and can be shipped or deferred independently — if you would rather run them as separate efforts, split at the phase boundaries, not inside them.

> **One decision to confirm before Phase 6.** The plan resolves F1 toward *Graphify is optional but strongly recommended*, correcting `README.md`. If Graphify is meant to be hard-required, Task 14 inverts and the `graphify-out/graph.json` gating in `.agents/rules/graphify.md` must be removed instead. Confirm before starting Task 14.

## Global Constraints

- **Pair parity.** Every behavior change to a `.sh` file requires the identical change to its `.ps1` sibling, and an assertion in **both** `scripts/test_template.sh` and `scripts/test_template.ps1`.
- **PowerShell floor: Windows PowerShell 5.1 and PowerShell 7.** No .NET 5+ APIs (`SHA256::HashData`, `Convert::ToHexString`, `File.ReadAllLinesAsync`). Use `-cmatch` / `-cnotmatch` wherever letter case is part of the input contract. CI enforces this with the PSScriptAnalyzer profile `win-48_x64_10.0.17763.0_5.1.17763.316_x64_4.0.30319.42000_framework`.
- **Python floor: 3.10** (the extractor uses `str | None` in runtime signatures). Standard library only — the extractor must stay dependency-free because `_patched_dispatch` removes a `".apx": "sql"` dependency gate.
- **`.apx` files are LF-only** (`.gitattributes`: `*.apx text eol=lf`).
- **Never hand-edit `database/`.** It is a generated mirror.
- **Temporary files only under `scratch/`.** Never `/tmp`, never the repo root.
- **`.env` is parsed as data, never executed.**
- **Both suites must stay green** after every task: `bash scripts/test_template.sh` and `pwsh -NoProfile -File scripts/test_template.ps1`.
- **Commit message trailer** on every commit: `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>`.
- **Do not push.** Commit locally only; delivery is a separate authorization.

---

# Phase 1 — Configuration loaders

Fixes F2, F3, F19, F20, F25, F28. No database, no Graphify. Highest user-facing impact per line changed.

---

### Task 1: `.env` whitespace parity

**Files:**
- Modify: `scripts/load_env.sh:17-25`, `scripts/load_env.sh:62-74`
- Test: `scripts/test_template.sh` (after the `assert_env_rejected` block, ~line 238), `scripts/test_template.ps1` (after the `Assert-EnvTextRejected` calls, ~line 115)

**Interfaces:**
- Consumes: nothing.
- Produces: `load_env.sh` skips whitespace-only lines and rejects whitespace-only values, matching `load_env.ps1`. No new functions or variables are exported.

- [ ] **Step 1: Write the failing Bash tests**

Add to `scripts/test_template.sh` immediately after the last `assert_env_rejected` line (the `CODE_PREFIXES=SAMPLE_,` case):

```bash
# A whitespace-only line is not a configuration error. PowerShell's
# IsNullOrWhiteSpace already skips one, so Bash must too -- otherwise a .env
# authored on Windows loads there and fails on Linux.
BLANK_LINE_ENV_FILE="$TEST_ROOT/blank-line.env"
{ cat "$ENV_FILE"; printf '   \n\t\n'; } > "$BLANK_LINE_ENV_FILE"
bash -c 'source "$1" "$2"' _ "$REPO_ROOT/scripts/load_env.sh" "$BLANK_LINE_ENV_FILE" \
  || fail "environment loader rejected a whitespace-only line"

# A whitespace-only value IS a configuration error, and both loaders must agree.
assert_env_rejected "$ENV_FILE" 's/^PROJECT_NAME=.*/PROJECT_NAME=   /' \
  "environment loader accepted a whitespace-only value"
```

- [ ] **Step 2: Write the failing PowerShell tests**

`scripts/test_template.ps1` has `Assert-EnvTextRejected` but no accepting counterpart. Add this helper immediately after the `Assert-EnvTextRejected` function definition:

```powershell
  function Assert-EnvTextAccepted([string]$Text, [string]$Message) {
    $validFile = Join-Path $testRoot "valid-$([Guid]::NewGuid().ToString('N')).env"
    [System.IO.File]::WriteAllText($validFile, $Text)
    try {
      . (Join-Path $PSScriptRoot "load_env.ps1") -EnvFile $validFile
    } catch {
      Assert-True $false "$Message : $($_.Exception.Message)"
    }
  }
```

Then add these two assertions after the last `Assert-EnvTextRejected` call:

```powershell
  Assert-EnvTextAccepted ($envText + "   `n`t`n") "PowerShell loader rejected a whitespace-only line"
  Assert-EnvTextRejected ($envText.Replace('PROJECT_NAME=$(throw should-not-run)', 'PROJECT_NAME=   ')) "PowerShell loader accepted a whitespace-only value"
```

- [ ] **Step 3: Run both suites to verify the Bash half fails**

Run: `bash scripts/test_template.sh`
Expected: FAIL with `environment loader rejected a whitespace-only line`

Run: `pwsh -NoProfile -File scripts/test_template.ps1`
Expected: PASS — PowerShell already has the target behavior. This asymmetry is the finding.

- [ ] **Step 4: Fix the whitespace-only line in `load_env.sh`**

Replace lines 19-21:

```bash
  case "$project_env_line" in
    ''|'#'*) continue ;;
  esac
```

with:

```bash
  case "$project_env_line" in
    '#'*) continue ;;
  esac
  # A line of only whitespace is not a configuration error. PowerShell's
  # IsNullOrWhiteSpace already skips one, so Bash must agree, or a .env
  # authored on Windows loads there and fails on Linux.
  if [ -z "${project_env_line//[[:space:]]/}" ]; then
    continue
  fi
```

- [ ] **Step 5: Fix the whitespace-only value in `load_env.sh`**

Replace line 70:

```bash
  if [ "$project_env_seen_present" != true ] || [ -z "${!project_env_key:-}" ]; then
```

with:

```bash
  project_env_value="${!project_env_key:-}"
  if [ "$project_env_seen_present" != true ] || [ -z "${project_env_value//[[:space:]]/}" ]; then
```

- [ ] **Step 6: Run both suites to verify they pass**

Run: `bash scripts/test_template.sh && pwsh -NoProfile -File scripts/test_template.ps1`
Expected: both print their `PASS:` lines and exit 0.

- [ ] **Step 7: Commit**

```bash
git add scripts/load_env.sh scripts/test_template.sh scripts/test_template.ps1
git commit -m "$(cat <<'EOF'
fix: make the Bash and PowerShell env loaders agree on whitespace

A whitespace-only line was rejected by Bash and skipped by PowerShell; a
whitespace-only value was accepted by Bash and rejected by PowerShell. A .env
authored on one platform could fail to load on the other. PowerShell's
behavior wins in both directions.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: Reject unquoted inline comments

**Files:**
- Modify: `scripts/load_env.sh:45-49`, `scripts/load_env.ps1:38-41`
- Test: `scripts/test_template.sh`, `scripts/test_template.ps1`

**Interfaces:**
- Consumes: Task 1's loaders.
- Produces: both loaders reject an **unquoted** value containing whitespace followed by `#`, and both fix the one-character-quote crash. Quoting a value is the documented escape hatch for a literal `#`.

- [ ] **Step 1: Write the failing tests**

Add to `scripts/test_template.sh` after Task 1's assertions:

```bash
# Values are parsed literally, so an unquoted inline comment would be stored
# verbatim -- silently, for PROJECT_NAME, which has no format rule of its own.
assert_env_rejected "$ENV_FILE" 's/^PROJECT_NAME=.*/PROJECT_NAME=inventory # the good one/' \
  "environment loader accepted an inline comment on an unvalidated setting"
assert_env_rejected "$ENV_FILE" 's/^DB_ENVIRONMENT=.*/DB_ENVIRONMENT=development # active/' \
  "environment loader accepted an inline comment on a validated setting"

# Quoting is the escape hatch for a value that really contains '#'.
QUOTED_HASH_ENV_FILE="$TEST_ROOT/quoted-hash.env"
sed -E 's/^PROJECT_NAME=.*/PROJECT_NAME="release #4"/' "$ENV_FILE" > "$QUOTED_HASH_ENV_FILE"
QUOTED_HASH_VALUE="$(bash -c 'source "$1" "$2"; printf "%s" "$PROJECT_NAME"' \
  _ "$REPO_ROOT/scripts/load_env.sh" "$QUOTED_HASH_ENV_FILE")"
test "$QUOTED_HASH_VALUE" = "release #4" \
  || fail "environment loader mangled a quoted value containing '#': $QUOTED_HASH_VALUE"

# A one-character quote must not crash either loader.
assert_env_rejected "$ENV_FILE" 's/^PROJECT_NAME=.*/PROJECT_NAME="/' \
  "environment loader accepted a one-character quote as a value"
```

Add to `scripts/test_template.ps1` after Task 1's assertions:

```powershell
  Assert-EnvTextRejected ($envText.Replace('PROJECT_NAME=$(throw should-not-run)', 'PROJECT_NAME=inventory # the good one')) "PowerShell loader accepted an inline comment on an unvalidated setting"
  Assert-EnvTextRejected ($envText.Replace("DB_ENVIRONMENT=development", "DB_ENVIRONMENT=development # active")) "PowerShell loader accepted an inline comment on a validated setting"
  Assert-EnvTextAccepted ($envText.Replace('PROJECT_NAME=$(throw should-not-run)', 'PROJECT_NAME="release #4"')) "PowerShell loader rejected a quoted value containing '#'"
  Assert-True ($env:PROJECT_NAME -eq 'release #4') "PowerShell loader mangled a quoted value containing '#'"
  Assert-EnvTextRejected ($envText.Replace('PROJECT_NAME=$(throw should-not-run)', 'PROJECT_NAME="')) "PowerShell loader accepted a one-character quote as a value"
```

- [ ] **Step 2: Run both suites to verify they fail**

Run: `bash scripts/test_template.sh`
Expected: FAIL with `environment loader accepted an inline comment on an unvalidated setting`

Run: `pwsh -NoProfile -File scripts/test_template.ps1`
Expected: FAIL on the same assertion. The one-character-quote case fails differently — PowerShell throws `ArgumentOutOfRangeException` from `Substring(1, -1)` rather than the loader's own error, which still registers as rejected; it is the quoted-`#` case that fails there.

- [ ] **Step 3: Implement in `load_env.sh`**

Replace lines 45-49:

```bash
  if [[ "$project_env_value" == \"*\" && "$project_env_value" == *\" ]]; then
    project_env_value="${project_env_value:1:${#project_env_value}-2}"
  elif [[ "$project_env_value" == \'*\' && "$project_env_value" == *\' ]]; then
    project_env_value="${project_env_value:1:${#project_env_value}-2}"
  fi
```

with:

```bash
  project_env_quoted=false
  if [ "${#project_env_value}" -ge 2 ]; then
    if [[ "$project_env_value" == \"*\" ]] || [[ "$project_env_value" == \'*\' ]]; then
      project_env_value="${project_env_value:1:${#project_env_value}-2}"
      project_env_quoted=true
    fi
  fi
  # Values are parsed literally, so an unquoted inline comment would be stored
  # verbatim. For the settings with a format rule that surfaces as a confusing
  # error; for PROJECT_NAME, which has none, it is stored silently.
  if [ "$project_env_quoted" != true ] && [[ "$project_env_value" =~ [[:space:]]# ]]; then
    project_env_fail "$project_env_key has an inline comment; .env values are parsed literally, so put the comment on its own line, or quote the value to keep a literal '#'"
    return 1 2>/dev/null || exit 1
  fi
```

Then add `project_env_quoted` to the `unset` list on line 156-158:

```bash
unset project_env_line project_env_key project_env_value project_env_required
unset project_env_seen_keys project_env_seen_key project_env_seen_present
unset project_env_prefix_items project_env_prefix_item project_env_quoted
```

- [ ] **Step 4: Implement in `load_env.ps1`**

Replace lines 38-41:

```powershell
  if (($projectEnvValue.StartsWith('"') -and $projectEnvValue.EndsWith('"')) -or
      ($projectEnvValue.StartsWith("'") -and $projectEnvValue.EndsWith("'"))) {
    $projectEnvValue = $projectEnvValue.Substring(1, $projectEnvValue.Length - 2)
  }
```

with:

```powershell
  # The length guard matters: a one-character value of '"' satisfies both
  # StartsWith and EndsWith, and Substring(1, -1) throws.
  $projectEnvQuoted = $false
  if ($projectEnvValue.Length -ge 2 -and
      (($projectEnvValue.StartsWith('"') -and $projectEnvValue.EndsWith('"')) -or
       ($projectEnvValue.StartsWith("'") -and $projectEnvValue.EndsWith("'")))) {
    $projectEnvValue = $projectEnvValue.Substring(1, $projectEnvValue.Length - 2)
    $projectEnvQuoted = $true
  }
  if (-not $projectEnvQuoted -and $projectEnvValue -match '\s#') {
    throw "project environment error: $projectEnvKey has an inline comment; .env values are parsed literally, so put the comment on its own line, or quote the value to keep a literal '#'"
  }
```

Add `projectEnvQuoted` to the `Remove-Variable` list at line 100-103:

```powershell
Remove-Variable -Name projectEnvRepoRoot, projectEnvSeen, projectEnvAllowed,
  projectEnvRequired, projectEnvLine, projectEnvKey, projectEnvValue,
  projectEnvPrefixValue, projectEnvPrefixItem, projectEnvQuoted `
  -ErrorAction SilentlyContinue
```

- [ ] **Step 5: Run both suites to verify they pass**

Run: `bash scripts/test_template.sh && pwsh -NoProfile -File scripts/test_template.ps1`
Expected: both exit 0.

- [ ] **Step 6: Document the rule in `.env.example`**

Add after line 2 (`# Never store passwords...`):

```dotenv
# Values are parsed literally. An inline comment is rejected -- put comments on
# their own line. To keep a literal '#' inside a value, quote the whole value.
```

- [ ] **Step 7: Commit**

```bash
git add scripts/load_env.sh scripts/load_env.ps1 scripts/test_template.sh scripts/test_template.ps1 .env.example
git commit -m "$(cat <<'EOF'
fix: reject unquoted inline comments in .env values

PROJECT_NAME is the one setting with no format rule, so an inline comment was
stored verbatim and silently. Validated settings failed with a message that
never mentioned comments. Both loaders now reject an unquoted value containing
whitespace followed by '#', and quoting is the escape hatch.

Also guards quote-stripping against a one-character value, which threw
ArgumentOutOfRangeException in PowerShell.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: Resolve a relative `PROJECT_ENV_FILE` against the repository root

**Files:**
- Modify: `scripts/load_env.sh:4`, `scripts/load_env.ps1:14-18`
- Test: `scripts/test_template.sh`, `scripts/test_template.ps1`

**Interfaces:**
- Consumes: Task 2's loaders.
- Produces: both loaders accept a relative `PROJECT_ENV_FILE` from any working directory. `load_env.sh` gains a `project_env_repo_root` internal, unset before it returns.

- [ ] **Step 1: Write the failing tests**

Add to `scripts/test_template.sh`:

```bash
# README.md documents `PROJECT_ENV_FILE=.env.other scripts/export_apps.sh`.
# A relative path must not depend on the caller's working directory.
RELATIVE_ENV_NAME=".env.relative-test"
cp "$ENV_FILE" "$REPO_ROOT/$RELATIVE_ENV_NAME"
relative_env_status=0
( cd "$TEST_ROOT" && bash -c 'source "$1" "$2"' \
    _ "$REPO_ROOT/scripts/load_env.sh" "$RELATIVE_ENV_NAME" ) || relative_env_status=$?
rm -f "$REPO_ROOT/$RELATIVE_ENV_NAME"
test "$relative_env_status" -eq 0 \
  || fail "environment loader could not resolve a relative PROJECT_ENV_FILE from another directory"
```

Add to `scripts/test_template.ps1`:

```powershell
  $relativeEnvName = ".env.relative-test"
  Copy-Item -LiteralPath $baseEnvFile -Destination (Join-Path $repoRoot $relativeEnvName)
  try {
    Push-Location $testRoot
    . (Join-Path $PSScriptRoot "load_env.ps1") -EnvFile $relativeEnvName
    Pop-Location
  } catch {
    Pop-Location
    Assert-True $false "PowerShell loader could not resolve a relative PROJECT_ENV_FILE from another directory: $($_.Exception.Message)"
  } finally {
    Remove-Item -LiteralPath (Join-Path $repoRoot $relativeEnvName) -Force -ErrorAction SilentlyContinue
  }
```

- [ ] **Step 2: Run both suites to verify they fail**

Run: `bash scripts/test_template.sh`
Expected: FAIL with `environment loader could not resolve a relative PROJECT_ENV_FILE from another directory`

Run: `pwsh -NoProfile -File scripts/test_template.ps1`
Expected: FAIL with the PowerShell equivalent.

- [ ] **Step 3: Implement in `load_env.sh`**

Replace line 4:

```bash
PROJECT_ENV_FILE="${1:-${PROJECT_ENV_FILE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)/.env}}"
```

with:

```bash
project_env_repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
PROJECT_ENV_FILE="${1:-${PROJECT_ENV_FILE:-$project_env_repo_root/.env}}"

# README.md documents a relative PROJECT_ENV_FILE. Resolve it against the
# repository root when it is not found relative to the caller's directory, so a
# wrapper run from a subdirectory finds the same file as one run from the root.
# The drive-letter arm keeps Git Bash from treating C:/... as relative.
case "$PROJECT_ENV_FILE" in
  /*|[A-Za-z]:[/\\]*) ;;
  *)
    if [ ! -f "$PROJECT_ENV_FILE" ] && [ -f "$project_env_repo_root/$PROJECT_ENV_FILE" ]; then
      PROJECT_ENV_FILE="$project_env_repo_root/$PROJECT_ENV_FILE"
    fi
    ;;
esac
```

Add `project_env_repo_root` to the final `unset` list.

- [ ] **Step 4: Implement in `load_env.ps1`**

Replace line 15:

```powershell
if ([string]::IsNullOrWhiteSpace($EnvFile)) { $EnvFile = Join-Path $projectEnvRepoRoot ".env" }
```

with:

```powershell
if ([string]::IsNullOrWhiteSpace($EnvFile)) { $EnvFile = Join-Path $projectEnvRepoRoot ".env" }
# Mirror load_env.sh: a relative PROJECT_ENV_FILE resolves against the
# repository root when it is not found relative to the caller's location.
if (-not [System.IO.Path]::IsPathRooted($EnvFile) -and
    -not (Test-Path -LiteralPath $EnvFile -PathType Leaf)) {
  $projectEnvRootRelative = Join-Path $projectEnvRepoRoot $EnvFile
  if (Test-Path -LiteralPath $projectEnvRootRelative -PathType Leaf) {
    $EnvFile = $projectEnvRootRelative
  }
}
```

Add `projectEnvRootRelative` to the `Remove-Variable` list.

- [ ] **Step 5: Run both suites to verify they pass**

Run: `bash scripts/test_template.sh && pwsh -NoProfile -File scripts/test_template.ps1`
Expected: both exit 0.

- [ ] **Step 6: Commit**

```bash
git add scripts/load_env.sh scripts/load_env.ps1 scripts/test_template.sh scripts/test_template.ps1
git commit -m "$(cat <<'EOF'
fix: resolve a relative PROJECT_ENV_FILE against the repository root

README.md documents `PROJECT_ENV_FILE=.env.other scripts/export_apps.sh`, but
both loaders tested the path against the caller's working directory, so the
documented form failed from any subdirectory.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

# Phase 2 — Database backup correctness

Fixes F4, F21, F24. Static SQL assertions plus the existing fake-SQLcl orchestration harness; no live database needed.

---

### Task 4: Exclude Oracle recycle-bin objects from every backup query

**Files:**
- Modify: `scripts/backup_db.sql:51-84` (name guard), `:100-119` (tables driver), `:121-250` (five code drivers), `:263-293` (manifest)
- Test: `scripts/test_template.sh` (the `backup_db.sql` static-assertion block, ~lines 390-420)

**Interfaces:**
- Consumes: nothing.
- Produces: no recycle-bin object reaches the guard, the driver, or the manifest; the guard names up to ten offending objects in its ORA-20020 message.

**Background the implementer needs.** A table dropped without `PURGE` stays in `ALL_OBJECTS` and `ALL_TABLES` as `BIN$<base64>==$0`. Base64 of 16 bytes always carries `=` padding, so the name fails the `^[A-Za-z0-9_$#]+$` filename check and the guard aborts the whole backup — with a message that names nothing. `ALL_TABLES` has a `DROPPED` column; `ALL_OBJECTS` does **not**, so the guard and the manifest need a `NOT LIKE 'BIN$%'` predicate instead. Fixing only the driver would move the failure from ORA-20020 to a manifest count mismatch. Dropped tables also drag their triggers into the recycle bin, so the trigger driver needs the exclusion too. Applying `NOT LIKE 'BIN$%'` uniformly to all seven driver queries is harmless for the object types that can never be in the recycle bin, and makes the count assertion simple.

- [ ] **Step 1: Write the failing static assertions**

Add to `scripts/test_template.sh`, immediately after the existing `'\$', '-S-'` count assertion:

```bash
# A table dropped without PURGE stays in ALL_OBJECTS and ALL_TABLES as
# BIN$<base64>==$0. The '=' fails the filename character check, so the name
# guard aborted every backup with a message that named no object. ALL_OBJECTS
# has no DROPPED column, so the guard and manifest need the name predicate.
test "$(grep -c "NOT LIKE 'BIN\$%'" "$REPO_ROOT/scripts/backup_db.sql")" = 9 \
  || fail "backup_db.sql does not exclude recycle-bin objects from all seven drivers, the guard, and the manifest"
grep -q "tables_to_export.dropped = 'NO'" "$REPO_ROOT/scripts/backup_db.sql" \
  || fail "backup_db.sql does not use the authoritative ALL_TABLES.DROPPED column"
grep -q 'LISTAGG(object_name' "$REPO_ROOT/scripts/backup_db.sql" \
  || fail "backup_db.sql does not name the unsafe objects it refuses to export"
```

- [ ] **Step 2: Run the suite to verify it fails**

Run: `bash scripts/test_template.sh`
Expected: FAIL with `backup_db.sql does not exclude recycle-bin objects from all seven drivers, the guard, and the manifest`

- [ ] **Step 3: Replace the name guard so it excludes and reports**

Replace the whole `DECLARE`/`BEGIN`/`END;`/`/` block at `scripts/backup_db.sql:51-84` with:

```sql
DECLARE
  v_unsafe VARCHAR2(4000);
BEGIN
  SELECT LISTAGG(object_name, ', ') WITHIN GROUP (ORDER BY object_name)
  INTO v_unsafe
  FROM (
    SELECT object_name
    FROM all_objects
    WHERE owner = UPPER('&&target_schema')
      AND (
        (LOWER('&&object_scope') = 'tables' AND object_type = 'TABLE')
        OR
        (LOWER('&&object_scope') = 'code' AND object_type IN (
          'VIEW', 'PACKAGE', 'PACKAGE BODY', 'PROCEDURE', 'FUNCTION', 'TRIGGER'
        ))
      )
      -- A table dropped without PURGE, and any trigger it dragged with it,
      -- stays here as BIN$<base64>==$0. Those are not project objects.
      AND object_name NOT LIKE 'BIN$%'
      AND (
        '&&object_prefixes' = '*'
        OR EXISTS (
          SELECT 1
          FROM (
            SELECT REGEXP_SUBSTR('&&object_prefixes', '[^,]+', 1, LEVEL) object_prefix
            FROM dual
            CONNECT BY LEVEL <= REGEXP_COUNT('&&object_prefixes', ',') + 1
          ) configured_prefixes
          WHERE INSTR(all_objects.object_name, configured_prefixes.object_prefix) = 1
        )
      )
      AND NOT REGEXP_LIKE(object_name, '^[A-Za-z0-9_$#]+$')
      AND ROWNUM <= 10
  );

  IF v_unsafe IS NOT NULL THEN
    RAISE_APPLICATION_ERROR(-20020,
      'Schema contains object names that are unsafe for metadata export filenames: '
      || SUBSTR(v_unsafe, 1, 1800));
  END IF;
END;
/
```

- [ ] **Step 4: Add the exclusion to the tables driver**

In the `FROM all_tables tables_to_export` query, immediately after the line `AND tables_to_export.owner = UPPER('&&target_schema')`, add:

```sql
  AND tables_to_export.dropped = 'NO'
  AND tables_to_export.table_name NOT LIKE 'BIN$%'
```

- [ ] **Step 5: Add the exclusion to the six remaining drivers**

In the `FROM all_views views_to_export` query, after `AND views_to_export.owner = UPPER('&&target_schema')`, add:

```sql
  AND views_to_export.view_name NOT LIKE 'BIN$%'
```

In each of the five `FROM all_objects objects_to_export` queries (PACKAGE spec, PACKAGE BODY, PROCEDURE, FUNCTION, TRIGGER), after the `AND objects_to_export.object_type = '<TYPE>'` line, add:

```sql
  AND objects_to_export.object_name NOT LIKE 'BIN$%'
```

- [ ] **Step 6: Add the exclusion to the manifest**

In the manifest query's `LEFT JOIN all_objects` block, after the line `AND all_objects.object_type = expected_types.object_type`, add:

```sql
 AND all_objects.object_name NOT LIKE 'BIN$%'
```

The predicate belongs in the `ON` clause, not a `WHERE`, so the `LEFT JOIN` keeps producing a `0` row for object types the schema has none of.

- [ ] **Step 7: Verify the count is exactly nine and the suite passes**

Run: `grep -c "NOT LIKE 'BIN\$%'" scripts/backup_db.sql`
Expected: `9` (seven drivers + guard + manifest)

Run: `bash scripts/test_template.sh && pwsh -NoProfile -File scripts/test_template.ps1`
Expected: both exit 0.

- [ ] **Step 8: Record the lesson in `self_improve.md`**

Append to the "Durable Lessons" section:

```markdown
### Exclude the Oracle recycle bin from every metadata query, not just the driver

- Trigger: running `scripts/backup_db.*` against a schema where a table was
  dropped without `PURGE`, with `PREFIXES=*`.
- Evidence: recycle-bin objects keep the name `BIN$<base64>==$0`. The base64
  padding guarantees an `=`, which fails the
  `^[A-Za-z0-9_$#]+$` filename check, so the name guard raised ORA-20020 and
  aborted the whole backup before the driver was generated -- naming no object,
  so the operator had nothing to search for.
- Preferred behavior: exclude `BIN$%` in the guard, all seven driver queries,
  and the manifest. `ALL_TABLES.DROPPED` is authoritative but `ALL_OBJECTS` has
  no such column, so the guard and manifest must use the name predicate. Fixing
  only the driver converts the abort into a manifest count mismatch.
- Verification: `scripts/test_template.sh` asserts nine `NOT LIKE 'BIN$%'`
  predicates, the `dropped = 'NO'` column filter, and that the guard names the
  objects it refuses.
```

- [ ] **Step 9: Commit**

```bash
git add scripts/backup_db.sql scripts/test_template.sh self_improve.md
git commit -m "$(cat <<'EOF'
fix: exclude Oracle recycle-bin objects from metadata backup

A table dropped without PURGE stays in ALL_OBJECTS as BIN$<base64>==$0. The
base64 padding '=' failed the filename character check, so the name guard
aborted every backup with a message that named no object. Excludes BIN$ in the
guard, all seven drivers, and the manifest, uses ALL_TABLES.DROPPED where it
exists, and makes the guard list what it refuses.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 5: Stage only the directories a scope writes

**Files:**
- Modify: `scripts/backup_db.sh:52-56`, `:90-101`, `:110-128`, `:136-139`; `scripts/backup_db.ps1:41-52`, `:92-99`, `:128-131`, `:132-137`
- Test: `scripts/test_backup_orchestration.sh`

**Interfaces:**
- Consumes: Task 4's `backup_db.sql`.
- Produces: `scope_directories <tables|code>` in Bash and `Get-ScopeDirectory -Scope <tables|code>` in PowerShell, each printing/returning the directory names that scope writes. Both are used by staging creation *and* completeness verification, replacing the duplicated `case`/`if` pair.

**Background.** SQLcl's `SPOOL` does not create missing directories, which is why they are pre-created. Creating all six for every schema means a split-schema project installs ten empty directories — and an empty `database/APP_DATA/views/` reads as "this schema has no views" when the truth is "views were never looked for here". A scope can also legitimately produce zero objects of one type, so pruning empty directories before replacement is needed as well as scoping their creation.

- [ ] **Step 1: Write the failing test**

Add to `scripts/test_backup_orchestration.sh`, after the existing complete-case assertions:

```bash
# A split-schema project must not install directories the scope never writes,
# and must not install an empty directory for a type that produced no objects.
EMPTY_DIR="$(find "$TEST_REPO/database" -mindepth 2 -type d -empty -print -quit)"
test -z "$EMPTY_DIR" || fail "backup installed an empty scope directory: $EMPTY_DIR"
```

- [ ] **Step 2: Run the orchestration test to verify it fails**

Run: `bash scripts/test_backup_orchestration.sh`
Expected: FAIL with `backup installed an empty scope directory: .../database/<schema>/<type>`

- [ ] **Step 3: Add `scope_directories` to `backup_db.sh` and use it for staging**

Replace lines 52-56:

```bash
for schema in "${BACKUP_SCHEMAS[@]}"; do
  db_stage="$STAGING_DIR/database/$schema"
  mkdir -p "$db_stage/tables" "$db_stage/views" "$db_stage/packages" \
    "$db_stage/procedures" "$db_stage/functions" "$db_stage/triggers"
done
```

with:

```bash
# SQLcl's SPOOL does not create missing directories, so each scope's own
# directories are created just before its run -- and only its own, so a
# split-schema project does not install directories nothing ever writes to.
scope_directories() {
  case "$1" in
    tables) printf '%s\n' tables ;;
    code)   printf '%s\n' views packages procedures functions triggers ;;
    *) echo "unsupported backup scope: $1" >&2; return 1 ;;
  esac
}
```

- [ ] **Step 4: Create the scope's directories inside `run_backup_scope`**

In `run_backup_scope`, immediately after the `local prefixes="$5"` line, add:

```bash
  local scope_dir
  while IFS= read -r scope_dir; do
    mkdir -p "$STAGING_DIR/database/$schema/$scope_dir"
  done < <(scope_directories "$scope")
```

- [ ] **Step 5: Reuse the same function in `verify_scope_complete`**

Replace lines 90-101:

```bash
  local scope_dirs
  case "$scope" in
    tables) scope_dirs="tables" ;;
    code)   scope_dirs="views packages procedures functions triggers" ;;
  esac
  local actual=0
  local scope_dir found
  for scope_dir in $scope_dirs; do
    found="$(find "$STAGING_DIR/database/$schema/$scope_dir" -maxdepth 1 -type f \
      -name '*.sql' 2>/dev/null | wc -l)"
    actual=$((actual + found))
  done
```

with:

```bash
  local actual=0
  local scope_dir found
  while IFS= read -r scope_dir; do
    found="$(find "$STAGING_DIR/database/$schema/$scope_dir" -maxdepth 1 -type f \
      -name '*.sql' 2>/dev/null | wc -l)"
    actual=$((actual + found))
  done < <(scope_directories "$scope")
```

- [ ] **Step 6: Prune empty directories before replacement**

Replace lines 136-139:

```bash
for schema in "${BACKUP_SCHEMAS[@]}"; do
  "$REPO_ROOT/scripts/replace_mirror.sh" \
    "$STAGING_DIR/database/$schema" "database/$schema"
done
```

with:

```bash
for schema in "${BACKUP_SCHEMAS[@]}"; do
  # A scope that produced no objects of one type leaves an empty directory that
  # would otherwise be installed, implying "none exist" where the truth is
  # "none were looked for". Prune after verification, before replacement.
  find "$STAGING_DIR/database/$schema" -mindepth 1 -type d -empty -delete
  "$REPO_ROOT/scripts/replace_mirror.sh" \
    "$STAGING_DIR/database/$schema" "database/$schema"
done
```

- [ ] **Step 7: Mirror all four changes in `backup_db.ps1`**

Replace lines 41-45 of `Test-ScopeComplete`:

```powershell
  if ($Scope -eq 'tables') {
    $scopeDirs = @('tables')
  } else {
    $scopeDirs = @('views', 'packages', 'procedures', 'functions', 'triggers')
  }
```

with:

```powershell
  $scopeDirs = Get-ScopeDirectory -Scope $Scope
```

Add this function immediately before `Test-ScopeComplete`:

```powershell
# SQLcl's SPOOL does not create missing directories, so each scope's own
# directories are created just before its run -- and only its own, so a
# split-schema project does not install directories nothing ever writes to.
function Get-ScopeDirectory {
  param([Parameter(Mandatory = $true)][ValidateSet("tables", "code")][string] $Scope)
  if ($Scope -eq "tables") { return @("tables") }
  return @("views", "packages", "procedures", "functions", "triggers")
}
```

Replace lines 92-99:

```powershell
foreach ($schema in $backupSchemas) {
  $dbStage = Join-Path $stagingPath "database/$schema"
  New-Item -ItemType Directory -Force -Path @(
    (Join-Path $dbStage "tables"), (Join-Path $dbStage "views"),
    (Join-Path $dbStage "packages"), (Join-Path $dbStage "procedures"),
    (Join-Path $dbStage "functions"), (Join-Path $dbStage "triggers")
  ) | Out-Null
}
```

with nothing — the directories now get created per scope. Inside the `foreach ($target in $backupTargets)` loop, immediately before the `Invoke-Sqlcl` call, add:

```powershell
    foreach ($scopeDir in (Get-ScopeDirectory -Scope $target.Scope)) {
      New-Item -ItemType Directory -Force `
        -LiteralPath (Join-Path $stagingPath "database/$($target.Schema)/$scopeDir") | Out-Null
    }
```

Replace lines 128-131:

```powershell
  foreach ($schema in $backupSchemas) {
    & (Join-Path $PSScriptRoot "replace_mirror.ps1") `
      (Join-Path $stagingPath "database/$schema") "database/$schema"
  }
```

with:

```powershell
  foreach ($schema in $backupSchemas) {
    # A scope that produced no objects of one type leaves an empty directory
    # that would otherwise be installed. Prune after verification. Descending
    # order empties the deepest directories first, so a parent left empty by
    # its own pruned children is removed in the same pass.
    Get-ChildItem -LiteralPath (Join-Path $stagingPath "database/$schema") -Recurse -Directory |
      Sort-Object -Property FullName -Descending |
      ForEach-Object {
        if (-not (Get-ChildItem -LiteralPath $_.FullName -Force)) {
          Remove-Item -LiteralPath $_.FullName -Force
        }
      }
    & (Join-Path $PSScriptRoot "replace_mirror.ps1") `
      (Join-Path $stagingPath "database/$schema") "database/$schema"
  }
```

- [ ] **Step 8: Fix the `finally` that turns success into failure**

Replace `scripts/backup_db.ps1:134-136`:

```powershell
  if ($locationPushed) { Pop-Location }
  if (Test-Path -LiteralPath $stagingPath) {
    Remove-Item -LiteralPath $stagingPath -Recurse -Force -ErrorAction Stop
  }
```

with:

```powershell
  if ($locationPushed) { Pop-Location }
  if (Test-Path -LiteralPath $stagingPath) {
    # This runs after the mirrors are already installed. A file handle Windows
    # has not released yet must not convert a completed backup into a failure,
    # which is why Bash uses `rm -rf` in a trap and ignores the result.
    Remove-Item -LiteralPath $stagingPath -Recurse -Force -ErrorAction SilentlyContinue
  }
```

- [ ] **Step 9: Run all three suites**

Run: `bash scripts/test_backup_orchestration.sh && bash scripts/test_template.sh && pwsh -NoProfile -File scripts/test_template.ps1`
Expected: all exit 0.

- [ ] **Step 10: Commit**

```bash
git add scripts/backup_db.sh scripts/backup_db.ps1 scripts/test_backup_orchestration.sh
git commit -m "$(cat <<'EOF'
fix: stage only the directories each backup scope writes

A split-schema project installed ten empty directories, and an empty
database/<schema>/views/ reads as "this schema has no views" when the truth is
"views were never looked for here". Scope directories are now derived from one
shared function used by both staging and verification, and empty directories
are pruned before replacement.

Also stops backup_db.ps1's finally block from converting a completed backup
into a thrown error when Windows has not released a staging file handle.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

# Phase 3 — Mirror replacement

Fixes F5, F6, F7. The riskiest phase: it rewrites the control flow of the script that moves real directories. Run the orchestration suites after every step.

---

### Task 6: One stale-tolerant lock protocol for both implementations

**Files:**
- Modify: `scripts/replace_mirror.sh:123-130`, `scripts/replace_mirror.ps1:92-108`
- Test: `scripts/test_template.sh`, `scripts/test_template.ps1`

**Interfaces:**
- Consumes: nothing.
- Produces: `acquire_mirror_lock <lock-file> <canonical-rel>` (Bash, returns 0 on success) and `Enter-MirrorLock -LockPath <path> -CanonicalRelative <rel>` (PowerShell, returns the held `FileStream`). Both use the path `scratch/.mirror-locks/<sha256(canonical-rel)[0:16]>.lock` and the same file format. `MIRROR_LOCK_STALE_SECONDS` (env var, default 900) tunes the staleness window.

**Lock protocol v1 — write this comment block into both files.**

```
# Lock protocol v1. Both implementations must agree, because on Windows a
# Git Bash run and a PowerShell run can target the same mirror.
#
#   path:     scratch/.mirror-locks/<first 16 hex of sha256(canonical-rel)>.lock
#   contents: version=1 / impl=sh|ps1 / pid=<n> / epoch=<unix seconds>, LF each
#
#   acquire:  atomic exclusive create (noclobber redirect / FileMode::CreateNew).
#             On failure, read the holder's fields:
#               - same impl and pid alive  -> real contention, refuse
#               - otherwise, epoch older than MIRROR_LOCK_STALE_SECONDS
#                                          -> break the lock and retry once
#               - otherwise                -> refuse, naming the file and the
#                                             remaining wait
#   release:  delete the file (EXIT trap / finally)
#
# PowerShell opens with FileShare::Read, not None, so the Bash side can still
# read the metadata of a live PowerShell lock. CreateNew, not OpenOrCreate:
# OpenOrCreate would let PowerShell silently steal a Bash lock, because Bash
# holds no OS handle. Cross-implementation liveness cannot be checked (the pid
# namespaces differ under MSYS), so cross-impl contention degrades to the
# staleness window. Same-impl contention is always detected exactly.
```

- [ ] **Step 1: Write the failing Bash test**

Add to `scripts/test_template.sh`, after the existing dirty-mirror assertions:

```bash
# A killed process used to leave a lock that blocked every future run forever.
LOCK_ROOT="$TEST_REPO/scratch/.mirror-locks"
mkdir -p "$LOCK_ROOT" "$TEST_REPO/scratch/lock-staged"
printf 'content\n' > "$TEST_REPO/scratch/lock-staged/file.txt"
STALE_LOCK_KEY="$(printf '%s' "database/mirror" | sha256sum | cut -c1-16)"
printf 'version=1\nimpl=sh\npid=999999\nepoch=1\n' > "$LOCK_ROOT/$STALE_LOCK_KEY.lock"
MIRROR_SYNC_REPO_ROOT="$TEST_REPO" "$REPO_ROOT/scripts/replace_mirror.sh" \
  "$TEST_REPO/scratch/lock-staged" "database/mirror" \
  || fail "a stale mirror lock was not broken"
test ! -e "$LOCK_ROOT/$STALE_LOCK_KEY.lock" || fail "the mirror lock was not released"

# A live lock from the same implementation must still be honored.
mkdir -p "$TEST_REPO/scratch/live-staged"
printf 'content\n' > "$TEST_REPO/scratch/live-staged/file.txt"
git -C "$TEST_REPO" add -A
git -C "$TEST_REPO" -c user.name=TemplateTest -c user.email=test@example.invalid commit -qm "lock fixture"
printf 'version=1\nimpl=sh\npid=%s\nepoch=%s\n' "$$" "$(date +%s)" \
  > "$LOCK_ROOT/$STALE_LOCK_KEY.lock"
if MIRROR_SYNC_REPO_ROOT="$TEST_REPO" "$REPO_ROOT/scripts/replace_mirror.sh" \
    "$TEST_REPO/scratch/live-staged" "database/mirror"; then
  fail "a live mirror lock was ignored"
fi
rm -f "$LOCK_ROOT/$STALE_LOCK_KEY.lock"
```

- [ ] **Step 2: Run the suite to verify it fails**

Run: `bash scripts/test_template.sh`
Expected: FAIL with `a stale mirror lock was not broken` — the current Bash code makes a `cksum`-named *directory*, so the SHA-256-named file is not even the path it checks.

- [ ] **Step 3: Implement the Bash lock**

Replace `scripts/replace_mirror.sh:123-130`:

```bash
LOCK_ROOT="$SCRATCH_ROOT/.mirror-locks"
mkdir -p "$LOCK_ROOT"
LOCK_KEY="$(printf '%s' "$CANONICAL_REL" | cksum | awk '{print $1}')"
LOCK_DIR="$LOCK_ROOT/$LOCK_KEY.lock"
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  echo "another mirror replacement is already running for $CANONICAL_REL" >&2
  exit 1
fi
```

with (paste the protocol comment block above this):

```bash
MIRROR_LOCK_STALE_SECONDS="${MIRROR_LOCK_STALE_SECONDS:-900}"

lock_digest() {
  if command -v sha256sum >/dev/null 2>&1; then
    printf '%s' "$1" | sha256sum | cut -c1-16
  elif command -v shasum >/dev/null 2>&1; then
    printf '%s' "$1" | shasum -a 256 | cut -c1-16
  else
    printf '%s' "$1" | cksum | awk '{printf "%016x", $1}'
  fi
}

lock_field() {
  sed -n "s/^$2=//p" "$1" 2>/dev/null | head -1 | tr -d '\r'
}

acquire_mirror_lock() {
  local lock_file="$1" canonical="$2"
  local attempt holder_impl holder_pid holder_epoch now age
  for attempt in 1 2; do
    if ( set -o noclobber
         printf 'version=1\nimpl=sh\npid=%s\nepoch=%s\n' "$$" "$(date +%s)" \
           > "$lock_file" ) 2>/dev/null; then
      return 0
    fi
    if [ "$attempt" -eq 2 ]; then
      break
    fi
    holder_impl="$(lock_field "$lock_file" impl)"
    holder_pid="$(lock_field "$lock_file" pid)"
    holder_epoch="$(lock_field "$lock_file" epoch)"
    now="$(date +%s)"
    if [ "$holder_impl" = sh ] && [ -n "$holder_pid" ] && kill -0 "$holder_pid" 2>/dev/null; then
      echo "another mirror replacement is already running for $canonical (pid $holder_pid)" >&2
      return 1
    fi
    age=$(( now - ${holder_epoch:-0} ))
    if [ -z "$holder_epoch" ] || [ "$age" -ge "$MIRROR_LOCK_STALE_SECONDS" ]; then
      echo "breaking stale mirror lock for $canonical (impl=${holder_impl:-unknown} pid=${holder_pid:-unknown} age=${age}s)" >&2
      rm -f -- "$lock_file"
      continue
    fi
    echo "another mirror replacement is already running for $canonical" >&2
    echo "if that process is gone, remove $lock_file or wait $(( MIRROR_LOCK_STALE_SECONDS - age )) seconds" >&2
    return 1
  done
  return 1
}

LOCK_ROOT="$SCRATCH_ROOT/.mirror-locks"
mkdir -p "$LOCK_ROOT"
LOCK_FILE="$LOCK_ROOT/$(lock_digest "$CANONICAL_REL").lock"
acquire_mirror_lock "$LOCK_FILE" "$CANONICAL_REL" || exit 1
```

- [ ] **Step 4: Release the file, not the directory**

In `cleanup_replacement`, replace:

```bash
  rmdir "$LOCK_DIR" 2>/dev/null || true
```

with:

```bash
  rm -f -- "$LOCK_FILE" 2>/dev/null || true
```

- [ ] **Step 5: Run the Bash suites to verify they pass**

Run: `bash scripts/test_template.sh && bash scripts/test_backup_orchestration.sh && bash scripts/test_export_orchestration.sh`
Expected: all exit 0.

- [ ] **Step 6: Write the failing PowerShell test**

Add to `scripts/test_template.ps1`, after the existing dirty-mirror assertion:

```powershell
  $lockRoot = Join-Path $testRepo "scratch/.mirror-locks"
  New-Item -ItemType Directory -Force -Path $lockRoot | Out-Null
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    $lockBytes = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes("database/mirror"))
  } finally { $sha.Dispose() }
  $lockName = ([System.BitConverter]::ToString($lockBytes) -replace '-', '').Substring(0, 16).ToLowerInvariant() + ".lock"
  $lockPath = Join-Path $lockRoot $lockName
  [System.IO.File]::WriteAllText($lockPath, "version=1`nimpl=ps1`npid=999999`nepoch=1`n")
  New-Item -ItemType Directory -Force -Path (Join-Path $testRepo "scratch/lock-staged") | Out-Null
  [System.IO.File]::WriteAllText((Join-Path $testRepo "scratch/lock-staged/file.txt"), "content`n")
  & (Join-Path $testRepo "scripts/replace_mirror.ps1") `
    -StagedDir (Join-Path $testRepo "scratch/lock-staged") -Destination "database/mirror"
  Assert-True (-not (Test-Path -LiteralPath $lockPath)) "a stale mirror lock was not broken and released"
```

- [ ] **Step 7: Implement the PowerShell lock**

Replace `scripts/replace_mirror.ps1:92-108` with (paste the protocol comment block above this):

```powershell
$mirrorLockStaleSeconds = 900
if (-not [string]::IsNullOrWhiteSpace($env:MIRROR_LOCK_STALE_SECONDS)) {
  $mirrorLockStaleSeconds = [int]$env:MIRROR_LOCK_STALE_SECONDS
}

function Get-MirrorLockField([string]$Path, [string]$Key) {
  try { $lines = [System.IO.File]::ReadAllLines($Path) } catch { return $null }
  foreach ($line in $lines) {
    $trimmed = $line.TrimEnd("`r")
    if ($trimmed.StartsWith("$Key=")) { return $trimmed.Substring($Key.Length + 1) }
  }
  return $null
}

function Enter-MirrorLock([string]$LockPath, [string]$CanonicalRelative) {
  foreach ($attempt in 1, 2) {
    try {
      # FileShare::Read, so a Bash run can still read a live lock's metadata.
      $stream = [System.IO.File]::Open($LockPath, [System.IO.FileMode]::CreateNew,
        [System.IO.FileAccess]::Write, [System.IO.FileShare]::Read)
      $epoch = [int][double]::Parse((Get-Date -UFormat %s))
      $payload = [System.Text.Encoding]::UTF8.GetBytes(
        "version=1`nimpl=ps1`npid=$PID`nepoch=$epoch`n")
      $stream.Write($payload, 0, $payload.Length)
      $stream.Flush()
      return $stream
    } catch [System.IO.IOException] {
      if ($attempt -eq 2) { break }
      $holderImpl = Get-MirrorLockField -Path $LockPath -Key "impl"
      $holderPid = Get-MirrorLockField -Path $LockPath -Key "pid"
      $holderEpoch = Get-MirrorLockField -Path $LockPath -Key "epoch"
      if ($holderImpl -eq "ps1" -and $holderPid -and (Get-Process -Id ([int]$holderPid) -ErrorAction SilentlyContinue)) {
        throw "another mirror replacement is already running for $CanonicalRelative (pid $holderPid)"
      }
      $age = $mirrorLockStaleSeconds
      if ($holderEpoch) {
        $age = [int][double]::Parse((Get-Date -UFormat %s)) - [int]$holderEpoch
      }
      if (-not $holderEpoch -or $age -ge $mirrorLockStaleSeconds) {
        Write-Warning "breaking stale mirror lock for $CanonicalRelative (impl=$holderImpl pid=$holderPid age=${age}s)"
        Remove-Item -LiteralPath $LockPath -Force -ErrorAction SilentlyContinue
        continue
      }
      throw ("another mirror replacement is already running for $CanonicalRelative; " +
        "if that process is gone, remove $LockPath or wait $($mirrorLockStaleSeconds - $age) seconds")
    }
  }
  throw "could not acquire the mirror lock for $CanonicalRelative"
}

$lockRoot = Join-Path $scratchRoot ".mirror-locks"
New-Item -ItemType Directory -Force -Path $lockRoot | Out-Null
# SHA256::HashData and Convert::ToHexString are .NET 5+, so they are missing on
# Windows PowerShell 5.1. Create()/ComputeHash and BitConverter work on both.
$sha256 = [System.Security.Cryptography.SHA256]::Create()
try {
  $hashBytes = $sha256.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($canonicalRelativeDestination))
} finally {
  $sha256.Dispose()
}
$lockName = ([System.BitConverter]::ToString($hashBytes) -replace '-', '').Substring(0, 16).ToLowerInvariant() + ".lock"
$lockPath = Join-Path $lockRoot $lockName
$lockHandle = Enter-MirrorLock -LockPath $lockPath -CanonicalRelative $canonicalRelativeDestination
```

> The `.ToLowerInvariant()` is required: Bash's `sha256sum | cut` produces lowercase hex, and the two implementations must compute the same filename.

- [ ] **Step 8: Run the PowerShell suite to verify it passes**

Run: `pwsh -NoProfile -File scripts/test_template.ps1`
Expected: exit 0.

- [ ] **Step 9: Verify both implementations compute the same lock name**

Run:

```bash
printf '%s' "database/mirror" | sha256sum | cut -c1-16
```

Run:

```bash
pwsh -NoProfile -Command '$s=[System.Security.Cryptography.SHA256]::Create(); $b=$s.ComputeHash([System.Text.Encoding]::UTF8.GetBytes("database/mirror")); $s.Dispose(); ([System.BitConverter]::ToString($b) -replace "-","").Substring(0,16).ToLowerInvariant()'
```

Expected: the two commands print the identical 16-character string.

- [ ] **Step 10: Commit**

```bash
git add scripts/replace_mirror.sh scripts/replace_mirror.ps1 scripts/test_template.sh scripts/test_template.ps1
git commit -m "$(cat <<'EOF'
fix: one stale-tolerant mirror lock protocol for both implementations

Bash made a cksum-named lock directory and PowerShell a SHA-256-named lock
file, so on Windows the two shells could not see each other's lock. A killed
process left either one behind permanently, with no staleness detection and no
message naming the path to remove.

Both now use the same path, the same file format, atomic exclusive create, and
an explicit staleness break. PowerShell keeps CreateNew rather than
OpenOrCreate, which would let it silently steal a Bash lock.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 7: Make multi-target replacement atomic

**Files:**
- Modify: `scripts/replace_mirror.sh` (whole control flow), `scripts/replace_mirror.ps1` (whole control flow), `scripts/export_apps.sh:83-86`, `scripts/export_apps.ps1:64-67`, `scripts/backup_db.sh:136-139`, `scripts/backup_db.ps1:128-131`
- Test: `scripts/test_export_orchestration.sh`

**Interfaces:**
- Consumes: Task 6's `acquire_mirror_lock` / `Enter-MirrorLock`.
- Produces: `replace_mirror.sh <staged1> <dest1> [<staged2> <dest2> ...]` and `replace_mirror.ps1 <staged1> <dest1> [...]` (positional `[string[]]$Pairs`, even count). All pairs are validated and locked before any move; a failure unwinds every completed move in reverse.

**Background.** Export and verification are already all-or-nothing. Replacement is not: `export_apps.sh` replaces app 100, then app 200, with no rollback, so a failure on the second leaves the tree half-updated. All moves are same-filesystem renames, so an exact unwind is possible.

- [ ] **Step 1: Teach the fake SQLcl shim to dirty a mirror mid-run**

The existing test for "failure of the second export must leave both existing mirrors untouched" covers an *export* failure, which happens before any replacement. To reach the replacement phase, the second mirror has to become dirty **after** the pre-flight and **before** the recheck under the lock — which is exactly what the fake shim can do, because it runs between those two points.

In `scripts/test_export_orchestration.sh`, inside the `cat > "$FAKE_SQL"` heredoc, add immediately after the `FAKE_EXPORT_NOTHING_APP_ID` block:

```bash
if [ "${FAKE_DIRTY_MIRROR_APP_ID:-}" = "$app_id" ]; then
  # Dirty a *different* application's destination while this one exports, so
  # the replacement phase fails after the pre-flight has already passed.
  printf 'appeared mid-run\n' \
    > "$FAKE_REPO_ROOT/apps/$schema/${FAKE_DIRTY_MIRROR_TARGET}/uncommitted.apx"
fi
```

Then add the two new variables to `run_export`, beside the existing `FAKE_*` exports:

```bash
    FAKE_REPO_ROOT="$TEST_REPO" \
    FAKE_DIRTY_MIRROR_APP_ID="${FAKE_DIRTY_MIRROR_APP_ID:-}" \
    FAKE_DIRTY_MIRROR_TARGET="${FAKE_DIRTY_MIRROR_TARGET:-}" \
```

- [ ] **Step 2: Write the failing test**

Add to `scripts/test_export_orchestration.sh`, immediately before the final `echo "PASS: ..."` line:

```bash
# Export is already all-or-nothing. Replacement must be too: if the second
# application's mirror cannot be installed, the first must not be left changed.
git -C "$TEST_REPO" checkout -- apps
commit_all "seed the atomic replacement fixture"
before_100="$(cat "$MIRROR_100/application.apx")"
if FAKE_DIRTY_MIRROR_APP_ID=100 FAKE_DIRTY_MIRROR_TARGET=101 run_export; then
  fail "export succeeded despite an un-replaceable second mirror"
fi
test "$(cat "$MIRROR_100/application.apx")" = "$before_100" \
  || fail "the first mirror was left replaced after the second could not be installed"
rm -f "$MIRROR_101/uncommitted.apx"
test -z "$(git -C "$TEST_REPO" status --porcelain -- apps)" \
  || fail "a rolled-back replacement left the working tree dirty"
```

- [ ] **Step 3: Run the orchestration test to verify it fails**

Run: `bash scripts/test_export_orchestration.sh`
Expected: FAIL with `the first mirror was left replaced after the second failed`

- [ ] **Step 4: Restructure `replace_mirror.sh` to validate all pairs first**

Replace the argument handling at lines 6-7:

```bash
STAGED_DIR_ARG="${1:?usage: replace_mirror.sh <staged-dir> <destination>}"
DEST_DIR_ARG="${2:?usage: replace_mirror.sh <staged-dir> <destination>}"
```

with:

```bash
if [ "$#" -lt 2 ] || [ $(( $# % 2 )) -ne 0 ]; then
  echo "usage: replace_mirror.sh <staged-dir> <destination> [<staged-dir> <destination> ...]" >&2
  exit 1
fi

STAGED_DIRS=()
DEST_DIRS=()
CANONICAL_RELS=()
```

Then wrap the existing validation — everything currently at lines 9-121, from `if [ ! -d "$STAGED_DIR_ARG" ]` through the `BACKUP_DIR` existence check — in a function:

```bash
validate_pair() {
  STAGED_DIR_ARG="$1"
  DEST_DIR_ARG="$2"
  # ... the existing body, unchanged, referring to STAGED_DIR_ARG/DEST_DIR_ARG ...
  # At the end, instead of falling through, append the resolved values:
  STAGED_DIRS+=("$STAGED_DIR")
  DEST_DIRS+=("$DEST_DIR")
  CANONICAL_RELS+=("$CANONICAL_REL")
}
```

Keep the body byte-for-byte as it is today; only the two argument assignments at the top and the three `+=` lines at the bottom are new. The `check_clean_mirror` call currently on line 85 stays inside the function — it is the pre-lock check.

- [ ] **Step 5: Add the validate-all, lock-all, move-all control flow**

After the `validate_pair` function definition, replace everything from the old line 123 (`LOCK_ROOT=...`) to the end of the file with:

```bash
while [ "$#" -gt 0 ]; do
  validate_pair "$1" "$2"
  shift 2
done

LOCK_ROOT="$SCRATCH_ROOT/.mirror-locks"
mkdir -p "$LOCK_ROOT"

ACQUIRED_LOCKS=()
INSTALLED_INDEXES=()
MOVED_DEST_INDEXES=()
BACKUP_DIRS=()

release_locks() {
  local lock_file
  for lock_file in "${ACQUIRED_LOCKS[@]:-}"; do
    [ -n "$lock_file" ] && rm -f -- "$lock_file" 2>/dev/null || true
  done
}

unwind_replacements() {
  local index
  # Reverse order: undo the staged move first, then restore the old mirror.
  for (( index=${#STAGED_DIRS[@]} - 1; index >= 0; index-- )); do
    case " ${INSTALLED_INDEXES[*]:-} " in
      *" $index "*)
        mv -- "${DEST_DIRS[$index]}" "${STAGED_DIRS[$index]}" 2>/dev/null || \
          echo "rollback could not return ${DEST_DIRS[$index]} to staging" >&2
        ;;
    esac
    case " ${MOVED_DEST_INDEXES[*]:-} " in
      *" $index "*)
        mv -- "${BACKUP_DIRS[$index]}" "${DEST_DIRS[$index]}" 2>/dev/null || \
          echo "rollback failed; the previous mirror is at ${BACKUP_DIRS[$index]}" >&2
        ;;
    esac
  done
}

cleanup_replacement() {
  cleanup_status=$?
  if [ "$cleanup_status" -ne 0 ]; then
    unwind_replacements
  fi
  release_locks
  trap - EXIT
  exit "$cleanup_status"
}
trap cleanup_replacement EXIT
trap 'exit 130' INT
trap 'exit 143' TERM HUP

for (( PAIR_INDEX=0; PAIR_INDEX < ${#STAGED_DIRS[@]}; PAIR_INDEX++ )); do
  LOCK_FILE="$LOCK_ROOT/$(lock_digest "${CANONICAL_RELS[$PAIR_INDEX]}").lock"
  acquire_mirror_lock "$LOCK_FILE" "${CANONICAL_RELS[$PAIR_INDEX]}" || exit 1
  ACQUIRED_LOCKS+=("$LOCK_FILE")
  BACKUP_DIRS+=("$REPO_ROOT/scratch/.mirror-backup.$(basename -- "${DEST_DIRS[$PAIR_INDEX]}").$$.$PAIR_INDEX")
done

# Recheck every mirror after taking every lock, to close the check-to-replace
# window as much as possible, then move them all.
for (( PAIR_INDEX=0; PAIR_INDEX < ${#STAGED_DIRS[@]}; PAIR_INDEX++ )); do
  DEST_REL="${CANONICAL_RELS[$PAIR_INDEX]}"
  check_clean_mirror
done

for (( PAIR_INDEX=0; PAIR_INDEX < ${#STAGED_DIRS[@]}; PAIR_INDEX++ )); do
  if [ -e "${DEST_DIRS[$PAIR_INDEX]}" ] || [ -L "${DEST_DIRS[$PAIR_INDEX]}" ]; then
    mv -- "${DEST_DIRS[$PAIR_INDEX]}" "${BACKUP_DIRS[$PAIR_INDEX]}"
    MOVED_DEST_INDEXES+=("$PAIR_INDEX")
  fi
  mv -- "${STAGED_DIRS[$PAIR_INDEX]}" "${DEST_DIRS[$PAIR_INDEX]}"
  INSTALLED_INDEXES+=("$PAIR_INDEX")
done

# Every mirror is installed. Discard the saved copies.
for (( PAIR_INDEX=0; PAIR_INDEX < ${#BACKUP_DIRS[@]}; PAIR_INDEX++ )); do
  if [ -e "${BACKUP_DIRS[$PAIR_INDEX]}" ] || [ -L "${BACKUP_DIRS[$PAIR_INDEX]}" ]; then
    rm -rf -- "${BACKUP_DIRS[$PAIR_INDEX]}" || {
      echo "mirrors installed, but cleanup failed; the previous mirror is at ${BACKUP_DIRS[$PAIR_INDEX]}" >&2
      exit 1
    }
  fi
done
INSTALLED_INDEXES=()
MOVED_DEST_INDEXES=()
```

> `INSTALLED_INDEXES` and `MOVED_DEST_INDEXES` are cleared at the very end so the EXIT trap cannot unwind a run that already succeeded.

- [ ] **Step 6: Call it once, with every pair, from the Bash wrappers**

Replace `scripts/export_apps.sh:83-86`:

```bash
# Install only after every requested application has exported and verified.
for app_id in "${APP_IDS[@]}"; do
  "$REPO_ROOT/scripts/replace_mirror.sh" \
    "$STAGE_PARENT/$app_id" "apps/$APEX_PARSING_SCHEMA/$app_id"
done
```

with:

```bash
# Install only after every requested application has exported and verified, and
# install them in one call so a failure on the last application does not leave
# the earlier ones replaced.
REPLACE_ARGS=()
for app_id in "${APP_IDS[@]}"; do
  REPLACE_ARGS+=("$STAGE_PARENT/$app_id" "apps/$APEX_PARSING_SCHEMA/$app_id")
done
"$REPO_ROOT/scripts/replace_mirror.sh" "${REPLACE_ARGS[@]}"
```

Replace the loop added in Task 5 Step 6 of `scripts/backup_db.sh` with:

```bash
REPLACE_ARGS=()
for schema in "${BACKUP_SCHEMAS[@]}"; do
  # A scope that produced no objects of one type leaves an empty directory that
  # would otherwise be installed, implying "none exist" where the truth is
  # "none were looked for". Prune after verification, before replacement.
  find "$STAGING_DIR/database/$schema" -mindepth 1 -type d -empty -delete
  REPLACE_ARGS+=("$STAGING_DIR/database/$schema" "database/$schema")
done
"$REPO_ROOT/scripts/replace_mirror.sh" "${REPLACE_ARGS[@]}"
```

- [ ] **Step 7: Run the Bash suites**

Run: `bash scripts/test_export_orchestration.sh && bash scripts/test_backup_orchestration.sh && bash scripts/test_template.sh`
Expected: all exit 0.

- [ ] **Step 8: Apply the identical restructure to `replace_mirror.ps1`**

Replace the `param` block at lines 3-6:

```powershell
param(
  [Parameter(Mandatory = $true)][string]$StagedDir,
  [Parameter(Mandatory = $true)][string]$Destination
)
```

with:

```powershell
param(
  [Parameter(Mandatory = $true, ValueFromRemainingArguments = $true)]
  [ValidateScript({ $_.Count -ge 2 -and $_.Count % 2 -eq 0 })]
  [string[]]$Pairs
)
```

Wrap the existing validation body (lines 10-90 today, from the `Test-Path` on `$StagedDir` through the `$backupPath` existence check) in:

```powershell
function Test-MirrorPair {
  param([string]$StagedDir, [string]$Destination, [int]$Index)
  # ... the existing body, unchanged ...
  return [PSCustomObject]@{
    StagedPath = $stagedPath
    DestinationPath = $destinationPath
    CanonicalRelative = $canonicalRelativeDestination
    BackupPath = Join-Path $scratchPath (".mirror-backup.{0}.{1}.{2}" -f $mirrorName, $PID, $Index)
  }
}

$validated = @()
for ($i = 0; $i -lt $Pairs.Count; $i += 2) {
  $validated += Test-MirrorPair -StagedDir $Pairs[$i] -Destination $Pairs[$i + 1] -Index ($i / 2)
}
```

Then replace the single-pair move block (today lines 110-141) with:

```powershell
$lockHandles = @()
$installed = @()
$movedDestination = @()
try {
  foreach ($pair in $validated) {
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
      $hashBytes = $sha256.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($pair.CanonicalRelative))
    } finally { $sha256.Dispose() }
    $lockName = ([System.BitConverter]::ToString($hashBytes) -replace '-', '').Substring(0, 16).ToLowerInvariant() + ".lock"
    $pair | Add-Member -NotePropertyName LockPath -NotePropertyValue (Join-Path $lockRoot $lockName)
    $lockHandles += Enter-MirrorLock -LockPath $pair.LockPath -CanonicalRelative $pair.CanonicalRelative
  }

  # Recheck every mirror after taking every lock.
  foreach ($pair in $validated) {
    $dirty = @(git -C $repoRoot status --porcelain --untracked-files=all -- $pair.DestinationPath)
    if ($LASTEXITCODE -ne 0) { throw "unable to recheck Git status for mirror: $($pair.CanonicalRelative)" }
    if (-not [string]::IsNullOrWhiteSpace(($dirty -join "`n"))) {
      throw "refusing to replace dirty mirror: $($pair.CanonicalRelative)"
    }
  }

  foreach ($pair in $validated) {
    if (Test-Path -LiteralPath $pair.DestinationPath) {
      Move-Item -LiteralPath $pair.DestinationPath -Destination $pair.BackupPath
      $movedDestination += $pair
    }
    Move-Item -LiteralPath $pair.StagedPath -Destination $pair.DestinationPath
    $installed += $pair
  }
} catch {
  $originalErrorMessage = $_.Exception.Message
  # Reverse order: undo the staged move first, then restore the old mirror.
  [array]::Reverse($installed)
  foreach ($pair in $installed) {
    Move-Item -LiteralPath $pair.DestinationPath -Destination $pair.StagedPath -ErrorAction SilentlyContinue
  }
  [array]::Reverse($movedDestination)
  foreach ($pair in $movedDestination) {
    Move-Item -LiteralPath $pair.BackupPath -Destination $pair.DestinationPath -ErrorAction SilentlyContinue
  }
  throw "mirror replacement failed and was rolled back. Original error: $originalErrorMessage"
} finally {
  foreach ($handle in $lockHandles) { if ($null -ne $handle) { $handle.Dispose() } }
  foreach ($pair in $validated) {
    if ($pair.PSObject.Properties.Name -contains 'LockPath' -and (Test-Path -LiteralPath $pair.LockPath -PathType Leaf)) {
      Remove-Item -LiteralPath $pair.LockPath -Force -ErrorAction SilentlyContinue
    }
  }
}

foreach ($pair in $validated) {
  if (Test-Path -LiteralPath $pair.BackupPath) {
    Remove-Item -LiteralPath $pair.BackupPath -Recurse -Force
  }
}
```

- [ ] **Step 9: Update the PowerShell callers and tests**

In `scripts/export_apps.ps1`, replace lines 64-67 with:

```powershell
  # Install every application in one call so a failure on the last does not
  # leave the earlier ones replaced.
  $replaceArgs = @()
  foreach ($appId in $appIds) {
    $replaceArgs += (Join-Path $stageParent $appId)
    $replaceArgs += "apps/$($env:APEX_PARSING_SCHEMA)/$appId"
  }
  & (Join-Path $PSScriptRoot "replace_mirror.ps1") @replaceArgs
```

In `scripts/backup_db.ps1`, collect pairs the same way and call `replace_mirror.ps1` once.

In `scripts/test_template.ps1`, every `-StagedDir X -Destination Y` call becomes positional `X Y` — the parameter no longer exists.

- [ ] **Step 10: Run every suite**

Run: `bash scripts/test_template.sh && bash scripts/test_export_orchestration.sh && bash scripts/test_backup_orchestration.sh && pwsh -NoProfile -File scripts/test_template.ps1`
Expected: all exit 0.

- [ ] **Step 11: Update the documented behavior**

In `docs/production-database-safety.md`, under "Export behavior", replace the sentence beginning "They read metadata, never export table data, and replace only exact targets" with:

```markdown
They read metadata, never export table data, and replace only exact targets
after every required export succeeds and Git confirms those targets have no
local changes. When more than one mirror is involved, all of them are locked
and replaced together: a failure part-way through rolls every completed
replacement back, so the tree is never left half-updated.
```

- [ ] **Step 12: Commit**

```bash
git add scripts/replace_mirror.sh scripts/replace_mirror.ps1 scripts/export_apps.sh scripts/export_apps.ps1 scripts/backup_db.sh scripts/backup_db.ps1 scripts/test_export_orchestration.sh scripts/test_template.ps1 docs/production-database-safety.md
git commit -m "$(cat <<'EOF'
fix: make multi-target mirror replacement atomic

Export and verification were already all-or-nothing, but replacement ran in a
loop with no rollback, so a failure on the second application or schema left
the first replaced. replace_mirror now takes every staged/destination pair,
validates and locks all of them, and unwinds every completed move on failure.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

# Phase 4 — APEXlang extractor

Fixes F12, F13, F14, F15, F16, F17, F18. Pure Python with an existing 24-test suite; no database, no Graphify install needed.

---

### Task 8: Parse the whole `FROM` list, and widen CTE detection

**Files:**
- Modify: `scripts/graphify_apexlang_extractor.py:53-58` (regexes), `:236-244` (`_sql_dependencies`)
- Test: `scripts/test_graphify_apexlang_extractor.py`

**Interfaces:**
- Consumes: nothing.
- Produces: `_from_items(text) -> Iterator[str]` yielding each top-level item of every `FROM`/`JOIN` clause. `READ_RE` is deleted; `CTE_RE` replaces the inline CTE regex. `_sql_dependencies` keeps its `(reads, writes, calls)` signature.

**Background.** `READ_RE` matches only the single token after `FROM`/`JOIN`, so `FROM orders o, customers c, order_items i` yields `{ORDERS}` and silently loses two tables. Widening it alone would make things worse: `WITH t (a,b) AS (SELECT …)` is not recognised as a CTE today, so `FROM t` would start emitting a phantom node for every such query. The two changes must land together.

The scanner below was prototyped against 16 queries — comma joins, ANSI joins, inline views, `TABLE(...)`, CTEs with and without column lists, multiple CTEs, schema-qualified and quoted identifiers, `GROUP BY`/`ORDER BY`/`FOR UPDATE`/`UNION` terminators, `UPDATE … SET`, and nested subqueries — and produced the expected reads for all of them.

- [ ] **Step 1: Write the failing tests**

Add to `scripts/test_graphify_apexlang_extractor.py`, inside `ApexlangExtractorTests`:

```python
    def test_reads_every_table_in_a_comma_separated_from_list(self) -> None:
        reads, _writes, _calls = extractor._sql_dependencies(
            "select o.id from orders o, customers c, order_items i where o.id = c.id"
        )
        self.assertEqual(reads, {"ORDERS", "CUSTOMERS", "ORDER_ITEMS"})

    def test_does_not_treat_a_cte_with_a_column_list_as_a_table(self) -> None:
        reads, _writes, _calls = extractor._sql_dependencies(
            "with t (a, b) as (select 1, 2 from dual) select a from t, orders"
        )
        self.assertEqual(reads, {"ORDERS"})

    def test_does_not_treat_the_table_operator_as_a_table(self) -> None:
        reads, _writes, _calls = extractor._sql_dependencies(
            "select 1 from table(pkg.pipe(x)), orders"
        )
        self.assertEqual(reads, {"ORDERS"})

    def test_stops_a_from_list_at_a_clause_keyword(self) -> None:
        reads, _writes, _calls = extractor._sql_dependencies(
            "select 1 from orders group by id"
        )
        self.assertEqual(reads, {"ORDERS"})

    def test_reads_tables_from_multiple_ctes_and_the_main_query(self) -> None:
        reads, _writes, _calls = extractor._sql_dependencies(
            "with a as (select 1 x from dual), b (y) as (select 2 from dual) "
            "select 1 from a, b, orders"
        )
        self.assertEqual(reads, {"ORDERS"})
```

- [ ] **Step 2: Run the extractor tests to verify they fail**

Run: `python3 scripts/test_graphify_apexlang_extractor.py -v`
Expected: FAIL on `test_reads_every_table_in_a_comma_separated_from_list` with `{'ORDERS'} != {'ORDERS', 'CUSTOMERS', 'ORDER_ITEMS'}`

- [ ] **Step 3: Replace the read/CTE regexes**

Delete `READ_RE` (line 55) and add, after `SUBSTITUTION_PART_RE`:

```python
FROM_START_RE = re.compile(r'\b(?:FROM|JOIN)\b', re.IGNORECASE)
# Keywords that end a FROM list. SELECT/WITH/AS are included because an
# unbalanced closing parenthesis is not the only way a clause can end.
FROM_STOP_RE = re.compile(
    r'\b(?:WHERE|GROUP|ORDER|HAVING|CONNECT|START|UNION|INTERSECT|MINUS|MODEL'
    r'|FETCH|OFFSET|FOR|JOIN|INNER|LEFT|RIGHT|FULL|CROSS|NATURAL|ON|USING|SET'
    r'|RETURNING|INTO|VALUES|SELECT|WITH|AS)\b',
    re.IGNORECASE,
)
FROM_ITEM_RE = re.compile(rf'^\s*({SQL_IDENTIFIER})')
# Row sources that are syntax, not tables.
FROM_KEYWORDS = {"table", "lateral", "xmltable", "json_table", "only", "the"}
# A CTE may carry a column list, and may be marked (NOT) MATERIALIZED. Missing
# one makes its later FROM reference look like a real table.
CTE_RE = re.compile(
    rf'\b({SQL_IDENTIFIER})\s*(?:\([^()]*\))?\s+AS\s*'
    rf'(?:NOT\s+MATERIALIZED\s+|MATERIALIZED\s+)?\(\s*(?:WITH|SELECT)\b',
    re.IGNORECASE,
)
```

- [ ] **Step 4: Add the `FROM`-clause scanner**

Add after `_blank_out`:

```python
def _from_items(text: str):
    """Yield every top-level item of every FROM/JOIN clause in *text*.

    A regex cannot do this: the clause ends at a keyword, at a top-level comma,
    or at a closing parenthesis that belongs to an enclosing clause, and a lazy
    match happily runs past that parenthesis into the next CTE.
    """
    for start in FROM_START_RE.finditer(text):
        index = item_start = start.end()
        depth = 0
        while index < len(text):
            char = text[index]
            if char == '(':
                depth += 1
            elif char == ')':
                if depth == 0:
                    break
                depth -= 1
            elif char == ',' and depth == 0:
                yield text[item_start:index]
                item_start = index + 1
            elif depth == 0 and (char.isalpha() or char == '_'):
                if FROM_STOP_RE.match(text, index):
                    if index > item_start:
                        yield text[item_start:index]
                    item_start = None
                    break
                index += re.match(r'[A-Za-z0-9_$#]*', text[index:]).end()
                continue
            index += 1
        if item_start is not None:
            yield text[item_start:index]
```

- [ ] **Step 5: Rewrite the read and CTE halves of `_sql_dependencies`**

Replace the `cte_names` and `reads` assignments:

```python
    cte_names = {
        _reference_label(match.group(1)).casefold()
        for match in re.finditer(
            rf'\b({SQL_IDENTIFIER})\s+AS\s*\(\s*SELECT\b',
            reads_clean,
            re.IGNORECASE,
        )
    }
    reads = {
        _reference_label(match.group(1))
        for match in READ_RE.finditer(reads_clean)
        if _reference_label(match.group(1)).casefold() not in cte_names
    }
```

with:

```python
    cte_names = {
        _reference_label(match.group(1)).casefold()
        for match in CTE_RE.finditer(reads_clean)
    }
    reads = set()
    for item in _from_items(reads_clean):
        item_match = FROM_ITEM_RE.match(item)
        if not item_match:
            continue
        if item_match.group(1).casefold() in FROM_KEYWORDS:
            continue
        label = _reference_label(item_match.group(1))
        if label.casefold() not in cte_names:
            reads.add(label)
```

- [ ] **Step 6: Run the extractor tests to verify they pass**

Run: `python3 scripts/test_graphify_apexlang_extractor.py -v`
Expected: all tests pass, including the 24 that existed before.

- [ ] **Step 7: Run the whole suite**

Run: `bash scripts/test_template.sh`
Expected: exit 0.

- [ ] **Step 8: Commit**

```bash
git add scripts/graphify_apexlang_extractor.py scripts/test_graphify_apexlang_extractor.py
git commit -m "$(cat <<'EOF'
fix: read every table in a FROM list, and recognise CTE column lists

FROM orders o, customers c, order_items i registered only ORDERS, silently
losing two tables from the graph. Widening that alone would have made things
worse: WITH t (a,b) AS (SELECT ...) was not recognised as a CTE, so its later
FROM reference would have become a phantom table node. Both land together.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 9: Attribute navigation to the application it actually targets

**Files:**
- Modify: `scripts/graphify_apexlang_extractor.py:47-48` (`PAGE_TARGET_RE`, `APEX_URL_PAGE_RE`), and the navigation block in `parse_apexlang`
- Test: `scripts/test_graphify_apexlang_extractor.py`

**Interfaces:**
- Consumes: Task 8's extractor.
- Produces: `APEX_URL_PAGE_RE` gains a leading capture group for the application segment; `parse_apexlang` tracks a `pending_application` local. `PAGE_TARGET_RE` is unchanged.

**Background.** `f?p=102:1:&SESSION.` inside application 101 currently produces an edge to `apex_app_101_page_1` — page 1 of the *calling* application. In a multi-application workspace every cross-application link is silently misrouted. The APEXlang property form (`application: 102` beside `page: 1`) has the same problem from the other direction, and needs a small piece of state because the two properties are on separate lines.

- [ ] **Step 1: Write the failing tests**

Add to `scripts/test_graphify_apexlang_extractor.py`:

```python
    def test_navigation_to_another_application_targets_that_application(self) -> None:
        source = (
            "app 101 (\n"
            "    name: Caller\n"
            "    page 5 (\n"
            "        name: Launcher\n"
            "        region go (\n"
            "            url: f?p=102:1:&SESSION.\n"
            "        )\n"
            "    )\n"
            ")\n"
        )
        result = extractor.parse_apexlang(source, Path("apps/DEMO/101/pages/p00005.apx"))
        targets = {
            edge["target"] for edge in result["edges"] if edge["relation"] == "navigates_to"
        }
        self.assertIn("apex_app_102_page_1", targets)
        self.assertNotIn("apex_app_101_page_1", targets)

    def test_navigation_with_a_substituted_application_stays_in_this_application(self) -> None:
        source = (
            "app 101 (\n"
            "    page 5 (\n"
            "        region go (\n"
            "            url: f?p=&APP_ID.:9:&SESSION.\n"
            "        )\n"
            "    )\n"
            ")\n"
        )
        result = extractor.parse_apexlang(source, Path("apps/DEMO/101/pages/p00005.apx"))
        targets = {
            edge["target"] for edge in result["edges"] if edge["relation"] == "navigates_to"
        }
        self.assertEqual(targets, {"apex_app_101_page_9"})

    def test_navigation_to_an_unresolvable_alias_emits_no_edge(self) -> None:
        source = (
            "app 101 (\n"
            "    page 5 (\n"
            "        region go (\n"
            "            url: f?p=my-alias:3:&SESSION.\n"
            "        )\n"
            "    )\n"
            ")\n"
        )
        result = extractor.parse_apexlang(source, Path("apps/DEMO/101/pages/p00005.apx"))
        targets = {
            edge["target"] for edge in result["edges"] if edge["relation"] == "navigates_to"
        }
        self.assertEqual(targets, set())

    def test_page_target_uses_a_sibling_application_property(self) -> None:
        source = (
            "app 101 (\n"
            "    page 5 (\n"
            "        region go (\n"
            "            application: 102\n"
            "            page: 7\n"
            "        )\n"
            "    )\n"
            ")\n"
        )
        result = extractor.parse_apexlang(source, Path("apps/DEMO/101/pages/p00005.apx"))
        targets = {
            edge["target"] for edge in result["edges"] if edge["relation"] == "navigates_to"
        }
        self.assertEqual(targets, {"apex_app_102_page_7"})
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `python3 scripts/test_graphify_apexlang_extractor.py -v`
Expected: FAIL on `test_navigation_to_another_application_targets_that_application` — `apex_app_102_page_1` is not in the targets.

- [ ] **Step 3: Capture the application segment in the URL pattern**

Replace line 48:

```python
APEX_URL_PAGE_RE = re.compile(r'f\?p=[^:\s]*:(\d+):', re.IGNORECASE)
```

with:

```python
# The application segment is captured, not discarded: in a multi-application
# workspace, attributing f?p=102:1: to the calling application silently routes
# every cross-application link to the wrong page.
APEX_URL_PAGE_RE = re.compile(r'f\?p=([^:\s]*):(\d+):', re.IGNORECASE)
APPLICATION_PROPERTY_RE = re.compile(r'^\s*application\s*:\s*(\d+)\s*$', re.IGNORECASE)
```

- [ ] **Step 4: Add the target-application resolver**

Add after `_nearest_owner`:

```python
def _navigation_application(segment: str | None, current_app_id: str) -> str | None:
    """Resolve the application an f?p target names.

    A numeric segment is that application. An empty segment or an APEX
    substitution such as &APP_ID. means this one. Anything else is an alias
    this extractor cannot resolve without the workspace, and guessing would
    reintroduce the misrouting this function exists to prevent.
    """
    if segment is None:
        return current_app_id
    segment = segment.strip()
    if not segment or segment.startswith("&"):
        return current_app_id
    if segment.isdigit():
        return segment
    return None
```

- [ ] **Step 5: Use it in the navigation block**

Replace the two navigation loops in `parse_apexlang`:

```python
        for page_match in PAGE_TARGET_RE.finditer(line):
            target = make_id("apex", "app", app_id, "page", page_match.group(1))
            if target != owner:
                add_edge(owner, target, "navigates_to", line_number)
        for page_match in APEX_URL_PAGE_RE.finditer(line):
            target = make_id("apex", "app", app_id, "page", page_match.group(1))
            if target != owner:
                add_edge(owner, target, "navigates_to", line_number)
```

with:

```python
        application_match = APPLICATION_PROPERTY_RE.match(line)
        if application_match:
            pending_application = application_match.group(1)

        for page_match in PAGE_TARGET_RE.finditer(line):
            target_app = _navigation_application(pending_application, app_id)
            if target_app is None:
                continue
            target = make_id("apex", "app", target_app, "page", page_match.group(1))
            if target != owner:
                add_edge(owner, target, "navigates_to", line_number)
        for page_match in APEX_URL_PAGE_RE.finditer(line):
            target_app = _navigation_application(page_match.group(1), app_id)
            if target_app is None:
                continue
            target = make_id("apex", "app", target_app, "page", page_match.group(2))
            if target != owner:
                add_edge(owner, target, "navigates_to", line_number)
```

- [ ] **Step 6: Initialise and reset `pending_application`**

Beside the existing `pending_property: str | None = None` initialisation, add:

```python
    pending_application: str | None = None
```

Reset it wherever `pending_property` is reset — in the component-close branch and in the fence-close branch — by adding this line beside each `pending_property = None`:

```python
            pending_application = None
```

Also reset it when a new component is declared, immediately before `frames.append(...)`:

```python
            pending_application = None
```

- [ ] **Step 7: Run the tests to verify they pass**

Run: `python3 scripts/test_graphify_apexlang_extractor.py -v`
Expected: all pass.

- [ ] **Step 8: Commit**

```bash
git add scripts/graphify_apexlang_extractor.py scripts/test_graphify_apexlang_extractor.py
git commit -m "$(cat <<'EOF'
fix: attribute APEX navigation to the application it actually targets

f?p=102:1: inside application 101 produced an edge to page 1 of application
101, so every cross-application link in a multi-app workspace was silently
misrouted. Numeric segments now resolve to that application, &APP_ID. and an
empty segment mean the current one, and an unresolvable alias emits no edge
rather than a wrong one.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 10: Give every `references_component` edge a target node

**Files:**
- Modify: `scripts/graphify_apexlang_extractor.py` (the `reference_match` branch in `parse_apexlang`)
- Test: `scripts/test_graphify_apexlang_extractor.py`

**Interfaces:**
- Consumes: Task 9's extractor.
- Produces: the LOV/list/build-option/authentication reference branch creates a `synthetic_reference=True` placeholder node before its edge, exactly as the `authorizationScheme` branch already does. The existing "declared component replaces a synthetic reference" behavior in `add_node` covers the merge.

- [ ] **Step 1: Write the failing test**

```python
    def test_component_reference_creates_a_placeholder_node(self) -> None:
        source = (
            "app 101 (\n"
            "    page 5 (\n"
            "        region picker (\n"
            "            listOfValues: @DEPARTMENTS\n"
            "        )\n"
            "    )\n"
            ")\n"
        )
        result = extractor.parse_apexlang(source, Path("apps/DEMO/101/pages/p00005.apx"))
        node_ids = {node["id"] for node in result["nodes"]}
        reference_edges = [
            edge for edge in result["edges"] if edge["relation"] == "references_component"
        ]
        self.assertEqual(len(reference_edges), 1)
        self.assertIn(reference_edges[0]["target"], node_ids)
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `python3 scripts/test_graphify_apexlang_extractor.py -k test_component_reference_creates_a_placeholder_node -v`
Expected: FAIL — the edge target is not among the node ids.

- [ ] **Step 3: Create the placeholder before the edge**

In the `reference_match` branch, replace:

```python
            if property_name in COMPONENT_REFERENCE_PROPERTIES and not is_template_reference:
                target_kind = COMPONENT_REFERENCE_PROPERTIES[property_name]
                target = make_id(app_node_id, target_kind, reference)
                add_edge(owner, target, "references_component", line_number)
```

with:

```python
            if property_name in COMPONENT_REFERENCE_PROPERTIES and not is_template_reference:
                target_kind = COMPONENT_REFERENCE_PROPERTIES[property_name]
                target = make_id(app_node_id, target_kind, reference)
                # A component declared in another file arrives with the same id
                # and replaces this placeholder; one that is never declared at
                # least leaves a visible dangling reference instead of an edge
                # pointing at nothing.
                add_node(
                    _node(
                        target,
                        _label(target_kind, reference),
                        source_path,
                        line_number,
                        component_type=target_kind,
                        application_id=app_id,
                        synthetic_reference=True,
                    )
                )
                add_edge(owner, target, "references_component", line_number)
```

- [ ] **Step 4: Run the full extractor suite**

Run: `python3 scripts/test_graphify_apexlang_extractor.py -v`
Expected: all pass — in particular `test_declared_authorization_replaces_an_earlier_synthetic_reference`, which proves the merge path this reuses.

- [ ] **Step 5: Commit**

```bash
git add scripts/graphify_apexlang_extractor.py scripts/test_graphify_apexlang_extractor.py
git commit -m "$(cat <<'EOF'
fix: give every references_component edge a target node

The LOV, list and build-option reference branch emitted an edge without
creating the node it pointed at, unlike the authorizationScheme branch beside
it. A reference to a component declared in another file merges as before; one
that is never declared now leaves a visible dangling reference.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 11: Make extraction failures visible, and pin the unqualified-call limitation

**Files:**
- Modify: `scripts/graphify_apexlang_extractor.py` (`extract_apexlang`)
- Test: `scripts/test_graphify_apexlang_extractor.py`

**Interfaces:**
- Consumes: Task 10's extractor.
- Produces: `extract_apexlang` catches `Exception`, writes a one-line warning to stderr, and still returns `{"nodes": [], "edges": [], "error": str(exc)}`.

**Background.** The catch tuple is narrow, but 13 targeted adversarial inputs and 4000 random strings produced no escaping exception — this is hardening, not a demonstrated bug. The reason to do it anyway is that a batch indexer should not die on one bad file. But broadening the catch **on its own** makes things worse: the `error` field is already where a malformed `.apx` goes to die unnoticed. The warning is the point; the wider catch is what makes the warning reachable.

Unqualified calls (`log_event('m');`) are deliberately **not** detected. The dot requirement in `PAREN_CALL_RE` is load-bearing: without it, `NVL(`, `TO_CHAR(` and `SUBSTR(` all become `calls` edges. Correct detection needs the `database/` symbol table, which is not available during per-file extraction. The test below pins the behavior so nobody "fixes" it into a flood of false edges.

- [ ] **Step 1: Write the failing tests**

```python
    def test_reports_an_unexpected_failure_without_raising(self) -> None:
        broken = Path("apps/DEMO/101/pages/does-not-exist.apx")
        with mock.patch.object(
            extractor, "parse_apexlang", side_effect=RuntimeError("boom")
        ), mock.patch.object(Path, "read_text", return_value="app 1 (\n)\n"):
            with contextlib.redirect_stderr(io.StringIO()) as captured:
                result = extractor.extract_apexlang(broken)
        self.assertEqual(result["nodes"], [])
        self.assertIn("boom", result["error"])
        self.assertIn(str(broken), captured.getvalue())

    def test_unqualified_calls_are_deliberately_not_detected(self) -> None:
        # The dot requirement in PAREN_CALL_RE is load-bearing: without it every
        # SQL built-in (NVL, TO_CHAR, SUBSTR) becomes a `calls` edge. Resolving
        # unqualified names needs the database/ symbol table, which per-file
        # extraction does not have. Do not "fix" this without that.
        _reads, _writes, calls = extractor._sql_dependencies("begin log_event('m'); end;")
        self.assertEqual(calls, set())
        _reads, _writes, calls = extractor._sql_dependencies("begin pkg.proc(x); end;")
        self.assertEqual(calls, {"PKG.PROC"})
```

Add these imports at the top of the test file if they are not already present:

```python
import contextlib
import io
from unittest import mock
```

- [ ] **Step 2: Run the tests to verify the first fails**

Run: `python3 scripts/test_graphify_apexlang_extractor.py -k unexpected_failure -v`
Expected: FAIL — `RuntimeError: boom` escapes the catch tuple.

- [ ] **Step 3: Widen the catch and add the warning**

Replace `extract_apexlang`:

```python
def extract_apexlang(path: Path) -> dict[str, object]:
    """Graphify extractor entry point."""
    try:
        text = path.read_text(encoding="utf-8")
        return parse_apexlang(text, path)
    except (OSError, UnicodeError, ApexlangParseError) as exc:
        return {"nodes": [], "edges": [], "error": str(exc)}
```

with:

```python
def extract_apexlang(path: Path) -> dict[str, object]:
    """Graphify extractor entry point.

    Never raises: one malformed file must not end a batch indexing run. The
    warning matters as much as the catch -- returning an `error` nobody reads
    is how a file silently vanishes from the graph.
    """
    try:
        text = path.read_text(encoding="utf-8")
        return parse_apexlang(text, path)
    except Exception as exc:  # noqa: BLE001 - see the docstring
        print(
            f"Warning: APEXlang extraction failed for {path}: "
            f"{type(exc).__name__}: {exc}",
            file=sys.stderr,
        )
        return {"nodes": [], "edges": [], "error": str(exc)}
```

Add `import sys` to the imports at the top of the file, after `import re`.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `python3 scripts/test_graphify_apexlang_extractor.py -v`
Expected: all pass.

- [ ] **Step 5: Reinstall the extractor into Graphify and re-verify**

Because the installed copy is compared byte-for-byte against the canonical source, an extractor change invalidates the installation.

Run: `python3 setup_graphify_apx.py`
Expected: `Graphify at '<path>' is configured with the project APEXlang extractor`

- [ ] **Step 6: Commit**

```bash
git add scripts/graphify_apexlang_extractor.py scripts/test_graphify_apexlang_extractor.py
git commit -m "$(cat <<'EOF'
fix: report an APEXlang extraction failure instead of vanishing

One malformed .apx must not end a batch indexing run, so the catch widens to
Exception -- but a wider catch alone would make failures more silent, because
the returned `error` field is not surfaced anywhere. The stderr warning is the
point of the change.

Also pins the deliberate non-detection of unqualified PL/SQL calls: the dot
requirement keeps NVL/TO_CHAR/SUBSTR out of the graph, and resolving bare names
needs a symbol table per-file extraction does not have.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

# Phase 5 — Graphify installer

Fixes F8, F9, F10, F11.

---

### Task 12: Patch the Graphify behind `graphify` on PATH, and always invalidate the cache

**Files:**
- Modify: `setup_graphify_apx.py:22-48` (`find_graphify_dirs`), `:233-267` (`setup_graphify_apx`)
- Test: `scripts/test_setup_graphify.py`

**Interfaces:**
- Consumes: nothing.
- Produces: `graphify_console_interpreter() -> str | None` returning the interpreter path behind the `graphify` console script; `find_graphify_dirs()` prefers that interpreter's package and falls back to the glob sweep with a warning. `setup_graphify_apx()` invalidates the `.apx` AST cache whenever **at least one** directory was patched, and still returns `False` unless all did.

**Background.** "Use the current interpreter" is not the fix: for a `uv tool install`, the invoking Python is never the tool's interpreter, which is precisely why the glob sweep exists. The shim's shebang — already read at lines 240-248 for the pip step — is the right target. And `if not all(results): return False` currently short-circuits before `invalidate_apx_cache`, so one stale orphan environment leaves the *working* environment with stale `.apx` AST cache: exactly the regression `self_improve.md` records.

- [ ] **Step 1: Write the failing tests**

Add to `scripts/test_setup_graphify.py`, inside `GraphifyPatchTests`:

First make the existing fixture reusable for two packages. `write_package` currently hardcodes `self.root`; parameterise it and keep the old call site working:

```python
    def write_package_at(self, base: Path) -> None:
        (base / "extractors").mkdir(parents=True, exist_ok=True)
        (base / "detect.py").write_text(
            "CODE_EXTENSIONS = {'.sql',}\n",
            encoding="utf-8",
        )
        (base / "extract.py").write_text(
            "from graphify.extractors.sql import extract_sql  # noqa: F401\n"
            '_DISPATCH = {\n    ".sql": extract_sql,\n}\n'
            '_EXTRA_FOR_EXTENSION = {\n    ".sql": "sql",\n}\n',
            encoding="utf-8",
        )

    def write_package(self) -> None:
        self.write_package_at(self.root)
```

Then add the two tests. Note the module is bound as `MODULE` in this file, not by its own name:

```python
    def test_invalidates_apx_cache_when_only_some_directories_patch(self) -> None:
        good = self.root / "good"
        broken = self.root / "broken"
        self.write_package_at(good)
        self.write_package_at(broken)
        (broken / "extract.py").write_text("nothing to anchor on\n", encoding="utf-8")
        cache = MODULE.REPO_ROOT / "graphify-out" / "cache" / "ast"
        cache.mkdir(parents=True, exist_ok=True)
        stale = cache / "partial-setup-fixture.json"
        stale.write_text(
            json.dumps({"nodes": [{"source_file": "apps/DEMO/101/pages/p1.apx"}]}),
            encoding="utf-8",
        )
        self.addCleanup(lambda: stale.unlink(missing_ok=True))
        with mock.patch.object(
            MODULE, "find_graphify_dirs", return_value=[str(good), str(broken)]
        ):
            self.assertFalse(MODULE.setup_graphify_apx())
        self.assertFalse(
            stale.exists(),
            "a partially successful setup must still invalidate stale .apx cache",
        )

    def test_prefers_the_interpreter_behind_the_graphify_console_script(self) -> None:
        self.assertTrue(hasattr(MODULE, "graphify_console_interpreter"))
```

Add `import json` and `from unittest import mock` to the test file's imports.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `python3 scripts/test_setup_graphify.py -v`
Expected: FAIL on `test_invalidates_apx_cache_when_only_some_directories_patch` — the stale cache file still exists.

- [ ] **Step 3: Extract the interpreter resolver**

Add before `find_graphify_dirs`:

```python
def graphify_console_interpreter() -> str | None:
    """Return the interpreter behind the `graphify` console script on PATH.

    A `uv tool install` gives Graphify its own isolated interpreter, so
    importing graphify in *this* process usually finds nothing, or finds a
    different copy. The console script's shebang names the right one. Windows
    shims are compiled .exe launchers with no shebang to read.
    """
    graphify_bin = shutil.which("graphify")
    if not graphify_bin or not os.path.exists(graphify_bin):
        return None
    try:
        with open(graphify_bin, "r", encoding="utf-8") as handle:
            first_line = handle.readline()
    except (UnicodeDecodeError, OSError):
        return None
    if not first_line.startswith("#!"):
        return None
    interpreter = first_line.strip()[2:].strip()
    return interpreter if os.path.exists(interpreter) else None
```

- [ ] **Step 4: Prefer that interpreter in `find_graphify_dirs`**

Replace the body of `find_graphify_dirs` from its first line through `dirs.append(os.path.dirname(graphify.__file__))`:

```python
def find_graphify_dirs():
    dirs = []
    # 1. Try importing graphify in current python
    try:
        import graphify
        dirs.append(os.path.dirname(graphify.__file__))
    except Exception:
        pass
```

with:

```python
def find_graphify_dirs():
    # 1. The interpreter behind `graphify` on PATH is the installation that
    #    actually runs. Patch only that one when it can be resolved: sweeping
    #    every globbed path makes an orphaned environment fail the whole setup.
    interpreter = graphify_console_interpreter()
    if interpreter:
        try:
            located = subprocess.run(
                [interpreter, "-c",
                 "import graphify, os; print(os.path.dirname(graphify.__file__))"],
                capture_output=True, text=True, timeout=30,
            )
            if located.returncode == 0 and located.stdout.strip():
                candidate = located.stdout.strip()
                if os.path.isdir(candidate):
                    return [candidate]
        except (OSError, subprocess.SubprocessError):
            pass

    dirs = []
    # 2. Fall back to this interpreter, then to a filesystem sweep.
    try:
        import graphify
        dirs.append(os.path.dirname(graphify.__file__))
    except Exception:
        pass
```

Renumber the remaining comments in the function from `# 2.`/`# 3.` to `# 3.`/`# 4.`, and add this line immediately before the final `return sorted(set(dirs))`:

```python
    if len(dirs) > 1:
        print("Warning: could not resolve the active Graphify from PATH; "
              f"patching {len(dirs)} candidate installation(s)")
```

- [ ] **Step 5: Invalidate the cache whenever anything was patched**

Replace lines 261-267:

```python
    results = [patch_graphify_dir(Path(base)) for base in g_dirs]
    if not all(results):
        return False
    removed = invalidate_apx_cache(REPO_ROOT / "graphify-out" / "cache" / "ast")
    if removed:
        print(f"Invalidated {removed} stale APEXlang AST cache entr{'y' if removed == 1 else 'ies'}")
    return True
```

with:

```python
    results = {base: patch_graphify_dir(Path(base)) for base in g_dirs}
    for base, patched in results.items():
        if not patched:
            print(f"Warning: Graphify at '{base}' was not configured")
    if not any(results.values()):
        return False
    # A cache invalidation skipped because some *other* installation failed is
    # how the graph ends up with cached .apx results from the former SQL route:
    # zero architectural relationships, no error. Invalidate whenever any
    # installation was actually patched.
    removed = invalidate_apx_cache(REPO_ROOT / "graphify-out" / "cache" / "ast")
    if removed:
        print(f"Invalidated {removed} stale APEXlang AST cache entr{'y' if removed == 1 else 'ies'}")
    return all(results.values())
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `python3 scripts/test_setup_graphify.py -v && bash scripts/test_template.sh`
Expected: both exit 0.

- [ ] **Step 7: Commit**

```bash
git add setup_graphify_apx.py scripts/test_setup_graphify.py
git commit -m "$(cat <<'EOF'
fix: target the active Graphify, and invalidate the cache on partial success

`if not all(results): return False` short-circuited before the .apx AST cache
was invalidated, so one stale orphan environment left the *working* one with
cached results from the former SQL route -- zero architectural relationships,
no error, which is the regression self_improve.md already records.

Also resolves the installation to patch from the graphify console script's
shebang rather than sweeping every globbed path. The current interpreter is not
a substitute: a uv tool install has its own.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 13: Report the `tree-sitter-sql` install, and add a verification mode

**Files:**
- Modify: `setup_graphify_apx.py:236-253` (pip step), `:269-270` (entry point)
- Test: `scripts/test_setup_graphify.py`

**Interfaces:**
- Consumes: Task 12's `graphify_console_interpreter`.
- Produces: `main(argv: list[str]) -> int` supporting `--verify`, which checks every located installation without modifying anything and returns non-zero if any fails. The pip step reports a non-zero exit instead of discarding it.

- [ ] **Step 1: Write the failing test**

```python
    def test_verify_mode_reports_an_unpatched_installation(self) -> None:
        self.write_package()
        with mock.patch.object(
            MODULE, "find_graphify_dirs", return_value=[str(self.root)]
        ):
            self.assertEqual(MODULE.main(["--verify"]), 1)

    def test_verify_mode_accepts_a_patched_installation(self) -> None:
        self.write_package()
        self.assertTrue(MODULE.patch_graphify_dir(self.root))
        with mock.patch.object(
            MODULE, "find_graphify_dirs", return_value=[str(self.root)]
        ):
            self.assertEqual(MODULE.main(["--verify"]), 0)
```

- [ ] **Step 2: Run it to verify it fails**

Run: `python3 scripts/test_setup_graphify.py -k verify_mode -v`
Expected: FAIL with `AttributeError: module 'setup_graphify_apx' has no attribute 'main'`

- [ ] **Step 3: Make the pip step honest**

Replace lines 236-253:

```python
    # Attempt uv pip install first
    graphify_bin = shutil.which("graphify")
    if graphify_bin and os.path.exists(graphify_bin):
        try:
            with open(graphify_bin, "r") as f:
                first_line = f.readline()
        except (UnicodeDecodeError, OSError):
            # Windows pip/uv console-script shims are compiled .exe launchers,
            # not shebang scripts — nothing to sniff, just skip this step.
            first_line = ""
        if first_line.startswith("#!"):
            py_path = first_line.strip()[2:]
            if os.path.exists(py_path):
                subprocess.run([py_path, "-m", "pip", "install", "tree-sitter-sql"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                try:
                    subprocess.run(["uv", "pip", "install", "--python", py_path, "tree-sitter-sql"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                except Exception:
                    pass
```

with:

```python
    # Best-effort: the supported path is `uv tool install graphifyy --with
    # tree-sitter-sql`. Report what happened rather than discarding it -- a
    # silent failure here shows up much later as an unindexable database/ tree.
    py_path = graphify_console_interpreter()
    if py_path:
        installed = False
        for command in (
            [py_path, "-m", "pip", "install", "tree-sitter-sql"],
            ["uv", "pip", "install", "--python", py_path, "tree-sitter-sql"],
        ):
            try:
                completed = subprocess.run(command, capture_output=True, text=True, timeout=300)
            except (OSError, subprocess.SubprocessError):
                continue
            if completed.returncode == 0:
                installed = True
                break
        if not installed:
            print("Note: could not install tree-sitter-sql into Graphify's interpreter.\n"
                  "      Without it, database/ and supporting-objects/*.sql cannot be indexed.\n"
                  "      Install it with Graphify instead:\n"
                  "        uv tool install graphifyy --with tree-sitter-sql --force")
```

- [ ] **Step 4: Add `main` with `--verify`**

Replace the entry point at lines 269-270:

```python
if __name__ == "__main__":
    raise SystemExit(0 if setup_graphify_apx() else 1)
```

with:

```python
def main(argv: list[str]) -> int:
    """Entry point. `--verify` checks the installation without changing it."""
    if "--verify" in argv:
        bases = find_graphify_dirs()
        if not bases:
            print("Graphify installation not found")
            return 1
        failed = False
        for base in bases:
            verified, reason = verify_installation(Path(base))
            print(f"{'OK  ' if verified else 'FAIL'} {base}: {reason}")
            failed = failed or not verified
        return 1 if failed else 0
    return 0 if setup_graphify_apx() else 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
```

- [ ] **Step 5: Run the tests**

Run: `python3 scripts/test_setup_graphify.py -v && bash scripts/test_template.sh`
Expected: both exit 0.

- [ ] **Step 6: Make the workflow use `--verify` as a pre-flight**

In `.agents/workflows/graphify.md`, replace the "Upgrade gate" section body with:

```markdown
A Graphify upgrade replaces `site-packages` and silently removes the APEXlang
patches; nothing detects the reverted state at query time. Before any
`graphify update` or `graphify extract`, run the pre-flight — it changes
nothing and exits non-zero when the integration is not installed:

```bash
python3 setup_graphify_apx.py --verify
```

If it fails, run `python3 setup_graphify_apx.py` to reinstall. Graphify has no
supported APEXlang extension point, so setup validates the current package
anchors and fails closed if an upgrade is incompatible. Never repair the
installed copy by hand; update the tracked extractor/setup and their tests so
the fix persists for every template user.
```

Add the same pre-flight line to the Rules list in `.agents/rules/graphify.md`, replacing the final bullet:

```markdown
- Before `graphify update` or `graphify extract`, run `python3 setup_graphify_apx.py --verify`. It changes nothing and exits non-zero if a Graphify upgrade has silently reverted the APEXlang integration; reinstall with `python3 setup_graphify_apx.py` when it does.
```

- [ ] **Step 7: Commit**

```bash
git add setup_graphify_apx.py scripts/test_setup_graphify.py .agents/workflows/graphify.md .agents/rules/graphify.md
git commit -m "$(cat <<'EOF'
feat: add setup_graphify_apx.py --verify, and report the tree-sitter-sql install

The tree-sitter-sql step discarded stdout, stderr and the exit code, so a
failure was invisible until database/ turned out to be unindexable. And a
Graphify upgrade silently reverts the APEXlang patches with nothing detecting
it at query time -- --verify is a pre-flight the workflow can run before every
update instead of relying on someone remembering an upgrade happened.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

# Phase 6 — Documentation, hygiene, CI

Fixes F1, F22, F23, F25, F26, F27.

---

### Task 14: Resolve the Graphify required-vs-optional contradiction

> **Confirm the decision before starting.** This task assumes Graphify is **optional but strongly recommended**, and corrects `README.md`. If it is meant to be hard-required, invert: keep the README and delete the `graphify-out/graph.json` gating from `.agents/rules/graphify.md`.

**Files:**
- Modify: `README.md:23`, `README.md:50`, `.agents/rules/graphify.md:9-10`
- Test: `scripts/test_graphify_corpus.py`

**Interfaces:**
- Consumes: nothing.
- Produces: one consistent statement of Graphify's status across all four documents, and a test that fails if they diverge again.

- [ ] **Step 1: Write the failing test**

Add to `scripts/test_graphify_corpus.py`, inside `GraphifyCorpusTests`:

```python
    def test_graphify_status_is_stated_consistently(self) -> None:
        readme = (REPO_ROOT / "README.md").read_text(encoding="utf-8")
        agents = (REPO_ROOT / "AGENTS.md").read_text(encoding="utf-8")
        rules = (REPO_ROOT / ".agents/rules/graphify.md").read_text(encoding="utf-8")
        # Every rule in the rules file is gated on graphify-out/ existing, and
        # the scripts work without Graphify. "Required" in the README was the
        # outlier, and agents read AGENTS.md as authoritative.
        self.assertNotIn("Graphify is required for this project", readme)
        self.assertIn("optional", agents.lower())
        self.assertIn("if `graphify-out/`", rules)
```

- [ ] **Step 2: Run it to verify it fails**

Run: `python3 scripts/test_graphify_corpus.py -k status_is_stated -v`
Expected: FAIL — `'Graphify is required for this project' unexpectedly found in readme`

- [ ] **Step 3: Correct the README prerequisites table**

Replace `README.md:23`:

```markdown
| **Graphify** | Required. The knowledge graph this template is built around; see [Knowledge graph](#knowledge-graph) below |
```

with:

```markdown
| **Graphify** | Strongly recommended. The knowledge graph this template is built around; everything works without it, but agents fall back on grep. See [Knowledge graph](#knowledge-graph) below |
```

- [ ] **Step 4: Correct the README knowledge-graph section**

Replace `README.md:50`:

```markdown
Graphify is required for this project. It indexes a domain-only corpus
```

with:

```markdown
Graphify is optional, and strongly recommended. Every script, guard, and export
in this template works without it; what you lose is the scoped-subgraph answer
to architecture questions, and agents fall back on repository-wide grep. It
indexes a domain-only corpus
```

- [ ] **Step 5: Fix the install pointer in the rules file**

Replace `.agents/rules/graphify.md:9-10`:

```markdown
This project can use a domain-focused graphify knowledge graph at graphify-out/, if the
`graphify` CLI is installed (https://github.com/ash2osh — see `AGENTS.md`
"Optional Tooling"). It is not guaranteed to be present; if `graphify-out/`
```

with:

```markdown
This project can use a domain-focused graphify knowledge graph at graphify-out/, if the
`graphify` CLI is installed (`uv tool install graphifyy --with tree-sitter-sql`
— note the distribution is `graphifyy` and the command is `graphify`; see
`AGENTS.md` "Optional Tooling"). It is not guaranteed to be present; if `graphify-out/`
```

- [ ] **Step 6: Run the tests and the link checker**

Run: `python3 scripts/test_graphify_corpus.py -v && python3 scripts/check_local_links.py . && bash scripts/test_template.sh`
Expected: all exit 0.

- [ ] **Step 7: Commit**

```bash
git add README.md .agents/rules/graphify.md scripts/test_graphify_corpus.py
git commit -m "$(cat <<'EOF'
docs: state Graphify's status consistently

README.md called Graphify required while AGENTS.md, the rules file and the
workflow all called it optional -- and agents read AGENTS.md as authoritative.
Every rule is already gated on graphify-out/ existing and the scripts work
without it, so the README was the outlier.

Also replaces a bare GitHub profile URL with the actual install command.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 15: PowerShell path and encoding hygiene

**Files:**
- Modify: `scripts/normalize_apx.ps1:14-18`, `scripts/backup_db.ps1:89,103`, `scripts/export_apps.ps1:21`, `scripts/load_env.sh` (final unset block)
- Test: `scripts/test_template.sh`, `scripts/test_template.ps1`

**Interfaces:**
- Consumes: Phase 1–3's scripts.
- Produces: no glob-expanding `-Path` on a caller-supplied path; `normalize_apx.ps1` preserves a UTF-8 BOM as `perl -pi` does; `load_env.sh` unsets its own functions.

- [ ] **Step 1: Write the failing tests**

Add to `scripts/test_template.sh`:

```bash
# perl -pi is byte-oriented and preserves a BOM; the PowerShell normalizer must
# not silently rewrite the bytes of the one file type .gitattributes exists to
# keep stable.
BOM_DIR="$TEST_ROOT/bom"
mkdir -p "$BOM_DIR"
printf '\xEF\xBB\xBFapp 1 (\r\n)\r\n' > "$BOM_DIR/application.apx"
"$REPO_ROOT/scripts/normalize_apx.sh" "$BOM_DIR"
test "$(head -c 3 "$BOM_DIR/application.apx" | od -An -tx1 | tr -d ' ')" = "efbbbf" \
  || fail "the Bash normalizer stripped a UTF-8 BOM"
! LC_ALL=C grep -q $'\r' "$BOM_DIR/application.apx" \
  || fail "the Bash normalizer left a CR"

# load_env.sh must not leave its helpers defined in the caller's shell, which is
# what load_env.ps1's cleanup comment claims it mirrors.
LEAKED_FUNCTIONS="$(bash -c 'source "$1" "$2" >/dev/null 2>&1; declare -F | grep -c project_env' \
  _ "$REPO_ROOT/scripts/load_env.sh" "$ENV_FILE")"
test "$LEAKED_FUNCTIONS" = "0" \
  || fail "load_env.sh left $LEAKED_FUNCTIONS helper function(s) defined in the caller"
```

Add to `scripts/test_template.ps1`:

```powershell
  $bomDir = Join-Path $testRoot "bom"
  New-Item -ItemType Directory -Force -Path $bomDir | Out-Null
  $bomBytes = [byte[]]@(0xEF, 0xBB, 0xBF) + [System.Text.Encoding]::UTF8.GetBytes("app 1 (`r`n)`r`n")
  [System.IO.File]::WriteAllBytes((Join-Path $bomDir "application.apx"), $bomBytes)
  & (Join-Path $PSScriptRoot "normalize_apx.ps1") $bomDir
  $normalized = [System.IO.File]::ReadAllBytes((Join-Path $bomDir "application.apx"))
  Assert-True ($normalized[0] -eq 0xEF -and $normalized[1] -eq 0xBB -and $normalized[2] -eq 0xBF) `
    "the PowerShell normalizer stripped a UTF-8 BOM"
  Assert-True (-not ($normalized -contains 0x0D)) "the PowerShell normalizer left a CR"

  # A repository cloned under a directory containing [ or ] must still work.
  $globDir = Join-Path $testRoot "glob[1]"
  New-Item -ItemType Directory -Force -Path $globDir | Out-Null
  [System.IO.File]::WriteAllText((Join-Path $globDir "application.apx"), "app 1 (`r`n)`r`n")
  & (Join-Path $PSScriptRoot "normalize_apx.ps1") $globDir
  Assert-True (-not ([System.IO.File]::ReadAllText((Join-Path $globDir "application.apx")).Contains("`r"))) `
    "normalize_apx.ps1 did not normalize a path containing glob characters"
```

- [ ] **Step 2: Run both suites to verify they fail**

Run: `bash scripts/test_template.sh`
Expected: FAIL with `load_env.sh left 2 helper function(s) defined in the caller`

Run: `pwsh -NoProfile -File scripts/test_template.ps1`
Expected: FAIL with `the PowerShell normalizer stripped a UTF-8 BOM`

- [ ] **Step 3: Fix `normalize_apx.ps1`**

Replace lines 14-18:

```powershell
Get-ChildItem -Path $TargetDir -Filter *.apx -Recurse | ForEach-Object {
  $path = $_.FullName
  $text = [System.IO.File]::ReadAllText($path) -replace "`r`n", "`n" -replace "`r", "`n"
  $text = $text.TrimEnd("`n") + "`n"
  [System.IO.File]::WriteAllText($path, $text, [System.Text.UTF8Encoding]::new($false))
}
```

with:

```powershell
# -LiteralPath, because a clone under a directory containing [ or ] must work.
Get-ChildItem -LiteralPath $TargetDir -Filter *.apx -Recurse | ForEach-Object {
  $path = $_.FullName
  # perl -pi is byte-oriented and preserves a BOM. Detect and re-emit it so the
  # two normalizers produce identical bytes for identical input.
  $bytes = [System.IO.File]::ReadAllBytes($path)
  $hasBom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
  $text = [System.IO.File]::ReadAllText($path) -replace "`r`n", "`n" -replace "`r", "`n"
  $text = $text.TrimEnd("`n") + "`n"
  [System.IO.File]::WriteAllText($path, $text, (New-Object System.Text.UTF8Encoding($hasBom)))
}
```

> `ReadAllText` strips the BOM from the decoded string, so re-emitting it is the encoder's job — which is why `$hasBom` is read from the raw bytes. `New-Object` rather than `::new()` keeps the PSScriptAnalyzer 5.1 profile happy.

- [ ] **Step 4: Replace glob-expanding `-Path` on caller-supplied paths**

In `scripts/backup_db.ps1`, replace line 89 and line 103:

```powershell
New-Item -ItemType Directory -Force -Path $scratchPath | Out-Null
```
```powershell
  Push-Location $stagingPath
```

with:

```powershell
New-Item -ItemType Directory -Force -LiteralPath $scratchPath | Out-Null
```
```powershell
  Push-Location -LiteralPath $stagingPath
```

In `scripts/export_apps.ps1`, replace line 21:

```powershell
New-Item -ItemType Directory -Force -Path $scratchPath | Out-Null
```

with:

```powershell
New-Item -ItemType Directory -Force -LiteralPath $scratchPath | Out-Null
```

Then sweep for any remaining case:

Run: `grep -n -- '-Path \$' scripts/*.ps1`
Expected: every remaining hit is a literal path the script itself constructed, not one a caller supplied. Convert any that is caller-supplied.

- [ ] **Step 5: Unset the Bash loader's helper functions**

Append to `scripts/load_env.sh` after the existing `unset` lines:

```bash
# load_env.ps1 removes its helper and says it is mirroring this file. It was
# not: only variables were unset, leaving two functions in the caller's shell.
unset -f project_env_fail project_env_validate_unique_csv
```

- [ ] **Step 6: Run both suites to verify they pass**

Run: `bash scripts/test_template.sh && pwsh -NoProfile -File scripts/test_template.ps1`
Expected: both exit 0.

- [ ] **Step 7: Commit**

```bash
git add scripts/normalize_apx.ps1 scripts/backup_db.ps1 scripts/export_apps.ps1 scripts/load_env.sh scripts/test_template.sh scripts/test_template.ps1
git commit -m "$(cat <<'EOF'
fix: PowerShell path and encoding hygiene

normalize_apx stripped a UTF-8 BOM in PowerShell and preserved it in Bash, so
the two halves produced different bytes for identical input -- on the one file
type .gitattributes exists to keep stable. Caller-supplied paths now use
-LiteralPath so a clone under a directory containing [ or ] works.

Also unsets the two helper functions load_env.sh was leaving in the caller's
shell, which load_env.ps1's cleanup comment already claimed to mirror.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 16: Close the remaining documentation and CI gaps

**Files:**
- Modify: `.agents/skills/install-uc-apx/SKILL.md`, `AGENTS.md:167-181` (§6), `.github/workflows/template-checks.yml`, `README.md` (troubleshooting)
- Test: `scripts/test_template.sh`

**Interfaces:**
- Consumes: everything above.
- Produces: consistent loader invocation across both skills; a check that `AGENTS.md` §6 was filled in; shellcheck in CI; documented recovery for a stale `graphify-out/`.

- [ ] **Step 1: Write the failing tests**

Add to `scripts/test_template.sh`, in the documentation-assertion block:

```bash
# Both skills must invoke the PowerShell loader the way the file requires.
grep -q '\. scripts/load_env\.ps1\|\. \./scripts/load_env\.ps1' \
  "$REPO_ROOT/.agents/skills/install-uc-apx/SKILL.md" \
  || fail "install-uc-apx does not dot-source the PowerShell loader"

# AGENTS.md section 6 is a fill-in table. Warn while the placeholders remain, so
# a configured project cannot silently keep the template's example schemas.
if grep -q '<PROJECT>_DATA' "$REPO_ROOT/AGENTS.md"; then
  grep -q 'Replace this table' "$REPO_ROOT/AGENTS.md" \
    || fail "AGENTS.md section 6 still holds placeholders without saying so"
fi
```

- [ ] **Step 2: Run the suite to verify it fails**

Run: `bash scripts/test_template.sh`
Expected: FAIL with `install-uc-apx does not dot-source the PowerShell loader`

- [ ] **Step 3: Fix the skill's loader invocation**

In `.agents/skills/install-uc-apx/SKILL.md`, replace:

```markdown
2. Read it with `. scripts/load_env.sh .env` on Bash or
   `scripts/load_env.ps1 -EnvFile .env` on PowerShell. Never `source`, `eval`,
   or execute `.env` directly.
```

with:

```markdown
2. Read it with `. scripts/load_env.sh .env` on Bash or
   `. ./scripts/load_env.ps1 -EnvFile .env` on PowerShell — both are
   dot-sourced, which is what those files require. Never `source`, `eval`,
   or execute `.env` directly.
```

- [ ] **Step 4: Mark §6 as unfilled**

In `AGENTS.md`, immediately after the `## 6. Schema Ownership (fill in for this project)` heading, add:

```markdown
> **Replace this table before doing schema work.** The rows below are the
> template's examples, not this project's schemas. `scripts/test_template.sh`
> checks only that this notice is still here while the placeholders are — it
> cannot tell you the table is wrong once you remove it.
```

- [ ] **Step 5: Add shellcheck to CI**

In `.github/workflows/template-checks.yml`, add to the `linux` job immediately after the "Check shell syntax" step:

```yaml
      # The scripts carry `# shellcheck source=` directives, so `bash -n` alone
      # was leaving the tool they were written for unrun.
      - name: Run shellcheck
        run: |
          sudo apt-get update -qq && sudo apt-get install -y shellcheck
          shellcheck --severity=warning scripts/*.sh
```

- [ ] **Step 6: Run shellcheck locally and fix what it finds**

Run: `shellcheck --severity=warning scripts/*.sh`
Expected: no output. If it reports anything, fix the script — not the severity threshold. The likeliest hits after Phase 3 are `SC2086` (unquoted expansion) and `SC2178`/`SC2128` around the new arrays; both are real and worth fixing.

- [ ] **Step 7: Document stale-graph recovery**

Add to `README.md`, at the end of the "Knowledge graph" section:

```markdown
`graphify-out/` is local state and is gitignored, so it can outlive the sources
it describes — a clone that indexed a demo application keeps answering from it
after those files are gone, and `.agents/rules/graphify.md` is `always_on`, so
every agent is routed there first. Check it:

```bash
git rev-parse HEAD
python3 -c "import json; print(json.load(open('graphify-out/graph.json'))['built_at_commit'])"
```

If the commits differ substantially, or if the indexed sources no longer exist,
rebuild with `graphify extract . --force` or delete `graphify-out/` — every
rule is gated on it existing, so removing it is safe.
```

- [ ] **Step 8: Run everything**

Run: `bash scripts/test_template.sh && bash scripts/test_export_orchestration.sh && bash scripts/test_backup_orchestration.sh && pwsh -NoProfile -File scripts/test_template.ps1 && python3 scripts/check_local_links.py .`
Expected: all exit 0.

- [ ] **Step 9: Commit**

```bash
git add .agents/skills/install-uc-apx/SKILL.md AGENTS.md .github/workflows/template-checks.yml README.md scripts/test_template.sh
git commit -m "$(cat <<'EOF'
docs: close the remaining loader, schema-table and CI gaps

install-uc-apx invoked the PowerShell loader without dot-sourcing while
initialize-project dot-sourced it. AGENTS.md section 6 held template
placeholders with nothing saying so. CI ran `bash -n` but never shellcheck,
despite the scripts carrying shellcheck directives. And a stale graphify-out/
silently outlives its sources while an always_on rule routes every agent to it.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

## Final verification

- [ ] **Run every suite on Linux**

```bash
bash scripts/test_template.sh && \
bash scripts/test_export_orchestration.sh && \
bash scripts/test_backup_orchestration.sh && \
pwsh -NoProfile -File scripts/test_template.ps1 && \
python3 scripts/check_local_links.py . && \
shellcheck --severity=warning scripts/*.sh
```

Expected: every command exits 0.

- [ ] **Confirm the Graphify integration still installs and verifies**

```bash
python3 setup_graphify_apx.py && python3 setup_graphify_apx.py --verify
```

Expected: `configured with the project APEXlang extractor`, then `OK`.

- [ ] **Confirm nothing outside the intended files changed**

```bash
git status --short --branch
git diff --stat main...HEAD
```

Expected: only the files named in this plan. `apps/`, `database/`, and `app_context/` must be untouched.

- [ ] **Leave the Windows half to CI.** The PowerShell 5.1 half, the PSScriptAnalyzer compatibility profile, and Git Bash behavior are only exercised on the `windows-latest` runner. Do not claim cross-platform verification from a Linux run — push the branch and read the CI result.

## Local cleanup (not a code change, do not commit)

The review found local state that no commit can fix:

```bash
# A graph built at 65af9ae describing 162 files that no longer exist, which an
# always_on rule routes every agent to.
rm -rf graphify-out/

# Empty directories left by a deleted demo. Git cannot see them; they will sit
# beside whatever the next export creates.
find apps app_context ai_generate -mindepth 1 -type d -empty -delete
```

Run these once, on the working clone, after the branch merges.
