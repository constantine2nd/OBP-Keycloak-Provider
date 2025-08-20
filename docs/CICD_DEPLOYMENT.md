# CI/CD-Style Deployment Guide

This guide covers the new CI/CD-style deployment script that provides predictable, automated deployment suitable for continuous integration environments.

## Overview

The CI/CD deployment script (`sh/run-local-postgres-cicd.sh`) is designed for automated environments where you want:

- **Always build**: No conditional logic - always rebuild everything
- **Always replace**: Stop and remove existing containers every time
- **Cache invalidation**: Docker layers rebuild when JAR file changes
- **Fast feedback**: Clear success/failure indicators
- **Deterministic**: Same inputs always produce same outputs

## Key Differences from Original Script

| Aspect | Original Script | CI/CD Script |
|--------|----------------|--------------|
| Build Strategy | Conditional (--build flag) | Always build |
| Container Handling | Optional replacement | Always stop & remove |
| Cache Strategy | Docker cache reuse | Force rebuild with invalidation |
| Output | Verbose, interactive | Streamlined, pipeline-friendly |
| Error Handling | Continue on some errors | Fail fast on any error |

## Usage

### Basic Deployment
```bash
./sh/run-local-postgres-cicd.sh
```

### Themed Deployment
```bash
./sh/run-local-postgres-cicd.sh --themed
```

## Prerequisites

1. **Local PostgreSQL** running on port 5432
2. **Databases configured**:
   - `keycloakdb` (user: keycloak, password: f)
   - `obp_mapped` (user: obp, password: f)
3. **Environment file**: `.env.local` with proper configuration

## Deployment Pipeline

The script follows an 8-step pipeline:

### [1/8] Environment Validation
- Checks Docker installation and daemon
- Validates Maven installation
- Loads and validates `.env.local` configuration
- Verifies all required environment variables
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
- Uses host.docker.internal for database access
- Maps standard ports (8000 HTTP, 8443 HTTPS)

### [8/8] Health Check
- Waits up to 2 minutes for service readiness
- Tests admin console accessibility
- Provides clear success/failure indication

## Cache Invalidation Strategy

### Problem Solved
Docker caches layers aggressively. Without proper invalidation:
- JAR file changes don't trigger image rebuilds
- Stale code runs in containers
- Inconsistent behavior between deployments

### Solution Implementation
Both Dockerfiles now include:

```dockerfile
# Build arguments for cache invalidation
ARG BUILD_TIMESTAMP
ARG JAR_CHECKSUM

# Cache invalidation layer - forces rebuild when JAR changes
RUN echo "Build timestamp: ${BUILD_TIMESTAMP}" > /tmp/build-info.txt && \
    echo "JAR checksum: ${JAR_CHECKSUM}" >> /tmp/build-info.txt

# Add JAR file - this layer rebuilds when cache is invalidated above
ADD --chown=keycloak:keycloak target/obp-keycloak-provider.jar /opt/keycloak/providers/
```

### How It Works
**How It Works**:
1. Script generates JAR checksum before build
2. Checksum passed as Docker build argument
3. Build argument change invalidates Docker cache
4. All subsequent layers rebuild with new JAR
5. Build info saved in container for debugging

### Theme Validation Strategy

**Themed Deployment Requirements**:
- ✅ `themes/obp/theme.properties` with valid content
- ✅ `themes/obp/login/` directory structure
- ✅ Required templates: `login.ftl`, `template.ftl`
- ✅ `.github/Dockerfile_themed` exists
- ✅ Optional: CSS files, images, message files

**Validation Process**:
```bash
# Theme structure validation
validate_theme_files() {
    # Check Dockerfile exists
    # Validate theme directory structure  
    # Verify theme.properties content
    # Check required template files
    # Validate resources (CSS, images)
    # Check internationalization files
}
```

## Environment Configuration

### Required .env.local Variables
```bash
# Keycloak Admin
KEYCLOAK_ADMIN=admin
KEYCLOAK_ADMIN_PASSWORD=admin

# Keycloak Database
KC_DB_URL=jdbc:postgresql://localhost:5432/keycloakdb
KC_DB_USERNAME=keycloak
KC_DB_PASSWORD=f

# User Storage Database
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

## Monitoring and Troubleshooting

### Deployment Status
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

### Migration Monitoring
```bash
# Monitor migration logs
docker logs obp-keycloak-local -f | grep -E "(MIGRATION|OPTIMAL|LEGACY)"
```

### Build Information
Check container for build details:
```bash
docker exec obp-keycloak-local cat /opt/keycloak/build-info.txt
```

## CI/CD Integration

### GitHub Actions Example
```yaml
name: Deploy OBP Keycloak
on:
  push:
    branches: [ main ]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Setup PostgreSQL
        # ... database setup steps
        
      - name: Deploy Keycloak
        run: ./sh/run-local-postgres-cicd.sh
        
      - name: Run tests
        run: |
          # Wait for service
          timeout 300 bash -c 'until curl -f http://localhost:8000/admin/; do sleep 5; done'
          # Run integration tests
