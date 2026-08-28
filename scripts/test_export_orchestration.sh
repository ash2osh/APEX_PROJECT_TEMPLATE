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
if [ "${FAKE_EXPORT_NOTHING:-false}" = true ]; then
  exit 0
fi
for alias_name in $FAKE_APP_ALIASES; do
  app_dir="apps/$schema/$alias_name"
  mkdir -p "$app_dir/pages" "$app_dir/.apex"
  printf 'prompt application\r\n' > "$app_dir/application.apx"
  printf 'prompt page one\r\n' > "$app_dir/pages/p00001.apx"
  printf '{"format":"APEXLANG"}\n' > "$app_dir/.apex/apexlang.json"
done
FAKE
chmod +x "$FAKE_SQL"

git init -q "$TEST_REPO"

ENV_FILE="$TEST_ROOT/export.env"
cat > "$ENV_FILE" <<'ENVEOF'
PROJECT_NAME=export-test
DB_ENVIRONMENT=development
APEX_APP_ID=100
TABLES_SCHEMA=SAMPLE_DATA
TABLES_SQLCL_CONNECTION=dev_SAMPLE_DATA
TABLES_EXPECTED_USER=SAMPLE_DATA
TABLES_REQUIRED_ROLE=NONE
CODE_SCHEMA=SAMPLE_CODE
CODE_SQLCL_CONNECTION=dev_SAMPLE_CODE
CODE_EXPECTED_USER=SAMPLE_CODE
CODE_REQUIRED_ROLE=NONE
APEX_PARSING_SCHEMA=SAMPLE_APEX
APEX_SQLCL_CONNECTION=dev_SAMPLE_APEX
APEX_EXPECTED_USER=SAMPLE_APEX
APEX_REQUIRED_ROLE=NONE
INSTALL_UC_APX=false
UC_APX_SKILLS_AGENT=universal
ENVEOF

run_export() {
  PATH="$TEST_ROOT/bin:$PATH" PROJECT_ENV_FILE="$ENV_FILE" \
    FAKE_APP_ALIASES="$1" FAKE_EXPORT_NOTHING="${2:-false}" \
    "$TEST_REPO/scripts/export_apps.sh"
}

MIRROR="$TEST_REPO/apps/SAMPLE_APEX/100"

# An alias-named export is installed under the application id.
run_export "sample-app-alias"
test -f "$MIRROR/application.apx" || fail "export was not installed under the application id"
test -f "$MIRROR/pages/p00001.apx" || fail "exported pages were not installed"
test -f "$MIRROR/.apex/apexlang.json" || fail "exported .apex metadata was not installed"
test ! -e "$TEST_REPO/apps/SAMPLE_APEX/sample-app-alias" || fail "alias-named directory was left behind"
! LC_ALL=C grep -q $'\r' "$MIRROR/application.apx" || fail "exported .apx retained CR characters"
! LC_ALL=C grep -q $'\r' "$MIRROR/pages/p00001.apx" || fail "exported page retained CR characters"

# Renaming the alias in APEX must not fork the mirror into a second directory.
commit_all "seed exported app mirror"
printf 'prompt stale page\n' > "$MIRROR/pages/p00002.apx"
commit_all "add a page that the next export no longer contains"
run_export "totally-different-alias"
test -f "$MIRROR/application.apx" || fail "re-export with a new alias lost the mirror"
test ! -e "$MIRROR/pages/p00002.apx" || fail "re-export retained stale page content"
test ! -e "$TEST_REPO/apps/SAMPLE_APEX/totally-different-alias" || fail "renamed alias forked the mirror"
test "$(find "$TEST_REPO/apps/SAMPLE_APEX" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')" = 1 \
  || fail "more than one application directory exists after a rename"

# A dirty mirror is still refused, and an empty or ambiguous export fails loudly.
commit_all "record re-export"
printf 'local edit\n' >> "$MIRROR/application.apx"
if run_export "sample-app-alias"; then
  fail "export replaced a dirty mirror"
fi
git -C "$TEST_REPO" checkout -- "apps/SAMPLE_APEX/100/application.apx"

if run_export "" true; then
  fail "export accepted an SQLcl run that produced no application directory"
fi
if run_export "alias-one alias-two"; then
  fail "export accepted an ambiguous multi-directory export"
fi

echo "PASS: APEX export names its mirror by application id"
