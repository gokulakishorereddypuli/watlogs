-- ================================================================
-- WatLogs – Oracle APEX DDL Script
-- Schema  : watlogs
-- Execute : as the 'watlogs' schema owner (or DBA granting to it)
-- ================================================================

-- ----------------------------------------------------------------
-- Drop existing objects (safe to re-run)
-- ----------------------------------------------------------------
BEGIN
    FOR r IN (SELECT object_name, object_type
              FROM   user_objects
              WHERE  object_name IN ('WL_CAPTCHA','WL_CHECKINS',
                                     'WL_LOGIN_HISTORY','WL_SESSIONS',
                                     'WL_LOOKUP','WL_USERS','WL_ID_SEQ')
              ORDER  BY CASE object_type
                          WHEN 'TABLE'    THEN 2
                          WHEN 'SEQUENCE' THEN 1
                        END DESC) LOOP
        BEGIN
            IF r.object_type = 'TABLE' THEN
                EXECUTE IMMEDIATE 'DROP TABLE ' || r.object_name || ' CASCADE CONSTRAINTS PURGE';
            ELSIF r.object_type = 'SEQUENCE' THEN
                EXECUTE IMMEDIATE 'DROP SEQUENCE ' || r.object_name;
            END IF;
        EXCEPTION
            WHEN OTHERS THEN NULL;
        END;
    END LOOP;
END;
/

-- ----------------------------------------------------------------
-- Sequence (used to generate numeric suffixes for IDs)
-- ----------------------------------------------------------------
CREATE SEQUENCE wl_id_seq
    START WITH  1000
    INCREMENT BY 1
    NOCACHE
    NOORDER;

-- ================================================================
-- Table: WL_USERS
-- ================================================================
CREATE TABLE wl_users (
    id            VARCHAR2(40)     NOT NULL,
    username      VARCHAR2(100)    NOT NULL,
    password_hash VARCHAR2(128)    NOT NULL,   -- SHA-256 hex (64 chars)
    role          VARCHAR2(20)     DEFAULT 'user'    NOT NULL,
    legal_name    VARCHAR2(200),
    email         VARCHAR2(200),
    contact_info  VARCHAR2(300),
    status        VARCHAR2(20)     DEFAULT 'pending' NOT NULL,
                                               -- active | frozen | pending
    created_by    VARCHAR2(100),
    last_login    TIMESTAMP WITH TIME ZONE,
    last_ip       VARCHAR2(50),
    created_at    TIMESTAMP WITH TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
    updated_at    TIMESTAMP WITH TIME ZONE,
    --
    CONSTRAINT wl_users_pk         PRIMARY KEY (id),
    CONSTRAINT wl_users_uname_uq   UNIQUE (username),
    CONSTRAINT wl_users_email_uq   UNIQUE (email),
    CONSTRAINT wl_users_role_chk   CHECK (role   IN ('user','admin','superadmin')),
    CONSTRAINT wl_users_status_chk CHECK (status IN ('active','frozen','pending'))
);

-- ================================================================
-- Table: WL_SESSIONS
-- ================================================================
CREATE TABLE wl_sessions (
    id          VARCHAR2(40)     NOT NULL,
    user_id     VARCHAR2(40)     NOT NULL,
    username    VARCHAR2(100)    NOT NULL,
    role        VARCHAR2(20)     NOT NULL,
    login_time  TIMESTAMP WITH TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
    logout_time TIMESTAMP WITH TIME ZONE,
    ip_address  VARCHAR2(50),
    active      NUMBER(1)        DEFAULT 1 NOT NULL,
    created_at  TIMESTAMP WITH TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
    --
    CONSTRAINT wl_sessions_pk         PRIMARY KEY (id),
    CONSTRAINT wl_sessions_user_fk    FOREIGN KEY (user_id)
                                      REFERENCES wl_users(id) ON DELETE CASCADE,
    CONSTRAINT wl_sessions_active_chk CHECK (active IN (0,1))
);

-- ================================================================
-- Table: WL_LOGIN_HISTORY
-- ================================================================
CREATE TABLE wl_login_history (
    id          VARCHAR2(40)     NOT NULL,
    user_id     VARCHAR2(40)     NOT NULL,
    username    VARCHAR2(100)    NOT NULL,
    role        VARCHAR2(20),
    login_time  TIMESTAMP WITH TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
    logout_time TIMESTAMP WITH TIME ZONE,
    ip_address  VARCHAR2(50),
    status      VARCHAR2(20)     DEFAULT 'logged_in' NOT NULL,
    session_id  VARCHAR2(40),
    created_at  TIMESTAMP WITH TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
    updated_at  TIMESTAMP WITH TIME ZONE,
    --
    CONSTRAINT wl_hist_pk         PRIMARY KEY (id),
    CONSTRAINT wl_hist_user_fk    FOREIGN KEY (user_id)
                                  REFERENCES wl_users(id) ON DELETE CASCADE,
    CONSTRAINT wl_hist_status_chk CHECK (status IN ('logged_in','logged_out'))
);

