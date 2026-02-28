-- ================================================================
-- WatLogs – PL/SQL Package Script
-- Schema  : watlogs
-- Execute : as the 'watlogs' schema owner
-- Run this BEFORE 01_ddl.sql seed INSERT and 03_ords.sql
-- ================================================================

-- ================================================================
-- Package Specification
-- ================================================================
CREATE OR REPLACE PACKAGE wl_pkg AS

    -- ── Utility ────────────────────────────────────────────────
    FUNCTION  hash_password   (p_password  IN VARCHAR2)  RETURN VARCHAR2;
    FUNCTION  generate_id     RETURN VARCHAR2;
    FUNCTION  get_setting     (p_key       IN VARCHAR2)  RETURN VARCHAR2;
    PROCEDURE set_setting     (p_key       IN VARCHAR2,
                               p_value     IN VARCHAR2,
                               p_updated_by IN VARCHAR2 DEFAULT 'system');
    FUNCTION  json_success    (p_data      IN CLOB)      RETURN CLOB;
    FUNCTION  json_error      (p_message   IN VARCHAR2,
                               p_code      IN NUMBER DEFAULT 400) RETURN CLOB;

    -- ── Captcha ────────────────────────────────────────────────
    PROCEDURE generate_captcha (p_token  OUT VARCHAR2,
                                p_question OUT VARCHAR2);
    FUNCTION  verify_captcha   (p_token  IN VARCHAR2,
                                p_answer IN VARCHAR2)    RETURN BOOLEAN;
    PROCEDURE purge_captcha;   -- remove expired tokens

    -- ── Session ────────────────────────────────────────────────
    FUNCTION  validate_session (p_session_id IN VARCHAR2) RETURN VARCHAR2;
    -- Returns JSON user object or NULL when invalid

    -- ── Auth ───────────────────────────────────────────────────
    PROCEDURE do_login   (p_username    IN  VARCHAR2,
                          p_password    IN  VARCHAR2,
                          p_role        IN  VARCHAR2,
                          p_ip          IN  VARCHAR2,
                          p_cap_token   IN  VARCHAR2,
                          p_cap_answer  IN  VARCHAR2,
                          p_result      OUT CLOB,
                          p_http_status OUT NUMBER);

    PROCEDURE do_logout  (p_session_id  IN  VARCHAR2,
                          p_result      OUT CLOB,
                          p_http_status OUT NUMBER);

    PROCEDURE do_signup  (p_username    IN  VARCHAR2,
                          p_password    IN  VARCHAR2,
                          p_legal_name  IN  VARCHAR2,
                          p_email       IN  VARCHAR2,
                          p_contact     IN  VARCHAR2,
                          p_cap_token   IN  VARCHAR2,
                          p_cap_answer  IN  VARCHAR2,
                          p_result      OUT CLOB,
                          p_http_status OUT NUMBER);

    FUNCTION  get_current_user (p_session_id IN VARCHAR2) RETURN CLOB;

    -- ── Users ──────────────────────────────────────────────────
    FUNCTION  get_users        (p_session_id  IN VARCHAR2,
                                p_status_filter IN VARCHAR2 DEFAULT NULL) RETURN CLOB;
    FUNCTION  get_user         (p_session_id  IN VARCHAR2,
                                p_user_id     IN VARCHAR2) RETURN CLOB;
    PROCEDURE update_user      (p_session_id  IN  VARCHAR2,
                                p_user_id     IN  VARCHAR2,
                                p_legal_name  IN  VARCHAR2,
                                p_email       IN  VARCHAR2,
                                p_contact     IN  VARCHAR2,
                                p_result      OUT CLOB,
                                p_http_status OUT NUMBER);
    PROCEDURE update_user_status (p_session_id  IN  VARCHAR2,
                                  p_user_id     IN  VARCHAR2,
                                  p_status      IN  VARCHAR2,
                                  p_result      OUT CLOB,
                                  p_http_status OUT NUMBER);
    PROCEDURE approve_user     (p_session_id  IN  VARCHAR2,
                                p_user_id     IN  VARCHAR2,
                                p_result      OUT CLOB,
                                p_http_status OUT NUMBER);
    PROCEDURE create_user      (p_session_id  IN  VARCHAR2,
                                p_username    IN  VARCHAR2,
                                p_password    IN  VARCHAR2,
                                p_legal_name  IN  VARCHAR2,
                                p_email       IN  VARCHAR2,
                                p_contact     IN  VARCHAR2,
                                p_role        IN  VARCHAR2,
                                p_result      OUT CLOB,
                                p_http_status OUT NUMBER);
    PROCEDURE change_password  (p_session_id  IN  VARCHAR2,
                                p_current_pwd IN  VARCHAR2,
                                p_new_pwd     IN  VARCHAR2,
                                p_result      OUT CLOB,
                                p_http_status OUT NUMBER);

    -- ── Sessions list ─────────────────────────────────────────
    FUNCTION  get_sessions     (p_session_id  IN VARCHAR2) RETURN CLOB;

    -- ── Login history ─────────────────────────────────────────
    FUNCTION  get_history      (p_session_id  IN VARCHAR2,
                                p_user_filter IN VARCHAR2 DEFAULT NULL,
                                p_from_date   IN VARCHAR2 DEFAULT NULL,
                                p_to_date     IN VARCHAR2 DEFAULT NULL,
                                p_status_filter IN VARCHAR2 DEFAULT NULL) RETURN CLOB;
    FUNCTION  get_my_history   (p_session_id  IN VARCHAR2) RETURN CLOB;

    -- ── Check-ins ─────────────────────────────────────────────
    PROCEDURE do_checkin       (p_session_id  IN  VARCHAR2,
                                p_result      OUT CLOB,
                                p_http_status OUT NUMBER);
    PROCEDURE do_checkout      (p_session_id  IN  VARCHAR2,
                                p_checkin_id  IN  VARCHAR2,
                                p_result      OUT CLOB,
                                p_http_status OUT NUMBER);
    FUNCTION  get_checkins     (p_session_id  IN VARCHAR2) RETURN CLOB;
    FUNCTION  get_my_checkins  (p_session_id  IN VARCHAR2) RETURN CLOB;

    -- ── Lookup / Settings ─────────────────────────────────────
    FUNCTION  get_all_settings  (p_session_id  IN VARCHAR2) RETURN CLOB;
    PROCEDURE save_settings     (p_session_id  IN  VARCHAR2,
                                 p_settings_json IN  CLOB,
                                 p_result      OUT CLOB,
                                 p_http_status OUT NUMBER);

    -- ── Bulk import ───────────────────────────────────────────
    PROCEDURE bulk_import      (p_session_id  IN  VARCHAR2,
                                p_users_json  IN  CLOB,
                                p_result      OUT CLOB,
                                p_http_status OUT NUMBER);

END wl_pkg;
/

