# Keycloak provider for user federation in Postgres

This project demonstrates the ability to use Postgres as user storage provider of Keycloak with **cloud-native runtime configuration** support and **separated database architecture**.

## 🔄 Database Architecture

**Important**: This project now uses **separated databases** for better security and maintainability:

- **Keycloak Internal Database**: Stores realms, clients, tokens, sessions (Port 5433)
- **User Storage Database**: Contains your external user data for federation (Port 5434)



## 🚀 Cloud-Native Features

- ✅ **Runtime Configuration**: Environment variables read at runtime (no build-time injection)
- ✅ **Kubernetes Ready**: Native support for ConfigMaps and Secrets
- ✅ **Docker Hub Compatible**: Generic images that work across all environments
- ✅ **12-Factor App Compliant**: Follows modern cloud-native principles
- ✅ **CI/CD Friendly**: "Build once, deploy everywhere" approach

## 🔒 Security Features

- ✅ **View-Based Access**: Uses `v_oidc_users` view for secure, read-only data access
- ✅ **Read-Only Operations**: All write operations (INSERT, UPDATE, DELETE) are disabled
- ✅ **Minimal Permissions**: Dedicated `oidc_user` with SELECT-only database permissions
- ✅ **Column Filtering**: Only OIDC-required fields exposed through database view
- ✅ **User Validation**: Only validated users accessible through OIDC authentication

## Requirements

The following software is required to work build it locally:

