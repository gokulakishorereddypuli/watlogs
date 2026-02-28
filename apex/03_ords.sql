-- ================================================================
-- WatLogs – ORDS REST Service Script
-- Schema  : watlogs
-- Execute : as the 'watlogs' schema owner (after 01_ddl + 02_packages)
-- Base URL: https://<apex-host>/ords/watlogs/
-- ================================================================

-- Enable ORDS for the watlogs schema
BEGIN
    ORDS.ENABLE_SCHEMA(
        p_enabled             => TRUE,
        p_schema              => 'WATLOGS',
        p_url_mapping_type    => 'BASE_PATH',
        p_url_mapping_pattern => 'watlogs',
        p_auto_rest_auth      => FALSE
    );
    COMMIT;
END;
/

-- ================================================================
-- Define REST Module
-- ================================================================
BEGIN
    ORDS.DEFINE_MODULE(
        p_module_name    => 'watlogs.api',
        p_base_path      => '/',
        p_items_per_page => 0,
        p_status         => 'PUBLISHED',
        p_comments       => 'WatLogs REST API'
    );
    COMMIT;
END;
/

-- ================================================================
-- Helper: session ID is always read from the X-Session-Id header
-- In every handler below we bind it via :session_id (ORDS header bind)
-- ================================================================

-- ================================================================
-- AUTH endpoints
-- ================================================================

-- ── POST /auth/login ─────────────────────────────────────────
BEGIN
    ORDS.DEFINE_TEMPLATE(p_module_name => 'watlogs.api', p_pattern => 'auth/login');
    ORDS.DEFINE_HANDLER(
        p_module_name   => 'watlogs.api',
        p_pattern       => 'auth/login',
        p_method        => 'POST',
        p_source_type   => ORDS.SOURCE_TYPE_PLSQL,
        p_mimes_allowed => 'application/json',
        p_comments      => 'Authenticate user',
        p_source        => q'[
DECLARE
  v_result      CLOB;
  v_status      NUMBER;
  v_username    VARCHAR2(100);
  v_password    VARCHAR2(500);
  v_role        VARCHAR2(20);
  v_ip          VARCHAR2(50);
  v_cap_token   VARCHAR2(100);
  v_cap_answer  VARCHAR2(100);
BEGIN
  APEX_JSON.PARSE(:body_text);
  v_username   := APEX_JSON.GET_VARCHAR2('username');
  v_password   := APEX_JSON.GET_VARCHAR2('password');
  v_role       := APEX_JSON.GET_VARCHAR2('role');
  v_cap_token  := APEX_JSON.GET_VARCHAR2('captchaToken');
  v_cap_answer := APEX_JSON.GET_VARCHAR2('captchaAnswer');
  v_ip := COALESCE(
    OWA_UTIL.GET_CGI_ENV('X-Forwarded-For'),
    OWA_UTIL.GET_CGI_ENV('REMOTE_ADDR'),
    '127.0.0.1'
  );
  wl_pkg.do_login(v_username, v_password, v_role, v_ip,
                  v_cap_token, v_cap_answer, v_result, v_status);
  :status := v_status;
  OWA_UTIL.MIME_HEADER('application/json', FALSE);
  OWA_UTIL.HTTP_HEADER_CLOSE;
  HTP.P(v_result);
END;
]'
    );
    COMMIT;
END;
/

-- ── POST /auth/logout ────────────────────────────────────────
BEGIN
    ORDS.DEFINE_TEMPLATE(p_module_name => 'watlogs.api', p_pattern => 'auth/logout');
    ORDS.DEFINE_HANDLER(
        p_module_name   => 'watlogs.api',
        p_pattern       => 'auth/logout',
        p_method        => 'POST',
        p_source_type   => ORDS.SOURCE_TYPE_PLSQL,
        p_mimes_allowed => 'application/json',
        p_comments      => 'Logout user session',
        p_source        => q'[
DECLARE
  v_result   CLOB;
  v_status   NUMBER;
  v_sess_id  VARCHAR2(40);
BEGIN
  APEX_JSON.PARSE(:body_text);
  v_sess_id := APEX_JSON.GET_VARCHAR2('sessionId');
  wl_pkg.do_logout(v_sess_id, v_result, v_status);
  :status := v_status;
  OWA_UTIL.MIME_HEADER('application/json', FALSE);
  OWA_UTIL.HTTP_HEADER_CLOSE;
  HTP.P(v_result);
END;
]'
    );
    COMMIT;
