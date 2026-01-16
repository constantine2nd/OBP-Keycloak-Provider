# Keycloak provider for user federation in Postgres

This project demonstrates the ability to use Postgres as user storage provider of Keycloak with **cloud-native runtime configuration** support and **separated database architecture**.

## 🔄 Database Architecture

**Important**: This project now uses **separated databases** for better security and maintainability:

- **Keycloak Internal Database**: Stores realms, clients, tokens, sessions (Port 5433)
- **User Storage Database**: Contains your external user data for federation (Port 5434)



## 🚀 Cloud-Native Features

- ✅ **Runtime Configuration**: Environment variables read at runtime (no build-time injection)
- ✅ **Cloud Ready**: Native support for environment-based configuration
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

For development or legacy systems, you can access the `authuser` table directly instead of using the recommended `v_oidc_users` view:

```bash
# Environment variables for direct table access (not recommended for production)
DB_USER=obp
DB_PASSWORD=f
DB_AUTHUSER_TABLE=authuser  # Direct table access instead of v_oidc_users view
```

**Note**: The recommended approach is to use `DB_AUTHUSER_TABLE=v_oidc_users` with the view created by `database/setup-user-storage.sql`, which provides better security by only exposing validated users and proper field mapping.

See the configuration examples below for detailed setup instructions.

## Prerequisites

Before running the OBP Keycloak Provider, ensure you have the following set up:

### Database Setup

The application requires two PostgreSQL databases with properly configured users:

1. **Keycloak Internal Database** - Run the setup script to create the keycloak user:
   ```bash
   # See database/setup-keycloak-user.sql for the complete setup script
   psql -U postgres -h localhost -f database/setup-keycloak-user.sql
   ```

