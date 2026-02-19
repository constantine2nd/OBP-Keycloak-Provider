#!/bin/bash

# CI/CD-Style OBP Keycloak Provider Deployment Script
# This script always builds, always replaces containers - designed for automated environments
#
# Requirements:
# - PostgreSQL running for Keycloak's internal database (KC_DB_URL)
# - OBP API instance reachable at OBP_API_URL
#
# Usage: ./development/run-local-postgres-cicd.sh [--themed]

set -e

# Signal handler for Ctrl+C
cleanup_and_exit() {
    echo ""
    echo -e "${YELLOW}=== Deployment Interrupted ===${NC}"
    echo -e "${GREEN}Container may still be running in background${NC}"
    echo "Check with: docker ps --filter name=obp-keycloak-local"
    exit 0
}

trap cleanup_and_exit SIGINT

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
DEPLOYMENT_TYPE="standard"
DOCKERFILE_PATH="development/docker/Dockerfile"
IMAGE_TAG="obp-keycloak-provider-local"
CONTAINER_NAME="obp-keycloak-local"
THEMED_BUILD_ARG=""

# Parse command line arguments
if [[ "$1" == "--themed" || "$1" == "-t" ]]; then
    DEPLOYMENT_TYPE="themed"
    IMAGE_TAG="obp-keycloak-provider-local-themed"
    # Use unified Dockerfile and instruct it to include themes via build-arg
    THEMED_BUILD_ARG="--build-arg THEMED=true"
fi

echo -e "${CYAN}================================================${NC}"
echo -e "${GREEN}  CI/CD OBP Keycloak Provider Deployment       ${NC}"
echo -e "${CYAN}================================================${NC}"
echo -e "${BLUE}Mode: Always Build & Replace${NC}"
echo -e "${BLUE}Deployment: $DEPLOYMENT_TYPE${NC}"
echo -e "${BLUE}$(date '+%Y-%m-%d %H:%M:%S')${NC}"
echo ""

# Step 1: Environment validation
echo -e "${CYAN}[1/8] Validating Environment${NC}"

# Check Docker
if ! command -v docker &> /dev/null; then
    echo -e "${RED}✗ Docker not found${NC}"
    exit 1
fi

if ! docker info &> /dev/null; then
    echo -e "${RED}✗ Docker not running${NC}"
    exit 1
fi

# Check Maven
if ! command -v mvn &> /dev/null; then
    echo -e "${RED}✗ Maven not found${NC}"
    exit 1
fi

# Load environment variables
if [ ! -f ".env" ]; then
    echo -e "${RED}✗ .env file not found${NC}"
    echo "Create .env with database configuration (see .env.docker.example)"
    exit 1
fi

source .env

# Set default values for Keycloak service connection
KEYCLOAK_HOST="${KEYCLOAK_HOST:-localhost}"

# Validate required vars
required_vars=("KC_DB_URL" "KC_DB_USERNAME" "KC_DB_PASSWORD" "OBP_API_URL" "OBP_API_USERNAME" "OBP_API_PASSWORD" "OBP_API_CONSUMER_KEY" "OBP_AUTHUSER_PROVIDER")
for var in "${required_vars[@]}"; do
    if [ -z "${!var}" ]; then
        echo -e "${RED}✗ Missing environment variable: $var${NC}"
        if [ "$var" = "OBP_AUTHUSER_PROVIDER" ]; then
            echo -e "${RED}CRITICAL: OBP_AUTHUSER_PROVIDER is MANDATORY for security${NC}"
            echo "Add to .env file: OBP_AUTHUSER_PROVIDER=your_provider_name"
        elif [ "$var" = "OBP_API_URL" ]; then
            echo "Add to .env file: OBP_API_URL=http://localhost:8080"
        elif [ "$var" = "OBP_API_USERNAME" ] || [ "$var" = "OBP_API_PASSWORD" ] || [ "$var" = "OBP_API_CONSUMER_KEY" ]; then
            echo "Add to .env file: $var=your_value"
        fi
        exit 1
    fi
done