* [Git](https://git-scm.com) 2.2.1 or later
* [Docker Engine](https://docs.docker.com/engine/install/) or [Docker Desktop](https://docs.docker.com/desktop/) 1.9 or later
* [Maven](https://maven.apache.org/) 3.8.5 or later
* [Java](https://www.java.com/ru/) 17 or later

See the links above for installation instructions on your platform. You can verify the versions are installed and running:

    $ git --version
    $ curl -V
    $ mvn -version
    $ docker --version
    $ java --version



## 🔧 Quick Configuration

### View-Based Access (Recommended for Production)

```bash
# Environment variables for secure view-based access
DB_USER=oidc_user
DB_PASSWORD=your_secure_password
DB_AUTHUSER_TABLE=v_oidc_users
```

**Benefits:**
- Enhanced security through PostgreSQL view filtering
- Read-only access prevents accidental data modification
- Only validated users are accessible through OIDC
- Minimal database permissions for the application user

### Direct Table Access (Development/Legacy)

```bash
# Environment variables for direct table access
DB_USER=obp
DB_PASSWORD=f
DB_AUTHUSER_TABLE=authuser
```

See [VIEW_BASED_ACCESS.md](VIEW_BASED_ACCESS.md) for detailed setup instructions.

## Usage
### Docker containers
[Postgres](https://www.postgresql.org/) - database for which we want to store User Federation.

[Keycloak](https://www.keycloak.org/) - KC container with custom certificate, for use over `https`. The container is described in [Dockerfile](/docker/Dockerfile).

### CI/CD and Automation

The project includes GitHub Actions workflows for automated builds and deployments:
- **Automated container builds** on pushes to main branch
- **Multi-architecture support** with alternative Dockerfiles
- **Dependency updates** via Dependabot
- **Container signing** with Cosign for security

### Theming Support

The project includes a comprehensive **OBP Theme** that transforms Keycloak's login experience to match the Open Bank Project Portal design system:

- **Modern Dark Theme**: Elegant glassmorphism UI with backdrop blur effects
- **OBP Branding**: Official logos, colors, and typography (Plus Jakarta Sans)
- **Portal Design Consistency**: Matches OBP Portal's visual identity and user experience
- **OKLCH Color System**: Modern color palette with primary (dark blue/gray) and secondary (teal/green) colors
- **Responsive Design**: Mobile-first approach optimized for all devices
- **Accessibility Features**: WCAG 2.1 compliance with high contrast support
- **Internationalization**: Multi-language support with customizable messages

#### Theme Deployment Options

The project supports two deployment modes:

1. **Local PostgreSQL Deployment** (uses existing local PostgreSQL):
   ```shell
   # Standard deployment with local PostgreSQL
   $ ./sh/run-local-postgres.sh

   # Themed deployment with local PostgreSQL
   $ ./sh/run-local-postgres.sh --themed --validate
   ```

2. **CI/CD Deployment** (always build & replace - automated environments):
   ```shell
   # Standard CI/CD deployment
   $ ./sh/run-local-postgres-cicd.sh

   # Themed CI/CD deployment
   $ ./sh/run-local-postgres-cicd.sh --themed
   ```

#### OBP Theme Structure

```
themes/obp/
├── theme.properties                    # Theme configuration
├── login/                             # Login theme files
│   ├── login.ftl                      # Custom login template
│   ├── messages/                      # Internationalization
│   │   └── messages_en.properties     # English messages
│   └── resources/                     # Static resources
│       ├── css/
│       │   └── styles.css             # Main stylesheet
│       └── img/                       # OBP logos and assets
│           ├── obp_logo.png
│           ├── logo2x-1.png
│           └── favicon.png
```

#### Theme Activation

After deploying with `--themed`, activate the OBP theme:
1. Access Admin Console: https://localhost:8443/admin
2. Go to Realm Settings > Themes
3. Set Login Theme to "obp"
4. Save changes

> **Complete Documentation**: See [docs/OBP_THEME.md](docs/OBP_THEME.md) for comprehensive theming guide, customization options, and development workflow.

#### Testing Theme Deployment

Validate your themed deployment setup:
```shell
$ ./sh/validate-themed-setup.sh
```

This script checks all prerequisites, validates theme files, and ensures proper configuration.

### Environment Configuration

The database connection and Keycloak settings are now configured using **runtime environment variables** instead of build-time configuration. This enables cloud-native deployments with Kubernetes, Docker Hub hosted images, and modern CI/CD pipelines.

> **Complete Documentation**:
> - [docs/CLOUD_NATIVE.md](docs/CLOUD_NATIVE.md) - Cloud-native deployment guide
> - [docs/ENVIRONMENT.md](docs/ENVIRONMENT.md) - Environment configuration reference
> - [k8s/](k8s/) - Kubernetes deployment examples

#### Quick Start Guide

1. **Copy and configure environment variables:**
   ```shell
   $ cp .env.example .env
   $ nano .env  # Edit with your actual configuration
   ```

2. **Validate your configuration:**
   ```shell
   $ ./sh/validate-env.sh
   ```

3. **Run the application:**
   ```shell
   # Local PostgreSQL deployment (themed)
   $ ./sh/run-local-postgres.sh --themed --validate

   # OR CI/CD deployment (always build & replace)
   $ ./sh/run-local-postgres-cicd.sh --themed
   ```

4. **Test themed deployment (optional):**
   ```shell
   $ ./sh/validate-themed-setup.sh
   ```

> **Note**: For local PostgreSQL deployments, the `--validate` flag automatically runs validation checks during startup.

#### Setup Environment Variables

1. Copy the example environment file:
   ```shell
   $ cp .env.example .env
   ```

2. Edit the `.env` file with your actual configuration values:
   ```properties
   # Keycloak Admin Configuration
   KEYCLOAK_ADMIN=your-admin
   KEYCLOAK_ADMIN_PASSWORD=your-admin-password

   # Keycloak's Internal Database Configuration
   KC_DB_USERNAME=keycloak
   KC_DB_PASSWORD=secure-keycloak-password

   # User Storage Database Configuration
   USER_STORAGE_DB_USER=obp
   USER_STORAGE_DB_PASSWORD=secure-user-storage-password
   DB_USER=obp
   DB_PASSWORD=secure-user-storage-password
   ```

3. **Validate your configuration (recommended):**
   ```shell
   $ ./sh/validate-env.sh
   ```
   This script will:
   - Check all required variables are set
   - Validate configuration format and values
   - Warn about potential security issues
   - Provide helpful troubleshooting information

> **Documentation Resources**:
> - **[.env.example](.env.example)**: Complete environment variable reference with examples and security notes
> - **[docs/ENVIRONMENT.md](docs/ENVIRONMENT.md)**: Comprehensive configuration guide with troubleshooting and deployment examples
> - **[docs/WORKFLOW.md](docs/WORKFLOW.md)**: Development workflow and container management guide
> - **[docs/CICD_DEPLOYMENT.md](docs/CICD_DEPLOYMENT.md)**: CI/CD-style deployment guide for automated environments
> - **Validation tools**: `./sh/validate-env.sh` and `./sh/compare-env.sh`
> - **Comparison tools**: `./sh/compare-deployment-scripts.sh` and `./sh/test-cache-invalidation.sh`

#### Key Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| **Keycloak Admin** | | |
| `KEYCLOAK_ADMIN` | `admin` | Keycloak admin username |
| `KEYCLOAK_ADMIN_PASSWORD` | `admin` | Keycloak admin password |
| **Keycloak Database** | | |
| `KC_DB_USERNAME` | `keycloak` | Keycloak's internal database username |
| `KC_DB_PASSWORD` | `keycloak_changeme` | Keycloak's internal database password |
| `KC_DB_URL` | `jdbc:postgresql://keycloak-postgres:5432/keycloak` | Keycloak's internal database URL |
| **User Storage Database** | | |
| `DB_URL` | `jdbc:postgresql://user-storage-postgres:5432/obp_mapped` | User storage database URL |
| **Port Configuration** | | |
| `KC_DB_PORT` | `5433` | Keycloak database external port |
| `USER_STORAGE_DB_PORT` | `5434` | User storage database external port |
| `DB_USER` | `obp` | User storage database username |
| `DB_PASSWORD` | `changeme` | User storage database password |
| **Configuration** | | |
| `KC_HOSTNAME_STRICT` | `false` | Hostname strict mode |
| `HIBERNATE_DDL_AUTO` | `validate` | Schema validation mode for user storage |

#### Docker Deployment

When using Docker, you can:

1. Use a `.env` file with docker-compose:
   ```shell
   $ cp docker-compose.example.yml docker-compose.yml
   $ docker-compose up
   ```

2. Pass environment variables directly:
   ```shell
   $ docker run -e KC_DB_URL=jdbc:postgresql://keycloak-host:5432/keycloak \
                 -e KC_DB_USERNAME=keycloak_user \
                 -e KC_DB_PASSWORD=keycloak_pass \
                 -e DB_URL=jdbc:postgresql://user-storage-host:5432/obp_mapped \
                 -e DB_USER=obp_user \
                 -e DB_PASSWORD=obp_pass \
                 -e KEYCLOAK_ADMIN=admin \
                 -e KEYCLOAK_ADMIN_PASSWORD=secure_password \
                 your-keycloak-image
   ```

#### Configuration Tools

- **Validate configuration**: `./sh/validate-env.sh`
- **Compare with example**: `./sh/compare-env.sh`
- **Manage container**: `./sh/manage-container.sh`

## Deployment Strategies

### Choosing the Right Deployment Method

The project provides two focused deployment approaches:

| Method | Use Case | Build Strategy | Best For |
|--------|----------|---------------|-----------|
| **Local PostgreSQL** (`run-local-postgres.sh`) | Development with existing PostgreSQL | Conditional rebuild | Daily development, testing |
| **CI/CD** (`run-local-postgres-cicd.sh`) | Automated pipelines | Always rebuild | CI/CD, production deployments |

### Development Deployment
```bash
# Interactive development with validation and caching
./sh/run-local-postgres.sh --themed --validate

# Quick iteration (skips some validation)
./sh/run-local-postgres.sh --themed

# Standard deployment without themes
./sh/run-local-postgres.sh
```

**Features:**
- Conditional rebuilds for faster iteration
- Comprehensive validation and testing
- Interactive feedback and guidance
- Container management helpers

### CI/CD Deployment
```bash
# Automated, reproducible deployments (always fresh build)
./sh/run-local-postgres-cicd.sh --themed

# Standard CI/CD deployment
./sh/run-local-postgres-cicd.sh
```

**Features:**
- Always builds from scratch (no caching issues)
- JAR checksum-based cache invalidation
- Fail-fast error handling
- Structured pipeline output
- Health checks with timeout

### Analysis and Testing Tools
```bash
# Compare deployment approaches
./sh/compare-deployment-scripts.sh

# Test Docker cache invalidation
./sh/test-cache-invalidation.sh

# Validate theme structure (for themed deployments)
./sh/test-theme-validation.sh
```

📖 **Detailed Guides**:
- [docs/CICD_DEPLOYMENT.md](docs/CICD_DEPLOYMENT.md) - Complete CI/CD documentation
- [SCRIPT_REMOVAL_SUMMARY.md](SCRIPT_REMOVAL_SUMMARY.md) - Legacy script removal summary

#### Build Options

The project supports **cloud-native deployment patterns**:

1. **Runtime Configuration** (Recommended - Cloud-Native):
   ```shell
   # Build once (no environment variables needed)
   $ mvn clean package
   $ docker build -t obp-keycloak-provider .

   # Deploy anywhere with runtime config
   $ docker run -e KC_DB_URL="jdbc:postgresql://keycloak-host:5432/keycloak" \
                 -e KC_DB_USERNAME="keycloak_user" \
                 -e KC_DB_PASSWORD="keycloak_password" \
                 -e DB_URL="jdbc:postgresql://user-storage-host:5432/obp_mapped" \
                 -e DB_USER="obp_user" \
                 -e DB_PASSWORD="obp_password" \
                 obp-keycloak-provider
   ```

2. **Kubernetes Deployment**:
   ```shell
   $ kubectl apply -f k8s/configmap.yaml
   $ kubectl apply -f k8s/secret.yaml
   $ kubectl apply -f k8s/deployment.yaml
   ```

3. **Docker Compose** (Runtime Config):
   ```shell
   $ docker-compose -f docker-compose.runtime.yml up
   ```

4. **CI/CD builds** using GitHub Actions workflows:
   - Single generic build for all environments
   - Container signing and publishing to Docker Hub
   - Multi-architecture support with runtime configuration

#### Container Management

When you run the deployment scripts, they start the Keycloak container and follow the logs. When you press `Ctrl+C`, the script exits but **the container continues running in the background**.

**After pressing Ctrl+C:**
- The container remains accessible at http://localhost:8000 and https://localhost:8443
- Use `./sh/manage-container.sh` for an interactive container management menu
- Or use these direct commands:
  - View logs: `docker logs -f obp-keycloak`
  - Stop container: `docker stop obp-keycloak`
  - Remove container: `docker rm obp-keycloak`
  - Stop and remove: `docker stop obp-keycloak && docker rm obp-keycloak`

### Using Postgres
> **Warning: I recommend using your own database**, cause not all systems will have a database at `localhost` available to the `docker` container.

To deploy the container use the script :
```shell
$ sh/pg.sh
```

The script deploys the container locally.

It uses port : 5434 (changed from 5432 to avoid conflicts with system PostgreSQL).

The system now uses two separate databases:

1. **Keycloak's Internal Database**: Stores realms, clients, tokens, and Keycloak's own data (accessible on localhost:5433)
2. **User Storage Database**: Contains your external user data that Keycloak federates (accessible on localhost:5434)

> **Important**: Due to recent fixes, the user storage database now runs on port 5434 instead of 5432 to avoid conflicts with system PostgreSQL installations.

In the **User Storage Database**, the `authuser` table must be created by a database administrator:

> **⚠️ CRITICAL**: The `authuser` table is **READ-ONLY** for the Keycloak User Storage Provider and **MUST** be created by a database administrator with appropriate permissions. Keycloak setup scripts cannot create this table due to read-only access restrictions.

> **📋 SETUP REQUIREMENT**: The authuser table must exist before running Keycloak. INSERT, UPDATE, and DELETE operations are not supported through Keycloak. Users must be managed through other means outside of Keycloak.

```sql
-- ===============================================
-- DATABASE ADMINISTRATOR SETUP REQUIRED
-- ===============================================
-- This SQL must be executed by a database administrator
-- with CREATE privileges on the obp_mapped database.
-- The Keycloak application has READ-ONLY access only.

CREATE TABLE public.authuser (
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

-- Grant READ-ONLY access to Keycloak user
GRANT SELECT ON public.authuser TO obp;
GRANT USAGE ON SEQUENCE authuser_id_seq TO obp;
```

**Database Setup Requirements:**
- 📋 Table must be created by database administrator BEFORE running Keycloak
- 📋 Keycloak user (obp) needs only SELECT permissions on authuser table
- 📋 Database administrator must create table structure and indexes

**Keycloak Provider Limitations:**
- ✅ User authentication and login
- ✅ User profile viewing
- ✅ Password validation
- 🔴 User creation through Keycloak (disabled - read-only access)
- 🔴 User profile updates through Keycloak (disabled - read-only access)
- 🔴 User deletion through Keycloak (disabled - read-only access)
- 🔴 Table creation through setup scripts (disabled - insufficient permissions)

Users must be added to the `authuser` table using external database administration tools outside of Keycloak.

### Using Keycloak

KC is deployed in a custom container.

To deploy the KC container, I created a [Dockerfile](/docker/Dockerfile) file in which :
- I create a certificate for `https` access
- I add a provider `obp-keycloak-provider`

## Build the project

### Cloud-Native Approach (Recommended)

Build once, deploy everywhere with runtime configuration:

```shell
# Build the provider (no environment variables needed)
$ mvn clean package

# Test runtime configuration
$ ./sh/test-runtime-config.sh

# Run with local PostgreSQL
$ ./sh/run-local-postgres.sh --themed --validate
```

### Legacy Approach

For compatibility, you can still use the legacy build script:
```shell
$ ./sh/run-local-postgres.sh
```

> **Note**: The legacy approach uses build-time configuration which is not recommended for production deployments. Use the cloud-native approach for Kubernetes and Docker Hub deployments.

## Login to KC

After launching, go to [https://localhost:8443](https://localhost:8443) in your browser.
To log in to KC, use admin credentials :
```properties
user : admin
pass : admin
```

Click the [User federation](https://localhost:8443/admin/master/console/#/master/user-federation) tab .

The provider ``obp-keycloak-provider`` is in list of providers.

![KC providers](/docs/images/providers.png?raw=true "KC providers")

## Cloud-Native Deployment Examples

### Kubernetes
```yaml
# ConfigMap for non-sensitive config
apiVersion: v1
kind: ConfigMap
metadata:
  name: obp-keycloak-config
data:
  DB_DRIVER: "org.postgresql.Driver"
  HIBERNATE_DDL_AUTO: "validate"

---
# Secret for sensitive data
apiVersion: v1
kind: Secret
metadata:
  name: obp-keycloak-secrets
stringData:
  # Keycloak's internal database
  KC_DB_URL: "jdbc:postgresql://keycloak-postgres:5432/keycloak"
  KC_DB_USERNAME: "keycloak"
  KC_DB_PASSWORD: "secure_keycloak_password"

  # User storage database
  DB_URL: "jdbc:postgresql://user-storage-postgres:5432/obp_mapped"
  DB_USER: "obp"
  DB_PASSWORD: "secure_user_storage_password"
```

### Docker Hub Deployment
```shell
# Pull generic image
docker pull your-org/obp-keycloak-provider:latest

# Run with environment-specific configuration
docker run -e KC_DB_URL="jdbc:postgresql://keycloak-prod-db:5432/keycloak" \
           -e KC_DB_USERNAME="keycloak_prod_user" \
           -e KC_DB_PASSWORD="secure_keycloak_password" \
           -e DB_URL="jdbc:postgresql://user-storage-prod-db:5432/obp" \
           -e DB_USER="obp_prod_user" \
           -e DB_PASSWORD="secure_user_storage_password" \
           your-org/obp-keycloak-provider:latest
```

### Testing Runtime Configuration
```shell
# Validate the cloud-native setup
$ ./sh/test-runtime-config.sh

# Compare with example configuration
$ ./sh/compare-env.sh
```

## Recent Changes

### Database Separation Fixes (Latest)

The following critical issues have been resolved:

1. **Fixed JDBC URL Configuration**: Corrected malformed `KC_DB_URL` default value in `docker-compose.runtime.yml`
2. **Resolved Port Conflicts**: Changed user-storage-postgres to port 5434 to avoid conflicts with system PostgreSQL
3. **Fixed SQL Syntax Error**: Removed incomplete SQL statement in database initialization script
4. **Updated Environment Variables**: All configuration now properly supports the separated database architecture



### Port Changes
- **Keycloak Internal Database**: `localhost:5433` (unchanged)
- **User Storage Database**: `localhost:5434` (changed from 5432)
- **Keycloak Application**: `localhost:8000` (HTTP) and `localhost:8443` (HTTPS)

### Troubleshooting
If you encounter connection issues:
1. Run the validation script: `./sh/validate-separated-db-config.sh`
2. Check for port conflicts: `ss -tulpn | grep :5432` or `netstat -tulpn | grep :5432`
3. Review the setup documentation in the `docs/` directory

## Documentation


- **[Cloud-Native Guide](docs/CLOUD_NATIVE.md)** - Complete guide for Kubernetes and Docker Hub deployments
- **[Environment Configuration](docs/ENVIRONMENT.md)** - Environment variable reference
- **[CI/CD Deployment](docs/CICD_DEPLOYMENT.md)** - Automated deployment guide for pipelines

- **[Kubernetes Examples](k8s/)** - Production-ready Kubernetes manifests
- **[Docker Compose](docker-compose.runtime.yml)** - Runtime configuration example
