# Database Separation Migration Guide

This guide helps you migrate from the previous single-database setup to the new separated database architecture where Keycloak's internal database is separate from the user storage database.

## 🔧 Recent Fixes (Latest Update)

**Critical issues resolved in the latest version:**

1. **✅ Fixed JDBC URL Configuration**: Corrected malformed `KC_DB_URL` default value in `docker-compose.runtime.yml`
2. **✅ Resolved Port Conflicts**: Changed user-storage-postgres to port 5434 to avoid conflicts with system PostgreSQL
3. **✅ Fixed SQL Syntax Error**: Removed incomplete SQL statement in database initialization script
4. **✅ Updated Documentation**: All guides now reflect the correct port configuration

**If you're experiencing connection issues, these fixes should resolve them!**

## Overview

### Previous Architecture (Single Database)
- Keycloak and user storage shared the same PostgreSQL database
- Single set of database credentials (`DB_URL`, `DB_USER`, `DB_PASSWORD`)
- Potential conflicts and security concerns

### New Architecture (Separated Databases)
- **Keycloak Internal Database**: Stores realms, clients, tokens, sessions (Port 5433)
- **User Storage Database**: Contains external user data for federation (Port 5434)
- Clear separation of concerns and improved security
- **Fixed Configuration**: Recent updates resolve common connection issues

## Migration Steps

### Step 1: Backup Your Data

Before starting the migration, create backups of your existing data:

```bash
# Backup existing database
pg_dump -h localhost -U obp -d obp_mapped > backup_$(date +%Y%m%d_%H%M%S).sql

# If you have Keycloak data in the same database, back it up separately
pg_dump -h localhost -U obp -d obp_mapped -t keycloak_* > keycloak_backup_$(date +%Y%m%d_%H%M%S).sql
```

### Step 2: Update Environment Variables

Replace your existing environment variables:

#### Old Configuration (.env)
```properties
# Old single database configuration
DB_URL=jdbc:postgresql://localhost:5432/obp_mapped
DB_USER=obp
DB_PASSWORD=your_password
KC_BOOTSTRAP_ADMIN_USERNAME=admin
KC_BOOTSTRAP_ADMIN_PASSWORD=admin_password
```

#### New Configuration (.env)
```properties
# Keycloak Admin Configuration
KEYCLOAK_ADMIN=admin
KEYCLOAK_ADMIN_PASSWORD=admin_password

# Keycloak's Internal Database
KC_DB_USERNAME=keycloak
KC_DB_PASSWORD=secure_keycloak_password
KC_DB_PORT=5433

# User Storage Database (your existing data)
USER_STORAGE_DB_USER=obp
USER_STORAGE_DB_PASSWORD=your_existing_password
USER_STORAGE_DB_PORT=5434  # Changed from 5432 to avoid conflicts

# These are auto-mapped from the above
DB_USER=${USER_STORAGE_DB_USER}
DB_PASSWORD=${USER_STORAGE_DB_PASSWORD}
DB_DRIVER=org.postgresql.Driver
DB_DIALECT=org.hibernate.dialect.PostgreSQLDialect
```

### Step 3: Update Docker Compose Configuration

#### Option A: Using Updated docker-compose.runtime.yml (Recommended)

If you're using the provided Docker Compose files:

```bash
# Pull latest changes (includes recent fixes)
git pull origin main

# Copy your environment variables
cp env.sample .env
# Edit .env with your actual values

# Validate your configuration (recommended)
./sh/validate-separated-db-config.sh

# Start with new separated databases
docker-compose -f docker-compose.runtime.yml up
```

**Recent Fix**: The `KC_DB_URL` configuration has been corrected and port conflicts resolved.

#### Option B: Manually Update Your Existing docker-compose.yml

Add the new Keycloak database service:

