#!/usr/bin/env bash
# Source this file to load a strict KEY=VALUE .env file without executing it.

PROJECT_ENV_FILE="${1:-${PROJECT_ENV_FILE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)/.env}}"

project_env_fail() {
  echo "project environment error: $*" >&2
  return 1
}

if [ ! -f "$PROJECT_ENV_FILE" ]; then
  project_env_fail "configuration file not found: $PROJECT_ENV_FILE (copy .env.example to .env)"
  return 1 2>/dev/null || exit 1
fi

project_env_seen_keys=()
while IFS= read -r project_env_line || [ -n "$project_env_line" ]; do
  project_env_line="${project_env_line%$'\r'}"
  case "$project_env_line" in
    ''|'#'*) continue ;;
  esac
  if [[ ! "$project_env_line" =~ ^([A-Z][A-Z0-9_]*)=(.*)$ ]]; then
    project_env_fail "invalid line in $PROJECT_ENV_FILE: $project_env_line"
    return 1 2>/dev/null || exit 1
  fi
  project_env_key="${BASH_REMATCH[1]}"
  project_env_value="${BASH_REMATCH[2]}"
  case "$project_env_key" in
    PROJECT_NAME|DB_ENVIRONMENT|APEX_APP_ID|APEX_APP_SLUG|\
    TABLES_SCHEMA|TABLES_SQLCL_CONNECTION|TABLES_EXPECTED_USER|TABLES_REQUIRED_ROLE|\
    CODE_SCHEMA|CODE_SQLCL_CONNECTION|CODE_EXPECTED_USER|CODE_REQUIRED_ROLE|\
    APEX_PARSING_SCHEMA|APEX_SQLCL_CONNECTION|APEX_EXPECTED_USER|APEX_REQUIRED_ROLE|\
    INSTALL_UC_APX|UC_APX_SKILLS_AGENT) ;;
    *)
      project_env_fail "unsupported setting in $PROJECT_ENV_FILE: $project_env_key"
      return 1 2>/dev/null || exit 1
      ;;
  esac
  for project_env_seen_key in "${project_env_seen_keys[@]}"; do
    if [ "$project_env_seen_key" = "$project_env_key" ]; then
      project_env_fail "duplicate setting in $PROJECT_ENV_FILE: $project_env_key"
      return 1 2>/dev/null || exit 1
    fi
  done
  if [[ "$project_env_value" == \"*\" && "$project_env_value" == *\" ]]; then
    project_env_value="${project_env_value:1:${#project_env_value}-2}"
  elif [[ "$project_env_value" == \'*\' && "$project_env_value" == *\' ]]; then
    project_env_value="${project_env_value:1:${#project_env_value}-2}"
  fi
  printf -v "$project_env_key" '%s' "$project_env_value"
  export "$project_env_key"
  project_env_seen_keys+=("$project_env_key")
done < "$PROJECT_ENV_FILE"

project_env_required=(
  PROJECT_NAME DB_ENVIRONMENT APEX_APP_ID APEX_APP_SLUG
  TABLES_SCHEMA TABLES_SQLCL_CONNECTION TABLES_EXPECTED_USER TABLES_REQUIRED_ROLE
  CODE_SCHEMA CODE_SQLCL_CONNECTION CODE_EXPECTED_USER CODE_REQUIRED_ROLE
  APEX_PARSING_SCHEMA APEX_SQLCL_CONNECTION APEX_EXPECTED_USER APEX_REQUIRED_ROLE
  INSTALL_UC_APX UC_APX_SKILLS_AGENT
)
for project_env_key in "${project_env_required[@]}"; do
  project_env_seen_present=false
  for project_env_seen_key in "${project_env_seen_keys[@]}"; do
    if [ "$project_env_seen_key" = "$project_env_key" ]; then
      project_env_seen_present=true
      break
    fi
  done
  if [ "$project_env_seen_present" != true ] || [ -z "${!project_env_key:-}" ]; then
    project_env_fail "$project_env_key is required in $PROJECT_ENV_FILE"
    return 1 2>/dev/null || exit 1
  fi
done

[[ "$APEX_APP_ID" =~ ^[1-9][0-9]*$ ]] || {
  project_env_fail "APEX_APP_ID must be a positive integer"
  return 1 2>/dev/null || exit 1
}
[[ "$APEX_APP_SLUG" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || {
  project_env_fail "APEX_APP_SLUG contains unsafe path characters"
  return 1 2>/dev/null || exit 1
}
case "$DB_ENVIRONMENT" in
  development|test|staging|production) ;;
  *)
    project_env_fail "DB_ENVIRONMENT must be development, test, staging, or production"
    return 1 2>/dev/null || exit 1
    ;;
esac
case "$INSTALL_UC_APX" in
  true|false) ;;
  *)
    project_env_fail "INSTALL_UC_APX must be true or false"
    return 1 2>/dev/null || exit 1
    ;;
esac
case "$UC_APX_SKILLS_AGENT" in
  universal|claude-code) ;;
  *)
    project_env_fail "UC_APX_SKILLS_AGENT must be universal or claude-code"
    return 1 2>/dev/null || exit 1
    ;;
esac
for project_env_key in TABLES_SCHEMA TABLES_EXPECTED_USER CODE_SCHEMA \
  CODE_EXPECTED_USER APEX_PARSING_SCHEMA APEX_EXPECTED_USER; do
  if [[ ! "${!project_env_key}" =~ ^[A-Z][A-Z0-9_$#]{0,127}$ ]]; then
    project_env_fail "$project_env_key must be an uppercase Oracle identifier"
    return 1 2>/dev/null || exit 1
  fi
done
for project_env_key in TABLES_SQLCL_CONNECTION CODE_SQLCL_CONNECTION APEX_SQLCL_CONNECTION; do
  if [[ ! "${!project_env_key}" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
    project_env_fail "$project_env_key contains unsupported characters"
    return 1 2>/dev/null || exit 1
  fi
done
for project_env_key in TABLES_REQUIRED_ROLE CODE_REQUIRED_ROLE APEX_REQUIRED_ROLE; do
  if [[ ! "${!project_env_key}" =~ ^[A-Z][A-Z0-9_$#]{0,127}$ ]]; then
    project_env_fail "$project_env_key must be an uppercase Oracle role name or NONE"
    return 1 2>/dev/null || exit 1
  fi
done

unset project_env_line project_env_key project_env_value project_env_required
unset project_env_seen_keys project_env_seen_key project_env_seen_present
