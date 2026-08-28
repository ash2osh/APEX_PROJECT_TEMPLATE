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

mkdir -p "$TEST_REPO/scratch/symlink-content-staged"
printf 'content\n' > "$TEST_REPO/scratch/symlink-content-staged/file.txt"
ln -s "$TEST_REPO/outside" "$TEST_REPO/scratch/symlink-content-staged/outside-link"
if MIRROR_SYNC_REPO_ROOT="$TEST_REPO" "$REPO_ROOT/scripts/replace_mirror.sh" \
    "$TEST_REPO/scratch/symlink-content-staged" "database/symlink-content"; then
  fail "staging with symlinked content was accepted"
fi

mkdir -p "$TEST_REPO/outside" "$TEST_REPO/scratch/symlink-staged"
printf 'outside\n' > "$TEST_REPO/scratch/symlink-staged/file.txt"
mv "$TEST_REPO/apps" "$TEST_REPO/apps-real"
ln -s "$TEST_REPO/outside" "$TEST_REPO/apps"
if MIRROR_SYNC_REPO_ROOT="$TEST_REPO" "$REPO_ROOT/scripts/replace_mirror.sh" \
    "$TEST_REPO/scratch/symlink-staged" "apps/schema/app"; then
  fail "symlinked mirror parent was accepted"
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

if command -v pwsh >/dev/null 2>&1; then
  mkdir -p "$TEST_REPO/ps-scripts" "$TEST_REPO/database/mirror-ps" "$TEST_REPO/scratch/staged-ps"
  cp "$REPO_ROOT/scripts/replace_mirror.ps1" "$TEST_REPO/ps-scripts/replace_mirror.ps1"

  printf 'stale\n' > "$TEST_REPO/database/mirror-ps/stale.txt"
  git -C "$TEST_REPO" add database/mirror-ps/stale.txt
  git -C "$TEST_REPO" -c user.name=TemplateTest -c user.email=test@example.invalid commit -qm "ps mirror seed"
  printf 'new\n' > "$TEST_REPO/scratch/staged-ps/new.txt"

  pwsh -NoProfile -File "$TEST_REPO/ps-scripts/replace_mirror.ps1" \
    -StagedDir "$TEST_REPO/scratch/staged-ps" -Destination "database/mirror-ps" \
    || fail "PowerShell replace_mirror.ps1 failed on a valid replacement"
  test -f "$TEST_REPO/database/mirror-ps/new.txt" || fail "PowerShell replace_mirror.ps1 did not install new mirror content"
  test ! -e "$TEST_REPO/database/mirror-ps/stale.txt" || fail "PowerShell replace_mirror.ps1 retained stale mirror content"

  mkdir -p "$TEST_REPO/scratch/empty-staged-ps"
  if pwsh -NoProfile -File "$TEST_REPO/ps-scripts/replace_mirror.ps1" \
      -StagedDir "$TEST_REPO/scratch/empty-staged-ps" -Destination "database/empty-ps"; then
    fail "PowerShell replace_mirror.ps1 accepted empty staging"
  fi

  printf 'not a directory\n' > "$TEST_REPO/scratch/file-staged-ps"
  if pwsh -NoProfile -File "$TEST_REPO/ps-scripts/replace_mirror.ps1" \
      -StagedDir "$TEST_REPO/scratch/file-staged-ps" -Destination "database/file-ps"; then
    fail "PowerShell replace_mirror.ps1 accepted a file as staging input"
  fi

  printf 'local change\n' >> "$TEST_REPO/database/mirror-ps/new.txt"
  mkdir -p "$TEST_REPO/scratch/dirty-staged-ps"
  printf 'replacement\n' > "$TEST_REPO/scratch/dirty-staged-ps/new.txt"
  if pwsh -NoProfile -File "$TEST_REPO/ps-scripts/replace_mirror.ps1" \
      -StagedDir "$TEST_REPO/scratch/dirty-staged-ps" -Destination "database/mirror-ps"; then
    fail "PowerShell replace_mirror.ps1 did not refuse a dirty mirror"
  fi

  printf 'one\r\ntwo\r\n' > "$TEST_REPO/scratch/sample-ps.apx"
  pwsh -NoProfile -File "$REPO_ROOT/scripts/normalize_apx.ps1" -TargetDir "$TEST_REPO/scratch" \
    || fail "PowerShell normalize_apx.ps1 failed"
  ! LC_ALL=C grep -q $'\r' "$TEST_REPO/scratch/sample-ps.apx" || fail "PowerShell normalizer retained CR characters"
  test "$(tail -c 1 "$TEST_REPO/scratch/sample-ps.apx" | od -An -t x1 | tr -d ' \n')" = "0a" || fail "PowerShell normalizer did not add a trailing LF"
