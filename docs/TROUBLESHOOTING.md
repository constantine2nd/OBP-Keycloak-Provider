# Troubleshooting Guide

This guide helps you diagnose and resolve common issues with the OBP Keycloak Provider, particularly focusing on Database Separation Migration problems.

## 🔧 Recent Critical Fixes

**Latest Update**: The following critical issues have been resolved in the current version:

1. **✅ Fixed JDBC URL Configuration**
   - **Issue**: `KC_DB_URL` had malformed default value `"keycloak"` 
   - **Fix**: Corrected to `"jdbc:postgresql://keycloak-postgres:5432/keycloak"`
   - **Impact**: Resolves `UnknownHostException: keycloak-postgres` errors

2. **✅ Resolved Port Conflicts**
   - **Issue**: User storage database conflicted with system PostgreSQL on port 5432
   - **Fix**: Changed to port 5434 externally
   - **Impact**: Eliminates "port already in use" errors

3. **✅ Fixed SQL Syntax Error**
   - **Issue**: Incomplete SQL statement in database initialization script
   - **Fix**: Removed malformed `insert into users` line
   - **Impact**: Database initialization now completes successfully

4. **✅ Updated Documentation**
   - **Issue**: Outdated port references and configuration examples
   - **Fix**: All documentation updated to reflect correct configuration
   - **Impact**: Consistent and accurate setup instructions

## 🚨 Common Error Scenarios

### 1. UnknownHostException: keycloak-postgres

**Error Message:**
```
java.net.UnknownHostException: keycloak-postgres
```

**Status:** ✅ **RESOLVED** in latest version

**Root Cause:** Malformed `KC_DB_URL` environment variable

**Solution:** 
```bash
# Ensure you have the latest version
git pull origin main

# Verify the fix is applied
grep "KC_DB_URL.*keycloak-postgres" docker-compose.runtime.yml
# Should show: KC_DB_URL: ${KC_DB_URL:-jdbc:postgresql://keycloak-postgres:5432/keycloak}

# Restart containers
docker-compose -f docker-compose.runtime.yml down
docker-compose -f docker-compose.runtime.yml up
```

### 2. Port Already in Use Errors

**Error Message:**
```
Error starting userland proxy: listen tcp4 0.0.0.0:5432: bind: address already in use
```

**Status:** ✅ **RESOLVED** in latest version

**Root Cause:** Conflict with system PostgreSQL installation

**Solution:**
```bash
# Check if you have the latest port configuration
grep "USER_STORAGE_DB_PORT" docker-compose.runtime.yml
# Should show: - "${USER_STORAGE_DB_PORT:-5434}:5432"

# If not updated, pull latest changes
git pull origin main

# Restart with correct ports
docker-compose -f docker-compose.runtime.yml down
export USER_STORAGE_DB_PORT=5434
docker-compose -f docker-compose.runtime.yml up
```

### 3. SQL Syntax Errors During Database Initialization

**Error Message:**
```
psql:/docker-entrypoint-initdb.d/script.sql:27: ERROR: syntax error at or near "INSERT"
```

**Status:** ✅ **RESOLVED** in latest version

**Root Cause:** Incomplete SQL statement in `sql/script.sql`

**Solution:**
```bash
# Verify the fix is applied
grep -n "insert into users" sql/script.sql
# Should return nothing (line was removed)

# Clean restart with fixed SQL
docker-compose -f docker-compose.runtime.yml down -v
docker-compose -f docker-compose.runtime.yml up
```

### 4. Container Name Conflicts

**Error Message:**
```
Conflict. The container name "/obp-keycloak" is already in use
```

**Solution:**
```bash
# Remove existing containers
docker rm -f obp-keycloak keycloak-postgres user-storage-postgres

# Or use the management script
./sh/manage-container.sh
# Select option to stop and remove containers
```

### 5. Environment Variable Issues

**Error Message:**
```
Required environment variable 'KC_DB_URL' is not set
```

