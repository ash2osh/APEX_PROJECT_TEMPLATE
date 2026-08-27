#!/usr/bin/env bash
# Pre-connect environment classification. Database identity is verified in SQL.
set -euo pipefail

OPERATION="${1:?usage: check_db_target.sh <read|write>}"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
# shellcheck source=load_env.sh
source "$REPO_ROOT/scripts/load_env.sh" "${PROJECT_ENV_FILE:-$REPO_ROOT/.env}"

case "$OPERATION" in
  read|write) ;;
  *) echo "unsupported database operation class: $OPERATION" >&2; exit 2 ;;
esac

shopt -s nocasematch
if [[ "$SQLCL_CONNECTION" =~ (^|[-_.])(prod|prd|production|live)[0-9]*([-_.]|$) ]] && \
   [ "$DB_ENVIRONMENT" != production ]; then
  echo "connection '$SQLCL_CONNECTION' resembles production but DB_ENVIRONMENT=$DB_ENVIRONMENT" >&2
  echo "ask the user whether this is production before continuing" >&2
  exit 2
fi
shopt -u nocasematch

if [ "$DB_ENVIRONMENT" = production ]; then
  if [ "$OPERATION" != read ]; then
    echo "production database operations are always read-only; '$OPERATION' is blocked" >&2
    exit 2
  fi
  if [ -z "${DB_REQUIRED_ROLE:-}" ] || [ "$DB_REQUIRED_ROLE" = NONE ]; then
    echo "DB_REQUIRED_ROLE is required for production" >&2
    exit 2
  fi
  if [ "$DB_EXPECTED_USER" = "$DB_TARGET_SCHEMA" ]; then
    echo "production must use a dedicated non-owner read-only account" >&2
    exit 2
  fi
fi
