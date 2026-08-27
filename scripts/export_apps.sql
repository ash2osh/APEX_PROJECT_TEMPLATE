-- Exports the APEX application {{APP_ID}} to apps/{{SCHEMA}}/{{APP_SLUG}}/ using SQLcl's
-- APEXLANG export type. Run via:
--   sql -S -noupdates -name {{CONN_NAME}} @scripts/export_apps.sql
SET DEFINE OFF
SET ENCODING UTF-8
WHENEVER SQLERROR EXIT SQL.SQLCODE
WHENEVER OSERROR EXIT FAILURE

SELECT 'SQLcl target: session_user=' || SYS_CONTEXT('USERENV', 'SESSION_USER')
       || ', current_schema=' || SYS_CONTEXT('USERENV', 'CURRENT_SCHEMA')
       || ', db_name=' || SYS_CONTEXT('USERENV', 'DB_NAME')
       || ', service=' || SYS_CONTEXT('USERENV', 'SERVICE_NAME')
FROM DUAL;

DECLARE
  v_session_user VARCHAR2(128) := SYS_CONTEXT('USERENV', 'SESSION_USER');
  v_current_schema VARCHAR2(128) := SYS_CONTEXT('USERENV', 'CURRENT_SCHEMA');
BEGIN
  IF v_session_user != '{{SCHEMA}}' OR v_current_schema != '{{SCHEMA}}' THEN
    RAISE_APPLICATION_ERROR(-20001,
      'export_apps.sql expected session/current schema {{SCHEMA}} but found '
      || v_session_user || '/' || v_current_schema);
  END IF;
END;
/

apex export -applicationid {{APP_ID}} -exptype APEXLANG -overwrite-files -dir apps/{{SCHEMA}}/{{APP_SLUG}}

exit