**Solution:**
```bash
# Copy environment template
cp env.sample .env

# Edit with your values
nano .env

# Validate configuration
./sh/validate-separated-db-config.sh

# Run with local PostgreSQL
./sh/run-local-postgres.sh --themed --validate
```

## 🔍 Diagnostic Commands

### Quick Health Check
```bash
# Check all containers status
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

# Verify database connections
docker exec -it keycloak-postgres psql -U keycloak -d keycloak -c "SELECT version();"
docker exec -it user-storage-postgres psql -U obp -d obp_mapped -c "SELECT version();"

# Check Keycloak application logs
docker logs obp-keycloak --tail 50
```

### Port Availability Check
```bash
# Check if required ports are available
ss -tulpn | grep -E ":(5433|5434|8000|8443)"

# Or using netstat
netstat -tulpn | grep -E ":(5433|5434|8000|8443)"
```

### Configuration Validation
```bash
# Run comprehensive validation
./sh/validate-separated-db-config.sh

# Check environment variables
docker exec -it obp-keycloak printenv | grep -E "(KC_DB|DB_)"

# Compare with examples
./sh/compare-env.sh
```

### Database Connection Testing
```bash
# Test Keycloak database connection
docker exec -it keycloak-postgres psql -U keycloak -d keycloak -c "\l"

# Test user storage database connection
docker exec -it user-storage-postgres psql -U obp -d obp_mapped -c "\dt"

# Verify table structure
docker exec -it user-storage-postgres psql -U obp -d obp_mapped -c "\d authuser"
```

## 🛠️ Step-by-Step Troubleshooting

### If Keycloak Won't Start

1. **Check container logs:**
   ```bash
   docker logs obp-keycloak | grep -i error
   ```

2. **Verify database connectivity:**
   ```bash
   docker exec -it obp-keycloak ping keycloak-postgres
   docker exec -it obp-keycloak ping user-storage-postgres
   ```

3. **Test environment variables:**
   ```bash
   docker exec -it obp-keycloak env | grep -E "(KC_DB|DB_)"
   ```

4. **Check network connectivity:**
   ```bash
   docker network inspect obp-keycloak-provider_obp-network
   ```

### If Database Connection Fails

1. **Verify database containers are healthy:**
   ```bash
   docker inspect keycloak-postgres | grep "Health"
   docker inspect user-storage-postgres | grep "Health"
   ```

2. **Check database logs:**
   ```bash
   docker logs keycloak-postgres | tail -20
   docker logs user-storage-postgres | tail -20
   ```

3. **Test direct connection:**
   ```bash
   psql -h localhost -p 5433 -U keycloak -d keycloak
   psql -h localhost -p 5434 -U obp -d obp_mapped
   ```

### If Port Conflicts Persist

1. **Identify what's using the ports:**
   ```bash
   sudo lsof -i :5432
   sudo lsof -i :5433
   sudo lsof -i :5434
   ```

2. **Stop conflicting services:**
   ```bash
   # For system PostgreSQL
   sudo systemctl stop postgresql
   
   # For other containers
   docker ps | grep postgres
   docker stop <container-name>
   ```

3. **Use alternative ports:**
   ```bash
   export KC_DB_PORT=15433
   export USER_STORAGE_DB_PORT=15434
   docker-compose -f docker-compose.runtime.yml up
   ```

## 🔧 Advanced Troubleshooting

### Container Network Issues

```bash
# Inspect Docker network
docker network ls
docker network inspect obp-keycloak-provider_obp-network

# Test connectivity between containers
docker exec -it obp-keycloak nslookup keycloak-postgres
docker exec -it obp-keycloak telnet keycloak-postgres 5432
```

### Database Schema Issues

```bash
# Check if tables exist
docker exec -it keycloak-postgres psql -U keycloak -d keycloak -c "\dt" | head -10
docker exec -it user-storage-postgres psql -U obp -d obp_mapped -c "\dt"

# Verify Keycloak schema
docker exec -it keycloak-postgres psql -U keycloak -d keycloak -c "SELECT count(*) FROM information_schema.tables WHERE table_schema = 'public';"

# Check user table structure
docker exec -it user-storage-postgres psql -U obp -d obp_mapped -c "\d authuser"
```

