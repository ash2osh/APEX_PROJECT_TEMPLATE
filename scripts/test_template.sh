#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEST_ROOT="$REPO_ROOT/scratch/template-test.$$.${RANDOM}"
TEST_REPO="$TEST_ROOT/repo"

cleanup() {
  rm -rf -- "$TEST_ROOT"
}
trap cleanup EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

if command -v python3 >/dev/null 2>&1; then
  PYTHON_COMMAND=python3
elif command -v python >/dev/null 2>&1; then
  PYTHON_COMMAND=python
else
  fail "Python 3 was not found on PATH"
fi

# Git Bash on Windows refuses `ln -s` to a target that does not exist yet,
# because it silently falls back to copying. MSYS=winsymlinks:nativestrict
# asks for a real Windows symlink instead, which needs Developer Mode or the
# create-symlink privilege. Try it, verify the result really is a link, and
# report honestly when the platform cannot make one.
make_symlink() {
  MSYS=winsymlinks:nativestrict ln -s "$1" "$2" 2>/dev/null || return 1
  [ -L "$2" ] || return 1
}

mkdir -p "$TEST_REPO/database/mirror" "$TEST_REPO/scratch/staged"
git init -q "$TEST_REPO"
printf 'stale\n' > "$TEST_REPO/database/mirror/stale.txt"
git -C "$TEST_REPO" add database/mirror/stale.txt
git -C "$TEST_REPO" -c user.name=TemplateTest -c user.email=test@example.invalid commit -qm initial
printf 'new\n' > "$TEST_REPO/scratch/staged/new.txt"

MIRROR_SYNC_REPO_ROOT="$TEST_REPO" "$REPO_ROOT/scripts/replace_mirror.sh" \
  "$TEST_REPO/scratch/staged" "database/mirror"

test -f "$TEST_REPO/database/mirror/new.txt" || fail "new mirror content was not installed"
test ! -e "$TEST_REPO/database/mirror/stale.txt" || fail "stale mirror content was retained"

mkdir -p "$TEST_REPO/apps/schema/app" "$TEST_REPO/scratch/dotdot-staged"
printf 'tracked\n' > "$TEST_REPO/apps/schema/app/tracked.txt"
git -C "$TEST_REPO" add apps/schema/app/tracked.txt
git -C "$TEST_REPO" -c user.name=TemplateTest -c user.email=test@example.invalid commit -qm "seed app mirror"
printf 'replacement\n' > "$TEST_REPO/scratch/dotdot-staged/new.txt"
set +e
timeout 3s env MIRROR_SYNC_REPO_ROOT="$TEST_REPO" "$REPO_ROOT/scripts/replace_mirror.sh" \
  "$TEST_REPO/scratch/dotdot-staged" "apps/schema/.."
dotdot_status=$?
set -e
test "$dotdot_status" -ne 0 || fail "dot-dot mirror destination was accepted"
test "$dotdot_status" -ne 124 || fail "dot-dot mirror destination reached a hanging move"
test -f "$TEST_REPO/apps/schema/app/tracked.txt" || fail "dot-dot destination displaced the app mirror"

mkdir -p "$TEST_REPO/scratch/empty-staged"
if MIRROR_SYNC_REPO_ROOT="$TEST_REPO" "$REPO_ROOT/scripts/replace_mirror.sh" \
    "$TEST_REPO/scratch/empty-staged" "database/empty"; then
  fail "empty staging was accepted"
fi

mkdir -p "$TEST_REPO/scratch/invalid-staged"
printf 'content\n' > "$TEST_REPO/scratch/invalid-staged/file.txt"
if MIRROR_SYNC_REPO_ROOT="$TEST_REPO" "$REPO_ROOT/scripts/replace_mirror.sh" \
    "$TEST_REPO/scratch/invalid-staged" "$TEST_REPO/not-a-mirror"; then
  fail "invalid mirror destination was accepted"
fi

if MIRROR_SYNC_REPO_ROOT="$TEST_REPO" "$REPO_ROOT/scripts/replace_mirror.sh" \
    "$REPO_ROOT/scripts" "database/mirror"; then
  fail "staging outside scratch was accepted"
fi

