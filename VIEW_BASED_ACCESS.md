# View-Based Access Setup Guide

This document explains how to set up and use the `v_authuser_oidc` view for secure, read-only access to user data in the OBP Keycloak Provider.

## Overview

The OBP Keycloak Provider now supports view-based access through the `DB_AUTHUSER_TABLE` environment variable. This provides enhanced security by:

- **Read-only access**: Prevents accidental data modification through Keycloak
- **Column filtering**: Only exposes OIDC-required fields
- **User filtering**: Only shows validated users
- **Database-level security**: Leverages PostgreSQL's access control system

## Quick Setup

### 1. Database Administrator Tasks

Execute the following SQL as a database administrator (e.g., `postgres` user):

```sql
-- Connect as database administrator
-- sudo -u postgres psql -d obp_mapped

-- Create dedicated OIDC user
CREATE USER oidc_user WITH PASSWORD 'your_secure_password_here';

-- Create the view
CREATE OR REPLACE VIEW public.v_authuser_oidc AS
SELECT
    id,
    username,
    firstname,
    lastname,
    email,
    validated,
    provider,
    password_pw,
    password_slt,
    createdat,
    updatedat
FROM public.authuser
WHERE validated = true;

-- Grant permissions
GRANT CONNECT ON DATABASE obp_mapped TO oidc_user;
GRANT USAGE ON SCHEMA public TO oidc_user;
GRANT SELECT ON public.v_authuser_oidc TO oidc_user;
```

### 2. Application Configuration

Update your environment variables:

```bash
# Use view-based access (recommended for production)
DB_USER=oidc_user
DB_PASSWORD=your_secure_password_here
DB_AUTHUSER_TABLE=v_authuser_oidc
```

## Configuration Options

### Production Setup (Recommended)

```bash
# Environment variables
DB_URL=jdbc:postgresql://your-db-host:5432/obp_mapped
DB_USER=oidc_user
DB_PASSWORD=secure_oidc_password
DB_AUTHUSER_TABLE=v_authuser_oidc
```

**Benefits:**
- Enhanced security through view-based access
- Read-only permissions prevent data corruption
- Only validated users are accessible
- Minimal surface area for potential security issues

### Development Setup (Legacy Compatibility)

```bash
# Environment variables
DB_URL=jdbc:postgresql://localhost:5432/obp_mapped
DB_USER=obp
DB_PASSWORD=f
DB_AUTHUSER_TABLE=authuser
```

**Benefits:**
- Direct table access for debugging
- Backward compatibility with existing setups
- Full user dataset access (including unvalidated users)

## View Definition

The `v_authuser_oidc` view is defined as:

```sql
CREATE OR REPLACE VIEW public.v_authuser_oidc AS
SELECT
    id,                    -- Primary key for user identification
    username,              -- Unique username for login
    firstname,             -- User's first name
    lastname,              -- User's last name
    email,                 -- User's email address
    validated,             -- User validation status
    provider,              -- Authentication provider
    password_pw,           -- Hashed password
    password_slt,          -- Password salt
    createdat,             -- Account creation timestamp
    updatedat              -- Last update timestamp
FROM public.authuser
WHERE validated = true;    -- Only show validated users
```

### Excluded Fields

The following fields from the original `authuser` table are **not** included in the view for security reasons:

- `locale`: User's locale preference (not essential for OIDC authentication)
- `timezone`: User's timezone preference (not essential for OIDC authentication)
- `user_c`: Internal user counter (not needed for OIDC)
- `superuser`: Admin flag (security-sensitive)
- `passwordshouldbechanged`: Password policy flag (not needed for OIDC)

## Security Benefits

### 1. Read-Only Access
- **No INSERT operations**: Users cannot be created through Keycloak
- **No UPDATE operations**: User profiles cannot be modified through Keycloak
- **No DELETE operations**: Users cannot be removed through Keycloak

### 2. Column-Level Security
- **Sensitive fields filtered**: Admin flags and internal counters are not exposed
- **OIDC-focused**: Only fields required for OpenID Connect are included
- **Minimal exposure**: Reduces potential attack surface

### 3. Row-Level Security
- **Validated users only**: Unvalidated/pending users are not accessible through OIDC
- **Consistent data**: Only users ready for authentication are exposed

### 4. Database-Level Security
- **PostgreSQL ACLs**: Leverages database access control lists
- **Dedicated user**: `oidc_user` has minimal, specific permissions
- **Audit trail**: Database logs all access attempts

## Migration Guide

### From Direct Table Access

If you're currently using direct `authuser` table access:

**Current configuration:**
```bash
DB_USER=obp
DB_PASSWORD=f
DB_AUTHUSER_TABLE=authuser  # or not set (defaults to authuser)
```

**New configuration:**
```bash
DB_USER=oidc_user
DB_PASSWORD=your_secure_password
DB_AUTHUSER_TABLE=v_authuser_oidc
```

**Migration steps:**
1. Create the `oidc_user` and view using the SQL above
2. Test the new configuration in a development environment
3. Update production environment variables
4. Restart Keycloak services
5. Verify users can still authenticate

### Rollback Plan

If issues occur, you can quickly rollback:

```bash
# Temporary rollback to direct table access
DB_USER=obp
DB_PASSWORD=f
DB_AUTHUSER_TABLE=authuser
```

## Testing and Validation

### 1. View Creation Test

