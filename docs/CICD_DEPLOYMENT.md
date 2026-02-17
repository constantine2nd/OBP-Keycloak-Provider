# development/run-local-postgres-cicd.sh Deployment Guide

This guide covers the CI/CD-style deployment script that provides predictable, automated deployment for local development environments.

## Overview

The deployment script (`development/run-local-postgres-cicd.sh`) is designed for local development environments where you want:

- **Always build**: No conditional logic - always rebuild everything
- **Always replace**: Stop and remove existing containers every time
- **Cache invalidation**: Docker layers rebuild when JAR file changes
- **Fast feedback**: Clear success/failure indicators
- **Deterministic**: Same inputs always produce same outputs

## Usage

### Basic Deployment
```bash
./development/run-local-postgres-cicd.sh
```

### Themed Deployment
```bash
./development/run-local-postgres-cicd.sh --themed
```

## Prerequisites

1. **PostgreSQL** accessible from Docker containers
2. **Databases configured**:
   - Keycloak database (as specified in `KC_DB_URL`)
   - User storage database (as specified in `DB_URL`)
   - User `oidc_user` with restricted view-only access to `v_oidc_users`
3. **Environment file**: `.env` with proper configuration

## Script Pipeline

The script follows an 8-step pipeline:

### [1/8] Environment Validation
- Checks Docker installation and daemon
- Validates Maven installation
- Loads and validates `.env` configuration
- Verifies all required environment variables (including DB_AUTHUSER_TABLE)
- **Security validation**: Ensures `DB_AUTHUSER_TABLE=v_oidc_users`
- **Themed deployments**: Validates theme files and structure

### [2/8] Database Connectivity
- Tests connection to Keycloak database
- Tests connection to User Storage database
- Fails fast if databases are unreachable

### [3/8] Maven Build
- Runs `mvn clean package -DskipTests`
- Generates JAR checksum for cache invalidation
- Creates build timestamp

### [4/8] Container Cleanup - Stop
- Stops existing container if running
- Non-blocking if container doesn't exist

### [5/8] Container Cleanup - Remove
- Removes existing container if exists
- Ensures clean slate for new deployment

### [6/8] Docker Image Build
- Builds image with `--no-cache` flag
- Passes build timestamp and JAR checksum as build args
- Forces cache invalidation when JAR changes

### [7/8] Container Start
- Creates new container with fresh configuration
- Uses database URLs from `.env` configuration
- Maps standard ports (7787 HTTP, 8443 HTTPS, 9000 management)

### [8/8] Health Check
- Waits up to 2 minutes for service readiness
- Uses Keycloak's `/health/ready` endpoint on management port (9000)
- Provides clear success/failure indication

## Theme Validation (--themed flag)

**Themed Deployment Requirements**:
- ✅ `themes/obp/theme.properties` with valid content
- ✅ `themes/obp/login/` directory structure
- ✅ Required templates: `login.ftl`, `template.ftl`
- ✅ `.github/Dockerfile_themed` exists
- ✅ Optional: CSS files, images, message files

## Environment Configuration

### Required .env Variables
```bash
# Keycloak Admin
KEYCLOAK_ADMIN=admin
KEYCLOAK_ADMIN_PASSWORD=admin

# Keycloak Database
KC_DB_URL=jdbc:postgresql://host.docker.internal:5432/keycloakdb
KC_DB_USERNAME=keycloak
KC_DB_PASSWORD=f

# User Storage Database (secure view-based access)
DB_URL=jdbc:postgresql://host.docker.internal:5432/obp_mapped
DB_USER=oidc_user
DB_PASSWORD=your_secure_password
DB_DRIVER=org.postgresql.Driver
DB_DIALECT=org.hibernate.dialect.PostgreSQLDialect
DB_AUTHUSER_TABLE=v_oidc_users

# MANDATORY: Provider filtering for user authentication (REQUIRED for security)
OBP_AUTHUSER_PROVIDER=your_provider_name

# Configuration
HIBERNATE_DDL_AUTO=validate
KC_HTTP_ENABLED=true
KC_HOSTNAME_STRICT=false
```

