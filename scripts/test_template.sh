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

# A real failure after the first staged replacement must unwind both mirrors.
mkdir -p "$TEST_REPO/database/atomic-one" "$TEST_REPO/database/atomic-two" \
  "$TEST_REPO/scratch/atomic-one" "$TEST_REPO/scratch/atomic-two"
printf 'old one\n' > "$TEST_REPO/database/atomic-one/value.txt"
printf 'old two\n' > "$TEST_REPO/database/atomic-two/value.txt"
git -C "$TEST_REPO" add database/atomic-one database/atomic-two database/mirror
git -C "$TEST_REPO" -c user.name=TemplateTest -c user.email=test@example.invalid commit -qm "seed atomic replacement mirrors"
printf 'new one\n' > "$TEST_REPO/scratch/atomic-one/value.txt"
printf 'new two\n' > "$TEST_REPO/scratch/atomic-two/value.txt"
if MIRROR_SYNC_TEST_FAIL_STAGED_MOVE_INDEX=1 MIRROR_SYNC_REPO_ROOT="$TEST_REPO" \
    "$REPO_ROOT/scripts/replace_mirror.sh" \
    "$TEST_REPO/scratch/atomic-one" "database/atomic-one" \
    "$TEST_REPO/scratch/atomic-two" "database/atomic-two"; then
  fail "test-only second staged move failure was accepted"
fi
test "$(cat "$TEST_REPO/database/atomic-one/value.txt")" = "old one" \
  || fail "Bash rollback did not restore the first mirror"
test "$(cat "$TEST_REPO/database/atomic-two/value.txt")" = "old two" \
  || fail "Bash rollback did not restore the second mirror"
test -z "$(git -C "$TEST_REPO" status --porcelain -- database/atomic-one database/atomic-two)" \
  || fail "Bash rollback left an atomic mirror dirty"

# The indexed backup path is the one the move uses, so it must be rejected
# during validation before any lock or move. Pause the first Git query until
# the background replacement PID is known, then create that exact path.
mkdir -p "$TEST_REPO/database/collision" "$TEST_REPO/scratch/collision-staged"
printf 'old collision\n' > "$TEST_REPO/database/collision/value.txt"
git -C "$TEST_REPO" add database/collision
git -C "$TEST_REPO" -c user.name=TemplateTest -c user.email=test@example.invalid commit -qm "seed indexed backup collision"
printf 'new collision\n' > "$TEST_REPO/scratch/collision-staged/value.txt"
COLLISION_GIT_BIN="$TEST_REPO/scratch/collision-git-bin"
COLLISION_READY="$TEST_REPO/scratch/collision-ready"
COLLISION_RELEASE="$TEST_REPO/scratch/collision-release"
COLLISION_WAITED="$TEST_REPO/scratch/collision-waited"
mkdir -p "$COLLISION_GIT_BIN"
cat > "$COLLISION_GIT_BIN/git" <<'GIT'
#!/usr/bin/env bash
set -euo pipefail
if [ ! -e "$MIRROR_SYNC_TEST_COLLISION_WAITED" ]; then
  : > "$MIRROR_SYNC_TEST_COLLISION_READY"
  while [ ! -e "$MIRROR_SYNC_TEST_COLLISION_RELEASE" ]; do sleep 0.01; done
  : > "$MIRROR_SYNC_TEST_COLLISION_WAITED"
fi
exec "$MIRROR_SYNC_TEST_REAL_GIT" "$@"
GIT
chmod +x "$COLLISION_GIT_BIN/git"
MIRROR_SYNC_TEST_COLLISION_READY="$COLLISION_READY" \
  MIRROR_SYNC_TEST_COLLISION_RELEASE="$COLLISION_RELEASE" \
  MIRROR_SYNC_TEST_COLLISION_WAITED="$COLLISION_WAITED" \
  MIRROR_SYNC_TEST_REAL_GIT="$(command -v git)" PATH="$COLLISION_GIT_BIN:$PATH" \
  MIRROR_SYNC_REPO_ROOT="$TEST_REPO" "$REPO_ROOT/scripts/replace_mirror.sh" \
  "$TEST_REPO/scratch/collision-staged" "database/collision" \
  > "$TEST_REPO/scratch/collision.log" 2>&1 &
COLLISION_PID=$!
for _ in $(seq 1 100); do
  [ -e "$COLLISION_READY" ] && break
  sleep 0.01
