# OBP-Keycloak-Provider: Development Tools

This directory contains development tools and scripts for **building, running, and managing** the `obp-keycloak-provider` in local development environments. All scripts support separated database architecture and include recent critical fixes.

## 🔧 Recent Updates

**Critical fixes included:**
- ✅ Fixed JDBC URL configuration in docker-compose files
- ✅ Resolved port conflicts (user storage moved to port 5434)
- ✅ Fixed SQL syntax errors in database initialization
- ✅ Updated all scripts to support separated database architecture

## Available Scripts

The `development/` directory contains exactly **2 shell scripts**:

### 1. Main Deployment Script (`run-local-postgres-cicd.sh`)

**Purpose**: Primary deployment script for local development with CI/CD-style approach

```bash
# Standard deployment
./development/run-local-postgres-cicd.sh

# With custom themes
./development/run-local-postgres-cicd.sh --themed
```

**What it does:**
- ✅ Validates environment configuration
- ✅ Tests database connectivity
- ✅ Builds Maven project
- ✅ Creates Docker image with cache invalidation
- ✅ Deploys container with proper configuration
- ✅ Performs health checks
- ✅ **Themed mode**: Validates and includes OBP custom themes

**8-Step Pipeline:**
1. Environment validation
2. Database connectivity test
3. Maven build
4. Container cleanup (stop)
5. Container cleanup (remove)
6. Docker image build
7. Container start
8. Health check

### 2. Container Management (`manage-container.sh`)

**Purpose**: Interactive container management with menu-driven interface

```bash
./development/manage-container.sh
```

**Features:**
- 🎛️ Interactive menu system
- 📊 Container status checking
- 📋 Log viewing (last 50 lines or follow mode)
- 🔄 Start/stop/restart operations
- 🗑️ Container removal
- 🌐 URL and credential display
- 🔍 Automatic container detection

---

## Quick Start Guide

### 1. Setup Environment
```bash
# Copy and edit environment file
cp env.sample .env
# Edit .env with your configuration
```

### 2. Deploy Application
```bash
# Standard deployment
./development/run-local-postgres-cicd.sh

# Themed deployment (requires themes/obp/ directory)
./development/run-local-postgres-cicd.sh --themed
```

### 3. Manage Container
```bash
# Interactive management
./development/manage-container.sh
```

---

## Environment Requirements

### Required Environment Variables
- `KC_DB_URL` - Keycloak database URL
- `KC_DB_USERNAME` - Keycloak database user
- `KC_DB_PASSWORD` - Keycloak database password
- `DB_URL` - User storage database URL
- `DB_USER` - User storage database user (should be `oidc_user`)
- `DB_PASSWORD` - User storage database password
- `DB_AUTHUSER_TABLE` - Must be `v_oidc_users` for security
- `OBP_AUTHUSER_PROVIDER` - Provider name (mandatory)

### Optional Variables
- `KEYCLOAK_ADMIN` - Admin username (default: admin)
- `KEYCLOAK_ADMIN_PASSWORD` - Admin password (default: admin)
- `KEYCLOAK_HTTP_PORT` - HTTP port (default: 8000)
- `KEYCLOAK_HTTPS_PORT` - HTTPS port (default: 8443)

---

## Container Management

### Using the Management Script
```bash
./development/manage-container.sh
```

**Menu Options:**
1. Check container status
2. View logs (last 50 lines)
3. Follow logs (real-time)
4. Stop container
5. Start container
6. Restart container
7. Remove container
8. Stop and remove
9. Show access URLs
0. Exit

### Direct Docker Commands
```bash
# View logs
docker logs obp-keycloak-local -f

# Stop all containers
docker stop obp-keycloak-local

# Remove with volumes (careful: deletes data)
docker rm obp-keycloak-local

# Check status
docker ps --filter name=obp-keycloak-local
```

---

## Themed Deployments

### Prerequisites
- `themes/obp/theme.properties` - Theme configuration
- `themes/obp/login/login.ftl` - Login template
- `themes/obp/login/template.ftl` - Base template
- Optional: CSS, images, message files in `themes/obp/login/resources/`

### Deployment
```bash
./development/run-local-postgres-cicd.sh --themed
```

### Theme Activation
1. Access Admin Console: https://localhost:8443/admin
2. Login with admin credentials
3. Go to: Realm Settings > Themes
4. Select "obp" from Login theme dropdown
5. Save configuration

---

## Troubleshooting

### Common Issues

#### Database Connection Failures
```bash
# Check PostgreSQL status
sudo systemctl status postgresql

# Test manual connection
PGPASSWORD=your_password psql -h host.docker.internal -p 5432 -U oidc_user -d obp_mapped
```

#### Container Issues
```bash
# Check port conflicts
netstat -tulpn | grep -E ':(8000|8443)'

# Review container logs
docker logs obp-keycloak-local

# Full cleanup if needed
docker system prune -f
```

#### Theme Issues (--themed deployments)
```bash
# Check theme files exist
find themes/obp -type f

# Verify theme configuration
cat themes/obp/theme.properties

# Try standard deployment first
./development/run-local-postgres-cicd.sh
```

### Security Validation Errors
- **DB_AUTHUSER_TABLE must be 'v_oidc_users'**: Update `.env` file
- **OBP_AUTHUSER_PROVIDER is mandatory**: Set provider name in `.env` file

---

## Access Information

After successful deployment:

### Service URLs
- **HTTP**: http://localhost:8000
- **HTTPS**: https://localhost:8443
- **Admin Console**: https://localhost:8443/admin

### Default Credentials
- **Username**: admin
- **Password**: admin

---

## Best Practices

1. **Use secure passwords**: Never use defaults in production
2. **Validate configuration**: The deployment script validates all settings
3. **Monitor logs**: Use `./development/manage-container.sh` for log monitoring
4. **Clean deployments**: Scripts ensure clean state on each run
5. **Database security**: Always use `oidc_user` with view-only permissions
6. **Theme testing**: Test standard deployment before themed if issues occur

---

## Support

For issues with development scripts:

1. Check container logs: `docker logs obp-keycloak-local`
2. Use the management script: `./development/manage-container.sh`
3. Ensure `.env` file contains all required variables
4. Review troubleshooting section above
5. Check Docker system resources: `docker system df`

The scripts are designed to fail fast and provide clear error messages to facilitate quick problem resolution in local development environments.