END;
/

-- ── POST /auth/signup ────────────────────────────────────────
BEGIN
    ORDS.DEFINE_TEMPLATE(p_module_name => 'watlogs.api', p_pattern => 'auth/signup');
    ORDS.DEFINE_HANDLER(
        p_module_name   => 'watlogs.api',
        p_pattern       => 'auth/signup',
        p_method        => 'POST',
        p_source_type   => ORDS.SOURCE_TYPE_PLSQL,
        p_mimes_allowed => 'application/json',
        p_comments      => 'Register new user account',
        p_source        => q'[
DECLARE
  v_result     CLOB;
  v_status     NUMBER;
BEGIN
  APEX_JSON.PARSE(:body_text);
  wl_pkg.do_signup(
    APEX_JSON.GET_VARCHAR2('username'),
    APEX_JSON.GET_VARCHAR2('password'),
    APEX_JSON.GET_VARCHAR2('legalName'),
    APEX_JSON.GET_VARCHAR2('email'),
    APEX_JSON.GET_VARCHAR2('contact'),
    APEX_JSON.GET_VARCHAR2('captchaToken'),
    APEX_JSON.GET_VARCHAR2('captchaAnswer'),
    v_result, v_status
  );
  :status := v_status;
  OWA_UTIL.MIME_HEADER('application/json', FALSE);
  OWA_UTIL.HTTP_HEADER_CLOSE;
  HTP.P(v_result);
END;
]'
    );
    COMMIT;
END;
/

-- ── GET /auth/me ─────────────────────────────────────────────
BEGIN
    ORDS.DEFINE_TEMPLATE(p_module_name => 'watlogs.api', p_pattern => 'auth/me');
    ORDS.DEFINE_HANDLER(
        p_module_name   => 'watlogs.api',
        p_pattern       => 'auth/me',
        p_method        => 'GET',
        p_source_type   => ORDS.SOURCE_TYPE_PLSQL,
        p_comments      => 'Get current authenticated user',
        p_source        => q'[
DECLARE
  v_sid VARCHAR2(40) := OWA_UTIL.GET_CGI_ENV('X-Session-Id');
BEGIN
  OWA_UTIL.MIME_HEADER('application/json', FALSE);
  OWA_UTIL.HTTP_HEADER_CLOSE;
  HTP.P(wl_pkg.get_current_user(v_sid));
END;
]'
    );
    COMMIT;
END;
/

-- ── GET /captcha ─────────────────────────────────────────────
BEGIN
    ORDS.DEFINE_TEMPLATE(p_module_name => 'watlogs.api', p_pattern => 'captcha');
    ORDS.DEFINE_HANDLER(
        p_module_name   => 'watlogs.api',
        p_pattern       => 'captcha',
        p_method        => 'GET',
        p_source_type   => ORDS.SOURCE_TYPE_PLSQL,
        p_comments      => 'Generate new captcha challenge',
        p_source        => q'[
DECLARE
  v_token    VARCHAR2(100);
  v_question VARCHAR2(100);
BEGIN
  wl_pkg.generate_captcha(v_token, v_question);
  OWA_UTIL.MIME_HEADER('application/json', FALSE);
  OWA_UTIL.HTTP_HEADER_CLOSE;
  HTP.P('{"ok":true,"data":{"token":'
        || APEX_JSON.STRINGIFY(v_token)    || ',"question":'
        || APEX_JSON.STRINGIFY(v_question) || '}}');
END;
]'
    );
    COMMIT;
END;
/

-- ================================================================
-- USERS endpoints
-- ================================================================

-- ── GET  /users ──────────────────────────────────────────────
BEGIN
    ORDS.DEFINE_TEMPLATE(p_module_name => 'watlogs.api', p_pattern => 'users');
    ORDS.DEFINE_HANDLER(
        p_module_name   => 'watlogs.api',
        p_pattern       => 'users',
        p_method        => 'GET',
        p_source_type   => ORDS.SOURCE_TYPE_PLSQL,
        p_comments      => 'List users',
        p_source        => q'[
DECLARE
  v_sid    VARCHAR2(40) := OWA_UTIL.GET_CGI_ENV('X-Session-Id');
  v_status VARCHAR2(20) := :status_filter;
BEGIN
  OWA_UTIL.MIME_HEADER('application/json', FALSE);
  OWA_UTIL.HTTP_HEADER_CLOSE;
  HTP.P(wl_pkg.get_users(v_sid, v_status));
END;
]'
    );
    COMMIT;
