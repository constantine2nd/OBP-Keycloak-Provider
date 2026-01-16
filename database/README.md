# Database Setup Scripts

This directory contains SQL scripts for setting up the databases required by the OBP Keycloak Provider.

## Overview

The OBP Keycloak Provider requires two PostgreSQL databases:

1. **Keycloak's Internal Database** (`keycloak`) - Stores Keycloak's realm data, users, clients, tokens, etc.
2. **User Storage Database** (`obp_mapped`) - Contains external user data that Keycloak federates from your existing OBP system

## Scripts

### setup-keycloak-user.sql

Creates the database user and database for Keycloak's internal storage.

**What it does:**
- Creates the `keycloak` PostgreSQL role with appropriate permissions
- Creates the `keycloak` database owned by the keycloak user
- Sets up proper permissions for Keycloak to manage its schema

**Usage:**
```bash
# Run as PostgreSQL superuser (replace password with your KC_DB_PASSWORD value)
psql -U postgres -h localhost -c "
CREATE ROLE keycloak WITH 
    NOSUPERUSER
    NOCREATEDB
    NOCREATEROLE
    INHERIT
    LOGIN
    NOREPLICATION
    NOBYPASSRLS
    CONNECTION LIMIT -1
    PASSWORD 'your_kc_db_password_from_env_file';"

# Then run the setup script
psql -U postgres -h localhost -f database/setup-keycloak-user.sql
```

**Environment Variables:**
- `KC_DB_USERNAME=keycloak` (matches the role created)
- `KC_DB_PASSWORD=your_secure_password` (set this in your `.env` file)
- `KC_DB_NAME=keycloak` (matches the database created)

### setup-user-storage.sql

**IMPORTANT:** This file now references the official OBP-API SQL scripts as the source of truth to avoid code duplication.

**What you need to do:**
1. Use the official OBP-API repository scripts instead of the local setup-user-storage.sql
2. Navigate to the OBP-API repository: https://github.com/OpenBankProject/OBP-API/tree/develop/obp-api/src/main/scripts/sql/OIDC
3. Follow the instructions in the README.md file in that directory

**Official Usage:**
```bash
# Clone or download the OBP-API repository
# Navigate to: obp-api/src/main/scripts/sql/OIDC/
# Run the official setup script:
psql -d your_obp_database
\i give_read_access_to_users.sql
```

**Environment Variables:**
- `DB_USER=oidc_user` (matches the role created)
- `DB_PASSWORD=your_secure_password` (set this in your `.env` file)
- `DB_NAME=obp_mapped` (your existing OBP database)
- `DB_AUTHUSER_TABLE=v_oidc_users` (the view created by this script)

**View Structure:**
The `v_oidc_users` view provides the following columns:
- `user_id` - From resourceuser.userid_
- `username`, `firstname`, `lastname`, `email` - User profile data
- `validated`, `provider` - Authentication status and provider
- `password_pw`, `password_slt` - Password hash and salt
- `createdat`, `updatedat` - Timestamps

**Security Features:**
- Only includes validated users (`WHERE au.validated = true`)
- Read-only access for the oidc_user role
- Connection limit of 10 for the database user
- Includes verification queries to ensure proper setup

## User Storage Database

For the user storage database (`obp_mapped`), you should use your existing OBP PostgreSQL database. The `setup-user-storage.sql` script will create the necessary view and user.

**Official Setup (recommended):**
```bash
# Use the official OBP-API repository scripts
# Navigate to: https://github.com/OpenBankProject/OBP-API/tree/develop/obp-api/src/main/scripts/sql/OIDC
cd obp-api/src/main/scripts/sql/OIDC/
psql -d your_obp_database
\i give_read_access_to_users.sql
```

**What the official scripts do:**
- **set_and_connect.sql**: Defines variables and database connection
- **cre_OIDC_USER.sql**: Creates the oidc_user role with appropriate permissions
- **cre_v_oidc_users.sql**: Creates the v_oidc_users view joining authuser and resourceuser
- **give_read_access_to_users.sql**: Main script that orchestrates the setup

**Why use the official scripts:**
- Always up-to-date with the latest OBP-API changes
- Maintained by the OBP team
- Includes proper security settings and error handling
- Avoids code duplication and version drift

## Quick Setup Guide

1. **Set up Keycloak's database:**
   ```bash
   # Edit the password in the script first!
   psql -U postgres -h localhost -f database/setup-keycloak-user.sql
   ```

2. **Set up User Storage database:**
   ```bash
   # Use the official OBP-API scripts
   # Navigate to the OBP-API repository: obp-api/src/main/scripts/sql/OIDC/
   psql -d obp_mapped
   \i give_read_access_to_users.sql
   ```

3. **Configure your `.env` file:**
   ```properties
   # Keycloak Database
   KC_DB_USERNAME=keycloak
   KC_DB_PASSWORD=your_secure_keycloak_password
   KC_DB_NAME=keycloak
   
   # User Storage Database (your existing OBP database)
   DB_USER=oidc_user
   DB_PASSWORD=your_secure_oidc_user_password
   DB_NAME=obp_mapped
   ```

4. **Verify the setup:**
   ```bash
   # Test Keycloak database connection
   PGPASSWORD="your_kc_password" psql -h localhost -U keycloak -d keycloak -c "SELECT 1;"
   
   # Test User Storage database connection and view
   PGPASSWORD="your_db_password" psql -h localhost -U oidc_user -d obp_mapped -c "SELECT COUNT(*) FROM v_oidc_users;"
   ```

## Security Notes

- Always use strong passwords for database users
- The `keycloak` user has full access to the `keycloak` database only
- The `oidc_user` should have read-only access to the user storage database
- In production, consider using SSL connections and restrict network access
- Never commit actual passwords to version control

## Troubleshooting

**Connection failures:**
- Verify PostgreSQL is running and accepting connections
- Check that the users exist: `SELECT rolname FROM pg_roles WHERE rolname IN ('keycloak', 'oidc_user');`
- Verify database ownership: `SELECT datname, datdba, (SELECT rolname FROM pg_roles WHERE oid = datdba) as owner FROM pg_database WHERE datname IN ('keycloak', 'obp_mapped');`

**Permission issues:**
- Ensure the keycloak user owns the keycloak database
- Verify oidc_user has SELECT permissions on v_oidc_users view
- Check that the view v_oidc_users exists and contains the expected columns
- Verify the view shows only validated users: `SELECT COUNT(*) FROM v_oidc_users WHERE validated = true;`

**View-related issues:**
- Ensure authuser and resourceuser tables exist in your OBP database
- Verify the join condition: `au.user_c = ru.id` matches your schema
- Check that validated users exist: `SELECT COUNT(*) FROM authuser WHERE validated = true;`

For more detailed setup instructions, see the main [README.md](../README.md) file.