```sql
-- Verify view exists
\d v_authuser_oidc

-- Test view access
SELECT count(*) FROM v_authuser_oidc;

-- Verify data consistency
SELECT 
    (SELECT count(*) FROM authuser WHERE validated = true) as expected,
    (SELECT count(*) FROM v_authuser_oidc) as actual;
```

### 2. User Permissions Test

```bash
# Test as oidc_user
PGPASSWORD='your_password' psql -h localhost -U oidc_user -d obp_mapped

# Should work
SELECT count(*) FROM v_authuser_oidc;

# Should fail (good!)
INSERT INTO v_authuser_oidc (username) VALUES ('test');
UPDATE v_authuser_oidc SET email = 'test@test.com';
DELETE FROM v_authuser_oidc WHERE id = 1;
```

### 3. Application Test

```bash
# Set environment variables
export DB_USER=oidc_user
export DB_PASSWORD=your_secure_password
export DB_AUTHUSER_TABLE=v_authuser_oidc

# Test with validation script
./sh/test-local-postgres-setup.sh

# Test authentication
curl -X POST http://localhost:8000/realms/your-realm/protocol/openid-connect/token \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "username=testuser&password=testpass&grant_type=password&client_id=your-client"
```

## Troubleshooting

### Common Issues

#### 1. View Does Not Exist
```
ERROR: relation "v_authuser_oidc" does not exist
```

**Solution:** Create the view using the SQL provided above as database administrator.

#### 2. Permission Denied
```
ERROR: permission denied for relation v_authuser_oidc
```

**Solution:** Grant SELECT permission to `oidc_user`:
```sql
GRANT SELECT ON public.v_authuser_oidc TO oidc_user;
```

#### 3. No Users Found
```
INFO: Found 0 users in database
```

**Possible causes:**
- No validated users in the database
- View filter is too restrictive
- Wrong view configuration

**Check:**
```sql
-- Check total users
SELECT count(*) FROM authuser;

-- Check validated users
SELECT count(*) FROM authuser WHERE validated = true;

-- Check view data
SELECT count(*) FROM v_authuser_oidc;
```

#### 4. Authentication Failures
```
WARN: User not found: username
```

**Solution:** Ensure users are validated:
```sql
UPDATE authuser SET validated = true WHERE username = 'your_user';
```

### Debug Commands

```bash
# Test database connection
PGPASSWORD='password' psql -h host -U oidc_user -d obp_mapped -c "SELECT 1"

# Verify view structure
PGPASSWORD='password' psql -h host -U oidc_user -d obp_mapped -c "\d v_authuser_oidc"

# Check user count
PGPASSWORD='password' psql -h host -U oidc_user -d obp_mapped -c "SELECT count(*) FROM v_authuser_oidc"

# Validate environment
./sh/test-local-postgres-setup.sh
```

## Performance Considerations

### 1. View Performance
- **Underlying indexes**: The view uses indexes from the `authuser` table
- **WHERE clause**: The `validated = true` filter is efficient if indexed
- **No performance penalty**: Views don't store data, just provide filtered access

### 2. Recommended Indexes

Ensure these indexes exist on the `authuser` table:

```sql
-- Primary key (already exists)
CREATE INDEX authuser_pk ON public.authuser (id);

-- Username lookup
CREATE UNIQUE INDEX authuser_username_provider ON public.authuser (username, provider);

-- Email lookup
CREATE INDEX authuser_email ON public.authuser (email);

-- Validation status (for view filtering)
CREATE INDEX authuser_validated ON public.authuser (validated);
```

### 3. Monitoring

Monitor view performance:

```sql
-- Check query performance
EXPLAIN ANALYZE SELECT * FROM v_authuser_oidc WHERE username = 'testuser';

-- Monitor view usage
SELECT 
    schemaname,
    viewname,
    n_tup_ins,
    n_tup_upd,
    n_tup_del
FROM pg_stat_user_tables 
WHERE relname = 'v_authuser_oidc';
```

## Security Audit

### Regular Checks

1. **Permission audit:**
```sql
-- Check who has access to the view
SELECT 
    grantee, 
    privilege_type 
FROM information_schema.role_table_grants 
WHERE table_name = 'v_authuser_oidc';
```

2. **View definition audit:**
```sql
-- Verify view definition hasn't changed
SELECT definition FROM pg_views WHERE viewname = 'v_authuser_oidc';
```

3. **User activity audit:**
```sql
-- Check connection logs for oidc_user
-- (Enable logging in postgresql.conf: log_connections = on)
grep "oidc_user" /var/log/postgresql/postgresql-*.log
```

## Best Practices

1. **Strong passwords**: Use strong, unique passwords for `oidc_user`
2. **Regular rotation**: Rotate `oidc_user` password regularly
3. **Network security**: Use SSL/TLS for database connections
4. **Monitoring**: Monitor database access logs
5. **Backup**: Regular backups of both table and view definitions
6. **Testing**: Test view changes in development first
7. **Documentation**: Keep view definition documented and version controlled

## Support

For issues or questions about view-based access:

1. Check the troubleshooting section above
2. Run validation scripts: `./sh/test-local-postgres-setup.sh`
3. Review database logs for permission or connection issues
4. Verify environment variables are correctly set
5. Test database connectivity separately from Keycloak

---

**Last Updated:** January 2025  
**Compatible With:** OBP Keycloak Provider v1.0+, PostgreSQL 12+, Keycloak 26+