# Local PostgreSQL Setup Guide

This guide explains how to run the OBP Keycloak Provider with existing local PostgreSQL instances instead of Docker Compose databases. This approach is ideal for development environments where you already have PostgreSQL configured.

## 🗄️ Database Architecture

This setup uses **two separate local PostgreSQL databases**:

1. **Keycloak Internal Database** (`keycloakdb`)
   - **Purpose**: Stores Keycloak's realm data, users, clients, tokens, sessions
   - **Connection**: `jdbc:postgresql://localhost:5432/keycloakdb`
   - **User**: `keycloak` / Password: `f`

2. **User Storage Database** (`obp_mapped`)
   - **Purpose**: Contains external user data for federation
   - **Connection**: `jdbc:postgresql://localhost:5432/obp_mapped`  
   - **User**: `obp` / Password: `f`

## 📋 Prerequisites

### Required Software
- **PostgreSQL** 12+ running locally on port 5432
- **Docker** 20+ for running Keycloak container
- **Maven** 3.8+ for building the project
- **Java** 17+ for Maven compilation

### Database Requirements
- Two PostgreSQL databases: `keycloakdb` and `obp_mapped`
- Two database users with appropriate permissions
- PostgreSQL service running and accessible

## 🚀 Quick Start

### 1. Verify Database Setup

```bash
# Test Keycloak database connection
PGPASSWORD=f psql -h localhost -p 5432 -U keycloak -d keycloakdb -c "SELECT version();"

# Test User Storage database connection  
PGPASSWORD=f psql -h localhost -p 5432 -U obp -d obp_mapped -c "SELECT version();"
```

### 2. Configure Environment

```bash
# Copy local configuration template
cp .env.local .env

# Verify configuration
cat .env
```

### 3. Run with Local PostgreSQL

```bash
# Standard deployment
./sh/run-local-postgres.sh --test --validate

# Themed deployment with custom UI
./sh/run-local-postgres.sh --themed --test --validate
```

### 4. Access Application

- **HTTP**: http://localhost:8000
- **HTTPS**: https://localhost:8443
- **Admin Console**: https://localhost:8443/admin
- **Login**: admin / admin

## 🛠️ Detailed Setup Instructions

### Step 1: Database Creation

If you don't have the required databases, create them:

```sql
-- Connect as PostgreSQL superuser
sudo -u postgres psql

-- Create Keycloak database and user
CREATE DATABASE keycloakdb;
CREATE USER keycloak WITH PASSWORD 'f';
GRANT ALL PRIVILEGES ON DATABASE keycloakdb TO keycloak;
GRANT ALL ON SCHEMA public TO keycloak;

-- Create User Storage database and user
CREATE DATABASE obp_mapped;
CREATE USER obp WITH PASSWORD 'f';
GRANT ALL PRIVILEGES ON DATABASE obp_mapped TO obp;
GRANT ALL ON SCHEMA public TO obp;

-- Exit PostgreSQL
\q
```

### Step 2: User Storage Table Setup

The User Storage database needs the `authuser` table for user federation:

> **⚠️ CRITICAL**: The `authuser` table is **READ-ONLY** for the Keycloak User Storage Provider and must be created by a database administrator with appropriate permissions. The Keycloak setup scripts cannot create this table due to read-only access restrictions.

> **📋 SETUP REQUIREMENT**: The authuser table must exist before running Keycloak. INSERT, UPDATE, and DELETE operations are not supported through Keycloak. Users must be managed through other means outside of Keycloak.

