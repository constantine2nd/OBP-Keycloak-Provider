-- ===============================================
-- DATABASE ADMINISTRATOR SETUP REQUIRED
-- ===============================================
-- This SQL must be executed by a database administrator
-- with CREATE privileges on the obp_mapped database.
-- The Keycloak application has READ-ONLY access only.

-- Connect as database administrator (NOT as obp user)
-- Example: sudo -u postgres psql -d obp_mapped

CREATE TABLE if not exists public.authuser (
	id bigserial NOT NULL,
	firstname varchar(100) NULL,
	lastname varchar(100) NULL,
	email varchar(100) NULL,
	username varchar(100) NULL,
	password_pw varchar(48) NULL,
	password_slt varchar(20) NULL,
	provider varchar(100) NULL,
	locale varchar(16) NULL,
	validated bool NULL,
	user_c int8 NULL,
	createdat timestamp NULL,
	updatedat timestamp NULL,
	timezone varchar(32) NULL,
	superuser bool NULL,
	passwordshouldbechanged bool NULL,
	CONSTRAINT authuser_pk PRIMARY KEY (id)
);

-- Create indexes
CREATE INDEX authuser_user_c ON public.authuser USING btree (user_c);
CREATE UNIQUE INDEX authuser_username_provider ON public.authuser USING btree (username, provider);

-- ===============================================
-- OIDC USER SETUP (RECOMMENDED FOR PRODUCTION)
-- ===============================================
-- Create dedicated OIDC user with minimal permissions
CREATE USER oidc_user WITH PASSWORD 'secure_oidc_password';

-- Create view with only OIDC-required fields for enhanced security
CREATE OR REPLACE VIEW public.v_oidc_users AS
SELECT
    id,
    firstname,
    lastname,
    email,
    username,
    password_pw,
    password_slt,
    provider,
    locale,
    validated,
    createdat,
    updatedat,
    timezone
FROM public.authuser
WHERE validated = true;  -- Only show validated users to OIDC

-- Grant permissions to OIDC user
GRANT CONNECT ON DATABASE obp_mapped TO oidc_user;
GRANT USAGE ON SCHEMA public TO oidc_user;
GRANT SELECT ON public.v_oidc_users TO oidc_user;

-- ===============================================
-- LEGACY OBP USER SETUP (FOR BACKWARD COMPATIBILITY)
-- ===============================================
-- Grant READ-ONLY access to legacy Keycloak user
GRANT SELECT ON public.authuser TO obp;
GRANT USAGE ON SEQUENCE authuser_id_seq TO obp;

-- ===============================================
-- CONFIGURATION OPTIONS
-- ===============================================
-- Use DB_AUTHUSER_TABLE environment variable to choose access method:
--
-- Option 1 (RECOMMENDED - Production Security):
--   DB_USER=oidc_user
--   DB_PASSWORD=secure_oidc_password
--   DB_AUTHUSER_TABLE=v_oidc_users
--   Benefits: View-based access, minimal permissions, enhanced security
--
-- Option 2 (Legacy/Development):
--   DB_USER=obp
--   DB_PASSWORD=f
--   DB_AUTHUSER_TABLE=authuser
--   Benefits: Direct table access, backward compatibility

-- ===============================================
-- KEYCLOAK PROVIDER LIMITATIONS
-- ===============================================
-- NOTE: The authuser table/view is READ-ONLY for the Keycloak User Storage Provider
-- INSERT, UPDATE, and DELETE operations are not supported through Keycloak
-- Users must be managed through database administration tools outside of Keycloak
-- The Keycloak application cannot create, modify, or delete users in this table/view

-- ✅ Supported: User authentication, login, profile viewing, password validation
-- 🔴 Disabled: User creation, profile updates, user deletion through Keycloak
-- 🔴 Disabled: Table creation through Keycloak setup scripts (insufficient permissions)

-- ===============================================
-- SECURITY NOTES
-- ===============================================
-- v_oidc_users view provides enhanced security by:
-- - Filtering out sensitive columns not needed for OIDC
-- - Restricting access to validated users only
-- - Providing database-level access control
-- - Preventing accidental data modification