mkdir -p "$TEST_REPO/outside" "$TEST_REPO/scratch/symlink-content-staged"
printf 'content\n' > "$TEST_REPO/scratch/symlink-content-staged/file.txt"
if make_symlink "$TEST_REPO/outside" "$TEST_REPO/scratch/symlink-content-staged/outside-link"; then
  if MIRROR_SYNC_REPO_ROOT="$TEST_REPO" "$REPO_ROOT/scripts/replace_mirror.sh" \
      "$TEST_REPO/scratch/symlink-content-staged" "database/symlink-content"; then
    fail "staging with symlinked content was accepted"
  fi

  mkdir -p "$TEST_REPO/scratch/symlink-staged"
  printf 'outside\n' > "$TEST_REPO/scratch/symlink-staged/file.txt"
  mv "$TEST_REPO/apps" "$TEST_REPO/apps-real"
  make_symlink "$TEST_REPO/outside" "$TEST_REPO/apps" \
    || fail "could not replace the app mirror parent with a symlink"
  if MIRROR_SYNC_REPO_ROOT="$TEST_REPO" "$REPO_ROOT/scripts/replace_mirror.sh" \
      "$TEST_REPO/scratch/symlink-staged" "apps/schema/app"; then
    fail "symlinked mirror parent was accepted"
  fi
  rm -f "$TEST_REPO/apps"
  mv "$TEST_REPO/apps-real" "$TEST_REPO/apps"
else
  echo "SKIP: this platform cannot create symbolic links — replace_mirror.sh symlink refusals were not exercised" >&2
fi

printf 'local change\n' >> "$TEST_REPO/database/mirror/new.txt"
mkdir -p "$TEST_REPO/scratch/dirty-staged"
printf 'replacement\n' > "$TEST_REPO/scratch/dirty-staged/new.txt"

if MIRROR_SYNC_REPO_ROOT="$TEST_REPO" "$REPO_ROOT/scripts/replace_mirror.sh" \
    "$TEST_REPO/scratch/dirty-staged" "database/mirror"; then
  fail "dirty mirror replacement was not refused"
fi

printf 'one\r\ntwo\r\n' > "$TEST_REPO/scratch/sample.apx"
printf 'lone\rreturn' > "$TEST_REPO/scratch/lone-cr.apx"
"$REPO_ROOT/scripts/normalize_apx.sh" "$TEST_REPO/scratch"
! LC_ALL=C grep -q $'\r' "$TEST_REPO/scratch/sample.apx" || fail "normalizer retained CR characters"
! LC_ALL=C grep -q $'\r' "$TEST_REPO/scratch/lone-cr.apx" || fail "normalizer retained lone CR characters"
test "$(tail -c 1 "$TEST_REPO/scratch/sample.apx" | od -An -t x1 | tr -d ' \n')" = "0a" || fail "normalizer did not add a trailing LF"
! grep -Eq 'git[[:space:]]+checkout' "$REPO_ROOT/scripts/normalize_apx.sh" "$REPO_ROOT/scripts/normalize_apx.ps1" || fail "normalizer still invokes Git checkout"

# The .ps1 half of every script pair only gets exercised if a PowerShell is
# found. Windows ships Windows PowerShell 5.1 as "powershell" and often has
# no "pwsh" at all, and the .ps1 scripts declare #Requires -Version 5.1, so
# fall back to it rather than skipping the whole half of the suite there.
PWSH=""
for candidate in pwsh powershell; do
  if command -v "$candidate" >/dev/null 2>&1; then
    PWSH="$candidate"
    break
  fi