```sql
-- ===============================================
-- DATABASE ADMINISTRATOR SETUP REQUIRED
-- ===============================================
-- This SQL must be executed by a database administrator
-- with CREATE privileges on the obp_mapped database.
-- The Keycloak application has READ-ONLY access only.

-- Connect as database administrator (NOT as obp user)
-- Example: sudo -u postgres psql -d obp_mapped

-- Create authuser table (READ-ONLY for Keycloak)
CREATE TABLE IF NOT EXISTS public.authuser (
    id bigserial NOT NULL,
    firstname varchar(100) NULL,
    lastname varchar(100) NULL,
    email varchar(100) NULL,
    username varchar(100) NULL,
    password_pw varchar(48) NULL,
    password_slt varchar(20) NULL,
    provider varchar(100) NULL,
    locale varchar(16) NULL,
    validated bool NULL,
    user_c int8 NULL,
    createdat timestamp NULL,
    updatedat timestamp NULL,
    timezone varchar(32) NULL,
    superuser bool NULL,
    passwordshouldbechanged bool NULL,
    CONSTRAINT authuser_pk PRIMARY KEY (id)
);

-- Create indexes
CREATE INDEX IF NOT EXISTS authuser_user_c ON public.authuser USING btree (user_c);
CREATE UNIQUE INDEX IF NOT EXISTS authuser_username_provider ON public.authuser USING btree (username, provider);

-- Grant READ-ONLY access to obp user
GRANT SELECT ON public.authuser TO obp;
GRANT USAGE ON SEQUENCE authuser_id_seq TO obp;

-- Verify table creation
\d authuser
SELECT count(*) FROM authuser;

-- ===============================================
-- KEYCLOAK PROVIDER LIMITATIONS
-- ===============================================
-- ✅ User authentication and login
-- ✅ User profile viewing  
-- ✅ Password validation
-- 🔴 User creation (disabled - read-only table)
-- 🔴 User profile updates (disabled - read-only table)
-- 🔴 User deletion (disabled - read-only table)

-- NOTE: Users must be added to authuser table through external
-- applications or database administration tools outside of Keycloak.
-- The Keycloak provider only supports reading existing users.
```

### Step 3: Environment Configuration

Create `.env.local` with your database configuration:

```bash
# Copy the template
cp .env.local .env

# Edit configuration if needed
nano .env
```

**Key configuration values**:
```properties
# Keycloak Admin
KEYCLOAK_ADMIN=admin
KEYCLOAK_ADMIN_PASSWORD=admin

# Keycloak Database (Local PostgreSQL)
KC_DB=postgres
KC_DB_URL=jdbc:postgresql://localhost:5432/keycloakdb
KC_DB_USERNAME=keycloak
KC_DB_PASSWORD=f

# User Storage Database (Local PostgreSQL)
DB_URL=jdbc:postgresql://localhost:5432/obp_mapped
DB_USER=obp
DB_PASSWORD=f
DB_DRIVER=org.postgresql.Driver
DB_DIALECT=org.hibernate.dialect.PostgreSQLDialect

# Configuration
HIBERNATE_DDL_AUTO=validate
KC_HTTP_ENABLED=true
KC_HOSTNAME_STRICT=false
```

### Step 4: Build and Run

```bash
# Make script executable
chmod +x sh/run-local-postgres.sh

# Test database connections
./sh/run-local-postgres.sh --test

# Run with validation
./sh/run-local-postgres.sh --validate

# Force rebuild if needed
./sh/run-local-postgres.sh --build

# Themed deployment
./sh/run-local-postgres.sh --themed --validate
```

## 🎨 Theme Configuration (Optional)

For custom OBP theme deployment:

### 1. Run Themed Deployment
```bash
./sh/run-local-postgres.sh --themed --validate
```

### 2. Activate Theme in Admin Console
1. Go to https://localhost:8443/admin
2. Login with admin/admin
3. Navigate to: **Realm Settings** → **Themes**
4. Set **Login Theme** to: `obp`
5. Click **Save**

### 3. Test Custom Theme
- Logout from admin console
- Visit login page to see custom OBP theme
- Features: Dark UI, modern styling, OBP branding

## 🔧 Script Options

### Available Commands

```bash
# Basic usage
./sh/run-local-postgres.sh [OPTIONS]

# Options:
--themed, -t     # Build with custom themes
--build, -b      # Force rebuild of Docker image  
--test, -x       # Test database connections first
--validate, -v   # Validate configuration and setup
--help, -h       # Show help message
```

### Usage Examples