```yaml
version: '3.8'

services:
  # NEW: Keycloak's internal database
  keycloak-postgres:
    image: postgres:16-alpine
    container_name: keycloak-postgres
    environment:
      POSTGRES_DB: keycloak
      POSTGRES_USER: keycloak
      POSTGRES_PASSWORD: ${KC_DB_PASSWORD}
    ports:
      - "${KC_DB_PORT:-5433}:5432"
    volumes:
      - keycloak_postgres_data:/var/lib/postgresql/data
    networks:
      - your-network

  # EXISTING: Rename and update your user storage database
  user-storage-postgres:  # Renamed from 'postgres'
    image: postgres:16-alpine
    container_name: user-storage-postgres  # Renamed
    environment:
      POSTGRES_DB: obp_mapped
      POSTGRES_USER: ${USER_STORAGE_DB_USER}
      POSTGRES_PASSWORD: ${USER_STORAGE_DB_PASSWORD}
    ports:
      - "${USER_STORAGE_DB_PORT:-5434}:5432"  # Updated port to avoid conflicts
    # Keep your existing configuration...

  keycloak:
    # ... existing configuration ...
    environment:
      # NEW: Keycloak's internal database
      KC_DB: postgres
      KC_DB_URL: jdbc:postgresql://keycloak-postgres:5432/keycloak
      KC_DB_USERNAME: ${KC_DB_USERNAME}
      KC_DB_PASSWORD: ${KC_DB_PASSWORD}
      
      # EXISTING: User storage database (updated service name)
      DB_URL: jdbc:postgresql://user-storage-postgres:5432/obp_mapped
      DB_USER: ${DB_USER}
      DB_PASSWORD: ${DB_PASSWORD}
      # ... rest of your config ...

volumes:
  keycloak_postgres_data:  # NEW volume
  user_storage_postgres_data:  # Renamed from postgres_data
```

### Step 4: Data Migration (If Needed)

If your existing database contains Keycloak data mixed with user data:

```bash
# 1. Start only the databases
docker-compose -f docker-compose.runtime.yml up keycloak-postgres user-storage-postgres -d

# 2. If you have Keycloak data in your existing database, migrate it
# (This step is only needed if Keycloak was using the same database)

# Export Keycloak tables from old database
pg_dump -h localhost -p 5432 -U obp -d obp_mapped \
  --table=keycloak_* --table=realm* --table=client* \
  --data-only --no-owner > keycloak_data_export.sql

# Import to new Keycloak database
psql -h localhost -p 5433 -U keycloak -d keycloak -f keycloak_data_export.sql

# 3. Start Keycloak
docker-compose -f docker-compose.runtime.yml up keycloak
```

### Step 5: Verify Migration

1. **Check Database Connections**:
   ```bash
   # Check Keycloak database
   docker exec -it keycloak-postgres psql -U keycloak -d keycloak -c "\dt"
   
   # Check user storage database
   docker exec -it user-storage-postgres psql -U obp -d obp_mapped -c "\dt"
   ```

2. **Verify Keycloak Startup**:
   ```bash
   docker logs obp-keycloak | grep -i "database"
   ```

3. **Test Authentication**:
   - Access Keycloak admin console: http://localhost:8080/admin
   - Log in with your admin credentials
   - Verify user federation is working

### Step 6: Update Application Configuration

If you have external applications connecting to the databases:

#### Keycloak Database (Internal Use Only)
- **Host**: localhost
- **Port**: 5433
- **Database**: keycloak
- **Username**: keycloak
- **Note**: Only Keycloak should connect to this database

#### User Storage Database
- **Host**: localhost  
- **Port**: 5434 (changed from 5432 to avoid conflicts)
- **Database**: obp_mapped (unchanged)
- **Username**: obp (unchanged)
- **Note**: Update your existing applications to use the new port 5434

## Troubleshooting

### Common Issues

#### 1. Port Conflicts (RESOLVED)
```bash
# This issue has been fixed in the latest version
# User storage database now uses port 5434 by default
# If you still have conflicts, check what's using the ports:
sudo netstat -tulpn | grep :5434
sudo netstat -tulpn | grep :5433

# If system PostgreSQL is running on 5432, it won't conflict anymore
sudo systemctl status postgresql  # Check system PostgreSQL status
```

#### 2. Connection Refused
```bash
# Check if containers are running
docker ps | grep postgres

# Check container logs
docker logs keycloak-postgres
docker logs user-storage-postgres

# Verify network connectivity
docker exec -it obp-keycloak ping keycloak-postgres
```

#### 3. Authentication Failed
```bash
# Check environment variables
docker exec -it obp-keycloak printenv | grep -E "(KC_DB|DB_)"

# Test database connection manually
docker exec -it keycloak-postgres psql -U keycloak -d keycloak -c "SELECT version();"
```

