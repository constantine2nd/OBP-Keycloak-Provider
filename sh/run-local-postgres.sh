#!/bin/bash

# Script to run OBP Keycloak Provider with existing local PostgreSQL instances
# This script uses standalone Docker container connecting to local PostgreSQL databases
#
# Requirements:
# - PostgreSQL running locally on port 5432
# - Database 'keycloakdb' with user 'keycloak' (password: 'f')
# - Database 'obp_mapped' with user 'obp' (password: 'f')
#
# Usage: ./sh/run-local-postgres.sh [OPTIONS]

set -e

# Signal handler for Ctrl+C
cleanup_and_exit() {
    echo ""
    echo ""
    echo -e "${YELLOW}=== Script Interrupted ===${NC}"
    echo -e "${GREEN}The Keycloak container is still running in the background.${NC}"
    echo ""
    echo "Container status:"
    docker ps --filter "name=obp-keycloak-local" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || echo "  Container may not be running"
    echo ""
    echo "To manage the container:"
    echo "  View logs:    docker logs -f obp-keycloak-local"
    echo "  Stop:         docker stop obp-keycloak-local"
    echo "  Remove:       docker rm obp-keycloak-local"
    echo "  Stop & Remove: docker stop obp-keycloak-local && docker rm obp-keycloak-local"
    echo ""
    echo "Access URLs (if container is running):"
    echo "  HTTP:  http://localhost:8000"
    echo "  HTTPS: https://localhost:8443"
    echo "  Admin Console: https://localhost:8443/admin"
    echo ""
    echo "Database connections:"
    echo "  Keycloak DB:      psql -h localhost -p 5432 -U keycloak -d keycloakdb"
    echo "  User Storage DB:  psql -h localhost -p 5432 -U obp -d obp_mapped"
    echo ""
    exit 0
}

# Function to display usage
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --themed, -t    Build with custom themes support"
    echo "  --build, -b     Force rebuild of Docker image"
    echo "  --test, -x      Test database connections before starting"
    echo "  --validate, -v  Validate configuration and setup"
    echo "  --help, -h      Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0              # Standard deployment with local PostgreSQL"
    echo "  $0 --themed     # Themed deployment with custom UI"
    echo "  $0 --test       # Test database connections first"
    echo "  $0 --validate   # Validate complete setup"
    echo ""
    echo "This script uses existing local PostgreSQL instances:"
    echo "  - Keycloak DB: localhost:5432/keycloakdb (keycloak/f)"
    echo "  - User Storage: localhost:5432/obp_mapped (obp/f)"
    echo ""
}

# Trap Ctrl+C (SIGINT) and call cleanup function
trap cleanup_and_exit SIGINT

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Default options
DEPLOYMENT_TYPE="standard"
DOCKERFILE_PATH="docker/Dockerfile"
IMAGE_TAG="obp-keycloak-provider-local"
CONTAINER_NAME="obp-keycloak-local"
FORCE_BUILD=false
TEST_CONNECTIONS=false
VALIDATE_SETUP=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --themed|-t)
            DEPLOYMENT_TYPE="themed"
            DOCKERFILE_PATH=".github/Dockerfile_themed"
            IMAGE_TAG="obp-keycloak-provider-local-themed"
            shift
            ;;
        --build|-b)
            FORCE_BUILD=true
            shift
            ;;
        --test|-x)
            TEST_CONNECTIONS=true
            shift
            ;;
        --validate|-v)
            VALIDATE_SETUP=true
            shift
            ;;
        --help|-h)
            show_usage
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            show_usage
            exit 1
            ;;
    esac
done

echo -e "${CYAN}================================================${NC}"
echo -e "${GREEN}  OBP Keycloak Provider - Local PostgreSQL     ${NC}"
echo -e "${CYAN}================================================${NC}"
echo -e "${BLUE}Database: Existing Local PostgreSQL Instances${NC}"
echo -e "${BLUE}Deployment: $DEPLOYMENT_TYPE${NC}"
echo ""

# Check if .env.local file exists, create if not
if [ ! -f ".env.local" ]; then
    echo -e "${RED}Error: .env.local file not found!${NC}"
    echo ""
    echo "Please create .env.local file with your local PostgreSQL configuration."
    echo "Example content:"
    echo ""
    cat << 'EOF'
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
EOF
    echo ""
    echo "Run: cp .env.local.example .env.local # (if example exists)"
    echo "Or create the file manually with the above content."
    exit 1
fi

