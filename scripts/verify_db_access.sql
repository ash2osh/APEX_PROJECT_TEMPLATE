-- Shared read-only identity and production-role gate. The calling script must
-- define target_schema, db_environment, expected_user, and required_role.
SET SERVEROUTPUT ON

SELECT 'SQLcl target: session_user=' || SYS_CONTEXT('USERENV', 'SESSION_USER')
       || ', current_schema=' || SYS_CONTEXT('USERENV', 'CURRENT_SCHEMA')
       || ', db_name=' || SYS_CONTEXT('USERENV', 'DB_NAME')
       || ', service=' || SYS_CONTEXT('USERENV', 'SERVICE_NAME')
FROM DUAL;

DECLARE
  v_target_schema     VARCHAR2(128) := UPPER('&&target_schema');
  v_environment       VARCHAR2(32)  := LOWER('&&db_environment');
  v_expected_user     VARCHAR2(128) := UPPER('&&expected_user');
  v_required_role     VARCHAR2(128) := UPPER('&&required_role');
  v_session_user      VARCHAR2(128) := SYS_CONTEXT('USERENV', 'SESSION_USER');
  v_current_schema    VARCHAR2(128) := SYS_CONTEXT('USERENV', 'CURRENT_SCHEMA');
  v_database_identity VARCHAR2(512) := SYS_CONTEXT('USERENV', 'DB_NAME') || '.'
                                       || SYS_CONTEXT('USERENV', 'SERVICE_NAME');
  v_count             PLS_INTEGER;
BEGIN
  IF v_session_user != v_expected_user THEN
    RAISE_APPLICATION_ERROR(-20001,
      'Expected session user ' || v_expected_user || ' but found ' || v_session_user);
  END IF;

  SELECT COUNT(*) INTO v_count
  FROM all_users
  WHERE username = v_target_schema;
  IF v_count = 0 THEN
    RAISE_APPLICATION_ERROR(-20014,
      'Target schema does not exist or is not visible: ' || v_target_schema);
  END IF;

  IF REGEXP_LIKE(v_database_identity,
       '(^|[^[:alnum:]])(prod|prd|production|live)[[:digit:]]*([^[:alnum:]]|$)', 'i')
     AND v_environment != 'production' THEN
    RAISE_APPLICATION_ERROR(-20002,
      'Database/service identity resembles production; ask the user to classify it before continuing');
  END IF;

  IF v_environment = 'production' THEN
    IF v_session_user = v_target_schema THEN
      RAISE_APPLICATION_ERROR(-20003,
        'Production must use a dedicated non-owner read-only account');
    END IF;

    IF v_required_role IS NULL OR v_required_role = 'NONE' THEN
      RAISE_APPLICATION_ERROR(-20010,
        'Production requires a named read-only role');
    END IF;

    SELECT COUNT(*) INTO v_count FROM session_roles WHERE role = v_required_role;
    IF v_count = 0 THEN
      RAISE_APPLICATION_ERROR(-20004,
        'Required production read-only role is not enabled: ' || v_required_role);
    END IF;

    SELECT COUNT(*) INTO v_count FROM user_objects;
    IF v_count > 0 THEN
      RAISE_APPLICATION_ERROR(-20005,
        'Production read-only account owns database objects');
    END IF;

    SELECT COUNT(*) INTO v_count
    FROM user_role_privs
    WHERE admin_option = 'YES';
    IF v_count > 0 THEN
      RAISE_APPLICATION_ERROR(-20011,
        'Production session user has a role with ADMIN OPTION');
    END IF;

    SELECT COUNT(*) INTO v_count
    FROM user_sys_privs
    WHERE admin_option = 'YES';
    IF v_count > 0 THEN
      RAISE_APPLICATION_ERROR(-20012,
        'Production session user has a system privilege with ADMIN OPTION');
    END IF;

    SELECT COUNT(*) INTO v_count
    FROM user_tab_privs_recd
    WHERE grantable = 'YES';
    IF v_count > 0 THEN
      RAISE_APPLICATION_ERROR(-20013,
        'Production session user has an object privilege with GRANT OPTION');
    END IF;

    SELECT COUNT(*) INTO v_count
    FROM session_privs
    WHERE privilege NOT IN (
      'CREATE SESSION', 'READ ANY TABLE', 'SELECT ANY TABLE',
      'SELECT ANY DICTIONARY', 'SELECT ANY SEQUENCE', 'SELECT ANY TRANSACTION'
    );
    IF v_count > 0 THEN
      RAISE_APPLICATION_ERROR(-20006,
        'Production session has system privileges outside the read-only allowlist');
    END IF;

    SELECT COUNT(*) INTO v_count
    FROM user_tab_privs_recd
    WHERE privilege IN (
      'ALTER', 'DELETE', 'EXECUTE', 'INDEX', 'INSERT', 'REFERENCES', 'UPDATE'
    );
    IF v_count > 0 THEN
      RAISE_APPLICATION_ERROR(-20007,
        'Production session user has direct write-capable object privileges');
    END IF;

    SELECT COUNT(*) INTO v_count
    FROM role_tab_privs
    WHERE privilege IN (
      'ALTER', 'DELETE', 'EXECUTE', 'INDEX', 'INSERT', 'REFERENCES', 'UPDATE'
    )
      AND role IN (SELECT role FROM session_roles);
    IF v_count > 0 THEN
      RAISE_APPLICATION_ERROR(-20008,
        'An enabled production role has write-capable object privileges');
    END IF;
  ELSIF v_expected_user = v_target_schema AND v_current_schema != v_target_schema THEN
    RAISE_APPLICATION_ERROR(-20009,
      'Expected current schema ' || v_target_schema || ' but found ' || v_current_schema);
  END IF;
END;
/
