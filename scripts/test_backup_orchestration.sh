#!/usr/bin/env bash
set -euo pipefail

SOURCE_ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
TEST_ROOT="$SOURCE_ROOT/scratch/backup-orchestration-test.$$.${RANDOM}"
TEST_REPO="$TEST_ROOT/repo"

cleanup() { rm -rf -- "$TEST_ROOT"; }
trap cleanup EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

mkdir -p "$TEST_REPO/scripts" "$TEST_ROOT/bin"
cp "$SOURCE_ROOT/scripts/backup_db.sh" "$SOURCE_ROOT/scripts/backup_db.sql" \
  "$SOURCE_ROOT/scripts/load_env.sh" "$SOURCE_ROOT/scripts/check_db_target.sh" \
  "$SOURCE_ROOT/scripts/replace_mirror.sh" "$TEST_REPO/scripts/"

FAKE_SQL="$TEST_ROOT/bin/sql"
cat > "$FAKE_SQL" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

connection="$4"
schema="$6"
scope="$7"
prefixes="${10}"

IFS=, read -r -a required_destinations <<< "$FAKE_REQUIRED_DESTINATIONS"
for required_schema in "${required_destinations[@]}"; do
  test -f "$FAKE_REPO_ROOT/database/$required_schema/old.txt" || {
    echo "a mirror was replaced before both SQLcl passes completed" >&2
    exit 1
  }
done

printf '%s:%s:%s:%s\n' "$scope" "$schema" "$connection" "$prefixes" >> "$FAKE_SQL_LOG"
mkdir -p "database/$schema/tables" "database/$schema/views"

# SQLcl spools with the platform's line terminator, so the same manifest is
# LF-terminated on Linux and CRLF-terminated on Windows. Both must parse.
write_manifest() {
  if [ "${FAKE_MANIFEST_CRLF:-false}" = true ]; then
    printf '%s\r\n' "$@" > "database/$schema/manifest-$scope.txt"
  else
    printf '%s\n' "$@" > "database/$schema/manifest-$scope.txt"
  fi
}

if [ "$scope" = tables ]; then
  printf 'table metadata\n' > "database/$schema/tables/T_SAMPLE.sql"
  # A spool failure loses the file but never the manifest count.
  if [ "${FAKE_DROP_ONE_FILE:-false}" != true ]; then
    printf 'table metadata\n' > "database/$schema/tables/T_SECOND.sql"
  fi
  if [ "${FAKE_MANIFEST_UNREADABLE:-false}" = true ]; then
    write_manifest '' 'no counts here'
  else
    write_manifest 'TABLE=2'
  fi
else
  printf 'view metadata\n' > "database/$schema/views/V_SAMPLE.sql"
  write_manifest 'VIEW=1' 'PACKAGE=0' 'PACKAGE BODY=0' 'PROCEDURE=0' \
    'FUNCTION=0' 'TRIGGER=0'
fi
printf '%s\n' "$scope" > "database/$schema/manifest-$scope-scope.txt"
EOF
chmod +x "$FAKE_SQL"

git init -q "$TEST_REPO"

write_env() {
  local env_file="$1"
  local tables_schema="$2"
  local code_schema="$3"
  cat > "$env_file" <<EOF
PROJECT_NAME=backup-test
DB_ENVIRONMENT=development
APEX_APP_ID=100
TABLES_SCHEMA=$tables_schema
TABLES_PREFIXES=TAB_,COMMON_
TABLES_SQLCL_CONNECTION=dev_${tables_schema}
TABLES_EXPECTED_USER=$tables_schema
CODE_SCHEMA=$code_schema
CODE_PREFIXES=CODE_,COMMON_
CODE_SQLCL_CONNECTION=dev_${code_schema}
CODE_EXPECTED_USER=$code_schema
APEX_PARSING_SCHEMA=APEX_TEST
APEX_SQLCL_CONNECTION=dev_APEX_TEST
APEX_EXPECTED_USER=APEX_TEST
INSTALL_UC_APX=false
UC_APX_SKILLS_AGENT=universal
EOF
}