```

### Jenkins Pipeline Example
```groovy
pipeline {
    agent any
    stages {
        stage('Build & Deploy') {
            steps {
                sh './sh/run-local-postgres-cicd.sh'
            }
        }
        stage('Test') {
            steps {
                sh '''
                    timeout 300 bash -c 'until curl -f http://localhost:8000/admin/; do sleep 5; done'
                    # Add your tests here
                '''
            }
        }
    }
    post {
        always {
            sh 'docker logs obp-keycloak-local || true'
        }
    }
}
```

## Performance Considerations

### Build Time
- Initial build: ~2-3 minutes (downloads dependencies)
- Subsequent builds: ~1-2 minutes (cached layers)
- JAR change builds: ~1-2 minutes (invalidated layers)

### Resource Usage
- CPU: High during build, low during runtime
- Memory: ~1GB for container
- Disk: ~500MB per image version

### Optimization Tips
1. Use dedicated build agents with Docker layer caching
2. Pre-pull base images in CI environment
3. Consider multi-stage build optimizations for production

## Comparison with Original Script

### When to Use CI/CD Script
- ✅ Automated deployment pipelines
- ✅ Development environments requiring fresh builds
- ✅ Testing scenarios needing clean state
- ✅ When build consistency is critical

### When to Use Original Script
- ✅ Local development with frequent testing
- ✅ When preserving running state is important
- ✅ Manual debugging sessions
- ✅ Resource-constrained environments

## Migration from Original Script

1. **Update automation**: Replace script calls
   ```bash
   # Old
   ./sh/run-local-postgres.sh --build --themed
   
   # New
   ./sh/run-local-postgres-cicd.sh --themed
   ```

2. **Remove conditional logic**: No need for build flags
3. **Update documentation**: Reference new script in README
4. **Test thoroughly**: Verify CI/CD pipeline compatibility

## Troubleshooting Common Issues

### Database Connection Failures
```bash
# Check PostgreSQL status
sudo systemctl status postgresql

# Test manual connection
PGPASSWORD=f psql -h localhost -p 5432 -U keycloak -d keycloakdb
```

### Docker Build Failures
```bash
# Check Docker space
docker system df

# Clean up if needed
docker system prune -f

# Check build logs
docker build --no-cache -t debug-image -f docker/Dockerfile .
```

### Container Start Issues
```bash
# Check port conflicts
netstat -tulpn | grep -E ':(8000|8443)'

# Review container logs
docker logs obp-keycloak-local

# Themed deployment specific
docker exec obp-keycloak-local ls -la /opt/keycloak/themes/obp/
docker logs obp-keycloak-local | grep -i theme
```

### Cache Issues
The script uses `--no-cache` to prevent cache issues, but if problems persist:
```bash
# Full Docker cleanup
docker system prune -a -f
```

### Theme Issues
For themed deployment problems:
```bash
# Test theme validation
./sh/test-theme-validation.sh

# Check theme files
find themes/obp -type f

# Verify theme.properties
cat themes/obp/theme.properties | grep -E "(parent=|styles=)"

# Test with standard deployment first
./sh/run-local-postgres-cicd.sh
```

## Best Practices

1. **Version your .env.local**: Include in version control as `.env.example`
2. **Monitor build times**: Track performance degradation
3. **Use health checks**: Verify deployment success programmatically
4. **Log everything**: Capture build and deployment logs
5. **Test rollback**: Ensure you can revert to previous versions
6. **Document changes**: Update this file when modifying the script
7. **Validate themes**: Run `./sh/test-theme-validation.sh` before themed deployments
8. **Test incrementally**: Try standard deployment before themed if issues occur

## Support

For issues with the CI/CD deployment script:

1. Check the troubleshooting section above
2. Review container logs: `docker logs obp-keycloak-local`
3. Verify database connectivity manually
4. Test with original script to isolate issues
5. Check Docker system resources and cleanup if needed

The CI/CD script is designed to fail fast and provide clear error messages to facilitate quick problem resolution in automated environments.