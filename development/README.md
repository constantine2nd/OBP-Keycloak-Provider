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
# Standard deployment (uses the unified Dockerfile at development/docker/Dockerfile)
./development/run-local-postgres-cicd.sh

# With custom themes (script will pass THEMED build-arg)
./development/run-local-postgres-cicd.sh --themed

# Alternatively: build directly with Docker using the single unified Dockerfile.
# Standard (no themes):
docker build --no-cache --build-arg THEMED=false -t obp-keycloak:standard -f development/docker/Dockerfile .

# Themed build (includes themes/obp and themes/obp-dark from repo context):
docker build --no-cache --build-arg THEMED=true -t obp-keycloak:themed -f development/docker/Dockerfile .
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
# Standard deployment (recommended: use the script which builds + deploys)
./development/run-local-postgres-cicd.sh

# Themed deployment (requires themes/obp/ directory; the script will validate and include themes)
./development/run-local-postgres-cicd.sh --themed

# Direct Docker build options using the single development Dockerfile:
# Build standard image (no themes):
docker build --no-cache --build-arg THEMED=false -t obp-keycloak:standard -f development/docker/Dockerfile .

# Build themed image (ensure themes/obp exists in repository root):
docker build --no-cache --build-arg THEMED=true -t obp-keycloak:themed -f development/docker/Dockerfile .
```

### Build arguments

The unified Dockerfile accepts several build-time arguments (passed with `--build-arg`). The provider JAR and JDBC driver JARs must be pre-built on the host before running `docker build` (the deployment script handles this automatically).

- `KEYCLOAK_VERSION` (default: `26.5.1`) — the Keycloak base image tag used in the builder and final images. Example:
```bash
--build-arg KEYCLOAK_VERSION=26.5.1
```

- `THEMED` (default: `false`) — controls whether the Dockerfile retains the `themes/obp` and `themes/obp-dark` directories in the final image. Set to `true` to keep themes in the image (the deployment script passes this when `--themed` is used):
```bash
--build-arg THEMED=true
```

- `BUILD_TIMESTAMP` and `JAR_CHECKSUM` — used to invalidate build cache and force rebuild when sources or built artifacts change. The deployment script computes and passes these automatically. If building manually, compute and pass them to ensure cache invalidation:
```bash
BUILD_TIMESTAMP=$(date +%s)
JAR_CHECKSUM=$(sha256sum target/obp-keycloak-provider.jar | cut -d' ' -f1)

docker build --no-cache \
  --build-arg BUILD_TIMESTAMP="$BUILD_TIMESTAMP" \
  --build-arg JAR_CHECKSUM="$JAR_CHECKSUM" \
  --build-arg THEMED=true \
  -f development/docker/Dockerfile -t obp-keycloak:themed .
```

> Note: In CI you should pin `KEYCLOAK_VERSION` to a specific version for reproducible builds. Avoid `latest` in CI.

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
- `KEYCLOAK_HTTP_PORT` - HTTP port (default: 7787)
- `KEYCLOAK_HTTPS_PORT` - HTTPS port (default: 8443)
- `KEYCLOAK_MGMT_PORT` - Management/health port (default: 9000)

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
netstat -tulpn | grep -E ':(7787|8443|9000)'

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
- **HTTP**: http://localhost:7787
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