done
if [ -n "$PWSH" ]; then
  mkdir -p "$TEST_REPO/ps-scripts" "$TEST_REPO/database/mirror-ps" "$TEST_REPO/scratch/staged-ps"
  cp "$REPO_ROOT/scripts/replace_mirror.ps1" "$TEST_REPO/ps-scripts/replace_mirror.ps1"

  printf 'stale\n' > "$TEST_REPO/database/mirror-ps/stale.txt"
  git -C "$TEST_REPO" add database/mirror-ps/stale.txt
  git -C "$TEST_REPO" -c user.name=TemplateTest -c user.email=test@example.invalid commit -qm "ps mirror seed"
  printf 'new\n' > "$TEST_REPO/scratch/staged-ps/new.txt"

  "$PWSH" -NoProfile -File "$TEST_REPO/ps-scripts/replace_mirror.ps1" \
    -StagedDir "$TEST_REPO/scratch/staged-ps" -Destination "database/mirror-ps" \
    || fail "PowerShell replace_mirror.ps1 failed on a valid replacement"
  test -f "$TEST_REPO/database/mirror-ps/new.txt" || fail "PowerShell replace_mirror.ps1 did not install new mirror content"
  test ! -e "$TEST_REPO/database/mirror-ps/stale.txt" || fail "PowerShell replace_mirror.ps1 retained stale mirror content"

  mkdir -p "$TEST_REPO/scratch/empty-staged-ps"
  if "$PWSH" -NoProfile -File "$TEST_REPO/ps-scripts/replace_mirror.ps1" \
      -StagedDir "$TEST_REPO/scratch/empty-staged-ps" -Destination "database/empty-ps"; then
    fail "PowerShell replace_mirror.ps1 accepted empty staging"
  fi

  printf 'not a directory\n' > "$TEST_REPO/scratch/file-staged-ps"
  if "$PWSH" -NoProfile -File "$TEST_REPO/ps-scripts/replace_mirror.ps1" \
      -StagedDir "$TEST_REPO/scratch/file-staged-ps" -Destination "database/file-ps"; then
    fail "PowerShell replace_mirror.ps1 accepted a file as staging input"
  fi

  printf 'local change\n' >> "$TEST_REPO/database/mirror-ps/new.txt"
  mkdir -p "$TEST_REPO/scratch/dirty-staged-ps"
  printf 'replacement\n' > "$TEST_REPO/scratch/dirty-staged-ps/new.txt"
  if "$PWSH" -NoProfile -File "$TEST_REPO/ps-scripts/replace_mirror.ps1" \
      -StagedDir "$TEST_REPO/scratch/dirty-staged-ps" -Destination "database/mirror-ps"; then
    fail "PowerShell replace_mirror.ps1 did not refuse a dirty mirror"
  fi

  printf 'one\r\ntwo\r\n' > "$TEST_REPO/scratch/sample-ps.apx"
  "$PWSH" -NoProfile -File "$REPO_ROOT/scripts/normalize_apx.ps1" -TargetDir "$TEST_REPO/scratch" \
    || fail "PowerShell normalize_apx.ps1 failed"
  ! LC_ALL=C grep -q $'\r' "$TEST_REPO/scratch/sample-ps.apx" || fail "PowerShell normalizer retained CR characters"
  test "$(tail -c 1 "$TEST_REPO/scratch/sample-ps.apx" | od -An -t x1 | tr -d ' \n')" = "0a" || fail "PowerShell normalizer did not add a trailing LF"
else
  echo "SKIP: no pwsh or powershell on PATH — replace_mirror.ps1 and normalize_apx.ps1 were not exercised" >&2
fi

test -f "$REPO_ROOT/.env.example" || fail ".env.example is missing"
git -C "$REPO_ROOT" check-ignore -q .env || fail ".env is not ignored"

ENV_FILE="$TEST_ROOT/project.env"
INJECTION_MARKER="$TEST_ROOT/env-was-executed"
cat > "$ENV_FILE" <<EOF
PROJECT_NAME=\$(touch $INJECTION_MARKER)
DB_ENVIRONMENT=development
APEX_APP_ID=100,200
TABLES_SCHEMA=SAMPLE_DATA
TABLES_PREFIXES=SAMPLE_,COMMON_
TABLES_SQLCL_CONNECTION=dev1_SAMPLE_DATA
TABLES_EXPECTED_USER=SAMPLE_DATA
CODE_SCHEMA=SAMPLE_CODE
CODE_PREFIXES=SAMPLE_,COMMON_
CODE_SQLCL_CONNECTION=dev1_SAMPLE_CODE
CODE_EXPECTED_USER=SAMPLE_CODE
APEX_PARSING_SCHEMA=SAMPLE_APEX
APEX_SQLCL_CONNECTION=dev1_SAMPLE_APEX
APEX_EXPECTED_USER=SAMPLE_APEX
INSTALL_UC_APX=false
UC_APX_SKILLS_AGENT=universal
EOF

ENV_OUTPUT="$(bash -c 'source "$1" "$2"; printf "%s|%s|%s|%s|%s|%s" "$PROJECT_NAME" "$APEX_APP_ID" "$TABLES_PREFIXES" "$CODE_PREFIXES" "$TABLES_SCHEMA" "$APEX_PARSING_SCHEMA"' \
  _ "$REPO_ROOT/scripts/load_env.sh" "$ENV_FILE")"
test "$ENV_OUTPUT" = "\$(touch $INJECTION_MARKER)|100,200|SAMPLE_,COMMON_|SAMPLE_,COMMON_|SAMPLE_DATA|SAMPLE_APEX" || fail "environment loader changed literal or CSV values"
test ! -e "$INJECTION_MARKER" || fail "environment loader executed .env content"

