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

IFS=, read -r -a required_destinations <<< "$FAKE_REQUIRED_DESTINATIONS"
for required_schema in "${required_destinations[@]}"; do
  test -f "$FAKE_REPO_ROOT/database/$required_schema/old.txt" || {
    echo "a mirror was replaced before both SQLcl passes completed" >&2
    exit 1
  }
done

printf '%s:%s:%s\n' "$scope" "$schema" "$connection" >> "$FAKE_SQL_LOG"
mkdir -p "database/$schema/tables" "database/$schema/views"
printf '%s\n' "$scope" > "database/$schema/manifest-$scope.txt"
if [ "$scope" = tables ]; then
  printf 'table metadata\n' > "database/$schema/tables/T_SAMPLE.sql"
else
  printf 'view metadata\n' > "database/$schema/views/V_SAMPLE.sql"
fi
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
APEX_APP_SLUG=backup-test
TABLES_SCHEMA=$tables_schema
TABLES_SQLCL_CONNECTION=dev_${tables_schema}
TABLES_EXPECTED_USER=$tables_schema
TABLES_REQUIRED_ROLE=NONE
CODE_SCHEMA=$code_schema
CODE_SQLCL_CONNECTION=dev_${code_schema}
CODE_EXPECTED_USER=$code_schema
CODE_REQUIRED_ROLE=NONE
APEX_PARSING_SCHEMA=APEX_TEST
APEX_SQLCL_CONNECTION=dev_APEX_TEST
APEX_EXPECTED_USER=APEX_TEST
APEX_REQUIRED_ROLE=NONE
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
    FAKE_SQL_LOG="$sql_log" "$TEST_REPO/scripts/backup_db.sh"

  test "$(wc -l < "$sql_log" | tr -d ' ')" = 2 || fail "$case_name did not run exactly two SQLcl passes"
  sed -n '1p' "$sql_log" | grep -q "^tables:$tables_schema:" || fail "$case_name did not run tables first"
  sed -n '2p' "$sql_log" | grep -q "^code:$code_schema:" || fail "$case_name did not run code second"
  test -f "$TEST_REPO/database/$tables_schema/manifest-tables.txt" || fail "$case_name lost the tables manifest"
  test -f "$TEST_REPO/database/$code_schema/manifest-code.txt" || fail "$case_name lost the code manifest"
  test ! -e "$TEST_REPO/database/$tables_schema/old.txt" || fail "$case_name retained stale table mirror content"
  test ! -e "$TEST_REPO/database/$code_schema/old.txt" || fail "$case_name retained stale code mirror content"
}

run_case same-schema SAME SAME

git -C "$TEST_REPO" add database/SAME
git -C "$TEST_REPO" -c user.name=TemplateTest -c user.email=test@example.invalid \
  commit -qm "record same-schema refresh"

run_case split-schema DATA CODE

echo "PASS: database backup two-pass orchestration"
