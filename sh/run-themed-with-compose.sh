#!/bin/bash

# Script to run OBP Keycloak Provider with themed deployment using Docker Compose
# This script properly handles the separated database architecture with custom themes
#
# Usage: ./sh/run-themed-with-compose.sh [OPTIONS]
#
# RECENT FIXES INCLUDED:
# - Uses docker-compose for separated database architecture
# - Proper environment variable loading
# - Enhanced validation and error handling
# - Support for themed deployment with custom UI

set -e

# Signal handler for Ctrl+C
cleanup_and_exit() {
    echo ""
    echo ""
    echo -e "${YELLOW}=== Script Interrupted ===${NC}"
    echo -e "${GREEN}The Docker Compose services are still running in the background.${NC}"
    echo ""
    echo "Service status:"
    docker-compose -f docker-compose.runtime.yml ps 2>/dev/null || echo "  Services may not be running"
    echo ""
    echo "To manage services:"
    echo "  View logs:         docker-compose -f docker-compose.runtime.yml logs -f"
    echo "  Stop services:     docker-compose -f docker-compose.runtime.yml stop"
    echo "  Stop and remove:   docker-compose -f docker-compose.runtime.yml down"
    echo "  Full cleanup:      docker-compose -f docker-compose.runtime.yml down -v"
    echo ""
    echo "Access URLs (if services are running):"
    echo "  HTTP:  http://localhost:8000"
    echo "  HTTPS: https://localhost:8443"
    echo "  Admin Console: https://localhost:8443/admin"
    echo ""
    echo "Database connections:"
    echo "  Keycloak DB:      localhost:5433"
    echo "  User Storage DB:  localhost:5434"
    echo ""
    exit 0
}

# Function to display usage
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --build, -b     Force rebuild of Docker images"
    echo "  --clean, -c     Clean start (remove volumes and rebuild)"
    echo "  --validate, -v  Validate configuration before starting"
    echo "  --help, -h      Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0              # Start with existing images"
    echo "  $0 --build      # Rebuild images and start"
    echo "  $0 --clean      # Clean start with fresh databases"
    echo "  $0 --validate   # Validate configuration first"
    echo ""
    echo "This script uses Docker Compose with separated database architecture:"
    echo "  - Keycloak Internal Database (port 5433)"
    echo "  - User Storage Database (port 5434)"
    echo "  - Custom OBP Theme support"
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
FORCE_BUILD=false
CLEAN_START=false
VALIDATE_FIRST=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --build|-b)
            FORCE_BUILD=true
            shift
            ;;
        --clean|-c)
            CLEAN_START=true
            FORCE_BUILD=true
            shift
            ;;
        --validate|-v)
            VALIDATE_FIRST=true
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

echo -e "${CYAN}===============================================${NC}"
echo -e "${GREEN}  OBP Keycloak Provider - Themed Deployment  ${NC}"
echo -e "${CYAN}===============================================${NC}"
echo -e "${BLUE}Architecture: Separated Databases + Custom Themes${NC}"
echo -e "${BLUE}Configuration: Cloud-Native Runtime Environment${NC}"
echo ""

# Check if required files exist
echo "Checking required files..."
required_files=("docker-compose.runtime.yml" "env.sample" "docker/Dockerfile")
missing_files=()

for file in "${required_files[@]}"; do
    if [ ! -f "$file" ]; then
        missing_files+=("$file")
    fi
done

