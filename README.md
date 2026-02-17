# Keycloak provider for user federation in Postgres

This project demonstrates the ability to use Postgres as user storage provider of Keycloak with **cloud-native runtime configuration** support and **separated database architecture**.

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
## Prerequisites

Before running the OBP Keycloak Provider, ensure you have the following set up:

### Database Setup

The application requires two PostgreSQL databases with properly configured users:

1. **Keycloak Internal Database** - Run the setup script to create the keycloak user:
   ```bash
   # See database/setup-keycloak-user.sql for the complete setup script
   psql -U postgres -h localhost -f database/setup-keycloak-user.sql
   ```

2. **User Storage Database** - [OBP-API database schema](https://github.com/OpenBankProject/OBP-API/tree/develop/obp-api/src/main/scripts/sql/OIDC)

### Software Requirements

- PostgreSQL 12+ running and accessible
- Docker and Docker Compose (for containerized deployment)
- Maven 3.6+ (for building from source)
- Java 11+ (for building from source)

## Usage
### Docker containers
[Postgres](https://www.postgresql.org/) - database for which we want to store User Federation.

[Keycloak](https://www.keycloak.org/) - KC container with custom certificate, for use over `https`. The container is described in [Dockerfile](/development/docker/Dockerfile).

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

### Development Deployment
```bash
# Standard deployment without themes
./development/run-local-postgres-cicd.sh
```
### CI/CD Deployment
```bash
# Automated, reproducible deployments (always fresh build)
./development/run-local-postgres-cicd.sh --themed

# Standard CI/CD deployment
./development/run-local-postgres-cicd.sh
```

### Analysis and Testing Tools
```bash
# Manage running containers interactively
./development/manage-container.sh
```

📖 **Detailed Guides**:
- [docs/CICD_DEPLOYMENT.md](docs/CICD_DEPLOYMENT.md) - Complete CI/CD documentation

### Using Postgres
For PostgreSQL setup, please refer to the main deployment scripts or set up your own database instance.

The system now uses two separate databases:

1. **Keycloak's Internal Database**: Stores realms, clients, tokens, and Keycloak's own data (accessible on localhost:5433)
2. **User Storage Database**: Contains your external user data that Keycloak federates (accessible on localhost:5434)

> **Important**: Due to recent fixes, the user storage database now runs on port 5434 instead of 5432 to avoid conflicts with system PostgreSQL installations.

For the **User Storage Database** setup, use the official OBP-API SQL scripts:

> **IMPORTANT**: Use the official OBP-API repository scripts as the source of truth. This avoids code duplication and ensures you have the latest, maintained SQL scripts.

**Keycloak Provider Features:**
- ✅ User authentication and login via the `v_oidc_users` view
- ✅ User profile viewing (read-only access)
- ✅ Password validation
- ✅ Secure federation with existing OBP user data
- 🔴 User creation/updates/deletion (read-only by design)

For detailed setup instructions, see the [database/README.md](database/README.md) file and the official OBP-API repository.

### Using Keycloak
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