```bash
# Standard deployment
./sh/run-local-postgres.sh

# Test connections before starting
./sh/run-local-postgres.sh --test

# Themed deployment with validation
./sh/run-local-postgres.sh --themed --validate

# Force rebuild and start
./sh/run-local-postgres.sh --build

# Complete setup with all checks
./sh/run-local-postgres.sh --themed --test --validate --build
```

## 🔍 Testing and Validation

### Database Connection Tests

```bash
# Test Keycloak database
PGPASSWORD=f psql -h localhost -p 5432 -U keycloak -d keycloakdb -c "\l"

# Test User Storage database
PGPASSWORD=f psql -h localhost -p 5432 -U obp -d obp_mapped -c "\dt"

# Check authuser table
PGPASSWORD=f psql -h localhost -p 5432 -U obp -d obp_mapped -c "SELECT count(*) FROM authuser;"
```

### Application Health Checks

```bash
# Check container status
docker ps --filter "name=obp-keycloak-local"

# Test HTTP endpoint
curl -f http://localhost:8000/health/ready

# Test HTTPS endpoint  
curl -k https://localhost:8443/health/ready

# View application logs
docker logs -f obp-keycloak-local
```

### User Federation Testing

```bash
# Check user storage provider in admin console
# 1. Go to https://localhost:8443/admin
# 2. Navigate to: User Federation
# 3. Verify "obp-keycloak-provider" is listed
# 4. Test user sync and authentication
```

## 🛠️ Container Management

### Container Operations

```bash
# View logs
docker logs -f obp-keycloak-local

# Stop container
docker stop obp-keycloak-local

# Start container  
docker start obp-keycloak-local

# Restart container
docker restart obp-keycloak-local

# Remove container
docker rm obp-keycloak-local

# Stop and remove
docker stop obp-keycloak-local && docker rm obp-keycloak-local
```

### Database Operations

```bash
# Connect to Keycloak database
PGPASSWORD=f psql -h localhost -p 5432 -U keycloak -d keycloakdb

# Connect to User Storage database
PGPASSWORD=f psql -h localhost -p 5432 -U obp -d obp_mapped

# Backup databases
pg_dump -h localhost -p 5432 -U keycloak keycloakdb > keycloak_backup.sql
pg_dump -h localhost -p 5432 -U obp obp_mapped > user_storage_backup.sql

# Restore databases
psql -h localhost -p 5432 -U keycloak -d keycloakdb < keycloak_backup.sql
psql -h localhost -p 5432 -U obp -d obp_mapped < user_storage_backup.sql
```

## 🐛 Troubleshooting

### Common Issues

#### 1. Database Connection Failed

**Error**: `Connection attempt failed` or `JDBC connection error`

**Solutions**:
```bash
# Check PostgreSQL is running
sudo systemctl status postgresql

# Start PostgreSQL if stopped
sudo systemctl start postgresql

# Verify databases exist
sudo -u postgres psql -l | grep -E "(keycloakdb|obp_mapped)"

# Test connections manually
PGPASSWORD=f psql -h localhost -p 5432 -U keycloak -d keycloakdb
PGPASSWORD=f psql -h localhost -p 5432 -U obp -d obp_mapped
```

#### 2. Permission Denied

**Error**: `FATAL: permission denied for database`

**Solutions**:
```sql
-- Connect as PostgreSQL superuser
sudo -u postgres psql

-- Grant permissions
GRANT ALL PRIVILEGES ON DATABASE keycloakdb TO keycloak;
GRANT ALL PRIVILEGES ON DATABASE obp_mapped TO obp;
GRANT ALL ON SCHEMA public TO keycloak;
GRANT ALL ON SCHEMA public TO obp;
```

#### 3. Table Does Not Exist

**Error**: `relation "authuser" does not exist`

**Solutions**:
```bash
# Run script with validation (creates table automatically)
./sh/run-local-postgres.sh --validate

# Or create manually
PGPASSWORD=f psql -h localhost -p 5432 -U obp -d obp_mapped -f sql/script.sql
```

#### 4. Container Cannot Connect to Host

**Error**: `UnknownHostException: host.docker.internal`