done
[ -e "$COLLISION_READY" ] || fail "indexed backup collision fixture did not reach validation"
mkdir "$TEST_REPO/scratch/.mirror-backup.collision.$COLLISION_PID.0"
: > "$COLLISION_RELEASE"
set +e
wait "$COLLISION_PID"
collision_status=$?
set -e
test "$collision_status" -ne 0 || fail "indexed backup collision was accepted"
test "$(cat "$TEST_REPO/database/collision/value.txt")" = "old collision" \
  || fail "indexed backup collision changed the mirror"

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

git -C "$TEST_REPO" add -A database/mirror
git -C "$TEST_REPO" -c user.name=TemplateTest -c user.email=test@example.invalid commit -qm "clean lock fixture"

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

# A creator writes metadata after atomically creating the file. A contender
# that observes the incomplete file must never delete it and take the lock.
mkdir -p "$TEST_REPO/scratch/partial-staged"
printf 'content\n' > "$TEST_REPO/scratch/partial-staged/file.txt"
printf 'version=1\nimpl=ps1\n' > "$LOCK_ROOT/$STALE_LOCK_KEY.lock"
if MIRROR_SYNC_REPO_ROOT="$TEST_REPO" "$REPO_ROOT/scripts/replace_mirror.sh" \
    "$TEST_REPO/scratch/partial-staged" "database/mirror"; then
  fail "a partial mirror lock was stolen"
fi
test -e "$LOCK_ROOT/$STALE_LOCK_KEY.lock" || fail "a partial mirror lock was deleted"
rm -f "$LOCK_ROOT/$STALE_LOCK_KEY.lock"

# Only a complete protocol-v1 record can authorize stale-lock removal. These
# records have a valid old epoch but each omits or corrupts another field.
mkdir -p "$TEST_REPO/scratch/incomplete-fields-staged"
printf 'content\n' > "$TEST_REPO/scratch/incomplete-fields-staged/file.txt"
for INCOMPLETE_LOCK in \
  $'impl=ps1\npid=999999\nepoch=1\n' \
  $'version=1\npid=999999\nepoch=1\n' \
  $'version=1\nimpl=ps1\nepoch=1\n' \
  $'version=2\nimpl=ps1\npid=999999\nepoch=1\n' \
  $'version=1\nimpl=other\npid=999999\nepoch=1\n' \
  $'version=1\nimpl=ps1\npid=not-a-pid\nepoch=1\n'; do
  printf '%s' "$INCOMPLETE_LOCK" > "$LOCK_ROOT/$STALE_LOCK_KEY.lock"
  if MIRROR_SYNC_REPO_ROOT="$TEST_REPO" "$REPO_ROOT/scripts/replace_mirror.sh" \
      "$TEST_REPO/scratch/incomplete-fields-staged" "database/mirror"; then
    fail "an incomplete protocol-v1 mirror lock was stolen"
  fi
  test -e "$LOCK_ROOT/$STALE_LOCK_KEY.lock" || fail "an incomplete protocol-v1 mirror lock was deleted"
done
rm -f "$LOCK_ROOT/$STALE_LOCK_KEY.lock"

# Cross-implementation PID namespaces are incomparable, so a fresh foreign
# lock must remain contention even when its PID is not alive locally.
mkdir -p "$TEST_REPO/scratch/cross-impl-staged"
printf 'content\n' > "$TEST_REPO/scratch/cross-impl-staged/file.txt"
printf 'version=1\nimpl=ps1\npid=999999\nepoch=%s\n' "$(date +%s)" \
  > "$LOCK_ROOT/$STALE_LOCK_KEY.lock"
if MIRROR_SYNC_REPO_ROOT="$TEST_REPO" "$REPO_ROOT/scripts/replace_mirror.sh" \
    "$TEST_REPO/scratch/cross-impl-staged" "database/mirror"; then
  fail "a fresh cross-implementation mirror lock was ignored"
fi
test -e "$LOCK_ROOT/$STALE_LOCK_KEY.lock" || fail "a fresh cross-implementation mirror lock was deleted"
rm -f "$LOCK_ROOT/$STALE_LOCK_KEY.lock"