run_case() {
  local case_name="$1"
  local tables_schema="$2"
  local code_schema="$3"
  local required_destinations="$tables_schema"
  if [ "$code_schema" != "$tables_schema" ]; then
    required_destinations="$required_destinations,$code_schema"
  fi

  for schema in ${required_destinations//,/ }; do
    mkdir -p "$TEST_REPO/database/$schema"
    printf 'old mirror\n' > "$TEST_REPO/database/$schema/old.txt"
  done
  git -C "$TEST_REPO" add database
  git -C "$TEST_REPO" -c user.name=TemplateTest -c user.email=test@example.invalid \
    commit -qm "seed $case_name mirrors"

  local env_file="$TEST_ROOT/$case_name.env"
  local sql_log="$TEST_ROOT/$case_name.log"
  write_env "$env_file" "$tables_schema" "$code_schema"

  PATH="$TEST_ROOT/bin:$PATH" PROJECT_ENV_FILE="$env_file" \
    FAKE_REPO_ROOT="$TEST_REPO" FAKE_REQUIRED_DESTINATIONS="$required_destinations" \
    FAKE_MANIFEST_CRLF="${FAKE_MANIFEST_CRLF:-false}" \
    FAKE_SQL_LOG="$sql_log" "$TEST_REPO/scripts/backup_db.sh"

  test "$(wc -l < "$sql_log" | tr -d ' ')" = 2 || fail "$case_name did not run exactly two SQLcl passes"
  sed -n '1p' "$sql_log" | grep -q "^tables:$tables_schema:.*:TAB_,COMMON_$" \
    || fail "$case_name did not pass table prefixes in the first SQLcl call"
  sed -n '2p' "$sql_log" | grep -q "^code:$code_schema:.*:CODE_,COMMON_$" \
    || fail "$case_name did not pass code prefixes in the second SQLcl call"
  test -f "$TEST_REPO/database/$tables_schema/manifest-tables.txt" || fail "$case_name lost the tables manifest"
  test -f "$TEST_REPO/database/$code_schema/manifest-code.txt" || fail "$case_name lost the code manifest"
  grep -qE $'^TABLE=2\r?$' "$TEST_REPO/database/$tables_schema/manifest-tables.txt" \
    || fail "$case_name lost the tables manifest counts"
  test ! -e "$TEST_REPO/database/$tables_schema/old.txt" || fail "$case_name retained stale table mirror content"
  test ! -e "$TEST_REPO/database/$code_schema/old.txt" || fail "$case_name retained stale code mirror content"
}

run_case same-schema SAME SAME

git -C "$TEST_REPO" add database/SAME
git -C "$TEST_REPO" -c user.name=TemplateTest -c user.email=test@example.invalid \
  commit -qm "record same-schema refresh"

run_case split-schema DATA CODE

# A scope that writes fewer object files than its manifest counts is refused,
# and the previous mirror survives untouched.
git -C "$TEST_REPO" add database
git -C "$TEST_REPO" -c user.name=TemplateTest -c user.email=test@example.invalid \
  commit -qm "record split-schema refresh"

for schema in DATA CODE; do
  printf 'old mirror\n' > "$TEST_REPO/database/$schema/old.txt"
done
git -C "$TEST_REPO" add database
git -C "$TEST_REPO" -c user.name=TemplateTest -c user.email=test@example.invalid \
  commit -qm "re-seed mirrors for the incomplete-backup case"

incomplete_env="$TEST_ROOT/incomplete.env"
write_env "$incomplete_env" DATA CODE
if PATH="$TEST_ROOT/bin:$PATH" PROJECT_ENV_FILE="$incomplete_env" \
  FAKE_REPO_ROOT="$TEST_REPO" FAKE_REQUIRED_DESTINATIONS="DATA,CODE" \
  FAKE_SQL_LOG="$TEST_ROOT/incomplete.log" FAKE_DROP_ONE_FILE=true \
  "$TEST_REPO/scripts/backup_db.sh" 2>"$TEST_ROOT/incomplete.err"; then
  fail "backup installed a mirror with fewer files than the manifest counts"
fi
grep -q 'manifest expects' "$TEST_ROOT/incomplete.err" \
  || fail "the incomplete backup failed for the wrong reason: $(cat "$TEST_ROOT/incomplete.err")"
test -f "$TEST_REPO/database/DATA/tables/T_SECOND.sql" \
  || fail "an incomplete backup damaged the previous mirror"
test -z "$(git -C "$TEST_REPO" status --porcelain -- database)" \
  || fail "an incomplete backup left the mirror dirty"

# SQLcl spools CRLF on Windows. A completeness guard that cannot read a CRLF
# manifest counts nothing, compares 0 against 0, and waves an empty mirror
# through -- the exact failure this guard exists to stop. A CRLF manifest must
# behave the same as an LF one: complete passes, incomplete is refused.
FAKE_MANIFEST_CRLF=true run_case crlf-manifest CRDATA CRCODE

for schema in CRDATA CRCODE; do
  printf 'old mirror\n' > "$TEST_REPO/database/$schema/old.txt"
done
git -C "$TEST_REPO" add database
git -C "$TEST_REPO" -c user.name=TemplateTest -c user.email=test@example.invalid \
  commit -qm "record CRLF-manifest refresh"

crlf_incomplete_env="$TEST_ROOT/crlf-incomplete.env"
write_env "$crlf_incomplete_env" CRDATA CRCODE
if PATH="$TEST_ROOT/bin:$PATH" PROJECT_ENV_FILE="$crlf_incomplete_env" \
  FAKE_REPO_ROOT="$TEST_REPO" FAKE_REQUIRED_DESTINATIONS="CRDATA,CRCODE" \
  FAKE_SQL_LOG="$TEST_ROOT/crlf-incomplete.log" FAKE_DROP_ONE_FILE=true \
  FAKE_MANIFEST_CRLF=true \
  "$TEST_REPO/scripts/backup_db.sh" 2>"$TEST_ROOT/crlf-incomplete.err"; then
  fail "backup accepted an incomplete mirror described by a CRLF manifest"
fi
grep -q 'manifest expects' "$TEST_ROOT/crlf-incomplete.err" \
  || fail "the CRLF incomplete backup failed for the wrong reason: $(cat "$TEST_ROOT/crlf-incomplete.err")"

# A manifest with no readable counts says nothing about completeness, so it
# must fail closed instead of approving whatever happens to be staged.
unreadable_env="$TEST_ROOT/unreadable.env"
write_env "$unreadable_env" CRDATA CRCODE
if PATH="$TEST_ROOT/bin:$PATH" PROJECT_ENV_FILE="$unreadable_env" \
  FAKE_REPO_ROOT="$TEST_REPO" FAKE_REQUIRED_DESTINATIONS="CRDATA,CRCODE" \
  FAKE_SQL_LOG="$TEST_ROOT/unreadable.log" FAKE_MANIFEST_UNREADABLE=true \
  "$TEST_REPO/scripts/backup_db.sh" 2>"$TEST_ROOT/unreadable.err"; then
  fail "backup accepted a manifest with no readable object counts"
fi
grep -q 'no readable object' "$TEST_ROOT/unreadable.err" \
  || fail "the unreadable-manifest backup failed for the wrong reason: $(cat "$TEST_ROOT/unreadable.err")"

echo "PASS: database backup two-pass orchestration"
