-- Export schema metadata only (never table data). Arguments are supplied by
-- the validated shell/PowerShell wrappers: schema, scope, environment,
-- expected session user, and required production read-only role.
SET DEFINE ON
DEFINE target_schema = '&1'
DEFINE object_scope = '&2'
DEFINE db_environment = '&3'
DEFINE expected_user = '&4'
DEFINE required_role = '&5'
SET ENCODING UTF-8
SET PAGESIZE 0
SET LINESIZE 32767
SET LONG 100000000
SET LONGCHUNKSIZE 100000000
SET TRIMSPOOL ON
SET FEEDBACK OFF
SET ECHO OFF
SET VERIFY OFF
WHENEVER SQLERROR EXIT SQL.SQLCODE
WHENEVER OSERROR EXIT FAILURE

BEGIN
  IF LOWER('&&object_scope') NOT IN ('tables', 'code') THEN
    RAISE_APPLICATION_ERROR(-20021,
      'Metadata export scope must be tables or code');
  END IF;
END;
/

@@verify_db_access.sql

BEGIN
  DBMS_METADATA.SET_TRANSFORM_PARAM(DBMS_METADATA.SESSION_TRANSFORM, 'PRETTY', TRUE);
  DBMS_METADATA.SET_TRANSFORM_PARAM(DBMS_METADATA.SESSION_TRANSFORM, 'SQLTERMINATOR', TRUE);
  DBMS_METADATA.SET_TRANSFORM_PARAM(DBMS_METADATA.SESSION_TRANSFORM, 'SEGMENT_ATTRIBUTES', FALSE);
  DBMS_METADATA.SET_TRANSFORM_PARAM(DBMS_METADATA.SESSION_TRANSFORM, 'STORAGE', FALSE);
END;
/

-- Object names become filenames and SQL string literals in the generated
-- driver. Reject unexpected names before writing or executing that driver.
DECLARE
  v_count PLS_INTEGER;
BEGIN
  SELECT COUNT(*)
  INTO v_count
  FROM all_objects
  WHERE owner = UPPER('&&target_schema')
    AND (
      (LOWER('&&object_scope') = 'tables' AND object_type = 'TABLE')
      OR
      (LOWER('&&object_scope') = 'code' AND object_type IN (
        'VIEW', 'PACKAGE', 'PACKAGE BODY', 'PROCEDURE', 'FUNCTION', 'TRIGGER'
      ))
    )
    AND NOT REGEXP_LIKE(object_name, '^[A-Za-z0-9_$#]+$');

  IF v_count > 0 THEN
    RAISE_APPLICATION_ERROR(-20020,
      'Schema contains object names that are unsafe for metadata export filenames');
  END IF;
END;
/

SPOOL scripts/_backup_db_driver_&&object_scope..sql

