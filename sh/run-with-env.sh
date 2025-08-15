#!/bin/bash

# Script to run Keycloak with environment variables
# This script loads environment variables from .env file and runs the application

set -e

# Signal handler for Ctrl+C
cleanup_and_exit() {
    echo ""
    echo ""
    echo -e "${YELLOW}=== Script Interrupted ===${NC}"
    echo -e "${GREEN}The Keycloak container is still running in the background.${NC}"
    echo ""
    echo "Container status:"
    docker ps --filter "name=obp-keycloak" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || echo "  Container may not be running"
    echo ""
    echo "To manage the container:"
    echo "  View logs:    docker logs -f obp-keycloak"
    echo "  Stop:         docker stop obp-keycloak"
    echo "  Remove:       docker rm obp-keycloak"
    echo "  Stop & Remove: docker stop obp-keycloak && docker rm obp-keycloak"
    echo "  Manage:       ./sh/manage-container.sh"
    echo ""
    echo "Access URLs (if container is running):"
    echo "  HTTP:  http://localhost:8080"
    echo "  HTTPS: https://localhost:8443"
    echo ""
    exit 0
}

# Trap Ctrl+C (SIGINT) and call cleanup function
trap cleanup_and_exit SIGINT

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}OBP Keycloak Provider - Development Setup${NC}"
echo "============================================"

# Check if .env file exists
if [ ! -f ".env" ]; then
    echo -e "${YELLOW}Warning: .env file not found.${NC}"
    echo "Creating .env file from .env.example..."

    if [ -f ".env.example" ]; then
        cp .env.example .env
        echo -e "${GREEN}✓ Created .env file from .env.example${NC}"
        echo -e "${YELLOW}Please edit .env file with your database configuration before continuing.${NC}"
        read -p "Press Enter to continue after editing .env file..."
    else
        echo -e "${RED}Error: .env.example file not found!${NC}"
        exit 1
    fi
fi

# Load environment variables from .env file
echo "Loading environment variables from .env file..."
export $(grep -v '^#' .env | xargs)

# Validate required environment variables
echo "Validating environment variables..."
required_vars=("DB_URL" "DB_USER" "DB_PASSWORD")
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
    echo -e "${YELLOW}Please set these variables in your .env file.${NC}"
    exit 1
fi

echo -e "${GREEN}Environment variables validated${NC}"

# Display current configuration (without password)
echo ""
echo "Current Configuration:"
echo "  Database URL: $DB_URL"
echo "  Database User: $DB_USER"
echo "  Database Password: [HIDDEN]"
echo "  Hibernate DDL Auto: ${HIBERNATE_DDL_AUTO:-validate}"
echo ""

# Build the project with environment variables
echo "Building the project with environment variables..."
mvn clean package -DskipTests \
    -Denv.DB_URL="$DB_URL" \
    -Denv.DB_USER="$DB_USER" \
    -Denv.DB_PASSWORD="$DB_PASSWORD" \
    -Denv.DB_DRIVER="${DB_DRIVER:-org.postgresql.Driver}" \
    -Denv.DB_DIALECT="${DB_DIALECT:-org.hibernate.dialect.PostgreSQLDialect}" \
    -Denv.HIBERNATE_DDL_AUTO="${HIBERNATE_DDL_AUTO:-validate}" \
    -Denv.HIBERNATE_SHOW_SQL="${HIBERNATE_SHOW_SQL:-true}" \
    -Denv.HIBERNATE_FORMAT_SQL="${HIBERNATE_FORMAT_SQL:-true}"

if [ $? -ne 0 ]; then
    echo -e "${RED}Error: Maven build failed!${NC}"
    exit 1
fi

echo -e "${GREEN}Project built successfully${NC}"

# Build Docker image
echo "Building Docker image..."
docker build -t obp-keycloak-provider -f docker/Dockerfile .

if [ $? -ne 0 ]; then
    echo -e "${RED}Error: Docker build failed!${NC}"
    exit 1
fi

echo -e "${GREEN}Docker image built successfully${NC}"

# Stop existing container if running
echo "Stopping existing containers..."
docker stop obp-keycloak 2>/dev/null || true
docker rm obp-keycloak 2>/dev/null || true

# Run the container with environment variables
echo "Starting Keycloak container with environment variables..."
docker run -d \
    --name obp-keycloak \
    -p 8080:8080 \
    -p 8443:8443 \
    -e KEYCLOAK_ADMIN=admin \
    -e KEYCLOAK_ADMIN_PASSWORD=admin \
    -e DB_URL="$DB_URL" \
    -e DB_USER="$DB_USER" \
    -e DB_PASSWORD="$DB_PASSWORD" \
    -e DB_DRIVER="${DB_DRIVER:-org.postgresql.Driver}" \
    -e DB_DIALECT="${DB_DIALECT:-org.hibernate.dialect.PostgreSQLDialect}" \
    -e HIBERNATE_DDL_AUTO="${HIBERNATE_DDL_AUTO:-validate}" \
    -e HIBERNATE_SHOW_SQL="${HIBERNATE_SHOW_SQL:-true}" \
    -e HIBERNATE_FORMAT_SQL="${HIBERNATE_FORMAT_SQL:-true}" \
    obp-keycloak-provider

if [ $? -ne 0 ]; then
    echo -e "${RED}Error: Failed to start Docker container!${NC}"
    exit 1
fi

echo -e "${GREEN}Keycloak container started successfully${NC}"
echo ""
echo "Container Information:"
echo "  Container Name: obp-keycloak"
echo "  HTTP Port: 8080"
echo "  HTTPS Port: 8443"
echo "  Admin Username: admin"
echo "  Admin Password: admin"
echo ""
echo "Access URLs:"
echo "  HTTP:  http://localhost:8080"
echo "  HTTPS: https://localhost:8443"
echo ""
echo "Useful Commands:"
echo "  View logs:    docker logs -f obp-keycloak"
echo "  Stop:         docker stop obp-keycloak"
echo "  Remove:       docker rm obp-keycloak"
echo "  Manage:       ./sh/manage-container.sh"
echo ""

# Follow container logs continuously
echo ""
echo -e "${GREEN}Setup complete! Keycloak is starting up...${NC}"
echo -e "${YELLOW}Following container logs (Press Ctrl+C to exit and return to shell)...${NC}"
echo -e "${RED}Note: The container will continue running in the background after Ctrl+C${NC}"
echo ""

# Follow logs continuously
docker logs -f obp-keycloak
