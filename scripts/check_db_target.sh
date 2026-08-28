#!/usr/bin/env bash
# Pre-connect environment classification. Database identity is verified in SQL.
#
# Production safety in this template is an instruction to the client, not a
# privilege audit: read targets are allowed, write operation classes are
# refused, and the operator is told to run SELECT statements only.
set -euo pipefail

OPERATION="${1:?usage: check_db_target.sh <read|write> <tables|code|apex>}"
TARGET="${2:?usage: check_db_target.sh <read|write> <tables|code|apex>}"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
# shellcheck source=load_env.sh
source "$REPO_ROOT/scripts/load_env.sh" "${PROJECT_ENV_FILE:-$REPO_ROOT/.env}"

case "$OPERATION" in
  read|write) ;;
  *) echo "unsupported database operation class: $OPERATION" >&2; exit 2 ;;
esac

case "$TARGET" in
  tables) TARGET_CONNECTION="$TABLES_SQLCL_CONNECTION" ;;
  code)   TARGET_CONNECTION="$CODE_SQLCL_CONNECTION" ;;
  apex)   TARGET_CONNECTION="$APEX_SQLCL_CONNECTION" ;;
  *) echo "unsupported database target: $TARGET" >&2; exit 2 ;;
esac

shopt -s nocasematch
if [[ "$TARGET_CONNECTION" =~ (^|[-_.])(prod|prd|production|live)[0-9]*([-_.]|$) ]] && \
   [ "$DB_ENVIRONMENT" != production ]; then
  echo "$TARGET connection '$TARGET_CONNECTION' resembles production but DB_ENVIRONMENT=$DB_ENVIRONMENT" >&2
  echo "ask the user whether this is production before continuing" >&2
  exit 2
fi
shopt -u nocasematch

if [ "$DB_ENVIRONMENT" = production ]; then
  if [ "$OPERATION" != read ]; then
    echo "production database operations are always read-only; '$OPERATION' is blocked" >&2
    exit 2
  fi
  cat >&2 <<'NOTICE'
PRODUCTION SESSION - READ ONLY
  Run SELECT statements only.
  Do NOT run INSERT, UPDATE, DELETE, MERGE, or any other DML.
  Do NOT run CREATE, ALTER, DROP, TRUNCATE, or any other DDL.
  Do NOT COMMIT. Prepare changes for an approved deployment instead.
  This is not enforced by the database. It is your contract.
NOTICE
fi