# Exactly the configured age is not older than the window. Override date in
# only this child process to make the boundary deterministic.
FIXED_DATE_BIN="$TEST_REPO/scratch/fixed-date-bin"
mkdir -p "$FIXED_DATE_BIN" "$TEST_REPO/scratch/boundary-staged"
printf '#!/bin/sh\nprintf "1000\\n"\n' > "$FIXED_DATE_BIN/date"
chmod +x "$FIXED_DATE_BIN/date"
printf 'content\n' > "$TEST_REPO/scratch/boundary-staged/file.txt"
printf 'version=1\nimpl=ps1\npid=999999\nepoch=990\n' > "$LOCK_ROOT/$STALE_LOCK_KEY.lock"
if MIRROR_LOCK_STALE_SECONDS=10 PATH="$FIXED_DATE_BIN:$PATH" \
    MIRROR_SYNC_REPO_ROOT="$TEST_REPO" "$REPO_ROOT/scripts/replace_mirror.sh" \
    "$TEST_REPO/scratch/boundary-staged" "database/mirror"; then
  fail "a boundary-age mirror lock was treated as stale"
fi
test -e "$LOCK_ROOT/$STALE_LOCK_KEY.lock" || fail "a boundary-age mirror lock was deleted"
rm -f "$LOCK_ROOT/$STALE_LOCK_KEY.lock"

# A non-SHA fallback would make Bash target a different path from PowerShell.
# Run a real replacement with only the commands it needs, deliberately omitting
# sha256sum and shasum while retaining cksum to expose the former bad fallback.
NO_SHA_BIN="$TEST_REPO/scratch/no-sha-bin"
mkdir -p "$NO_SHA_BIN" "$TEST_REPO/scratch/no-sha-staged"
for TOOL in dirname mkdir find git stat basename sed head tr date rm mv cksum awk; do
  TOOL_PATH="$(command -v "$TOOL")"
  if [ -z "$TOOL_PATH" ] || ! ln -s "$TOOL_PATH" "$NO_SHA_BIN/$TOOL" 2>/dev/null; then
    fail "could not build the no-SHA-256 PATH fixture for $TOOL"
  fi
done
printf 'content\n' > "$TEST_REPO/scratch/no-sha-staged/file.txt"
if NO_SHA_OUTPUT="$(PATH="$NO_SHA_BIN" MIRROR_SYNC_REPO_ROOT="$TEST_REPO" "$BASH" \
    "$REPO_ROOT/scripts/replace_mirror.sh" "$TEST_REPO/scratch/no-sha-staged" "database/mirror" 2>&1)"; then
  fail "mirror replacement accepted a non-SHA-256 lock path"
fi
case "$NO_SHA_OUTPUT" in
  *"SHA-256 is required to acquire a mirror lock"*) ;;
  *) fail "mirror replacement did not explain the missing SHA-256 tool" ;;
