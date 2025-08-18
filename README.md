# Keycloak provider for user federation in Postgres

This project demonstrates the ability to use Postgres as user storage provider of Keycloak with **cloud-native runtime configuration** support.

## 🚀 Cloud-Native Features

- ✅ **Runtime Configuration**: Environment variables read at runtime (no build-time injection)
- ✅ **Kubernetes Ready**: Native support for ConfigMaps and Secrets
- ✅ **Docker Hub Compatible**: Generic images that work across all environments
- ✅ **12-Factor App Compliant**: Follows modern cloud-native principles
- ✅ **CI/CD Friendly**: "Build once, deploy everywhere" approach

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

1. **Standard Deployment** (default):
   ```shell
   $ ./sh/run-with-env.sh
   # or explicitly
   $ ./sh/run-with-env.sh --standard
   ```

2. **Themed Deployment** (with custom UI):
   ```shell
   $ ./sh/run-with-env.sh --themed
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
$ ./sh/test-themed-deployment.sh
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
   # Standard deployment
   $ ./sh/run-with-env.sh
   
   # OR with custom themes
   $ ./sh/run-with-env.sh --themed
   ```

4. **Test themed deployment (optional):**
   ```shell
   $ ./sh/test-themed-deployment.sh
   ```

#### Setup Environment Variables

1. Copy the example environment file:
   ```shell
   $ cp .env.example .env
   ```

2. Edit the `.env` file with your actual configuration values:
   ```properties
   # Database configuration
   DB_URL=jdbc:postgresql://your-db-host:5432/your-database
   DB_USER=your-username
   DB_PASSWORD=your-secure-password
   
   # Keycloak admin credentials
   KC_BOOTSTRAP_ADMIN_USERNAME=your-admin
   KC_BOOTSTRAP_ADMIN_PASSWORD=your-admin-password
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
> - **Validation tools**: `./sh/validate-env.sh` and `./sh/compare-env.sh`

#### Key Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `DB_URL` | `jdbc:postgresql://localhost:5432/obp_mapped` | PostgreSQL database URL |
| `DB_USER` | `obp` | Database username |
| `DB_PASSWORD` | `changeme` | Database password |
| `KC_BOOTSTRAP_ADMIN_USERNAME` | `admin` | Initial admin username |
| `KC_BOOTSTRAP_ADMIN_PASSWORD` | `admin` | Initial admin password |
| `KC_HOSTNAME_STRICT` | `false` | Hostname strict mode |
| `HIBERNATE_DDL_AUTO` | `validate` | Schema validation mode |

#### Docker Deployment

When using Docker, you can:

1. Use a `.env` file with docker-compose:
   ```shell
   $ cp docker-compose.example.yml docker-compose.yml
   $ docker-compose up
   ```

2. Pass environment variables directly:
   ```shell
   $ docker run -e DB_URL=jdbc:postgresql://host:5432/db \
                 -e DB_USER=user \
                 -e DB_PASSWORD=pass \
                 -e KC_BOOTSTRAP_ADMIN_USERNAME=admin \
                 -e KC_BOOTSTRAP_ADMIN_PASSWORD=secure_password \
                 your-keycloak-image
   ```

#### Configuration Tools

- **Validate configuration**: `./sh/validate-env.sh`
- **Compare with example**: `./sh/compare-env.sh`  
- **Run with environment**: `./sh/run-with-env.sh`
- **Manage container**: `./sh/manage-container.sh`

#### Build Options

The project supports **cloud-native deployment patterns**:

1. **Runtime Configuration** (Recommended - Cloud-Native):
   ```shell
   # Build once (no environment variables needed)
   $ mvn clean package
   $ docker build -t obp-keycloak-provider .
   
   # Deploy anywhere with runtime config
   $ docker run -e DB_URL="jdbc:postgresql://host:5432/db" \
                 -e DB_USER="user" \
                 -e DB_PASSWORD="password" \
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

When you run `./sh/run-with-env.sh`, it starts the Keycloak container and follows the logs. When you press `Ctrl+C`, the script exits but **the container continues running in the background**.

**After pressing Ctrl+C:**
- The container remains accessible at http://localhost:8080 and https://localhost:8443
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

It uses port : 5432. 

The scripts in the container create a `keycloak` database. 
In the database create a table `users` :
```sql
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
	uniqueid varchar(32) NULL,
	createdat timestamp NULL,
	updatedat timestamp NULL,
	timezone varchar(32) NULL,
	superuser bool NULL,
	passwordshouldbechanged bool NULL,
	CONSTRAINT authuser_pk PRIMARY KEY (id)
);
```
Add mock user to the table.

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

# Run with runtime environment variables
$ ./sh/run-with-env.sh
```

### Legacy Approach

For compatibility, you can still use the legacy build script:
```shell
$ sh/run.sh
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
  DB_URL: "jdbc:postgresql://postgres:5432/obp_mapped"
  DB_USER: "obp"
  DB_PASSWORD: "secure_password"
```

### Docker Hub Deployment
```shell
# Pull generic image
docker pull your-org/obp-keycloak-provider:latest

# Run with environment-specific configuration
docker run -e DB_URL="jdbc:postgresql://prod-db:5432/obp" \
           -e DB_USER="prod_user" \
           -e DB_PASSWORD="secure_password" \
           your-org/obp-keycloak-provider:latest
```

### Testing Runtime Configuration
```shell
# Validate the cloud-native setup
$ ./sh/test-runtime-config.sh

# Compare with example configuration
$ ./sh/compare-env.sh
```

## Documentation

- **[Cloud-Native Guide](docs/CLOUD_NATIVE.md)** - Complete guide for Kubernetes and Docker Hub deployments
- **[Environment Configuration](docs/ENVIRONMENT.md)** - Environment variable reference
- **[Kubernetes Examples](k8s/)** - Production-ready Kubernetes manifests
- **[Docker Compose](docker-compose.runtime.yml)** - Runtime configuration example