### Environment Variable Debugging

```bash
# Show all environment variables in container
docker exec -it obp-keycloak env | sort

# Verify specific database configuration
docker exec -it obp-keycloak bash -c 'echo "KC_DB_URL: $KC_DB_URL"'
docker exec -it obp-keycloak bash -c 'echo "DB_URL: $DB_URL"'

# Check if variables are properly set
./sh/validate-separated-db-config.sh > validation_report.txt 2>&1
```

## 📋 Validation Checklist

Before reporting issues, verify:

- [ ] **Latest Version**: `git pull origin main` completed
- [ ] **Fixed Configuration**: `KC_DB_URL` contains full JDBC URL
- [ ] **Correct Ports**: User storage on 5434, Keycloak DB on 5433
- [ ] **Clean SQL**: No syntax errors in `sql/script.sql`
- [ ] **Environment Setup**: `.env` file exists and configured
- [ ] **Port Availability**: No conflicts on required ports
- [ ] **Validation Passed**: `./sh/validate-separated-db-config.sh` succeeds
- [ ] **Containers Healthy**: All containers show "healthy" status
- [ ] **Network Connectivity**: Containers can communicate
- [ ] **Database Access**: Manual connections work

## 🆘 Getting Help

### Information to Include When Reporting Issues

1. **System Information:**
   ```bash
   uname -a
   docker --version
   docker-compose --version
   ```

2. **Container Status:**
   ```bash
   docker ps -a
   docker logs obp-keycloak --tail 100
   ```

3. **Configuration:**
   ```bash
   # Sanitized environment (remove passwords)
   ./sh/validate-separated-db-config.sh
   ```

4. **Network Information:**
   ```bash
   docker network ls
   ss -tulpn | grep -E ":(5433|5434|8000|8443)"
   ```

### Support Resources

- **Migration Guide**: [DATABASE_SEPARATION_MIGRATION.md](DATABASE_SEPARATION_MIGRATION.md)
- **Cloud Native Guide**: [CLOUD_NATIVE.md](CLOUD_NATIVE.md)
- **Environment Reference**: [ENVIRONMENT.md](ENVIRONMENT.md)
- **Main Documentation**: [README.md](../README.md)

### Quick Recovery Commands

```bash
# Complete reset and restart
docker-compose -f docker-compose.runtime.yml down -v
docker system prune -f
git pull origin main
cp env.sample .env
# Edit .env with your values
./sh/validate-separated-db-config.sh
docker-compose -f docker-compose.runtime.yml up
```

## 🔄 Version Compatibility

### Current Version (Latest)
- ✅ Fixed JDBC URL configuration
- ✅ Resolved port conflicts
- ✅ Fixed SQL syntax errors
- ✅ Updated documentation

### Upgrading from Previous Versions

```bash
# Pull latest changes
git pull origin main

# Update environment file
cp env.sample .env.new
# Merge your settings from old .env

# Clean restart
docker-compose -f docker-compose.runtime.yml down -v
docker-compose -f docker-compose.runtime.yml up
```

## 📊 Performance Troubleshooting

### Slow Startup Issues

```bash
# Check resource usage
docker stats obp-keycloak keycloak-postgres user-storage-postgres

# Monitor logs during startup
docker logs -f obp-keycloak | grep -E "(INFO|WARN|ERROR)"

# Check database performance
docker exec -it keycloak-postgres psql -U keycloak -d keycloak -c "SELECT version(), current_setting('shared_buffers');"
```

### Memory Issues

```bash
# Check container memory limits
docker inspect obp-keycloak | grep -i memory

# Monitor memory usage
docker exec -it obp-keycloak cat /proc/meminfo

# Adjust container resources if needed
docker run --memory=2g --cpus=2 ...
```

Remember: Most common issues have been resolved in the latest version. Always ensure you have the most recent updates before troubleshooting!