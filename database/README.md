# Database Setup Scripts

This directory contains SQL scripts for setting up **Keycloak's internal database** only.

> **Note**: The OBP Keycloak Provider no longer accesses a user storage database directly.
> User authentication is delegated entirely to the OBP REST API. No `v_oidc_users` view,
> no JDBC driver, and no `oidc_user` database account are needed.

## Quick Setup Guide

1. **Set up Keycloak's internal database:**
   ```bash
   # Edit the password in the script first!
   psql -U postgres -h localhost -f database/setup-keycloak-user.sql
   ```

2. **Configure your `.env` file:**
   See [env.sample](../env.sample) for the complete environment variable reference.

## Security Notes

- Always use strong passwords for database users
- The `keycloak` database user has access to the `keycloak` database only

For deployment instructions, see the main [README.md](../README.md) file.