# Load environment variables from .env.local
echo "Loading environment variables from .env.local..."
source .env.local

echo -e "${GREEN}✓ Environment variables loaded${NC}"

# Validate required environment variables
echo ""
echo "Validating environment variables..."
required_vars=("KC_DB_URL" "KC_DB_USERNAME" "KC_DB_PASSWORD" "DB_URL" "DB_USER" "DB_PASSWORD")
missing_vars=()

for var in "${required_vars[@]}"; do
    if [ -z "${!var}" ]; then
        missing_vars+=("$var")
    fi
done

if [ ${#missing_vars[@]} -ne 0 ]; then
    echo -e "${RED}Error: Missing required environment variables:${NC}"
    for var in "${missing_vars[@]}"; do
        echo -e "${RED}  - $var${NC}"
    done
    echo -e "${YELLOW}Please set these variables in your .env.local file.${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Environment variables validated${NC}"

# Test database connections if requested
if [ "$TEST_CONNECTIONS" = true ] || [ "$VALIDATE_SETUP" = true ]; then
    echo ""
    echo "Testing database connections..."

    # Test Keycloak database
    echo -n "Testing Keycloak database connection... "
    if PGPASSWORD="$KC_DB_PASSWORD" psql -h localhost -p 5432 -U "$KC_DB_USERNAME" -d keycloakdb -c "SELECT 1;" > /dev/null 2>&1; then
        echo -e "${GREEN}✓ Connected${NC}"
    else
        echo -e "${RED}✗ Failed${NC}"
        echo -e "${RED}Error: Cannot connect to Keycloak database${NC}"
        echo "Connection details: postgresql://localhost:5432/keycloakdb (user: $KC_DB_USERNAME)"
        echo "Please ensure:"
        echo "1. PostgreSQL is running: sudo systemctl status postgresql"
        echo "2. Database exists: psql -h localhost -p 5432 -U $KC_DB_USERNAME -d keycloakdb"
        echo "3. Password is correct: $KC_DB_PASSWORD"
        exit 1
    fi

    # Test User Storage database
    echo -n "Testing User Storage database connection... "
    if PGPASSWORD="$DB_PASSWORD" psql -h localhost -p 5432 -U "$DB_USER" -d obp_mapped -c "SELECT 1;" > /dev/null 2>&1; then
        echo -e "${GREEN}✓ Connected${NC}"
    else
        echo -e "${RED}✗ Failed${NC}"
        echo -e "${RED}Error: Cannot connect to User Storage database${NC}"
        echo "Connection details: postgresql://localhost:5432/obp_mapped (user: $DB_USER)"
        echo "Please ensure:"
        echo "1. Database exists: psql -h localhost -p 5432 -U $DB_USER -d obp_mapped"
        echo "2. Password is correct: $DB_PASSWORD"
        exit 1
    fi

    # Check if authuser table exists
    echo -n "Checking authuser table... "
    if PGPASSWORD="$DB_PASSWORD" psql -h localhost -p 5432 -U "$DB_USER" -d obp_mapped -c "\d authuser" > /dev/null 2>&1; then
        echo -e "${GREEN}✓ Table exists${NC}"

        # Check table structure
        echo -n "Validating authuser table structure... "
        required_columns=("id" "username" "password_pw" "email" "firstname" "lastname")
        missing_columns=()

        for column in "${required_columns[@]}"; do
            if ! PGPASSWORD="$DB_PASSWORD" psql -h localhost -p 5432 -U "$DB_USER" -d obp_mapped -c "\d authuser" 2>/dev/null | grep -q "$column"; then
                missing_columns+=("$column")
            fi
        done

        if [ ${#missing_columns[@]} -eq 0 ]; then
            echo -e "${GREEN}✓ Valid structure${NC}"
        else
            echo -e "${YELLOW}⚠ Missing columns: ${missing_columns[*]}${NC}"
            echo "The table may need to be created or updated."
        fi
    else
        echo -e "${YELLOW}⚠ Table does not exist${NC}"
        echo ""
        echo -e "${BLUE}Creating authuser table...${NC}"

        # Create the table
        PGPASSWORD="$DB_PASSWORD" psql -h localhost -p 5432 -U "$DB_USER" -d obp_mapped << 'EOF'
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
    uniqueid varchar(32) NULL,
    createdat timestamp NULL,
    updatedat timestamp NULL,
    timezone varchar(32) NULL,
    superuser bool NULL,
    passwordshouldbechanged bool NULL,
    CONSTRAINT authuser_pk PRIMARY KEY (id)
);

-- Create indexes
CREATE INDEX IF NOT EXISTS authuser_uniqueid ON public.authuser USING btree (uniqueid);
CREATE INDEX IF NOT EXISTS authuser_user_c ON public.authuser USING btree (user_c);
CREATE UNIQUE INDEX IF NOT EXISTS authuser_username_provider ON public.authuser USING btree (username, provider);

-- Insert sample user
INSERT INTO public.authuser (firstname,lastname,email,username,password_pw,password_slt,provider,locale,validated,user_c,uniqueid,createdat,updatedat,timezone,superuser,passwordshouldbechanged)
VALUES ('Test','User','test@tesobe.com','testuser','b;$2a$10$SGIAR0RtthMlgJK9DhElBekIvo5ulZ26GBZJQ','nXiDOLye3CtjzEke','http://127.0.0.1:8000','en_US',true,1,'TEST_USER_UNIQUE_ID_123','2023-06-06 05:28:25.959','2023-06-06 05:28:25.967','UTC',false,NULL)
ON CONFLICT (username, provider) DO NOTHING;
EOF

        if [ $? -eq 0 ]; then
            echo -e "${GREEN}✓ Table created successfully${NC}"
        else
            echo -e "${RED}✗ Failed to create table${NC}"
            exit 1
        fi
    fi
fi

# Display current configuration
echo ""
echo "Current Configuration:"
echo "  Deployment Type: $DEPLOYMENT_TYPE"
echo "  Container Name: $CONTAINER_NAME"
echo "  Image Tag: $IMAGE_TAG"
echo "  Dockerfile: $DOCKERFILE_PATH"
echo "  Force Build: $FORCE_BUILD"
echo ""
echo "Database Configuration:"
echo "  Keycloak DB: $KC_DB_URL (user: $KC_DB_USERNAME)"
echo "  User Storage: $DB_URL (user: $DB_USER)"
echo "  Hibernate DDL: ${HIBERNATE_DDL_AUTO:-validate}"
echo ""

if [ "$DEPLOYMENT_TYPE" = "themed" ]; then
    echo "Theme Configuration:"
    echo "  Custom Theme: obp"
    echo "  Styling: Dark theme with modern UI"
    echo "  Branding: Open Bank Project"
    echo ""
fi

# Check if Docker is running
echo "Checking Docker environment..."
if ! command -v docker &> /dev/null; then
    echo -e "${RED}Error: Docker is not installed or not in PATH${NC}"
    exit 1
fi

if ! docker info &> /dev/null; then
    echo -e "${RED}Error: Docker is not running${NC}"
    echo "Please start Docker: sudo systemctl start docker"
    exit 1
fi

echo -e "${GREEN}✓ Docker environment ready${NC}"

# Build the Maven project
echo ""
echo "Building Maven project..."
mvn clean package -DskipTests

if [ $? -ne 0 ]; then
    echo -e "${RED}Error: Maven build failed!${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Maven project built successfully${NC}"

# Build or check Docker image
if [ "$FORCE_BUILD" = true ] || ! docker images | grep -q "$IMAGE_TAG"; then
    echo ""
    echo "Building Docker image..."
    docker build -t "$IMAGE_TAG" -f "$DOCKERFILE_PATH" .

    if [ $? -ne 0 ]; then
        echo -e "${RED}Error: Docker image build failed!${NC}"
        exit 1
    fi

    echo -e "${GREEN}✓ Docker image built successfully${NC}"
else
    echo -e "${GREEN}✓ Docker image already exists${NC}"
fi

# Stop and remove existing container
echo ""
echo "Stopping existing container..."
docker stop "$CONTAINER_NAME" 2>/dev/null || true
docker rm "$CONTAINER_NAME" 2>/dev/null || true

# Prepare environment variables for container
# Note: We use host.docker.internal to access localhost from container
CONTAINER_ENV_VARS=(
    "-e" "KEYCLOAK_ADMIN=${KEYCLOAK_ADMIN:-admin}"
    "-e" "KEYCLOAK_ADMIN_PASSWORD=${KEYCLOAK_ADMIN_PASSWORD:-admin}"
    "-e" "KC_DB=postgres"
    "-e" "KC_DB_URL=jdbc:postgresql://host.docker.internal:5432/keycloakdb"
    "-e" "KC_DB_USERNAME=$KC_DB_USERNAME"
    "-e" "KC_DB_PASSWORD=$KC_DB_PASSWORD"
    "-e" "DB_URL=jdbc:postgresql://host.docker.internal:5432/obp_mapped"
    "-e" "DB_USER=$DB_USER"
    "-e" "DB_PASSWORD=$DB_PASSWORD"
    "-e" "DB_DRIVER=${DB_DRIVER:-org.postgresql.Driver}"
    "-e" "DB_DIALECT=${DB_DIALECT:-org.hibernate.dialect.PostgreSQLDialect}"
    "-e" "HIBERNATE_DDL_AUTO=${HIBERNATE_DDL_AUTO:-validate}"
    "-e" "HIBERNATE_SHOW_SQL=${HIBERNATE_SHOW_SQL:-true}"
    "-e" "HIBERNATE_FORMAT_SQL=${HIBERNATE_FORMAT_SQL:-true}"
    "-e" "KC_HOSTNAME_STRICT=${KC_HOSTNAME_STRICT:-false}"
    "-e" "KC_HTTP_ENABLED=${KC_HTTP_ENABLED:-true}"
    "-e" "KC_HEALTH_ENABLED=${KC_HEALTH_ENABLED:-true}"
    "-e" "KC_METRICS_ENABLED=${KC_METRICS_ENABLED:-true}"
    "-e" "KC_FEATURES=${KC_FEATURES:-token-exchange}"
)

# Add host networking for easier database access
NETWORK_ARGS="--add-host=host.docker.internal:host-gateway"

# Start container
echo ""
echo "Starting Keycloak container with local PostgreSQL..."
docker run -d \
    --name "$CONTAINER_NAME" \
    -p "${KEYCLOAK_HTTP_PORT:-8000}:8080" \
    -p "${KEYCLOAK_HTTPS_PORT:-8443}:8443" \
    $NETWORK_ARGS \
    "${CONTAINER_ENV_VARS[@]}" \
    "$IMAGE_TAG"

if [ $? -ne 0 ]; then
    echo -e "${RED}Error: Failed to start Docker container!${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Keycloak container started successfully${NC}"
echo ""

# Wait for container to initialize and be ready
echo "Waiting for container to initialize..."
sleep 10

# Check container status
if ! docker ps --filter "name=$CONTAINER_NAME" --format "{{.Status}}" | grep -q "^Up"; then
    echo -e "${RED}✗ Container failed to start${NC}"
    echo ""
    echo "Container logs:"
    docker logs "$CONTAINER_NAME" --tail 30
    exit 1
fi

echo -e "${GREEN}✓ Container is running${NC}"

# Wait for Keycloak to be ready
echo "Waiting for Keycloak to be ready..."
KEYCLOAK_READY=false
MAX_WAIT=120  # 2 minutes
WAIT_COUNT=0

while [ $WAIT_COUNT -lt $MAX_WAIT ] && [ "$KEYCLOAK_READY" = false ]; do
    # Check if admin console is accessible (which means Keycloak is ready)
    if curl -s -f -m 5 "http://localhost:${KEYCLOAK_HTTP_PORT:-8000}/admin/" > /dev/null 2>&1; then
        KEYCLOAK_READY=true
        echo -e "${GREEN}✓ Keycloak is ready and responding${NC}"
    else
        echo -n "."
        sleep 2
        WAIT_COUNT=$((WAIT_COUNT + 2))
    fi
done

if [ "$KEYCLOAK_READY" = false ]; then
    echo ""
    echo -e "${RED}✗ Keycloak failed to become ready within $MAX_WAIT seconds${NC}"
    echo ""
    echo "Container logs:"
    docker logs "$CONTAINER_NAME" --tail 50
    echo ""
    echo "Container is still running. You can check logs with: docker logs -f $CONTAINER_NAME"
    exit 1
fi

echo ""
echo -e "${CYAN}================================================${NC}"
echo -e "${GREEN}     Deployment Complete - Service Running      ${NC}"
echo -e "${CYAN}================================================${NC}"
echo ""

echo "Service Information:"
echo "  Container: $CONTAINER_NAME"
echo "  Image: $IMAGE_TAG"
echo "  Deployment: $DEPLOYMENT_TYPE"
echo "  Configuration: Local PostgreSQL"
echo ""

echo "Database Connections:"
echo "  Keycloak DB:      localhost:5432/keycloakdb (keycloak/f)"
echo "  User Storage DB:  localhost:5432/obp_mapped (obp/f)"
echo ""

echo "Application Access:"
echo "  HTTP:          http://localhost:${KEYCLOAK_HTTP_PORT:-8000}"
echo "  HTTPS:         https://localhost:${KEYCLOAK_HTTPS_PORT:-8443}"
echo "  Admin Console: https://localhost:${KEYCLOAK_HTTPS_PORT:-8443}/admin"
echo "  Admin User:    ${KEYCLOAK_ADMIN:-admin} / ${KEYCLOAK_ADMIN_PASSWORD:-admin}"
echo ""

if [ "$DEPLOYMENT_TYPE" = "themed" ]; then
    echo -e "${BLUE}Theme Activation Instructions:${NC}"
    echo "1. Access Admin Console: https://localhost:${KEYCLOAK_HTTPS_PORT:-8443}/admin"
    echo "2. Login with admin credentials"
    echo "3. Go to: Realm Settings > Themes"
    echo "4. Set Login Theme to: obp"
    echo "5. Click Save"
    echo ""
fi

echo "Management Commands:"
echo "  View logs:    docker logs -f $CONTAINER_NAME"
echo "  Stop:         docker stop $CONTAINER_NAME"
echo "  Restart:      docker restart $CONTAINER_NAME"
echo "  Remove:       docker rm $CONTAINER_NAME"
echo ""

echo "Database Access:"
echo "  Keycloak:     PGPASSWORD=f psql -h localhost -p 5432 -U keycloak -d keycloakdb"
echo "  User Storage: PGPASSWORD=f psql -h localhost -p 5432 -U obp -d obp_mapped"
echo ""

echo "Testing Commands:"
echo "  Service check: curl -f http://localhost:${KEYCLOAK_HTTP_PORT:-8000}/admin/"
echo "  Admin access: curl -k https://localhost:${KEYCLOAK_HTTPS_PORT:-8443}/admin"
echo ""

# Validate setup if requested
if [[ "$*" == *"--validate"* ]]; then
    echo -e "${BLUE}Running validation checks...${NC}"
    echo ""

    # Test admin console accessibility
    echo -n "Testing admin console accessibility... "
    if curl -s -f -m 10 "http://localhost:${KEYCLOAK_HTTP_PORT:-8000}/admin/" > /dev/null 2>&1; then
        echo -e "${GREEN}✓${NC}"
    else
        echo -e "${RED}✗${NC}"
    fi

    # Test HTTPS admin console
    echo -n "Testing HTTPS admin console... "
    if curl -k -s -f -m 10 "https://localhost:${KEYCLOAK_HTTPS_PORT:-8443}/admin/" > /dev/null 2>&1; then
        echo -e "${GREEN}✓${NC}"
    else
        echo -e "${RED}✗${NC}"
    fi

    # Test database connections (if container is running)
    echo -n "Testing container database connectivity... "
    if docker exec "$CONTAINER_NAME" timeout 10 bash -c "curl -s http://localhost:8080/admin/" > /dev/null 2>&1; then
        echo -e "${GREEN}✓${NC}"
    else
        echo -e "${RED}✗${NC}"
    fi

    if [ "$DEPLOYMENT_TYPE" = "themed" ]; then
        echo -n "Testing theme accessibility... "
        # Check if theme resources are accessible
        if curl -s -f -m 10 "http://localhost:${KEYCLOAK_HTTP_PORT:-8000}/resources/obp/" > /dev/null 2>&1; then
            echo -e "${GREEN}✓${NC}"
        else
            echo -e "${YELLOW}~ (Theme resources may load after realm configuration)${NC}"
        fi
    fi

    echo ""
fi

# Check container health
echo "Checking container health..."
sleep 10

# Test HTTP endpoint
if curl -f "http://localhost:${KEYCLOAK_HTTP_PORT:-8000}/health/ready" >/dev/null 2>&1; then
    echo -e "${GREEN}✓ Keycloak health check passed${NC}"
else
    echo -e "${YELLOW}⚠ Keycloak may still be starting up${NC}"
fi

echo ""
echo -e "${GREEN}Setup complete! Keycloak is running with local PostgreSQL databases.${NC}"
if [ "$DEPLOYMENT_TYPE" = "themed" ]; then
    echo -e "${BLUE}Custom themes are available - activate 'obp' theme in Admin Console.${NC}"
fi
echo -e "${YELLOW}Following container logs (Press Ctrl+C to exit and return to shell)...${NC}"
echo -e "${RED}Note: The container will continue running in the background after Ctrl+C${NC}"
echo ""

# Follow container logs
docker logs -f "$CONTAINER_NAME"