else
  echo "SKIP: pwsh not found — replace_mirror.ps1 and normalize_apx.ps1 were not exercised" >&2
fi

test -f "$REPO_ROOT/.env.example" || fail ".env.example is missing"
git -C "$REPO_ROOT" check-ignore -q .env || fail ".env is not ignored"

ENV_FILE="$TEST_ROOT/project.env"
INJECTION_MARKER="$TEST_ROOT/env-was-executed"
cat > "$ENV_FILE" <<EOF
PROJECT_NAME=\$(touch $INJECTION_MARKER)
DB_ENVIRONMENT=development
APEX_APP_ID=100
APEX_APP_SLUG=sample-app
TABLES_SCHEMA=SAMPLE_DATA
TABLES_SQLCL_CONNECTION=dev1_SAMPLE_DATA
TABLES_EXPECTED_USER=SAMPLE_DATA
TABLES_REQUIRED_ROLE=NONE
CODE_SCHEMA=SAMPLE_CODE
CODE_SQLCL_CONNECTION=dev1_SAMPLE_CODE
CODE_EXPECTED_USER=SAMPLE_CODE
CODE_REQUIRED_ROLE=NONE
APEX_PARSING_SCHEMA=SAMPLE_APEX
APEX_SQLCL_CONNECTION=dev1_SAMPLE_APEX
APEX_EXPECTED_USER=SAMPLE_APEX
APEX_REQUIRED_ROLE=NONE
INSTALL_UC_APX=false
UC_APX_SKILLS_AGENT=universal
EOF

ENV_OUTPUT="$(bash -c 'source "$1" "$2"; printf "%s|%s|%s|%s" "$PROJECT_NAME" "$TABLES_SCHEMA" "$CODE_SCHEMA" "$APEX_PARSING_SCHEMA"' \
  _ "$REPO_ROOT/scripts/load_env.sh" "$ENV_FILE")"
test "$ENV_OUTPUT" = "\$(touch $INJECTION_MARKER)|SAMPLE_DATA|SAMPLE_CODE|SAMPLE_APEX" || fail "environment loader changed literal values"
test ! -e "$INJECTION_MARKER" || fail "environment loader executed .env content"

MISSING_ROLE_ENV_FILE="$TEST_ROOT/missing-role.env"
grep -v '^CODE_REQUIRED_ROLE=' "$ENV_FILE" > "$MISSING_ROLE_ENV_FILE"
if CODE_REQUIRED_ROLE=INHERITED bash -c 'source "$1" "$2"' \
    _ "$REPO_ROOT/scripts/load_env.sh" "$MISSING_ROLE_ENV_FILE"; then
  fail "environment loader accepted an inherited value for a missing setting"
fi

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
  -e 's/TABLES_REQUIRED_ROLE=NONE/TABLES_REQUIRED_ROLE=SAMPLE_DATA_PROD_RO/' \
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