MISSING_PREFIX_ENV_FILE="$TEST_ROOT/missing-prefix.env"
grep -v '^CODE_PREFIXES=' "$ENV_FILE" > "$MISSING_PREFIX_ENV_FILE"
if CODE_PREFIXES=INHERITED_ bash -c 'source "$1" "$2"' \
    _ "$REPO_ROOT/scripts/load_env.sh" "$MISSING_PREFIX_ENV_FILE"; then
  fail "environment loader accepted an inherited value for a missing prefix setting"
fi

STAR_PREFIX_ENV_FILE="$TEST_ROOT/star-prefix.env"
sed -E 's/^(TABLES_PREFIXES|CODE_PREFIXES)=.*/\1=*/' "$ENV_FILE" > "$STAR_PREFIX_ENV_FILE"
bash -c 'source "$1" "$2"' _ "$REPO_ROOT/scripts/load_env.sh" "$STAR_PREFIX_ENV_FILE" \
  || fail "environment loader rejected the export-all prefix sentinel"

assert_env_rejected() {
  local source_file="$1"
  local sed_expression="$2"
  local message="$3"
  local invalid_file="$TEST_ROOT/invalid-env-$RANDOM.env"
  sed -E "$sed_expression" "$source_file" > "$invalid_file"
  if bash -c 'source "$1" "$2"' _ "$REPO_ROOT/scripts/load_env.sh" "$invalid_file"; then
    fail "$message"
  fi
}

assert_env_rejected "$ENV_FILE" 's/^APEX_APP_ID=.*/APEX_APP_ID=100, 200/' "environment loader accepted whitespace in APEX_APP_ID"
assert_env_rejected "$ENV_FILE" 's/^APEX_APP_ID=.*/APEX_APP_ID=100,100/' "environment loader accepted duplicate APEX application ids"
assert_env_rejected "$ENV_FILE" 's/^APEX_APP_ID=.*/APEX_APP_ID=100,/' "environment loader accepted an empty APEX application id"
assert_env_rejected "$ENV_FILE" 's/^APEX_APP_ID=.*/APEX_APP_ID=0/' "environment loader accepted a non-positive APEX application id"
assert_env_rejected "$ENV_FILE" 's/^PROJECT_NAME=.*/project_name=sample-project/' "environment loader accepted a lowercase setting name"
assert_env_rejected "$ENV_FILE" 's/^TABLES_SCHEMA=.*/TABLES_SCHEMA=sample/' "environment loader accepted a lowercase Oracle identifier"
assert_env_rejected "$ENV_FILE" 's/^TABLES_PREFIXES=.*/TABLES_PREFIXES=sample_/' "environment loader accepted a lowercase table prefix"
assert_env_rejected "$ENV_FILE" 's/^TABLES_PREFIXES=.*/TABLES_PREFIXES=SAMPLE_, SAMPLE2_/' "environment loader accepted whitespace in table prefixes"
assert_env_rejected "$ENV_FILE" 's/^TABLES_PREFIXES=.*/TABLES_PREFIXES=SAMPLE_,SAMPLE_/' "environment loader accepted duplicate table prefixes"
assert_env_rejected "$ENV_FILE" 's/^CODE_PREFIXES=.*/CODE_PREFIXES=*,SAMPLE_/' "environment loader accepted a mixed star prefix list"
assert_env_rejected "$ENV_FILE" 's/^CODE_PREFIXES=.*/CODE_PREFIXES=SAMPLE_,/' "environment loader accepted an empty code prefix"

for removed_role in TABLES_REQUIRED_ROLE CODE_REQUIRED_ROLE APEX_REQUIRED_ROLE; do
  LEGACY_ROLE_ENV_FILE="$TEST_ROOT/legacy-$removed_role.env"
  printf '%s\n' "$(cat "$ENV_FILE")" "$removed_role=NONE" > "$LEGACY_ROLE_ENV_FILE"
  if bash -c 'source "$1" "$2"' _ "$REPO_ROOT/scripts/load_env.sh" "$LEGACY_ROLE_ENV_FILE"; then
    fail "environment loader accepted removed role setting $removed_role"
  fi
done

"$PYTHON_COMMAND" - "$REPO_ROOT/.env.example" <<'PY'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
lines = path.read_text(encoding="utf-8").splitlines()
assignments = [(i, line.split("=", 1)[0]) for i, line in enumerate(lines)
               if re.match(r"^[A-Z][A-Z0-9_]*=", line)]