SELECT 'SPOOL database/&&target_schema/tables/' || table_name || '.sql'
       || CHR(10) || 'SELECT DBMS_METADATA.GET_DDL(''TABLE'', ''' || table_name
       || ''', ''&&target_schema'') FROM DUAL;'
       || CHR(10) || 'SPOOL OFF'
FROM all_tables
WHERE LOWER('&&object_scope') = 'tables'
  AND owner = UPPER('&&target_schema')
ORDER BY table_name;

SELECT 'SPOOL database/&&target_schema/views/' || view_name || '.sql'
       || CHR(10) || 'SELECT DBMS_METADATA.GET_DDL(''VIEW'', ''' || view_name
       || ''', ''&&target_schema'') FROM DUAL;'
       || CHR(10) || 'SPOOL OFF'
FROM all_views
WHERE LOWER('&&object_scope') = 'code'
  AND owner = UPPER('&&target_schema')
ORDER BY view_name;

SELECT 'SPOOL database/&&target_schema/packages/' || object_name || '_SPEC.sql'
       || CHR(10) || 'SELECT DBMS_METADATA.GET_DDL(''PACKAGE_SPEC'', ''' || object_name
       || ''', ''&&target_schema'') FROM DUAL;'
       || CHR(10) || 'SPOOL OFF'
FROM all_objects
WHERE LOWER('&&object_scope') = 'code'
  AND owner = UPPER('&&target_schema')
  AND object_type = 'PACKAGE'
ORDER BY object_name;

SELECT 'SPOOL database/&&target_schema/packages/' || object_name || '_BODY.sql'
       || CHR(10) || 'SELECT DBMS_METADATA.GET_DDL(''PACKAGE_BODY'', ''' || object_name
       || ''', ''&&target_schema'') FROM DUAL;'
       || CHR(10) || 'SPOOL OFF'
FROM all_objects
WHERE LOWER('&&object_scope') = 'code'
  AND owner = UPPER('&&target_schema')
  AND object_type = 'PACKAGE BODY'
ORDER BY object_name;

SELECT 'SPOOL database/&&target_schema/procedures/' || object_name || '.sql'
       || CHR(10) || 'SELECT DBMS_METADATA.GET_DDL(''PROCEDURE'', ''' || object_name
       || ''', ''&&target_schema'') FROM DUAL;'
       || CHR(10) || 'SPOOL OFF'
FROM all_objects
WHERE LOWER('&&object_scope') = 'code'
  AND owner = UPPER('&&target_schema')
  AND object_type = 'PROCEDURE'
ORDER BY object_name;

SELECT 'SPOOL database/&&target_schema/functions/' || object_name || '.sql'
       || CHR(10) || 'SELECT DBMS_METADATA.GET_DDL(''FUNCTION'', ''' || object_name
       || ''', ''&&target_schema'') FROM DUAL;'
       || CHR(10) || 'SPOOL OFF'
FROM all_objects
WHERE LOWER('&&object_scope') = 'code'
  AND owner = UPPER('&&target_schema')
  AND object_type = 'FUNCTION'
ORDER BY object_name;

SELECT 'SPOOL database/&&target_schema/triggers/' || object_name || '.sql'
       || CHR(10) || 'SELECT DBMS_METADATA.GET_DDL(''TRIGGER'', ''' || object_name
       || ''', ''&&target_schema'') FROM DUAL;'
       || CHR(10) || 'SPOOL OFF'
FROM all_objects
WHERE LOWER('&&object_scope') = 'code'
  AND owner = UPPER('&&target_schema')
  AND object_type = 'TRIGGER'
ORDER BY object_name;

SPOOL OFF

@scripts/_backup_db_driver_&&object_scope..sql

COLUMN manifest_file NEW_VALUE manifest_file NOPRINT
SELECT CASE LOWER('&&object_scope')
         WHEN 'tables' THEN 'manifest-tables.txt'
         WHEN 'code' THEN 'manifest-code.txt'
       END AS manifest_file
FROM dual;

SPOOL database/&&target_schema/&&manifest_file
WITH expected_types (object_type, object_scope) AS (
  SELECT 'TABLE', 'tables' FROM dual UNION ALL
  SELECT 'VIEW', 'code' FROM dual UNION ALL
  SELECT 'PACKAGE', 'code' FROM dual UNION ALL
  SELECT 'PACKAGE BODY', 'code' FROM dual UNION ALL
  SELECT 'PROCEDURE', 'code' FROM dual UNION ALL
  SELECT 'FUNCTION', 'code' FROM dual UNION ALL
  SELECT 'TRIGGER', 'code' FROM dual
)
SELECT expected_types.object_type || '=' || COUNT(all_objects.object_name)
FROM expected_types
LEFT JOIN all_objects
  ON all_objects.owner = UPPER('&&target_schema')
 AND all_objects.object_type = expected_types.object_type
WHERE expected_types.object_scope = LOWER('&&object_scope')
GROUP BY expected_types.object_type
ORDER BY expected_types.object_type;
SPOOL OFF

SET DEFINE OFF
EXIT
