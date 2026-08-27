-- Read-only audit of a production agent account.
-- Usage: @scripts/audit_production_access.sql TARGET_SCHEMA EXPECTED_USER REQUIRED_ROLE
SET DEFINE ON
DEFINE target_schema = '&1'
DEFINE expected_user = '&2'
DEFINE required_role = '&3'
SET PAGESIZE 100
SET LINESIZE 240
SET FEEDBACK ON
SET VERIFY OFF
WHENEVER SQLERROR EXIT SQL.SQLCODE

PROMPT === Session identity ===
SELECT SYS_CONTEXT('USERENV', 'SESSION_USER') AS session_user,
       SYS_CONTEXT('USERENV', 'CURRENT_SCHEMA') AS current_schema,
       SYS_CONTEXT('USERENV', 'DB_NAME') AS db_name,
       SYS_CONTEXT('USERENV', 'SERVICE_NAME') AS service_name
FROM dual;

PROMPT === Enabled roles ===
SELECT role FROM session_roles ORDER BY role;

PROMPT === Enabled system privileges ===
SELECT privilege FROM session_privs ORDER BY privilege;

PROMPT === Write-capability findings (must return no rows) ===
SELECT 'SESSION_USER_MISMATCH' AS finding, SYS_CONTEXT('USERENV', 'SESSION_USER') AS detail
FROM dual
WHERE SYS_CONTEXT('USERENV', 'SESSION_USER') != UPPER('&&expected_user')
UNION ALL
SELECT 'TARGET_OWNER_LOGIN', SYS_CONTEXT('USERENV', 'SESSION_USER')
FROM dual
WHERE SYS_CONTEXT('USERENV', 'SESSION_USER') = UPPER('&&target_schema')
UNION ALL
SELECT 'REQUIRED_ROLE_NOT_ENABLED', UPPER('&&required_role')
FROM dual
WHERE NOT EXISTS (
  SELECT 1 FROM session_roles WHERE role = UPPER('&&required_role')
)
UNION ALL
SELECT 'OWNED_OBJECT', object_type || ':' || object_name
FROM user_objects
UNION ALL
SELECT 'ROLE_ADMIN_OPTION', granted_role
FROM user_role_privs
WHERE admin_option = 'YES'
UNION ALL
SELECT 'SYSTEM_ADMIN_OPTION', privilege
FROM user_sys_privs
WHERE admin_option = 'YES'
UNION ALL
SELECT 'OBJECT_GRANT_OPTION', owner || '.' || table_name || ':' || privilege
FROM user_tab_privs_recd
WHERE grantable = 'YES'
UNION ALL
SELECT 'NON_READ_SYSTEM_PRIVILEGE', privilege
FROM session_privs
WHERE privilege NOT IN (
  'CREATE SESSION', 'READ ANY TABLE', 'SELECT ANY TABLE',
  'SELECT ANY DICTIONARY', 'SELECT ANY SEQUENCE', 'SELECT ANY TRANSACTION'
)
UNION ALL
SELECT 'DIRECT_WRITE_OBJECT_GRANT', owner || '.' || table_name || ':' || privilege
FROM user_tab_privs_recd
WHERE privilege IN ('ALTER', 'DELETE', 'EXECUTE', 'INDEX', 'INSERT', 'REFERENCES', 'UPDATE')
UNION ALL
SELECT 'ROLE_WRITE_OBJECT_GRANT', owner || '.' || table_name || ':' || privilege
FROM role_tab_privs
WHERE privilege IN ('ALTER', 'DELETE', 'EXECUTE', 'INDEX', 'INSERT', 'REFERENCES', 'UPDATE')
  AND role IN (SELECT role FROM session_roles);

SET DEFINE OFF
EXIT