-- ================================================================
-- Table: WL_CHECKINS
-- ================================================================
CREATE TABLE wl_checkins (
    id            VARCHAR2(40)  NOT NULL,
    user_id       VARCHAR2(40)  NOT NULL,
    username      VARCHAR2(100) NOT NULL,
    checkin_time  TIMESTAMP WITH TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
    checkout_time TIMESTAMP WITH TIME ZONE,
    duration_mins NUMBER(10),
    created_at    TIMESTAMP WITH TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
    updated_at    TIMESTAMP WITH TIME ZONE,
    --
    CONSTRAINT wl_checkins_pk      PRIMARY KEY (id),
    CONSTRAINT wl_checkins_user_fk FOREIGN KEY (user_id)
                                   REFERENCES wl_users(id) ON DELETE CASCADE
);

-- ================================================================
-- Table: WL_LOOKUP  (key-value system settings)
-- ================================================================
CREATE TABLE wl_lookup (
    setting_key   VARCHAR2(100) NOT NULL,
    setting_value CLOB,
    updated_by    VARCHAR2(100),
    updated_at    TIMESTAMP WITH TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
    --
    CONSTRAINT wl_lookup_pk PRIMARY KEY (setting_key)
);

-- ================================================================
-- Table: WL_CAPTCHA  (server-side captcha tokens)
-- ================================================================
CREATE TABLE wl_captcha (
    token      VARCHAR2(100) NOT NULL,
    answer     VARCHAR2(20)  NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
    expires_at TIMESTAMP WITH TIME ZONE
               DEFAULT (SYSTIMESTAMP + INTERVAL '5' MINUTE) NOT NULL,
    used       NUMBER(1)     DEFAULT 0 NOT NULL,
    --
    CONSTRAINT wl_captcha_pk       PRIMARY KEY (token),
    CONSTRAINT wl_captcha_used_chk CHECK (used IN (0,1))
);

-- ================================================================
-- Indexes
-- ================================================================
CREATE INDEX wl_sessions_user_idx  ON wl_sessions      (user_id, active);
CREATE INDEX wl_hist_user_idx      ON wl_login_history  (user_id, login_time DESC);
CREATE INDEX wl_checkins_user_idx  ON wl_checkins       (user_id, checkin_time DESC);
CREATE INDEX wl_captcha_exp_idx    ON wl_captcha        (expires_at);
CREATE INDEX wl_users_status_idx   ON wl_users          (status);
CREATE INDEX wl_users_role_idx     ON wl_users          (role);

-- ================================================================
-- Default Lookup / Settings
-- ================================================================
INSERT INTO wl_lookup (setting_key, setting_value, updated_by)
    VALUES ('min_login_hours',        '10',                                     'system');
INSERT INTO wl_lookup (setting_key, setting_value, updated_by)
    VALUES ('ip_restriction_enabled', 'false',                                  'system');
INSERT INTO wl_lookup (setting_key, setting_value, updated_by)
    VALUES ('allowed_ips',            '[]',                                     'system');
INSERT INTO wl_lookup (setting_key, setting_value, updated_by)
    VALUES ('app_name',               'WatLogs',                                'system');
INSERT INTO wl_lookup (setting_key, setting_value, updated_by)
    VALUES ('ords_base_url',          'https://your-apex-host/ords/watlogs',    'system');
    -- ^^^ UPDATE this value with your actual APEX ORDS base URL before using the application
INSERT INTO wl_lookup (setting_key, setting_value, updated_by)
    VALUES ('require_approval',       'true',                                   'system');

-- ================================================================
-- Seed: Super Admin user
-- NOTE: password_hash is computed by wl_pkg.hash_password('superadmin')
--       Run AFTER the package in 02_packages.sql has been compiled.
-- ================================================================
INSERT INTO wl_users (id, username, password_hash, role,
                      legal_name, email, status, created_by)
SELECT 'superadmin_root',
       'superadmin',
       wl_pkg.hash_password('superadmin'),
       'superadmin',
       'Super Administrator',
       'superadmin@watlogs.local',
       'active',
       'system'
FROM   DUAL
WHERE  NOT EXISTS (SELECT 1 FROM wl_users WHERE username = 'superadmin');

COMMIT;