#### 4. Keycloak Won't Start
```bash
# Check Keycloak logs for database errors
docker logs obp-keycloak | grep -i error

# Verify database schema
docker exec -it keycloak-postgres psql -U keycloak -d keycloak -c "\dt" | head -20
```

## Troubleshooting Recent Issues

### Issue: UnknownHostException: keycloak-postgres
**Status**: ✅ RESOLVED in latest version

**Cause**: Malformed `KC_DB_URL` environment variable in docker-compose.runtime.yml
**Fix**: Updated default value from `"keycloak"` to `"jdbc:postgresql://keycloak-postgres:5432/keycloak"`

### Issue: Port 5432 already in use
**Status**: ✅ RESOLVED in latest version

**Cause**: Conflict with system PostgreSQL installation
**Fix**: Changed user-storage-postgres to use port 5434 externally

### Issue: SQL syntax error in initialization
**Status**: ✅ RESOLVED in latest version

**Cause**: Incomplete SQL statement in script.sql
**Fix**: Removed malformed `insert into users` line

## Rollback Procedure

If you need to rollback to the single database setup:

1. **Stop all containers**:
   ```bash
   docker-compose -f docker-compose.runtime.yml down
   ```

2. **Restore your backup**:
   ```bash
   # Restore from backup created in Step 1
   psql -h localhost -p 5434 -U obp -d obp_mapped < backup_YYYYMMDD_HHMMSS.sql
   ```

3. **Use old configuration**:
   - Revert your `.env` file to the old format
   - Use the old docker-compose configuration

## Benefits of Separated Databases

### Security
- **Principle of Least Privilege**: Each database has specific access patterns
- **Credential Isolation**: Compromise of one database doesn't affect the other
- **Audit Trail**: Clear separation of access logs

### Performance
- **Resource Isolation**: Each database can be tuned for its specific workload
- **Scaling**: Databases can be scaled independently
- **Backup Strategy**: Different backup schedules and retention policies

### Maintenance
- **Clear Boundaries**: No confusion about which data belongs where
- **Independent Updates**: User storage updates don't affect Keycloak
- **Testing**: Easier to test with separate data sets

## Production Considerations

### Database Hosting
- **Managed Services**: Consider AWS RDS, Google Cloud SQL, or Azure Database
- **High Availability**: Set up read replicas and failover
- **Monitoring**: Implement separate monitoring for each database

### Security
- **Network Isolation**: Use private networks in production
- **Encryption**: Enable TLS for database connections
- **Access Control**: Use different credentials for different environments

### Backup Strategy
```bash
# Automated backup script example
#!/bin/bash
DATE=$(date +%Y%m%d_%H%M%S)

# Backup Keycloak database (port 5433)
pg_dump -h localhost -p 5433 -U keycloak keycloak > "keycloak_backup_$DATE.sql"

# Backup User Storage database (port 5434)
pg_dump -h localhost -p 5434 -U obp obp_mapped > "user_storage_backup_$DATE.sql"

# Upload to cloud storage
aws s3 cp keycloak_backup_$DATE.sql s3://your-backup-bucket/keycloak/
aws s3 cp user_storage_backup_$DATE.sql s3://your-backup-bucket/user-storage/
```

## Support

If you encounter issues during migration:

1. **Run the validation script**: `./sh/validate-separated-db-config.sh`
2. **Check the logs**: `docker logs obp-keycloak`
3. **Verify port availability**: `ss -tulpn | grep :5434` and `ss -tulpn | grep :5433`
4. **Check for recent fixes**: Ensure you have the latest version with the resolved issues
5. **Review documentation**: [CLOUD_NATIVE.md](CLOUD_NATIVE.md), [README.md](../README.md)
6. **Create an issue**: Include logs, configuration, and steps to reproduce

### Quick Validation Commands
```bash
# Validate complete configuration
./sh/validate-separated-db-config.sh

# Check database connections
docker exec -it keycloak-postgres psql -U keycloak -d keycloak -c "SELECT version();"
docker exec -it user-storage-postgres psql -U obp -d obp_mapped -c "SELECT version();"

# Verify container status
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
```

## Next Steps

After successful migration:

1. **Update monitoring**: Add monitoring for both databases
2. **Update backup procedures**: Ensure both databases are backed up
3. **Review security**: Audit database access and credentials
4. **Test failover**: Verify recovery procedures work with separated databases
5. **Update documentation**: Document your specific configuration for your team