# Database Setup Scripts

This directory contains SQL scripts for setting up the databases required by the OBP Keycloak Provider.


## Quick Setup Guide

1. **Set up Keycloak's database:**
   ```bash
   # Edit the password in the script first!
   psql -U postgres -h localhost -f database/setup-keycloak-user.sql
   ```

2. **Set up User Storage database:**
   - Repository: https://github.com/OpenBankProject/OBP-API
   - Navigate to: `obp-api/src/main/scripts/sql/OIDC/`

3. **Configure your `.env` file:**
   **[env.sample](env.sample)**: Complete environment variable reference with examples and securit

## Security Notes

- Always use strong passwords for database users
- The `keycloak` user has full access to the `keycloak` database only
- The `oidc_user` should have read-only access to the user storage database

For more detailed setup instructions, see the main [README.md](../README.md) file.
