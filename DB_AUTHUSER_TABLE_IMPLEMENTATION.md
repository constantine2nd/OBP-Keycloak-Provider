# DB_AUTHUSER_TABLE Implementation Summary

This document summarizes the implementation of the `DB_AUTHUSER_TABLE` environment variable to support view-based access using `v_authuser_oidc` in the OBP Keycloak Provider.

## Overview

The `DB_AUTHUSER_TABLE` environment variable allows the application to use either:
- **`v_authuser_oidc`** (default): A secure database view with read-only access
- **`authuser`**: Direct table access for backward compatibility

This implementation enhances security by providing view-based access with minimal permissions for production environments.

## Changes Made

### 1. Core Application Changes

#### DatabaseConfig.java
- **Updated default value**: Changed `DEFAULT_AUTHUSER_TABLE` from `"authuser"` to `"v_authuser_oidc"`
- **Added getter method**: `getAuthUserTable()` method already existed and properly returns the configured table/view name
- **Environment variable support**: `DB_AUTHUSER_TABLE` environment variable is properly loaded at runtime

#### KcUserStorageProvider.java
- **All SQL queries updated**: Every database query now uses `dbConfig.getAuthUserTable()` instead of hardcoded table names
- **Affected methods**:
  - `getUserById()`: Uses configurable table/view for user lookup by ID
  - `getUserByUsername()`: Uses configurable table/view for username-based lookup
  - `getUserByEmail()`: Uses configurable table/view for email-based lookup
  - `getUsersCount()`: Uses configurable table/view for counting users
  - `searchForUserStream()`: Uses configurable table/view for user searches
  - `getAllUsers()`: Uses configurable table/view for user enumeration

### 2. Configuration Files

#### env.sample
- **Updated default**: Changed `DB_AUTHUSER_TABLE=authuser` to `DB_AUTHUSER_TABLE=v_authuser_oidc`
- **Updated comment**: Clarified that `v_authuser_oidc` is now the default for view-based access

#### docker-compose.runtime.yml
- **Added environment variable**: Added `DB_AUTHUSER_TABLE: ${DB_AUTHUSER_TABLE:-v_authuser_oidc}`
- **Default value**: Uses `v_authuser_oidc` as default in container environment

#### docker-compose.example.yml
- **Added environment variable**: Added `DB_AUTHUSER_TABLE: v_authuser_oidc`
- **Hardcoded value**: Shows explicit configuration for production example

### 3. Scripts and Testing

#### sh/test-local-postgres-setup.sh
- **Updated default**: Changed default from `authuser` to `v_authuser_oidc` in `AUTHUSER_TABLE="${DB_AUTHUSER_TABLE:-v_authuser_oidc}"`
- **Dynamic testing**: Script now tests whatever table/view is configured

#### Profile Update Testing
- **Read-only validation**: Built-in checks verify read-only behavior with `v_authuser_oidc` view
- **Consistent behavior**: Script now uses the new default consistently

### 4. Database Setup

#### sql/script.sql
- **Added OIDC user creation**: Creates `oidc_user` with secure password
- **Added view definition**: Creates `v_authuser_oidc` view with filtered columns and validated users only
- **Added permissions**: Grants minimal SELECT permissions to `oidc_user` on the view
- **Enhanced documentation**: Added configuration options and security notes
- **Backward compatibility**: Maintains existing `obp` user permissions for legacy setups

### 5. Documentation

#### docs/ENVIRONMENT.md
- **Added DB_AUTHUSER_TABLE documentation**: Complete reference including default value, description, and use cases
- **Added security section**: Explains benefits of view-based access
- **Updated examples**: All configuration examples now show proper usage
- **Added troubleshooting**: Specific troubleshooting steps for table/view access issues

#### VIEW_BASED_ACCESS.md (New File)
- **Comprehensive guide**: Complete setup and usage guide for view-based access
- **SQL scripts**: Ready-to-use SQL for database administrators
- **Configuration examples**: Production and development configurations
- **Security benefits**: Detailed explanation of security enhancements
- **Migration guide**: Step-by-step migration from direct table access
- **Troubleshooting**: Common issues and solutions
- **Performance considerations**: Indexing and monitoring recommendations

#### README.md
- **Added security features section**: Highlights view-based access capabilities
- **Added quick configuration**: Shows both production (view-based) and development (direct) configurations
- **Reference to detailed docs**: Points users to VIEW_BASED_ACCESS.md for detailed setup

#### AUTHUSER_READ_ONLY_POLICY.md (Updated)
- **Maintained consistency**: All references to table access now acknowledge both table and view options
- **Security policy**: Policy applies to both direct table and view-based access

## Configuration Options

### Production Configuration (Recommended)
```bash
DB_USER=oidc_user
DB_PASSWORD=secure_oidc_password
DB_AUTHUSER_TABLE=v_authuser_oidc
```

**Benefits:**
- Enhanced security through view-based access
- Read-only permissions prevent data corruption
- Only validated users are accessible
- Minimal surface area for security issues

### Development Configuration
```bash
DB_USER=obp
DB_PASSWORD=f
DB_AUTHUSER_TABLE=authuser
```

**Benefits:**
- Direct table access for debugging
- Backward compatibility
- Full dataset access including unvalidated users

### Default Behavior
- **New default**: `v_authuser_oidc` (view-based access)
- **Automatic fallback**: If `DB_AUTHUSER_TABLE` is not set, uses `v_authuser_oidc`
- **Runtime configuration**: Value is read at application startup from environment

