#!/usr/bin/env bash
# Verify that the APEX export names its mirror by the immutable application id
# rather than by the application alias SQLcl chooses for the export directory.
set -euo pipefail

SOURCE_ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
TEST_ROOT="$SOURCE_ROOT/scratch/export-orchestration-test.$$.${RANDOM}"
TEST_REPO="$TEST_ROOT/repo"

cleanup() { rm -rf -- "$TEST_ROOT"; }
trap cleanup EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

commit_all() {
  git -C "$TEST_REPO" add -A
  git -C "$TEST_REPO" -c user.name=TemplateTest -c user.email=test@example.invalid \
    commit -qm "$1"
}

mkdir -p "$TEST_REPO/scripts" "$TEST_ROOT/bin"
cp "$SOURCE_ROOT/scripts/export_apps.sh" "$SOURCE_ROOT/scripts/export_apps.sql" \
  "$SOURCE_ROOT/scripts/load_env.sh" "$SOURCE_ROOT/scripts/check_db_target.sh" \
  "$SOURCE_ROOT/scripts/replace_mirror.sh" "$SOURCE_ROOT/scripts/normalize_apx.sh" \
  "$TEST_REPO/scripts/"

# Stands in for SQLcl. It writes the alias-named directory that SQLcl would
# create, with CRLF content so the normalizer is exercised too.
FAKE_SQL="$TEST_ROOT/bin/sql"
cat > "$FAKE_SQL" <<'FAKE'
#!/usr/bin/env bash
set -euo pipefail
schema="$6"
app_id="$7"
printf '%s\n' "$app_id" >> "$FAKE_SQL_LOG"
if [ "${FAKE_FAIL_APP_ID:-}" = "$app_id" ]; then
  exit 42
fi
if [ "${FAKE_EXPORT_NOTHING_APP_ID:-}" = "$app_id" ]; then
  exit 0
fi
alias_names="app-${app_id}-${FAKE_ALIAS_SUFFIX:-default}"
if [ "${FAKE_AMBIGUOUS_APP_ID:-}" = "$app_id" ]; then
  alias_names="$alias_names app-${app_id}-second"
fi
for alias_name in $alias_names; do
  app_dir="apps/$schema/$alias_name"
  mkdir -p "$app_dir/pages" "$app_dir/.apex"
  printf 'prompt application %s\r\n' "$app_id" > "$app_dir/application.apx"
  printf 'prompt page one for %s\r\n' "$app_id" > "$app_dir/pages/p00001.apx"
  printf '{"format":"APEXLANG"}\n' > "$app_dir/.apex/apexlang.json"
done
FAKE
chmod +x "$FAKE_SQL"

git init -q "$TEST_REPO"

ENV_FILE="$TEST_ROOT/export.env"
cat > "$ENV_FILE" <<'ENVEOF'
PROJECT_NAME=export-test
DB_ENVIRONMENT=development
APEX_APP_ID=100,101
TABLES_SCHEMA=SAMPLE_DATA
TABLES_PREFIXES=SAMPLE_
TABLES_SQLCL_CONNECTION=dev_SAMPLE_DATA
TABLES_EXPECTED_USER=SAMPLE_DATA
CODE_SCHEMA=SAMPLE_CODE
CODE_PREFIXES=SAMPLE_
CODE_SQLCL_CONNECTION=dev_SAMPLE_CODE
CODE_EXPECTED_USER=SAMPLE_CODE
APEX_PARSING_SCHEMA=SAMPLE_APEX
APEX_SQLCL_CONNECTION=dev_SAMPLE_APEX
APEX_EXPECTED_USER=SAMPLE_APEX
INSTALL_UC_APX=false
UC_APX_SKILLS_AGENT=universal
ENVEOF

run_export() {
  PATH="$TEST_ROOT/bin:$PATH" PROJECT_ENV_FILE="$ENV_FILE" \
    FAKE_SQL_LOG="$TEST_ROOT/sql.log" \
    FAKE_ALIAS_SUFFIX="${FAKE_ALIAS_SUFFIX:-default}" \
    FAKE_FAIL_APP_ID="${FAKE_FAIL_APP_ID:-}" \
    FAKE_EXPORT_NOTHING_APP_ID="${FAKE_EXPORT_NOTHING_APP_ID:-}" \
    FAKE_AMBIGUOUS_APP_ID="${FAKE_AMBIGUOUS_APP_ID:-}" \
    "$TEST_REPO/scripts/export_apps.sh"
}

MIRROR_100="$TEST_REPO/apps/SAMPLE_APEX/100"
MIRROR_101="$TEST_REPO/apps/SAMPLE_APEX/101"

# Two alias-named exports are staged, verified, normalized, and installed under
# their immutable numeric application ids only after both SQLcl calls succeed.
run_export
test "$(tr '\n' ',' < "$TEST_ROOT/sql.log")" = "100,101," \
  || fail "multi-app export did not call SQLcl once per application in order"
for app_id in 100 101; do
  mirror="$TEST_REPO/apps/SAMPLE_APEX/$app_id"
  test -f "$mirror/application.apx" || fail "app $app_id was not installed under its id"
  test -f "$mirror/pages/p00001.apx" || fail "app $app_id pages were not installed"
  test -f "$mirror/.apex/apexlang.json" || fail "app $app_id metadata was not installed"
  grep -q "application $app_id" "$mirror/application.apx" || fail "app $app_id received another app's export"
  ! LC_ALL=C grep -q $'\r' "$mirror/application.apx" || fail "app $app_id retained CR characters"
done
test "$(find "$TEST_REPO/apps/SAMPLE_APEX" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')" = 2 \
  || fail "alias directories were left beside the two numeric mirrors"

# Renaming the alias in APEX must not fork the mirror into a second directory.
commit_all "seed exported app mirror"
printf 'prompt stale page\n' > "$MIRROR_100/pages/p00002.apx"
commit_all "add a page that the next export no longer contains"
FAKE_ALIAS_SUFFIX=renamed run_export
test ! -e "$MIRROR_100/pages/p00002.apx" || fail "re-export retained stale page content"
test "$(find "$TEST_REPO/apps/SAMPLE_APEX" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')" = 2 \
  || fail "renamed aliases forked numeric mirrors"

# Failure of the second export must leave both existing mirrors untouched.
commit_all "record re-export"
if FAKE_FAIL_APP_ID=101 run_export; then
  fail "export accepted failure of the second application"
fi
test -z "$(git -C "$TEST_REPO" status --porcelain -- apps)" \
  || fail "failure of the second export changed an existing mirror"

# Every destination is preflighted before the first SQLcl call.
printf 'local edit\n' >> "$MIRROR_101/application.apx"
lines_before="$(wc -l < "$TEST_ROOT/sql.log" | tr -d ' ')"
if run_export; then
  fail "export replaced a dirty mirror"
fi
lines_after="$(wc -l < "$TEST_ROOT/sql.log" | tr -d ' ')"
test "$lines_before" = "$lines_after" || fail "SQLcl ran before every destination was preflighted"
git -C "$TEST_REPO" checkout -- "apps/SAMPLE_APEX/101/application.apx"

if FAKE_EXPORT_NOTHING_APP_ID=100 run_export; then
  fail "export accepted an SQLcl run that produced no application directory"
fi
if FAKE_AMBIGUOUS_APP_ID=100 run_export; then
  fail "export accepted an ambiguous multi-directory export"
fi
test -z "$(git -C "$TEST_REPO" status --porcelain -- apps)" \
  || fail "invalid staged exports changed existing mirrors"

echo "PASS: atomic multi-application APEX export orchestration"