expected = {
    "PROJECT_NAME", "DB_ENVIRONMENT", "APEX_APP_ID",
    "TABLES_SCHEMA", "TABLES_PREFIXES", "TABLES_SQLCL_CONNECTION", "TABLES_EXPECTED_USER",
    "CODE_SCHEMA", "CODE_PREFIXES", "CODE_SQLCL_CONNECTION", "CODE_EXPECTED_USER",
    "APEX_PARSING_SCHEMA", "APEX_SQLCL_CONNECTION", "APEX_EXPECTED_USER",
    "INSTALL_UC_APX", "UC_APX_SKILLS_AGENT",
}
actual = {key for _, key in assignments}
if actual != expected:
    raise SystemExit(f".env.example keys differ: expected={sorted(expected)} actual={sorted(actual)}")
for index, key in assignments:
    preceding = lines[max(0, index - 2):index]
    if len(preceding) != 2 or not preceding[0].startswith("# Purpose:") or not preceding[1].startswith("# Example"):
        raise SystemExit(f"{key} lacks immediate Purpose and Example comments")
PY
bash -c 'source "$1" "$2"' _ "$REPO_ROOT/scripts/load_env.sh" "$REPO_ROOT/.env.example" \
  || fail ".env.example does not pass the Bash loader"

INIT_SKILL="$REPO_ROOT/.agents/skills/initialize-project/SKILL.md"
grep -q 'TABLES_PREFIXES=<prefix-csv-or-\*>' "$INIT_SKILL" \
  || fail "initialize-project does not collect table prefixes"
grep -q 'CODE_PREFIXES=<prefix-csv-or-\*>' "$INIT_SKILL" \
  || fail "initialize-project does not collect code prefixes"
grep -q 'APEX_APP_ID=<positive-id-csv>' "$INIT_SKILL" \
  || fail "initialize-project does not document multiple app ids"
! grep -q '_REQUIRED_ROLE=<role-or-NONE>' "$INIT_SKILL" \
  || fail "initialize-project still writes removed role settings"
grep -q 'obsolete unsupported settings' "$INIT_SKILL" \
  || fail "initialize-project does not flag removed role settings as unsupported"

for target in tables code apex; do
  PROJECT_ENV_FILE="$ENV_FILE" "$REPO_ROOT/scripts/check_db_target.sh" read "$target"
done

SAME_PROFILE_ENV_FILE="$TEST_ROOT/same-profile.env"
sed -E \
  -e 's/^(TABLES_SCHEMA|CODE_SCHEMA|APEX_PARSING_SCHEMA)=.*/\1=UNIFIED/' \
  -e 's/^(TABLES_EXPECTED_USER|CODE_EXPECTED_USER|APEX_EXPECTED_USER)=.*/\1=UNIFIED/' \
  -e 's/^(TABLES_SQLCL_CONNECTION|CODE_SQLCL_CONNECTION|APEX_SQLCL_CONNECTION)=.*/\1=dev_UNIFIED/' \
  "$ENV_FILE" > "$SAME_PROFILE_ENV_FILE"
for target in tables code apex; do
  PROJECT_ENV_FILE="$SAME_PROFILE_ENV_FILE" "$REPO_ROOT/scripts/check_db_target.sh" read "$target"
done

LEGACY_ENV_FILE="$TEST_ROOT/legacy.env"
printf '%s\n' "$(cat "$ENV_FILE")" 'DB_TARGET_SCHEMA=LEGACY' > "$LEGACY_ENV_FILE"
if bash -c 'source "$1" "$2"' _ "$REPO_ROOT/scripts/load_env.sh" "$LEGACY_ENV_FILE"; then
  fail "environment loader accepted a legacy single-profile setting"
fi

PROD_ENV_FILE="$TEST_ROOT/production.env"
sed \
  -e 's/DB_ENVIRONMENT=development/DB_ENVIRONMENT=production/' \
  -e 's/TABLES_SQLCL_CONNECTION=dev1_SAMPLE_DATA/TABLES_SQLCL_CONNECTION=primary-prod-SAMPLE_DATA/' \
  -e 's/TABLES_EXPECTED_USER=SAMPLE_DATA/TABLES_EXPECTED_USER=SAMPLE_DATA_AGENT_RO/' \
  "$ENV_FILE" > "$PROD_ENV_FILE"
