-- Export one APEX application as APEXlang. Arguments are supplied by the
-- validated shell/PowerShell wrappers: schema, app id, environment,
-- expected session user, declared role.
SET DEFINE ON
DEFINE target_schema = '&1'
DEFINE app_id = '&2'
DEFINE db_environment = '&3'
DEFINE expected_user = '&4'
DEFINE required_role = '&5'
SET ENCODING UTF-8
WHENEVER SQLERROR EXIT SQL.SQLCODE
WHENEVER OSERROR EXIT FAILURE

@@verify_db_access.sql

-- -dir is the parent directory. SQLcl creates the application-alias child.
apex export -applicationid &&app_id -exptype APEXLANG -overwrite-files -dir apps/&&target_schema

SET DEFINE OFF
exit