**Solutions**:
```bash
# For Linux, add host mapping
docker run --add-host=host.docker.internal:host-gateway ...

# Or use direct IP
DB_URL=jdbc:postgresql://172.17.0.1:5432/obp_mapped
```

#### 5. Port Already in Use

**Error**: `bind: address already in use`

**Solutions**:
```bash
# Check what's using the port
sudo lsof -i :8000
sudo lsof -i :8443

# Stop conflicting containers
docker stop $(docker ps -q --filter "publish=8000")

# Use different ports
KEYCLOAK_HTTP_PORT=8001 KEYCLOAK_HTTPS_PORT=8444 ./sh/run-local-postgres.sh
```

### Debugging Commands

```bash
# Check container logs
docker logs obp-keycloak-local --tail 100

# Check PostgreSQL logs
sudo tail -f /var/log/postgresql/postgresql-14-main.log

# Test database connectivity from container
docker exec -it obp-keycloak-local ping host.docker.internal

# Validate environment variables
docker exec -it obp-keycloak-local env | grep -E "(KC_DB|DB_)"

# Check container network
docker network ls
docker inspect bridge
```

## 📊 Performance Considerations

### Database Optimization

```sql
-- Optimize PostgreSQL for development
-- Edit /etc/postgresql/14/main/postgresql.conf

shared_buffers = 256MB
effective_cache_size = 1GB
maintenance_work_mem = 64MB
checkpoint_completion_target = 0.9
wal_buffers = 16MB
default_statistics_target = 100
random_page_cost = 1.1
effective_io_concurrency = 200

-- Restart PostgreSQL
sudo systemctl restart postgresql
```

### Container Resources

```bash
# Run with memory limits
docker run --memory=2g --cpus=2 ...

# Monitor resource usage
docker stats obp-keycloak-local
```

## 🔒 Security Considerations

### Production Recommendations

1. **Change Default Passwords**:
   ```bash
   # Update .env file
   KEYCLOAK_ADMIN_PASSWORD=secure_admin_password
   KC_DB_PASSWORD=secure_keycloak_password  
   DB_PASSWORD=secure_user_storage_password
   ```

2. **Enable HTTPS Only**:
   ```bash
   KC_HTTP_ENABLED=false
   KC_HOSTNAME_STRICT_HTTPS=true
   ```

3. **Database Security**:
   ```sql
   -- Create read-only user for user storage
   CREATE USER obp_readonly WITH PASSWORD 'secure_readonly_password';
   GRANT CONNECT ON DATABASE obp_mapped TO obp_readonly;
   GRANT USAGE ON SCHEMA public TO obp_readonly;
   GRANT SELECT ON ALL TABLES IN SCHEMA public TO obp_readonly;
   ```

4. **Network Security**:
   ```bash
   # Use specific Docker networks
   docker network create obp-network
   docker run --network obp-network ...
   ```

## 📚 Additional Resources

### Related Documentation
- **[Main README](../README.md)** - Project overview
- **[Cloud Native Deployment](CLOUD_NATIVE.md)** - Kubernetes deployment
- **[Troubleshooting Guide](TROUBLESHOOTING.md)** - Common issues

### External Resources
- [PostgreSQL Documentation](https://www.postgresql.org/docs/)
- [Keycloak Documentation](https://www.keycloak.org/documentation)
- [Docker Documentation](https://docs.docker.com/)

## 🎯 Next Steps

After successful deployment:

1. **Configure User Federation**:
   - Access Admin Console → User Federation
   - Verify OBP provider is active
   - Test user synchronization

2. **Customize Themes** (if using themed deployment):
   - Modify theme files in `themes/obp/`
   - Rebuild container with `--build` flag
   - Activate custom theme in admin console

3. **Set Up Monitoring**:
   - Configure log aggregation
   - Set up health check monitoring
   - Monitor database performance

4. **Backup Strategy**:
   - Regular database backups
   - Container image versioning
   - Configuration backup

---

**Note**: This setup is optimized for development environments. For production deployments, consider using managed PostgreSQL services, proper SSL certificates, and enhanced security configurations.