END;
/

-- ── POST /users  (create user / admin) ──────────────────────
BEGIN
    ORDS.DEFINE_HANDLER(
        p_module_name   => 'watlogs.api',
        p_pattern       => 'users',
        p_method        => 'POST',
        p_source_type   => ORDS.SOURCE_TYPE_PLSQL,
        p_mimes_allowed => 'application/json',
        p_comments      => 'Create user (admin-initiated)',
        p_source        => q'[
DECLARE
  v_result CLOB;
  v_status NUMBER;
  v_sid    VARCHAR2(40) := OWA_UTIL.GET_CGI_ENV('X-Session-Id');
BEGIN
  APEX_JSON.PARSE(:body_text);
  wl_pkg.create_user(
    v_sid,
    APEX_JSON.GET_VARCHAR2('username'),
    APEX_JSON.GET_VARCHAR2('password'),
    APEX_JSON.GET_VARCHAR2('legalName'),
    APEX_JSON.GET_VARCHAR2('email'),
    APEX_JSON.GET_VARCHAR2('contact'),
    APEX_JSON.GET_VARCHAR2('role'),
    v_result, v_status
  );
  :status := v_status;
  OWA_UTIL.MIME_HEADER('application/json', FALSE);
  OWA_UTIL.HTTP_HEADER_CLOSE;
  HTP.P(v_result);
END;
]'
    );
    COMMIT;
END;
/

-- ── GET  /users/:id ──────────────────────────────────────────
BEGIN
    ORDS.DEFINE_TEMPLATE(p_module_name => 'watlogs.api', p_pattern => 'users/:id');
    ORDS.DEFINE_HANDLER(
        p_module_name   => 'watlogs.api',
        p_pattern       => 'users/:id',
        p_method        => 'GET',
        p_source_type   => ORDS.SOURCE_TYPE_PLSQL,
        p_comments      => 'Get user by ID',
        p_source        => q'[
DECLARE
  v_sid VARCHAR2(40) := OWA_UTIL.GET_CGI_ENV('X-Session-Id');
BEGIN
  OWA_UTIL.MIME_HEADER('application/json', FALSE);
  OWA_UTIL.HTTP_HEADER_CLOSE;
  HTP.P(wl_pkg.get_user(v_sid, :id));
END;
]'
    );
    COMMIT;
END;
/

-- ── PUT  /users/:id  (update profile) ───────────────────────
BEGIN
    ORDS.DEFINE_HANDLER(
        p_module_name   => 'watlogs.api',
        p_pattern       => 'users/:id',
        p_method        => 'PUT',
        p_source_type   => ORDS.SOURCE_TYPE_PLSQL,
        p_mimes_allowed => 'application/json',
        p_comments      => 'Update user profile',
        p_source        => q'[
DECLARE
  v_result CLOB;
  v_status NUMBER;
  v_sid    VARCHAR2(40) := OWA_UTIL.GET_CGI_ENV('X-Session-Id');
BEGIN
  APEX_JSON.PARSE(:body_text);
  wl_pkg.update_user(
    v_sid, :id,
    APEX_JSON.GET_VARCHAR2('legalName'),
    APEX_JSON.GET_VARCHAR2('email'),
    APEX_JSON.GET_VARCHAR2('contact'),
    v_result, v_status
  );
  :status := v_status;
  OWA_UTIL.MIME_HEADER('application/json', FALSE);
  OWA_UTIL.HTTP_HEADER_CLOSE;
  HTP.P(v_result);
END;
]'
    );
    COMMIT;
END;
/

-- ── PUT  /users/:id/status ───────────────────────────────────
BEGIN
    ORDS.DEFINE_TEMPLATE(p_module_name => 'watlogs.api', p_pattern => 'users/:id/status');
    ORDS.DEFINE_HANDLER(
        p_module_name   => 'watlogs.api',
        p_pattern       => 'users/:id/status',
        p_method        => 'PUT',
        p_source_type   => ORDS.SOURCE_TYPE_PLSQL,
        p_mimes_allowed => 'application/json',
        p_comments      => 'Freeze or activate user',
        p_source        => q'[
DECLARE
  v_result CLOB;
  v_status NUMBER;
  v_sid    VARCHAR2(40) := OWA_UTIL.GET_CGI_ENV('X-Session-Id');
BEGIN
  APEX_JSON.PARSE(:body_text);
  wl_pkg.update_user_status(
    v_sid, :id,
    APEX_JSON.GET_VARCHAR2('status'),
    v_result, v_status
  );
  :status := v_status;
  OWA_UTIL.MIME_HEADER('application/json', FALSE);
  OWA_UTIL.HTTP_HEADER_CLOSE;
  HTP.P(v_result);
END;
]'
    );
    COMMIT;
