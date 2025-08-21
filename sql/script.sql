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

-- Grant READ-ONLY access to Keycloak user
GRANT SELECT ON public.authuser TO obp;
GRANT USAGE ON SEQUENCE authuser_id_seq TO obp;

-- ===============================================
-- KEYCLOAK PROVIDER LIMITATIONS
-- ===============================================
-- NOTE: The authuser table is READ-ONLY for the Keycloak User Storage Provider
-- INSERT, UPDATE, and DELETE operations are not supported through Keycloak
-- Users must be managed through database administration tools outside of Keycloak
-- The Keycloak application cannot create, modify, or delete users in this table

-- ✅ Supported: User authentication, login, profile viewing, password validation
-- 🔴 Disabled: User creation, profile updates, user deletion through Keycloak
-- 🔴 Disabled: Table creation through Keycloak setup scripts (insufficient permissions)