if [ ${#missing_files[@]} -ne 0 ]; then
    echo -e "${RED}Error: Missing required files:${NC}"
    for file in "${missing_files[@]}"; do
        echo -e "${RED}  - $file${NC}"
    done
    exit 1
fi

echo -e "${GREEN}✓ Required files found${NC}"

# Check if .env file exists, create from template if not
if [ ! -f ".env" ]; then
    echo -e "${YELLOW}Warning: .env file not found.${NC}"
    echo "Creating .env file from env.sample..."

    if [ -f "env.sample" ]; then
        cp env.sample .env
        echo -e "${GREEN}✓ Created .env file from env.sample${NC}"
        echo ""
        echo -e "${YELLOW}IMPORTANT: Please review and edit .env file with your configuration!${NC}"
        echo "Key settings to review:"
        echo "  - KEYCLOAK_ADMIN_PASSWORD (change from default)"
        echo "  - KC_DB_PASSWORD (change from default)"
        echo "  - USER_STORAGE_DB_PASSWORD (change from default)"
        echo ""
        read -p "Press Enter after reviewing .env file to continue..."
    else
        echo -e "${RED}Error: env.sample file not found!${NC}"
        exit 1
    fi
fi

echo -e "${GREEN}✓ Environment file ready${NC}"

# Validate configuration if requested
if [ "$VALIDATE_FIRST" = true ]; then
    echo ""
    echo "Running configuration validation..."
    if [ -f "sh/validate-separated-db-config.sh" ]; then
        chmod +x sh/validate-separated-db-config.sh
        if ./sh/validate-separated-db-config.sh; then
            echo -e "${GREEN}✓ Configuration validation passed${NC}"
        else
            echo -e "${RED}✗ Configuration validation failed${NC}"
            echo "Please fix the configuration issues before proceeding."
            exit 1
        fi
    else
        echo -e "${YELLOW}Warning: Validation script not found, skipping validation${NC}"
    fi
    echo ""
fi

# Check for theme files
echo "Checking theme files..."
theme_files=(
    "themes/obp/theme.properties"
    "themes/obp/login/login.ftl"
    "themes/obp/login/resources/css/styles.css"
    "themes/obp/login/messages/messages_en.properties"
)

missing_theme_files=()
for file in "${theme_files[@]}"; do
    if [ ! -f "$file" ]; then
        missing_theme_files+=("$file")
    fi
done

if [ ${#missing_theme_files[@]} -ne 0 ]; then
    echo -e "${YELLOW}Warning: Some theme files are missing:${NC}"
    for file in "${missing_theme_files[@]}"; do
        echo -e "${YELLOW}  - $file${NC}"
    done
    echo ""
    echo -e "${BLUE}Theme files will be created with defaults during build.${NC}"
    echo -e "${BLUE}You can customize them later and rebuild.${NC}"
else
    echo -e "${GREEN}✓ Theme files found${NC}"
fi

# Check Docker and Docker Compose
echo ""
echo "Checking Docker environment..."

if ! command -v docker &> /dev/null; then
    echo -e "${RED}Error: Docker is not installed or not in PATH${NC}"
    exit 1
fi

if ! docker info &> /dev/null; then
    echo -e "${RED}Error: Docker is not running${NC}"
    exit 1
fi

if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null 2>&1; then
    echo -e "${RED}Error: Docker Compose is not available${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Docker environment ready${NC}"

# Display current configuration
echo ""
echo "Current Configuration:"
echo "  Deployment Type: Themed (with OBP custom theme)"
echo "  Compose File: docker-compose.runtime.yml"
echo "  Database Architecture: Separated (Keycloak + User Storage)"
echo "  Configuration: Runtime environment variables"
echo "  Force Build: $FORCE_BUILD"
echo "  Clean Start: $CLEAN_START"

# Load environment variables to display config (non-sensitive)
if [ -f ".env" ]; then
    source .env 2>/dev/null || true
    echo ""
    echo "Environment Configuration:"
    echo "  Keycloak Admin: ${KEYCLOAK_ADMIN:-admin}"
    echo "  Keycloak DB Port: ${KC_DB_PORT:-5433}"
    echo "  User Storage DB Port: ${USER_STORAGE_DB_PORT:-5434}"
    echo "  Keycloak HTTP Port: ${KEYCLOAK_HTTP_PORT:-8000}"
    echo "  Keycloak HTTPS Port: ${KEYCLOAK_HTTPS_PORT:-8443}"
    echo "  Hibernate DDL Mode: ${HIBERNATE_DDL_AUTO:-validate}"
fi

echo ""
echo "Theme Configuration:"
echo "  Custom Theme: obp"
echo "  Base Theme: keycloak"
echo "  Styling: Dark theme with modern UI"
echo "  Branding: Open Bank Project"
echo "  Internationalization: English (customizable)"
echo ""

# Clean start if requested
if [ "$CLEAN_START" = true ]; then
    echo -e "${YELLOW}Performing clean start (removing volumes and containers)...${NC}"
    docker-compose -f docker-compose.runtime.yml down -v 2>/dev/null || true
    docker system prune -f 2>/dev/null || true
    echo -e "${GREEN}✓ Clean start completed${NC}"
fi

# Build the Maven project
echo "Building Maven project..."
mvn clean package -DskipTests

if [ $? -ne 0 ]; then
    echo -e "${RED}Error: Maven build failed!${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Maven project built successfully${NC}"

# Build or pull Docker images
if [ "$FORCE_BUILD" = true ]; then
    echo ""
    echo "Building Docker images..."
    docker-compose -f docker-compose.runtime.yml build --no-cache

    if [ $? -ne 0 ]; then
        echo -e "${RED}Error: Docker image build failed!${NC}"
        exit 1
    fi

    echo -e "${GREEN}✓ Docker images built successfully${NC}"
else
    echo ""
    echo "Pulling/updating Docker images..."
    docker-compose -f docker-compose.runtime.yml pull 2>/dev/null || true
fi

# Stop any existing services
echo ""
echo "Stopping existing services..."
docker-compose -f docker-compose.runtime.yml down 2>/dev/null || true

# Start services
echo ""
echo -e "${GREEN}Starting OBP Keycloak with separated databases and custom themes...${NC}"
echo ""

# Start services in background first
docker-compose -f docker-compose.runtime.yml up -d

if [ $? -ne 0 ]; then
    echo -e "${RED}Error: Failed to start Docker Compose services!${NC}"
    echo ""
    echo "Troubleshooting steps:"
    echo "1. Check if ports are available: ss -tulpn | grep -E ':(5433|5434|8000|8443)'"
    echo "2. Validate configuration: ./sh/validate-separated-db-config.sh"
    echo "3. Check Docker logs: docker-compose -f docker-compose.runtime.yml logs"
    exit 1
fi

echo -e "${GREEN}✓ Services started successfully${NC}"
echo ""

# Wait a moment for services to initialize
echo "Waiting for services to initialize..."
sleep 5

# Check service status
echo ""
echo "Service Status:"
docker-compose -f docker-compose.runtime.yml ps

echo ""
echo -e "${CYAN}===============================================${NC}"
echo -e "${GREEN}     Deployment Complete - Services Running    ${NC}"
echo -e "${CYAN}===============================================${NC}"
echo ""

echo "Service Information:"
echo "  Deployment: OBP Keycloak Provider (Themed)"
echo "  Architecture: Separated Databases"
echo "  Configuration: Runtime Environment Variables"
echo ""

echo "Database Services:"
echo "  Keycloak Internal DB:  localhost:5433 (keycloak/keycloak_changeme)"
echo "  User Storage DB:       localhost:5434 (obp/changeme)"
echo ""

echo "Application Access:"
echo "  HTTP:          http://localhost:8000"
echo "  HTTPS:         https://localhost:8443"
echo "  Admin Console: https://localhost:8443/admin"
echo "  Admin User:    admin / admin"
echo ""

echo -e "${BLUE}Theme Activation Instructions:${NC}"
echo "1. Access Admin Console: https://localhost:8443/admin"
echo "2. Login with admin/admin"
echo "3. Go to: Realm Settings > Themes"
echo "4. Set Login Theme to: obp"
echo "5. Click Save"
echo ""

echo -e "${BLUE}Custom Theme Features:${NC}"
echo "  ✓ Modern dark theme with glassmorphism effects"
echo "  ✓ OBP branding and color scheme"
echo "  ✓ Responsive design for all devices"
echo "  ✓ Custom typography (Plus Jakarta Sans)"
echo "  ✓ Accessibility features"
echo "  ✓ Multi-language support"
echo ""

echo "Management Commands:"
echo "  View logs:         docker-compose -f docker-compose.runtime.yml logs -f"
echo "  Stop services:     docker-compose -f docker-compose.runtime.yml stop"
echo "  Restart services:  docker-compose -f docker-compose.runtime.yml restart"
echo "  Stop and remove:   docker-compose -f docker-compose.runtime.yml down"
echo "  Full cleanup:      docker-compose -f docker-compose.runtime.yml down -v"
echo ""

echo "Database Access:"
echo "  Keycloak DB:  psql -h localhost -p 5433 -U keycloak -d keycloak"
echo "  User Storage: psql -h localhost -p 5434 -U obp -d obp_mapped"
echo ""

echo "Troubleshooting:"
echo "  Validate config:   ./sh/validate-separated-db-config.sh"
echo "  Check container:   docker logs obp-keycloak"
echo "  Check databases:   docker logs keycloak-postgres && docker logs user-storage-postgres"
echo ""

# Check if services are healthy
echo "Checking service health..."
sleep 10

# Check container status
if docker ps | grep -q "obp-keycloak.*Up"; then
    echo -e "${GREEN}✓ Keycloak container is running${NC}"
else
    echo -e "${YELLOW}⚠ Keycloak container may still be starting${NC}"
fi

if docker ps | grep -q "keycloak-postgres.*Up.*healthy"; then
    echo -e "${GREEN}✓ Keycloak database is healthy${NC}"
else
    echo -e "${YELLOW}⚠ Keycloak database may still be initializing${NC}"
fi

if docker ps | grep -q "user-storage-postgres.*Up.*healthy"; then
    echo -e "${GREEN}✓ User storage database is healthy${NC}"
else
    echo -e "${YELLOW}⚠ User storage database may still be initializing${NC}"
fi

echo ""
echo -e "${GREEN}Setup complete! Following Keycloak logs...${NC}"
echo -e "${BLUE}Custom themes are loading... Once ready, activate 'obp' theme in Admin Console.${NC}"
echo -e "${YELLOW}Press Ctrl+C to exit log view (services will continue running)${NC}"
echo ""

# Follow Keycloak logs
docker-compose -f docker-compose.runtime.yml logs -f keycloak