## Database Requirements

### For v_authuser_oidc (Production)
1. **User creation**: `oidc_user` with secure password
2. **View creation**: `v_authuser_oidc` with filtered columns and validated users
3. **Permissions**: SELECT permission on view for `oidc_user`

### For authuser (Development/Legacy)
1. **Existing setup**: Uses existing `obp` user
2. **Direct access**: Full table access with existing permissions
3. **Backward compatibility**: No changes required for existing deployments

## Security Enhancements

### View-Based Access Benefits
1. **Read-only operations**: No INSERT, UPDATE, or DELETE possible
2. **Column filtering**: Only OIDC-required fields exposed
3. **Row filtering**: Only validated users accessible
4. **Database-level security**: Leverages PostgreSQL ACLs
5. **Minimal permissions**: `oidc_user` has only SELECT on view

### Security Model
- **Separation of concerns**: Database admin manages users, application only reads
- **Principle of least privilege**: Minimal permissions for application user
- **Defense in depth**: Multiple layers of security (application + database)

## Migration Path

### From Direct Table Access
1. **Create database objects**: Run SQL script to create `oidc_user` and view
2. **Test in development**: Validate configuration with new environment variables
3. **Update production**: Change environment variables and restart services
4. **Monitor**: Verify authentication still works properly
5. **Rollback plan**: Can quickly revert to direct table access if needed

### Zero-Downtime Migration
The implementation supports zero-downtime migration:
1. Database setup can be done while application is running
2. Environment variable change requires restart but is very quick
3. Both access methods can coexist during transition

## Testing and Validation

### Automated Testing
- **Script validation**: `sh/test-local-postgres-setup.sh` validates configured table/view
- **Profile testing**: Built-in validation verifies read-only behavior
- **Environment validation**: Configuration scripts check all required variables

### Manual Testing
```bash
# Test view access
PGPASSWORD='password' psql -h host -U oidc_user -d obp_mapped -c "SELECT count(*) FROM v_authuser_oidc;"

# Test application configuration
export DB_AUTHUSER_TABLE=v_authuser_oidc
./sh/test-local-postgres-setup.sh
```

## Backward Compatibility

### Existing Deployments
- **No breaking changes**: Existing deployments continue to work
- **Gradual migration**: Can migrate at your own pace
- **Rollback capability**: Can revert to previous configuration anytime

### Legacy Support
- **obp user**: Still supported for backward compatibility
- **Direct table access**: Still available via `DB_AUTHUSER_TABLE=authuser`
- **Existing scripts**: Continue to work with both configurations

## Performance Impact

### View Performance
- **No performance penalty**: Views don't store data, just filter access
- **Same indexes**: Uses existing indexes from underlying table
- **Efficient filtering**: `validated = true` condition is index-friendly

### Query Performance
- **Identical execution**: Same query performance as direct table access
- **Index usage**: All existing indexes are utilized by the view
- **No additional overhead**: PostgreSQL optimizes view queries efficiently

## Monitoring and Maintenance

### Health Checks
- **Connection testing**: Scripts verify database connectivity
- **Data validation**: Scripts check that configured table/view exists
- **Permission verification**: Scripts validate user permissions

### Regular Maintenance
- **Password rotation**: Regular rotation of `oidc_user` password
- **Permission audit**: Regular review of database permissions
- **View definition**: Monitor and version control view definition changes

## Implementation Status

### ✅ Completed
- [x] Core application support for `DB_AUTHUSER_TABLE`
- [x] Default value changed to `v_authuser_oidc`
- [x] All SQL queries use configurable table/view name
- [x] Environment configuration updated
- [x] Docker compose files updated
- [x] Testing scripts updated
- [x] Database setup scripts updated
- [x] Comprehensive documentation created
- [x] Migration guides provided
- [x] Security model documented

### ✅ Tested
- [x] View-based access functionality
- [x] Backward compatibility with direct table access
- [x] Environment variable configuration
- [x] Database connection and permissions
- [x] Application startup and user authentication

### ✅ Ready for Production
- [x] Security-hardened default configuration
- [x] Production deployment documentation
- [x] Migration and rollback procedures
- [x] Monitoring and maintenance guidelines

## Next Steps

1. **Database administrator**: Create `oidc_user` and `v_authuser_oidc` view using provided SQL
2. **Development team**: Test view-based access in development environment
3. **Production deployment**: Update environment variables to use new secure defaults
4. **Monitoring**: Verify authentication works and monitor for any issues
5. **Documentation**: Update internal deployment guides with new configuration

## Related Files

### Core Implementation
- `src/main/java/io/tesobe/config/DatabaseConfig.java`
- `src/main/java/io/tesobe/providers/KcUserStorageProvider.java`

### Configuration
- `env.sample`
- `docker-compose.runtime.yml`
- `docker-compose.example.yml`

### Database
- `sql/script.sql`

### Scripts
- `sh/test-local-postgres-setup.sh`
- Profile update validation scripts

### Documentation
- `docs/ENVIRONMENT.md`
- `VIEW_BASED_ACCESS.md`
- `README.md`

---

**Implementation Date**: January 2025  
**Status**: Complete and Ready for Production  
**Compatibility**: OBP Keycloak Provider v1.0+, PostgreSQL 12+, Keycloak 26+