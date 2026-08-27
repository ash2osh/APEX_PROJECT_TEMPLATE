-- Exports every table, view, and package in {{SCHEMA}} to database/{{SCHEMA}}/,
-- one file per object, via DBMS_METADATA. Run via:
--   sql -S -noupdates -name {{CONN_NAME}} @scripts/backup_db.sql
SET DEFINE OFF
SET ENCODING UTF-8
SET PAGESIZE 0
SET LINESIZE 32767
SET LONG 100000000
SET LONGCHUNKSIZE 100000000
SET TRIMSPOOL ON
SET FEEDBACK OFF
SET ECHO OFF
SET VERIFY OFF

BEGIN
  DBMS_METADATA.SET_TRANSFORM_PARAM(DBMS_METADATA.SESSION_TRANSFORM, 'PRETTY', TRUE);
  DBMS_METADATA.SET_TRANSFORM_PARAM(DBMS_METADATA.SESSION_TRANSFORM, 'SQLTERMINATOR', TRUE);
  DBMS_METADATA.SET_TRANSFORM_PARAM(DBMS_METADATA.SESSION_TRANSFORM, 'SEGMENT_ATTRIBUTES', FALSE);
  DBMS_METADATA.SET_TRANSFORM_PARAM(DBMS_METADATA.SESSION_TRANSFORM, 'STORAGE', FALSE);
END;
/

-- Guard: fail loudly if connected to the wrong schema, instead of silently
-- exporting into the wrong directory.
DECLARE
  v_schema VARCHAR2(128) := SYS_CONTEXT('USERENV', 'CURRENT_SCHEMA');
BEGIN
  IF v_schema != '{{SCHEMA}}' THEN
    RAISE_APPLICATION_ERROR(-20001,
      'backup_db.sql expected schema {{SCHEMA}} but current schema is ' || v_schema);
  END IF;
END;
/

SPOOL scripts/_backup_db_driver.sql

SELECT 'SPOOL database/{{SCHEMA}}/tables/' || table_name || '.sql'
       || CHR(10) || 'SELECT DBMS_METADATA.GET_DDL(''TABLE'', ''' || table_name || ''', ''{{SCHEMA}}'') FROM DUAL;'
       || CHR(10) || 'SPOOL OFF'
FROM user_tables
ORDER BY table_name;

SELECT 'SPOOL database/{{SCHEMA}}/views/' || view_name || '.sql'
       || CHR(10) || 'SELECT DBMS_METADATA.GET_DDL(''VIEW'', ''' || view_name || ''', ''{{SCHEMA}}'') FROM DUAL;'
       || CHR(10) || 'SPOOL OFF'
FROM user_views
ORDER BY view_name;

SELECT 'SPOOL database/{{SCHEMA}}/packages/' || object_name || '_SPEC.sql'
       || CHR(10) || 'SELECT DBMS_METADATA.GET_DDL(''PACKAGE_SPEC'', ''' || object_name || ''', ''{{SCHEMA}}'') FROM DUAL;'
       || CHR(10) || 'SPOOL OFF'
       || CHR(10) || 'SPOOL database/{{SCHEMA}}/packages/' || object_name || '_BODY.sql'
       || CHR(10) || 'SELECT DBMS_METADATA.GET_DDL(''PACKAGE_BODY'', ''' || object_name || ''', ''{{SCHEMA}}'') FROM DUAL;'
       || CHR(10) || 'SPOOL OFF'
FROM user_objects
WHERE object_type = 'PACKAGE'
ORDER BY object_name;

SPOOL OFF

@scripts/_backup_db_driver.sql