# Validate themed deployment requirements
validate_theme_files() {
    echo -e "${CYAN}Validating themed deployment requirements...${NC}"

    # Using unified Dockerfile at $DOCKERFILE_PATH; no separate themed Dockerfile required

    # Check if theme directory exists
    if [ ! -d "themes/obp" ]; then
        echo -e "${RED}✗ Theme directory not found: themes/obp${NC}"
        echo "Themed deployment requires the obp theme directory"
        echo "Create it with: mkdir -p themes/obp/login"
        return 1
    fi

    # Check theme.properties
    if [ ! -f "themes/obp/theme.properties" ]; then
        echo -e "${RED}✗ Theme configuration not found: themes/obp/theme.properties${NC}"
        return 1
    fi

    # Validate theme.properties content
    echo -n "Validating theme.properties content... "
    if grep -q "parent=base" "themes/obp/theme.properties" &&
       grep -q "styles=" "themes/obp/theme.properties"; then
        echo -e "${GREEN}✓${NC}"
    else
        echo -e "${RED}✗ Invalid theme.properties${NC}"
        echo "theme.properties must contain 'parent=base' and 'styles=' entries"
        return 1
    fi

    # Check login theme directory
    if [ ! -d "themes/obp/login" ]; then
        echo -e "${RED}✗ Login theme directory not found: themes/obp/login${NC}"
        return 1
    fi

    # Check required login template files
    required_templates=("login.ftl" "template.ftl")
    missing_templates=()
    for template in "${required_templates[@]}"; do
        if [ ! -f "themes/obp/login/$template" ]; then
            missing_templates+=("$template")
        fi
    done

    if [ ${#missing_templates[@]} -ne 0 ]; then
        echo -e "${RED}✗ Missing login templates: ${missing_templates[*]}${NC}"
        echo "Required templates in themes/obp/login/:"
        for template in "${required_templates[@]}"; do
            echo "  - $template"
        done
        return 1
    fi

    # Check for resources directory
    echo -n "Checking theme resources... "
    if [ -d "themes/obp/login/resources" ]; then
        echo -e "${GREEN}✓ Resources directory found${NC}"

        # Check for CSS files
        if [ -d "themes/obp/login/resources/css" ]; then
            css_count=$(find "themes/obp/login/resources/css" -name "*.css" 2>/dev/null | wc -l)
            if [ "$css_count" -gt 0 ]; then
                echo "  Found $css_count CSS file(s)"
            fi
        fi

        # Check for image files
        if [ -d "themes/obp/login/resources/img" ]; then
            img_count=$(find "themes/obp/login/resources/img" -type f 2>/dev/null | wc -l)
            if [ "$img_count" -gt 0 ]; then
                echo "  Found $img_count image file(s)"
            fi
        fi
    else
        echo -e "${YELLOW}~ Resources directory optional${NC}"
    fi

    # Check messages directory for internationalization
    echo -n "Checking internationalization... "
    if [ -d "themes/obp/login/messages" ]; then
        msg_count=$(find "themes/obp/login/messages" -name "messages_*.properties" 2>/dev/null | wc -l)
        if [ "$msg_count" -gt 0 ]; then
            echo -e "${GREEN}✓ Found $msg_count message file(s)${NC}"
        else
            echo -e "${YELLOW}~ No message files found${NC}"
        fi
    else
        echo -e "${YELLOW}~ Messages directory optional${NC}"
    fi

    echo -e "${GREEN}✓ All themed deployment requirements validated${NC}"
    return 0
}

if [ "$DEPLOYMENT_TYPE" = "themed" ]; then
    if ! validate_theme_files; then
        echo ""
        echo -e "${RED}Theme validation failed. Cannot proceed with themed deployment.${NC}"
        echo ""
        echo -e "${BLUE}Quick fixes:${NC}"
        echo "1. Check if theme files exist: ls -la themes/obp/"
        echo "2. Verify theme structure: find themes/obp -type f"
        echo "3. Try standard deployment instead: ./development/run-local-postgres-cicd.sh"
        echo ""
        exit 1
    fi
fi

echo -e "${GREEN}✓ Environment validated (including mandatory security variables)${NC}"

# Step 2: Connectivity tests
echo -e "${CYAN}[2/8] Testing Connectivity${NC}"

# Extract host and port from a JDBC URL
parse_jdbc_url() {
    local url="$1"
    echo "$url" | sed -n 's|.*://\([^/;]*\).*|\1|p'
}

test_db_connection() {
    local label="$1"
    local jdbc_url="$2"
    local host_port
    host_port=$(parse_jdbc_url "$jdbc_url")
    local host="${host_port%%:*}"
    local port="${host_port##*:}"

    # Default port if not specified
    if [ "$host" = "$port" ]; then
        port=5432
    fi

    # host.docker.internal is a Docker-only alias; resolve to localhost for host-side checks
    local test_host="$host"
    if [ "$host" = "host.docker.internal" ]; then
        test_host="localhost"
    fi

    echo -n "  Testing $label ($host:$port)... "

    if command -v pg_isready &> /dev/null; then
        if pg_isready -h "$test_host" -p "$port" -t 5 > /dev/null 2>&1; then
            echo -e "${GREEN}✓ reachable${NC}"
            return 0
        fi
    elif command -v nc &> /dev/null; then
        if nc -z -w 5 "$test_host" "$port" 2>/dev/null; then
            echo -e "${GREEN}✓ reachable${NC}"
            return 0
        fi
    else
        if (echo > /dev/tcp/"$test_host"/"$port") 2>/dev/null; then
            echo -e "${GREEN}✓ reachable${NC}"
            return 0
        fi
    fi

    echo -e "${RED}✗ unreachable${NC}"
    return 1
}

test_obp_api() {
    local url="$1"
    echo -n "  Testing OBP API ($url)... "
    if command -v curl &> /dev/null; then
        if curl -s -o /dev/null -m 10 "$url"; then
            echo -e "${GREEN}✓ reachable${NC}"
            return 0
        fi
    fi
    echo -e "${RED}✗ unreachable${NC}"
    return 1
}

test_db_connection "Keycloak DB" "$KC_DB_URL" || {
    echo -e "${RED}✗ Keycloak DB is unreachable — cannot continue${NC}"
    echo "Ensure PostgreSQL is running and KC_DB_URL in .env is correct."
    exit 1
}

test_obp_api "$OBP_API_URL" || {
    echo -e "${YELLOW}⚠ OBP API unreachable at $OBP_API_URL — continuing anyway${NC}"
    echo "  Keycloak will start but logins will fail until OBP API is reachable."
}

echo -e "${GREEN}✓ Connectivity check done${NC}"


# Step 3: Clean build
echo -e "${CYAN}[3/8] Building Maven Project${NC}"

mvn clean package -DskipTests -q

if [ $? -ne 0 ]; then
    echo -e "${RED}✗ Maven build failed${NC}"
    exit 1
fi

# Generate build timestamp for cache invalidation
BUILD_TIMESTAMP=$(date +%s)
JAR_CHECKSUM=$(sha256sum target/obp-keycloak-provider.jar | cut -d' ' -f1)

echo -e "${GREEN}✓ Maven project built (checksum: ${JAR_CHECKSUM:0:8})${NC}"

# Step 4: Stop existing container
echo -e "${CYAN}[4/8] Stopping Existing Container${NC}"

if docker ps -q --filter "name=$CONTAINER_NAME" | grep -q .; then
    docker stop "$CONTAINER_NAME" > /dev/null 2>&1
    echo -e "${GREEN}✓ Container stopped${NC}"
else
    echo -e "${GREEN}✓ No existing container${NC}"
fi

# Step 5: Remove existing container
echo -e "${CYAN}[5/8] Removing Existing Container${NC}"

if docker ps -aq --filter "name=$CONTAINER_NAME" | grep -q .; then
    docker rm "$CONTAINER_NAME" > /dev/null 2>&1
    echo -e "${GREEN}✓ Container removed${NC}"
else
    echo -e "${GREEN}✓ No container to remove${NC}"
fi

# Step 6: Build Docker image
echo -e "${CYAN}[6/8] Building Docker Image${NC}"

# Display build context
echo "Building with:"
echo "  Dockerfile: $DOCKERFILE_PATH"
echo "  Image tag: $IMAGE_TAG"
echo "  Type: $DEPLOYMENT_TYPE"

# Force rebuild with cache invalidation; capture output for diagnostics
DOCKER_BUILD_LOG=$(mktemp)
docker build \
    --no-cache \
    --build-arg BUILD_TIMESTAMP="$BUILD_TIMESTAMP" \
    --build-arg JAR_CHECKSUM="$JAR_CHECKSUM" \
    $THEMED_BUILD_ARG \
    -t "$IMAGE_TAG" \
    -f "$DOCKERFILE_PATH" \
    . > "$DOCKER_BUILD_LOG" 2>&1

if [ $? -ne 0 ]; then
    echo -e "${RED}✗ Docker image build failed${NC}"
    echo ""
    echo -e "${YELLOW}--- Docker build output ---${NC}"
    cat "$DOCKER_BUILD_LOG"
    echo -e "${YELLOW}--- End of build output ---${NC}"
    rm -f "$DOCKER_BUILD_LOG"
    echo ""
    echo "Check the Dockerfile: $DOCKERFILE_PATH"
    if [ "$DEPLOYMENT_TYPE" = "themed" ]; then
        echo ""
        echo -e "${YELLOW}Themed deployment troubleshooting:${NC}"
        echo "• Ensure themes/obp/ directory exists with required files"
        echo "• Check theme.properties file: cat themes/obp/theme.properties"
        echo "• Verify login directory: ls -la themes/obp/login/"
        echo "• Build logs: Check Docker build output above"
        echo ""
        echo -e "${BLUE}Recovery suggestions:${NC}"
        echo "1. Verify theme files: ls -la themes/obp/"
        echo "2. Try standard deployment first: ./development/run-local-postgres-cicd.sh"
        echo "3. Check theme directory permissions"
    fi
    exit 1
fi

rm -f "$DOCKER_BUILD_LOG"
echo -e "${GREEN}✓ Docker image built${NC}"

# Step 7: Start new container
echo -e "${CYAN}[7/8] Starting New Container${NC}"

# Translate localhost/127.0.0.1 in OBP_API_URL to host.docker.internal so the
# provider inside the container can reach OBP running on the host.
# (Inside Docker, 127.0.0.1 resolves to the container itself, not the host.)
CONTAINER_OBP_API_URL="${OBP_API_URL//127.0.0.1/host.docker.internal}"
CONTAINER_OBP_API_URL="${CONTAINER_OBP_API_URL//localhost/host.docker.internal}"
if [ "$CONTAINER_OBP_API_URL" != "$OBP_API_URL" ]; then
    echo -e "${BLUE}  OBP_API_URL rewritten for container networking:${NC}"
    echo "    host: $OBP_API_URL"
    echo "    container: $CONTAINER_OBP_API_URL"
fi

# Container environment variables
CONTAINER_ENV_VARS=(
    "-e" "KEYCLOAK_ADMIN=${KEYCLOAK_ADMIN:-admin}"
    "-e" "KEYCLOAK_ADMIN_PASSWORD=${KEYCLOAK_ADMIN_PASSWORD:-admin}"
    "-e" "KC_DB=postgres"
    "-e" "KC_DB_URL=$KC_DB_URL"
    "-e" "KC_DB_USERNAME=$KC_DB_USERNAME"
    "-e" "KC_DB_PASSWORD=$KC_DB_PASSWORD"
    "-e" "OBP_API_URL=$CONTAINER_OBP_API_URL"
    "-e" "OBP_API_USERNAME=$OBP_API_USERNAME"
    "-e" "OBP_API_PASSWORD=$OBP_API_PASSWORD"
    "-e" "OBP_API_CONSUMER_KEY=$OBP_API_CONSUMER_KEY"
    "-e" "OBP_AUTHUSER_PROVIDER=$OBP_AUTHUSER_PROVIDER"
    "-e" "KC_HOSTNAME_STRICT=${KC_HOSTNAME_STRICT:-false}"
    "-e" "KC_HTTP_ENABLED=${KC_HTTP_ENABLED:-true}"
    "-e" "KC_HEALTH_ENABLED=${KC_HEALTH_ENABLED:-true}"
    "-e" "KC_METRICS_ENABLED=${KC_METRICS_ENABLED:-true}"
    "-e" "KC_FEATURES=${KC_FEATURES:-token-exchange}"
    "-e" "FORGOT_PASSWORD_URL=${FORGOT_PASSWORD_URL:-}"
)

# Start container
docker run -d \
    --name "$CONTAINER_NAME" \
    -p "${KEYCLOAK_HTTP_PORT:-7787}:8080" \
    -p "${KEYCLOAK_HTTPS_PORT:-8443}:8443" \
    -p "${KEYCLOAK_MGMT_PORT:-9000}:9000" \
    --add-host=host.docker.internal:host-gateway \
    "${CONTAINER_ENV_VARS[@]}" \
    "$IMAGE_TAG" > /dev/null 2>&1

if [ $? -ne 0 ]; then
    echo -e "${RED}✗ Container start failed${NC}"
    if [ "$DEPLOYMENT_TYPE" = "themed" ]; then
        echo ""
        echo -e "${YELLOW}Themed container startup troubleshooting:${NC}"
        echo "• Check theme files were copied correctly"
        echo "• Verify container image was built successfully"
        echo "• Check for theme-related errors in Docker output"
        echo ""
        echo -e "${BLUE}Debug commands:${NC}"
        echo "docker run --rm $IMAGE_TAG ls -la /opt/keycloak/themes/"
        echo "docker logs $CONTAINER_NAME"
    fi
    exit 1
fi

echo -e "${GREEN}✓ Container started${NC}"

# Step 8: Health check
echo -e "${CYAN}[8/8] Waiting for Service Readiness${NC}"

READY=false
WAIT_COUNT=0
MAX_WAIT=120

while [ $WAIT_COUNT -lt $MAX_WAIT ] && [ "$READY" = false ]; do
    if curl -sk -f -m 5 "https://$KEYCLOAK_HOST:${KEYCLOAK_MGMT_PORT:-9000}/health/ready" > /dev/null 2>&1; then
        READY=true
        echo -e "${GREEN}✓ Service is ready${NC}"

        # Additional themed deployment validation
        if [ "$DEPLOYMENT_TYPE" = "themed" ]; then
            echo -n "Testing theme accessibility... "
            # Check if theme resources are accessible
            if curl -s -f -m 10 "http://$KEYCLOAK_HOST:${KEYCLOAK_HTTP_PORT:-7787}/resources/obp/" > /dev/null 2>&1; then
                echo -e "${GREEN}✓ Theme resources accessible${NC}"
            else
                echo -e "${YELLOW}~ Theme resources may load after realm configuration${NC}"
            fi

            # Verify theme installation in container
            echo -n "Verifying theme installation... "
            if docker exec "$CONTAINER_NAME" ls /opt/keycloak/themes/obp/theme.properties > /dev/null 2>&1; then
                echo -e "${GREEN}✓ Theme files installed${NC}"
            else
                echo -e "${RED}✗ Theme files missing in container${NC}"
            fi
        fi
    else
        echo -n "."
        sleep 2
        WAIT_COUNT=$((WAIT_COUNT + 2))
    fi
done

if [ "$READY" = false ]; then
    echo ""
    echo -e "${RED}✗ Service failed to become ready within $MAX_WAIT seconds${NC}"
    echo "Check logs: docker logs $CONTAINER_NAME"

    if [ "$DEPLOYMENT_TYPE" = "themed" ]; then
        echo ""
        echo -e "${YELLOW}Themed deployment diagnostics:${NC}"
        echo "• Container logs: docker logs $CONTAINER_NAME | grep -i theme"
        echo "• Theme files: docker exec $CONTAINER_NAME ls -la /opt/keycloak/themes/obp/ 2>/dev/null || echo 'Theme files not accessible'"
        echo "• Service status: docker exec $CONTAINER_NAME ps aux 2>/dev/null || echo 'Container not responding'"
        echo ""
        echo -e "${BLUE}Recovery options:${NC}"
        echo "1. Wait longer: The container may still be starting up"
        echo "2. Check theme syntax: Validate theme.properties file"
        echo "3. Restart container: docker restart $CONTAINER_NAME"
        echo "4. Try standard deployment: ./development/run-local-postgres-cicd.sh"
    fi
    exit 1
fi

# Deployment summary
echo ""
echo -e "${CYAN}================================================${NC}"
echo -e "${GREEN}       Deployment Complete - Service Ready      ${NC}"
echo -e "${CYAN}================================================${NC}"
echo ""

echo "Build Information:"
echo "  Timestamp: $(date '+%Y-%m-%d %H:%M:%S')"
echo "  JAR Checksum: $JAR_CHECKSUM"
echo "  Container: $CONTAINER_NAME"
echo "  Image: $IMAGE_TAG"
echo "  Type: $DEPLOYMENT_TYPE"
echo "  OBP API: $OBP_API_URL"
echo "  Provider: $OBP_AUTHUSER_PROVIDER"
echo ""

echo "Service Access:"
echo "  HTTP:  http://$KEYCLOAK_HOST:${KEYCLOAK_HTTP_PORT:-7787}"
echo "  HTTPS: https://$KEYCLOAK_HOST:${KEYCLOAK_HTTPS_PORT:-8443}"
echo "  Admin: https://$KEYCLOAK_HOST:${KEYCLOAK_HTTPS_PORT:-8443}/admin"
echo "         (${KEYCLOAK_ADMIN:-admin} / ${KEYCLOAK_ADMIN_PASSWORD:-admin})"
echo ""

if [ "$DEPLOYMENT_TYPE" = "themed" ]; then
    echo -e "${BLUE}Theme Configuration:${NC}"
    echo "  Custom Theme: obp"
    echo "  Styling: Dark theme with modern UI"
    echo "  Branding: Open Bank Project"
    echo "  Theme Location: /opt/keycloak/themes/obp/"
    echo ""
    echo -e "${BLUE}Theme Activation Instructions:${NC}"
    echo "  1. Access Admin Console: https://$KEYCLOAK_HOST:${KEYCLOAK_HTTPS_PORT:-8443}/admin"
    echo "  2. Login with admin credentials (${KEYCLOAK_ADMIN:-admin})"
    echo "  3. Go to: Realm Settings > Themes"
    echo "  4. Set Login Theme: obp"
    echo "  5. Click Save to apply changes"
    echo ""
    echo -e "${BLUE}Theme Verification Commands:${NC}"
    echo "  List themes:     docker exec $CONTAINER_NAME ls -la /opt/keycloak/themes/"
    echo "  Check obp theme: docker exec $CONTAINER_NAME ls -la /opt/keycloak/themes/obp/"
    echo "  Theme config:    docker exec $CONTAINER_NAME cat /opt/keycloak/themes/obp/theme.properties"
    echo ""
    echo -e "${BLUE}Theme Resources:${NC}"
    echo "  URL: http://$KEYCLOAK_HOST:${KEYCLOAK_HTTP_PORT:-7787}/resources/obp/"
    echo "  Note: Theme resources load after realm configuration"
    echo ""
fi

echo "Management:"
echo "  Logs:    docker logs -f $CONTAINER_NAME"
echo "  Stop:    docker stop $CONTAINER_NAME"
echo "  Restart: docker restart $CONTAINER_NAME"
echo "  Remove:  docker rm $CONTAINER_NAME"
echo ""

echo "Application Monitoring:"
echo "  docker logs $CONTAINER_NAME -f"
echo ""

echo -e "${GREEN}Deployment pipeline completed successfully!${NC}"

if [ "$DEPLOYMENT_TYPE" = "themed" ]; then
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════${NC}"
    echo -e "${BLUE}Custom themes are available - activate 'obp' theme in Admin Console.${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════${NC}"
fi
