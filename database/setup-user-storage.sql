-- =============================================================================
-- User Storage Database Setup Script
-- =============================================================================
-- This script sets up the user storage database components for OBP Keycloak Provider.
-- This should be run on your existing OBP database to enable OIDC user federation.
--
-- Usage:
--   psql -U postgres -h localhost -d obp_mapped -f setup-user-storage.sql
--
-- Environment Variables Referenced:
--   DB_USER (default: oidc_user)
--   DB_PASSWORD (set in your .env file)
--   DB_NAME (default: obp_mapped)
--   DB_AUTHUSER_TABLE (default: v_oidc_users)
-- =============================================================================

-- Create the OIDC user view
-- This view joins authuser and resourceuser tables to provide user data for OIDC authentication
-- Only validated users are included for security
CREATE OR REPLACE VIEW public.v_oidc_users
AS SELECT ru.userid_ AS user_id,
    au.username,
    au.firstname,
    au.lastname,
    au.email,
    au.validated,
    au.provider,
    au.password_pw,
    au.password_slt,
    au.createdat,
    au.updatedat
   FROM authuser au
     JOIN resourceuser ru ON au.user_c = ru.id
  WHERE au.validated = true
  ORDER BY au.username;

-- Add comment to the view for documentation
COMMENT ON VIEW public.v_oidc_users IS 'OIDC user view for Keycloak federation - contains only validated users from authuser table joined with resourceuser';

-- Create the oidc_user role for read-only access
-- This user will be used by Keycloak to query user information
CREATE ROLE oidc_user WITH
	NOSUPERUSER
	NOCREATEDB
	NOCREATEROLE
	INHERIT
	LOGIN
	NOREPLICATION
	NOBYPASSRLS
	CONNECTION LIMIT 10;

-- Set the password for the oidc_user
-- Replace 'your_secure_password' with the value from DB_PASSWORD in your .env file
ALTER ROLE oidc_user WITH PASSWORD 'your_secure_password';

-- Grant SELECT permission on the OIDC users view
GRANT SELECT ON public.v_oidc_users TO oidc_user;

-- Grant USAGE on the public schema (required for view access)
GRANT USAGE ON SCHEMA public TO oidc_user;

-- Optional: Grant SELECT on related tables if direct access is needed
-- Uncomment these lines if you need direct table access instead of view-based access
-- GRANT SELECT ON public.authuser TO oidc_user;
-- GRANT SELECT ON public.resourceuser TO oidc_user;

-- Verify the setup
-- Check if the view exists and has data
SELECT
    'v_oidc_users view created successfully' AS status,
    COUNT(*) AS total_users,
    COUNT(CASE WHEN validated = true THEN 1 END) AS validated_users
FROM public.v_oidc_users;

-- Check if the oidc_user role exists and has proper permissions
SELECT
    r.rolname AS role_name,
    r.rolcanlogin AS can_login,
    r.rolconnlimit AS connection_limit,
    'Role created successfully' AS status
FROM pg_roles r
WHERE r.rolname = 'oidc_user';

-- Display granted permissions
SELECT
    grantee,
    table_name,
    privilege_type,
    'Permissions granted successfully' AS status
FROM information_schema.role_table_grants
WHERE grantee = 'oidc_user' AND table_name = 'v_oidc_users';

-- Security verification
-- Ensure only validated users are accessible
SELECT
    'Security check' AS test,
    CASE
        WHEN COUNT(CASE WHEN validated = false THEN 1 END) = 0
        THEN 'PASSED - No unvalidated users in view'
        ELSE 'WARNING - Unvalidated users found in view'
    END AS result
FROM public.v_oidc_users;

-- Display sample data structure (first 3 users, no sensitive data)
SELECT
    'Sample view structure' AS info,
    user_id,
    username,
    email,
    validated,
    provider
FROM public.v_oidc_users
LIMIT 3;

-- Final confirmation message
SELECT
    'User storage database setup completed!' AS result,
    'Database: ' || current_database() AS database_info,
    'View: v_oidc_users, User: oidc_user' AS components,
    'Remember to update DB_PASSWORD in your .env file' AS reminder;