PROJECT_ENV_FILE="$PROD_ENV_FILE" "$REPO_ROOT/scripts/check_db_target.sh" read tables
if PROJECT_ENV_FILE="$PROD_ENV_FILE" "$REPO_ROOT/scripts/check_db_target.sh" write tables; then
  fail "production write operation was accepted"
fi

MISLABELED_ENV_FILE="$TEST_ROOT/mislabeled.env"
sed 's/CODE_SQLCL_CONNECTION=dev1_SAMPLE_CODE/CODE_SQLCL_CONNECTION=sample_prod/' "$ENV_FILE" > "$MISLABELED_ENV_FILE"
PROJECT_ENV_FILE="$MISLABELED_ENV_FILE" "$REPO_ROOT/scripts/check_db_target.sh" read tables
if PROJECT_ENV_FILE="$MISLABELED_ENV_FILE" "$REPO_ROOT/scripts/check_db_target.sh" read code; then
  fail "production-like connection name was accepted as development"
fi

NUMBERED_PROD_ENV_FILE="$TEST_ROOT/numbered-prod.env"
sed 's/APEX_SQLCL_CONNECTION=dev1_SAMPLE_APEX/APEX_SQLCL_CONNECTION=sample-prod1/' "$ENV_FILE" > "$NUMBERED_PROD_ENV_FILE"
if PROJECT_ENV_FILE="$NUMBERED_PROD_ENV_FILE" "$REPO_ROOT/scripts/check_db_target.sh" read apex; then
  fail "numbered production-like connection name was accepted as development"
fi

# Production is read-only by instruction, not by privilege audit. A role-less
# owner login is accepted for reads, refused for writes, and told the rule.
PROD_OWNER_ENV_FILE="$TEST_ROOT/production-owner.env"
sed \
  -e 's/DB_ENVIRONMENT=development/DB_ENVIRONMENT=production/' \
  -e 's/CODE_SQLCL_CONNECTION=dev1_SAMPLE_CODE/CODE_SQLCL_CONNECTION=primary-prod-SAMPLE_CODE/' \
  "$ENV_FILE" > "$PROD_OWNER_ENV_FILE"
PROD_NOTICE="$(PROJECT_ENV_FILE="$PROD_OWNER_ENV_FILE" "$REPO_ROOT/scripts/check_db_target.sh" read code 2>&1)" \
  || fail "production owner account without a role was rejected for reads"
grep -q 'SELECT statements only' <<< "$PROD_NOTICE" \
  || fail "production read did not print the SELECT-only instruction"
grep -q 'Do NOT run INSERT' <<< "$PROD_NOTICE" || fail "production notice does not name DML"
grep -q 'Do NOT run CREATE' <<< "$PROD_NOTICE" || fail "production notice does not name DDL"
if PROJECT_ENV_FILE="$PROD_OWNER_ENV_FILE" "$REPO_ROOT/scripts/check_db_target.sh" write code; then
  fail "production write operation was accepted"
fi

# The removed production privilege machinery must not creep back in.
! grep -qE '\-200(03|04|05|06|07|08|10|11|12|13)' "$REPO_ROOT/scripts/verify_db_access.sql" \
  || fail "removed production privilege checks are still present"
! grep -qE 'session_privs|session_roles|user_tab_privs_recd|role_tab_privs|user_sys_privs|user_role_privs|user_objects' \
  "$REPO_ROOT/scripts/verify_db_access.sql" \
  || fail "verify_db_access.sql still audits privileges"
! grep -q 'non-owner' "$REPO_ROOT/scripts/check_db_target.sh" \
  || fail "pre-connect non-owner gate is still present"
grep -q 'SELECT statements only' "$REPO_ROOT/scripts/verify_db_access.sql" \
  || fail "post-connect production instruction is missing"
test ! -e "$REPO_ROOT/scripts/audit_production_access.sql" \
  || fail "the removed privilege audit script is back"
for RULE_FILE in "$REPO_ROOT/.agents/rules/agent-safety.md" "$REPO_ROOT/AGENTS.md"; do
  grep -q 'SELECT statements only' "$RULE_FILE" \
    || fail "production read-only instruction is missing from $RULE_FILE"
done

LEGACY_SLUG_ENV_FILE="$TEST_ROOT/legacy-slug.env"
printf '%s\n' "$(cat "$ENV_FILE")" 'APEX_APP_SLUG=sample-app' > "$LEGACY_SLUG_ENV_FILE"
if bash -c 'source "$1" "$2"' _ "$REPO_ROOT/scripts/load_env.sh" "$LEGACY_SLUG_ENV_FILE"; then
  fail "environment loader accepted the legacy APEX_APP_SLUG setting"