-- ================================================================
-- Package Body
-- ================================================================
CREATE OR REPLACE PACKAGE BODY wl_pkg AS

    -- ──────────────────────────────────────────────────────────
    -- Internal constants
    -- ──────────────────────────────────────────────────────────
    c_salt CONSTANT VARCHAR2(20) := '__wl2024__';

    -- ──────────────────────────────────────────────────────────
    -- UTILITY: hash_password
    --   SHA-256 of (password || '__wl2024__'), returned as lowercase hex.
    -- ──────────────────────────────────────────────────────────
    FUNCTION hash_password(p_password IN VARCHAR2) RETURN VARCHAR2 IS
    BEGIN
        RETURN LOWER(RAWTOHEX(
            DBMS_CRYPTO.HASH(
                UTL_RAW.CAST_TO_RAW(p_password || c_salt),
                DBMS_CRYPTO.HASH_SH256
            )
        ));
    END hash_password;

    -- ──────────────────────────────────────────────────────────
    -- UTILITY: generate_id  (timestamp-based unique identifier)
    -- ──────────────────────────────────────────────────────────
    FUNCTION generate_id RETURN VARCHAR2 IS
    BEGIN
        RETURN 'id' || TO_CHAR(SYSTIMESTAMP,'YYYYMMDDHH24MISSFF6')
                    || LOWER(RAWTOHEX(DBMS_CRYPTO.RANDOMBYTES(4)));
    END generate_id;

    -- ──────────────────────────────────────────────────────────
    -- UTILITY: get/set setting
    -- ──────────────────────────────────────────────────────────
    FUNCTION get_setting(p_key IN VARCHAR2) RETURN VARCHAR2 IS
        v_val CLOB;
    BEGIN
        SELECT setting_value INTO v_val
        FROM   wl_lookup
        WHERE  setting_key = p_key;
        RETURN SUBSTR(v_val, 1, 4000);
    EXCEPTION
        WHEN NO_DATA_FOUND THEN RETURN NULL;
    END get_setting;

    PROCEDURE set_setting(p_key IN VARCHAR2, p_value IN VARCHAR2,
                          p_updated_by IN VARCHAR2 DEFAULT 'system') IS
    BEGIN
        MERGE INTO wl_lookup t
        USING (SELECT p_key k FROM DUAL) s ON (t.setting_key = s.k)
        WHEN MATCHED     THEN UPDATE SET setting_value = p_value,
                                         updated_by    = p_updated_by,
                                         updated_at    = SYSTIMESTAMP
        WHEN NOT MATCHED THEN INSERT (setting_key, setting_value, updated_by)
                              VALUES (p_key, p_value, p_updated_by);
        COMMIT;
    END set_setting;

    -- ──────────────────────────────────────────────────────────
    -- UTILITY: JSON helpers
    -- ──────────────────────────────────────────────────────────
    FUNCTION json_success(p_data IN CLOB) RETURN CLOB IS
    BEGIN
        RETURN '{"ok":true,"data":' || p_data || '}';
    END json_success;

    FUNCTION json_error(p_message IN VARCHAR2, p_code IN NUMBER DEFAULT 400)
    RETURN CLOB IS
    BEGIN
        RETURN '{"ok":false,"message":' || APEX_JSON.STRINGIFY(p_message) || '}';
    END json_error;

    -- ──────────────────────────────────────────────────────────
    -- UTILITY: user_to_json  (internal helper)
    -- ──────────────────────────────────────────────────────────
    FUNCTION user_to_json(r IN wl_users%ROWTYPE) RETURN CLOB IS
    BEGIN
        RETURN '{'
            || '"id":'          || APEX_JSON.STRINGIFY(r.id)          || ','
            || '"username":'    || APEX_JSON.STRINGIFY(r.username)    || ','
            || '"role":'        || APEX_JSON.STRINGIFY(r.role)        || ','
            || '"legalName":'   || APEX_JSON.STRINGIFY(r.legal_name)  || ','
            || '"email":'       || APEX_JSON.STRINGIFY(r.email)       || ','
            || '"contactInfo":' || APEX_JSON.STRINGIFY(r.contact_info)|| ','
            || '"status":'      || APEX_JSON.STRINGIFY(r.status)      || ','
            || '"createdBy":'   || APEX_JSON.STRINGIFY(r.created_by)  || ','
            || '"lastLogin":'   || APEX_JSON.STRINGIFY(
                                      TO_CHAR(r.last_login,
                                              'YYYY-MM-DD"T"HH24:MI:SS"Z"'))|| ','
            || '"lastIp":'      || APEX_JSON.STRINGIFY(r.last_ip)     || ','
            || '"createdAt":'   || APEX_JSON.STRINGIFY(
                                      TO_CHAR(r.created_at,
                                              'YYYY-MM-DD"T"HH24:MI:SS"Z"'))
            || '}';
    END user_to_json;

    -- ──────────────────────────────────────────────────────────
    -- CAPTCHA: generate_captcha
    -- ──────────────────────────────────────────────────────────
    PROCEDURE generate_captcha(p_token   OUT VARCHAR2,
                                p_question OUT VARCHAR2) IS
        v_a   NUMBER;
        v_b   NUMBER;
        v_op  VARCHAR2(3);
        v_ans NUMBER;
    BEGIN
        purge_captcha;
        v_a  := TRUNC(DBMS_RANDOM.VALUE(1, 20));
        v_b  := TRUNC(DBMS_RANDOM.VALUE(1, 10));
        v_op := CASE TRUNC(DBMS_RANDOM.VALUE(0,3))
                    WHEN 0 THEN '+'
                    WHEN 1 THEN '-'
                    ELSE        '*'
                END;
        v_ans := CASE v_op
                    WHEN '+' THEN v_a + v_b
                    WHEN '-' THEN ABS(v_a - v_b)
                    ELSE          v_a * v_b
                 END;
        p_token    := LOWER(RAWTOHEX(DBMS_CRYPTO.RANDOMBYTES(16)));
        p_question := v_a || ' ' || v_op || ' ' || v_b || ' = ?';
        INSERT INTO wl_captcha (token, answer, created_at, expires_at, used)
        VALUES (p_token, TO_CHAR(v_ans), SYSTIMESTAMP,
                SYSTIMESTAMP + INTERVAL '5' MINUTE, 0);
        COMMIT;
    END generate_captcha;

    FUNCTION verify_captcha(p_token IN VARCHAR2, p_answer IN VARCHAR2)
    RETURN BOOLEAN IS
        v_ans  VARCHAR2(20);
        v_exp  TIMESTAMP WITH TIME ZONE;
        v_used NUMBER;
    BEGIN
        BEGIN
            SELECT answer, expires_at, used
            INTO   v_ans, v_exp, v_used
            FROM   wl_captcha
            WHERE  token = p_token;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN RETURN FALSE;
        END;
        IF v_used = 1 OR v_exp < SYSTIMESTAMP THEN RETURN FALSE; END IF;
        IF TRIM(LOWER(p_answer)) <> LOWER(v_ans)  THEN RETURN FALSE; END IF;
        UPDATE wl_captcha SET used = 1 WHERE token = p_token;
        COMMIT;
        RETURN TRUE;
    END verify_captcha;

    PROCEDURE purge_captcha IS
    BEGIN
        DELETE FROM wl_captcha WHERE expires_at < SYSTIMESTAMP;
        COMMIT;
    END purge_captcha;

    -- ──────────────────────────────────────────────────────────
    -- SESSION: validate_session
    --   Returns JSON user object (with nested session) or NULL.
    -- ──────────────────────────────────────────────────────────
    FUNCTION validate_session(p_session_id IN VARCHAR2) RETURN VARCHAR2 IS
        v_sess  wl_sessions%ROWTYPE;
        v_user  wl_users%ROWTYPE;
    BEGIN
        IF p_session_id IS NULL THEN RETURN NULL; END IF;
        BEGIN
            SELECT * INTO v_sess FROM wl_sessions
            WHERE  id = p_session_id AND active = 1;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN RETURN NULL;
        END;
        BEGIN
            SELECT * INTO v_user FROM wl_users
            WHERE  id = v_sess.user_id AND status = 'active';
        EXCEPTION
            WHEN NO_DATA_FOUND THEN RETURN NULL;
        END;
        RETURN '{'
            || '"id":'        || APEX_JSON.STRINGIFY(v_sess.id)         || ','
            || '"userId":'    || APEX_JSON.STRINGIFY(v_sess.user_id)    || ','
            || '"username":'  || APEX_JSON.STRINGIFY(v_sess.username)   || ','
            || '"role":'      || APEX_JSON.STRINGIFY(v_sess.role)       || ','
            || '"ipAddress":' || APEX_JSON.STRINGIFY(v_sess.ip_address) || ','
            || '"loginTime":' || APEX_JSON.STRINGIFY(
                                    TO_CHAR(v_sess.login_time,
                                            'YYYY-MM-DD"T"HH24:MI:SS"Z"'))|| ','
            || '"user":'      || user_to_json(v_user)
            || '}';
    END validate_session;

    -- ──────────────────────────────────────────────────────────
    -- AUTH: do_login
    -- ──────────────────────────────────────────────────────────
    PROCEDURE do_login(p_username    IN  VARCHAR2,
                       p_password    IN  VARCHAR2,
                       p_role        IN  VARCHAR2,
                       p_ip          IN  VARCHAR2,
                       p_cap_token   IN  VARCHAR2,
                       p_cap_answer  IN  VARCHAR2,
                       p_result      OUT CLOB,
                       p_http_status OUT NUMBER) IS
        v_user     wl_users%ROWTYPE;
        v_sess_id  VARCHAR2(40);
        v_hist_id  VARCHAR2(40);
        v_now      TIMESTAMP WITH TIME ZONE := SYSTIMESTAMP;
        v_lkp_ip   VARCHAR2(4000);
        v_ip_ena   VARCHAR2(10);
    BEGIN
        -- Validate inputs
        IF p_username IS NULL OR p_password IS NULL THEN
            p_http_status := 400;
            p_result := json_error('Username and password are required.');
            RETURN;
        END IF;

        -- Server-side captcha verification (when token is provided)
        IF p_cap_token IS NOT NULL AND LENGTH(TRIM(p_cap_token)) > 0 THEN
            IF NOT verify_captcha(p_cap_token, p_cap_answer) THEN
                p_http_status := 400;
                p_result := json_error('Captcha verification failed. Please try again.');
                RETURN;
            END IF;
        END IF;

        -- Fetch user
        BEGIN
            SELECT * INTO v_user FROM wl_users
            WHERE  LOWER(username) = LOWER(p_username);
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                p_http_status := 401;
                p_result := json_error('Invalid username or password.');
                RETURN;
        END;

        -- Password check
        IF v_user.password_hash <> hash_password(p_password) THEN
            p_http_status := 401;
            p_result := json_error('Invalid username or password.');
            RETURN;
        END IF;

        -- Status checks
        IF v_user.status = 'pending' THEN
            p_http_status := 403;
            p_result := json_error('Account pending admin approval. Please wait for an administrator to activate your account.');
            RETURN;
        END IF;
        IF v_user.status = 'frozen' THEN
            p_http_status := 403;
            p_result := json_error('Account is frozen. Contact an administrator.');
            RETURN;
        END IF;

        -- Role check
        IF p_role IS NOT NULL AND p_role <> v_user.role THEN
            p_http_status := 401;
            p_result := json_error('This account has role "' || v_user.role
                                   || '". Please select the correct role.');
            RETURN;
        END IF;

        -- IP restriction
        v_ip_ena := get_setting('ip_restriction_enabled');
        IF v_ip_ena = 'true' THEN
            v_lkp_ip := get_setting('allowed_ips');
            -- Proper check: IP must appear as a complete entry (quoted in JSON array)
            -- or match as an exact prefix (prefix entry followed by '.')
            IF v_lkp_ip IS NOT NULL THEN
                DECLARE
                    v_ip_allowed BOOLEAN := FALSE;
                BEGIN
                    -- Exact IP match: ["...","<ip>","..."]
                    IF INSTR(v_lkp_ip, '"' || p_ip || '"') > 0 THEN
                        v_ip_allowed := TRUE;
                    END IF;
                    -- Prefix match: IP starts with the stored prefix followed by a dot
                    -- e.g., stored "192.168.1" matches "192.168.1.100" but NOT "192.168.10.1"
                    IF NOT v_ip_allowed THEN
                        FOR rec IN (
                            SELECT TRIM(REPLACE(REPLACE(column_value, '"', ''), '[', '')) AS pfx
                            FROM   TABLE(APEX_STRING.SPLIT(v_lkp_ip, ','))
                            WHERE  TRIM(REPLACE(REPLACE(column_value, '"', ''), ']', '')) IS NOT NULL
                        ) LOOP
                            IF rec.pfx IS NOT NULL AND
                               SUBSTR(p_ip, 1, LENGTH(rec.pfx) + 1) = rec.pfx || '.' THEN
                                v_ip_allowed := TRUE;
                            END IF;
                        END LOOP;
                    END IF;
                    IF NOT v_ip_allowed THEN
                        p_http_status := 403;
                        p_result := json_error('Your IP (' || p_ip || ') is not on the allowed list.');
                        RETURN;
                    END IF;
                END;
            END IF;
        END IF;

        -- One active session per user
        DECLARE
            v_active_sess VARCHAR2(40);
        BEGIN
            SELECT id INTO v_active_sess FROM wl_sessions
            WHERE  user_id = v_user.id AND active = 1
            AND    ROWNUM  = 1;
            p_http_status := 409;
            p_result := json_error('This account already has an active session. Logout from the other device first.');
            RETURN;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN NULL;
        END;

        -- Create session
        v_sess_id := generate_id();
        INSERT INTO wl_sessions (id, user_id, username, role, login_time,
                                  ip_address, active)
        VALUES (v_sess_id, v_user.id, v_user.username, v_user.role,
                v_now, p_ip, 1);

        -- Login history
        v_hist_id := generate_id();
        INSERT INTO wl_login_history (id, user_id, username, role, login_time,
                                       ip_address, status, session_id)
        VALUES (v_hist_id, v_user.id, v_user.username, v_user.role,
                v_now, p_ip, 'logged_in', v_sess_id);

        -- Update user last login
        UPDATE wl_users SET last_login = v_now, last_ip = p_ip,
                            updated_at = v_now
        WHERE  id = v_user.id;

        COMMIT;

        p_http_status := 200;
        p_result := json_success('{"session":' || validate_session(v_sess_id) || '}');
    END do_login;

    -- ──────────────────────────────────────────────────────────
    -- AUTH: do_logout
    -- ──────────────────────────────────────────────────────────
    PROCEDURE do_logout(p_session_id  IN  VARCHAR2,
                        p_result      OUT CLOB,
                        p_http_status OUT NUMBER) IS
        v_now    TIMESTAMP WITH TIME ZONE := SYSTIMESTAMP;
        v_uid    VARCHAR2(40);
    BEGIN
        IF p_session_id IS NULL THEN
            p_http_status := 400;
            p_result := json_error('Session ID required.');
            RETURN;
        END IF;
        BEGIN
            SELECT user_id INTO v_uid FROM wl_sessions
            WHERE  id = p_session_id AND active = 1;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                p_http_status := 200;
                p_result := json_success('"logged_out"');
                RETURN;
        END;

        UPDATE wl_sessions SET active = 0, logout_time = v_now,
                               updated_at = v_now
        WHERE  id = p_session_id;

        UPDATE wl_login_history
        SET    status = 'logged_out', logout_time = v_now, updated_at = v_now
        WHERE  session_id = p_session_id AND status = 'logged_in';

        -- Auto-checkout if checked in
        UPDATE wl_checkins
        SET    checkout_time = v_now,
               duration_mins = ROUND((EXTRACT(DAY FROM (v_now - checkin_time))*86400
                                     + EXTRACT(HOUR FROM (v_now - checkin_time))*3600
                                     + EXTRACT(MINUTE FROM (v_now - checkin_time))*60
                                     + EXTRACT(SECOND FROM (v_now - checkin_time))) / 60),
               updated_at    = v_now
        WHERE  user_id = v_uid AND checkout_time IS NULL;

        COMMIT;
        p_http_status := 200;
        p_result := json_success('"logged_out"');
    END do_logout;

    -- ──────────────────────────────────────────────────────────
    -- AUTH: do_signup
    -- ──────────────────────────────────────────────────────────
    PROCEDURE do_signup(p_username    IN  VARCHAR2,
                        p_password    IN  VARCHAR2,
                        p_legal_name  IN  VARCHAR2,
                        p_email       IN  VARCHAR2,
                        p_contact     IN  VARCHAR2,
                        p_cap_token   IN  VARCHAR2,
                        p_cap_answer  IN  VARCHAR2,
                        p_result      OUT CLOB,
                        p_http_status OUT NUMBER) IS
        v_id        VARCHAR2(40);
        v_req_appr  VARCHAR2(10);
        v_status    VARCHAR2(20);
        v_cnt       NUMBER;
    BEGIN
        -- Required fields
        IF p_username IS NULL OR p_password IS NULL OR p_legal_name IS NULL
           OR p_email IS NULL THEN
            p_http_status := 400;
            p_result := json_error('Username, password, legal name and email are required.');
            RETURN;
        END IF;

        -- Server-side captcha verification (when token is provided)
        IF p_cap_token IS NOT NULL AND LENGTH(TRIM(p_cap_token)) > 0 THEN
            IF NOT verify_captcha(p_cap_token, p_cap_answer) THEN
                p_http_status := 400;
                p_result := json_error('Captcha verification failed. Please try again.');
                RETURN;
            END IF;
        END IF;

        IF LENGTH(p_password) < 6 THEN
            p_http_status := 400;
            p_result := json_error('Password must be at least 6 characters.');
            RETURN;
        END IF;

        -- Duplicate username check
        SELECT COUNT(*) INTO v_cnt FROM wl_users
        WHERE  LOWER(username) = LOWER(p_username);
        IF v_cnt > 0 THEN
            p_http_status := 409;
            p_result := json_error('Username already taken.');
            RETURN;
        END IF;

        -- Duplicate email check
        IF p_email IS NOT NULL THEN
            SELECT COUNT(*) INTO v_cnt FROM wl_users
            WHERE  LOWER(email) = LOWER(p_email);
            IF v_cnt > 0 THEN
                p_http_status := 409;
                p_result := json_error('Email already registered.');
                RETURN;
            END IF;
        END IF;

        -- Determine initial status
        v_req_appr := NVL(get_setting('require_approval'), 'true');
        v_status   := CASE v_req_appr WHEN 'true' THEN 'pending' ELSE 'active' END;

        v_id := generate_id();
        INSERT INTO wl_users (id, username, password_hash, role,
                               legal_name, email, contact_info,
                               status, created_by)
        VALUES (v_id, p_username, hash_password(p_password), 'user',
                p_legal_name, p_email, p_contact, v_status, 'signup');
        COMMIT;

        p_http_status := 201;
        IF v_status = 'pending' THEN
            p_result := json_success('{"message":"Account created. Awaiting admin approval before you can log in.","requiresApproval":true}');
        ELSE
            p_result := json_success('{"message":"Account created successfully. You can now sign in.","requiresApproval":false}');
        END IF;
    END do_signup;

    -- ──────────────────────────────────────────────────────────
    -- AUTH: get_current_user
    -- ──────────────────────────────────────────────────────────
    FUNCTION get_current_user(p_session_id IN VARCHAR2) RETURN CLOB IS
        v_sess_json VARCHAR2(32767);
    BEGIN
        v_sess_json := validate_session(p_session_id);
        IF v_sess_json IS NULL THEN
            RETURN json_error('Invalid or expired session.', 401);
        END IF;
        RETURN json_success('{"session":' || v_sess_json || '}');
    END get_current_user;

    -- ──────────────────────────────────────────────────────────
    -- USERS: get_users
    -- ──────────────────────────────────────────────────────────
    FUNCTION get_users(p_session_id    IN VARCHAR2,
                       p_status_filter IN VARCHAR2 DEFAULT NULL) RETURN CLOB IS
        v_sess  VARCHAR2(32767);
        v_role  VARCHAR2(20);
        v_uid   VARCHAR2(40);
        v_json  CLOB := '[';
        v_first BOOLEAN := TRUE;
        v_user  wl_users%ROWTYPE;
        CURSOR c_users IS
            SELECT * FROM wl_users
            WHERE  id <> v_uid
            AND    (v_role = 'superadmin' OR role <> 'superadmin')
            AND    (p_status_filter IS NULL OR status = p_status_filter)
            ORDER  BY username;
    BEGIN
        v_sess := validate_session(p_session_id);
        IF v_sess IS NULL THEN
            RETURN json_error('Invalid or expired session.', 401);
        END IF;
        APEX_JSON.PARSE(v_sess);
        v_role := APEX_JSON.GET_VARCHAR2('role');
        v_uid  := APEX_JSON.GET_VARCHAR2('userId');
        IF v_role NOT IN ('admin','superadmin') THEN
            RETURN json_error('Insufficient permissions.', 403);
        END IF;
        FOR r IN c_users LOOP
            IF NOT v_first THEN v_json := v_json || ','; END IF;
            v_json  := v_json || user_to_json(r);
            v_first := FALSE;
        END LOOP;
        v_json := v_json || ']';
        RETURN json_success(v_json);
    END get_users;

    -- ──────────────────────────────────────────────────────────
    -- USERS: get_user
    -- ──────────────────────────────────────────────────────────
    FUNCTION get_user(p_session_id IN VARCHAR2,
                      p_user_id    IN VARCHAR2) RETURN CLOB IS
        v_sess VARCHAR2(32767);
        v_role VARCHAR2(20);
        v_uid  VARCHAR2(40);
        v_user wl_users%ROWTYPE;
    BEGIN
        v_sess := validate_session(p_session_id);
        IF v_sess IS NULL THEN RETURN json_error('Invalid session.', 401); END IF;
        APEX_JSON.PARSE(v_sess);
        v_role := APEX_JSON.GET_VARCHAR2('role');
        v_uid  := APEX_JSON.GET_VARCHAR2('userId');
        -- Allow self or admin+
        IF p_user_id <> v_uid AND v_role NOT IN ('admin','superadmin') THEN
            RETURN json_error('Insufficient permissions.', 403);
        END IF;
        BEGIN
            SELECT * INTO v_user FROM wl_users WHERE id = p_user_id;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN RETURN json_error('User not found.', 404);
        END;
        RETURN json_success(user_to_json(v_user));
    END get_user;

    -- ──────────────────────────────────────────────────────────
    -- USERS: update_user (profile)
    -- ──────────────────────────────────────────────────────────
    PROCEDURE update_user(p_session_id  IN  VARCHAR2,
                          p_user_id     IN  VARCHAR2,
                          p_legal_name  IN  VARCHAR2,
                          p_email       IN  VARCHAR2,
                          p_contact     IN  VARCHAR2,
                          p_result      OUT CLOB,
                          p_http_status OUT NUMBER) IS
        v_sess VARCHAR2(32767);
        v_uid  VARCHAR2(40);
        v_cnt  NUMBER;
    BEGIN
        v_sess := validate_session(p_session_id);
        IF v_sess IS NULL THEN
            p_http_status := 401; p_result := json_error('Invalid session.'); RETURN;
        END IF;
        APEX_JSON.PARSE(v_sess);
        v_uid := APEX_JSON.GET_VARCHAR2('userId');
        IF p_user_id <> v_uid THEN
            p_http_status := 403; p_result := json_error('Cannot update another user.'); RETURN;
        END IF;
        IF p_legal_name IS NULL THEN
            p_http_status := 400; p_result := json_error('Legal name is required.'); RETURN;
        END IF;
        IF p_email IS NOT NULL THEN
            SELECT COUNT(*) INTO v_cnt FROM wl_users
            WHERE  LOWER(email) = LOWER(p_email) AND id <> p_user_id;
            IF v_cnt > 0 THEN
                p_http_status := 409; p_result := json_error('Email already used.'); RETURN;
            END IF;
        END IF;
        UPDATE wl_users SET legal_name   = p_legal_name,
                            email        = p_email,
                            contact_info = p_contact,
                            updated_at   = SYSTIMESTAMP
        WHERE  id = p_user_id;
        COMMIT;
        p_http_status := 200;
        p_result := json_success('"updated"');
    END update_user;

    -- ──────────────────────────────────────────────────────────
    -- USERS: update_user_status (freeze/activate)
    -- ──────────────────────────────────────────────────────────
    PROCEDURE update_user_status(p_session_id  IN  VARCHAR2,
                                  p_user_id     IN  VARCHAR2,
                                  p_status      IN  VARCHAR2,
                                  p_result      OUT CLOB,
                                  p_http_status OUT NUMBER) IS
        v_sess VARCHAR2(32767);
        v_role VARCHAR2(20);
    BEGIN
        v_sess := validate_session(p_session_id);
        IF v_sess IS NULL THEN
            p_http_status := 401; p_result := json_error('Invalid session.'); RETURN;
        END IF;
        APEX_JSON.PARSE(v_sess);
        v_role := APEX_JSON.GET_VARCHAR2('role');
        IF v_role NOT IN ('admin','superadmin') THEN
            p_http_status := 403; p_result := json_error('Insufficient permissions.'); RETURN;
        END IF;
        IF p_status NOT IN ('active','frozen') THEN
            p_http_status := 400; p_result := json_error('Invalid status.'); RETURN;
        END IF;
        UPDATE wl_users SET status = p_status, updated_at = SYSTIMESTAMP
        WHERE  id = p_user_id;
        IF p_status = 'frozen' THEN
            UPDATE wl_sessions SET active = 0, logout_time = SYSTIMESTAMP
            WHERE  user_id = p_user_id AND active = 1;
        END IF;
        COMMIT;
        p_http_status := 200;
        p_result := json_success('"status_updated"');
    END update_user_status;

    -- ──────────────────────────────────────────────────────────
    -- USERS: approve_user
    -- ──────────────────────────────────────────────────────────
    PROCEDURE approve_user(p_session_id  IN  VARCHAR2,
                           p_user_id     IN  VARCHAR2,
                           p_result      OUT CLOB,
                           p_http_status OUT NUMBER) IS
        v_sess VARCHAR2(32767);
        v_role VARCHAR2(20);
        v_cnt  NUMBER;
    BEGIN
        v_sess := validate_session(p_session_id);
        IF v_sess IS NULL THEN
            p_http_status := 401; p_result := json_error('Invalid session.'); RETURN;
        END IF;
        APEX_JSON.PARSE(v_sess);
        v_role := APEX_JSON.GET_VARCHAR2('role');
        IF v_role NOT IN ('admin','superadmin') THEN
            p_http_status := 403; p_result := json_error('Insufficient permissions.'); RETURN;
        END IF;
        SELECT COUNT(*) INTO v_cnt FROM wl_users
        WHERE  id = p_user_id AND status = 'pending';
        IF v_cnt = 0 THEN
            p_http_status := 404; p_result := json_error('Pending user not found.'); RETURN;
        END IF;
        UPDATE wl_users SET status = 'active', updated_at = SYSTIMESTAMP
        WHERE  id = p_user_id;
        COMMIT;
        p_http_status := 200;
        p_result := json_success('"approved"');
    END approve_user;

    -- ──────────────────────────────────────────────────────────
    -- USERS: create_user (admin-created)
    -- ──────────────────────────────────────────────────────────
    PROCEDURE create_user(p_session_id  IN  VARCHAR2,
                          p_username    IN  VARCHAR2,
                          p_password    IN  VARCHAR2,
                          p_legal_name  IN  VARCHAR2,
                          p_email       IN  VARCHAR2,
                          p_contact     IN  VARCHAR2,
                          p_role        IN  VARCHAR2,
                          p_result      OUT CLOB,
                          p_http_status OUT NUMBER) IS
        v_sess   VARCHAR2(32767);
        v_srole  VARCHAR2(20);
        v_suname VARCHAR2(100);
        v_cnt    NUMBER;
        v_id     VARCHAR2(40);
    BEGIN
        v_sess := validate_session(p_session_id);
        IF v_sess IS NULL THEN
            p_http_status := 401; p_result := json_error('Invalid session.'); RETURN;
        END IF;
        APEX_JSON.PARSE(v_sess);
        v_srole  := APEX_JSON.GET_VARCHAR2('role');
        v_suname := APEX_JSON.GET_VARCHAR2('username');
        IF v_srole NOT IN ('admin','superadmin') THEN
            p_http_status := 403; p_result := json_error('Insufficient permissions.'); RETURN;
        END IF;
        IF p_role = 'admin' AND v_srole <> 'superadmin' THEN
            p_http_status := 403; p_result := json_error('Only superadmin can create admin accounts.'); RETURN;
        END IF;
        SELECT COUNT(*) INTO v_cnt FROM wl_users WHERE LOWER(username) = LOWER(p_username);
        IF v_cnt > 0 THEN p_http_status := 409; p_result := json_error('Username already taken.'); RETURN; END IF;
        IF p_email IS NOT NULL THEN
            SELECT COUNT(*) INTO v_cnt FROM wl_users WHERE LOWER(email) = LOWER(p_email);
            IF v_cnt > 0 THEN p_http_status := 409; p_result := json_error('Email already registered.'); RETURN; END IF;
        END IF;
        v_id := generate_id();
        INSERT INTO wl_users (id, username, password_hash, role,
                               legal_name, email, contact_info,
                               status, created_by)
        VALUES (v_id, p_username, hash_password(p_password),
                NVL(p_role,'user'), p_legal_name, p_email, p_contact,
                'active', v_suname);
        COMMIT;
        p_http_status := 201;
        p_result := json_success('"created"');
    END create_user;

    -- ──────────────────────────────────────────────────────────
    -- USERS: change_password
    -- ──────────────────────────────────────────────────────────
    PROCEDURE change_password(p_session_id  IN  VARCHAR2,
                               p_current_pwd IN  VARCHAR2,
                               p_new_pwd     IN  VARCHAR2,
                               p_result      OUT CLOB,
                               p_http_status OUT NUMBER) IS
        v_sess   VARCHAR2(32767);
        v_uid    VARCHAR2(40);
        v_stored VARCHAR2(128);
    BEGIN
        v_sess := validate_session(p_session_id);
        IF v_sess IS NULL THEN
            p_http_status := 401; p_result := json_error('Invalid session.'); RETURN;
        END IF;
        APEX_JSON.PARSE(v_sess);
        v_uid := APEX_JSON.GET_VARCHAR2('userId');
        SELECT password_hash INTO v_stored FROM wl_users WHERE id = v_uid;
        IF v_stored <> hash_password(p_current_pwd) THEN
            p_http_status := 400; p_result := json_error('Current password is incorrect.'); RETURN;
        END IF;
        IF LENGTH(p_new_pwd) < 6 THEN
            p_http_status := 400; p_result := json_error('New password must be at least 6 characters.'); RETURN;
        END IF;
        UPDATE wl_users SET password_hash = hash_password(p_new_pwd),
                            updated_at    = SYSTIMESTAMP
        WHERE  id = v_uid;
        COMMIT;
        p_http_status := 200;
        p_result := json_success('"password_updated"');
    END change_password;

    -- ──────────────────────────────────────────────────────────
    -- SESSIONS list
    -- ──────────────────────────────────────────────────────────
    FUNCTION get_sessions(p_session_id IN VARCHAR2) RETURN CLOB IS
        v_sess  VARCHAR2(32767);
        v_role  VARCHAR2(20);
        v_json  CLOB := '[';
        v_first BOOLEAN := TRUE;
        v_comma VARCHAR2(1) := '';
    BEGIN
        v_sess := validate_session(p_session_id);
        IF v_sess IS NULL THEN RETURN json_error('Invalid session.', 401); END IF;
        APEX_JSON.PARSE(v_sess);
        v_role := APEX_JSON.GET_VARCHAR2('role');
        IF v_role NOT IN ('admin','superadmin') THEN
            RETURN json_error('Insufficient permissions.', 403);
        END IF;
        FOR r IN (SELECT s.id, s.username, s.role, s.ip_address,
                         TO_CHAR(s.login_time,'YYYY-MM-DD"T"HH24:MI:SS"Z"') lt,
                         TO_CHAR(s.logout_time,'YYYY-MM-DD"T"HH24:MI:SS"Z"') lot,
                         s.active
                  FROM   wl_sessions s ORDER BY s.login_time DESC) LOOP
            v_json := v_json || v_comma
                   || '{"id":'       || APEX_JSON.STRINGIFY(r.id)         || ','
                   || '"username":'  || APEX_JSON.STRINGIFY(r.username)   || ','
                   || '"role":'      || APEX_JSON.STRINGIFY(r.role)       || ','
                   || '"ipAddress":' || APEX_JSON.STRINGIFY(r.ip_address) || ','
                   || '"loginTime":' || APEX_JSON.STRINGIFY(r.lt)         || ','
                   || '"logoutTime":'|| APEX_JSON.STRINGIFY(r.lot)        || ','
                   || '"active":'    || CASE r.active WHEN 1 THEN 'true' ELSE 'false' END
                   || '}';
            v_comma := ',';
        END LOOP;
        RETURN json_success(v_json || ']');
    END get_sessions;

    -- ──────────────────────────────────────────────────────────
    -- HISTORY helpers
    -- ──────────────────────────────────────────────────────────
    FUNCTION hist_row_json(p_id       VARCHAR2, p_username VARCHAR2,
                            p_role     VARCHAR2, p_login    VARCHAR2,
                            p_logout   VARCHAR2, p_ip       VARCHAR2,
                            p_status   VARCHAR2, p_user_id  VARCHAR2)
    RETURN VARCHAR2 IS
    BEGIN
        RETURN '{"id":'       || APEX_JSON.STRINGIFY(p_id)       || ','
            || '"username":'  || APEX_JSON.STRINGIFY(p_username) || ','
            || '"role":'      || APEX_JSON.STRINGIFY(p_role)     || ','
            || '"loginTime":' || APEX_JSON.STRINGIFY(p_login)    || ','
            || '"logoutTime":'|| APEX_JSON.STRINGIFY(p_logout)   || ','
            || '"ipAddress":' || APEX_JSON.STRINGIFY(p_ip)       || ','
            || '"status":'    || APEX_JSON.STRINGIFY(p_status)   || ','
            || '"userId":'    || APEX_JSON.STRINGIFY(p_user_id)  || '}';
    END hist_row_json;

    FUNCTION get_history(p_session_id    IN VARCHAR2,
                         p_user_filter   IN VARCHAR2 DEFAULT NULL,
                         p_from_date     IN VARCHAR2 DEFAULT NULL,
                         p_to_date       IN VARCHAR2 DEFAULT NULL,
                         p_status_filter IN VARCHAR2 DEFAULT NULL) RETURN CLOB IS
        v_sess  VARCHAR2(32767);
        v_role  VARCHAR2(20);
        v_json  CLOB := '[';
        v_comma VARCHAR2(1) := '';
    BEGIN
        v_sess := validate_session(p_session_id);
        IF v_sess IS NULL THEN RETURN json_error('Invalid session.', 401); END IF;
        APEX_JSON.PARSE(v_sess);
        v_role := APEX_JSON.GET_VARCHAR2('role');
        IF v_role NOT IN ('admin','superadmin') THEN
            RETURN json_error('Insufficient permissions.', 403);
        END IF;
        FOR r IN (SELECT h.id, h.username, h.role, h.user_id,
                         TO_CHAR(h.login_time,'YYYY-MM-DD"T"HH24:MI:SS"Z"')  lt,
                         TO_CHAR(h.logout_time,'YYYY-MM-DD"T"HH24:MI:SS"Z"') lot,
                         h.ip_address, h.status
                  FROM   wl_login_history h
                  WHERE  (p_user_filter   IS NULL OR h.user_id = p_user_filter)
                  AND    (p_status_filter IS NULL OR h.status  = p_status_filter)
                  AND    (p_from_date     IS NULL OR
                          h.login_time >= TO_TIMESTAMP_TZ(p_from_date,'YYYY-MM-DD'))
                  AND    (p_to_date       IS NULL OR
                          h.login_time <  TO_TIMESTAMP_TZ(p_to_date,'YYYY-MM-DD') + 1)
                  ORDER  BY h.login_time DESC) LOOP
            v_json := v_json || v_comma
                   || hist_row_json(r.id, r.username, r.role,
                                    r.lt, r.lot, r.ip_address, r.status, r.user_id);
            v_comma := ',';
        END LOOP;
        RETURN json_success(v_json || ']');
    END get_history;

    FUNCTION get_my_history(p_session_id IN VARCHAR2) RETURN CLOB IS
        v_sess  VARCHAR2(32767);
        v_uid   VARCHAR2(40);
        v_json  CLOB := '[';
        v_comma VARCHAR2(1) := '';
    BEGIN
        v_sess := validate_session(p_session_id);
        IF v_sess IS NULL THEN RETURN json_error('Invalid session.', 401); END IF;
        APEX_JSON.PARSE(v_sess);
        v_uid := APEX_JSON.GET_VARCHAR2('userId');
        FOR r IN (SELECT h.id, h.username, h.role, h.user_id,
                         TO_CHAR(h.login_time,'YYYY-MM-DD"T"HH24:MI:SS"Z"')  lt,
                         TO_CHAR(h.logout_time,'YYYY-MM-DD"T"HH24:MI:SS"Z"') lot,
                         h.ip_address, h.status
                  FROM   wl_login_history h
                  WHERE  h.user_id = v_uid
                  ORDER  BY h.login_time DESC) LOOP
            v_json := v_json || v_comma
                   || hist_row_json(r.id, r.username, r.role,
                                    r.lt, r.lot, r.ip_address, r.status, r.user_id);
            v_comma := ',';
        END LOOP;
        RETURN json_success(v_json || ']');
    END get_my_history;

    -- ──────────────────────────────────────────────────────────
    -- CHECKINS
    -- ──────────────────────────────────────────────────────────
    FUNCTION checkin_row_json(p_id VARCHAR2, p_user_id VARCHAR2,
                               p_username VARCHAR2, p_ci VARCHAR2,
                               p_co VARCHAR2, p_dur NUMBER) RETURN VARCHAR2 IS
    BEGIN
        RETURN '{"id":'           || APEX_JSON.STRINGIFY(p_id)       || ','
            || '"userId":'        || APEX_JSON.STRINGIFY(p_user_id)  || ','
            || '"username":'      || APEX_JSON.STRINGIFY(p_username) || ','
            || '"checkinTime":'   || APEX_JSON.STRINGIFY(p_ci)       || ','
            || '"checkoutTime":'  || APEX_JSON.STRINGIFY(p_co)       || ','
            || '"duration":'      || NVL(TO_CHAR(p_dur),'null')
            || '}';
    END checkin_row_json;

    PROCEDURE do_checkin(p_session_id  IN  VARCHAR2,
                         p_result      OUT CLOB,
                         p_http_status OUT NUMBER) IS
        v_sess  VARCHAR2(32767);
        v_uid   VARCHAR2(40);
        v_uname VARCHAR2(100);
        v_cnt   NUMBER;
        v_id    VARCHAR2(40);
    BEGIN
        v_sess := validate_session(p_session_id);
        IF v_sess IS NULL THEN p_http_status:=401; p_result:=json_error('Invalid session.'); RETURN; END IF;
        APEX_JSON.PARSE(v_sess);
        v_uid   := APEX_JSON.GET_VARCHAR2('userId');
        v_uname := APEX_JSON.GET_VARCHAR2('username');
        SELECT COUNT(*) INTO v_cnt FROM wl_checkins
        WHERE  user_id = v_uid AND checkout_time IS NULL;
        IF v_cnt > 0 THEN
            p_http_status := 409; p_result := json_error('Already checked in.'); RETURN;
        END IF;
        v_id := generate_id();
        INSERT INTO wl_checkins (id, user_id, username, checkin_time)
        VALUES (v_id, v_uid, v_uname, SYSTIMESTAMP);
        COMMIT;
        p_http_status := 201;
        p_result := json_success('{"id":"'||v_id||'"}');
    END do_checkin;

    PROCEDURE do_checkout(p_session_id  IN  VARCHAR2,
                          p_checkin_id  IN  VARCHAR2,
                          p_result      OUT CLOB,
                          p_http_status OUT NUMBER) IS
        v_sess   VARCHAR2(32767);
        v_uid    VARCHAR2(40);
        v_ci_row wl_checkins%ROWTYPE;
        v_dur    NUMBER;
        v_now    TIMESTAMP WITH TIME ZONE := SYSTIMESTAMP;
    BEGIN
        v_sess := validate_session(p_session_id);
        IF v_sess IS NULL THEN p_http_status:=401; p_result:=json_error('Invalid session.'); RETURN; END IF;
        APEX_JSON.PARSE(v_sess);
        v_uid := APEX_JSON.GET_VARCHAR2('userId');
        BEGIN
            SELECT * INTO v_ci_row FROM wl_checkins
            WHERE  id = p_checkin_id AND user_id = v_uid AND checkout_time IS NULL;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                p_http_status:=404; p_result:=json_error('Active check-in not found.'); RETURN;
        END;
        v_dur := ROUND((EXTRACT(DAY  FROM(v_now - v_ci_row.checkin_time))*1440
                       +EXTRACT(HOUR FROM(v_now - v_ci_row.checkin_time))*60
                       +EXTRACT(MINUTE FROM(v_now - v_ci_row.checkin_time))));
        UPDATE wl_checkins SET checkout_time = v_now, duration_mins = v_dur,
                               updated_at    = v_now
        WHERE  id = p_checkin_id;
        COMMIT;
        p_http_status := 200;
        p_result := json_success('{"durationMins":'||v_dur||'}');
    END do_checkout;

    FUNCTION get_checkins(p_session_id IN VARCHAR2) RETURN CLOB IS
        v_sess  VARCHAR2(32767);
        v_role  VARCHAR2(20);
        v_json  CLOB := '[';
        v_comma VARCHAR2(1) := '';
    BEGIN
        v_sess := validate_session(p_session_id);
        IF v_sess IS NULL THEN RETURN json_error('Invalid session.', 401); END IF;
        APEX_JSON.PARSE(v_sess);
        v_role := APEX_JSON.GET_VARCHAR2('role');
        IF v_role NOT IN ('admin','superadmin') THEN
            RETURN json_error('Insufficient permissions.', 403);
        END IF;
        FOR r IN (SELECT c.id, c.user_id, c.username, c.duration_mins,
                         TO_CHAR(c.checkin_time,'YYYY-MM-DD"T"HH24:MI:SS"Z"')  ci,
                         TO_CHAR(c.checkout_time,'YYYY-MM-DD"T"HH24:MI:SS"Z"') co
                  FROM   wl_checkins c ORDER BY c.checkin_time DESC) LOOP
            v_json := v_json || v_comma
                   || checkin_row_json(r.id,r.user_id,r.username,r.ci,r.co,r.duration_mins);
            v_comma := ',';
        END LOOP;
        RETURN json_success(v_json || ']');
    END get_checkins;

    FUNCTION get_my_checkins(p_session_id IN VARCHAR2) RETURN CLOB IS
        v_sess  VARCHAR2(32767);
        v_uid   VARCHAR2(40);
        v_json  CLOB := '[';
        v_comma VARCHAR2(1) := '';
    BEGIN
        v_sess := validate_session(p_session_id);
        IF v_sess IS NULL THEN RETURN json_error('Invalid session.', 401); END IF;
        APEX_JSON.PARSE(v_sess);
        v_uid := APEX_JSON.GET_VARCHAR2('userId');
        FOR r IN (SELECT c.id, c.user_id, c.username, c.duration_mins,
                         TO_CHAR(c.checkin_time,'YYYY-MM-DD"T"HH24:MI:SS"Z"')  ci,
                         TO_CHAR(c.checkout_time,'YYYY-MM-DD"T"HH24:MI:SS"Z"') co
                  FROM   wl_checkins c
                  WHERE  c.user_id = v_uid
                  ORDER  BY c.checkin_time DESC) LOOP
            v_json := v_json || v_comma
                   || checkin_row_json(r.id,r.user_id,r.username,r.ci,r.co,r.duration_mins);
            v_comma := ',';
        END LOOP;
        RETURN json_success(v_json || ']');
    END get_my_checkins;

    -- ──────────────────────────────────────────────────────────
    -- LOOKUP / SETTINGS
    -- ──────────────────────────────────────────────────────────
    FUNCTION get_all_settings(p_session_id IN VARCHAR2) RETURN CLOB IS
        v_sess  VARCHAR2(32767);
        v_role  VARCHAR2(20);
        v_json  CLOB := '{';
        v_comma VARCHAR2(1) := '';
    BEGIN
        v_sess := validate_session(p_session_id);
        IF v_sess IS NULL THEN RETURN json_error('Invalid session.', 401); END IF;
        APEX_JSON.PARSE(v_sess);
        v_role := APEX_JSON.GET_VARCHAR2('role');
        IF v_role NOT IN ('admin','superadmin') THEN
            RETURN json_error('Insufficient permissions.', 403);
        END IF;
        FOR r IN (SELECT setting_key, setting_value FROM wl_lookup ORDER BY setting_key) LOOP
            v_json := v_json || v_comma
                   || APEX_JSON.STRINGIFY(r.setting_key) || ':'
                   || APEX_JSON.STRINGIFY(SUBSTR(r.setting_value,1,4000));
            v_comma := ',';
        END LOOP;
        RETURN json_success(v_json || '}');
    END get_all_settings;

    PROCEDURE save_settings(p_session_id    IN  VARCHAR2,
                             p_settings_json IN  CLOB,
                             p_result        OUT CLOB,
                             p_http_status   OUT NUMBER) IS
        v_sess   VARCHAR2(32767);
        v_role   VARCHAR2(20);
        v_uname  VARCHAR2(100);
        v_keys   APEX_JSON.T_VALUES;
    BEGIN
        v_sess := validate_session(p_session_id);
        IF v_sess IS NULL THEN p_http_status:=401; p_result:=json_error('Invalid session.'); RETURN; END IF;
        APEX_JSON.PARSE(v_sess);
        v_role  := APEX_JSON.GET_VARCHAR2('role');
        v_uname := APEX_JSON.GET_VARCHAR2('username');
        IF v_role NOT IN ('admin','superadmin') THEN
            p_http_status:=403; p_result:=json_error('Insufficient permissions.'); RETURN;
        END IF;
        APEX_JSON.PARSE(v_keys, p_settings_json);
        FOR r IN (SELECT setting_key FROM wl_lookup ORDER BY setting_key) LOOP
            DECLARE
                v_val VARCHAR2(4000);
            BEGIN
                v_val := APEX_JSON.GET_VARCHAR2(v_keys, r.setting_key);
                IF v_val IS NOT NULL THEN
                    set_setting(r.setting_key, v_val, v_uname);
                END IF;
            EXCEPTION
                WHEN OTHERS THEN NULL;
            END;
        END LOOP;
        p_http_status := 200;
        p_result := json_success('"saved"');
    END save_settings;

    -- ──────────────────────────────────────────────────────────
    -- BULK IMPORT
    -- ──────────────────────────────────────────────────────────
    PROCEDURE bulk_import(p_session_id  IN  VARCHAR2,
                          p_users_json  IN  CLOB,
                          p_result      OUT CLOB,
                          p_http_status OUT NUMBER) IS
        v_sess   VARCHAR2(32767);
        v_role   VARCHAR2(20);
        v_uname  VARCHAR2(100);
        v_cnt    NUMBER := 0;
        v_errs   CLOB   := '[]';
        v_n      NUMBER;
        v_uname2 VARCHAR2(100);
        v_email  VARCHAR2(200);
        v_pass   VARCHAR2(200);
        v_lname  VARCHAR2(200);
        v_cont   VARCHAR2(300);
        v_id     VARCHAR2(40);
        v_dup    NUMBER;
        v_errs_arr APEX_JSON.T_VALUES;
    BEGIN
        v_sess := validate_session(p_session_id);
        IF v_sess IS NULL THEN p_http_status:=401; p_result:=json_error('Invalid session.'); RETURN; END IF;
        APEX_JSON.PARSE(v_sess);
        v_role  := APEX_JSON.GET_VARCHAR2('role');
        v_uname := APEX_JSON.GET_VARCHAR2('username');
        IF v_role <> 'superadmin' THEN
            p_http_status:=403; p_result:=json_error('Only superadmin can bulk import.'); RETURN;
        END IF;
        -- p_users_json expected: [{"username":…,"password":…,"legalName":…,"email":…,"contact":…},…]
        APEX_JSON.PARSE(v_errs_arr, p_users_json);
        v_n := APEX_JSON.GET_COUNT(v_errs_arr, '.');
        DECLARE
            v_errors_out VARCHAR2(32767) := '[';
            v_ec_comma   VARCHAR2(1)     := '';
        BEGIN
            FOR i IN 1..v_n LOOP
                BEGIN
                    v_uname2 := APEX_JSON.GET_VARCHAR2(v_errs_arr, '[%d].username', i);
                    v_pass   := APEX_JSON.GET_VARCHAR2(v_errs_arr, '[%d].password', i);
                    v_lname  := APEX_JSON.GET_VARCHAR2(v_errs_arr, '[%d].legalName', i);
                    v_email  := APEX_JSON.GET_VARCHAR2(v_errs_arr, '[%d].email', i);
                    v_cont   := APEX_JSON.GET_VARCHAR2(v_errs_arr, '[%d].contact', i);
                    IF v_uname2 IS NULL OR v_pass IS NULL THEN
                        v_errors_out := v_errors_out || v_ec_comma
                            || APEX_JSON.STRINGIFY('Row '||i||': username and password required');
                        v_ec_comma := ','; CONTINUE;
                    END IF;
                    SELECT COUNT(*) INTO v_dup FROM wl_users WHERE LOWER(username) = LOWER(v_uname2);
                    IF v_dup > 0 THEN
                        v_errors_out := v_errors_out || v_ec_comma
                            || APEX_JSON.STRINGIFY('Row '||i||': username "'||v_uname2||'" already exists');
                        v_ec_comma := ','; CONTINUE;
                    END IF;
                    v_id := generate_id();
                    INSERT INTO wl_users (id, username, password_hash, role,
                                          legal_name, email, contact_info,
                                          status, created_by)
                    VALUES (v_id, v_uname2, hash_password(v_pass), 'user',
                            v_lname, v_email, v_cont, 'active', v_uname);
                    v_cnt := v_cnt + 1;
                EXCEPTION
                    WHEN OTHERS THEN
                        v_errors_out := v_errors_out || v_ec_comma
                            || APEX_JSON.STRINGIFY('Row '||i||': '||SQLERRM);
                        v_ec_comma := ',';
                END;
            END LOOP;
            COMMIT;
            v_errors_out := v_errors_out || ']';
            p_http_status := 200;
            p_result := json_success('{"imported":'||v_cnt||',"errors":'||v_errors_out||'}');
        END;
    END bulk_import;

END wl_pkg;
/
