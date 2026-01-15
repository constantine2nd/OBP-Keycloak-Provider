-- =============================================================================
-- Keycloak Database User Setup Script
-- =============================================================================
-- This script creates the database user for Keycloak's internal database.
-- Run this script as a PostgreSQL superuser (e.g., postgres) before starting Keycloak.
--
-- Usage:
--   psql -U postgres -h localhost -f setup-keycloak-user.sql
--
-- Environment Variables Referenced:
--   KC_DB_USERNAME (default: keycloak)
--   KC_DB_PASSWORD (set in your .env file)
--   KC_DB_NAME (default: keycloak)
-- =============================================================================

-- Create the keycloak database user
CREATE ROLE keycloak WITH
	NOSUPERUSER
	NOCREATEDB
	NOCREATEROLE
	INHERIT
	LOGIN
	NOREPLICATION
	NOBYPASSRLS
	CONNECTION LIMIT -1;

-- Set the password for the keycloak user
-- Replace 'your_secure_password' with the value from KC_DB_PASSWORD in your .env file
ALTER ROLE keycloak WITH PASSWORD 'your_secure_password';

-- Create the keycloak database (if it doesn't exist)
CREATE DATABASE keycloak WITH
	OWNER = keycloak
	ENCODING = 'UTF8'
	LC_COLLATE = 'en_US.utf8'
	LC_CTYPE = 'en_US.utf8'
	TABLESPACE = pg_default
	CONNECTION LIMIT = -1;

-- Grant necessary permissions
GRANT ALL PRIVILEGES ON DATABASE keycloak TO keycloak;

-- Connect to the keycloak database and grant schema permissions
\c keycloak
GRANT ALL ON SCHEMA public TO keycloak;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO keycloak;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO keycloak;

-- Set default privileges for future objects
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO keycloak;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO keycloak;

-- Display confirmation
SELECT 'Keycloak database user and database created successfully!' AS result;
SELECT 'Database: keycloak, User: keycloak' AS configuration;
SELECT 'Remember to update KC_DB_PASSWORD in your .env file' AS reminder;
