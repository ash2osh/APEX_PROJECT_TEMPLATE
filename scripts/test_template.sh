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

mkdir -p "$TEST_REPO/outside" "$TEST_REPO/scratch/symlink-staged"
printf 'outside\n' > "$TEST_REPO/scratch/symlink-staged/file.txt"
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

python3 "$REPO_ROOT/scripts/check_local_links.py" \
  "$REPO_ROOT/.agents/skills/uc-apx" \
  "$REPO_ROOT/README.md" \
  "$REPO_ROOT/agents.md" \
  "$REPO_ROOT/app_context/README.md"

echo "PASS: template synchronization and documentation checks"