END;
/

-- ── PUT  /users/:id/approve ──────────────────────────────────
BEGIN
    ORDS.DEFINE_TEMPLATE(p_module_name => 'watlogs.api', p_pattern => 'users/:id/approve');
    ORDS.DEFINE_HANDLER(
        p_module_name   => 'watlogs.api',
        p_pattern       => 'users/:id/approve',
        p_method        => 'PUT',
        p_source_type   => ORDS.SOURCE_TYPE_PLSQL,
        p_mimes_allowed => 'application/json',
        p_comments      => 'Approve pending user account',
        p_source        => q'[
DECLARE
  v_result CLOB;
  v_status NUMBER;
  v_sid    VARCHAR2(40) := OWA_UTIL.GET_CGI_ENV('X-Session-Id');
BEGIN
  wl_pkg.approve_user(v_sid, :id, v_result, v_status);
  :status := v_status;
  OWA_UTIL.MIME_HEADER('application/json', FALSE);
  OWA_UTIL.HTTP_HEADER_CLOSE;
  HTP.P(v_result);
END;
]'
    );
    COMMIT;
END;
/

-- ── PUT  /users/:id/password ─────────────────────────────────
BEGIN
    ORDS.DEFINE_TEMPLATE(p_module_name => 'watlogs.api', p_pattern => 'users/:id/password');
    ORDS.DEFINE_HANDLER(
        p_module_name   => 'watlogs.api',
        p_pattern       => 'users/:id/password',
        p_method        => 'PUT',
        p_source_type   => ORDS.SOURCE_TYPE_PLSQL,
        p_mimes_allowed => 'application/json',
        p_comments      => 'Change user password',
        p_source        => q'[
DECLARE
  v_result CLOB;
  v_status NUMBER;
  v_sid    VARCHAR2(40) := OWA_UTIL.GET_CGI_ENV('X-Session-Id');
BEGIN
  APEX_JSON.PARSE(:body_text);
  wl_pkg.change_password(
    v_sid,
    APEX_JSON.GET_VARCHAR2('currentPassword'),
    APEX_JSON.GET_VARCHAR2('newPassword'),
    v_result, v_status
  );
  :status := v_status;
  OWA_UTIL.MIME_HEADER('application/json', FALSE);
  OWA_UTIL.HTTP_HEADER_CLOSE;
  HTP.P(v_result);
END;
]'
    );
    COMMIT;
END;
/

-- ================================================================
-- SESSIONS endpoint
-- ================================================================
BEGIN
    ORDS.DEFINE_TEMPLATE(p_module_name => 'watlogs.api', p_pattern => 'sessions');
    ORDS.DEFINE_HANDLER(
        p_module_name   => 'watlogs.api',
        p_pattern       => 'sessions',
        p_method        => 'GET',
        p_source_type   => ORDS.SOURCE_TYPE_PLSQL,
        p_comments      => 'List sessions (admin)',
        p_source        => q'[
DECLARE
  v_sid VARCHAR2(40) := OWA_UTIL.GET_CGI_ENV('X-Session-Id');
BEGIN
  OWA_UTIL.MIME_HEADER('application/json', FALSE);
  OWA_UTIL.HTTP_HEADER_CLOSE;
  HTP.P(wl_pkg.get_sessions(v_sid));
END;
]'
    );
    COMMIT;
END;
/

-- ================================================================
-- HISTORY endpoints
-- ================================================================
BEGIN
    ORDS.DEFINE_TEMPLATE(p_module_name => 'watlogs.api', p_pattern => 'history');
    ORDS.DEFINE_HANDLER(
        p_module_name   => 'watlogs.api',
        p_pattern       => 'history',
        p_method        => 'GET',
        p_source_type   => ORDS.SOURCE_TYPE_PLSQL,
        p_comments      => 'Login history (admin)',
        p_source        => q'[
DECLARE
  v_sid VARCHAR2(40) := OWA_UTIL.GET_CGI_ENV('X-Session-Id');
BEGIN
  OWA_UTIL.MIME_HEADER('application/json', FALSE);
  OWA_UTIL.HTTP_HEADER_CLOSE;
  HTP.P(wl_pkg.get_history(v_sid, :user_id, :from_date, :to_date, :status));
END;
]'
    );
    COMMIT;