### Optional .env Variables (with defaults)
```bash
# Database Configuration (has defaults if not specified)
DB_DRIVER=org.postgresql.Driver
DB_DIALECT=org.hibernate.dialect.PostgreSQLDialect

# Hibernate Settings
HIBERNATE_SHOW_SQL=true
HIBERNATE_FORMAT_SQL=true

# Keycloak Runtime
KC_HEALTH_ENABLED=true
KC_METRICS_ENABLED=true
KC_FEATURES=token-exchange

# Local Development Ports
KEYCLOAK_HTTP_PORT=7787
KEYCLOAK_HTTPS_PORT=8443
KEYCLOAK_MGMT_PORT=9000
```

## Security Requirements

The script enforces secure database access:

### Database User Requirements
- **User**: `oidc_user` (restricted permissions)
- **Access**: SELECT-only on `v_oidc_users` view
- **No access**: Direct `authuser` table access blocked

### Required Database Setup
```sql
-- Create restricted user
CREATE USER oidc_user WITH PASSWORD 'your_secure_password';

-- Create secure view
CREATE OR REPLACE VIEW v_oidc_users AS
SELECT id, username, email, firstname, lastname, provider
FROM authuser
WHERE provider = 'your_provider_name';

-- Grant minimal permissions
GRANT SELECT ON v_oidc_users TO oidc_user;
GRANT USAGE ON SCHEMA public TO oidc_user;

-- Ensure no other permissions
REVOKE ALL ON authuser FROM oidc_user;
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM oidc_user;
GRANT SELECT ON v_oidc_users TO oidc_user;
```

## Monitoring and Troubleshooting

### Script Output
The script provides clear status indicators:
- ✓ Green checkmarks for successful steps
- ✗ Red X marks for failures
- Step-by-step progress tracking

### Container Management
```bash
# View logs
docker logs -f obp-keycloak-local

# Check status
docker ps --filter name=obp-keycloak-local

# Stop and remove
docker stop obp-keycloak-local && docker rm obp-keycloak-local
```

### Common Issues

#### Database Connection Failures
```bash
# Check PostgreSQL status
sudo systemctl status postgresql

# Test manual connection using URLs from your .env
# Extract connection details from KC_DB_URL and DB_URL
# Example for default configuration:
PGPASSWORD=f psql -h host.docker.internal -p 5432 -U keycloak -d keycloakdb
PGPASSWORD=your_secure_password psql -h host.docker.internal -p 5432 -U oidc_user -d obp_mapped
```

#### Docker Build Failures
```bash
# Check Docker space
docker system df

# Clean up if needed
docker system prune -f
```

#### Container Start Issues
```bash
# Check port conflicts
netstat -tulpn | grep -E ':(7787|8443|9000)'

# Review container logs
docker logs obp-keycloak-local
```

#### Theme Issues (--themed deployment)
```bash
# Check theme files
find themes/obp -type f

# Verify theme.properties
cat themes/obp/theme.properties | grep -E "(parent=|styles=)"

# Test with standard deployment first
./development/run-local-postgres-cicd.sh
```

#### Security Validation Errors
```bash
# If DB_AUTHUSER_TABLE validation fails:
# Ensure in .env file:
DB_AUTHUSER_TABLE=v_oidc_users

# If OBP_AUTHUSER_PROVIDER validation fails:
# Ensure in .env file:
OBP_AUTHUSER_PROVIDER=your_provider_name
```

## Access Information

After successful deployment:

### Service URLs
- **HTTP**: http://localhost:7787
- **HTTPS**: https://localhost:8443
- **Admin Console**: https://localhost:8443/admin

### Default Credentials
- **Username**: admin
- **Password**: admin

### Theme Configuration (--themed deployments)
1. Access Admin Console: https://localhost:8443/admin
2. Login with admin credentials
3. Go to: Realm Settings > Themes
4. Select "obp" theme for Login theme
5. Save configuration

## Best Practices

1. **Use secure passwords**: Never use default passwords in production
2. **Validate configuration**: Run script to check all required variables
3. **Monitor logs**: Check `docker logs obp-keycloak-local` for issues
4. **Clean environment**: Script ensures clean state on each run
5. **Theme testing**: Test standard deployment before themed if issues occur
6. **Database security**: Always use `oidc_user` with view-only permissions

## Support

For issues with the deployment script:

1. Check the troubleshooting section above
2. Review container logs: `docker logs obp-keycloak-local`
3. Verify database connectivity manually
4. Ensure `.env` file contains all required variables
5. Check Docker system resources and cleanup if needed

The script is designed to fail fast and provide clear error messages to facilitate quick problem resolution in local development environments.