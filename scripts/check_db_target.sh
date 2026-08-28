#!/usr/bin/env bash
# Pre-connect environment classification. Database identity is verified in SQL.
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
  tables)
    TARGET_SCHEMA="$TABLES_SCHEMA"
    TARGET_CONNECTION="$TABLES_SQLCL_CONNECTION"
    TARGET_EXPECTED_USER="$TABLES_EXPECTED_USER"
    TARGET_REQUIRED_ROLE="$TABLES_REQUIRED_ROLE"
    TARGET_ROLE_KEY=TABLES_REQUIRED_ROLE
    ;;
  code)
    TARGET_SCHEMA="$CODE_SCHEMA"
    TARGET_CONNECTION="$CODE_SQLCL_CONNECTION"
    TARGET_EXPECTED_USER="$CODE_EXPECTED_USER"
    TARGET_REQUIRED_ROLE="$CODE_REQUIRED_ROLE"
    TARGET_ROLE_KEY=CODE_REQUIRED_ROLE
    ;;
  apex)
    TARGET_SCHEMA="$APEX_PARSING_SCHEMA"
    TARGET_CONNECTION="$APEX_SQLCL_CONNECTION"
    TARGET_EXPECTED_USER="$APEX_EXPECTED_USER"
    TARGET_REQUIRED_ROLE="$APEX_REQUIRED_ROLE"
    TARGET_ROLE_KEY=APEX_REQUIRED_ROLE
    ;;
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
  if [ "$TARGET_REQUIRED_ROLE" = NONE ]; then
    echo "$TARGET_ROLE_KEY is required for production" >&2
    exit 2
  fi
  if [ "$TARGET_EXPECTED_USER" = "$TARGET_SCHEMA" ]; then
    echo "production $TARGET target must use a dedicated non-owner read-only account" >&2
    exit 2
  fi
fi