2. **User Storage Database** - Run the setup script on your existing OBP database:
   ```bash
   # Creates v_oidc_users view and oidc_user role with proper permissions
   psql -U postgres -h localhost -d obp_mapped -f database/setup-user-storage.sql
   ```

   This creates the OIDC users view that joins your `authuser` and `resourceuser` tables. For the complete view definition, see the [OBP-API database schema](https://github.com/OpenBankProject/OBP-API).

> **📁 Complete database setup scripts and documentation**: [database/README.md](database/README.md)

### Software Requirements

- PostgreSQL 12+ running and accessible
- Docker and Docker Compose (for containerized deployment)
- Maven 3.6+ (for building from source)
- Java 11+ (for building from source)

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

1. **CI/CD Deployment** (always build & replace - automated environments):
   ```shell
   # Standard CI/CD deployment
   $ ./development/run-local-postgres-cicd.sh

   # Themed CI/CD deployment
   $ ./development/run-local-postgres-cicd.sh --themed
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

> **Complete Documentation**: See the theme structure and activation sections below for comprehensive theming guide, customization options, and development workflow.

#### Testing Theme Deployment

Validate your themed deployment setup by running the deployment script:
```shell
$ ./development/run-local-postgres-cicd.sh --themed
```

This script checks all prerequisites, validates theme files, and ensures proper configuration.

### Environment Configuration

The database connection and Keycloak settings are now configured using **runtime environment variables** instead of build-time configuration. This enables cloud-native deployments with Docker Hub hosted images, and modern CI/CD pipelines.

> **Complete Documentation**:
> - [docs/CICD_DEPLOYMENT.md](docs/CICD_DEPLOYMENT.md) - CI/CD deployment guide
> - [env.sample](env.sample) - Environment configuration reference

#### Quick Start Guide

1. **Copy and configure environment variables:**
   ```shell
   $ cp env.sample .env
   $ nano .env  # Edit with your actual configuration
   ```

2. **Validate your configuration:**
   ```shell
   $ ./development/run-local-postgres-cicd.sh
   ```

3. **Run the application:**
   ```shell
   # CI/CD deployment (always build & replace)
   $ ./development/run-local-postgres-cicd.sh --themed
   ```

4. **Test themed deployment (optional):**
   ```shell
   $ ./development/run-local-postgres-cicd.sh --themed
   ```

> **Note**: For local PostgreSQL deployments, the `--validate` flag automatically runs validation checks during startup.

#### Setup Environment Variables

1. Copy the example environment file:
   ```shell
   $ cp env.sample .env
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
   DB_NAME=obp_mapped
   DB_USER=oidc_user
   DB_PASSWORD=secure-user-storage-password
   DB_PORT=5432
   ```

3. **Validate your configuration (recommended):**
   ```shell
   $ ./development/run-local-postgres-cicd.sh
   ```
   This script will:
   - Validate all required variables are set
   - Check database connectivity
   - Build and deploy the application
   - Provide clear success/failure feedback

> **Documentation Resources**:
> - **[env.sample](env.sample)**: Complete environment variable reference with examples and security notes
> - **[docs/CICD_DEPLOYMENT.md](docs/CICD_DEPLOYMENT.md)**: CI/CD-style deployment guide for automated environments
> - **[development/README.md](development/README.md)**: Development tools and scripts documentation
> - **Available scripts**: Only 3 development scripts are included (see development directory)

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
| `DB_PORT` | `5432` | User storage database external port |
| `DB_USER` | `oidc_user` | User storage database username |
| `DB_PASSWORD` | `changeme` | User storage database password |
| `DB_AUTHUSER_TABLE` | `v_oidc_users` | View/table name for user authentication data |
| **Configuration** | | |
| `KC_HOSTNAME_STRICT` | `false` | Hostname strict mode |
| `HIBERNATE_DDL_AUTO` | `validate` | Schema validation mode for user storage |

#### Docker Deployment with External OBP Database

Docker setup uses Keycloak in container with external PostgreSQL for OBP user federation:

1. Use configuration with external PostgreSQL:
   ```shell
   $ cp .env.external-postgres .env
   $ # Edit .env with your database settings
   $ docker-compose up
   ```

2. Required setup:
   ```shell
   # External PostgreSQL must have:
   DB_USER=oidc_user
   DB_PASSWORD=your_password
   DB_DRIVER=org.postgresql.Driver
   DB_DIALECT=org.hibernate.dialect.PostgreSQLDialect
   OBP_AUTHUSER_PROVIDER=your_provider
   ```

#### Development Tools

The `development/` directory contains local development scripts:

- **Deployment**: `./development/run-local-postgres-cicd.sh` - Main deployment script (with --themed option)
- **Management**: `./development/manage-container.sh` - Interactive container management


See [development/README.md](development/README.md) for complete documentation of all development tools.

## Deployment Strategies

### Choosing the Right Deployment Method

The project provides two focused deployment approaches:

| Method | Use Case | Build Strategy | Best For |
|--------|----------|---------------|-----------|
| **CI/CD** (`run-local-postgres-cicd.sh`) | Automated pipelines | Always rebuild | CI/CD, production deployments |

### Development Deployment
```bash
# Standard deployment without themes
./development/run-local-postgres-cicd.sh
```

**Features:**
- Conditional rebuilds for faster iteration
- Comprehensive validation and testing
- Interactive feedback and guidance
- Container management helpers

### CI/CD Deployment
```bash
# Automated, reproducible deployments (always fresh build)
./development/run-local-postgres-cicd.sh --themed

# Standard CI/CD deployment
./development/run-local-postgres-cicd.sh
```

**Features:**
- Always builds from scratch (no caching issues)
- JAR checksum-based cache invalidation
- Fail-fast error handling
- Structured pipeline output
- Health checks with timeout

### Analysis and Testing Tools
```bash
# Manage running containers interactively
./development/manage-container.sh
```

📖 **Detailed Guides**:
- [docs/CICD_DEPLOYMENT.md](docs/CICD_DEPLOYMENT.md) - Complete CI/CD documentation

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

2. **Environment Variables Deployment**:
   ```shell
   $ export DB_URL="jdbc:postgresql://localhost:5432/obp_mapped"
   $ export DB_USER="obp"
   $ export DB_PASSWORD="obp_password"
   $ docker run --env-file .env obp-keycloak-provider
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
- Use `./development/manage-container.sh` for an interactive container management menu
- Or use these direct commands:
  - View logs: `docker logs -f obp-keycloak`
  - Stop container: `docker stop obp-keycloak`
  - Remove container: `docker rm obp-keycloak`
  - Stop and remove: `docker stop obp-keycloak && docker rm obp-keycloak`

### Using Postgres
> **Warning: I recommend using your own database**, cause not all systems will have a database at `localhost` available to the `docker` container.

For PostgreSQL setup, please refer to the main deployment scripts or set up your own database instance.

The system now uses two separate databases:

1. **Keycloak's Internal Database**: Stores realms, clients, tokens, and Keycloak's own data (accessible on localhost:5433)
2. **User Storage Database**: Contains your external user data that Keycloak federates (accessible on localhost:5434)

> **Important**: Due to recent fixes, the user storage database now runs on port 5434 instead of 5432 to avoid conflicts with system PostgreSQL installations.

For the **User Storage Database** setup, use the official OBP-API SQL scripts:

> **📋 IMPORTANT**: Use the official OBP-API repository scripts as the source of truth. This avoids code duplication and ensures you have the latest, maintained SQL scripts.

**Official Setup Process:**

1. **Clone/Download OBP-API Repository:**
   - Repository: https://github.com/OpenBankProject/OBP-API
   - Navigate to: `obp-api/src/main/scripts/sql/OIDC/`

2. **Run Official Setup Script:**
   ```bash
   cd obp-api/src/main/scripts/sql/OIDC/
   psql -d your_obp_database
   \i give_read_access_to_users.sql
   ```

**What the Official Scripts Do:**
- ✅ Create `v_oidc_users` view joining `authuser` and `resourceuser` tables
- ✅ Create `oidc_user` role with read-only permissions
- ✅ Grant appropriate SELECT permissions on the view
- ✅ Include security settings and error handling
- ✅ Only expose validated users for security

**Keycloak Provider Features:**
- ✅ User authentication and login via the `v_oidc_users` view
- ✅ User profile viewing (read-only access)
- ✅ Password validation
- ✅ Secure federation with existing OBP user data
- 🔴 User creation/updates/deletion (read-only by design)

**Why Use Official Scripts:**
- Always up-to-date with OBP-API changes
- Maintained by the OBP development team
- Proper security configurations included
- Avoids documentation drift and code duplication

For detailed setup instructions, see the [database/README.md](database/README.md) file and the official OBP-API repository.

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

# Run with CI/CD deployment
$ ./development/run-local-postgres-cicd.sh --themed
```

### Legacy Approach

For compatibility, you can still use the legacy build script:
```shell
$ ./development/run-local-postgres-cicd.sh
```

> **Note**: The legacy approach uses build-time configuration which is not recommended for production deployments. Use the cloud-native approach for Docker Hub deployments.

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
# Deploy and validate the setup
./development/run-local-postgres-cicd.sh
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
1. Run the deployment script which validates configuration: `./development/run-local-postgres-cicd.sh`
2. Check for port conflicts: `ss -tulpn | grep :5432` or `netstat -tulpn | grep :5432`
3. Review the setup documentation in the `docs/` directory

## Documentation


- **[Environment Configuration](env.sample)** - Environment variable reference
- **[CI/CD Deployment](docs/CICD_DEPLOYMENT.md)** - Automated deployment guide for pipelines
- **[Docker Compose](docker-compose.runtime.yml)** - Runtime configuration example