fi

test -f "$REPO_ROOT/.agents/skills/install-uc-apx/SKILL.md" || fail "conditional uc-apx installer skill is missing"
INIT_SKILL="$REPO_ROOT/.agents/skills/initialize-project/SKILL.md"
CLAUDE_INIT_SKILL="$REPO_ROOT/.claude/skills/initialize-project/SKILL.md"
CLAUDE_INIT_COMMAND="$REPO_ROOT/.claude/commands/init.md"
test -f "$INIT_SKILL" || fail "canonical initialize-project skill is missing"
test -f "$CLAUDE_INIT_SKILL" || fail "Claude initialize-project skill pointer is missing"
test -f "$CLAUDE_INIT_COMMAND" || fail "Claude /init command is missing"
grep -q '^name: initialize-project$' "$INIT_SKILL" || fail "initialize-project skill frontmatter is invalid"
grep -q 'never.*password\|Never.*password' "$INIT_SKILL" || fail "initialize-project skill does not prohibit passwords"
grep -q 'does not connect\|Do not connect\|never connect' "$INIT_SKILL" || fail "initialize-project skill does not prohibit database connections"
grep -q 'overwrite' "$INIT_SKILL" || fail "initialize-project skill does not require overwrite handling"
grep -q 'read tables' "$INIT_SKILL" || fail "initialize-project skill does not preflight the tables target"
grep -q 'read code' "$INIT_SKILL" || fail "initialize-project skill does not preflight the code target"
grep -q 'read apex' "$INIT_SKILL" || fail "initialize-project skill does not preflight the APEX target"
grep -q 'INSTALL_UC_APX=true' "$INIT_SKILL" || fail "initialize-project skill does not route optional uc-apx installation"
grep -Fq '$ARGUMENTS' "$CLAUDE_INIT_COMMAND" || fail "Claude /init command does not forward its arguments"
test ! -d "$REPO_ROOT/.agents/skills/uc-apx" || fail "bundled uc-apx skill content is still present"
EMPTY_CLAUDE_SKILL_DIR="$(find "$REPO_ROOT/.claude/skills" -mindepth 1 -maxdepth 1 -type d -empty -print -quit)"
test -z "$EMPTY_CLAUDE_SKILL_DIR" || fail "empty legacy Claude skill directory remains: $EMPTY_CLAUDE_SKILL_DIR"

grep -q "DBMS_METADATA.GET_DDL(''PROCEDURE''" "$REPO_ROOT/scripts/backup_db.sql" || fail "procedure metadata export is missing"
grep -q "DBMS_METADATA.GET_DDL(''FUNCTION''" "$REPO_ROOT/scripts/backup_db.sql" || fail "function metadata export is missing"
grep -q "DBMS_METADATA.GET_DDL(''TRIGGER''" "$REPO_ROOT/scripts/backup_db.sql" || fail "trigger metadata export is missing"
grep -q "DEFINE object_scope = '&2'" "$REPO_ROOT/scripts/backup_db.sql" || fail "database backup scope argument is missing"
grep -q 'manifest-tables.txt' "$REPO_ROOT/scripts/backup_db.sql" || fail "tables manifest is missing"
grep -q 'manifest-code.txt' "$REPO_ROOT/scripts/backup_db.sql" || fail "code manifest is missing"
# SQLcl turns the DDL 'insert' transform on by default, which appends an
# INSERT ... KU$ data-movement statement to every table's DDL.
grep -q '^SET DDL INSERT OFF$' "$REPO_ROOT/scripts/backup_db.sql" \
  || fail "backup_db.sql no longer disables the SQLcl DDL insert transform"
# SQLcl's client-side statement splitter cuts a SELECT at the first ';' even
# when that ';' sits inside a quoted literal. The driver-generating queries
# then return no rows, print no error, and exit 0, leaving an empty driver and
# an empty mirror. The generated statement terminator must stay CHR(59).
grep -q '^SET HEADING OFF$' "$REPO_ROOT/scripts/backup_db.sql" \
  || fail "backup_db.sql no longer turns column headings off for the generated driver"
test "$(grep -c "FROM DUAL' || CHR(59)$" "$REPO_ROOT/scripts/backup_db.sql")" = 7 \
  || fail "backup_db.sql does not build all seven generated terminators with CHR(59)"
! grep -q "FROM DUAL;'" "$REPO_ROOT/scripts/backup_db.sql" \
  || fail "backup_db.sql embeds a literal ';' inside a generated string literal"