END;
/

BEGIN
    ORDS.DEFINE_TEMPLATE(p_module_name => 'watlogs.api', p_pattern => 'history/me');
    ORDS.DEFINE_HANDLER(
        p_module_name   => 'watlogs.api',
        p_pattern       => 'history/me',
        p_method        => 'GET',
        p_source_type   => ORDS.SOURCE_TYPE_PLSQL,
        p_comments      => 'My login history',
        p_source        => q'[
DECLARE
  v_sid VARCHAR2(40) := OWA_UTIL.GET_CGI_ENV('X-Session-Id');
BEGIN
  OWA_UTIL.MIME_HEADER('application/json', FALSE);
  OWA_UTIL.HTTP_HEADER_CLOSE;
  HTP.P(wl_pkg.get_my_history(v_sid));
END;
]'
    );
    COMMIT;
END;
/

-- ================================================================
-- CHECKINS endpoints
-- ================================================================
BEGIN
    ORDS.DEFINE_TEMPLATE(p_module_name => 'watlogs.api', p_pattern => 'checkins');
    ORDS.DEFINE_HANDLER(
        p_module_name   => 'watlogs.api',
        p_pattern       => 'checkins',
        p_method        => 'GET',
        p_source_type   => ORDS.SOURCE_TYPE_PLSQL,
        p_comments      => 'List all check-ins (admin)',
        p_source        => q'[
DECLARE
  v_sid VARCHAR2(40) := OWA_UTIL.GET_CGI_ENV('X-Session-Id');
BEGIN
  OWA_UTIL.MIME_HEADER('application/json', FALSE);
  OWA_UTIL.HTTP_HEADER_CLOSE;
  HTP.P(wl_pkg.get_checkins(v_sid));
END;
]'
    );
    COMMIT;
END;
/

BEGIN
    ORDS.DEFINE_HANDLER(
        p_module_name   => 'watlogs.api',
        p_pattern       => 'checkins',
        p_method        => 'POST',
        p_source_type   => ORDS.SOURCE_TYPE_PLSQL,
        p_mimes_allowed => 'application/json',
        p_comments      => 'Check in',
        p_source        => q'[
DECLARE
  v_result CLOB;
  v_status NUMBER;
  v_sid    VARCHAR2(40) := OWA_UTIL.GET_CGI_ENV('X-Session-Id');
BEGIN
  wl_pkg.do_checkin(v_sid, v_result, v_status);
  :status := v_status;
  OWA_UTIL.MIME_HEADER('application/json', FALSE);
  OWA_UTIL.HTTP_HEADER_CLOSE;
  HTP.P(v_result);
END;
]'
    );
    COMMIT;
END;
/

BEGIN
    ORDS.DEFINE_TEMPLATE(p_module_name => 'watlogs.api', p_pattern => 'checkins/me');
    ORDS.DEFINE_HANDLER(
        p_module_name   => 'watlogs.api',
        p_pattern       => 'checkins/me',
        p_method        => 'GET',
        p_source_type   => ORDS.SOURCE_TYPE_PLSQL,
        p_comments      => 'My check-ins',
        p_source        => q'[
DECLARE
  v_sid VARCHAR2(40) := OWA_UTIL.GET_CGI_ENV('X-Session-Id');
BEGIN
  OWA_UTIL.MIME_HEADER('application/json', FALSE);
  OWA_UTIL.HTTP_HEADER_CLOSE;
  HTP.P(wl_pkg.get_my_checkins(v_sid));
END;
]'
    );
    COMMIT;
END;
/

BEGIN
    ORDS.DEFINE_TEMPLATE(p_module_name => 'watlogs.api', p_pattern => 'checkins/:id');
    ORDS.DEFINE_HANDLER(
        p_module_name   => 'watlogs.api',
        p_pattern       => 'checkins/:id',
        p_method        => 'PUT',
        p_source_type   => ORDS.SOURCE_TYPE_PLSQL,
        p_mimes_allowed => 'application/json',
        p_comments      => 'Check out',
        p_source        => q'[
DECLARE
  v_result CLOB;
  v_status NUMBER;
  v_sid    VARCHAR2(40) := OWA_UTIL.GET_CGI_ENV('X-Session-Id');
BEGIN
  wl_pkg.do_checkout(v_sid, :id, v_result, v_status);
  :status := v_status;
  OWA_UTIL.MIME_HEADER('application/json', FALSE);
  OWA_UTIL.HTTP_HEADER_CLOSE;
  HTP.P(v_result);
END;
]'
    );
    COMMIT;
