-- Exports the APEX application {{APP_ID}} to apps/{{SCHEMA}}/ using SQLcl's
-- APEXLANG export type. Run via:
--   sql -S -noupdates -name {{CONN_NAME}} @scripts/export_apps.sql
SET DEFINE OFF
SET ENCODING UTF-8

apex export -applicationid {{APP_ID}} -exptype APEXLANG -overwrite-files -dir apps/{{SCHEMA}}

exit
