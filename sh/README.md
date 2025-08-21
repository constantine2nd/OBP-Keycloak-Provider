````markdown
# OBP-Keycloak-Provider: Shell Scripts

This directory contains shell scripts for **building, running, and managing** the `obp-keycloak-provider` with support for separated database architecture and recent critical fixes.

## 🔧 Recent Updates

**Critical fixes included:**
- ✅ Fixed JDBC URL configuration in docker-compose files
- ✅ Resolved port conflicts (user storage moved to port 5434)
- ✅ Fixed SQL syntax errors in database initialization
- ✅ Updated all scripts to support separated database architecture

## Available Scripts

### Main Scripts

- **`run-local-postgres.sh`** - Local PostgreSQL deployment with runtime configuration
- **`validate-separated-db-config.sh`** - Comprehensive configuration validation  
- **`manage-container.sh`** - Interactive container management
- **`test-runtime-config.sh`** - Test cloud-native configuration
- **`compare-env.sh`** - Compare environment with examples

### Legacy Scripts

- **`run-local-postgres-cicd.sh`** - CI/CD deployment script (always build & replace)
- **`pg.sh`** - PostgreSQL container deployment

### Database Scripts

- **`validate-env.sh`** - Basic environment validation
- **`test-themed-deployment.sh`** - Theme deployment testing

---

## Primary Usage (Recommended)

### Cloud-Native Deployment

```bash
# 1. Setup environment
cp env.sample .env.local
# Edit .env.local with your configuration

# 2. Validate configuration
./sh/validate-separated-db-config.sh

# 3. Run with local PostgreSQL
./sh/run-local-postgres.sh --themed --validate

# 4. Manage containers (when needed)
./sh/manage-container.sh
```

---

## Requirements

- **Docker** (tested with Docker 20+)
- **Docker Compose** (tested with 2.0+)
- **Maven** (tested with Maven 3.8+)
- **Bash** (Linux or MacOS)
- **Git** (for pulling latest fixes)

### Environment Setup

Create a `.env` file in the project root:

```bash
cp env.sample .env
# Edit with your configuration
```

**Required environment variables for separated databases:**
```ini
# Keycloak Admin
KEYCLOAK_ADMIN=admin
KEYCLOAK_ADMIN_PASSWORD=secure_admin_password

# Keycloak Internal Database (Port 5433)
KC_DB_USERNAME=keycloak
KC_DB_PASSWORD=secure_keycloak_password

# User Storage Database (Port 5434 - changed from 5432)
USER_STORAGE_DB_USER=obp
USER_STORAGE_DB_PASSWORD=secure_user_password
```

> **Important**: Recent fixes changed the user storage port from 5432 to 5434 to avoid conflicts.

---

## Detailed Script Usage

### 1. Validation Script (`validate-separated-db-config.sh`)

**Purpose**: Comprehensive validation of separated database configuration

```bash
./sh/validate-separated-db-config.sh
```

**What it checks:**
- All required environment variables
- Database URL formats and connectivity
- Port availability and conflicts
- Recent fixes validation
- Security analysis
- Docker configuration

### 2. Local PostgreSQL Runner (`run-local-postgres.sh`)

**Purpose**: Deploy with runtime configuration (recommended)

```bash
# Standard deployment
./sh/run-local-postgres.sh

# With custom themes and validation
./sh/run-local-postgres.sh --themed --validate
```

**What it does:**
- Loads environment from `.env` file
- Starts separated database architecture
- Supports both standard and themed deployments
- Follows container logs

### 3. Container Manager (`manage-container.sh`)

**Purpose**: Interactive container management

```bash
./sh/manage-container.sh
```

**Features:**
- Start/stop/restart containers
- View logs and status
- Clean up resources
- Troubleshooting assistance

### 4. Runtime Config Tester (`test-runtime-config.sh`)

**Purpose**: Test cloud-native configuration without starting services

```bash
./sh/test-runtime-config.sh
```

---

## Database Architecture

### Separated Databases (Current)

| Service | External Port | Internal Port | Purpose |
|---------|---------------|---------------|---------|
| `keycloak-postgres` | 5433 | 5432 | Keycloak's internal data |
| `user-storage-postgres` | 5434 | 5432 | External user federation |
| `obp-keycloak` | 8000, 8443 | 8080, 8443 | Keycloak application |

### Recent Port Changes

**Important**: User storage database port changed from 5432 to 5434 to avoid conflicts with system PostgreSQL.

**Configuration required for:**
- External applications connecting to user storage
- Backup scripts
- Monitoring tools
- Development environments

---

## Container Management

### Automatic Cleanup

The scripts handle cleanup automatically:

- **Separated containers**: `obp-keycloak`, `keycloak-postgres`, `user-storage-postgres`
- **Networks**: `obp-network` 
- **Volumes**: `keycloak_postgres_data`, `user_storage_postgres_data`

### Manual Cleanup

```bash
# Stop all containers
docker-compose -f docker-compose.runtime.yml down

# Remove with volumes (careful: deletes data)
docker-compose -f docker-compose.runtime.yml down -v

# Interactive management
./sh/manage-container.sh
```

---

## Health Checks

### Application Health
```bash
# Keycloak health endpoint
curl -f http://localhost:8000/health/ready

# Database connectivity
docker exec -it keycloak-postgres pg_isready -U keycloak
docker exec -it user-storage-postgres pg_isready -U obp
```

### Container Status
```bash
# Check all containers
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

# Detailed health status
docker inspect obp-keycloak | grep -A 5 "Health"
```

## Troubleshooting

### Common Issues (Recently Fixed)

1. **UnknownHostException: keycloak-postgres** ✅ RESOLVED
   - Fixed malformed KC_DB_URL in docker-compose files

2. **Port 5432 already in use** ✅ RESOLVED  
   - Changed user storage to port 5434

3. **SQL syntax errors** ✅ RESOLVED
   - Fixed database initialization script

### Quick Diagnostics

```bash
# Comprehensive validation
./sh/validate-separated-db-config.sh

# Check recent fixes applied
grep "KC_DB_URL.*keycloak-postgres" docker-compose.runtime.yml
grep "USER_STORAGE_DB_PORT:-5434" docker-compose.runtime.yml

# View container logs
docker logs obp-keycloak --tail 50
```

## Documentation Links

- **[Main README](../README.md)** - Project overview and setup
- **[Troubleshooting](../docs/TROUBLESHOOTING.md)** - Common issues and recent fixes
- **[Cloud Native](../docs/CLOUD_NATIVE.md)** - Kubernetes and Docker Hub deployment
- **[Environment](../docs/ENVIRONMENT.md)** - Configuration reference

**Note**: Ensure you have the latest version (`git pull origin main`) to benefit from recent critical fixes.