# SQLcl cannot SPOOL to a path containing '$' (SP2-0332) and does not stop on
# the failure, so object names must be encoded in the generated filenames.
test "$(grep -c "REPLACE(\(table_name\|view_name\|object_name\), '\$', '-S-')" \
  "$REPO_ROOT/scripts/backup_db.sql")" = 7 \
  || fail "backup_db.sql does not encode '\$' in all seven generated filenames"
grep -q 'verify_scope_complete' "$REPO_ROOT/scripts/backup_db.sh" \
  || fail "backup_db.sh no longer verifies scope completeness against the manifest"
grep -q 'Test-ScopeComplete' "$REPO_ROOT/scripts/backup_db.ps1" \
  || fail "backup_db.ps1 no longer verifies scope completeness against the manifest"
# SQLcl builds a JLine console over stdin and aborts -- then exits 0 -- when
# stdin is a descriptor it cannot probe, which is what every non-interactive
# caller hands it on Windows. Both wrappers must feed it an empty file.
for SQLCL_WRAPPER in "$REPO_ROOT/scripts/backup_db.sh" "$REPO_ROOT/scripts/export_apps.sh"; do
  grep -q 'SQLCL_STDIN=' "$SQLCL_WRAPPER" \
    || fail "$(basename "$SQLCL_WRAPPER") does not redirect SQLcl standard input"
  grep -q '< "\$SQLCL_STDIN"' "$SQLCL_WRAPPER" \
    || fail "$(basename "$SQLCL_WRAPPER") does not feed SQLcl the empty standard input file"
done
grep -q 'check_db_target.sh" read tables' "$REPO_ROOT/scripts/backup_db.sh" || fail "database backup does not guard the tables target"
grep -q 'check_db_target.sh" read code' "$REPO_ROOT/scripts/backup_db.sh" || fail "database backup does not guard the code target"
grep -q 'APEX_SQLCL_CONNECTION' "$REPO_ROOT/scripts/export_apps.sh" || fail "APEX export does not use the APEX connection profile"
grep -q 'APEX_PARSING_SCHEMA' "$REPO_ROOT/scripts/export_apps.sh" || fail "APEX export does not use the parsing schema"
grep -q 'check_db_target.sh" read apex' "$REPO_ROOT/scripts/export_apps.sh" || fail "APEX export does not guard the APEX target"
grep -q 'application.apx' "$REPO_ROOT/scripts/export_apps.sh" || fail "APEX export does not require application.apx"
grep -q 'apexlang.json' "$REPO_ROOT/scripts/export_apps.sh" || fail "APEX export does not require .apex/apexlang.json"
! grep -Eqi '(uc-apx|apex)[[:space:]]+validate' "$REPO_ROOT/scripts/export_apps.sh" "$REPO_ROOT/scripts/export_apps.ps1" "$REPO_ROOT/scripts/export_apps.sql" || fail "APEX export invokes validation"
grep -q '^SET VERIFY OFF' "$REPO_ROOT/scripts/export_apps.sql" \
  || fail "APEX export exposes SQLcl substitution before/after blocks"
grep -q 'SESSION_USER' "$REPO_ROOT/scripts/verify_db_access.sql" || fail "post-connect session identity check is missing"
grep -q '\-20001' "$REPO_ROOT/scripts/verify_db_access.sql" || fail "post-connect expected-user check is missing"

"$REPO_ROOT/scripts/test_backup_orchestration.sh"
"$REPO_ROOT/scripts/test_export_orchestration.sh"

LINK_FIXTURE="$TEST_ROOT/link-fixture.md"
printf '[missing](not-here.md)\n' > "$LINK_FIXTURE"
if "$PYTHON_COMMAND" "$REPO_ROOT/scripts/check_local_links.py" "$LINK_FIXTURE"; then
  fail "local-link checker accepted a broken link"
fi
printf '%s\n' '````markdown' '[example](not-a-real-file.md)' '````' > "$LINK_FIXTURE"
"$PYTHON_COMMAND" "$REPO_ROOT/scripts/check_local_links.py" "$LINK_FIXTURE" || fail "local-link checker treated fenced example links as real"

"$PYTHON_COMMAND" "$REPO_ROOT/scripts/check_local_links.py" "$REPO_ROOT"

"$PYTHON_COMMAND" "$REPO_ROOT/scripts/test_setup_graphify.py"

echo "PASS: template synchronization and documentation checks"