END;
/

-- ================================================================
-- LOOKUP / SETTINGS endpoints
-- ================================================================
BEGIN
    ORDS.DEFINE_TEMPLATE(p_module_name => 'watlogs.api', p_pattern => 'lookup');
    ORDS.DEFINE_HANDLER(
        p_module_name   => 'watlogs.api',
        p_pattern       => 'lookup',
        p_method        => 'GET',
        p_source_type   => ORDS.SOURCE_TYPE_PLSQL,
        p_comments      => 'Get all settings',
        p_source        => q'[
DECLARE
  v_sid VARCHAR2(40) := OWA_UTIL.GET_CGI_ENV('X-Session-Id');
BEGIN
  OWA_UTIL.MIME_HEADER('application/json', FALSE);
  OWA_UTIL.HTTP_HEADER_CLOSE;
  HTP.P(wl_pkg.get_all_settings(v_sid));
END;
]'
    );
    COMMIT;
END;
/

BEGIN
    ORDS.DEFINE_HANDLER(
        p_module_name   => 'watlogs.api',
        p_pattern       => 'lookup',
        p_method        => 'PUT',
        p_source_type   => ORDS.SOURCE_TYPE_PLSQL,
        p_mimes_allowed => 'application/json',
        p_comments      => 'Save settings',
        p_source        => q'[
DECLARE
  v_result CLOB;
  v_status NUMBER;
  v_sid    VARCHAR2(40) := OWA_UTIL.GET_CGI_ENV('X-Session-Id');
BEGIN
  wl_pkg.save_settings(v_sid, :body_text, v_result, v_status);
  :status := v_status;
  OWA_UTIL.MIME_HEADER('application/json', FALSE);
  OWA_UTIL.HTTP_HEADER_CLOSE;
  HTP.P(v_result);
END;
]'
    );
    COMMIT;
END;
/

-- ================================================================
-- BULK IMPORT endpoint
-- ================================================================
BEGIN
    ORDS.DEFINE_TEMPLATE(p_module_name => 'watlogs.api', p_pattern => 'users/bulk');
    ORDS.DEFINE_HANDLER(
        p_module_name   => 'watlogs.api',
        p_pattern       => 'users/bulk',
        p_method        => 'POST',
        p_source_type   => ORDS.SOURCE_TYPE_PLSQL,
        p_mimes_allowed => 'application/json',
        p_comments      => 'Bulk import users (superadmin)',
        p_source        => q'[
DECLARE
  v_result CLOB;
  v_status NUMBER;
  v_sid    VARCHAR2(40) := OWA_UTIL.GET_CGI_ENV('X-Session-Id');
  v_body   CLOB;
BEGIN
  APEX_JSON.PARSE(:body_text);
  v_body := APEX_JSON.GET_CLOB('users');
  wl_pkg.bulk_import(v_sid, v_body, v_result, v_status);
  :status := v_status;
  OWA_UTIL.MIME_HEADER('application/json', FALSE);
  OWA_UTIL.HTTP_HEADER_CLOSE;
  HTP.P(v_result);
END;
]'
    );
    COMMIT;
END;
/

-- ================================================================
-- CORS support: add OPTIONS handler for all templates
-- (uncomment and adjust if your APEX instance needs explicit CORS)
-- ================================================================
-- BEGIN
--     FOR t IN (SELECT template_name FROM user_ords_templates
--               WHERE module_name = 'watlogs.api') LOOP
--         ORDS.DEFINE_HANDLER(
--             p_module_name => 'watlogs.api',
--             p_pattern     => t.template_name,
--             p_method      => 'OPTIONS',
--             p_source_type => ORDS.SOURCE_TYPE_PLSQL,
--             p_source      => q'[
-- BEGIN
--   OWA_UTIL.MIME_HEADER('text/plain', FALSE);
--   HTP.P('Access-Control-Allow-Origin: *');
--   HTP.P('Access-Control-Allow-Methods: GET, POST, PUT, DELETE, OPTIONS');
--   HTP.P('Access-Control-Allow-Headers: Content-Type, X-Session-Id');
--   OWA_UTIL.HTTP_HEADER_CLOSE;
-- END;
-- ]');
--     END LOOP;
--     COMMIT;
-- END;
-- /

COMMIT;