esac

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

  # Hold a real Bash replacement after it has acquired the shared lock. The
  # wrapper lets its first Git status pass, then blocks the post-lock recheck.
  CROSS_GIT_BIN="$TEST_REPO/scratch/cross-git-bin"
  CROSS_GIT_COUNT="$TEST_REPO/scratch/cross-git-count"
  CROSS_GIT_READY="$TEST_REPO/scratch/cross-git-ready"
  CROSS_GIT_RELEASE="$TEST_REPO/scratch/cross-git-release"
  CROSS_HOLDER_LOG="$TEST_REPO/scratch/cross-bash-holder.log"
  mkdir -p "$CROSS_GIT_BIN" "$TEST_REPO/scratch/cross-bash-held" "$TEST_REPO/scratch/cross-ps-contender"
  printf '#!/usr/bin/env bash\nset -euo pipefail\ncount=0\nif [ -f "$MIRROR_LOCK_TEST_GIT_COUNT" ]; then count=$(<"$MIRROR_LOCK_TEST_GIT_COUNT"); fi\ncount=$((count + 1))\nprintf "%%s\\n" "$count" > "$MIRROR_LOCK_TEST_GIT_COUNT"\nif [ "$count" -eq 2 ]; then\n  : > "$MIRROR_LOCK_TEST_GIT_READY"\n  for _ in $(seq 1 100); do\n    [ -e "$MIRROR_LOCK_TEST_GIT_RELEASE" ] && break\n    sleep 0.05\n  done\nfi\nexec "$MIRROR_LOCK_TEST_REAL_GIT" "$@"\n' \
    > "$CROSS_GIT_BIN/git"
  chmod +x "$CROSS_GIT_BIN/git"
  printf 'holder\n' > "$TEST_REPO/scratch/cross-bash-held/file.txt"
  printf 'contender\n' > "$TEST_REPO/scratch/cross-ps-contender/file.txt"
  MIRROR_LOCK_TEST_GIT_COUNT="$CROSS_GIT_COUNT" \
    MIRROR_LOCK_TEST_GIT_READY="$CROSS_GIT_READY" \
    MIRROR_LOCK_TEST_GIT_RELEASE="$CROSS_GIT_RELEASE" \
    MIRROR_LOCK_TEST_REAL_GIT="$(command -v git)" \
    PATH="$CROSS_GIT_BIN:$PATH" MIRROR_SYNC_REPO_ROOT="$TEST_REPO" \
    "$REPO_ROOT/scripts/replace_mirror.sh" "$TEST_REPO/scratch/cross-bash-held" "database/mirror" \
    > "$CROSS_HOLDER_LOG" 2>&1 &
  CROSS_HOLDER_PID=$!
  for _ in $(seq 1 100); do
    [ -e "$CROSS_GIT_READY" ] && break
    sleep 0.05
  done
  if [ ! -e "$CROSS_GIT_READY" ]; then
    : > "$CROSS_GIT_RELEASE"
    wait "$CROSS_HOLDER_PID" || true
    fail "Bash mirror holder did not acquire and retain the shared lock"
  fi
  test -f "$LOCK_ROOT/$STALE_LOCK_KEY.lock" || fail "Bash holder did not create the shared lock file"
  if "$PWSH" -NoProfile -File "$TEST_REPO/ps-scripts/replace_mirror.ps1" \
      "$TEST_REPO/scratch/cross-ps-contender" "database/mirror"; then
    : > "$CROSS_GIT_RELEASE"
    wait "$CROSS_HOLDER_PID" || true
    fail "PowerShell stole a live Bash mirror lock"
  fi
  : > "$CROSS_GIT_RELEASE"
  wait "$CROSS_HOLDER_PID" || fail "Bash mirror holder did not finish after release"

  printf 'stale\n' > "$TEST_REPO/database/mirror-ps/stale.txt"
  git -C "$TEST_REPO" add database/mirror-ps/stale.txt
  git -C "$TEST_REPO" -c user.name=TemplateTest -c user.email=test@example.invalid commit -qm "ps mirror seed"
  printf 'new\n' > "$TEST_REPO/scratch/staged-ps/new.txt"

  "$PWSH" -NoProfile -File "$TEST_REPO/ps-scripts/replace_mirror.ps1" \
    "$TEST_REPO/scratch/staged-ps" "database/mirror-ps" \
    || fail "PowerShell replace_mirror.ps1 failed on a valid replacement"
  test -f "$TEST_REPO/database/mirror-ps/new.txt" || fail "PowerShell replace_mirror.ps1 did not install new mirror content"
  test ! -e "$TEST_REPO/database/mirror-ps/stale.txt" || fail "PowerShell replace_mirror.ps1 retained stale mirror content"

  mkdir -p "$TEST_REPO/scratch/empty-staged-ps"
  if "$PWSH" -NoProfile -File "$TEST_REPO/ps-scripts/replace_mirror.ps1" \
      "$TEST_REPO/scratch/empty-staged-ps" "database/empty-ps"; then
    fail "PowerShell replace_mirror.ps1 accepted empty staging"
  fi

  printf 'not a directory\n' > "$TEST_REPO/scratch/file-staged-ps"
  if "$PWSH" -NoProfile -File "$TEST_REPO/ps-scripts/replace_mirror.ps1" \
      "$TEST_REPO/scratch/file-staged-ps" "database/file-ps"; then
    fail "PowerShell replace_mirror.ps1 accepted a file as staging input"
  fi

  printf 'local change\n' >> "$TEST_REPO/database/mirror-ps/new.txt"
  mkdir -p "$TEST_REPO/scratch/dirty-staged-ps"
  printf 'replacement\n' > "$TEST_REPO/scratch/dirty-staged-ps/new.txt"
  if "$PWSH" -NoProfile -File "$TEST_REPO/ps-scripts/replace_mirror.ps1" \
      "$TEST_REPO/scratch/dirty-staged-ps" "database/mirror-ps"; then
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

MISSING_ENV_FILE="$TEST_ROOT/missing-environment-file.env"
missing_env_output="$(bash -c 'source "$1" >/dev/null 2>&1; status=$?; printf "%s|%s" "$status" "${project_env_repo_root-UNSET}"' \
  _ "$REPO_ROOT/scripts/load_env.sh" "$MISSING_ENV_FILE")"
test "$missing_env_output" = "1|UNSET" \
  || fail "Bash loader leaked project_env_repo_root after missing-file failure: $missing_env_output"

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
"$PYTHON_COMMAND" "$REPO_ROOT/scripts/test_graphify_apexlang_extractor.py"
"$PYTHON_COMMAND" "$REPO_ROOT/scripts/test_graphify_corpus.py"

echo "PASS: template synchronization and documentation checks"