PROD_NO_ROLE_ENV_FILE="$TEST_ROOT/production-no-role.env"
sed \
  -e 's/DB_ENVIRONMENT=development/DB_ENVIRONMENT=production/' \
  -e 's/APEX_SQLCL_CONNECTION=dev1_SAMPLE_APEX/APEX_SQLCL_CONNECTION=primary-prod-SAMPLE_APEX/' \
  -e 's/APEX_EXPECTED_USER=SAMPLE_APEX/APEX_EXPECTED_USER=SAMPLE_APEX_AGENT_RO/' \
  "$ENV_FILE" > "$PROD_NO_ROLE_ENV_FILE"
if PROJECT_ENV_FILE="$PROD_NO_ROLE_ENV_FILE" "$REPO_ROOT/scripts/check_db_target.sh" read apex; then
  fail "production connection without a read-only role was accepted"
fi

PROD_OWNER_ENV_FILE="$TEST_ROOT/production-owner.env"
sed \
  -e 's/DB_ENVIRONMENT=development/DB_ENVIRONMENT=production/' \
  -e 's/CODE_SQLCL_CONNECTION=dev1_SAMPLE_CODE/CODE_SQLCL_CONNECTION=primary-prod-SAMPLE_CODE/' \
  -e 's/CODE_REQUIRED_ROLE=NONE/CODE_REQUIRED_ROLE=SAMPLE_CODE_PROD_RO/' \
  "$ENV_FILE" > "$PROD_OWNER_ENV_FILE"
if PROJECT_ENV_FILE="$PROD_OWNER_ENV_FILE" "$REPO_ROOT/scripts/check_db_target.sh" read code; then
  fail "production owner account was accepted for the code target"
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
grep -q 'check_db_target.sh" read tables' "$REPO_ROOT/scripts/backup_db.sh" || fail "database backup does not guard the tables target"
grep -q 'check_db_target.sh" read code' "$REPO_ROOT/scripts/backup_db.sh" || fail "database backup does not guard the code target"
grep -q 'APEX_SQLCL_CONNECTION' "$REPO_ROOT/scripts/export_apps.sh" || fail "APEX export does not use the APEX connection profile"
grep -q 'APEX_PARSING_SCHEMA' "$REPO_ROOT/scripts/export_apps.sh" || fail "APEX export does not use the parsing schema"
grep -q 'check_db_target.sh" read apex' "$REPO_ROOT/scripts/export_apps.sh" || fail "APEX export does not guard the APEX target"
grep -q 'application.apx' "$REPO_ROOT/scripts/export_apps.sh" || fail "APEX export does not require application.apx"
grep -q 'apexlang.json' "$REPO_ROOT/scripts/export_apps.sh" || fail "APEX export does not require .apex/apexlang.json"
! grep -Eqi '(uc-apx|apex)[[:space:]]+validate' "$REPO_ROOT/scripts/export_apps.sh" "$REPO_ROOT/scripts/export_apps.ps1" "$REPO_ROOT/scripts/export_apps.sql" || fail "APEX export invokes validation"
grep -q 'session_roles' "$REPO_ROOT/scripts/verify_db_access.sql" || fail "post-connect production role verification is missing"
grep -q 'session_privs' "$REPO_ROOT/scripts/verify_db_access.sql" || fail "post-connect production privilege verification is missing"

"$REPO_ROOT/scripts/test_backup_orchestration.sh"

LINK_FIXTURE="$TEST_ROOT/link-fixture.md"
printf '[missing](not-here.md)\n' > "$LINK_FIXTURE"
if python3 "$REPO_ROOT/scripts/check_local_links.py" "$LINK_FIXTURE"; then
  fail "local-link checker accepted a broken link"
fi
printf '%s\n' '````markdown' '[example](not-a-real-file.md)' '````' > "$LINK_FIXTURE"
python3 "$REPO_ROOT/scripts/check_local_links.py" "$LINK_FIXTURE" || fail "local-link checker treated fenced example links as real"

python3 "$REPO_ROOT/scripts/check_local_links.py" "$REPO_ROOT"

python3 "$REPO_ROOT/scripts/test_setup_graphify.py"

echo "PASS: template synchronization and documentation checks"
